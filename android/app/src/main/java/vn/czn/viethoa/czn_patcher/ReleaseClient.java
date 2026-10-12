package vn.czn.viethoa.czn_patcher;
import android.content.Context;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class ReleaseClient {
    public static final String DEFAULT_CHANNEL="https://github.com/doubleD1302/CZN-VH/releases/latest/download/channel.json";
    public static java.net.HttpURLConnection open(String url)throws Exception{for(int i=0;i<6;i++){URL u=new URL(url);if(!u.getProtocol().equals("https")||u.getUserInfo()!=null)throw new IOException("Kênh cập nhật phải dùng HTTPS.");HttpURLConnection c=(HttpURLConnection)u.openConnection();c.setConnectTimeout(10000);c.setReadTimeout(30000);c.setInstanceFollowRedirects(false);c.setRequestProperty("User-Agent","CZN-VietHoa-Android/1.4.1");int code=c.getResponseCode();if(code>=300&&code<400){String next=c.getHeaderField("Location");c.disconnect();if(next==null)throw new IOException("Link chuyển hướng không hợp lệ.");url=new URL(u,next).toString();continue;}if(code!=200){c.disconnect();throw new IOException("Máy chủ trả mã "+code+". Bạn vẫn có thể cài bản đi kèm.");}return c;}throw new IOException("Quá nhiều chuyển hướng.");}
    public static JSONObject verify(String envelope)throws Exception{return PatchFormat.signed(envelope,Base64.getDecoder().decode(BuildTrust.PUBLIC_KEY));}
    public static JSONObject check(Context ctx)throws Exception{
        String url=ctx.getSharedPreferences("czn_settings",0).getString("channel",DEFAULT_CHANNEL);HttpURLConnection c=open(url);String envelope;
        try(InputStream in=c.getInputStream()){ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>262144)throw new IOException("Metadata quá lớn.");out.write(b,0,n);}envelope=out.toString("UTF-8");}finally{c.disconnect();}
        JSONObject channel=verify(envelope);if(channel.getInt("schema")!=1||!channel.getString("type").equals("channel"))throw new IOException("Kênh cập nhật sai định dạng.");int code=channel.getInt("patch_code");int seen=ctx.getSharedPreferences("czn_settings",0).getInt("highest_patch_code",10400);if(code<seen)throw new IOException("Máy chủ trả bản cập nhật cũ; đã từ chối hạ phiên bản.");
        if(channel.getLong("patch_size")<=0||channel.getLong("patch_size")>33554432L||!channel.getString("patch_sha256").matches("[a-f0-9]{64}"))throw new IOException("Thông tin gói không hợp lệ.");
        PatchFormat.write(new File(ctx.getFilesDir(),"channel.json"),envelope.getBytes(StandardCharsets.UTF_8));ctx.getSharedPreferences("czn_settings",0).edit().putInt("highest_patch_code",code).apply();return channel;
    }
    public static JSONObject cached(Context ctx)throws Exception{
        File f=new File(ctx.getFilesDir(),"channel.json");if(!f.isFile())return new JSONObject();
        JSONObject data=verify(new String(PatchFormat.bytes(f,262144),StandardCharsets.UTF_8));
        if(data.getInt("schema")!=1||!data.getString("type").equals("channel")||data.getInt("patch_code")<ctx.getSharedPreferences("czn_settings",0).getInt("highest_patch_code",10400))return new JSONObject();return data;
    }
    public static File download(Context ctx,JSONObject channel,boolean apk,AtomicBoolean cancelled,PatchEngine.Progress progress)throws Exception{
        String kind=apk?"app":"patch",hash=channel.getString(kind+"_sha256"),url=channel.getString(kind+"_url");long size=channel.getLong(kind+"_size"),max=apk?157286400L:33554432L;
        if(!hash.matches("[a-f0-9]{64}")||size<=0||size>max)throw new IOException("Kích thước/checksum cập nhật không hợp lệ.");File dir=new File(ctx.getFilesDir(),"updates");dir.mkdirs();File result=new File(dir,hash+(apk?".apk":".cznpatch"));if(result.exists()&&result.length()==size&&PatchFormat.sha(result).equals(hash))return result;
        File partial=new File(dir,hash+".part-"+UUID.randomUUID());HttpURLConnection c=open(url);
        try(InputStream in=c.getInputStream();FileOutputStream out=new FileOutputStream(partial)){MessageDigest d=MessageDigest.getInstance("SHA-256");byte[] b=new byte[65536];int n;long count=0;while((n=in.read(b))!=-1){if(cancelled.get())throw new IOException("Đã hủy tải; dữ liệu game giữ nguyên.");count+=n;if(count>size)throw new IOException("Gói tải vượt kích thước công bố.");out.write(b,0,n);d.update(b,0,n);progress.report("Đang tải: "+(count/1048576)+" / "+((size+1048575)/1048576)+" MB",(int)(count*100/size));}out.getFD().sync();if(count!=size||!PatchFormat.hex(d.digest()).equals(hash))throw new IOException("Gói tải không khớp SHA-256; đã từ chối cài.");Files.move(partial.toPath(),result.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);return result;}finally{c.disconnect();Files.deleteIfExists(partial.toPath());}
    }
}
