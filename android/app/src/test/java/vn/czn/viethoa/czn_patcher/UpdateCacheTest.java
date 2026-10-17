package vn.czn.viethoa.czn_patcher;

import org.junit.*;
import org.junit.rules.TemporaryFolder;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.Assert.*;

public class UpdateCacheTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();
    private File files, cache, updates;
    private static String hash(char c) { return String.valueOf(c).repeat(64); }
    private static String apk(char c) { return hash(c)+".apk"; }
    private static String patch(char c) { return hash(c)+".cznpatch"; }
    @Before public void setUp() throws Exception {
        files=temp.newFolder("files");cache=temp.newFolder("cache");updates=UpdateCache.directory(files);
    }
    private File put(File dir,String name) throws Exception {
        File f=new File(dir,name);Files.write(f.toPath(),new byte[]{1,2,3,4});return f;
    }
    private void prune(String app,String patch,Set<String> useful,Set<String> held) throws Exception {
        UpdateCache.prune(files,cache,app,patch,useful,held);
    }
    private void prune(String app,String patch,String... useful) throws Exception {
        prune(app,patch,new HashSet<>(Arrays.asList(useful)),Collections.emptySet());
    }

    @Test public void repeatedReleasesDoNotAccumulateOldDownloads() throws Exception {
        for(int i=1;i<=80;i++) {
            String h=String.format("%064x",i),a=h+".apk",p=h+".cznpatch";
            put(updates,a);put(updates,p);
            Set<String> future=new HashSet<>();
            for(File file:updates.listFiles())if(file.getName().endsWith(".apk"))future.add(file.getName());
            prune(a,p,future,Collections.emptySet());
            assertEquals("Only the new APK and patch remain",2,updates.listFiles().length);
            assertTrue(new File(updates,a).isFile());assertTrue(new File(updates,p).isFile());
        }
    }
    @Test public void firstLaunchAndWorkerCanCreateCacheDirectoryTogether() throws Exception {
        File fresh=temp.newFolder("fresh-files");ExecutorService executor=Executors.newFixedThreadPool(8);
        CountDownLatch start=new CountDownLatch(1);List<Future<File>> results=new ArrayList<>();
        try {
            for(int i=0;i<8;i++)results.add(executor.submit(()->{start.await();return UpdateCache.directory(fresh);}));
            start.countDown();
            for(Future<File> result:results)assertEquals(new File(fresh,"updates"),result.get(3,TimeUnit.SECONDS));
        } finally {executor.shutdownNow();}
    }
    @Test public void upgradeMigrationRemovesInstalledApksButKeepsOfflinePatchAndUserData() throws Exception {
        File old=put(updates,apk('a')),installed=put(updates,apk('b')),current=put(updates,patch('c'));
        File settings=put(files,"settings.json"),channel=put(files,"channel.json");
        File recovery=new File(files,".czn_viethoa/baselines/old");assertTrue(recovery.mkdirs());
        File backup=put(recovery,"base_b21_0.ssrc"),journal=put(recovery.getParentFile().getParentFile(),"journal.json");
        prune(apk('b'),patch('c'));
        assertFalse(old.exists());assertFalse(installed.exists());assertTrue(current.exists());
        for(File kept:Arrays.asList(settings,channel,backup,journal))assertArrayEquals(new byte[]{1,2,3,4},Files.readAllBytes(kept.toPath()));
    }
    @Test public void retainsFutureApkAndCurrentPatchIndependently() throws Exception {
        File older=put(updates,apk('a')),future=put(updates,apk('b')),oldPatch=put(updates,patch('c')),newPatch=put(updates,patch('d'));
        prune(apk('b'),patch('d'),apk('b'));
        assertFalse(older.exists());assertTrue(future.exists());assertFalse(oldPatch.exists());assertTrue(newPatch.exists());
    }
    @Test public void failedNewDownloadKeepsLastCompleteArtifacts() throws Exception {
        File app=put(updates,apk('a')),patch=put(updates,patch('b'));
        File abandoned=put(updates,hash('c')+".part-"+UUID.randomUUID());
        prune(apk('c'),patch('d'),apk('a'));
        assertTrue(app.exists());assertTrue(patch.exists());assertFalse(abandoned.exists());
        put(updates,apk('c'));put(updates,patch('d'));
        prune(apk('c'),patch('d'),apk('a'),apk('c'));
        assertFalse(app.exists());assertFalse(patch.exists());
    }
    @Test public void pendingPermissionAndInstallerKeepExactFilesUntilReleased() throws Exception {
        File pending=put(updates,apk('a')),installer=put(updates,apk('b')),latest=put(updates,apk('c'));
        Set<String> all=new HashSet<>(Arrays.asList(apk('a'),apk('b'),apk('c')));
        prune(apk('c'),null,all,new HashSet<>(Arrays.asList(apk('a'),apk('b'))));
        assertTrue(pending.exists());assertTrue(installer.exists());assertTrue(latest.exists());
        prune(apk('c'),null,all,Collections.emptySet());
        assertFalse(pending.exists());assertFalse(installer.exists());assertTrue(latest.exists());
    }
    @Test public void installerLeaseExpiresOrEndsOnceActualInstalledVersionCatchesUp() {
        long now=1700000000000L,until=now+86400000L;
        assertTrue(UpdateCache.installerLeaseValid(10624,10625,until,now));
        assertTrue(UpdateCache.installerLeaseValid(10624,10625,until,until-1));
        assertFalse(UpdateCache.installerLeaseValid(10624,10625,until,until));
        assertFalse(UpdateCache.installerLeaseValid(10625,10625,until,now));
        assertFalse(UpdateCache.installerLeaseValid(10626,10625,until,now));
        assertFalse(UpdateCache.installerLeaseValid(10624,10625,until,now-1));
    }
    @Test public void concurrentWorkerSweepCannotDeleteActiveDownloadOrConsumer() throws Exception {
        File result=put(updates,apk('a')),part=put(updates,hash('a')+".part-"+UUID.randomUUID());
        UpdateCache.Lease foreground=UpdateCache.acquire(result,part),worker=UpdateCache.acquire(result,part);
        ExecutorService executor=Executors.newSingleThreadExecutor();
        try {
            executor.submit(()->{try{prune(null,null);}catch(Exception e){throw new RuntimeException(e);}}).get(3,TimeUnit.SECONDS);
            assertTrue(result.exists());assertTrue(part.exists());
            foreground.close();prune(null,null);
            assertTrue(result.exists());assertTrue(part.exists());
            worker.close();prune(null,null);
            assertFalse(result.exists());assertFalse(part.exists());
        } finally {foreground.close();worker.close();executor.shutdownNow();}
    }
    @Test public void foregroundHandoffProtectsReturnedPathUntilConsumerOpensIt() throws Exception {
        File result=put(updates,apk('a'));
        try(UpdateCache.Lease handoff=UpdateCache.acquire(result)) {
            try(UpdateCache.Lease download=UpdateCache.acquire(result)){prune(null,null);}
            // Dart receives a path after download closes its own lease.
            prune(null,null);assertTrue(result.exists());
            try(UpdateCache.Lease consumer=UpdateCache.acquire(result)) {
                handoff.close();prune(null,null);assertTrue(result.exists());
            }
        }
        prune(null,null);assertFalse(result.exists());
    }
    @Test public void stalePartFromKilledProcessIsRemovedButActivePartSurvives() throws Exception {
        File stale=put(updates,hash('a')+".part-"+UUID.randomUUID());
        File live=put(updates,hash('b')+".part-"+UUID.randomUUID());
        try(UpdateCache.Lease lease=UpdateCache.acquire(live)) {
            prune(null,null);assertFalse(stale.exists());assertTrue(live.exists());
        }
        prune(null,null);assertFalse(live.exists());
    }
    @Test public void bundledCopiesAreDisposableOnlyAfterInstallerClosesThem() throws Exception {
        File legacy=put(files,"bundled.cznpatch");
        File active=put(cache,"bundled-"+UUID.randomUUID()+".cznpatch");
        File stale=put(cache,"bundled-"+UUID.randomUUID()+".cznpatch");
        File unrelated=put(cache,"user.cznpatch");
        try(UpdateCache.Lease lease=UpdateCache.acquire(legacy,active)) {
            prune(null,null);assertTrue(legacy.exists());assertTrue(active.exists());assertFalse(stale.exists());
        }
        prune(null,null);assertFalse(legacy.exists());assertFalse(active.exists());assertTrue(unrelated.exists());
    }
    @Test public void doesNotRecurseIntoDirectoriesOrDeleteUnknownFiles() throws Exception {
        File unknown=put(updates,"user-backup.apk"),metadata=put(updates,"notes.json");
        File dir=new File(updates,apk('a'));assertTrue(dir.mkdir());File saved=put(dir,apk('b'));
        prune(null,null);
        assertTrue(unknown.exists());assertTrue(metadata.exists());assertTrue(saved.exists());
    }
    private void symlink(Path link,Path target) throws Exception {
        try{Files.createSymbolicLink(link,target);}catch(UnsupportedOperationException|IOException|SecurityException e){Assume.assumeNoException("Symlinks not permitted by this test host",e);}
    }
    @Test public void symlinkArtifactNeverDeletesItsExternalTarget() throws Exception {
        File outside=put(temp.getRoot(),"outside.apk");Path link=new File(updates,apk('a')).toPath();symlink(link,outside.toPath());
        prune(null,null);assertTrue(outside.exists());assertTrue(Files.isSymbolicLink(link));
    }
    @Test public void symlinkUpdateDirectoryIsRejectedWithoutTouchingExternalFiles() throws Exception {
        assertTrue(updates.delete());File outside=temp.newFolder("outside");File artifact=put(outside,apk('a'));
        symlink(updates.toPath(),outside.toPath());
        assertThrows(IOException.class,()->prune(null,null));assertTrue(artifact.exists());
    }
}
