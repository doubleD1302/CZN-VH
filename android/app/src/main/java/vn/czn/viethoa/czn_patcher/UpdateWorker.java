package vn.czn.viethoa.czn_patcher;

import android.app.*;
import android.content.*;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.work.*;
import org.json.JSONObject;
import java.util.concurrent.atomic.AtomicBoolean;

/** Downloads whole signed app updates (UI/assets/code) and translation data independently. */
public class UpdateWorker extends Worker {
    public UpdateWorker(@NonNull Context c, @NonNull WorkerParameters p) { super(c, p); }

    @NonNull @Override public Result doWork() {
        Context c = getApplicationContext();
        ReleaseClient.cleanup(c);
        SharedPreferences prefs = c.getSharedPreferences("czn_settings", 0);
        if (!prefs.getBoolean("auto_download", true)) return Result.success();
        boolean incomplete = false;
        try {
            JSONObject channel = ReleaseClient.check(c);
            PackageInfo app = c.getPackageManager().getPackageInfo(c.getPackageName(), 0);
            int appCode = (int)(Build.VERSION.SDK_INT >= 28 ? app.getLongVersionCode() : app.versionCode);
            if (UpdatePolicy.hasAppUpdate(channel, appCode)) {
                try {
                    ReleaseClient.download(c, channel, true, new AtomicBoolean(false), (label, value) -> {});
                    int code = channel.getInt("app_code");
                    prefs.edit().putInt("downloaded_app_code", code).apply();
                    if (code > prefs.getInt("notified_ready_app_code", 0) && notify(c, 1500,
                            "Đã tải CZN Việt Hóa " + channel.getString("app_version"),
                            "Giao diện, icon và chức năng mới đã sẵn sàng. Mở app để xác nhận cập nhật.", "app-updates"))
                        prefs.edit().putInt("notified_ready_app_code", code).apply();
                } catch (Exception error) { incomplete = true; }
            }
            if (UpdatePolicy.hasPatchUpdate(channel, prefs.getInt("installed_code", 0))) {
                try {
                    ReleaseClient.download(c, channel, false, new AtomicBoolean(false), (label, value) -> {});
                    int code = channel.getInt("patch_code");
                    prefs.edit().putInt("downloaded_patch_code", code).apply();
                    if (code > prefs.getInt("notified_code", 0) && notify(c, 1400,
                            "Đã tải bản dịch " + channel.getString("patch_version"),
                            "Mở app để cập nhật tiếng Việt. Nếu có APK mới, app sẽ cập nhật ứng dụng trước.", "updates"))
                        prefs.edit().putInt("notified_code", code).apply();
                } catch (Exception error) { incomplete = true; }
            }
            return incomplete ? retryOrFail() : Result.success();
        } catch (Exception error) { return retryOrFail(); }
    }

    private Result retryOrFail() { return getRunAttemptCount() < 3 ? Result.retry() : Result.failure(); }

    private static boolean notify(Context c, int id, String title, String text, String channel) {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                != PackageManager.PERMISSION_GRANTED) return false;
        NotificationManager nm = (NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.createNotificationChannel(new NotificationChannel(channel,
                channel.equals("app-updates") ? "Cập nhật toàn bộ ứng dụng" : "Bản dịch mới",
                NotificationManager.IMPORTANCE_DEFAULT));
        Intent open = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        PendingIntent pi = PendingIntent.getActivity(c, id, open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        try {
            nm.notify(id, new Notification.Builder(c, channel)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done).setContentTitle(title)
                    .setContentText(text).setStyle(new Notification.BigTextStyle().bigText(text))
                    .setContentIntent(pi).setAutoCancel(true).build());
            return true;
        } catch (SecurityException ignored) { return false; }
    }
}
