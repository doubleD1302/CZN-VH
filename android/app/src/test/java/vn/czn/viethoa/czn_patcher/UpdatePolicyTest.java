package vn.czn.viethoa.czn_patcher;

import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;

public class UpdatePolicyTest {
    private JSONObject channel() throws Exception {
        return new JSONObject().put("app_code",10502).put("app_version","1.5.2")
            .put("app_url","https://example.com/app.apk").put("app_size",70000000)
            .put("app_sha256", "a".repeat(64)).put("patch_code",10402)
            .put("patch_sha256", "b".repeat(64));
    }
    private void identity(String pkg, long code, String version, String[] cert) throws Exception {
        UpdatePolicy.verifyApkIdentity(channel(),10501,"vn.czn.viethoa.community",pkg,code,version,
            new String[]{"release-cert"},cert);
    }
    @Test public void appOnlyReleaseWorksWhenPatchHasNotChanged() throws Exception {
        assertTrue(UpdatePolicy.hasAppUpdate(channel(),10501));
        assertFalse(UpdatePolicy.hasAppUpdate(channel(),10502));
        assertFalse(UpdatePolicy.hasAppUpdate(channel(),10503));
    }
    @Test public void rejectUnsafeOrOversizedAppMetadata() throws Exception {
        for(JSONObject c:new JSONObject[]{channel().put("app_url","http://example.com/a"),
                channel().put("app_size",157286401L),channel().put("app_sha256","broken"),
                channel().put("app_code",2147483648L)}) {
            assertThrows(Exception.class,()->UpdatePolicy.validateAppMetadata(c));
        }
    }
    @Test public void changedAppWithSamePatchIsRejectedBeforeDownloading() throws Exception {
        JSONObject old=channel(), fresh=channel().put("app_code",10503).put("app_sha256","c".repeat(64));
        assertThrows(Exception.class,()->UpdatePolicy.sameDownload(old,fresh,true));
        UpdatePolicy.sameDownload(old,fresh,false);
    }
    @Test public void matchingNewApkIsAccepted() throws Exception {
        identity("vn.czn.viethoa.community",10502,"1.5.2",new String[]{"release-cert"});
    }
    @Test public void wrongPackageVersionOrDowngradeIsRejected() throws Exception {
        assertThrows(Exception.class,()->identity("other.app",10502,"1.5.2",new String[]{"release-cert"}));
        assertThrows(Exception.class,()->identity("vn.czn.viethoa.community",10501,"1.5.1",new String[]{"release-cert"}));
        assertThrows(Exception.class,()->identity("vn.czn.viethoa.community",10502,"wrong",new String[]{"release-cert"}));
    }
    @Test public void wrongOrMissingCertificateIsRejected() throws Exception {
        assertThrows(Exception.class,()->identity("vn.czn.viethoa.community",10502,"1.5.2",new String[]{"different-cert"}));
        assertThrows(Exception.class,()->identity("vn.czn.viethoa.community",10502,"1.5.2",new String[]{}));
    }
}
