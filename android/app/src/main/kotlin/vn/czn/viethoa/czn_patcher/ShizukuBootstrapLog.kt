package vn.czn.viethoa.czn_patcher

import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import moe.shizuku.server.IRemoteProcess
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Read-only startup evidence, through the server Binder rather than the failing UserService. */
object ShizukuBootstrapLog {
    private val worker = Executors.newSingleThreadExecutor()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val cancellation = Executors.newSingleThreadExecutor()
    private val cancelling = AtomicBoolean(false)
    private val running = AtomicBoolean(false)
    @Volatile private var lastStarted = 0L
    @Volatile private var report: Map<String, Any?> = mapOf("state" to "not_requested")

    fun snapshot(): Map<String, Any?> = report

    fun capture(packageName: String, since: Long) {
        val now = SystemClock.elapsedRealtime()
        if ((lastStarted != 0L && now - lastStarted < 30_000L) || !running.compareAndSet(false, true)) return
        lastStarted = now
        val process = AtomicReference<IRemoteProcess?>()
        val input = AtomicReference<ParcelFileDescriptor?>()
        val errors = AtomicReference<ParcelFileDescriptor?>()
        val expired = AtomicBoolean(false)
        val completed = AtomicBoolean(false)
        report = mapOf("state" to "collecting", "since" to since)
        val timeout = watchdog.schedule({
            if (completed.compareAndSet(false, true)) {
                expired.set(true)
                report = mapOf("state" to "capture_timeout", "limit_ms" to 3000,
                    "deadline_scope" to "report; Binder RPC cancellation is best effort")
                try { input.get()?.close() } catch (_: Exception) {}
                try { errors.get()?.close() } catch (_: Exception) {}
                // A remote Binder call cannot be forcibly interrupted. Keep it off the
                // deadline scheduler and allow at most one cancellation RPC in flight.
                val child = process.get()
                if (child != null && cancelling.compareAndSet(false, true)) cancellation.execute {
                    try { child.destroy() } catch (_: Exception) {} finally { cancelling.set(false) }
                }
            }
        }, 3, TimeUnit.SECONDS)
        worker.execute {
            try {
                // Fixed argv, no shell or game command. Grant remains enforced by Shizuku.
                val server = IShizukuService.Stub.asInterface(Shizuku.getBinder())
                    ?: throw IllegalStateException("Shizuku server Binder không có.")
                val remote = server.newProcess(arrayOf(
                    "/system/bin/logcat", "-d", "-t", "600", "-v", "threadtime",
                    "ShizukuServiceStarter:V", "UserServiceManager:V", "UserServiceRecord:V",
                    "AndroidRuntime:E", "CznShizuku:I", "*:S"
                ), null, null)
                process.set(remote)
                if (expired.get()) return@execute
                remote.outputStream?.close()
                val fd = remote.inputStream ?: throw IllegalStateException("Không đọc được log Shizuku.")
                input.set(fd)
                if (expired.get()) return@execute
                val bytes = ByteArrayOutputStream()
                ParcelFileDescriptor.AutoCloseInputStream(fd).use { stream ->
                    val buffer = ByteArray(4096)
                    while (!expired.get() && bytes.size() < 65536) {
                        val count = stream.read(buffer, 0, minOf(buffer.size, 65536 - bytes.size()))
                        if (count < 0) break
                        bytes.write(buffer, 0, count)
                    }
                }
                val errFd = remote.errorStream
                errors.set(errFd)
                if (expired.get()) return@execute
                val commandError = if (errFd == null) "" else ParcelFileDescriptor.AutoCloseInputStream(errFd).use {
                    val buffer = ByteArray(1024)
                    val count = it.read(buffer)
                    if (count > 0) String(buffer, 0, count, Charsets.UTF_8) else ""
                }
                val lines = ownLines(bytes.toString("UTF-8"), packageName, since)
                if (completed.compareAndSet(false, true)) report = mapOf(
                    "state" to if (lines.isEmpty()) "no_matching_startup_log" else "captured",
                    "captured_at" to System.currentTimeMillis(), "since" to since,
                    "truncated" to (bytes.size() >= 65536), "lines" to lines,
                    "logcat_error" to commandError.take(1024)
                )
            } catch (error: Exception) {
                if (completed.compareAndSet(false, true)) report = mapOf(
                    "state" to "capture_failed", "error" to (error.message ?: error.javaClass.simpleName).take(1024)
                )
            } finally {
                timeout.cancel(false)
                try { input.get()?.close() } catch (_: Exception) {}
                try { errors.get()?.close() } catch (_: Exception) {}
                // Only this short-lived logcat child is stopped, never Shizuku or the game.
                try { process.get()?.destroy() } catch (_: Exception) {}
                running.set(false)
            }
        }
    }

    private fun ownLines(text: String, packageName: String, since: Long): List<String> {
        val cutoff = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(Date(since - 2000L))
        val row = Regex("^(\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3})\\s+(\\d+)\\s+\\d+\\s+[VDIWEFA]\\s+([^: ]+)\\s*:")
        val rows = text.lineSequence().mapNotNull { line ->
            row.find(line)?.let { match ->
                if (match.groupValues[1] < cutoff) null else Triple(line, match.groupValues[2], match.groupValues[3])
            }
        }.toList()
        val serviceName = PatchUserService::class.java.name
        val childPids = rows.filter { (line, _, tag) ->
            (tag == "ShizukuServiceStarter" || tag == "AndroidRuntime") &&
                (line.contains(packageName) || line.contains(serviceName))
        }.map { it.second }.toSet()
        val ownRows = rows.filter { it.first.contains(packageName) || it.first.contains(serviceName) }
        val token = Regex("[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}")
        val tokens = ownRows.flatMap { token.findAll(it.first).map { match -> match.value }.toList() }.toSet()
        return rows.filter { (line, pid, tag) ->
            line.contains(packageName) || line.contains(serviceName) ||
                (pid in childPids && (tag == "ShizukuServiceStarter" || tag == "AndroidRuntime")) ||
                (tag == "CznShizuku" && pid == Process.myPid().toString()) ||
                ((tag == "UserServiceManager" || tag == "UserServiceRecord") && tokens.any { line.contains(it) })
        }.takeLast(100).map { it.first.take(2048) }
    }
}
