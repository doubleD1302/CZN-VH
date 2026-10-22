package vn.czn.viethoa.czn_patcher

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import io.github.muntashirakon.adb.android.AdbMdns
import java.net.InetAddress
import java.util.concurrent.Executors

object AdbNotificationPairer {
    private const val TAG = "CZN_PAIR"
    const val CHANNEL_ID = "czn_adb_pairing"
    const val NOTIFICATION_ID = 2026
    const val KEY_PAIRING_INPUT = "czn_pairing_input"
    const val ACTION_PAIR = "vn.czn.viethoa.ACTION_PAIR_ADB"
    const val ACTION_CANCEL = "vn.czn.viethoa.ACTION_CANCEL_PAIR_ADB"

    @Volatile
    var discoveredPairingPort: Int = -1
        private set

    @Volatile
    var discoveredConnectPort: Int = -1
        private set

    private var mdnsPairing: AdbMdns? = null
    private var mdnsConnect: AdbMdns? = null
    private val executor = Executors.newSingleThreadExecutor()
    private var isPairingActive = false

    fun start(context: Context) {
        val appContext = context.applicationContext
        isPairingActive = true
        discoveredPairingPort = -1
        discoveredConnectPort = -1

        initChannel(appContext)

        // Khởi động mDNS dò tìm cổng Pairing
        try {
            mdnsPairing?.stop()
            mdnsPairing = AdbMdns(appContext, AdbMdns.SERVICE_TYPE_TLS_PAIRING) { addr: InetAddress?, port: Int ->
                Log.d(TAG, "mDNS phát hiện cổng Ghép nối: $port từ $addr")
                discoveredPairingPort = port
                updateNotification(
                    appContext,
                    "🎯 Đã tìm thấy cổng Ghép nối ($port)!",
                    "Pop-up mã 6 số đang mở! Bấm 'Nhập mã ghép nối' bên dưới để nhập mã 6 số."
                )
            }
            mdnsPairing?.start()
            Log.d(TAG, "Đã khởi động mDNS Pairing Discovery")
        } catch (t: Throwable) {
            Log.w(TAG, "Không thể khởi động mDNS Pairing: ${t.message}")
        }

        // Khởi động mDNS dò tìm cổng Connect
        try {
            mdnsConnect?.stop()
            mdnsConnect = AdbMdns(appContext, AdbMdns.SERVICE_TYPE_TLS_CONNECT) { addr: InetAddress?, port: Int ->
                Log.d(TAG, "mDNS phát hiện cổng Kết nối: $port từ $addr")
                discoveredConnectPort = port
            }
            mdnsConnect?.start()
            Log.d(TAG, "Đã khởi động mDNS Connect Discovery")
        } catch (t: Throwable) {
            Log.w(TAG, "Không thể khởi động mDNS Connect: ${t.message}")
        }

        // Phát thông báo chờ ban đầu
        updateNotification(
            appContext,
            "Ghép nối Local ADB (Gỡ lỗi không dây)",
            "1. Bấm 'Mở Cài đặt' ➔ Vào 'Gỡ lỗi không dây' ➔ Bấm 'Ghép nối bằng mã ghép nối'.\n2. Nhập mã 6 số (hoặc mã:cổng) trực tiếp tại đây."
        )
    }

