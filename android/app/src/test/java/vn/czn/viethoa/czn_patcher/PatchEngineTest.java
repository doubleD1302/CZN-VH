package vn.czn.viethoa.czn_patcher;
import org.junit.*;import static org.junit.Assert.*;import org.json.*;
import java.io.*;import java.nio.*;import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.security.*;import java.util.*;import java.util.zip.*;

public class PatchEngineTest {
    private File root;private KeyPair keys;private byte[] zip;private Map<String,String> original;
    private static byte[] utf(String s){return s.getBytes(StandardCharsets.UTF_8);}
    private static void putString(ByteBuffer b,int p,String s){b.position(p);b.put(utf(s));b.put((byte)0);}
    @Before public void setup()throws Exception{
        root=Files.createTempDirectory("czn-android-fixture-").toFile();keys=KeyPairGenerator.getInstance("RSA").generateKeyPair();String text="text/ja/text.db",story=PatchFormat.STORY;byte[] st=utf(text+"\0"+story+"\0");int so=232,gp=so+st.length,names=gp+64,fh=names+13;ByteBuffer b=ByteBuffer.allocate(fh+32).order(ByteOrder.LITTLE_ENDIAN);b.put(utf("SSRA")).putInt(4).putInt(88).putInt(2).putInt(2).putInt(0).putLong(so).putLong(st.length).putLong(88).putLong(152).putLong(0);b.position(so);b.put(st);b.position(gp);b.put(utf("GRPS")).putInt(2).putInt(13).putInt(0);b.putShort(gp+16,(short)0);b.putInt(gp+20,0);b.putShort(gp+40,(short)12);b.putInt(gp+44,8);putString(b,names,"lang_ja");putString(b,names+8,"base");b.position(fh);b.put(utf("FHSH")).putInt(2).putInt(1).putInt(0);JSONArray patches=new JSONArray();Map<String,byte[]> payloads=new LinkedHashMap<>();
        for(int i=0;i<2;i++){int gid=i==0?0:12,cid=i==0?1:21;String chunk=i==0?"lang_ja_b01_0.ssrc":"base_b21_0.ssrc";byte[] src=utf("0123456789abcdef0123456789abcdef");byte[] slot=Arrays.copyOfRange(src,8,24);long h=PatchFormat.xx(src);ByteBuffer whole=ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN);whole.put(src).put(utf("SSRC")).putInt(cid).putLong(h);PatchFormat.write(PatchFormat.safe(root,"chunks/"+chunk),whole.array());int c=88+i*32;b.putInt(c,cid).putShort(c+4,(short)gid).putLong(c+8,32).putLong(c+16,48).putLong(c+24,h);int f=152+i*40;b.putLong(f+8,8).putInt(f+16,16).putInt(f+20,24).putInt(f+28,i==0?0:text.length()+1).put(f+32,(byte)1).putShort(f+34,(short)gid);b.putLong(fh+16+i*8,123+i);String payload=i==0?"payload/text.zst":"payload/story.zst";byte[] data=utf("VIET"+i);payloads.put(payload,data);patches.put(new JSONObject().put("file",i==0?text:story).put("payload",payload).put("source_cs",16).put("source_us",24).put("source_sha256",PatchFormat.sha(new ByteArrayInputStream(slot))).put("source_xxh64",Long.toHexString(123+i)).put("target_cs",data.length).put("target_us",25).put("target_sha256",PatchFormat.sha(new ByteArrayInputStream(data))).put("target_xxh64","abcd"));}
        PatchFormat.write(new File(root,"manifest.ssra"),b.array());PatchFormat.write(new File(root,"manifest.ssra.prev"),b.array());PatchFormat.write(new File(root,"manifest.ssra.etag"),utf("https://cdn.example/android\r\nserver-etag\r\n123\r\n321\r\n"));JSONObject desc=new JSONObject().put("schema",2).put("min_patcher",10400).put("version_code",10400).put("version","1.4.0").put("patches",patches);byte[] raw=utf(desc.toString());Signature s=Signature.getInstance("SHA256withRSA");s.initSign(keys.getPrivate());s.update(raw);String envelope=new JSONObject().put("signed",Base64.getEncoder().encodeToString(raw)).put("signature",Base64.getEncoder().encodeToString(s.sign())).toString();ByteArrayOutputStream out=new ByteArrayOutputStream();try(ZipOutputStream z=new ZipOutputStream(out)){z.putNextEntry(new ZipEntry("release.json"));z.write(utf(envelope));z.closeEntry();for(Map.Entry<String,byte[]> e:payloads.entrySet()){z.putNextEntry(new ZipEntry(e.getKey()));z.write(e.getValue());z.closeEntry();}}zip=out.toByteArray();original=hashes();
    }
    private Map<String,String> hashes()throws Exception{Map<String,String> h=new TreeMap<>();for(String p:PatchFormat.ALLOWED){File f=PatchFormat.safe(root,p);if(f.exists())h.put(p,PatchFormat.sha(f));}return h;}
    private PatchEngine engine(){return new PatchEngine(keys.getPublic().getEncoded());}
    @Test public void patchOnlyChangesSlotsAndRestoreReturnsAllFive()throws Exception{
        byte[] before=PatchFormat.bytes(new File(root,"chunks/base_b21_0.ssrc"),1024);assertTrue(engine().apply(root,new ByteArrayInputStream(zip),(s,n)->{}).getBoolean("success"));byte[] after=PatchFormat.bytes(new File(root,"chunks/base_b21_0.ssrc"),1024);assertArrayEquals(Arrays.copyOfRange(before,0,8),Arrays.copyOfRange(after,0,8));assertArrayEquals(Arrays.copyOfRange(before,24,40),Arrays.copyOfRange(after,24,40));assertTrue(new String(PatchFormat.bytes(new File(root,"manifest.ssra.etag"),1024),StandardCharsets.UTF_8).startsWith("https://cdn.example/android\r\nserver-etag\r\n"));assertEquals(5,engine().restore(root,(s,n)->{}).getInt("restored_count"));assertEquals(original,hashes());
    }
    @Test public void commitFailureRollsBackEveryFile()throws Exception{PatchEngine e=engine();e.hook=(i,p)->{if(i==2)throw new IOException("simulated write failure");};try{e.apply(root,new ByteArrayInputStream(zip),(s,n)->{});fail();}catch(IOException expected){}assertEquals(original,hashes());assertFalse(new File(root,".czn_viethoa/journal.json").exists());}
    @Test public void untrustedSignatureNeverWritesTargets()throws Exception{try{new PatchEngine(KeyPairGenerator.getInstance("RSA").generateKeyPair().getPublic().getEncoded()).apply(root,new ByteArrayInputStream(zip),(s,n)->{});fail();}catch(Exception expected){}assertEquals(original,hashes());}
    @Test public void externalGameUpdatePreventsStaleRestore()throws Exception{engine().apply(root,new ByteArrayInputStream(zip),(s,n)->{});PatchFormat.write(new File(root,"manifest.ssra"),utf("GAME UPDATE"));Map<String,String> changed=hashes();try{engine().restore(root,(s,n)->{});fail();}catch(IOException expected){}assertEquals(changed,hashes());}
    @Test public void corruptedBackupPreventsAllRestoreWrites()throws Exception{engine().apply(root,new ByteArrayInputStream(zip),(s,n)->{});JSONObject state=new JSONObject(new String(PatchFormat.bytes(new File(root,".czn_viethoa/state.json"),262144),StandardCharsets.UTF_8));File bak=new File(root,".czn_viethoa/baselines/"+state.getString("baseline")+"/chunks/base_b21_0.ssrc");PatchFormat.write(bak,utf("CORRUPT"));Map<String,String> installed=hashes();try{engine().restore(root,(s,n)->{});fail();}catch(IOException expected){}assertEquals(installed,hashes());}
    @Test public void interruptedCommitIsRecoveredFromJournal()throws Exception{PatchEngine e=engine();e.hook=(i,p)->{if(i==2)throw new AssertionError("simulated process death");};try{e.apply(root,new ByteArrayInputStream(zip),(s,n)->{});fail();}catch(AssertionError expected){}assertTrue(new File(root,".czn_viethoa/journal.json").exists());engine().recover(root);assertEquals(original,hashes());assertFalse(new File(root,".czn_viethoa/state.json").exists());}
    @Test public void platformManifestAndUnrelatedChunkBytesArePreserved()throws Exception{
        File chunk=new File(root,"chunks/base_b21_0.ssrc");byte[] data=PatchFormat.bytes(chunk,1024);data[2]=99;long checksum=PatchFormat.xx(Arrays.copyOfRange(data,0,32));ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).putLong(40,checksum);PatchFormat.write(chunk,data);
        byte[] manifest=PatchFormat.bytes(new File(root,"manifest.ssra"),1024);ByteBuffer b=ByteBuffer.wrap(manifest).order(ByteOrder.LITTLE_ENDIAN);b.putInt(20,77);b.putLong(88+32+24,checksum);PatchFormat.write(new File(root,"manifest.ssra"),manifest);PatchFormat.write(new File(root,"manifest.ssra.prev"),manifest);
        engine().apply(root,new ByteArrayInputStream(zip),(t,n)->{});byte[] patched=PatchFormat.bytes(new File(root,"manifest.ssra"),1024);assertEquals(77,ByteBuffer.wrap(patched).order(ByteOrder.LITTLE_ENDIAN).getInt(20));assertEquals(99,PatchFormat.bytes(chunk,1024)[2]);
        boolean[] allowed=new boolean[manifest.length];for(int i=0;i<2;i++){for(int n=88+i*32+24;n<88+i*32+32;n++)allowed[n]=true;for(int n=152+i*40+16;n<152+i*40+24;n++)allowed[n]=true;allowed[152+i*40+32]=true;for(int n=manifest.length-16+i*8;n<manifest.length-16+(i+1)*8;n++)allowed[n]=true;}for(int i=0;i<manifest.length;i++)if(!allowed[i])assertEquals("Manifest byte "+i,manifest[i],patched[i]);
    }
    private byte[] alteredZip(boolean extra,boolean corrupt)throws Exception{ByteArrayOutputStream out=new ByteArrayOutputStream();try(ZipInputStream in=new ZipInputStream(new ByteArrayInputStream(zip));ZipOutputStream z=new ZipOutputStream(out)){ZipEntry e;while((e=in.getNextEntry())!=null){ByteArrayOutputStream part=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)part.write(b,0,n);byte[] data=part.toByteArray();if(corrupt&&e.getName().equals("payload/text.zst"))data[0]^=1;z.putNextEntry(new ZipEntry(e.getName()));z.write(data);z.closeEntry();}if(extra){z.putNextEntry(new ZipEntry("chunks/base_b99_0.ssrc"));z.write(utf("forbidden"));z.closeEntry();}}return out.toByteArray();}
    @Test public void unknownZipEntryIsRejectedBeforeWriting()throws Exception{try{engine().apply(root,new ByteArrayInputStream(alteredZip(true,false)),(s,n)->{});fail();}catch(IOException expected){}assertEquals(original,hashes());}
    @Test public void corruptPayloadIsRejectedBeforeWriting()throws Exception{try{engine().apply(root,new ByteArrayInputStream(alteredZip(false,true)),(s,n)->{});fail();}catch(IOException expected){}assertEquals(original,hashes());}

    @Test public void androidLFCacheInstallAndRestoreAreBothVerified()throws Exception{
        File cache=new File(root,"manifest.ssra.etag");String old="https://cdn.example/android\nserver-etag\n123\n321\n";PatchFormat.write(cache,utf(old));Map<String,String> before=hashes();
        assertTrue(engine().apply(root,new ByteArrayInputStream(zip),(t,n)->{}).getBoolean("success"));
        JSONObject state=engine().inspect(root);assertTrue(state.getBoolean("files_match"));assertEquals("LF",state.getJSONObject("cache_identity").getString("newline"));
        assertTrue(new String(PatchFormat.bytes(cache,1024),StandardCharsets.UTF_8).startsWith("https://cdn.example/android\nserver-etag\n"));
        assertEquals(5,engine().restore(root,(t,n)->{}).getInt("restored_count"));assertEquals(before,hashes());
    }
    @Test public void unsupportedCacheNeverCommitsAnyGameTarget()throws Exception{
        PatchFormat.write(new File(root,"manifest.ssra.etag"),utf("unsupported cache"));Map<String,String> before=hashes();
        try{engine().apply(root,new ByteArrayInputStream(zip),(t,n)->{});fail();}catch(CacheIdentity.Unsupported expected){}
        assertEquals(before,hashes());assertFalse(new File(root,".czn_viethoa/state.json").exists());assertFalse(new File(root,".czn_viethoa/journal.json").exists());
    }

    @Test public void patchThreeSlotsSupportsSubStory()throws Exception{
        File threeRoot=Files.createTempDirectory("czn-android-three-").toFile();
        String text="text/ja/text.db",story=PatchFormat.STORY,subStory=PatchFormat.SUB_STORY;
        byte[] st=utf(text+"\0"+story+"\0"+subStory+"\0");
        int so=304,gp=so+st.length,names=gp+64,fh=names+13;
        ByteBuffer b=ByteBuffer.allocate(fh+40).order(ByteOrder.LITTLE_ENDIAN);
        b.put(utf("SSRA")).putInt(4).putInt(88).putInt(3).putInt(3).putInt(0).putLong(so).putLong(st.length).putLong(88).putLong(184).putLong(0);
        b.position(so);b.put(st);
        b.position(gp);b.put(utf("GRPS")).putInt(2).putInt(13).putInt(0);
        b.putShort(gp+16,(short)0);b.putInt(gp+20,0);b.putShort(gp+40,(short)12);b.putInt(gp+44,8);
        putString(b,names,"lang_ja");putString(b,names+8,"base");
        b.position(fh);b.put(utf("FHSH")).putInt(3).putInt(1).putInt(0);
        JSONArray patches=new JSONArray();Map<String,byte[]> payloads=new LinkedHashMap<>();
        String[] files=new String[]{text,story,subStory};
        String[] chunks=new String[]{"lang_ja_b01_0.ssrc","base_b21_0.ssrc","base_b17_0.ssrc"};
        int[] cids=new int[]{1,21,17};
        int[] gids=new int[]{0,12,12};
        String[] payloadNames=new String[]{"payload/text.zst","payload/story.zst","payload/sub_story.zst"};
        int stOffset=0;
        for(int i=0;i<3;i++){
            byte[] src=utf("0123456789abcdef0123456789abcdef");
            byte[] slot=Arrays.copyOfRange(src,8,24);
            long h=PatchFormat.xx(src);
            ByteBuffer whole=ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN);
            whole.put(src).put(utf("SSRC")).putInt(cids[i]).putLong(h);
            PatchFormat.write(PatchFormat.safe(threeRoot,"chunks/"+chunks[i]),whole.array());
            int c=88+i*32;
            b.putInt(c,cids[i]).putShort(c+4,(short)gids[i]).putLong(c+8,32).putLong(c+16,48).putLong(c+24,h);
            int f=184+i*40;
            long offset=i==1?40:8;
            b.putLong(f+8,offset).putInt(f+16,16).putInt(f+20,24).putInt(f+28,stOffset).put(f+32,(byte)1).putShort(f+34,(short)gids[i]);
            stOffset+=files[i].length()+1;
            b.putLong(fh+16+i*8,123+i);
            byte[] data=utf("VIET3_"+i);
            payloads.put(payloadNames[i],data);
            patches.put(new JSONObject().put("file",files[i]).put("payload",payloadNames[i]).put("source_cs",16).put("source_us",24).put("source_sha256",PatchFormat.sha(new ByteArrayInputStream(slot))).put("source_xxh64",Long.toHexString(123+i)).put("target_cs",data.length).put("target_us",25).put("target_sha256",PatchFormat.sha(new ByteArrayInputStream(data))).put("target_xxh64","abcd"));
        }
        PatchFormat.write(new File(threeRoot,"manifest.ssra"),b.array());
        PatchFormat.write(new File(threeRoot,"manifest.ssra.prev"),b.array());
        PatchFormat.write(new File(threeRoot,"manifest.ssra.etag"),utf("https://cdn.example/android\r\nserver-etag\r\n123\r\n321\r\n"));
        JSONObject desc=new JSONObject().put("schema",2).put("min_patcher",10400).put("version_code",10630).put("version","1.6.30").put("patches",patches);
        byte[] raw=utf(desc.toString());
        Signature s=Signature.getInstance("SHA256withRSA");s.initSign(keys.getPrivate());s.update(raw);
        String envelope=new JSONObject().put("signed",Base64.getEncoder().encodeToString(raw)).put("signature",Base64.getEncoder().encodeToString(s.sign())).toString();
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){
            z.putNextEntry(new ZipEntry("release.json"));z.write(utf(envelope));z.closeEntry();
            for(Map.Entry<String,byte[]> e:payloads.entrySet()){
                z.putNextEntry(new ZipEntry(e.getKey()));z.write(e.getValue());z.closeEntry();
            }
        }
        JSONObject result=engine().apply(threeRoot,new ByteArrayInputStream(out.toByteArray()),(stg,n)->{});
        assertTrue(result.getBoolean("success"));
        assertEquals("1.6.30",result.getString("version"));
        assertEquals(10630,result.getInt("version_code"));
        assertEquals(6,engine().restore(threeRoot,(stg,n)->{}).getInt("restored_count"));
    }

    @Test public void patchThreeSlotsWithoutSubStoryChunkSucceedsGracefully()throws Exception{
        File optRoot=Files.createTempDirectory("czn-android-opt-").toFile();
        String text="text/ja/text.db",story=PatchFormat.STORY,subStory=PatchFormat.SUB_STORY;
        byte[] st=utf(text+"\0"+story+"\0"+subStory+"\0");
        int so=304,gp=so+st.length,names=gp+64,fh=names+13;
        ByteBuffer b=ByteBuffer.allocate(fh+40).order(ByteOrder.LITTLE_ENDIAN);
        b.put(utf("SSRA")).putInt(4).putInt(88).putInt(3).putInt(3).putInt(0).putLong(so).putLong(st.length).putLong(88).putLong(184).putLong(0);
        b.position(so);b.put(st);
        b.position(gp);b.put(utf("GRPS")).putInt(2).putInt(13).putInt(0);
        b.putShort(gp+16,(short)0);b.putInt(gp+20,0);b.putShort(gp+40,(short)12);b.putInt(gp+44,8);
        putString(b,names,"lang_ja");putString(b,names+8,"base");
        b.position(fh);b.put(utf("FHSH")).putInt(3).putInt(1).putInt(0);
        JSONArray patches=new JSONArray();Map<String,byte[]> payloads=new LinkedHashMap<>();
        String[] files=new String[]{text,story,subStory};
        String[] chunks=new String[]{"lang_ja_b01_0.ssrc","base_b21_0.ssrc","base_b17_0.ssrc"};
        int[] cids=new int[]{1,21,17};
        int[] gids=new int[]{0,12,12};
        String[] payloadNames=new String[]{"payload/text.zst","payload/story.zst","payload/sub_story.zst"};
        int stOffset=0;
        for(int i=0;i<3;i++){
            byte[] src=utf("0123456789abcdef0123456789abcdef");
            byte[] slot=Arrays.copyOfRange(src,8,24);
            long h=PatchFormat.xx(src);
            if(i<2){
                ByteBuffer whole=ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN);
                whole.put(src).put(utf("SSRC")).putInt(cids[i]).putLong(h);
                PatchFormat.write(PatchFormat.safe(optRoot,"chunks/"+chunks[i]),whole.array());
            }
            int c=88+i*32;
            b.putInt(c,cids[i]).putShort(c+4,(short)gids[i]).putLong(c+8,32).putLong(c+16,48).putLong(c+24,h);
            int f=184+i*40;
            long offset=i==1?40:8;
            b.putLong(f+8,offset).putInt(f+16,16).putInt(f+20,24).putInt(f+28,stOffset).put(f+32,(byte)1).putShort(f+34,(short)gids[i]);
            stOffset+=files[i].length()+1;
            b.putLong(fh+16+i*8,123+i);
            byte[] data=utf("VIET_OPT_"+i);
            payloads.put(payloadNames[i],data);
            patches.put(new JSONObject().put("file",files[i]).put("payload",payloadNames[i]).put("source_cs",16).put("source_us",24).put("source_sha256",PatchFormat.sha(new ByteArrayInputStream(slot))).put("source_xxh64",Long.toHexString(123+i)).put("target_cs",data.length).put("target_us",25).put("target_sha256",PatchFormat.sha(new ByteArrayInputStream(data))).put("target_xxh64","abcd"));
        }
        PatchFormat.write(new File(optRoot,"manifest.ssra"),b.array());
        PatchFormat.write(new File(optRoot,"manifest.ssra.prev"),b.array());
        PatchFormat.write(new File(optRoot,"manifest.ssra.etag"),utf("https://cdn.example/android\r\nserver-etag\r\n123\r\n321\r\n"));
        JSONObject desc=new JSONObject().put("schema",2).put("min_patcher",10400).put("version_code",10630).put("version","1.6.30").put("patches",patches);
        byte[] raw=utf(desc.toString());
        Signature s=Signature.getInstance("SHA256withRSA");s.initSign(keys.getPrivate());s.update(raw);
        String envelope=new JSONObject().put("signed",Base64.getEncoder().encodeToString(raw)).put("signature",Base64.getEncoder().encodeToString(s.sign())).toString();
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){
            z.putNextEntry(new ZipEntry("release.json"));z.write(utf(envelope));z.closeEntry();
            for(Map.Entry<String,byte[]> e:payloads.entrySet()){
                z.putNextEntry(new ZipEntry(e.getKey()));z.write(e.getValue());z.closeEntry();
            }
        }
        JSONObject result=engine().apply(optRoot,new ByteArrayInputStream(out.toByteArray()),(stg,n)->{});
        assertTrue(result.getBoolean("success"));
        assertFalse(result.getBoolean("sub_story_applied"));
        assertEquals("1.6.30",result.getString("version"));
        assertFalse(new File(optRoot,"chunks/base_b17_0.ssrc").exists());
        byte[] srcSub=utf("0123456789abcdef0123456789abcdef");
        long hSub=PatchFormat.xx(srcSub);
        ByteBuffer wholeSub=ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN);
        wholeSub.put(srcSub).put(utf("SSRC")).putInt(17).putLong(hSub);
        PatchFormat.write(PatchFormat.safe(optRoot,"chunks/base_b17_0.ssrc"),wholeSub.array());
        JSONObject result2=engine().apply(optRoot,new ByteArrayInputStream(out.toByteArray()),(stg,n)->{});
        assertTrue(result2.getBoolean("success"));
        assertTrue(result2.getBoolean("sub_story_applied"));
        assertEquals(6,engine().restore(optRoot,(stg,n)->{}).getInt("restored_count"));
    }

    @Test public void patchWithMinPatcher10700Succeeds()throws Exception{
        File r=Files.createTempDirectory("czn-minpatcher-pass-").toFile();
        String text="text/ja/text.db",story=PatchFormat.STORY;
        byte[] st=utf(text+"\0"+story+"\0");
        int so=264,gp=so+st.length,names=gp+64,fh=names+13;
        ByteBuffer b=ByteBuffer.allocate(fh+32).order(ByteOrder.LITTLE_ENDIAN);
        b.put(utf("SSRA")).putInt(4).putInt(88).putInt(2).putInt(2).putInt(0).putLong(so).putLong(st.length).putLong(88).putLong(184).putLong(0);
        b.position(so);b.put(st);
        b.position(gp);b.put(utf("GRPS")).putInt(2).putInt(13).putInt(0);
        b.putShort(gp+16,(short)0);b.putInt(gp+20,0);b.putShort(gp+40,(short)12);b.putInt(gp+44,8);
        putString(b,names,"lang_ja");putString(b,names+8,"base");
        b.position(fh);b.put(utf("FHSH")).putInt(2).putInt(1).putInt(0);
        Map<String,byte[]> payloads=new HashMap<>();JSONArray patches=new JSONArray();
        String[] files=new String[]{text,story};String[] chunks=new String[]{"lang_ja_b01_0.ssrc","base_b21_0.ssrc"};int[] cids=new int[]{1,21};int[] gids=new int[]{0,12};String[] payloadNames=new String[]{"payload/text.zst","payload/story.zst"};
        int stOffset=0;
        for(int i=0;i<2;i++){
            byte[] src=utf("0123456789abcdef0123456789abcdef");byte[] slot=Arrays.copyOfRange(src,8,24);long h=PatchFormat.xx(src);
            ByteBuffer whole=ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN);whole.put(src).put(utf("SSRC")).putInt(cids[i]).putLong(h);
            PatchFormat.write(PatchFormat.safe(r,"chunks/"+chunks[i]),whole.array());
            int c=88+i*32;b.putInt(c,cids[i]).putShort(c+4,(short)gids[i]).putLong(c+8,32).putLong(c+16,48).putLong(c+24,h);
            int f=184+i*40;long offset=8;b.putLong(f+8,offset).putInt(f+16,16).putInt(f+20,24).putInt(f+28,stOffset).put(f+32,(byte)1).putShort(f+34,(short)gids[i]);
            stOffset+=files[i].length()+1;b.putLong(fh+16+i*8,123+i);
            byte[] data=utf("VIET_"+i);payloads.put(payloadNames[i],data);
            patches.put(new JSONObject().put("file",files[i]).put("payload",payloadNames[i]).put("source_cs",16).put("source_us",24).put("source_sha256",PatchFormat.sha(new ByteArrayInputStream(slot))).put("source_xxh64",Long.toHexString(123+i)).put("target_cs",data.length).put("target_us",25).put("target_sha256",PatchFormat.sha(new ByteArrayInputStream(data))).put("target_xxh64","abcd"));
        }
        PatchFormat.write(new File(r,"manifest.ssra"),b.array());PatchFormat.write(new File(r,"manifest.ssra.prev"),b.array());PatchFormat.write(new File(r,"manifest.ssra.etag"),utf("https://cdn.example/android\r\nserver-etag\r\n123\r\n321\r\n"));
        JSONObject desc=new JSONObject().put("schema",2).put("min_patcher",10700).put("version_code",10701).put("version","1.7.0").put("patches",patches);
        byte[] raw=utf(desc.toString());Signature s=Signature.getInstance("SHA256withRSA");s.initSign(keys.getPrivate());s.update(raw);
        String envelope=new JSONObject().put("signed",Base64.getEncoder().encodeToString(raw)).put("signature",Base64.getEncoder().encodeToString(s.sign())).toString();
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){
            z.putNextEntry(new ZipEntry("release.json"));z.write(utf(envelope));z.closeEntry();
            for(Map.Entry<String,byte[]> e:payloads.entrySet()){z.putNextEntry(new ZipEntry(e.getKey()));z.write(e.getValue());z.closeEntry();}
        }
        JSONObject res=engine().apply(r,new ByteArrayInputStream(out.toByteArray()),(stg,n)->{});
        assertTrue(res.getBoolean("success"));
        assertEquals("1.7.0",res.getString("version"));
    }

    @Test public void patchWithFutureMinPatcherIsRejected()throws Exception{
        File r=Files.createTempDirectory("czn-minpatcher-fail-").toFile();
        JSONArray patches=new JSONArray();
        patches.put(new JSONObject().put("file","text/ja/text.db").put("payload","payload/text.zst").put("source_cs",16).put("source_us",24).put("source_sha256","abc").put("source_xxh64","123").put("target_cs",5).put("target_us",25).put("target_sha256","def").put("target_xxh64","abcd"));
        patches.put(new JSONObject().put("file",PatchFormat.STORY).put("payload","payload/story.zst").put("source_cs",16).put("source_us",24).put("source_sha256","abc").put("source_xxh64","124").put("target_cs",5).put("target_us",25).put("target_sha256","def").put("target_xxh64","abcd"));
        JSONObject desc=new JSONObject().put("schema",2).put("min_patcher",PatchEngine.CURRENT_PATCHER_CODE+1).put("version_code",10701).put("version","1.7.0").put("patches",patches);
        byte[] raw=utf(desc.toString());Signature s=Signature.getInstance("SHA256withRSA");s.initSign(keys.getPrivate());s.update(raw);
        String envelope=new JSONObject().put("signed",Base64.getEncoder().encodeToString(raw)).put("signature",Base64.getEncoder().encodeToString(s.sign())).toString();
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){
            z.putNextEntry(new ZipEntry("release.json"));z.write(utf(envelope));z.closeEntry();
            z.putNextEntry(new ZipEntry("payload/text.zst"));z.write(utf("test"));z.closeEntry();
            z.putNextEntry(new ZipEntry("payload/story.zst"));z.write(utf("test"));z.closeEntry();
        }
        try{
            engine().apply(r,new ByteArrayInputStream(out.toByteArray()),(stg,n)->{});
            fail("Expected exception for future min_patcher");
        }catch(IOException e){
            assertTrue(e.getMessage().contains("Gói cần phiên bản ứng dụng mới hơn."));
        }
    }

    @Test public void diskSpaceDeduplicationAndBaselineMultiplierAreVerified()throws Exception{
        JSONObject firstResult=engine().apply(root,new ByteArrayInputStream(zip),(s,n)->{});
        assertTrue(firstResult.getBoolean("success"));
        JSONObject state=new JSONObject(new String(PatchFormat.bytes(new File(root,".czn_viethoa/state.json"),262144),StandardCharsets.UTF_8));
        File base=new File(root,".czn_viethoa/baselines/"+state.getString("baseline")+"/chunks/base_b21_0.ssrc");
        assertTrue("Baseline backup phải tồn tại sau lần cài đầu",base.exists());
        
        // Tạo gói v1.4.1 kế thừa cùng baseline để kiểm tra hệ số 2x khi baseline đã tồn tại
        JSONObject desc=new JSONObject().put("schema",2).put("min_patcher",10400).put("version_code",10401).put("version","1.4.1");
        JSONArray patches=new JSONArray();
        byte[] srcText=PatchFormat.bytes(new File(root,".czn_viethoa/baselines/"+state.getString("baseline")+"/chunks/lang_ja_b01_0.ssrc"),1024);
        byte[] srcStory=PatchFormat.bytes(base,1024);
        byte[] slotText=Arrays.copyOfRange(srcText,8,24);
        byte[] slotStory=Arrays.copyOfRange(srcStory,8,24);
        byte[] data0=utf("VIET_UPDATED_0"),data1=utf("VIET_UPDATED_1");
        patches.put(new JSONObject().put("file","text/ja/text.db").put("payload","payload/text.zst").put("source_cs",16).put("source_us",24).put("source_sha256",PatchFormat.sha(new ByteArrayInputStream(slotText))).put("source_xxh64",Long.toHexString(123)).put("target_cs",data0.length).put("target_us",25).put("target_sha256",PatchFormat.sha(new ByteArrayInputStream(data0))).put("target_xxh64","abcd"));
        patches.put(new JSONObject().put("file",PatchFormat.STORY).put("payload","payload/story.zst").put("source_cs",16).put("source_us",24).put("source_sha256",PatchFormat.sha(new ByteArrayInputStream(slotStory))).put("source_xxh64",Long.toHexString(124)).put("target_cs",data1.length).put("target_us",25).put("target_sha256",PatchFormat.sha(new ByteArrayInputStream(data1))).put("target_xxh64","abcd"));
        desc.put("patches",patches);
        byte[] raw=utf(desc.toString());Signature s=Signature.getInstance("SHA256withRSA");s.initSign(keys.getPrivate());s.update(raw);
        String envelope=new JSONObject().put("signed",Base64.getEncoder().encodeToString(raw)).put("signature",Base64.getEncoder().encodeToString(s.sign())).toString();
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){
            z.putNextEntry(new ZipEntry("release.json"));z.write(utf(envelope));z.closeEntry();
            z.putNextEntry(new ZipEntry("payload/text.zst"));z.write(data0);z.closeEntry();
            z.putNextEntry(new ZipEntry("payload/story.zst"));z.write(data1);z.closeEntry();
        }
        JSONObject updateResult=engine().apply(root,new ByteArrayInputStream(out.toByteArray()),(stg,n)->{});
        assertTrue(updateResult.getBoolean("success"));
        assertEquals("1.4.1",updateResult.getString("version"));
        assertEquals(5,engine().restore(root,(stg,n)->{}).getInt("restored_count"));
        assertEquals(original,hashes());
    }

    @Test public void realNativeReadbackFixture()throws Exception{
        String baseline=System.getenv("CZN_TEST_BASELINE"),bundle=System.getenv("CZN_TEST_BUNDLE"),output=System.getenv("CZN_TEST_OUTPUT");Assume.assumeNotNull(baseline,bundle,output);File testRoot=new File(output);assertFalse("Do not overwrite previous evidence",testRoot.exists());testRoot.mkdirs();for(String rel:PatchFormat.ALLOWED){File f=new File(baseline,rel);if(f.exists()){File t=PatchFormat.safe(testRoot,rel);t.getParentFile().mkdirs();Files.copy(f.toPath(),t.toPath());}}PatchEngine real=new PatchEngine(Base64.getDecoder().decode(BuildTrust.PUBLIC_KEY));try(InputStream in=new FileInputStream(bundle)){assertTrue(real.apply(testRoot,in,(s,n)->{}).getBoolean("success"));}System.out.println("Native verification output: "+testRoot);
    }
}
