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
        const val CHANNEL_ID = "tailcall_active_call"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.tailcall.START_FOREGROUND"
        const val ACTION_STOP = "com.tailcall.STOP_FOREGROUND"
        const val ACTION_UPDATE = "com.tailcall.UPDATE_NOTIFICATION"
        const val EXTRA_STATUS_TEXT = "status_text"
        const val EXTRA_DURATION = "duration"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startForegroundService()
            ACTION_STOP -> stopForegroundService()
            ACTION_UPDATE -> updateNotification(
                intent.getStringExtra(EXTRA_STATUS_TEXT) ?: "接続中",
                intent.getStringExtra(EXTRA_DURATION) ?: ""
            )
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TailCall 通話",
                NotificationManager.IMPORTANCE_LOW // No sound
            ).apply {
                description = "通話中の接続状態を表示します"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(statusText: String, duration: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = if (duration.isNotEmpty()) "$statusText — $duration" else statusText

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TailCall")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun startForegroundService() {
        val notification = buildNotification("管制と接続中", "")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Acquire partial wake lock to prevent CPU sleep
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "TailCall::CallWakeLock"
        ).apply {
            acquire(8 * 60 * 60 * 1000L) // 8 hours max
        }
    }

    private fun updateNotification(statusText: String, duration: String) {
        val notification = buildNotification(statusText, duration)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundService() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
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
