package vn.czn.viethoa.czn_patcher;
import org.json.*;
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.channels.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.zip.*;

/** Streaming staging, verified backups, atomic file replacement and durable rollback journal. */
public final class PatchEngine {
    public interface Progress { void report(String label,int percent); }
    public interface CommitHook { void before(int index,String path)throws Exception; }
    private final byte[] key;public CommitHook hook=(i,p)->{};
    public PatchEngine(byte[] publicKey){key=publicKey.clone();}
    private static File home(File root){return new File(root,".czn_viethoa");}
    private static JSONObject json(File f)throws Exception{return new JSONObject(new String(PatchFormat.bytes(f,262144),StandardCharsets.UTF_8));}
    private static void atomic(File f,byte[] bytes)throws Exception{File tmp=new File(f.getPath()+".tmp");PatchFormat.write(tmp,bytes);Files.move(tmp.toPath(),f.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}
    private static void atomicJson(File f,JSONObject o)throws Exception{atomic(f,o.toString().getBytes(StandardCharsets.UTF_8));}
    private static void copyFile(File from,File to)throws Exception{to.getParentFile().mkdirs();try(InputStream in=new FileInputStream(from);FileOutputStream out=new FileOutputStream(to)){PatchFormat.copy(in,out,from.length());out.getFD().sync();}}
    private static void remove(File f)throws IOException{if(!f.exists())return;if(f.isDirectory()){File[] a=f.listFiles();if(a==null)throw new IOException("Không đọc được thư mục tạm.");for(File c:a){if(!c.getCanonicalPath().startsWith(f.getCanonicalPath()+File.separator))throw new IOException("Symlink tạm không hợp lệ.");remove(c);}}if(!f.delete())throw new IOException("Không xóa được file tạm.");}
    private static String hash(File f)throws Exception{return f.exists()?PatchFormat.sha(f):"absent";}
    private static File baseline(File root,JSONObject state)throws Exception{String id=state.getString("baseline");if(!id.matches("[a-f0-9]{64}"))throw new IOException("Baseline không hợp lệ.");return new File(home(root),"baselines/"+id);}
    private static void requireHashes(File root,JSONObject hashes)throws Exception{for(String rel:PatchFormat.keys(hashes))if(!hash(PatchFormat.safe(root,rel)).equals(hashes.getString(rel)))throw new IOException("Game đã thay đổi: "+rel+". Hãy hoàn tất cập nhật/kiểm tra dữ liệu game trước.");}
    private static File tx(File root,String id)throws Exception{if(!id.matches("[a-f0-9-]{36}"))throw new IOException("Journal không hợp lệ.");return new File(home(root),"transactions/"+id);}
    public void recover(File root)throws Exception{
        File jf=new File(home(root),"journal.json");if(!jf.exists())return;JSONObject j=json(jf);File dir=tx(root,j.getString("id"));JSONObject before=j.getJSONObject("before"),after=j.getJSONObject("after");
        // Validate the complete rollback set before modifying any target.
        for(String rel:PatchFormat.keys(before)){File back=PatchFormat.safe(new File(dir,"rollback"),rel);if(!hash(back).equals(before.getString(rel)))throw new IOException("Bản phục hồi giao dịch không toàn vẹn.");String now=hash(PatchFormat.safe(root,rel));if(!now.equals(before.getString(rel))&&!now.equals(after.getString(rel)))throw new IOException("Game thay đổi trong giao dịch; giữ nguyên dữ liệu và bản sao lưu.");}
        for(String rel:PatchFormat.keys(before)){File target=PatchFormat.safe(root,rel);if(!hash(target).equals(before.getString(rel))){File staged=PatchFormat.safe(new File(dir,"recover"),rel);copyFile(PatchFormat.safe(new File(dir,"rollback"),rel),staged);Files.move(staged.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}}
        requireHashes(root,before);File sf=new File(home(root),"state.json");if(j.isNull("previous_state")){Files.deleteIfExists(sf.toPath());}else atomicJson(sf,j.getJSONObject("previous_state"));Files.delete(jf.toPath());remove(dir);
    }
    public JSONObject inspect(File root)throws Exception{
        File h=home(root),jf=new File(h,"journal.json"),sf=new File(h,"state.json");JSONObject out=new JSONObject().put("root",root.getAbsolutePath()).put("recovery_required",jf.exists());
        if(sf.exists()){JSONObject s=json(sf);boolean matches=true;for(String rel:PatchFormat.keys(s.getJSONObject("installed")))if(!hash(PatchFormat.safe(root,rel)).equals(s.getJSONObject("installed").getString(rel)))matches=false;out.put("installed_version",s.getString("version")).put("installed_code",s.getInt("version_code")).put("files_match",matches);}
        return out;
    }
    public JSONObject apply(File root,InputStream zip,Progress progress)throws Exception{
        File h=home(root);h.mkdirs();try(RandomAccessFile lock=new RandomAccessFile(new File(h,"operation.lock"),"rw");FileLock guard=lock.getChannel().tryLock()){
            if(guard==null)throw new IOException("Có một giao dịch đang chạy.");recover(root);
            File sf=new File(h,"state.json");JSONObject prior=sf.exists()?json(sf):null;File sourceRoot=root;
            if(prior!=null){
                boolean intact=true;JSONObject installed=prior.getJSONObject("installed");for(String rel:PatchFormat.keys(installed))if(!hash(PatchFormat.safe(root,rel)).equals(installed.getString(rel)))intact=false;
                if(intact){sourceRoot=baseline(root,prior);requireHashes(sourceRoot,prior.getJSONObject("original"));}
                else {
                    if(hash(new File(root,"manifest.ssra")).equals(installed.getString("manifest.ssra")))throw new IOException("Bộ dữ liệu đang cài không nhất quán; hoàn tất kiểm tra game trước.");
                    for(String rel:PatchFormat.keys(installed))if(rel.startsWith("chunks/")&&hash(PatchFormat.safe(root,rel)).equals(installed.getString(rel)))throw new IOException("Game cập nhật còn giữ chunk của bản vá cũ; hãy dùng kiểm tra/tải lại dữ liệu trong game trước.");
                    // A complete publisher update starts a new source baseline; old backups stay intact.
                    sourceRoot=root;
                }
            }
            String id=UUID.randomUUID().toString();File work=tx(root,id);work.mkdirs();
            try{
                progress.report("Xác minh chữ ký và gói bản dịch",10);JSONObject release;Map<String,File> payloads=new HashMap<>();
                try(ZipInputStream z=new ZipInputStream(zip)){ZipEntry e=z.getNextEntry();if(e==null||!e.getName().equals("release.json"))throw new IOException("Gói cũ/chưa có chữ ký. Hãy dùng gói CZN Android v2.");ByteArrayOutputStream descriptor=new ByteArrayOutputStream();byte[] b=new byte[65536];int n;while((n=z.read(b))!=-1){if(descriptor.size()+n>262144)throw new IOException("Metadata quá lớn.");descriptor.write(b,0,n);}release=PatchFormat.signed(descriptor.toString("UTF-8"),key);
                    if(release.getInt("schema")!=2||release.getInt("min_patcher")>10400||release.getInt("version_code")<10400)throw new IOException("Gói cần phiên bản ứng dụng mới hơn.");if(prior!=null&&release.getInt("version_code")<prior.getInt("version_code"))throw new IOException("Không tự hạ phiên bản bản dịch.");
                    JSONArray patches=release.getJSONArray("patches");if(patches.length()!=2)throw new IOException("Gói phải có hai slot JP đã kiểm chứng.");Set<String> allowed=new HashSet<>(),names=new HashSet<>();for(int i=0;i<patches.length();i++){JSONObject p=patches.getJSONObject(i);String f=p.getString("file"),payload=p.getString("payload");if(!(f.equals("text/ja/text.db")||f.equals(PatchFormat.STORY))||!names.add(f)||!payload.matches("payload/[a-z]+\\.zst")||!allowed.add(payload))throw new IOException("Whitelist gói không hợp lệ.");}
                    long total=0;while((e=z.getNextEntry())!=null){String name=e.getName();if(e.isDirectory()||!allowed.contains(name)||payloads.containsKey(name))throw new IOException("File lạ/trùng trong ZIP.");File target=new File(work,name);target.getParentFile().mkdirs();try(FileOutputStream out=new FileOutputStream(target)){while((n=z.read(b))!=-1){total+=n;if(total>33554432L)throw new IOException("Gói giải nén quá lớn.");out.write(b,0,n);}out.getFD().sync();}payloads.put(name,target);}if(payloads.size()!=allowed.size())throw new IOException("Gói thiếu payload.");
                }
                progress.report("Kiểm tra nguồn Nhật trên thiết bị",25);PatchFormat manifest=new PatchFormat(PatchFormat.bytes(new File(sourceRoot,"manifest.ssra"),16777216));File stage=new File(work,"stage");Map<String,File> replacements=new LinkedHashMap<>();JSONArray patches=release.getJSONArray("patches");long required=33554432L;
                for(int i=0;i<patches.length();i++){
                    JSONObject p=patches.getJSONObject(i);PatchFormat.Entry f=manifest.files.get(p.getString("file"));if(f==null)throw new IOException("Thiếu slot JP.");PatchFormat.Chunk c=manifest.chunk(f);String wanted=f.name.equals(PatchFormat.STORY)?"base_b21_0.ssrc":"lang_ja_b01_0.ssrc";
                    if(!c.name.equals(wanted)||f.enc!=0||f.comp!=1||f.cs!=p.getInt("source_cs")||f.us!=p.getInt("source_us")||f.hash!=PatchFormat.hexLong(p.getString("source_xxh64")))throw new IOException("Nguồn JP đã đổi; cần bản dịch tương thích mới.");manifest.verifyChunk(sourceRoot,c);File payload=payloads.get(p.getString("payload"));long size=p.getLong("target_cs");if(size<1||size>f.cs||payload.length()!=size||!PatchFormat.sha(payload).equals(p.getString("target_sha256")))throw new IOException("Payload sai checksum/kích thước.");
                    File src=PatchFormat.safe(sourceRoot,"chunks/"+c.name);try(RandomAccessFile r=new RandomAccessFile(src,"r")){r.seek(f.offset-c.start);MessageDigest d=MessageDigest.getInstance("SHA-256");byte[] b=new byte[65536];int left=f.cs;while(left>0){int n=r.read(b,0,Math.min(left,b.length));if(n<0)throw new EOFException();d.update(b,0,n);left-=n;}if(!PatchFormat.hex(d.digest()).equals(p.getString("source_sha256")))throw new IOException("Nguồn JP không khớp gói. Chưa ghi thay đổi vào game.");}
                    required+=c.total*3;
                }
                if(root.getUsableSpace()<required)throw new IOException("Cần khoảng "+(required/1048576+1)+" MB dung lượng trống để sao lưu và cài.");
                for(int i=0;i<patches.length();i++){
                    JSONObject p=patches.getJSONObject(i);PatchFormat.Entry f=manifest.files.get(p.getString("file"));PatchFormat.Chunk c=manifest.chunk(f);String rel="chunks/"+c.name;File dest=PatchFormat.safe(stage,rel),src=PatchFormat.safe(sourceRoot,rel);copyFile(src,dest);File payload=payloads.get(p.getString("payload"));
                    try(RandomAccessFile out=new RandomAccessFile(dest,"rw");InputStream in=new FileInputStream(payload)){out.seek(f.offset-c.start);byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)out.write(b,0,n);long pad=f.cs-payload.length();Arrays.fill(b,(byte)0);while(pad>0){n=(int)Math.min(pad,b.length);out.write(b,0,n);pad-=n;}out.getFD().sync();}
                    long checksum=PatchFormat.xxFile(dest,c.size);try(RandomAccessFile out=new RandomAccessFile(dest,"rw")){out.seek(dest.length()-8);out.write(ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(checksum).array());out.getFD().sync();}
                    manifest.set(f,c,(int)payload.length(),p.getInt("target_us"),PatchFormat.hexLong(p.getString("target_xxh64")),checksum);replacements.put(rel,dest);progress.report("Chuẩn bị dữ liệu tiếng Việt",40+i*10);
                }
                File stagedManifest=PatchFormat.safe(stage,"manifest.ssra");PatchFormat.write(stagedManifest,manifest.data);if(new File(sourceRoot,"manifest.ssra.prev").exists()){File dest=PatchFormat.safe(stage,"manifest.ssra.prev");PatchFormat.write(dest,manifest.data);replacements.put("manifest.ssra.prev",dest);}if(new File(sourceRoot,"manifest.ssra.etag").exists()){File dest=PatchFormat.safe(stage,"manifest.ssra.etag");PatchFormat.write(dest,PatchFormat.identity(PatchFormat.bytes(new File(sourceRoot,"manifest.ssra.etag"),65536),manifest.data));replacements.put("manifest.ssra.etag",dest);}replacements.put("manifest.ssra",stagedManifest);
                String baseId=PatchFormat.sha(new File(sourceRoot,"manifest.ssra"));File base=new File(h,"baselines/"+baseId);JSONObject originals=new JSONObject(),installed=new JSONObject();for(String rel:replacements.keySet()){File src=PatchFormat.safe(sourceRoot,rel),saved=PatchFormat.safe(base,rel);String digest=PatchFormat.sha(src);if(!saved.exists())copyFile(src,saved);if(!PatchFormat.sha(saved).equals(digest))throw new IOException("Backup không khớp nguồn: "+rel);originals.put(rel,digest);installed.put(rel,PatchFormat.sha(replacements.get(rel)));}
                JSONObject next=new JSONObject().put("version",release.getString("version")).put("version_code",release.getInt("version_code")).put("baseline",baseId).put("original",originals).put("installed",installed);
                progress.report("Sao lưu đã xác minh; đang cài bản dịch",70);transaction(root,work,id,replacements,prior,next,progress);return new JSONObject().put("success",true).put("version",next.getString("version"));
            }finally{if(!new File(h,"journal.json").exists()&&work.exists())remove(work);}
        }
    }
    private void transaction(File root,File work,String id,Map<String,File> files,JSONObject prior,JSONObject next,Progress p)throws Exception{
        JSONObject before=new JSONObject(),after=new JSONObject();for(String rel:files.keySet()){File live=PatchFormat.safe(root,rel);String hash=PatchFormat.sha(live);File back=PatchFormat.safe(new File(work,"rollback"),rel);copyFile(live,back);if(!PatchFormat.sha(back).equals(hash))throw new IOException("Backup giao dịch thất bại.");before.put(rel,hash);after.put(rel,PatchFormat.sha(files.get(rel)));}
        File jf=new File(home(root),"journal.json");atomicJson(jf,new JSONObject().put("id",id).put("before",before).put("after",after).put("previous_state",prior==null?JSONObject.NULL:prior));
        try{requireHashes(root,before);int i=0;for(Map.Entry<String,File> e:files.entrySet()){hook.before(i,e.getKey());if(!PatchFormat.sha(PatchFormat.safe(root,e.getKey())).equals(before.getString(e.getKey())))throw new IOException("File đổi trong lúc ghi.");Files.move(e.getValue().toPath(),PatchFormat.safe(root,e.getKey()).toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);p.report("Đọc lại dữ liệu sau cài",75+(++i*20/files.size()));}requireHashes(root,after);File sf=new File(home(root),"state.json");if(next==null)Files.deleteIfExists(sf.toPath());else atomicJson(sf,next);Files.delete(jf.toPath());p.report("Hoàn tất",100);}catch(Exception e){try{recover(root);}catch(Exception recovery){e.addSuppressed(recovery);throw new IOException("Cần phục hồi giao dịch. Mở app và bấm Khôi phục giao dịch; không chạy game.",e);}throw new IOException("Cài chưa hoàn tất; đã phục hồi đầy đủ dữ liệu trước thao tác. "+e.getMessage(),e);}
    }
    public JSONObject restore(File root,Progress p)throws Exception{
        File h=home(root);h.mkdirs();try(RandomAccessFile lock=new RandomAccessFile(new File(h,"operation.lock"),"rw");FileLock guard=lock.getChannel().tryLock()){
            if(guard==null)throw new IOException("Có giao dịch đang chạy.");boolean pending=new File(h,"journal.json").exists();recover(root);File sf=new File(h,"state.json");if(!sf.exists()){if(pending)return new JSONObject().put("success",true).put("recovered",true);throw new IOException("Chưa có bản sao lưu của app này.");}JSONObject prior=json(sf);requireHashes(root,prior.getJSONObject("installed"));File base=baseline(root,prior);requireHashes(base,prior.getJSONObject("original"));String id=UUID.randomUUID().toString();File work=tx(root,id);Map<String,File> files=new LinkedHashMap<>();try{for(String rel:PatchFormat.keys(prior.getJSONObject("original"))){if(!rel.equals("manifest.ssra")){File tmp=PatchFormat.safe(new File(work,"stage"),rel);copyFile(PatchFormat.safe(base,rel),tmp);files.put(rel,tmp);}}File mf=PatchFormat.safe(new File(work,"stage"),"manifest.ssra");copyFile(new File(base,"manifest.ssra"),mf);files.put("manifest.ssra",mf);transaction(root,work,id,files,prior,null,p);return new JSONObject().put("success",true).put("restored_count",files.size());}finally{if(!new File(h,"journal.json").exists()&&work.exists())remove(work);}
        }
    }
}
