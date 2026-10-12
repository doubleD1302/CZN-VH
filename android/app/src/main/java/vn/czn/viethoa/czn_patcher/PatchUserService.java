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
        if(!PACKAGES.contains(pkg))throw new IOException("Gói game không được hỗ trợ.");
        List<File> bases=new ArrayList<>();List<String> volumes=new ArrayList<>();volumes.add("/storage/emulated/0");
        File[] storage=new File("/storage").listFiles();if(storage!=null)for(File v:storage)if(v.getName().matches("[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}"))volumes.add(v.getAbsolutePath());
        for(String volume:volumes)for(String kind:Arrays.asList("data","media","obb"))bases.add(new File(volume+"/Android/"+kind+"/"+pkg));
        return GameDiscovery.find(bases,new JSONObject().put("package",pkg).put("backend_uid",Process.myUid()).put("android_user",0));
    }
    private void closeGame(String pkg)throws Exception{java.lang.Process p=new ProcessBuilder("/system/bin/am","force-stop","--user","0",pkg).redirectErrorStream(true).start();if(!p.waitFor(15,TimeUnit.SECONDS)){p.destroy();throw new IOException("Không thể đóng game.");}if(p.exitValue()!=0)throw new IOException("Shizuku không thể đóng game; chưa ghi tài nguyên.");}
    private String error(Exception e){try{JSONObject result=new JSONObject().put("success",false).put("message",e.getMessage()==null?"Thao tác chưa hoàn tất.":e.getMessage());if(e instanceof GameDiscovery.Failure){GameDiscovery.Failure f=(GameDiscovery.Failure)e;result.put("error_code",f.code).put("diagnostics",f.diagnostics);}return result.toString();}catch(Exception ignored){return "{\"success\":false}";}}
    private PatchEngine engine(){return new PatchEngine(Base64.getDecoder().decode(BuildTrust.PUBLIC_KEY));}
    @Override public String inspect(String pkg){try{File root=discover(pkg);return engine().inspect(root).put("success",true).put("backend_uid",Process.myUid()).toString();}catch(Exception e){return error(e);}}
    @Override public synchronized String install(String pkg,ParcelFileDescriptor zip,IPatchProgress progress){try(ParcelFileDescriptor.AutoCloseInputStream in=new ParcelFileDescriptor.AutoCloseInputStream(zip)){File root=discover(pkg);closeGame(pkg);return engine().apply(root,in,(s,n)->{try{progress.report(s,n);}catch(Exception ignored){}}).toString();}catch(Exception e){return error(e);}}
    @Override public synchronized String restore(String pkg,IPatchProgress progress){try{File root=discover(pkg);closeGame(pkg);return engine().restore(root,(s,n)->{try{progress.report(s,n);}catch(Exception ignored){}}).toString();}catch(Exception e){return error(e);}}
    @Override public void destroy(){System.exit(0);}
}
