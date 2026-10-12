package vn.czn.viethoa.czn_patcher;

import java.io.IOException;
import java.net.URI;
import java.util.Arrays;
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
}
