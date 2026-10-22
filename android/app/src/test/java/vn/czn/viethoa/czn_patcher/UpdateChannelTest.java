package vn.czn.viethoa.czn_patcher;
import org.junit.Test;
import static org.junit.Assert.*;
public class UpdateChannelTest {
    @Test public void defaultsKeepPackagesSeparate() {
        assertEquals(UpdateChannel.SHARED,UpdateChannel.resolve(null,false));
        assertEquals(UpdateChannel.LOCAL,UpdateChannel.resolve(null,true));
        assertEquals(UpdateChannel.LOCAL,UpdateChannel.resolve(" ",true));
    }
    @Test public void migrateOnlyTheTwoOfficialSharedRoutes() {
        assertEquals(UpdateChannel.LOCAL,UpdateChannel.resolve(UpdateChannel.SHARED,true));
        assertEquals("https://github.com/doubleD1302/CZN-VH/releases/download/releases-1.0/localadb-channel.json",
            UpdateChannel.resolve("https://github.com/doubleD1302/CZN-VH/releases/download/releases-1.0/channel.json",true));
        assertEquals(UpdateChannel.LOCAL,UpdateChannel.resolve(UpdateChannel.LOCAL,true));
        assertEquals(UpdateChannel.SHARED,UpdateChannel.resolve(UpdateChannel.SHARED,false));
    }
    @Test public void preserveCustomRoutesAndLookalikesExactly() {
        for(String value:new String[]{"https://example.com/channel.json",UpdateChannel.SHARED+"?custom=1",
                "https://github.com.evil.example/doubleD1302/CZN-VH/releases/latest/download/channel.json"})
            assertEquals(value,UpdateChannel.resolve(value,true));
    }
    @Test public void rejectOldSharedApkCacheBeforeOfferingOrDownloading() {
        String shared="https://github.com/doubleD1302/CZN-VH/releases/download/releases-1.0/V1.9.1_CZN.apk";
        assertFalse(UpdateChannel.acceptsApp(UpdateChannel.LOCAL,shared,true));
        assertTrue(UpdateChannel.acceptsApp(UpdateChannel.SHARED,shared,false));
        assertTrue(UpdateChannel.acceptsApp(UpdateChannel.LOCAL,shared.replace("V1.9.1_CZN.apk","CZN_VietHoa_LocalADB_v1.9.3.apk"),true));
        assertTrue(UpdateChannel.acceptsApp("https://example.com/custom",shared,true));
    }
}
