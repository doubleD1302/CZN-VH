package vn.czn.viethoa.czn_patcher;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import org.json.*;
/** Read-only discovery below explicitly approved package directories. */
public final class GameDiscovery {
 public static final class Failure extends IOException {
  public final String code; public final JSONObject diagnostics;
  Failure(String code,String message,JSONObject d){super(message);this.code=code;diagnostics=d;}
 }
 private static final class Entry {final File dir;final int depth;Entry(File d,int n){dir=d;depth=n;}}
 public static File find(List<File> bases,JSONObject d)throws Exception {
  JSONArray attempts=new JSONArray(),missing=new JSONArray(),denied=new JSONArray();d.put("searched",attempts).put("missing_files",missing).put("unreadable",denied);
  Set<String> visited=new HashSet<>();Map<String,File> found=new LinkedHashMap<>();int count=0;boolean limited=false;
  for(File base:bases){
   attempts.put(base.getAbsolutePath());String canonical=base.getCanonicalPath();ArrayDeque<Entry> queue=new ArrayDeque<>();queue.add(new Entry(base,0));
   while(!queue.isEmpty()){
    Entry entry=queue.remove();File dir=entry.dir;String real=dir.getCanonicalPath();
    if(!real.equals(canonical)&&!real.startsWith(canonical+File.separator))continue;
    if(!visited.add(real))continue;if(++count>5000){limited=true;break;}
    try(DirectoryStream<Path> children=Files.newDirectoryStream(dir.toPath())){
     File manifest=new File(dir,"manifest.ssra");
     if(manifest.isFile()){
      List<String> absent=new ArrayList<>();
      for(String rel:Arrays.asList("manifest.ssra","chunks/lang_ja_b01_0.ssrc","chunks/base_b21_0.ssrc")){
       File f=new File(dir,rel);if(!f.isFile())absent.add(rel);else try(InputStream ignored=new FileInputStream(f)){}catch(IOException e){denied.put(f.getAbsolutePath());absent.add(rel+" (không đọc được)");}
      }
      if(absent.isEmpty())found.put(real,dir);else missing.put(new JSONObject().put("root",real).put("files",new JSONArray(absent)));
     }
     if(entry.depth<12)for(Path child:children){String name=child.getFileName().toString();if(!name.equals("chunks")&&!name.equals(".czn_viethoa")&&Files.isDirectory(child,LinkOption.NOFOLLOW_LINKS))queue.add(new Entry(child.toFile(),entry.depth+1));}
    }catch(NoSuchFileException e){}catch(AccessDeniedException|SecurityException e){denied.put(dir.getAbsolutePath());}catch(IOException e){denied.put(dir.getAbsolutePath());}
   }
  }
  d.put("directories_checked",count).put("scan_limit",limited);
  if(found.size()==1)return found.values().iterator().next();
  if(found.size()>1)throw new Failure("MULTIPLE_DATA","Có nhiều bộ dữ liệu CZN. Gửi báo cáo để xác minh bộ đang dùng trước khi cài.",d);
  if(missing.length()>0)throw new Failure("DATA_INCOMPLETE","Đã thấy dữ liệu nhưng thiếu hoặc không đọc được gói tiếng Nhật/cốt truyện. Chọn ngôn ngữ văn bản 日本語 trong CZN, chờ tải xong rồi bấm Kiểm tra lại.",d);
  if(denied.length()>0)throw new Failure("STORAGE_DENIED","Shizuku không đọc được thư mục game. Xiaomi: bật Gỡ lỗi USB (Cài đặt bảo mật), khởi động lại Shizuku và cấp quyền cho app. Game và patcher cần ở cùng hồ sơ Android; không dùng Không gian thứ hai/Ứng dụng kép.",d);
  throw new Failure(limited?"SCAN_LIMIT":"DATA_NOT_FOUND","Chưa thấy dữ liệu JP tại vùng lưu trữ truy cập được. Mở CZN, chọn 日本語, chờ tải xong rồi bấm Kiểm tra lại. Nếu vẫn lỗi, gửi Sao chép báo cáo. Dữ liệu riêng trong /data/user không thể vá qua Shizuku không root.",d);
 }
}
