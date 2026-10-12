package vn.czn.viethoa.czn_patcher;
import android.os.ParcelFileDescriptor;
import android.os.Process;
import androidx.annotation.Keep;
import java.io.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import org.json.*;

@Keep public class PatchUserService extends ICznService.Stub {
    public static final Set<String> PACKAGES=new HashSet<>(Arrays.asList("com.smilegate.chaoszero.stove.google","com.smilegate.chaoszero.stove","com.smilegate.chaoszero","com.stove.czn.google"));
    @Keep public PatchUserService(){}
    private File discover(String pkg)throws Exception{
        if(!PACKAGES.contains(pkg))throw new IOException("Gói game không được hỗ trợ.");File base=new File("/storage/emulated/0/Android/data/"+pkg);String prefix=base.getCanonicalPath()+"/";ArrayDeque<File> queue=new ArrayDeque<>();queue.add(base);int visited=0;
        while(!queue.isEmpty()&&visited++<1200){File dir=queue.remove();if(!dir.equals(base)&&!dir.getCanonicalPath().startsWith(prefix))continue;if(new File(dir,"manifest.ssra").isFile()&&new File(dir,"chunks").isDirectory())return dir;String relative=dir.getAbsolutePath().substring(base.getAbsolutePath().length());if(relative.split("/").length>9)continue;File[] children=dir.listFiles();if(children!=null)for(File f:children)if(f.isDirectory()&&!f.getName().equals(".czn_viethoa")&&!f.getName().equals("chunks"))queue.add(f);}
        throw new IOException("Chưa tìm thấy dữ liệu CZN. Mở game, tải đủ dữ liệu và ngôn ngữ Nhật rồi quay lại. Thiết bị phải cho Shizuku truy cập dữ liệu game.");
    }
    private void closeGame(String pkg)throws Exception{java.lang.Process p=new ProcessBuilder("/system/bin/am","force-stop","--user","0",pkg).redirectErrorStream(true).start();if(!p.waitFor(15,TimeUnit.SECONDS)){p.destroy();throw new IOException("Không thể đóng game.");}if(p.exitValue()!=0)throw new IOException("Shizuku không thể đóng game; chưa ghi tài nguyên.");}
    private String error(Exception e){try{return new JSONObject().put("success",false).put("message",e.getMessage()==null?"Thao tác chưa hoàn tất.":e.getMessage()).toString();}catch(Exception ignored){return "{\"success\":false}";}}
    private PatchEngine engine(){return new PatchEngine(Base64.getDecoder().decode(BuildTrust.PUBLIC_KEY));}
    @Override public String inspect(String pkg){try{File root=discover(pkg);return engine().inspect(root).put("success",true).put("backend_uid",Process.myUid()).toString();}catch(Exception e){return error(e);}}
    @Override public synchronized String install(String pkg,ParcelFileDescriptor zip,IPatchProgress progress){try(ParcelFileDescriptor.AutoCloseInputStream in=new ParcelFileDescriptor.AutoCloseInputStream(zip)){File root=discover(pkg);closeGame(pkg);return engine().apply(root,in,(s,n)->{try{progress.report(s,n);}catch(Exception ignored){}}).toString();}catch(Exception e){return error(e);}}
    @Override public synchronized String restore(String pkg,IPatchProgress progress){try{File root=discover(pkg);closeGame(pkg);return engine().restore(root,(s,n)->{try{progress.report(s,n);}catch(Exception ignored){}}).toString();}catch(Exception e){return error(e);}}
    @Override public void destroy(){System.exit(0);}
}
