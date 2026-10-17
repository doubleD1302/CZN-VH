package vn.czn.viethoa.czn_patcher;
import org.junit.Test;
import org.json.*;
import java.io.IOException;
import static org.junit.Assert.*;
public class ReleaseRelocationTest {
 String hash="a".repeat(64),old="https://github.com/doubleD1302/CZN-VH/releases/download/android-v1.6.25/app.apk";
 JSONArray listing(String digest,long size,String url,boolean draft)throws Exception {
  return new JSONArray().put(new JSONObject().put("draft",draft).put("prerelease",false).put("assets",new JSONArray().put(new JSONObject().put("name","CNZ_VietHoa_Fanmade.apk").put("size",size).put("digest",digest).put("browser_download_url",url))));
 }
 String moved="https://github.com/doubleD1302/CZN-VH/releases/download/releases-1.0/CNZ_VietHoa_Fanmade.apk";
 @Test public void exactSignedHashCanMoveTagAndName()throws Exception {assertEquals(moved,ReleaseClient.relocatedAsset(listing("sha256:"+hash,10,moved,false),old,10,hash,true));}
 @Test public void currentPublicApkMismatchIsRejected()throws Exception {assertThrows(IOException.class,()->ReleaseClient.relocatedAsset(listing("sha256:"+"b".repeat(64),10,moved,false),old,10,hash,true));}
 @Test public void sizeMismatchRejected()throws Exception {assertThrows(IOException.class,()->ReleaseClient.relocatedAsset(listing("sha256:"+hash,11,moved,false),old,10,hash,true));}
 @Test public void foreignRepositoryRejected()throws Exception {assertThrows(IOException.class,()->ReleaseClient.relocatedAsset(listing("sha256:"+hash,10,moved.replace("CZN-VH","other"),false),old,10,hash,true));}
 @Test public void draftRejected()throws Exception {assertThrows(IOException.class,()->ReleaseClient.relocatedAsset(listing("sha256:"+hash,10,moved,true),old,10,hash,true));}
}
