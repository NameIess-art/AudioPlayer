package com.example.music_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.media.app.NotificationCompat.MediaStyle

class PlaybackKeepAliveService : Service() {
    companion object {
        const val ACTION_START = "com.example.music_player.action.START_KEEP_ALIVE"
        const val ACTION_STOP = "com.example.music_player.action.STOP_KEEP_ALIVE"
        const val EXTRA_HAS_ACTIVE_PLAYBACK = "has_active_playback"
        const val EXTRA_HAS_ACTIVE_TIMER = "has_active_timer"
        const val EXTRA_USES_UNIFIED_PLAYBACK_NOTIFICATION =
            "uses_unified_playback_notification"
        const val EXTRA_KEEP_FOREGROUND_SERVICE_ALIVE =
            "keep_foreground_service_alive"

        private const val CHANNEL_ID = "playback_keep_alive"
        private const val UNIFIED_CHANNEL_ID = "com.example.music_player.channel.playback"
        private const val CHANNEL_NAME = "Playback"
        private const val GROUP_KEY = "com.example.music_player.PLAYBACK_GROUP"
        private const val NOTIFICATION_ID = 1107
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentNotificationId: Int? = null
    private var currentForegroundSignature: String? = null
    private var mediaSession: MediaSessionCompat? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                releaseWakeLock()
                releaseMediaSession()
                currentForegroundSignature = null
                currentNotificationId = null
                stopSelf()
                START_NOT_STICKY
            }
            else -> {
                val hasActivePlayback =
                    intent?.getBooleanExtra(EXTRA_HAS_ACTIVE_PLAYBACK, false) == true
                val hasActiveTimer =
                    intent?.getBooleanExtra(EXTRA_HAS_ACTIVE_TIMER, false) == true
                val usesUnifiedPlaybackNotification =
                    intent?.getBooleanExtra(
                        EXTRA_USES_UNIFIED_PLAYBACK_NOTIFICATION,
                        false
                    ) == true
                val keepForegroundServiceAlive =
                    intent?.getBooleanExtra(
                        EXTRA_KEEP_FOREGROUND_SERVICE_ALIVE,
                        false
                    ) == true

                if (!keepForegroundServiceAlive) {
                    stopForegroundCompat()
                    releaseWakeLock()
                    releaseMediaSession()
                    currentForegroundSignature = null
                    currentNotificationId = null
                    stopSelf()
                    START_NOT_STICKY
                } else {
                    createNotificationChannels()
                    syncMediaSession(hasActivePlayback = hasActivePlayback)
                    val foregroundSignature = listOf(
                        NOTIFICATION_ID,
                        hasActivePlayback,
                        hasActiveTimer,
                        usesUnifiedPlaybackNotification,
                        keepForegroundServiceAlive
                    ).joinToString("|")
                    val needsForegroundRefresh =
                        currentNotificationId != NOTIFICATION_ID ||
                            currentForegroundSignature != foregroundSignature

                    if (needsForegroundRefresh) {
                        ServiceCompat.startForeground(
                            this,
                            NOTIFICATION_ID,
                            buildNotification(
                                hasActivePlayback = hasActivePlayback,
                                hasActiveTimer = hasActiveTimer,
                                usesUnifiedPlaybackNotification =
                                    usesUnifiedPlaybackNotification
                            ),
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                        )
                        currentNotificationId = NOTIFICATION_ID
                        currentForegroundSignature = foregroundSignature
                    } else {
                        currentNotificationId = NOTIFICATION_ID
                    }
                    if (hasActivePlayback || hasActiveTimer) {
                        acquireWakeLock()
                    } else {
                        releaseWakeLock()
                    }
                    START_REDELIVER_INTENT
                }
            }
        }
    }

    override fun onDestroy() {
        stopForegroundCompat()
        releaseWakeLock()
        releaseMediaSession()
        currentForegroundSignature = null
        currentNotificationId = null
        super.onDestroy()
    }

    private fun buildNotification(
        hasActivePlayback: Boolean,
        hasActiveTimer: Boolean,
        usesUnifiedPlaybackNotification: Boolean
    ): Notification {
        val contentText = if (hasActiveTimer) {
            "睡眠定时器运行中"
        } else if (usesUnifiedPlaybackNotification) {
            "正在播放"
        } else if (hasActivePlayback) {
            "正在播放"
        } else {
            null
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

        val builder = NotificationCompat.Builder(
            this,
            if (usesUnifiedPlaybackNotification) UNIFIED_CHANNEL_ID else CHANNEL_ID
        )
            .setContentTitle("AudioPlayer")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(
                if (usesUnifiedPlaybackNotification) {
                    NotificationCompat.CATEGORY_TRANSPORT
                } else {
                    NotificationCompat.CATEGORY_SERVICE
                }
            )
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .apply {
                if (!contentText.isNullOrBlank()) {
                    setContentText(contentText)
                }
                if (pendingIntent != null) {
                    setContentIntent(pendingIntent)
                }
                if (usesUnifiedPlaybackNotification) {
                    setGroup(GROUP_KEY)
                    setGroupSummary(true)
                    setSortKey("0_summary")
                } else {
                    ensureMediaSession()?.sessionToken?.let { sessionToken ->
                        setStyle(MediaStyle().setMediaSession(sessionToken))
                    }
                }
            }
        return builder.build()
    }

    private fun syncMediaSession(hasActivePlayback: Boolean) {
        if (!hasActivePlayback) {
            releaseMediaSession()
            return
        }
        val session = ensureMediaSession()
        val playbackState = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_STOP
            )
            .setState(
                if (hasActivePlayback) {
                    PlaybackStateCompat.STATE_PLAYING
                } else {
                    PlaybackStateCompat.STATE_PAUSED
                },
                PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                1f
            )
            .build()
        session.setPlaybackState(playbackState)
        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, "AudioPlayer")
                .putString(
                    MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE,
                    "AudioPlayer"
                )
                .build()
        )
        session.isActive = true
    }

    private fun ensureMediaSession(): MediaSessionCompat {
        mediaSession?.let { return it }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val sessionActivity = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                1,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        return MediaSessionCompat(this, "$packageName.keepalive").also { session ->
            session.setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            if (sessionActivity != null) {
                session.setSessionActivity(sessionActivity)
            }
            mediaSession = session
        }
    }

    private fun releaseMediaSession() {
        mediaSession?.apply {
            isActive = false
            release()
        }
        mediaSession = null
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
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
        if (manager.getNotificationChannel(UNIFIED_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    UNIFIED_CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Playback notification controls"
                    setShowBadge(false)
                }
            )
        }
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