    fun stop(context: Context? = null) {
        isPairingActive = false
        try {
            mdnsPairing?.stop()
            mdnsPairing = null
        } catch (_: Throwable) {}
        try {
            mdnsConnect?.stop()
            mdnsConnect = null
        } catch (_: Throwable) {}

        if (context != null) {
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(NOTIFICATION_ID)
            } catch (_: Throwable) {}
        }
    }

    private fun initChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ghép nối Local ADB",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Hỗ trợ nhập mã ghép nối Local ADB trực tiếp từ thanh thông báo mà không bị đóng cửa sổ Cài đặt."
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }
    }

    fun updateNotification(
        context: Context,
        title: String,
        content: String,
        ongoing: Boolean = true,
        showInput: Boolean = true
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        val settingsIntent = Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
        val pendingSettings = PendingIntent.getActivity(
            context,
            201,
            settingsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pairReceiverIntent = Intent(context, AdbPairingReceiver::class.java).apply {
            action = ACTION_PAIR
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingPair = PendingIntent.getBroadcast(context, 202, pairReceiverIntent, flags)

        val cancelReceiverIntent = Intent(context, AdbPairingReceiver::class.java).apply {
            action = ACTION_CANCEL
        }
        val pendingCancel = PendingIntent.getBroadcast(context, 203, cancelReceiverIntent, PendingIntent.FLAG_IMMUTABLE)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher_czn)
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .addAction(0, "Mở Cài đặt", pendingSettings)

        if (showInput) {
            val remoteInput = RemoteInput.Builder(KEY_PAIRING_INPUT)
                .setLabel("Nhập mã 6 số (hoặc mã:cổng)")
                .build()

            val actionInput = NotificationCompat.Action.Builder(
                0,
                "Nhập mã ghép nối",
                pendingPair
            ).addRemoteInput(remoteInput).build()

            builder.addAction(actionInput)
        }

        if (ongoing) {
            builder.addAction(0, "Hủy", pendingCancel)
        }

        nm.notify(NOTIFICATION_ID, builder.build())
    }

    fun handlePairingInput(context: Context, rawInput: String) {
        executor.execute {
            try {
                val trimmed = rawInput.trim()
                Log.d(TAG, "Nhận input ghép nối từ Notification: $trimmed")

                // Phân tích input: có thể là "123456", "123456:37123", hoặc "123456 37123"
                val tokens = trimmed.split(Regex("[:\\s,]+")).filter { it.isNotEmpty() }
                var code = ""
                var port = -1

                if (tokens.size == 1) {
                    val single = tokens[0]
                    if (single.length == 6 && single.all { it.isDigit() }) {
                        code = single
                        port = discoveredPairingPort
                    }
                } else if (tokens.size >= 2) {
                    val t1 = tokens[0]
                    val t2 = tokens[1]
                    if (t1.length == 6 && t1.all { it.isDigit() }) {
                        code = t1
                        port = t2.toIntOrNull() ?: -1
                    } else if (t2.length == 6 && t2.all { it.isDigit() }) {
                        code = t2
                        port = t1.toIntOrNull() ?: -1
                    } else {
                        code = t1
                        port = t2.toIntOrNull() ?: -1
                    }
                }

                if (code.isBlank() || !code.all { it.isDigit() }) {
                    updateNotification(
                        context,
                        "❌ Mã ghép nối không hợp lệ",
                        "Mã phải gồm 6 chữ số (ví dụ: 123456). Vui lòng thử lại.",
                        ongoing = true,
                        showInput = true
                    )
                    return@execute
                }

                if (port <= 0 || port > 65535) {
                    updateNotification(
                        context,
                        "⚠️ Chưa phát hiện được Cổng ghép nối",
                        "mDNS chưa bắt được cổng. Vui lòng nhập theo định dạng: [Mã 6 số]:[Cổng 5 số]\nVí dụ: $code:37123",
                        ongoing = true,
                        showInput = true
                    )
                    return@execute
                }

                updateNotification(
                    context,
                    "⏳ Đang ghép nối Local ADB...",
                    "Đang ghép nối với cổng $port bằng mã $code...",
                    ongoing = true,
                    showInput = false
                )

                val paired = LocalAdbManager.pairDevice("127.0.0.1", port, code)
                if (paired) {
                    Log.d(TAG, "Ghép nối thành công! Đang thử kết nối daemon...")
                    val connPort = discoveredConnectPort
                    var connected = false
                    if (connPort > 0) {
                        try {
                            connected = LocalAdbManager.connectDevice("127.0.0.1", connPort)
                        } catch (ce: Throwable) {
                            Log.w(TAG, "Không thể tự kết nối cổng $connPort: ${ce.message}")
                        }
                    }

                    val successMsg = if (connected) {
                        "Đã ghép nối và kết nối ADB thành công! Bạn có thể quay lại app CZN để bắt đầu."
                    } else {
                        "Ghép nối thành công! Hãy mở lại app CZN và bấm 'Kết nối'."
                    }

                    updateNotification(
                        context,
                        "🎉 Ghép nối Local ADB thành công!",
                        successMsg,
                        ongoing = false,
                        showInput = false
                    )

                    // Tự động dừng mDNS và dọn thông báo sau 10 giây
                    executor.execute {
                        try {
                            Thread.sleep(10000)
                            stop(context)
                        } catch (_: Throwable) {}
                    }
                } else {
                    updateNotification(
                        context,
                        "❌ Ghép nối thất bại",
                        "Thiết bị từ chối ghép nối. Hãy mở lại pop-up mã mới và thử lại.",
                        ongoing = false,
                        showInput = true
                    )
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Lỗi khi xử lý ghép nối: ${t.message}", t)
                updateNotification(
                    context,
                    "❌ Ghép nối lỗi: ${t.message}",
                    "Vui lòng mở lại hộp thoại pop-up 'Ghép nối bằng mã ghép nối' và thử lại.",
                    ongoing = false,
                    showInput = true
                )
            }
        }
    }
}
