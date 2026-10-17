package vn.czn.viethoa.czn_patcher

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Movie
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.view.*
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast

class AnimatedGifView(context: Context) : View(context) {
    private var movie: Movie? = null
    private var movieStart: Long = 0L

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun setGifBytes(data: ByteArray) {
        movie = try {
            Movie.decodeByteArray(data, 0, data.size)
        } catch (_: Exception) {
            null
        }
        movieStart = 0L
        invalidate()
    }

    val isGifLoaded: Boolean get() = movie != null && (movie?.duration() ?: 0) > 0

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val m = movie ?: return
        val now = SystemClock.uptimeMillis()
        if (movieStart == 0L) {
            movieStart = now
        }
        val dur = if (m.duration() > 0) m.duration() else 1000
        val relTime = ((now - movieStart) % dur).toInt()
        m.setTime(relTime)

        val mw = m.width().coerceAtLeast(1)
        val mh = m.height().coerceAtLeast(1)
        val scale = Math.min(width.toFloat() / mw, height.toFloat() / mh)
        val dx = (width - mw * scale) / 2f
        val dy = (height - mh * scale) / 2f

        canvas.save()
        canvas.translate(dx, dy)
        canvas.scale(scale, scale)
        m.draw(canvas, 0f, 0f)
        canvas.restore()

        postInvalidateOnAnimation()
    }
}

class ChibiOverlayService : Service() {

    companion object {
        const val CHANNEL_ID = "czn_chibi_overlay_channel"
        const val NOTIFICATION_ID = 20261015
        const val ACTION_START = "vn.czn.viethoa.action.START_CHIBI_OVERLAY"
        const val ACTION_STOP = "vn.czn.viethoa.action.STOP_CHIBI_OVERLAY"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        showOverlayView()
        isRunning = true
        getSharedPreferences("czn_settings", Context.MODE_PRIVATE).edit()
            .putBoolean("overlay_enabled", true)
            .apply()

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nhân vật Chibi nổi ngoài màn hình",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Hiển thị nhân vật Chibi đồng hành trên các ứng dụng khác"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val openPendingIntent = PendingIntent.getActivity(this, 0, openAppIntent, flags)

        val stopIntent = Intent(this, ChibiOverlayService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(this, 1, stopIntent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("Nhân vật Chibi đang hiển thị")
            .setContentText("Chạm Chibi để mở app · Kéo thả để di chuyển")
            .setSmallIcon(R.drawable.ic_czn_foreground)
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "Tắt Chibi",
                    stopPendingIntent
                ).build()
            )

        return builder.build()
    }

    private fun showOverlayView() {
        if (overlayView != null) return

        try {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val sizeDp = 76
            val sizePx = (sizeDp * resources.displayMetrics.density).toInt()

            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                sizePx,
                sizePx,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                val prefs = getSharedPreferences("czn_settings", Context.MODE_PRIVATE)
                val dm = resources.displayMetrics
                val defaultX = (dm.widthPixels - sizePx - (12 * dm.density).toInt()).coerceAtLeast(0)
                val defaultY = (dm.heightPixels * 0.4).toInt().coerceAtLeast(0)
                x = prefs.getInt("overlay_x", defaultX)
                y = prefs.getInt("overlay_y", defaultY)
            }
            layoutParams = params

            val container = FrameLayout(this)
            val gifBytes = loadChibiBytes()
            if (gifBytes != null) {
                val gifView = AnimatedGifView(this).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    setGifBytes(gifBytes)
                }
                if (gifView.isGifLoaded) {
                    container.addView(gifView)
                } else {
                    val fallbackBmp = BitmapFactory.decodeByteArray(gifBytes, 0, gifBytes.size)
                    val iv = ImageView(this).apply {
                        layoutParams = FrameLayout.LayoutParams(
                            FrameLayout.LayoutParams.MATCH_PARENT,
                            FrameLayout.LayoutParams.MATCH_PARENT
                        )
                        scaleType = ImageView.ScaleType.FIT_CENTER
                        if (fallbackBmp != null) setImageBitmap(fallbackBmp) else setImageResource(R.mipmap.ic_launcher_czn)
                    }
                    container.addView(iv)
                }
            } else {
                val iv = ImageView(this).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setImageResource(R.mipmap.ic_launcher_czn)
                }
                container.addView(iv)
            }

            val touchSlop = ViewConfiguration.get(this).scaledTouchSlop
            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f
            var touchStartTime = 0L

            container.setOnTouchListener { v, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        touchStartTime = System.currentTimeMillis()
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        val dm = resources.displayMetrics
                        val maxX = (dm.widthPixels - sizePx).coerceAtLeast(0)
                        val maxY = (dm.heightPixels - sizePx).coerceAtLeast(0)
                        params.x = (initialX + dx).coerceIn(0, maxX)
                        params.y = (initialY + dy).coerceIn(0, maxY)
                        windowManager?.updateViewLayout(container, params)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        val dist = Math.hypot(
                            (event.rawX - initialTouchX).toDouble(),
                            (event.rawY - initialTouchY).toDouble()
                        )
                        val duration = System.currentTimeMillis() - touchStartTime
                        if (dist < touchSlop && duration < 350) {
                            v.performClick()
                            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                putExtra("open_companion_dialog", true)
                            }
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                            }
                        } else {
                            val dm = resources.displayMetrics
                            val maxX = (dm.widthPixels - sizePx).coerceAtLeast(0)
                            val midScreen = dm.widthPixels / 2
                            // Magnet snap to nearest edge
                            val targetX = if (params.x + sizePx / 2 < midScreen) 0 else maxX
                            params.x = targetX
                            windowManager?.updateViewLayout(container, params)

                            getSharedPreferences("czn_settings", Context.MODE_PRIVATE).edit()
                                .putInt("overlay_x", params.x)
                                .putInt("overlay_y", params.y)
                                .apply()
                        }
                        true
                    }
                    else -> false
                }
            }

            container.setOnClickListener {}

            windowManager?.addView(container, params)
            overlayView = container
        } catch (e: Exception) {
            isRunning = false
        }
    }

    private fun loadChibiBytes(): ByteArray? {
        val candidates = listOf(
            "flutter_assets/assets/companion.gif",
            "assets/companion.gif",
            "flutter_assets/assets/companion_still.png",
            "assets/companion_still.png"
        )
        for (path in candidates) {
            try {
                assets.open(path).use { stream ->
                    val b = stream.readBytes()
                    if (b.isNotEmpty()) return b
                }
            } catch (_: Exception) {}
        }
        return null
    }

    override fun onDestroy() {
        if (overlayView != null && windowManager != null) {
            try {
                windowManager?.removeView(overlayView)
            } catch (_: Exception) {}
            overlayView = null
        }
        isRunning = false
        getSharedPreferences("czn_settings", Context.MODE_PRIVATE).edit()
            .putBoolean("overlay_enabled", false)
            .apply()
        super.onDestroy()
    }
}
