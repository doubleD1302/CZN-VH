package vn.czn.viethoa.czn_patcher;

import org.json.*;
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.X509EncodedKeySpec;
import java.util.*;
import net.jpountz.xxhash.*;

/** SSRA v4 parser: never changes engine code or fields outside approved JP slots. */
public final class PatchFormat {
    public static final String STORY = "db/story_main_part1new_260729@story.db";
    public static final Set<String> ALLOWED = new HashSet<>(Arrays.asList("manifest.ssra", "manifest.ssra.etag", "manifest.ssra.prev", "chunks/lang_ja_b01_0.ssrc", "chunks/base_b21_0.ssrc"));
    public static String sha(File f) throws Exception { try(InputStream in = new FileInputStream(f)){return sha(in);} }
    public static String sha(InputStream in) throws Exception { MessageDigest d=MessageDigest.getInstance("SHA-256"); byte[] b=new byte[65536]; int n; while((n=in.read(b))!=-1) d.update(b,0,n); return hex(d.digest()); }
    public static String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte v:b)s.append(String.format(Locale.ROOT,"%02x",v&255));return s.toString();}
    public static byte[] bytes(File f,int max) throws Exception {if(f.length()>max)throw new IOException("Dữ liệu vượt giới hạn.");try(InputStream in=new FileInputStream(f)){ByteArrayOutputStream o=new ByteArrayOutputStream();copy(in,o,f.length());return o.toByteArray();}}
    public static void copy(InputStream in,OutputStream out,long count)throws IOException{byte[] b=new byte[65536];while(count>0){int n=in.read(b,0,(int)Math.min(count,b.length));if(n<0)throw new EOFException();out.write(b,0,n);count-=n;}}
    public static void write(File f,byte[] b)throws Exception{f.getParentFile().mkdirs();try(FileOutputStream out=new FileOutputStream(f)){out.write(b);out.getFD().sync();}}
    public static File safe(File root,String rel)throws Exception{if(!ALLOWED.contains(rel))throw new IOException("File ngoài phạm vi JP: "+rel);File f=new File(root,rel);if(!f.getCanonicalPath().startsWith(root.getCanonicalPath()+File.separator))throw new IOException("Đường dẫn không hợp lệ.");return f;}
    public static JSONObject signed(String envelope,byte[] publicKey)throws Exception{
        if(envelope.length()>262144)throw new IOException("Metadata quá lớn.");JSONObject e=new JSONObject(envelope);
        byte[] raw=Base64.getDecoder().decode(e.getString("signed"));byte[] signature=Base64.getDecoder().decode(e.getString("signature"));
        Signature v=Signature.getInstance("SHA256withRSA");v.initVerify(KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(publicKey)));v.update(raw);
        if(!v.verify(signature))throw new IOException("Bản cập nhật không có chữ ký hợp lệ của CZN Việt Hóa.");
        return new JSONObject(new String(raw,StandardCharsets.UTF_8));
    }
    public static long xx(byte[] b){return XXHashFactory.fastestJavaInstance().hash64().hash(b,0,b.length,0);}
    public static long xxFile(File f,long limit)throws Exception{StreamingXXHash64 h=XXHashFactory.fastestJavaInstance().newStreamingHash64(0);try(InputStream in=new FileInputStream(f)){byte[] b=new byte[65536];while(limit>0){int n=in.read(b,0,(int)Math.min(limit,b.length));if(n<0)throw new EOFException();h.update(b,0,n);limit-=n;}return h.getValue();}finally{h.close();}}
    public static Set<String> keys(JSONObject json){Set<String> keys=new HashSet<>();Iterator<String> it=json.keys();while(it.hasNext())keys.add(it.next());return keys;}
    public static String unsigned(long v){return Long.toUnsignedString(v);}
    public static long hexLong(String s){return Long.parseUnsignedLong(s,16);}
    public static class Chunk {int index,id,gid;long size,total,start,checksum;String name;}
    public static class Entry {int index,pos,cs,us,comp,enc,gid;long offset,hash;String name;}
    public final byte[] data;private final ByteBuffer b;private final int co,fo,fh;public final Map<String,Entry> files=new HashMap<>();public final List<Chunk> chunks=new ArrayList<>();
    private int pos(long v)throws IOException{if(v<0||v>data.length)throw new IOException("Chỉ mục SSRA vượt giới hạn.");return (int)v;}
    private String str(int start,int end)throws IOException{if(start<0||end>data.length||start>=end)throw new IOException("Tên SSRA không hợp lệ.");int i=start;while(i<end&&data[i]!=0)i++;if(i==end)throw new IOException("Tên SSRA thiếu kết thúc.");return new String(data,start,i-start,StandardCharsets.UTF_8);}
    private boolean tag(int p,String s){return p>=0&&p+4<=data.length&&new String(data,p,4,StandardCharsets.US_ASCII).equals(s);}
    public PatchFormat(byte[] input)throws Exception{
        data=input.clone();b=ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
        if(data.length<88||!tag(0,"SSRA")||b.getInt(4)!=4||b.getInt(8)!=88)throw new IOException("Phiên bản tài nguyên chưa được hỗ trợ.");
        int nc=b.getInt(12),nf=b.getInt(16);if(nc<1||nc>65535||nf<1||nf>2000000)throw new IOException("Chỉ mục không hợp lệ.");
        int so=pos(b.getLong(24)),ss=pos(b.getLong(32));co=pos(b.getLong(40));fo=pos(b.getLong(48));pos((long)co+nc*32L);pos((long)fo+nf*40L);int gp=pos((long)so+ss);if(!tag(gp,"GRPS"))throw new IOException("Thiếu nhóm SSRA.");
        int ng=b.getInt(gp+4),gs=b.getInt(gp+8);if(ng<1||ng>65535||gs<0)throw new IOException("Nhóm SSRA không hợp lệ.");int names=pos((long)gp+16+ng*24L);int end=pos((long)names+gs);Map<Integer,String> groups=new HashMap<>();
        for(int i=0;i<ng;i++){int k=gp+16+i*24;groups.put(b.getShort(k)&65535,str(pos((long)names+b.getInt(k+4)),end));}
        for(int i=0;i<nc;i++){int k=co+i*32;Chunk c=new Chunk();c.index=i;c.id=b.getInt(k);c.gid=b.getShort(k+4)&65535;c.size=b.getLong(k+8);c.total=b.getLong(k+16);c.checksum=b.getLong(k+24);if(c.size<0||c.total!=c.size+16)throw new IOException("Chunk SSRA không hợp lệ.");c.name=groups.get(c.gid)+String.format(Locale.ROOT,"_b%02d_0.ssrc",c.id);chunks.add(c);}
        Map<Integer,Long> starts=new HashMap<>();List<Chunk> sorted=new ArrayList<>(chunks);sorted.sort(Comparator.comparingInt(c->c.id));for(Chunk c:sorted){c.start=starts.getOrDefault(c.gid,0L);starts.put(c.gid,c.start+c.size);}
        int search=end;if(tag(end,"CNAM")){int cnt=b.getInt(end+4),ns=b.getInt(end+12);if(cnt!=nc||b.getInt(end+8)!=0||ns<0)throw new IOException("CNAM không hợp lệ.");int sn=pos((long)end+16+cnt*8L),se=pos((long)sn+ns);if(ns>0)for(int i=0;i<cnt;i++){int ci=b.getInt(end+16+i*8),no=b.getInt(end+20+i*8);if(ci<0||ci>=nc)throw new IOException("CNAM index.");String name=str(pos((long)sn+no),se);if(name.contains("/")||name.contains("\\")||name.contains(".."))throw new IOException("Tên chunk không hợp lệ.");chunks.get(ci).name=name;}search=se;}
        int hp=-1;for(int i=search;i<=data.length-16;i++)if(tag(i,"FHSH")&&i+16+nf*8L==data.length){hp=i;break;}
        if(hp<0||b.getInt(hp+4)!=nf||b.getInt(hp+8)!=1||b.getInt(hp+12)!=0)throw new IOException("Checksum SSRA chưa hỗ trợ.");fh=hp+16;
        for(int i=0;i<nf;i++){int k=fo+i*40;if((b.getInt(k+36)&1)!=0)continue;int no=b.getInt(k+28);if(no<0||no>=ss)throw new IOException("Tên file SSRA.");Entry f=new Entry();f.index=i;f.pos=k;f.name=str(so+no,so+ss).replace('\\','/');while(f.name.startsWith("/"))f.name=f.name.substring(1);f.offset=b.getLong(k+8);f.cs=b.getInt(k+16);f.us=b.getInt(k+20);f.comp=data[k+32]&255;f.enc=data[k+33]&255;f.gid=b.getShort(k+34)&65535;f.hash=b.getLong(fh+i*8);if(files.put(f.name,f)!=null)throw new IOException("ID file SSRA trùng.");}
        if(!files.containsKey("text/ja/text.db"))throw new IOException("Hãy tải ngôn ngữ Nhật trong game trước.");
    }
    public Chunk chunk(Entry f)throws Exception{for(Chunk c:chunks)if(c.gid==f.gid&&f.offset>=c.start&&f.offset+f.cs<=c.start+c.size)return c;throw new IOException("Slot JP trải nhiều chunk; cần gói tương thích mới.");}
    public void verifyChunk(File root,Chunk c)throws Exception{File f=safe(root,"chunks/"+c.name);if(f.length()!=c.total)throw new IOException("Game chưa tải đủ: "+c.name);byte[] tail=new byte[16];try(RandomAccessFile r=new RandomAccessFile(f,"r")){r.seek(f.length()-16);r.readFully(tail);}ByteBuffer t=ByteBuffer.wrap(tail).order(ByteOrder.LITTLE_ENDIAN);if(!new String(tail,0,4,StandardCharsets.US_ASCII).equals("SSRC")||t.getInt(4)!=c.id||t.getLong(8)!=c.checksum||xxFile(f,c.size)!=c.checksum)throw new IOException("Checksum game không khớp; hãy hoàn tất cập nhật game.");}
    public void set(Entry f,Chunk c,int cs,int us,long fileHash,long chunkHash){b.putInt(f.pos+16,cs);b.putInt(f.pos+20,us);data[f.pos+32]=1;b.putLong(fh+f.index*8,fileHash);b.putLong(co+c.index*32+24,chunkHash);}
    public static byte[] identity(byte[] existing,byte[] manifest)throws Exception{String s=new String(existing,StandardCharsets.UTF_8);String[] lines=s.split("\r\n",-1);if(lines.length<4||!lines[0].matches("https?://.+")||!lines[2].matches("[0-9]+")||!lines[3].matches("[0-9]+"))throw new IOException("Cache game chưa sẵn sàng.");lines[2]=unsigned(xx(manifest));lines[3]=Integer.toString(manifest.length);return String.join("\r\n",lines).getBytes(StandardCharsets.UTF_8);}
}
