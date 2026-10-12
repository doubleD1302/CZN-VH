package vn.czn.viethoa.czn_patcher;
import org.junit.*;import static org.junit.Assert.*;import java.nio.charset.StandardCharsets;
public class CacheIdentityTest {
 private static byte[] utf(String s){return s.getBytes(StandardCharsets.UTF_8);}
 @Test public void androidLFIsAcceptedAndPreserved()throws Exception{String original="https://cdn.example/android\nserver-etag\n123\n321\nextra\n";assertEquals(1,original.split("\r\n",-1).length);String result=new String(PatchFormat.identity(utf(original),utf("manifest")),StandardCharsets.UTF_8);assertEquals("https://cdn.example/android\nserver-etag\n"+PatchFormat.unsigned(PatchFormat.xx(utf("manifest")))+"\n8\nextra\n",result);}
 @Test public void windowsCRLFIsPreservedWithoutTrailingNewline()throws Exception{String result=new String(PatchFormat.identity(utf("https://cdn.example/windows\r\netag\r\n123\r\n321"),utf("abc")),StandardCharsets.UTF_8);assertEquals("https://cdn.example/windows\r\netag\r\n"+PatchFormat.unsigned(PatchFormat.xx(utf("abc")))+"\r\n3",result);}
 @Test public void utf8BOMAndUnrelatedFieldsArePreserved()throws Exception{String prefix="\ufeffhttps://cdn.example/path?q=keep\netag: unchanged\n";String result=new String(PatchFormat.identity(utf(prefix+"123\n321\nkeep me\n\n"),utf("abc")),StandardCharsets.UTF_8);assertTrue(result.startsWith(prefix));assertTrue(result.endsWith("\nkeep me\n\n"));}
 @Test public void mixedNewlinesDoNotGetSilentlyNormalized()throws Exception{try{PatchFormat.identity(utf("https://cdn.example\r\netag\n123\n321\n"),utf("a"));fail();}catch(CacheIdentity.Unsupported e){assertFalse(e.diagnostics.getBoolean("supported"));}}
 @Test public void invalidNumericFieldsAreRejected()throws Exception{try{PatchFormat.identity(utf("https://cdn.example\netag\n18446744073709551616\n321\n"),utf("a"));fail();}catch(CacheIdentity.Unsupported expected){}}
 @Test public void invalidUtf8IsNotReplacedWithCorruptedText()throws Exception{assertFalse(CacheIdentity.describe(new byte[]{(byte)0xc3,0x28}).getBoolean("supported"));}
}
