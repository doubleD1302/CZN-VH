package vn.czn.viethoa.czn_patcher;
import android.content.*;
import android.app.*;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.work.*;
import org.json.*;
import java.util.concurrent.atomic.AtomicBoolean;

public class UpdateWorker extends Worker {
    public UpdateWorker(@NonNull Context c,@NonNull WorkerParameters p){super(c,p);}
    @NonNull @Override public Result doWork(){Context c=getApplicationContext();SharedPreferences prefs=c.getSharedPreferences("czn_settings",0);if(!prefs.getBoolean("auto_download",true))return Result.success();try{
        JSONObject channel=ReleaseClient.check(c);int code=channel.getInt("patch_code");if(code<=prefs.getInt("installed_code",0))return Result.success();ReleaseClient.download(c,channel,false,new AtomicBoolean(false),(s,n)->{});
        if(code>prefs.getInt("notified_code",0) && (Build.VERSION.SDK_INT<33 || c.checkSelfPermission("android.permission.POST_NOTIFICATIONS")==android.content.pm.PackageManager.PERMISSION_GRANTED)){NotificationManager nm=(NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE);if(Build.VERSION.SDK_INT>=26)nm.createNotificationChannel(new NotificationChannel("updates","Bản dịch mới",NotificationManager.IMPORTANCE_DEFAULT));Intent open=c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());PendingIntent pi=PendingIntent.getActivity(c,1,open,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);try{nm.notify(1400,new Notification.Builder(c,"updates").setSmallIcon(android.R.drawable.stat_sys_download_done).setContentTitle("CZN Việt Hóa có bản mới").setContentText("Đã tải xong. Mở app để cài khi game đã đóng.").setContentIntent(pi).setAutoCancel(true).build());}catch(SecurityException ignored){return Result.success();}prefs.edit().putInt("notified_code",code).apply();}return Result.success();
    }catch(Exception e){return getRunAttemptCount()<3?Result.retry():Result.failure();}}
}
