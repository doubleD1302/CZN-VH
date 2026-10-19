package vn.czn.viethoa.czn_patcher;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.util.Arrays;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import org.json.JSONObject;

/** Checks shared by foreground app updates and background update notices. */
public final class UpdatePolicy {
    private UpdatePolicy() {}

    public static void validateAppMetadata(JSONObject data) throws Exception {
        long code = data.getLong("app_code"), size = data.getLong("app_size");
        URI url = new URI(data.getString("app_url"));
        if (code <= 0 || code > Integer.MAX_VALUE || size <= 0 || size > 157286400L
                || data.getString("app_version").trim().isEmpty()
                || !data.getString("app_sha256").matches("[a-f0-9]{64}")
                || !"https".equals(url.getScheme()) || url.getHost() == null
                || url.getUserInfo() != null) {
            throw new IOException("Thông tin cập nhật ứng dụng không hợp lệ.");
        }
    }

    public static boolean hasAppUpdate(JSONObject data, int installedCode) throws Exception {
        if (!data.has("app_code")) return false;
        validateAppMetadata(data);
        return data.getInt("app_code") > installedCode;
    }

    public static boolean hasPatchUpdate(JSONObject data, int installedCode) throws Exception {
        long code = data.getLong("patch_code");
        if (code <= 0 || code > Integer.MAX_VALUE) throw new IOException("Mã bản dịch không hợp lệ.");
        return code > installedCode;
    }

    public static void sameDownload(JSONObject requested, JSONObject trusted, boolean apk) throws Exception {
        String kind = apk ? "app" : "patch";
        if (!requested.getString(kind + "_sha256").equals(trusted.getString(kind + "_sha256"))
                || requested.getInt(kind + "_code") != trusted.getInt(kind + "_code")) {
            throw new IOException("Bản phát hành đã đổi. Bấm Kiểm tra cập nhật rồi tải lại.");
        }
    }

    public static void verifyApkIdentity(JSONObject expected, int installedCode,
            String installedPackage, String apkPackage, long apkCode, String apkVersion,
            String[] installedCerts, String[] apkCerts) throws Exception {
        validateAppMetadata(expected);
        if (!installedPackage.equals(apkPackage)) throw new IOException("APK không thuộc CZN Việt Hóa.");
        if (apkCode <= installedCode || apkCode != expected.getLong("app_code")
                || !expected.getString("app_version").equals(apkVersion)) {
            throw new IOException("Phiên bản APK không khớp hoặc không mới hơn bản đang dùng.");
        }
        String[] current = installedCerts.clone(), candidate = apkCerts.clone();
        Arrays.sort(current); Arrays.sort(candidate);
        if (current.length == 0 || !Arrays.equals(current, candidate)) {
            throw new IOException("APK không có cùng chứng chỉ với ứng dụng đang cài.");
        }
    }

    public static JSONObject verifyPatchIdentity(JSONObject channel, File patchFile, byte[] publicKey) throws Exception {
        if (!patchFile.exists() || !patchFile.isFile()) {
            throw new IOException("Tệp bản dịch không tồn tại: " + patchFile.getName());
        }
        JSONObject release;
        try (ZipFile zip = new ZipFile(patchFile)) {
            ZipEntry entry = zip.getEntry("release.json");
            if (entry == null) {
                throw new IOException("Gói bản dịch thiếu release.json.");
            }
            try (InputStream in = zip.getInputStream(entry);
                 ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) {
                    if (out.size() + n > 262144) throw new IOException("Metadata release.json quá lớn.");
                    out.write(buf, 0, n);
                }
                release = PatchFormat.signed(out.toString("UTF-8"), publicKey);
            }
        }
        int pkgCode = release.getInt("version_code");
        String pkgVer = release.getString("version");
        int expectedCode = channel.getInt("patch_code");
        String expectedVer = channel.getString("patch_version");

        if (pkgCode != expectedCode || !expectedVer.equals(pkgVer)) {
            throw new IOException("Lệch danh tính bản dịch: Kênh quảng bá " + expectedVer + " (code " + expectedCode
                    + ") nhưng tệp tải về là " + pkgVer + " (code " + pkgCode + "). [PATCH_IDENTITY_MISMATCH]");
        }
        if (release.getInt("schema") != 2) {
            throw new IOException("Schema gói bản dịch không hợp lệ.");
        }
        if (release.getInt("min_patcher") > PatchEngine.CURRENT_PATCHER_CODE) {
            throw new IOException("Gói yêu cầu phiên bản ứng dụng tối thiểu " + release.getInt("min_patcher")
                    + " nhưng phiên bản hiện tại là " + PatchEngine.CURRENT_PATCHER_CODE + ".");
        }
        return release;
    }
}
