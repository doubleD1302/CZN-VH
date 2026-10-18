package vn.czn.viethoa.czn_patcher;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.os.Build;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class ReleaseClient {
    public static final String DEFAULT_CHANNEL="https://github.com/doubleD1302/CZN-VH/releases/download/releases-1.0/localadb-channel.json";
    public static java.net.HttpURLConnection open(String url)throws Exception{
        for(int i=0;i<6;i++){
            URL u=new URL(url);
            if(!u.getProtocol().equals("https")||u.getUserInfo()!=null)throw new IOException("Kênh cập nhật phải dùng HTTPS.");
            HttpURLConnection c=(HttpURLConnection)u.openConnection();
            c.setConnectTimeout(10000);
            c.setReadTimeout(30000);
            c.setInstanceFollowRedirects(false);
            c.setRequestProperty("User-Agent","CZN-VietHoa-Android/1.4.1");
            int code;
            try {
                code=c.getResponseCode();
            } catch (UnknownHostException uhe) {
                c.disconnect();
                throw new IOException("Không thể kết nối máy chủ " + u.getHost() + " (lỗi DNS mạng hoặc không có Internet).", uhe);
            } catch (SocketTimeoutException ste) {
                c.disconnect();
                throw new IOException("Hết thời gian chờ kết nối máy chủ " + u.getHost() + ".", ste);
            }
            if(code>=300&&code<400){
                String next=c.getHeaderField("Location");
                c.disconnect();
                if(next==null)throw new IOException("Link chuyển hướng không hợp lệ.");
                url=new URL(u,next).toString();
                continue;
            }
            if(code!=200){
                c.disconnect();
                throw new HttpFailure(code);
            }
            return c;
        }
        throw new IOException("Quá nhiều chuyển hướng.");
    }
    public static JSONObject verify(String envelope)throws Exception{return PatchFormat.signed(envelope,Base64.getDecoder().decode(BuildTrust.PUBLIC_KEY));}
    public static JSONObject check(Context ctx)throws Exception{
        String url=ctx.getSharedPreferences("czn_settings",0).getString("channel",DEFAULT_CHANNEL);
        if(url==null||url.endsWith("/channel.json")||url.contains("latest/download/channel.json")||url.contains("/releases/download/releases/")){
            url=DEFAULT_CHANNEL;
            ctx.getSharedPreferences("czn_settings",0).edit().putString("channel",DEFAULT_CHANNEL).apply();
        }
        HttpURLConnection c=open(url);String envelope;
        try(InputStream in=c.getInputStream()){ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>262144)throw new IOException("Metadata quá lớn.");out.write(b,0,n);}envelope=out.toString("UTF-8");}finally{c.disconnect();}
        JSONObject channel=verify(envelope);if(channel.getInt("schema")!=1||!channel.getString("type").equals("channel"))throw new IOException("Kênh cập nhật sai định dạng.");int code=channel.getInt("patch_code");int seen=ctx.getSharedPreferences("czn_settings",0).getInt("highest_patch_code",10400);if(code<seen)throw new IOException("Máy chủ trả bản cập nhật cũ; đã từ chối hạ phiên bản.");
        if(channel.getLong("patch_size")<=0||channel.getLong("patch_size")>33554432L||!channel.getString("patch_sha256").matches("[a-f0-9]{64}"))throw new IOException("Thông tin gói không hợp lệ.");
        if(channel.has("app_code")){UpdatePolicy.validateAppMetadata(channel);if(channel.getInt("app_code")<ctx.getSharedPreferences("czn_settings",0).getInt("highest_app_code",0))throw new IOException("Máy chủ trả bản ứng dụng cũ; đã từ chối hạ phiên bản.");}
        PatchFormat.write(new File(ctx.getFilesDir(),"channel.json"),envelope.getBytes(StandardCharsets.UTF_8));ctx.getSharedPreferences("czn_settings",0).edit().putInt("highest_patch_code",code).putInt("highest_app_code",channel.optInt("app_code",0)).apply();cleanup(ctx);return channel;
    }
    public static JSONObject cached(Context ctx)throws Exception{
        File f=new File(ctx.getFilesDir(),"channel.json");if(!f.isFile())return new JSONObject();
        JSONObject data=verify(new String(PatchFormat.bytes(f,262144),StandardCharsets.UTF_8));
        if(data.getInt("schema")!=1||!data.getString("type").equals("channel")||data.getInt("patch_code")<ctx.getSharedPreferences("czn_settings",0).getInt("highest_patch_code",10400))return new JSONObject();
        if(data.has("app_code")){UpdatePolicy.validateAppMetadata(data);if(data.getInt("app_code")<ctx.getSharedPreferences("czn_settings",0).getInt("highest_app_code",0))return new JSONObject();}return data;
    }
    public static File download(Context ctx,JSONObject channel,boolean apk,AtomicBoolean cancelled,PatchEngine.Progress progress)throws Exception{
        String kind=apk?"app":"patch",hash=channel.getString(kind+"_sha256"),url=channel.getString(kind+"_url");long size=channel.getLong(kind+"_size"),max=apk?157286400L:33554432L;
        if(!hash.matches("[a-f0-9]{64}")||size<=0||size>max)throw new IOException("Kích thước/checksum cập nhật không hợp lệ.");
        File dir=UpdateCache.directory(ctx.getFilesDir()),result=new File(dir,hash+(apk?".apk":".cznpatch"));
        File partial=new File(dir,hash+".part-"+UUID.randomUUID());
        try(UpdateCache.Lease lease=UpdateCache.acquire(result,partial)) {
            if(result.exists()&&result.length()==size&&PatchFormat.sha(result).equals(hash)){cleanup(ctx);return result;}
            HttpURLConnection c=openAsset(url,size,hash,apk);
            try(InputStream in=c.getInputStream();FileOutputStream out=new FileOutputStream(partial)){MessageDigest d=MessageDigest.getInstance("SHA-256");byte[] b=new byte[65536];int n;long count=0;while((n=in.read(b))!=-1){if(cancelled.get())throw new IOException("Đã hủy tải; dữ liệu game giữ nguyên.");count+=n;if(count>size)throw new IOException("Gói tải vượt kích thước công bố.");out.write(b,0,n);d.update(b,0,n);progress.report("Đang tải: "+(count/1048576)+" / "+((size+1048575)/1048576)+" MB",(int)(count*100/size));}out.getFD().sync();if(count!=size||!PatchFormat.hex(d.digest()).equals(hash))throw new IOException("Gói tải không khớp SHA-256; đã từ chối cài.");Files.move(partial.toPath(),result.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);cleanup(ctx);return result;}finally{c.disconnect();Files.deleteIfExists(partial.toPath());}
        }
    }

    public static final class HttpFailure extends IOException {
        public final int status;
        HttpFailure(int status) { super("Máy chủ trả mã "+status+". Bạn vẫn có thể cài bản đi kèm.");this.status=status; }
    }
    // A release can be moved/renamed. Discovery is only a locator: the signed
    // size/hash remain mandatory and the downloaded bytes are checked below.
    public static String relocatedAsset(JSONArray releases,String original,long size,String hash,boolean apk)throws Exception {
        URI source=new URI(original);
        if(!"https".equals(source.getScheme())||!"github.com".equals(source.getHost())||source.getUserInfo()!=null||
                !source.getPath().startsWith("/doubleD1302/CZN-VH/releases/download/"))throw new IOException("Không tìm lại asset ngoài kho CZN.");
        String suffix=apk?".apk":".cznpatch";
        for(int i=0;i<releases.length();i++) {
            JSONObject release=releases.getJSONObject(i);
            if(release.optBoolean("draft")||release.optBoolean("prerelease"))continue;
            JSONArray assets=release.getJSONArray("assets");
            for(int j=0;j<assets.length();j++) {
                JSONObject asset=assets.getJSONObject(j);
                URI candidate=new URI(asset.getString("browser_download_url"));
                if("https".equals(candidate.getScheme())&&"github.com".equals(candidate.getHost())&&candidate.getUserInfo()==null&&
                        candidate.getPath().startsWith("/doubleD1302/CZN-VH/releases/download/")&&
                        asset.getString("name").endsWith(suffix)&&asset.getLong("size")==size&&
                        ("sha256:"+hash).equals(asset.optString("digest")))return candidate.toString();
            }
        }
        throw new IOException("Link cập nhật đã thay đổi, nhưng chưa tìm thấy tệp khớp SHA-256 đã ký. Chờ bản phát hành được sửa; có thể cài gói đi kèm.");
    }
    private static HttpURLConnection openAsset(String url,long size,String hash,boolean apk)throws Exception {
        try{return open(url);}catch(HttpFailure error){if(error.status!=404)throw error;}
        // Only recover official repository URLs; never change signed metadata.
        URI source=new URI(url);
        if(!"https".equals(source.getScheme())||!"github.com".equals(source.getHost())||
                !source.getPath().startsWith("/doubleD1302/CZN-VH/releases/download/"))throw new IOException("Link cập nhật trả 404.");
        HttpURLConnection api=open("https://api.github.com/repos/doubleD1302/CZN-VH/releases?per_page=10");
        String listing;
        try(InputStream in=api.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()) {
            byte[] buffer=new byte[8192];int n;
            while((n=in.read(buffer))!=-1){if(out.size()+n>1048576)throw new IOException("Danh sách phát hành quá lớn.");out.write(buffer,0,n);}
            listing=out.toString("UTF-8");
        }finally{api.disconnect();}
        return open(relocatedAsset(new JSONArray(listing),url,size,hash,apk));
    }

    private static long versionCode(PackageInfo info) {
        return Build.VERSION.SDK_INT>=28?info.getLongVersionCode():info.versionCode;
    }
    /** Persist until Android has consumed the file, even if this Activity/process goes away. */
    public static synchronized void holdForInstaller(Context ctx,File file,long code) throws IOException {
        boolean saved=ctx.getSharedPreferences("czn_settings",0).edit()
            .putString("installer_apk_path",file.getAbsolutePath()).putLong("installer_apk_code",code)
            .putLong("installer_apk_until",System.currentTimeMillis()+86400000L).commit();
        if(!saved)throw new IOException("Chưa lưu được APK chờ cài. Hãy thử lại.");
    }
    private static String cachedName(File dir,String path) throws IOException {
        if(path==null)return null;
        File file=new File(path);
        return dir.getCanonicalFile().equals(file.getCanonicalFile().getParentFile())
            && UpdateCache.apkName(file.getName())?file.getName():null;
    }
    /** Offline migration runs on every start, including the first launch after an APK upgrade. */
    public static synchronized void cleanup(Context ctx) {
        try {
            File dir=UpdateCache.directory(ctx.getFilesDir());
            SharedPreferences prefs=ctx.getSharedPreferences("czn_settings",0);
            long installed=versionCode(ctx.getPackageManager().getPackageInfo(ctx.getPackageName(),0));
            Set<String> useful=new HashSet<>(),held=new HashSet<>();
            File[] files=dir.listFiles();
            if(files!=null)for(File file:files)if(UpdateCache.apkName(file.getName())
                    && Files.isRegularFile(file.toPath(),LinkOption.NOFOLLOW_LINKS)) {
                PackageInfo info=ctx.getPackageManager().getPackageArchiveInfo(file.getAbsolutePath(),0);
                if(info!=null&&ctx.getPackageName().equals(info.packageName)&&versionCode(info)>installed)
                    useful.add(file.getName());
            }
            SharedPreferences.Editor edit=prefs.edit();
            String pending=cachedName(dir,prefs.getString("pending_app_update",null));
            if(pending!=null&&useful.contains(pending))held.add(pending);
            else edit.remove("pending_app_update");
            String installer=cachedName(dir,prefs.getString("installer_apk_path",null));
            if(installer!=null&&useful.contains(installer)&&UpdateCache.installerLeaseValid(installed,
                    prefs.getLong("installer_apk_code",0),prefs.getLong("installer_apk_until",0),System.currentTimeMillis()))held.add(installer);
            else edit.remove("installer_apk_path").remove("installer_apk_code").remove("installer_apk_until");
            if(prefs.getInt("downloaded_app_code",0)<=installed)edit.remove("downloaded_app_code");
            edit.apply();
            JSONObject channel;
            try{channel=cached(ctx);}catch(Exception untrusted){channel=new JSONObject();}
            String app=channel.optString("app_sha256","")+".apk";
            String patch=channel.optString("patch_sha256","")+".cznpatch";
            UpdateCache.prune(ctx.getFilesDir(),ctx.getCacheDir(),app,patch,useful,held);
        } catch(Exception error) {
            // Cleanup failure must not turn a verified update/install into a false failure.
            android.util.Log.w("CznUpdateCache","Chưa dọn được bộ nhớ cập nhật",error);
        }
    }
}
