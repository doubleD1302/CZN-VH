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
import java.io.InputStream
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val cacheReady = CompletableFuture<Unit>()
    private val handoffLock = Any()
    private val downloadHandoffs = mutableMapOf<String, Pair<File, UpdateCache.Lease>>()
    private var handoffsClosed = false
    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant -> if(code==1400){permissionResult?.success(grant==PackageManager.PERMISSION_GRANTED);permissionResult=null} }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        LocalAdbManager.init(applicationContext)
        ShizukuServiceConnector.configure(applicationContext, appCode())
        io.execute { try { ReleaseClient.cleanup(this) } finally { cacheReady.complete(Unit) } }
        Shizuku.addRequestPermissionResultListener(permissionListener)
        EventChannel(engine.dartExecutor.binaryMessenger,"vn.czn.viethoa/progress").setStreamHandler(object:EventChannel.StreamHandler{
            override fun onListen(arguments:Any?,sink:EventChannel.EventSink?){events=sink}
            override fun onCancel(arguments:Any?){events=null}
        })
        MethodChannel(engine.dartExecutor.binaryMessenger,"vn.czn.viethoa/patcher").setMethodCallHandler { call,result ->
            when(call.method){
                "status" -> { if(cacheReady.isDone) result.success(status()) else cacheReady.thenRun { ui.post { result.success(status()) } } }
                "isLocalAdbConnected" -> result.success(LocalAdbManager.isLocalConnected())
                "getWifiIp" -> result.success(LocalAdbManager.getLocalWifiIp())
                "pairLocalAdb" -> {
                    val host = call.argument<String>("host")?.trim()?.ifEmpty { null }
                    val port = call.argument<Int>("port") ?: 0
                    val code = call.argument<String>("code") ?: ""
                    io.execute {
                        try {
                            val ok = LocalAdbManager.pairDevice(host, port, code)
                            ui.post { result.success(ok) }
                        } catch (t: Throwable) {
                            val msg = t.message ?: t.javaClass.simpleName
                            android.util.Log.e("CZN_ADB", "pairLocalAdb error: $msg", t)
                            ui.post { result.error("PAIR_FAILED", msg, null) }
                        }
                    }
                }
                "connectLocalAdb" -> {
                    val host = call.argument<String>("host")?.trim()?.ifEmpty { null }
                    val port = call.argument<Int>("port") ?: 0
                    io.execute {
                        try {
                            val ok = LocalAdbManager.connectDevice(host, port)
                            ui.post { result.success(ok) }
                        } catch (t: Throwable) {
                            val msg = t.message ?: t.javaClass.simpleName
                            android.util.Log.e("CZN_ADB", "connectLocalAdb error: $msg", t)
                            ui.post { result.error("CONNECT_FAILED", msg, null) }
                        }
                    }
                }
                "openDevSettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(android.provider.Settings.ACTION_SETTINGS))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "requestAccess" -> {
                    if (LocalAdbManager.isLocalConnected()) {
                        result.success(true)
                    } else {
                        try {
                            if (!Shizuku.pingBinder()) result.error("LOCAL_ADB", "Chưa kết nối Local ADB. Hãy bấm Ghép nối/Kết nối Local ADB.", null)
                            else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) result.success(true)
                            else if (permissionResult != null) result.error("BUSY", "Đang chờ cấp quyền.", null)
                            else {
                                permissionResult = result
                                Shizuku.requestPermission(1400)
                                ui.postDelayed({
                                    if (permissionResult === result) {
                                        permissionResult = null
                                        result.error("TIMEOUT", "Chưa nhận được quyền. Thử cấp quyền lại.", null)
                                    }
                                }, 60000)
                            }
                        } catch (e: Exception) {
                            permissionResult = null
                            result.error("LOCAL_ADB", e.message, null)
                        }
                    }
                }
                "openShizuku" -> {
                    val intent = packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
                    if (intent != null) {
                        startActivity(intent)
                        result.success(true)
                    } else result.success(false)
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1401)
                    }
                    result.success(true)
                }
                "cancelDownload" -> { cancelled.set(true); result.success(true) }
                "snoozeNotice" -> {
                    val id = call.argument<String>("id") ?: ""
                    require(id.length <= 160)
                    getSharedPreferences("czn_settings", 0).edit().putString("notice_snooze_id", id).putLong("notice_snooze_until", System.currentTimeMillis() + TimeUnit.HOURS.toMillis(24)).apply()
                    result.success(true)
                }
                "selectGame" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg != null && PatchUserService.PACKAGES.contains(pkg)) {
                        getSharedPreferences("czn_settings", 0).edit().putString("selected_game", pkg).apply()
                        result.success(true)
                    } else result.error("PACKAGE", "Chọn bản CZN được hỗ trợ.", null)
                }
                "saveSettings" -> {
                    val channel = call.argument<String>("channel") ?: ReleaseClient.DEFAULT_CHANNEL
                    try {
                        val u = java.net.URI(channel)
                        require(u.scheme == "https" && u.host != null && u.userInfo == null)
                        getSharedPreferences("czn_settings", 0).edit().putString("channel", channel).putBoolean("auto_download", call.argument<Boolean>("autoDownload") ?: true).apply()
                        scheduleUpdates()
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED && call.argument<Boolean>("autoDownload") == true) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1401)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS", "Địa chỉ cập nhật phải là URL HTTPS hợp lệ.", null)
                    }
                }
                "launchGame" -> {
                    if (busy.get() || getSharedPreferences("czn_settings", 0).getBoolean("recovery_needed", false)) {
                        result.error("BUSY", "Cần hoàn tất cài/phục hồi trước khi mở game.", null)
                    } else {
                        val pkg = gamePackage()
                        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent != null) {
                            startActivity(intent)
                            result.success(true)
                        } else result.success(false)
                    }
                }
                "canDrawOverlays" -> result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.provider.Settings.canDrawOverlays(this) else true)
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this)) {
                        try {
                            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:$packageName")))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OVERLAY", e.message, null)
                        }
                    } else result.success(true)
                }
                "startChibiOverlay" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this)) {
                        result.error("PERMISSION", "Chưa được cấp quyền hiển thị trên ứng dụng khác.", null)
                    } else {
                        val intent = Intent(this, ChibiOverlayService::class.java).apply { action = ChibiOverlayService.ACTION_START }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        result.success(true)
                    }
                }
                "stopChibiOverlay" -> {
                    val intent = Intent(this, ChibiOverlayService::class.java).apply { action = ChibiOverlayService.ACTION_STOP }
                    startService(intent)
                    result.success(true)
                }
                "isChibiOverlayRunning" -> result.success(ChibiOverlayService.isRunning)
                "checkCompanionLaunchIntent" -> {
                    val shouldOpen = intent?.getBooleanExtra("open_companion_dialog", false) == true
                    if (shouldOpen) {
                        intent?.removeExtra("open_companion_dialog")
                    }
                    result.success(shouldOpen)
                }
                else -> io.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "lastOperation" -> map(lastOperation())
                            "bundledInfo" -> map(ReleaseClient.verify(assets.open("bundled-release.json").bufferedReader().use { it.readText() }))
                            "cachedChannel" -> map(ReleaseClient.cached(this))
                            "checkUpdate" -> map(ReleaseClient.check(this))
                            "scanGame" -> {
                                val pkg = gamePackage() ?: throw IllegalStateException("Chưa tìm thấy game CZN trên thiết bị.")
                                val state = runPatchOperation("inspect", pkg)
                                if (state.optBoolean("success") && !state.optBoolean("recovery_required")) {
                                    getSharedPreferences("czn_settings", 0).edit().putBoolean("recovery_needed", false).apply()
                                }
                                map(state)
                            }
                            "downloadPatch", "downloadApp" -> {
                                cancelled.set(false)
                                val data = JSONObject(call.argument<String>("channelJson") ?: "{}")
                                val trusted = ReleaseClient.check(this)
                                val apk = call.method == "downloadApp"
                                UpdatePolicy.sameDownload(data, trusted, apk)
                                if (apk) require(UpdatePolicy.hasAppUpdate(trusted, appCode())) { "Bạn đang dùng bản ứng dụng này hoặc mới hơn." }
                                val kind = if (apk) "app" else "patch"
                                val target = File(UpdateCache.directory(filesDir), trusted.getString(kind + "_sha256") + if (apk) ".apk" else ".cznpatch")
                                val handoff = UpdateCache.acquire(target)
                                try {
                                    val file = ReleaseClient.download(this, trusted, apk, cancelled) { s, n -> progress(s, n) }
                                    synchronized(handoffLock) {
                                        if (handoffsClosed) handoff.close()
                                        else downloadHandoffs.put(kind, Pair(file, handoff))?.second?.close()
                                    }
                                    file.absolutePath
                                } catch (error: Exception) {
                                    handoff.close()
                                    throw error
                                }
                            }
                            "installBundled", "installPatch", "restore" -> {
                                if (!busy.compareAndSet(false, true)) throw IllegalStateException("Có một giao dịch đang chạy.")
                                try {
                                    recordOperation(call.method, JSONObject().put("phase", "running").put("success", false).put("message", "Đang xử lý; chưa có xác nhận cài thành công."))
                                    val pkg = gamePackage() ?: throw IllegalStateException("Chưa cài CZN.")
                                    val readiness = runPatchOperation("inspect", pkg)
                                    require(readiness.optBoolean("success")) { readiness.optString("message", "Chưa tìm được dữ liệu game.") }
                                    getSharedPreferences("czn_settings", 0).edit().putBoolean("recovery_needed", true).commit()

                                    val response = when (call.method) {
                                        "restore" -> runPatchOperation("restore", pkg)
                                        "installBundled" -> assets.open("bundled.cznpatch").use { runPatchOperation("install", pkg, it) }
                                        "installPatch" -> {
                                            val zip = File(call.argument<String>("path") ?: "")
                                            UpdateCache.acquire(zip).use {
                                                consumeDownload(zip)
                                                require(zip.isFile && zip.length() <= 67108864L) { "Gói bản dịch không hợp lệ hoặc vượt 64 MB." }
                                                zip.inputStream().use { runPatchOperation("install", pkg, it) }
                                            }
                                        }
                                        else -> throw IllegalArgumentException()
                                    }

                                    val checked = try {
                                        runPatchOperation("inspect", pkg)
                                    } catch (postError: Exception) {
                                        JSONObject().put("success", false).put("error_code", "POST_INSPECT_FAILED").put("message", postError.message ?: "Không đọc lại được dữ liệu sau thao tác.")
                                    }
                                    response.put("post_install", checked)
                                    if (response.optBoolean("success") && !(checked.optBoolean("success") && !checked.optBoolean("recovery_required") && (if (call.method == "restore") !checked.has("installed_version") else checked.optBoolean("files_match") && checked.optInt("installed_code", 0) > 0 && checked.optInt("installed_code") == response.optInt("version_code", -1) && checked.optString("installed_version").isNotEmpty() && checked.optString("installed_version") == response.optString("version")))) {
                                        response.put("success", false).put("error_code", "POST_INSTALL_UNVERIFIED").put("message", "Chưa xác minh được dữ liệu sau cài. Chưa đánh dấu cài thành công; kiểm tra báo cáo trước khi mở game.")
                                    }
                                    if (response.optBoolean("success")) {
                                        response.put("message", if (call.method == "restore") "Đã khôi phục đầy đủ bản gốc." else "Cài thành công bản " + response.optString("version") + ". Dữ liệu sau cài đã khớp; chọn 日本語 trong game.")
                                    }
                                    recordOperation(call.method, response.put("phase", if (response.optBoolean("success")) "completed" else "failed"))
                                    if (checked.optBoolean("success") && !checked.optBoolean("recovery_required")) {
                                        getSharedPreferences("czn_settings", 0).edit().putBoolean("recovery_needed", false).commit()
                                    }
                                    if (response.optBoolean("success")) {
                                        getSharedPreferences("czn_settings", 0).edit().putInt("installed_code", checked.optInt("installed_code", 0)).apply()
                                    }
                                    map(response)
                                } finally {
                                    busy.set(false)
                                }
                            }
                            "installApp" -> openAppInstaller(File(call.argument<String>("path") ?: ""))
                            "resumeAppUpdate" -> {
                                val prefs = getSharedPreferences("czn_settings", 0)
                                val path = prefs.getString("pending_app_update", null) ?: throw IllegalStateException("Chưa có APK chờ cài.")
                                openAppInstaller(File(path))
                            }
                            else -> throw UnsupportedOperationException("Phương thức chưa hỗ trợ.")
                        }
                        ui.post { result.success(value) }
                    } catch (e: Exception) {
                        replyFailure(call.method, result, e)
                    }
                }
            }
        }
        scheduleUpdates()
    }

    private fun runPatchOperation(action: String, pkg: String, patchInput: InputStream? = null): JSONObject {
        if (LocalAdbManager.isLocalConnected()) {
            val staged = "/data/local/tmp/czn_staged.cznpatch"
            try {
                if (patchInput != null) {
                    LocalAdbManager.pushFile(patchInput, staged)
                }
                val args = if (patchInput != null) listOf(action, pkg, staged) else listOf(action, pkg)
                return LocalAdbManager.execPatchCli(this, args) { label, pct ->
                    progress(label, pct)
                }
            } finally {
                if (patchInput != null) {
                    try { LocalAdbManager.execCommand("rm -f \"$staged\"") } catch (_: Exception) {}
                }
            }
        } else {
            // Fallback to Shizuku service if Local ADB is not connected
            return when (action) {
                "inspect" -> JSONObject(service().inspect(pkg))
                "restore" -> {
                    val callback = object : IPatchProgress.Stub() {
                        override fun report(label: String?, percent: Int) { progress(label ?: "Đang xử lý", percent) }
                    }
                    JSONObject(service().restore(pkg, callback))
                }
                "install" -> {
                    val callback = object : IPatchProgress.Stub() {
                        override fun report(label: String?, percent: Int) { progress(label ?: "Đang xử lý", percent) }
                    }
                    val temp = File(cacheDir, "shizuku_install-${java.util.UUID.randomUUID()}.cznpatch")
                    try {
                        requireNotNull(patchInput) { "Thiếu dữ liệu bản vá." }
                        temp.outputStream().use { patchInput.copyTo(it) }
                        ParcelFileDescriptor.open(temp, ParcelFileDescriptor.MODE_READ_ONLY).use {
                            JSONObject(service().install(pkg, it, callback))
                        }
                    } finally {
                        temp.delete()
                    }
                }
                else -> throw UnsupportedOperationException("Lệnh chưa hỗ trợ: $action")
            }
        }
    }

    private fun replyFailure(action: String, result: MethodChannel.Result, error: Exception) {
        var cause: Throwable = error
        while ((cause is ExecutionException || cause is CompletionException) && cause.cause != null) cause = cause.cause!!
        val failure = cause as? ShizukuServiceConnector.Failure
        val code = failure?.code ?: if (cause is DeadObjectException) "SHIZUKU_SERVICE_DIED" else if (cause is TimeoutException) "NATIVE_TIMEOUT" else "NATIVE_EXCEPTION"
        val message = failure?.message ?: if (cause is DeadObjectException) "Dịch vụ vá đã ngắt kết nối. Bấm kiểm tra lại; kiểm tra báo cáo trước khi mở game." else cause.message ?: "Thao tác chưa hoàn tất."
        val details = failure?.diagnostics ?: ShizukuServiceConnector.diagnostics()
        if (action in listOf("installBundled", "installPatch", "restore")) {
            try { recordOperation(action, JSONObject().put("phase", "failed").put("success", false).put("message", message).put("error_code", code).put("diagnostics", JSONObject(details))) } catch (_: Exception) {}
        }
        ui.post { result.error(code, message, details) }
    }

    private fun lastOperation(): JSONObject {
        val f = File(filesDir, "last-operation.json")
        return if (f.isFile) JSONObject(f.readText()) else JSONObject()
    }

    private fun consumeDownload(file: File) {
        synchronized(handoffLock) {
            val keys = downloadHandoffs.filterValues { it.first.canonicalFile == file.canonicalFile }.keys.toList()
            keys.forEach { downloadHandoffs.remove(it)?.second?.close() }
        }
    }

    private fun openAppInstaller(file: File): Map<String, Any?> = UpdateCache.acquire(file).use { consumeDownload(file); openVerifiedAppInstaller(file) }

    private fun openVerifiedAppInstaller(file: File): Map<String, Any?> {
        require(file.isFile && file.canonicalPath.startsWith(File(filesDir, "updates").canonicalPath + File.separator) && file.name.endsWith(".apk")) { "APK không nằm trong bộ nhớ cập nhật của app." }
        val channel = ReleaseClient.cached(this)
        UpdatePolicy.validateAppMetadata(channel)
        require(file.length() == channel.getLong("app_size") && PatchFormat.sha(file) == channel.getString("app_sha256")) { "APK tải về không khớp bản cập nhật đã xác thực. Kiểm tra cập nhật rồi tải lại." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: throw IllegalStateException("APK cập nhật không hợp lệ.")
        val installed = packageManager.getPackageInfo(packageName, flags)
        fun certs(info: android.content.pm.PackageInfo): Array<String> {
            val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else @Suppress("DEPRECATION") info.signatures
            return signatures.orEmpty().map { PatchFormat.hex(java.security.MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toTypedArray()
        }
        val code = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else @Suppress("DEPRECATION") archive.versionCode.toLong()
        UpdatePolicy.verifyApkIdentity(channel, appCode(), packageName, archive.packageName, code, archive.versionName, certs(installed), certs(archive))
        ReleaseClient.holdForInstaller(this, file, code)
        val launch = CompletableFuture<Map<String, Any?>>()
        ui.post {
            try {
                val prefs = getSharedPreferences("czn_settings", 0)
                if (!packageManager.canRequestPackageInstalls()) {
                    prefs.edit().putString("pending_app_update", file.absolutePath).commit()
                    startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName")))
                    launch.complete(mapOf("state" to "permission_required"))
                } else {
                    startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(FileProvider.getUriForFile(this, "$packageName.updates", file), "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    prefs.edit().remove("pending_app_update").commit()
                    launch.complete(mapOf("state" to "installer_opened"))
                }
            } catch (e: Exception) { launch.completeExceptionally(e) }
        }
        return launch.get(15, TimeUnit.SECONDS)
    }

    private fun recordOperation(action: String, result: JSONObject) {
        result.put("action", action).put("time", System.currentTimeMillis())
        val target = File(filesDir, "last-operation.json")
        val temp = File(filesDir, "last-operation.tmp")
        PatchFormat.write(temp, result.toString().toByteArray(Charsets.UTF_8))
        java.nio.file.Files.move(temp.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
    }

    private fun map(json: JSONObject): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        json.keys().forEach { key ->
            val v = json.get(key)
            out[key] = when (v) {
                JSONObject.NULL -> null
                is JSONObject -> map(v)
                is JSONArray -> (0 until v.length()).map {
                    val item = v.get(it)
                    if (item is JSONObject) map(item) else if (item == JSONObject.NULL) null else item
                }
                else -> v
            }
        }
        return out
    }

    private fun progress(s: String, n: Int) {
        ui.post { events?.success(mapOf("label" to s, "percent" to n)) }
    }

    private fun appCode(): Int {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
    }

    private fun installedGames(): List<Map<String, Any?>> = PatchUserService.PACKAGES.sorted().mapNotNull { pkg ->
        try {
            val info = packageManager.getPackageInfo(pkg, 0)
            mapOf("package" to pkg, "name" to packageManager.getApplicationLabel(info.applicationInfo!!).toString(), "version" to info.versionName, "installer" to @Suppress("DEPRECATION") packageManager.getInstallerPackageName(pkg))
        } catch (e: PackageManager.NameNotFoundException) { null }
    }

    private fun gamePackage(): String? {
        val games = installedGames()
        val selected = getSharedPreferences("czn_settings", 0).getString("selected_game", null)
        return games.firstOrNull { it["package"] == selected }?.get("package") as String? ?: games.firstOrNull()?.get("package") as String?
    }

    private fun status(): Map<String, Any?> {
        val prefs = getSharedPreferences("czn_settings", 0)
        val localAdb = LocalAdbManager.isLocalConnected()
        val shizukuRunning = try { Shizuku.pingBinder() } catch (e: Exception) { false }
        val shizukuGranted = shizukuRunning && try { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED } catch (e: Exception) { false }
        val running = localAdb || shizukuRunning
        val granted = localAdb || shizukuGranted
        val canOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.provider.Settings.canDrawOverlays(this) else true
        return mapOf(
            "package" to gamePackage(),
            "games" to installedGames(),
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "shizukuRunning" to running,
            "accessGranted" to granted,
            "localAdbConnected" to localAdb,
            "shizukuConnected" to shizukuGranted,
            "autoDownload" to prefs.getBoolean("auto_download", true),
            "downloadedAppCode" to prefs.getInt("downloaded_app_code", 0),
            "downloadedPatchCode" to prefs.getInt("downloaded_patch_code", 0),
            "channel" to prefs.getString("channel", ReleaseClient.DEFAULT_CHANNEL),
            "appCode" to appCode(),
            "appVersion" to packageManager.getPackageInfo(packageName, 0).versionName,
            "android" to Build.VERSION.RELEASE,
            "androidUser" to android.os.Process.myUid() / 100000,
            "noticeSnoozeId" to prefs.getString("notice_snooze_id", ""),
            "noticeSnoozeUntil" to prefs.getLong("notice_snooze_until", 0),
            "recoveryPending" to prefs.getBoolean("recovery_needed", false),
            "appInstallAllowed" to packageManager.canRequestPackageInstalls(),
            "pendingAppUpdate" to prefs.contains("pending_app_update"),
            "overlayRunning" to ChibiOverlayService.isRunning,
            "canDrawOverlays" to canOverlay,
            "shizukuService" to ShizukuServiceConnector.diagnostics()
        )
    }

    private fun service(): ICznService = ShizukuServiceConnector.get()

    private fun scheduleUpdates() {
        val enabled = getSharedPreferences("czn_settings", 0).getBoolean("auto_download", true)
        val wm = WorkManager.getInstance(this)
        if (!enabled) {
            wm.cancelUniqueWork("czn-updates")
            return
        }
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).setRequiresStorageNotLow(true).build()
        val request = PeriodicWorkRequest.Builder(UpdateWorker::class.java, 12, TimeUnit.HOURS).setConstraints(constraints).build()
        wm.enqueueUniquePeriodicWork("czn-updates", ExistingPeriodicWorkPolicy.KEEP, request)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCompanionIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleCompanionIntent(intent)
    }

    private fun handleCompanionIntent(i: Intent?) {
        if (i?.getBooleanExtra("open_companion_dialog", false) == true) {
            i.removeExtra("open_companion_dialog")
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, "vn.czn.viethoa/patcher").invokeMethod("openCompanionDialog", null)
            }
        }
    }

    override fun onDestroy() {
        synchronized(handoffLock) {
            handoffsClosed = true
            downloadHandoffs.values.forEach { it.second.close() }
            downloadHandoffs.clear()
        }
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        super.onDestroy()
    }
}
