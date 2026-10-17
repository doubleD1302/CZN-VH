package vn.czn.viethoa.czn_patcher

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.IOException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** Process-owned connection: no Activity references and no retry of game operations. */
object ShizukuServiceConnector {
    class Failure(val code: String, message: String, val diagnostics: Map<String, Any?>) : IOException(message)

    private val main = Handler(Looper.getMainLooper())
    private const val ATTEMPT_MS = 10_000L
    private lateinit var args: Shizuku.UserServiceArgs
    private var configured = false
    private var appPackage = ""
    private var connectionStarted = 0L
    private var current: Attempt? = null
    private var sequence = 0L
    private var staleConnection: ServiceConnection? = null
    private val history = ArrayDeque<Map<String, Any?>>()
    @Volatile private var state: Map<String, Any?> = mapOf("stage" to "idle")

    // Retained for the application process, never for an Activity's lifetime.
    private val binderDead = Shizuku.OnBinderDeadListener {
        current?.let {
            if (it.server !== Shizuku.getBinder() || !Shizuku.pingBinder())
                fail(it, "SHIZUKU_STOPPED", "Shizuku đã ngắt kết nối.", false)
        }
    }
    private val binderReceived = Shizuku.OnBinderReceivedListener {
        // A daemon from an earlier Shizuku server must not be reused after restart.
        current?.let {
            if (it.server !== Shizuku.getBinder())
                fail(it, "SHIZUKU_RESTARTED", "Shizuku vừa khởi động lại. Bấm kiểm tra lại.", true)
        }
        if (current == null) diagnostic("server_ready", 0, null)
    }

