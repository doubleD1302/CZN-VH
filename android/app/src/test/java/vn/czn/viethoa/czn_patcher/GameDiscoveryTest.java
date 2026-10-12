package vn.czn.viethoa.czn_patcher;
import org.junit.*;import static org.junit.Assert.*;import java.io.*;import java.nio.file.*;import java.util.*;import org.json.*;
public class GameDiscoveryTest {
 private File base;
 @Before public void setup()throws Exception{base=Files.createTempDirectory("czn-discover-").toFile();}
 private File data(File root)throws Exception{root.mkdirs();for(String rel:Arrays.asList("manifest.ssra","chunks/lang_ja_b01_0.ssrc","chunks/base_b21_0.ssrc")){File f=new File(root,rel);f.getParentFile().mkdirs();Files.write(f.toPath(),new byte[]{1});}return root;}
 @Test public void findsDeepExternalData()throws Exception{File root=base;for(int i=0;i<10;i++)root=new File(root,"a");data(root);assertEquals(root.getCanonicalPath(),GameDiscovery.find(Arrays.asList(base),new JSONObject()).getCanonicalPath());}
 @Test public void manifestWithoutJapaneseFilesDoesNotPass()throws Exception{Files.write(new File(base,"manifest.ssra").toPath(),new byte[]{1});new File(base,"chunks").mkdir();try{GameDiscovery.find(Arrays.asList(base),new JSONObject());fail();}catch(GameDiscovery.Failure f){assertEquals("DATA_INCOMPLETE",f.code);assertTrue(f.diagnostics.getJSONArray("missing_files").length()>0);}}
 @Test public void multipleDataSetsAreNeverSilentlySelected()throws Exception{data(new File(base,"old"));data(new File(base,"live"));try{GameDiscovery.find(Arrays.asList(base),new JSONObject());fail();}catch(GameDiscovery.Failure f){assertEquals("MULTIPLE_DATA",f.code);}}
 @Test public void emptyPackageProducesActionableReport()throws Exception{try{GameDiscovery.find(Arrays.asList(base),new JSONObject());fail();}catch(GameDiscovery.Failure f){assertEquals("DATA_NOT_FOUND",f.code);assertEquals(base.getAbsolutePath(),f.diagnostics.getJSONArray("searched").getString(0));}}
 @Test public void missingPackageOnFirstVolumeStillFindsSecond()throws Exception{File actual=data(new File(base,"second/files/czn/gameres"));assertEquals(actual.getCanonicalPath(),GameDiscovery.find(Arrays.asList(new File(base,"first"),new File(base,"second")),new JSONObject()).getCanonicalPath());}
}
