package vn.czn.viethoa.czn_patcher;

import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.Base64;
import java.util.zip.*;

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
    @Test public void appAndPatchUpdatesAreIndependent() throws Exception {
        JSONObject both = channel();
        assertTrue(UpdatePolicy.hasAppUpdate(both, 10501));
        assertTrue(UpdatePolicy.hasPatchUpdate(both, 10401));
        assertFalse(UpdatePolicy.hasPatchUpdate(both, 10402));
        assertTrue(UpdatePolicy.hasAppUpdate(both, 10501));
        assertFalse(UpdatePolicy.hasAppUpdate(both, 10502));
        assertTrue(UpdatePolicy.hasPatchUpdate(both, 10401));
    }
    @Test public void invalidPatchVersionDoesNotMasqueradeAsUpdate() throws Exception {
        assertThrows(Exception.class, () -> UpdatePolicy.hasPatchUpdate(channel().put("patch_code", 0), 10400));
        assertThrows(Exception.class, () -> UpdatePolicy.hasPatchUpdate(channel().put("patch_code", 2147483648L), 10400));
    }

    private File createPatchZip(KeyPair keys, int schema, int minPatcher, int versionCode, String version) throws Exception {
        JSONObject desc = new JSONObject().put("schema", schema).put("min_patcher", minPatcher)
            .put("version_code", versionCode).put("version", version);
        byte[] raw = desc.toString().getBytes(StandardCharsets.UTF_8);
        Signature s = Signature.getInstance("SHA256withRSA");
        s.initSign(keys.getPrivate());
        s.update(raw);
        String envelope = new JSONObject().put("signed", Base64.getEncoder().encodeToString(raw))
            .put("signature", Base64.getEncoder().encodeToString(s.sign())).toString();
        File zipFile = File.createTempFile("czn-patch-", ".cznpatch");
        zipFile.deleteOnExit();
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zipFile))) {
            zos.putNextEntry(new ZipEntry("release.json"));
            zos.write(envelope.getBytes(StandardCharsets.UTF_8));
            zos.closeEntry();
        }
        return zipFile;
    }

    @Test public void verifyPatchIdentityMatchingSucceeds() throws Exception {
        KeyPair keys = KeyPairGenerator.getInstance("RSA").generateKeyPair();
        File patch = createPatchZip(keys, 2, 10700, 10801, "1.8.1");
        JSONObject ch = channel().put("patch_code", 10801).put("patch_version", "1.8.1");
        JSONObject release = UpdatePolicy.verifyPatchIdentity(ch, patch, keys.getPublic().getEncoded());
        assertEquals(10801, release.getInt("version_code"));
        assertEquals("1.8.1", release.getString("version"));
    }

    @Test public void verifyPatchIdentityMismatchIsRejected() throws Exception {
        KeyPair keys = KeyPairGenerator.getInstance("RSA").generateKeyPair();
        // File is 1.7.0 (10701), but channel claims 1.8.1 (10801)
        File patch = createPatchZip(keys, 2, 10700, 10701, "1.7.0");
        JSONObject ch = channel().put("patch_code", 10801).put("patch_version", "1.8.1");
        try {
            UpdatePolicy.verifyPatchIdentity(ch, patch, keys.getPublic().getEncoded());
            fail("Expected PATCH_IDENTITY_MISMATCH exception");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("[PATCH_IDENTITY_MISMATCH]"));
        }
    }

    @Test public void verifyPatchIdentitySchemaOrMinPatcherRejected() throws Exception {
        KeyPair keys = KeyPairGenerator.getInstance("RSA").generateKeyPair();
        File patchSchema = createPatchZip(keys, 1, 10700, 10801, "1.8.1");
        JSONObject ch = channel().put("patch_code", 10801).put("patch_version", "1.8.1");
        assertThrows(IOException.class, () -> UpdatePolicy.verifyPatchIdentity(ch, patchSchema, keys.getPublic().getEncoded()));

        File patchFuture = createPatchZip(keys, 2, PatchEngine.CURRENT_PATCHER_CODE + 1, 10801, "1.8.1");
        assertThrows(IOException.class, () -> UpdatePolicy.verifyPatchIdentity(ch, patchFuture, keys.getPublic().getEncoded()));
    }
}
