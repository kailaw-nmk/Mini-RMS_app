package com.tailcall.tailcall

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {

    companion object {
        const val CHANNEL_ID_STANDBY = "tailcall_standby"
        const val CHANNEL_ID_CALL = "tailcall_active_call"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START_STANDBY = "com.tailcall.START_STANDBY"
        const val ACTION_START_CALL = "com.tailcall.START_CALL"
        const val ACTION_STOP = "com.tailcall.STOP_FOREGROUND"
        const val ACTION_UPDATE = "com.tailcall.UPDATE_NOTIFICATION"
        const val EXTRA_STATUS_TEXT = "status_text"
        const val EXTRA_DURATION = "duration"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var isInCallMode = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_STANDBY -> startStandbyMode()
            ACTION_START_CALL -> upgradeToCallMode()
            ACTION_STOP -> stopForegroundService()
            ACTION_UPDATE -> updateNotification(
                intent.getStringExtra(EXTRA_STATUS_TEXT) ?: "待機中",
                intent.getStringExtra(EXTRA_DURATION) ?: ""
            )
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Standby channel — minimal presence
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID_STANDBY,
                "TailCall 待機",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "サーバー接続中・着信待機"
                setShowBadge(false)
            })

            // Active call channel — visible but no sound
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID_CALL,
                "TailCall 通話",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "通話中の接続状態を表示"
                setShowBadge(false)
            })
        }
    }

    private fun buildNotification(channelId: String, title: String, statusText: String, duration: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = if (duration.isNotEmpty()) "$statusText — $duration" else statusText

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setCategory(if (channelId == CHANNEL_ID_CALL) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_SERVICE)
            .setPriority(if (channelId == CHANNEL_ID_CALL) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_MIN)
            .build()
    }

    /**
     * Standby mode: started on server connect (before any call).
     * Keeps the app alive in the background while waiting for incoming calls.
     * Uses IMPORTANCE_MIN notification — barely visible in notification shade.
     */
    private fun startStandbyMode() {
        val notification = buildNotification(
            CHANNEL_ID_STANDBY, "TailCall", "着信待機中", ""
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        isInCallMode = false
    }

    /**
     * Call mode: upgraded when a call starts.
     * Acquires PARTIAL_WAKE_LOCK and shows visible notification.
     */
    private fun upgradeToCallMode() {
        val notification = buildNotification(
            CHANNEL_ID_CALL, "TailCall", "管制と接続中", ""
        )

        // Re-post notification with call channel
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)

        // Acquire wake lock only during active call
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "TailCall::CallWakeLock"
            ).apply {
                acquire(8 * 60 * 60 * 1000L) // 8 hours max
            }
        }

        isInCallMode = true
    }

    private fun updateNotification(statusText: String, duration: String) {
        val channelId = if (isInCallMode) CHANNEL_ID_CALL else CHANNEL_ID_STANDBY
        val title = if (isInCallMode) "TailCall" else "TailCall"
        val notification = buildNotification(channelId, title, statusText, duration)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundService() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
        isInCallMode = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        super.onDestroy()
    }
}