    fun configure(context: Context, code: Int) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (configured) return
        appPackage = context.applicationContext.packageName
        args = Shizuku.UserServiceArgs(ComponentName(context.applicationContext, PatchUserService::class.java))
            .daemon(true).processNameSuffix("patch").tag("czn-community-patcher")
            .version(code).debuggable(false)
        Shizuku.addBinderDeadListener(binderDead)
        Shizuku.addBinderReceivedListener(binderReceived)
        configured = true
    }

    fun diagnostics(): Map<String, Any?> = state + ("bootstrap_log" to ShizukuBootstrapLog.snapshot())

    /** Only the caller's worker thread waits. All API bind/detach/state changes are on main. */
    fun get(): ICznService {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Không chờ dịch vụ Shizuku trên luồng giao diện." }
        val result = CompletableFuture<ICznService>()
        main.post { request(result) }
        try {
            return result.get(25, TimeUnit.SECONDS)
        } catch (error: ExecutionException) {
            throw (error.cause ?: error)
        } catch (error: TimeoutException) {
            result.cancel(false)
            main.post {
                current?.let { attempt ->
                    attempt.waiters.remove(result)
                    if (attempt.binder == null && attempt.waiters.isEmpty()) detach(attempt)
                }
            }
            throw Failure("SHIZUKU_CALLBACK_TIMEOUT", "Chưa nhận được phản hồi kết nối Shizuku. Bấm kiểm tra lại.", state)
        } catch (error: InterruptedException) {
            result.cancel(false)
            main.post {
                current?.let { attempt ->
                    attempt.waiters.remove(result)
                    if (attempt.binder == null && attempt.waiters.isEmpty()) detach(attempt)
                }
            }
            Thread.currentThread().interrupt()
            throw error
        }
    }

    private fun request(result: CompletableFuture<ICznService>) {
        if (result.isDone) return
        try {
            check(configured) { "Bộ kết nối Shizuku chưa sẵn sàng." }
            check(Process.myUid() / 100000 == 0) { "Patcher chỉ hỗ trợ hồ sơ Android chính. Không dùng Không gian thứ hai/Ứng dụng kép." }
            if (!Shizuku.pingBinder()) throw Failure("SHIZUKU_NOT_RUNNING", "Hãy khởi động Shizuku trước.", state)
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED)
                throw Failure("SHIZUKU_PERMISSION", "Cấp quyền Shizuku cho CZN Việt Hóa trước.", state)
            current?.let { attempt ->
                val binder = attempt.binder
                if (binder != null && binder.isBinderAlive && attempt.server === Shizuku.getBinder()) {
                    result.complete(ICznService.Stub.asInterface(binder))
                    return
                }
                if (binder == null && attempt.server === Shizuku.getBinder()) {
                    attempt.waiters.add(result)
                    return
                }
                fail(attempt, "SHIZUKU_STALE_CONNECTION", "Kết nối dịch vụ vá cũ không còn hiệu lực. Bấm kiểm tra lại.", false)
            }
            start(mutableListOf(result), 1)
        } catch (error: Exception) {
            result.completeExceptionally(error)
        }
    }

    private class Attempt(val id: Long, val number: Int, val waiters: MutableList<CompletableFuture<ICznService>>, val server: IBinder?) {
        lateinit var connection: ServiceConnection
        lateinit var timeout: Runnable
        var binder: IBinder? = null
        var death: IBinder.DeathRecipient? = null
    }

    private fun start(waiters: MutableList<CompletableFuture<ICznService>>, number: Int) {
        waiters.removeAll { it.isDone }
        if (waiters.isEmpty()) return
        // A previous detach may have failed while the Shizuku server was down.
        // Clear the SDK tag cache before registering another callback for that tag.
        try {
            staleConnection?.let { Shizuku.unbindUserService(args, it, false) }
            staleConnection = null
        } catch (error: Exception) {
            diagnostic("SHIZUKU_DETACH_FAILED", number, error.message)
            val failure = Failure("SHIZUKU_DETACH_FAILED", "Chưa làm mới được kết nối Shizuku: ${error.message ?: error.javaClass.simpleName}", state)
            waiters.forEach { it.completeExceptionally(failure) }
            return
        }
        val attempt = Attempt(++sequence, number, waiters, Shizuku.getBinder())
        attempt.connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                if (current !== attempt) return // Never complete a later attempt from an old callback.
                if (attempt.server !== Shizuku.getBinder()) {
                    fail(attempt, "SHIZUKU_RESTARTED", "Shizuku vừa khởi động lại trong lúc kết nối.", true)
                    return
                }
                if (attempt.binder != null) return // SDK may deliver the same connected callback again.
                if (binder == null || !binder.isBinderAlive) {
                    fail(attempt, "SHIZUKU_DEAD_SERVICE", "Dịch vụ vá chưa trả kết nối hợp lệ.", true)
                    return
                }
                try {
                    val death = IBinder.DeathRecipient { main.post {
                        fail(attempt, "SHIZUKU_SERVICE_DIED", "Dịch vụ vá đã ngắt kết nối. Bấm kiểm tra lại.", true)
                    } }
                    binder.linkToDeath(death, 0)
                    attempt.binder = binder
                    attempt.death = death
                    main.removeCallbacks(attempt.timeout)
                    diagnostic("connected", attempt.number, null)
                    val service = ICznService.Stub.asInterface(binder)
                    attempt.waiters.forEach { it.complete(service) }
                    attempt.waiters.clear()
                } catch (error: Exception) {
                    fail(attempt, "SHIZUKU_DEAD_SERVICE", error.message ?: "Dịch vụ vá đã ngắt kết nối.", true)
                }
            }
            override fun onServiceDisconnected(name: ComponentName?) {
                fail(attempt, "SHIZUKU_SERVICE_DISCONNECTED", "Dịch vụ vá đã ngắt kết nối. Bấm kiểm tra lại.", true)
            }
            override fun onBindingDied(name: ComponentName?) {
                fail(attempt, "SHIZUKU_SERVICE_DIED", "Kết nối dịch vụ vá không còn hiệu lực.", true)
            }
            override fun onNullBinding(name: ComponentName?) {
                fail(attempt, "SHIZUKU_NULL_BINDING", "Không nhận được Binder của dịch vụ vá.", true)
            }
        }
        attempt.timeout = Runnable {
            fail(attempt, "SHIZUKU_BIND_TIMEOUT", "Dịch vụ vá chưa phản hồi trong 10s (lượt ${attempt.number}/2). Bấm kiểm tra lại và gửi báo cáo lỗi.", true)
        }
        current = attempt
        if (number == 1) connectionStarted = System.currentTimeMillis()
        diagnostic("binding", number, null)
        main.postDelayed(attempt.timeout, ATTEMPT_MS)
        try {
            Shizuku.bindUserService(args, attempt.connection)
        } catch (error: Exception) {
            Log.w("CznShizuku", "UserService bind failed", error)
            fail(attempt, "SHIZUKU_BIND_FAILED", "Không khởi tạo được kết nối dịch vụ vá: ${error.message ?: error.javaClass.simpleName}", true)
        }
    }

    private fun fail(attempt: Attempt, code: String, message: String, retry: Boolean) {
        if (current !== attempt) return
        val waiters = attempt.waiters.toMutableList()
        attempt.waiters.clear()
        detach(attempt)
        diagnostic(code, attempt.number, message)
        // Detach clears the SDK's entire cache for this tag. Finish it before a new bind.
        val canRetry = retry && attempt.number < 2 && waiters.any { !it.isDone } && try {
            Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) { false }
        if (canRetry) {
            start(waiters, attempt.number + 1)
        } else {
            if (code == "SHIZUKU_BIND_TIMEOUT" || code == "SHIZUKU_BIND_FAILED")
                ShizukuBootstrapLog.capture(appPackage, connectionStarted)
            val error = Failure(code, message, state)
            waiters.forEach { it.completeExceptionally(error) }
        }
    }

    private fun detach(attempt: Attempt) {
        if (current !== attempt) return
        current = null // Reject callbacks delivered synchronously during unbind too.
        main.removeCallbacks(attempt.timeout)
        attempt.death?.let { death -> try { attempt.binder?.unlinkToDeath(death, 0) } catch (_: Exception) {} }
        try {
            // remove=false disconnects callbacks. Never stop a daemon that may be writing game data.
            Shizuku.unbindUserService(args, attempt.connection, false)
        } catch (error: Exception) {
            staleConnection = attempt.connection
            Log.w("CznShizuku", "Detach failed", error)
        }
    }

    private fun diagnostic(stage: String, attempt: Int, message: String?) {
        val event = mapOf("stage" to stage, "attempt" to attempt, "time" to System.currentTimeMillis(), "message" to message)
        history.addLast(event)
        while (history.size > 12) history.removeFirst()
        state = event + ("events" to history.toList())
        Log.i("CznShizuku", "stage=$stage attempt=$attempt ${message ?: ""}")
    }
}
