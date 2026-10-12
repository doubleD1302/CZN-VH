package vn.czn.viethoa.czn_patcher;
import java.io.*;
import java.nio.*;
import java.nio.charset.*;
import org.json.*;
/** Keep the device's exact cache format; only local fingerprint and size may change. */
public final class CacheIdentity {
 public static final class Unsupported extends IOException {
  public final JSONObject diagnostics;
  Unsupported(JSONObject d){super("File nhận diện cache có định dạng chưa hỗ trợ. Chưa cài bản dịch. Bấm Sao chép lỗi để gửi báo cáo.");diagnostics=d;}
 }
 private static String decode(byte[] bytes)throws CharacterCodingException{return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();}
 private static String separator(String s){if(s.contains("\r\n")){String rest=s.replace("\r\n","");return rest.contains("\r")||rest.contains("\n")?null:"\r\n";}return s.contains("\n")&&!s.contains("\r")?"\n":null;}
 private static boolean hash(String s){try{if(!s.matches("[0-9]{1,20}"))return false;Long.parseUnsignedLong(s,10);return true;}catch(Exception e){return false;}}
 private static boolean size(String s){try{return s.matches("[0-9]{1,10}")&&Long.parseLong(s)>0&&Long.parseLong(s)<=Integer.MAX_VALUE;}catch(Exception e){return false;}}
 public static JSONObject describe(byte[] bytes)throws Exception {
  JSONObject d=new JSONObject().put("bytes",bytes.length);String s;
  try{s=decode(bytes);}catch(CharacterCodingException e){return d.put("encoding","unsupported").put("supported",false);}
  String sep=separator(s);String[] lines=s.split("\r\n|\n|\r",-1);String first=lines[0].startsWith("\ufeff")?lines[0].substring(1):lines[0];
  boolean valid=sep!=null&&lines.length>=4&&first.matches("https?://.+")&&hash(lines[2])&&size(lines[3]);
  return d.put("encoding","UTF-8").put("bom",s.startsWith("\ufeff")).put("newline",sep==null?"mixed_or_unknown":sep.equals("\n")?"LF":"CRLF").put("line_count",lines.length).put("url_line_valid",first.matches("https?://.+")).put("hash_line_valid",lines.length>2&&hash(lines[2])).put("size_line_valid",lines.length>3&&size(lines[3])).put("supported",valid);
 }
 public static byte[] update(byte[] existing,byte[] manifest)throws Exception {
  JSONObject d=describe(existing);if(!d.getBoolean("supported"))throw new Unsupported(d);
  String s=decode(existing),sep=separator(s);String[] lines=s.split(java.util.regex.Pattern.quote(sep),-1);
  lines[2]=PatchFormat.unsigned(PatchFormat.xx(manifest));lines[3]=Integer.toString(manifest.length);
  return String.join(sep,lines).getBytes(StandardCharsets.UTF_8);
 }
}
