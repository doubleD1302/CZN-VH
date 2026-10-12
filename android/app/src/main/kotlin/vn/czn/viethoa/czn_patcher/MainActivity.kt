package vn.czn.viethoa.czn_patcher

import android.Manifest
import android.content.*
import android.content.pm.PackageManager
import android.os.*
import androidx.core.content.FileProvider
import androidx.work.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
import org.json.*
import rikka.shizuku.Shizuku
import java.io.File
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var remote: ICznService? = null
    private var connecting: CompletableFuture<ICznService>? = null
    private var permissionResult: MethodChannel.Result? = null
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val args by lazy { Shizuku.UserServiceArgs(ComponentName(this, PatchUserService::class.java)).daemon(true).processNameSuffix("patch").tag("czn-community-patcher").version(appCode()).debuggable(false) }
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) { if(binder != null){remote=ICznService.Stub.asInterface(binder);connecting?.complete(remote)} }
        override fun onServiceDisconnected(name: ComponentName?) { remote=null;connecting?.completeExceptionally(IllegalStateException("Shizuku đã ngắt kết nối."));connecting=null }
    }
    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant -> if(code==1400){permissionResult?.success(grant==PackageManager.PERMISSION_GRANTED);permissionResult=null} }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        Shizuku.addRequestPermissionResultListener(permissionListener)
        EventChannel(engine.dartExecutor.binaryMessenger,"vn.czn.viethoa/progress").setStreamHandler(object:EventChannel.StreamHandler{
            override fun onListen(arguments:Any?,sink:EventChannel.EventSink?){events=sink}
            override fun onCancel(arguments:Any?){events=null}
        })
        MethodChannel(engine.dartExecutor.binaryMessenger,"vn.czn.viethoa/patcher").setMethodCallHandler { call,result ->
            when(call.method){
                "status" -> result.success(status())
                "requestAccess" -> {try{if(!Shizuku.pingBinder())result.error("SHIZUKU","Hãy mở và khởi động Shizuku trước.",null)
                    else if(Shizuku.checkSelfPermission()==PackageManager.PERMISSION_GRANTED)result.success(true)
                    else if(permissionResult!=null)result.error("BUSY","Đang chờ cấp quyền.",null)
                    else {permissionResult=result;Shizuku.requestPermission(1400);ui.postDelayed({if(permissionResult===result){permissionResult=null;result.error("TIMEOUT","Chưa nhận được quyền Shizuku. Thử cấp quyền lại.",null)}},60000)}
                }catch(e:Exception){permissionResult=null;result.error("SHIZUKU",e.message,null)}}
                "openShizuku" -> {val intent=packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api");if(intent!=null){startActivity(intent);result.success(true)}else result.success(false)}
                "requestNotifications" -> {if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),1401);result.success(true)}
                "cancelDownload" -> {cancelled.set(true);result.success(true)}
                "snoozeNotice" -> {val id=call.argument<String>("id") ?: "";require(id.length<=160);getSharedPreferences("czn_settings",0).edit().putString("notice_snooze_id",id).putLong("notice_snooze_until",System.currentTimeMillis()+TimeUnit.HOURS.toMillis(24)).apply();result.success(true)}
                "selectGame" -> {val pkg=call.argument<String>("package");if(pkg!=null && PatchUserService.PACKAGES.contains(pkg)){getSharedPreferences("czn_settings",0).edit().putString("selected_game",pkg).apply();result.success(true)}else result.error("PACKAGE","Chọn bản CZN được hỗ trợ.",null)}
                "saveSettings" -> {val channel=call.argument<String>("channel") ?: ReleaseClient.DEFAULT_CHANNEL
                    try{val u=java.net.URI(channel);require(u.scheme=="https" && u.host!=null && u.userInfo==null);getSharedPreferences("czn_settings",0).edit().putString("channel",channel).putBoolean("auto_download",call.argument<Boolean>("autoDownload") ?: true).apply();scheduleUpdates();if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED && call.argument<Boolean>("autoDownload")==true)requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),1401);result.success(true)}catch(e:Exception){result.error("SETTINGS","Địa chỉ cập nhật phải là URL HTTPS hợp lệ.",null)}}
                "launchGame" -> {if(busy.get() || getSharedPreferences("czn_settings",0).getBoolean("recovery_needed",false))result.error("BUSY","Cần hoàn tất cài/phục hồi trước khi mở game.",null)else{val pkg=gamePackage();val intent=pkg?.let{packageManager.getLaunchIntentForPackage(it)};if(intent!=null){startActivity(intent);result.success(true)}else result.success(false)}}
                else -> io.execute {try{val value:Any?=when(call.method){
                    "lastOperation" -> map(lastOperation())
                    "bundledInfo" -> map(ReleaseClient.verify(assets.open("bundled-release.json").bufferedReader().use{it.readText()}))
                    "cachedChannel" -> map(ReleaseClient.cached(this))
                    "checkUpdate" -> map(ReleaseClient.check(this))
                    "scanGame" -> {val state=JSONObject(service().inspect(gamePackage() ?: throw IllegalStateException("Chưa tìm thấy game CZN trên thiết bị.")));if(state.optBoolean("success") && !state.optBoolean("recovery_required"))getSharedPreferences("czn_settings",0).edit().putBoolean("recovery_needed",false).apply();map(state)}
                    "downloadPatch", "downloadApp" -> {cancelled.set(false);val data=JSONObject(call.argument<String>("channelJson") ?: "{}");val trusted=ReleaseClient.check(this);require(data.getString("patch_sha256")==trusted.getString("patch_sha256")){"Bản phát hành đã đổi; hãy kiểm tra lại."};ReleaseClient.download(this,trusted,call.method=="downloadApp",cancelled){s,n->progress(s,n)}.absolutePath}
                    "installBundled", "installPatch", "restore" -> {if(!busy.compareAndSet(false,true))throw IllegalStateException("Có một giao dịch đang chạy.");try{recordOperation(call.method,JSONObject().put("phase","running").put("success",false).put("message","Đang xử lý; chưa có xác nhận cài thành công."));
                        val pkg=gamePackage() ?: throw IllegalStateException("Chưa cài CZN.");val readiness=JSONObject(service().inspect(pkg));require(readiness.optBoolean("success")){readiness.optString("message","Chưa tìm được dữ liệu game.")};getSharedPreferences("czn_settings",0).edit().putBoolean("recovery_needed",true).commit();val callback=object:IPatchProgress.Stub(){override fun report(label:String?,percent:Int){progress(label ?: "Đang xử lý",percent)}}
                        val text=if(call.method=="restore")service().restore(pkg,callback)else{val zip=if(call.method=="installBundled"){val f=File(filesDir,"bundled.cznpatch");assets.open("bundled.cznpatch").use{input->f.outputStream().use{input.copyTo(it)}};f}else File(call.argument<String>("path") ?: "");require(zip.isFile && zip.length()<=33554432L){"Gói bản dịch không hợp lệ hoặc vượt 32 MB."};ParcelFileDescriptor.open(zip,ParcelFileDescriptor.MODE_READ_ONLY).use{service().install(pkg,it,callback)}}
                        val response=JSONObject(text);val checked=try{JSONObject(service().inspect(pkg))}catch(postError:Exception){JSONObject().put("success",false).put("error_code","POST_INSPECT_FAILED").put("message",postError.message ?: "Không đọc lại được dữ liệu sau thao tác.")};response.put("post_install",checked);if(response.optBoolean("success") && !(checked.optBoolean("success") && !checked.optBoolean("recovery_required") && (if(call.method=="restore") !checked.has("installed_version") else checked.optBoolean("files_match") && checked.optInt("installed_code",0)>0 && checked.optInt("installed_code")==response.optInt("version_code",-1) && checked.optString("installed_version").isNotEmpty() && checked.optString("installed_version")==response.optString("version")))){response.put("success",false).put("error_code","POST_INSTALL_UNVERIFIED").put("message","Chưa xác minh được dữ liệu sau cài. Chưa đánh dấu cài thành công; kiểm tra báo cáo trước khi mở game.")};if(response.optBoolean("success"))response.put("message",if(call.method=="restore") "Đã khôi phục đầy đủ bản gốc." else "Cài thành công bản "+response.optString("version")+". Dữ liệu sau cài đã khớp; chọn 日本語 trong game.");recordOperation(call.method,response.put("phase",if(response.optBoolean("success")) "completed" else "failed"));if(checked.optBoolean("success") && !checked.optBoolean("recovery_required"))getSharedPreferences("czn_settings",0).edit().putBoolean("recovery_needed",false).commit();if(response.optBoolean("success")){getSharedPreferences("czn_settings",0).edit().putInt("installed_code",checked.optInt("installed_code",0)).apply()};map(response)
                    }finally{busy.set(false)}}
                    "installApp" -> {val f=File(call.argument<String>("path") ?: "");require(f.canonicalPath.startsWith(File(filesDir,"updates").canonicalPath+File.separator)&&f.name.endsWith(".apk"));val channel=ReleaseClient.check(this);require(f.length()==channel.getLong("app_size")&&PatchFormat.sha(f)==channel.getString("app_sha256"));val archive=packageManager.getPackageArchiveInfo(f.absolutePath,0) ?: throw IllegalStateException("APK cập nhật không hợp lệ.");require(archive.packageName==packageName);ui.post{startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(FileProvider.getUriForFile(this,"$packageName.updates",f),"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))};true}
                    else -> throw UnsupportedOperationException("Phương thức chưa hỗ trợ.")
                };ui.post{result.success(value)}}catch(e:Exception){if(call.method in listOf("installBundled","installPatch","restore")){try{recordOperation(call.method,JSONObject().put("phase","failed").put("success",false).put("message",e.cause?.message ?: e.message ?: "Thao tác chưa hoàn tất.").put("error_code","NATIVE_EXCEPTION"))}catch(ignored:Exception){}};ui.post{result.error("CZN",if(e is DeadObjectException || e.cause is DeadObjectException) "Shizuku đã ngắt kết nối. Bấm kiểm tra lại hoặc phục hồi trước khi mở game." else (e.cause?.message ?: e.message ?: "Kết nối chưa hoàn tất. Bấm kiểm tra lại và thử lại thao tác."),null)}} }
            }
        }
        scheduleUpdates()
    }
    private fun lastOperation():JSONObject {val f=File(filesDir,"last-operation.json");return if(f.isFile)JSONObject(f.readText()) else JSONObject()}
    private fun recordOperation(action:String,result:JSONObject){result.put("action",action).put("time",System.currentTimeMillis());val target=File(filesDir,"last-operation.json");val temp=File(filesDir,"last-operation.tmp");PatchFormat.write(temp,result.toString().toByteArray(Charsets.UTF_8));java.nio.file.Files.move(temp.toPath(),target.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING,java.nio.file.StandardCopyOption.ATOMIC_MOVE)}
    private fun map(json:JSONObject):Map<String,Any?> {val out=mutableMapOf<String,Any?>();json.keys().forEach{key->val v=json.get(key);out[key]=when(v){JSONObject.NULL->null;is JSONObject->map(v);is JSONArray->(0 until v.length()).map{val item=v.get(it);if(item is JSONObject)map(item)else if(item==JSONObject.NULL)null else item};else->v}};return out}
    private fun progress(s:String,n:Int){ui.post{events?.success(mapOf("label" to s,"percent" to n))}}
    private fun appCode():Int {val info=packageManager.getPackageInfo(packageName,0);return if(Build.VERSION.SDK_INT>=28)info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode}
    private fun installedGames():List<Map<String,Any?>> = PatchUserService.PACKAGES.sorted().mapNotNull { pkg -> try{val info=packageManager.getPackageInfo(pkg,0);mapOf("package" to pkg,"name" to packageManager.getApplicationLabel(info.applicationInfo!!).toString(),"version" to info.versionName,"installer" to @Suppress("DEPRECATION") packageManager.getInstallerPackageName(pkg))}catch(e:PackageManager.NameNotFoundException){null} }
    private fun gamePackage():String? {val games=installedGames();val selected=getSharedPreferences("czn_settings",0).getString("selected_game",null);return games.firstOrNull{it["package"]==selected}?.get("package") as String? ?: games.firstOrNull()?.get("package") as String?}
    private fun status():Map<String,Any?> {val prefs=getSharedPreferences("czn_settings",0);val running=try{Shizuku.pingBinder()}catch(e:Exception){false};val granted=running && try{Shizuku.checkSelfPermission()==PackageManager.PERMISSION_GRANTED}catch(e:Exception){false};return mapOf("package" to gamePackage(),"games" to installedGames(),"manufacturer" to Build.MANUFACTURER,"model" to Build.MODEL,"shizukuRunning" to running,"accessGranted" to granted,"autoDownload" to prefs.getBoolean("auto_download",true),"channel" to prefs.getString("channel",ReleaseClient.DEFAULT_CHANNEL),"appCode" to appCode(),"appVersion" to packageManager.getPackageInfo(packageName,0).versionName,"android" to Build.VERSION.RELEASE,"androidUser" to android.os.Process.myUid()/100000,"noticeSnoozeId" to prefs.getString("notice_snooze_id",""),"noticeSnoozeUntil" to prefs.getLong("notice_snooze_until",0),"recoveryPending" to prefs.getBoolean("recovery_needed",false))}
    private fun service():ICznService {check(android.os.Process.myUid()/100000==0){"Patcher chỉ hỗ trợ hồ sơ Android chính. Không dùng Không gian thứ hai/Ứng dụng kép."};remote?.let{if(it.asBinder().isBinderAlive)return it};check(Shizuku.pingBinder() && Shizuku.checkSelfPermission()==PackageManager.PERMISSION_GRANTED){"Cần khởi động Shizuku và cấp quyền cho CZN Việt Hóa."};val future=CompletableFuture<ICznService>();connecting=future;ui.post{try{Shizuku.bindUserService(args,connection)}catch(e:Exception){future.completeExceptionally(e)}};return future.get(20,TimeUnit.SECONDS)}
    private fun scheduleUpdates(){val enabled=getSharedPreferences("czn_settings",0).getBoolean("auto_download",true);val wm=WorkManager.getInstance(this);if(!enabled){wm.cancelUniqueWork("czn-updates");return};val constraints=Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).setRequiresStorageNotLow(true).build();val request=PeriodicWorkRequest.Builder(UpdateWorker::class.java,12,TimeUnit.HOURS).setConstraints(constraints).build();wm.enqueueUniquePeriodicWork("czn-updates",ExistingPeriodicWorkPolicy.KEEP,request)}
    override fun onDestroy(){Shizuku.removeRequestPermissionResultListener(permissionListener);super.onDestroy()}
}
