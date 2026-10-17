package vn.czn.viethoa.czn_patcher;

import android.os.Process;
import androidx.annotation.Keep;
import java.io.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import org.json.*;

@Keep
public class PatchCli {
    public static final Set<String> PACKAGES = new HashSet<>(Arrays.asList(
        "com.smilegate.chaoszero.stove.google",
        "com.smilegate.chaoszero.stove",
        "com.smilegate.chaoszero",
        "com.stove.czn.google"
    ));

    private static File discover(String pkg) throws Exception {
        if (!PACKAGES.contains(pkg)) throw new IOException("Gói game không được hỗ trợ: " + pkg);
        List<File> bases = new ArrayList<>();
        List<String> volumes = new ArrayList<>();
        volumes.add("/storage/emulated/0");
        File[] storage = new File("/storage").listFiles();
        if (storage != null) {
            for (File v : storage) {
                if (v.getName().matches("[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}")) volumes.add(v.getAbsolutePath());
            }
        }
        for (String volume : volumes) {
            for (String kind : Arrays.asList("data", "media", "obb")) {
                bases.add(new File(volume + "/Android/" + kind + "/" + pkg));
            }
        }
        return GameDiscovery.find(bases, new JSONObject().put("package", pkg).put("backend_uid", Process.myUid()).put("android_user", 0));
    }

    private static void closeGame(String pkg) throws Exception {
        java.lang.Process p = new ProcessBuilder("/system/bin/am", "force-stop", "--user", "0", pkg).redirectErrorStream(true).start();
        if (!p.waitFor(15, TimeUnit.SECONDS)) {
            p.destroy();
            throw new IOException("Không thể đóng game.");
        }
        if (p.exitValue() != 0) throw new IOException("Không thể đóng game; chưa ghi tài nguyên.");
    }

    private static PatchEngine engine() {
        return new PatchEngine(Base64.getDecoder().decode(BuildTrust.PUBLIC_KEY));
    }

    public static void main(String[] args) {
        JSONObject result = new JSONObject();
        try {
            if (args.length < 2) {
                result.put("success", false).put("message", "Thiếu tham số lệnh (action, pkg).");
                System.out.println(result.toString());
                return;
            }
            String action = args[0];
            String pkg = args[1];
            File root = discover(pkg);

            if ("inspect".equals(action)) {
                JSONObject inspected = engine().inspect(root);
                inspected.put("success", true).put("backend_uid", Process.myUid());
                System.out.println(inspected.toString());
                return;
            } else if ("install".equals(action)) {
                if (args.length < 3) throw new IllegalArgumentException("Thiếu đường dẫn tệp vá.");
                File patchFile = new File(args[2]);
                if (!patchFile.isFile()) throw new FileNotFoundException("Tệp vá không tồn tại: " + patchFile.getAbsolutePath());
                closeGame(pkg);
                try (InputStream in = new FileInputStream(patchFile)) {
                    JSONObject applied = engine().apply(root, in, (label, percent) -> {
                        System.err.println("PROGRESS:" + percent + ":" + (label != null ? label : "Đang xử lý"));
                    });
                    System.out.println(applied.toString());
                }
                return;
            } else if ("restore".equals(action)) {
                closeGame(pkg);
                JSONObject restored = engine().restore(root, (label, percent) -> {
                    System.err.println("PROGRESS:" + percent + ":" + (label != null ? label : "Đang xử lý"));
                });
                System.out.println(restored.toString());
                return;
            } else {
                result.put("success", false).put("message", "Lệnh chưa hỗ trợ: " + action);
                System.out.println(result.toString());
            }
        } catch (Exception e) {
            try {
                result.put("success", false).put("message", e.getMessage() != null ? e.getMessage() : e.toString());
                if (e instanceof GameDiscovery.Failure) {
                    GameDiscovery.Failure f = (GameDiscovery.Failure) e;
                    result.put("error_code", f.code).put("diagnostics", f.diagnostics);
                }
                if (e instanceof CacheIdentity.Unsupported) {
                    result.put("error_code", "CACHE_FORMAT_UNSUPPORTED").put("diagnostics", ((CacheIdentity.Unsupported) e).diagnostics);
                }
                System.out.println(result.toString());
            } catch (Exception ignored) {
                System.out.println("{\"success\":false,\"message\":\"Lỗi không xác định\"}");
            }
        }
    }
}
