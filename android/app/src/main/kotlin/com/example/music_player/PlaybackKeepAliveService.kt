package com.example.music_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class PlaybackKeepAliveService : Service() {
    companion object {
        const val ACTION_START = "com.example.music_player.action.START_KEEP_ALIVE"
        const val ACTION_STOP = "com.example.music_player.action.STOP_KEEP_ALIVE"
        const val EXTRA_HAS_ACTIVE_PLAYBACK = "has_active_playback"
        const val EXTRA_HAS_ACTIVE_TIMER = "has_active_timer"

        private const val CHANNEL_ID = "playback_keep_alive"
        private const val CHANNEL_NAME = "Playback"
        private const val NOTIFICATION_ID = 1107
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                releaseWakeLock()
                stopSelf()
                START_NOT_STICKY
            }
            else -> {
                val hasActivePlayback =
                    intent?.getBooleanExtra(EXTRA_HAS_ACTIVE_PLAYBACK, false) == true
                val hasActiveTimer =
                    intent?.getBooleanExtra(EXTRA_HAS_ACTIVE_TIMER, false) == true

                createNotificationChannel()
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(
                        hasActivePlayback = hasActivePlayback,
                        hasActiveTimer = hasActiveTimer
                    )
                )
                acquireWakeLock()
                START_STICKY
            }
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun buildNotification(
        hasActivePlayback: Boolean,
        hasActiveTimer: Boolean
    ): Notification {
        val contentText = when {
            hasActivePlayback && hasActiveTimer -> "Playback and sleep timer are active."
            hasActivePlayback -> "Playback is running in the background."
            hasActiveTimer -> "Sleep timer is running in the background."
            else -> "Background keep-alive is active."
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AsmrPlayer")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .apply {
                if (pendingIntent != null) {
                    setContentIntent(pendingIntent)
                }
            }
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps playback alive while audio or timer is active."
                setShowBadge(false)
            }
        )
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return

        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:playback_keep_alive"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            wakeLock = null
        }
    }

    private fun releaseWakeLock() {
        val currentWakeLock = wakeLock ?: return
        try {
            if (currentWakeLock.isHeld) {
                currentWakeLock.release()
            }
        } catch (_: RuntimeException) {
            // Ignore stale wakelock state.
        } finally {
            wakeLock = null
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
