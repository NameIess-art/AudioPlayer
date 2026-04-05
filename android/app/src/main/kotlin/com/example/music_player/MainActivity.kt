package com.example.music_player

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.ContentUris
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.graphics.Bitmap
import android.util.LruCache
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import androidx.media.app.NotificationCompat.MediaStyle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import java.util.Locale

private object PlaybackWakeLockController {
    private var wakeLock: PowerManager.WakeLock? = null

    @Synchronized
    fun sync(context: Context, enabled: Boolean) {
        if (enabled) {
            acquire(context.applicationContext)
        } else {
            release()
        }
    }

    private fun acquire(context: Context) {
        if (wakeLock?.isHeld == true) return
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "${context.packageName}:playback_keep_alive"
            )?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            wakeLock = null
        }
    }

    private fun release() {
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
}

private data class UnifiedPlaybackNotificationItem(
    val id: String,
    val title: String,
    val subtitle: String?,
    val artPath: String?,
    val playing: Boolean,
    val hasPrevious: Boolean,
    val hasNext: Boolean
)

private object UnifiedPlaybackNotificationController {
    private const val channelId = "com.example.music_player.channel.playback"
    private const val channelName = "Playback"
    private const val channelDescription = "Playback notification controls"
    private const val groupKey = "com.example.music_player.PLAYBACK_GROUP"
    private const val summaryNotificationId = 11_225
    private const val prefsName = "music_player_notifications"
    private const val activeIdsKey = "active_notification_ids"
    private val activeNotificationIds = linkedSetOf<Int>()
    private val activeItemsById = linkedMapOf<String, UnifiedPlaybackNotificationItem>()
    private val artCache = object : LruCache<String, Bitmap>(12) {}
    private var lastSummarySignature: String? = null

    @Synchronized
    fun sync(
        context: Context,
        items: List<UnifiedPlaybackNotificationItem>,
        showSummary: Boolean,
        summaryText: String?,
        summaryLines: List<String>
    ) {
        val manager = NotificationManagerCompat.from(context)
        ensureChannel(context)

        if (items.isEmpty()) {
            clear(context)
            return
        }

        val previousIds = buildSet {
            addAll(activeNotificationIds)
            addAll(loadPersistedNotificationIds(context))
        }
        val nextIds = mutableSetOf<Int>()
        for (item in items) {
            val notificationId = notificationIdFor(item.id)
            if (activeItemsById[item.id] != item) {
                manager.notify(notificationId, buildChildNotification(context, item))
            }
            nextIds.add(notificationId)
        }

        val summarySignature = if (showSummary) {
            buildString {
                append(summaryText.orEmpty())
                append('\u0000')
                append(summaryLines.joinToString("\n"))
                append('\u0000')
                append(items.size)
            }
        } else {
            null
        }
        if (showSummary) {
            if (summarySignature != lastSummarySignature) {
                manager.notify(
                    summaryNotificationId,
                    buildSummaryNotification(context, items, summaryText, summaryLines)
                )
            }
        } else {
            manager.cancel(summaryNotificationId)
        }

        val staleIds = previousIds.filterNot(nextIds::contains)
        staleIds.forEach(manager::cancel)
        val activeSessionIds = items.mapTo(mutableSetOf()) { it.id }
        activeItemsById.keys
            .filterNot(activeSessionIds::contains)
            .toList()
            .forEach(activeItemsById::remove)
        items.forEach { item ->
            activeItemsById[item.id] = item
        }

        activeNotificationIds.apply {
            clear()
            addAll(nextIds)
        }
        lastSummarySignature = summarySignature
        savePersistedNotificationIds(context, nextIds)
    }

    @Synchronized
    fun clear(context: Context) {
        val manager = NotificationManagerCompat.from(context)
        val previousIds = buildSet {
            addAll(activeNotificationIds)
            addAll(loadPersistedNotificationIds(context))
        }
        previousIds.forEach(manager::cancel)
        manager.cancel(summaryNotificationId)
        activeNotificationIds.clear()
        activeItemsById.clear()
        lastSummarySignature = null
        savePersistedNotificationIds(context, emptySet())
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        val existing = manager.getNotificationChannel(channelId)
        if (existing != null) return

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = channelDescription
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildChildNotification(
        context: Context,
        item: UnifiedPlaybackNotificationItem
    ): android.app.Notification {
        val subtitle = item.subtitle?.takeIf { it.isNotBlank() }
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(item.title)
            .setContentText(subtitle)
            .setSubText(null)
            .setContentIntent(buildLaunchIntent(context, sessionId = item.id))
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setGroup(groupKey)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
            .setSortKey("1_${item.title}_${item.id}")

        resolveLargeIcon(item.artPath)?.let(builder::setLargeIcon)

        val compactActionIndices = mutableListOf<Int>()
        var actionIndex = 0

        if (item.hasPrevious) {
            builder.addAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                buildControlIntent(context, item.id, NotificationCommand.previous)
            )
            compactActionIndices.add(actionIndex)
            actionIndex += 1
        }
        builder.addAction(
            if (item.playing) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            },
            if (item.playing) "Pause" else "Play",
            buildControlIntent(context, item.id, NotificationCommand.toggle)
        )
        compactActionIndices.add(actionIndex)
        actionIndex += 1
        if (item.hasNext) {
            builder.addAction(
                android.R.drawable.ic_media_next,
                "Next",
                buildControlIntent(context, item.id, NotificationCommand.next)
            )
            compactActionIndices.add(actionIndex)
        }

        val mediaStyle = MediaStyle()
            .setShowActionsInCompactView(*compactActionIndices.toIntArray())
        builder.setStyle(mediaStyle)
        return builder.build()
    }

    private fun buildSummaryNotification(
        context: Context,
        items: List<UnifiedPlaybackNotificationItem>,
        summaryText: String?,
        summaryLines: List<String>
    ): android.app.Notification {
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("AudioPlayer")
            .setContentText(summaryText ?: "${items.size} sessions")
            .setContentIntent(buildLaunchIntent(context))
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setGroup(groupKey)
            .setGroupSummary(true)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
            .setSortKey("0_summary")

        val inboxStyle = NotificationCompat.InboxStyle()
            .setBigContentTitle("AudioPlayer")
        if (summaryLines.isEmpty()) {
            items.forEach { item ->
                inboxStyle.addLine(item.title)
            }
        } else {
            summaryLines.forEach(inboxStyle::addLine)
        }
        builder.setStyle(inboxStyle)
        return builder.build()
    }

    private fun buildLaunchIntent(
        context: Context,
        sessionId: String? = null
    ): PendingIntent? {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
                if (sessionId.isNullOrBlank()) {
                    removeExtra(MainActivity.notificationSessionIdExtra)
                } else {
                    action = MainActivity.openSessionFromNotificationAction
                    putExtra(MainActivity.notificationSessionIdExtra, sessionId)
                }
            }
            ?: return null
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        )
        val requestCode = if (sessionId.isNullOrBlank()) {
            0
        } else {
            notificationIdFor(sessionId)
        }
        return PendingIntent.getActivity(context, requestCode, launchIntent, flags)
    }

    private fun buildControlIntent(
        context: Context,
        sessionId: String,
        command: NotificationCommand
    ): PendingIntent {
        val intent = Intent(context, UnifiedPlaybackActionReceiver::class.java).apply {
            action = command.actionName
            putExtra("sessionId", sessionId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        )
        val requestCode = notificationIdFor(sessionId) + command.requestCodeOffset
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun loadPersistedNotificationIds(context: Context): Set<Int> {
        return context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getStringSet(activeIdsKey, emptySet())
            ?.mapNotNull(String::toIntOrNull)
            ?.toSet()
            ?: emptySet()
    }

    private fun savePersistedNotificationIds(context: Context, ids: Set<Int>) {
        context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(activeIdsKey, ids.map(Int::toString).toSet())
            .apply()
    }

    private fun resolveLargeIcon(artPath: String?): Bitmap? {
        val path = artPath?.takeIf { it.isNotBlank() } ?: return null
        artCache.get(path)?.let { return it }
        val decoded = BitmapFactory.decodeFile(path) ?: return null
        artCache.put(path, decoded)
        return decoded
    }

    private fun notificationIdFor(sessionId: String): Int {
        val hash = sessionId.hashCode()
        val positiveHash = if (hash == Int.MIN_VALUE) 0 else kotlin.math.abs(hash)
        return 20_000 + (positiveHash % 50_000)
    }
}

private val supportedImageExtensions = setOf(
    "jpg", "jpeg", "png", "webp", "bmp", "gif"
)

private val preferredCoverBasenames = listOf(
    "cover", "folder", "front", "album", "artwork", "poster"
)

private enum class NotificationCommand(
    val actionName: String,
    val requestCodeOffset: Int
) {
    toggle("toggle_session_playback", 1),
    previous("session_skip_previous", 2),
    next("session_skip_next", 3);
}

class MainActivity : AudioServiceActivity() {
    companion object {
        const val notificationSessionIdExtra = "notificationSessionId"
        const val openSessionFromNotificationAction =
            "com.example.music_player.OPEN_SESSION_FROM_NOTIFICATION"
    }

    private val fileCacheChannel = "music_player/file_cache"
    private val powerChannel = "music_player/power"
    private val notificationsChannel = "music_player/notifications"
    private val pickAudioSourceRequestCode = 7001
    private var pendingPickAudioResult: MethodChannel.Result? = null
    private var notificationsMethodChannel: MethodChannel? = null
    private var pendingNotificationSessionId: String? = null
    private val blockedExtensions = setOf(
        "vtt", "srt", "ass", "ssa", "lrc", "txt", "md", "json", "xml",
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif",
        "pdf", "zip", "rar", "7z", "tar", "gz", "doc", "docx"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, powerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepCpuAwake" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val hasActivePlayback =
                            call.argument<Boolean>("hasActivePlayback") ?: false
                        val hasActiveTimer =
                            call.argument<Boolean>("hasActiveTimer") ?: false
                        syncPlaybackKeepAlive(
                            enabled = enabled,
                            hasActivePlayback = hasActivePlayback,
                            hasActiveTimer = hasActiveTimer
                        )
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings())
                    }
                    else -> result.notImplemented()
                }
            }

        notificationsMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationsChannel)
        capturePendingNotificationSession(intent)
        notificationsMethodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "areNotificationsEnabled" -> {
                        result.success(
                            NotificationManagerCompat.from(this).areNotificationsEnabled()
                        )
                    }
                    "openNotificationSettings" -> {
                        result.success(openNotificationSettings())
                    }
                    "syncUnifiedPlaybackNotifications" -> {
                        val rawItems =
                            call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        val showSummary = call.argument<Boolean>("showSummary") ?: false
                        val summaryText = call.argument<String>("summaryText")
                        val summaryLines =
                            call.argument<List<String>>("summaryLines") ?: emptyList()
                        val items = rawItems.mapNotNull { raw ->
                            val id = raw["id"] as? String ?: return@mapNotNull null
                            val title = raw["title"] as? String ?: return@mapNotNull null
                            UnifiedPlaybackNotificationItem(
                                id = id,
                                title = title,
                                subtitle = raw["subtitle"] as? String,
                                artPath = raw["artPath"] as? String,
                                playing = raw["playing"] as? Boolean ?: false,
                                hasPrevious = raw["hasPrevious"] as? Boolean ?: false,
                                hasNext = raw["hasNext"] as? Boolean ?: false
                            )
                        }
                        UnifiedPlaybackNotificationController.sync(
                            this,
                            items,
                            showSummary,
                            summaryText,
                            summaryLines
                        )
                        result.success(null)
                    }
                    "clearUnifiedPlaybackNotifications" -> {
                        UnifiedPlaybackNotificationController.clear(this)
                        result.success(null)
                    }
                    "consumePendingNotificationSessionId" -> {
                        val sessionId = pendingNotificationSessionId
                        pendingNotificationSessionId = null
                        result.success(sessionId)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileCacheChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cacheFromUri" -> {
                        val uriString = call.argument<String>("uri")
                        val name = call.argument<String>("name") ?: "picked_audio"
                        val index = call.argument<Int>("index") ?: 0
                        if (uriString.isNullOrBlank()) {
                            result.error("invalid_args", "uri is required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val uri = Uri.parse(uriString)
                            val extension = name.substringAfterLast('.', "")
                            val safeExt = if (extension.isBlank()) "bin" else extension

                            val outDir = File(filesDir, "music_player_imports")
                            if (!outDir.exists()) {
                                outDir.mkdirs()
                            }
                            val outFile = File(outDir, "${System.currentTimeMillis()}_${index}.$safeExt")

                            contentResolver.openInputStream(uri).use { input ->
                                if (input == null) {
                                    result.error("open_failed", "cannot open input stream", null)
                                    return@setMethodCallHandler
                                }
                                FileOutputStream(outFile).use { output ->
                                    val buffer = ByteArray(64 * 1024)
                                    while (true) {
                                        val read = input.read(buffer)
                                        if (read < 0) break
                                        output.write(buffer, 0, read)
                                    }
                                    output.flush()
                                }
                            }
                            result.success(outFile.absolutePath)
                        } catch (e: Exception) {
                            result.error("cache_failed", e.message ?: "unknown error", null)
                        }
                    }
                    "scanFolder" -> {
                        val folder = call.argument<String>("folder")
                        if (folder.isNullOrBlank()) {
                            result.error("invalid_args", "folder is required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val tracks = scanFolder(folder)
                                val data = tracks.map { track ->
                                    hashMapOf(
                                        "path" to track.path,
                                        "title" to track.title,
                                        "groupKey" to track.groupKey,
                                        "groupTitle" to track.groupTitle,
                                        "groupSubtitle" to track.groupSubtitle
                                    )
                                }
                                runOnUiThread { result.success(data) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("scan_failed", e.message ?: "unknown error", null)
                                }
                            }
                        }.start()
                    }
                    "listChildFolders" -> {
                        val folder = call.argument<String>("folder")
                        if (folder.isNullOrBlank()) {
                            result.error("invalid_args", "folder is required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val folders = listChildFolders(folder)
                                runOnUiThread { result.success(folders) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "list_child_folders_failed",
                                        e.message ?: "unknown error",
                                        null
                                    )
                                }
                            }
                        }.start()
                    }
                    "resolveTrackCover" -> {
                        val trackPath = call.argument<String>("path")
                        val groupKey = call.argument<String>("groupKey")
                        if (trackPath.isNullOrBlank()) {
                            result.error("invalid_args", "path is required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val coverPath = resolveTrackCover(trackPath, groupKey)
                                runOnUiThread { result.success(coverPath) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "cover_resolve_failed",
                                        e.message ?: "unknown error",
                                        null
                                    )
                                }
                            }
                        }.start()
                    }
                    "pickAudioSource" -> {
                        launchPickAudioSource(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickAudioSourceRequestCode) {
            handlePickAudioSourceResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun launchPickAudioSource(result: MethodChannel.Result) {
        if (pendingPickAudioResult != null) {
            result.error("picker_busy", "Audio picker is already active", null)
            return
        }
        try {
            val pickFilesIntent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            val pickFolderIntent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            val chooserIntent = Intent(Intent.ACTION_CHOOSER).apply {
                putExtra(Intent.EXTRA_INTENT, pickFilesIntent)
                putExtra(Intent.EXTRA_TITLE, "Select audio")
                putExtra(Intent.EXTRA_INITIAL_INTENTS, arrayOf(pickFolderIntent))
            }

            pendingPickAudioResult = result
            startActivityForResult(chooserIntent, pickAudioSourceRequestCode)
        } catch (e: Exception) {
            pendingPickAudioResult = null
            result.error("picker_failed", e.message ?: "cannot launch picker", null)
        }
    }

    private fun handlePickAudioSourceResult(resultCode: Int, data: Intent?) {
        val callback = pendingPickAudioResult ?: return
        pendingPickAudioResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(null)
            return
        }

        val maybeTreeUri = data.data
        if (maybeTreeUri != null && DocumentsContract.isTreeUri(maybeTreeUri)) {
            persistReadPermission(maybeTreeUri, data.flags)
            callback.success(
                hashMapOf(
                    "kind" to "folder",
                    "path" to maybeTreeUri.toString()
                )
            )
            return
        }

        val files = arrayListOf<HashMap<String, String>>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                val uri = clip.getItemAt(i)?.uri ?: continue
                appendPickedFile(files, uri, data.flags)
            }
        }
        maybeTreeUri?.let { uri ->
            appendPickedFile(files, uri, data.flags)
        }

        if (files.isEmpty()) {
            callback.success(null)
            return
        }

        callback.success(
            hashMapOf(
                "kind" to "files",
                "files" to files
            )
        )
    }

    private fun appendPickedFile(
        files: MutableList<HashMap<String, String>>,
        uri: Uri,
        flags: Int
    ) {
        persistReadPermission(uri, flags)
        val name = resolveDisplayName(uri)
            ?: uri.lastPathSegment
            ?: "picked_audio"
        files.add(
            hashMapOf(
                "uri" to uri.toString(),
                "name" to name
            )
        )
    }

    private fun persistReadPermission(uri: Uri, flags: Int) {
        val canRead = flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0
        if (!canRead) return
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Some providers do not support persistable permissions.
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index < 0) return@use null
                cursor.getString(index)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun syncPlaybackKeepAlive(
        enabled: Boolean,
        hasActivePlayback: Boolean,
        hasActiveTimer: Boolean
    ) {
        try {
            if (enabled && hasActivePlayback) {
                val serviceIntent =
                    Intent(applicationContext, PlaybackKeepAliveService::class.java).apply {
                        action = PlaybackKeepAliveService.ACTION_START
                        putExtra(
                            PlaybackKeepAliveService.EXTRA_HAS_ACTIVE_PLAYBACK,
                            hasActivePlayback
                        )
                        putExtra(
                            PlaybackKeepAliveService.EXTRA_HAS_ACTIVE_TIMER,
                            hasActiveTimer
                        )
                    }
                ContextCompat.startForegroundService(applicationContext, serviceIntent)
            } else {
                applicationContext.stopService(
                    Intent(applicationContext, PlaybackKeepAliveService::class.java)
                )
            }
        } catch (_: Exception) {
            // Ignore foreground service sync failures and fall back to a wakelock.
        }
        try {
            PlaybackWakeLockController.sync(applicationContext, enabled)
        } catch (_: Exception) {
            // Ignore keep-alive sync failures and let playback continue best-effort.
        }
    }

    private fun openNotificationSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra("android.provider.extra.APP_PACKAGE", packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val fallbackIntent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null)
                ).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(fallbackIntent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val powerManager = getSystemService(POWER_SERVICE) as? PowerManager
        return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return false
        }

        return try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val fallbackIntent = Intent(
                    Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                ).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(fallbackIntent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private data class ScannedTrack(
        val path: String,
        val title: String,
        val groupKey: String,
        val groupTitle: String,
        val groupSubtitle: String
    )

    private fun scanFolder(folder: String): List<ScannedTrack> {
        val byPath = linkedMapOf<String, ScannedTrack>()
        val folderTrimmed = folder.trim()
        val uri = resolveContentUri(folderTrimmed)

        if (uri != null) {
            scanDocumentTree(uri, byPath)
            return byPath.values.toList()
        }

        val root = File(folderTrimmed)
        if (root.exists() && root.isDirectory) {
            scanFileSystem(root, byPath)
            if (byPath.isNotEmpty()) {
                return byPath.values.toList()
            }
        }

        scanMediaStore(folderTrimmed, byPath)
        return byPath.values.toList()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverNotificationSessionIntent(intent)
    }

    override fun onDestroy() {
        notificationsMethodChannel = null
        super.onDestroy()
    }

    private fun capturePendingNotificationSession(intent: Intent?) {
        pendingNotificationSessionId = extractNotificationSessionId(intent)
    }

    private fun deliverNotificationSessionIntent(intent: Intent?) {
        val sessionId = extractNotificationSessionId(intent) ?: return
        val channel = notificationsMethodChannel
        if (channel == null) {
            pendingNotificationSessionId = sessionId
            return
        }
        try {
            channel.invokeMethod(
                "openSessionFromNotification",
                mapOf("sessionId" to sessionId)
            )
        } catch (_: Exception) {
            pendingNotificationSessionId = sessionId
        }
    }

    private fun extractNotificationSessionId(intent: Intent?): String? {
        val action = intent?.action
        val sessionId = intent
            ?.getStringExtra(notificationSessionIdExtra)
            ?.takeIf { it.isNotBlank() }
            ?: return null
        if (action == null || action == openSessionFromNotificationAction) {
            return sessionId
        }
        return sessionId
    }

    private fun listChildFolders(folder: String): List<String> {
        val folderTrimmed = folder.trim()
        val uri = resolveContentUri(folderTrimmed)

        if (uri != null) {
            val treeRoot = DocumentFile.fromTreeUri(this, uri)
            val root = treeRoot ?: DocumentFile.fromSingleUri(this, uri) ?: return emptyList()
            if (!root.exists()) return emptyList()
            return try {
                root.listFiles()
                    .filter { it.isDirectory }
                    .map { it.uri.toString() }
                    .sortedBy { it.lowercase(Locale.US) }
            } catch (_: Exception) {
                emptyList()
            }
        }

        val root = File(folderTrimmed)
        if (!root.exists() || !root.isDirectory) {
            return emptyList()
        }
        return try {
            root.listFiles()
                ?.filter { it.isDirectory }
                ?.map { it.absolutePath }
                ?.sortedBy { it.lowercase(Locale.US) }
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun resolveContentUri(rawFolder: String): Uri? {
        if (rawFolder.startsWith("content://")) {
            return Uri.parse(rawFolder)
        }
        if (rawFolder.startsWith("/tree/")) {
            return Uri.parse("content://com.android.externalstorage.documents$rawFolder")
        }
        if (!rawFolder.contains("/") && rawFolder.contains(":")) {
            return DocumentsContract.buildTreeDocumentUri(
                "com.android.externalstorage.documents",
                rawFolder
            )
        }
        return null
    }

    private fun scanDocumentTree(rootUri: Uri, output: MutableMap<String, ScannedTrack>) {
        val treeRoot = DocumentFile.fromTreeUri(this, rootUri)
        val root = treeRoot ?: DocumentFile.fromSingleUri(this, rootUri) ?: return
        if (!root.exists()) return

        val rootName = normalizeDisplayName(root.name?.ifBlank { "Folder" } ?: "Folder")
        data class Node(val dir: DocumentFile, val relative: String)
        val pending = ArrayDeque<Node>()
        pending.add(Node(root, ""))

        while (pending.isNotEmpty()) {
            val current = pending.removeFirst()
            val children = try {
                current.dir.listFiles()
            } catch (_: Exception) {
                emptyArray()
            }
            for (child in children) {
                val childName = normalizeDisplayName(child.name?.trim().orEmpty())
                if (child.isDirectory) {
                    val nextRelative = when {
                        current.relative.isEmpty() -> childName
                        childName.isEmpty() -> current.relative
                        else -> "${current.relative}/$childName"
                    }
                    pending.add(Node(child, nextRelative))
                    continue
                }
                if (!child.isFile || !isSupportedDocumentFile(child)) {
                    continue
                }

                val parentRelative = current.relative
                val groupTitle = if (parentRelative.isEmpty()) rootName else parentRelative.substringAfterLast('/')
                val groupSubtitle = if (parentRelative.isEmpty()) {
                    rootName
                } else {
                    "$rootName/$parentRelative"
                }
                val groupKey = if (parentRelative.isEmpty()) {
                    root.uri.toString()
                } else {
                    "${root.uri}::$parentRelative"
                }
                val safeName = childName.ifEmpty {
                    normalizeDisplayName(child.uri.lastPathSegment ?: "audio_file")
                }
                val title = safeName.substringBeforeLast('.', safeName)
                output.putIfAbsent(
                    child.uri.toString(),
                    ScannedTrack(
                        path = child.uri.toString(),
                        title = title,
                        groupKey = groupKey,
                        groupTitle = groupTitle.ifBlank { rootName },
                        groupSubtitle = groupSubtitle
                    )
                )
            }
        }
    }

    private fun scanFileSystem(root: File, output: MutableMap<String, ScannedTrack>) {
        val pending = ArrayDeque<File>()
        pending.add(root)

        while (pending.isNotEmpty()) {
            val current = pending.removeFirst()
            val children = try {
                current.listFiles()
            } catch (_: Exception) {
                null
            } ?: continue

            for (child in children) {
                if (child.isDirectory) {
                    pending.add(child)
                    continue
                }
                if (!child.isFile || !isSupportedFileName(child.name)) {
                    continue
                }
                val parent = child.parentFile
                val parentPath = parent?.absolutePath ?: root.absolutePath
                val parentName = parent?.name?.ifBlank { parentPath } ?: parentPath
                val title = child.name.substringBeforeLast('.', child.name)
                output.putIfAbsent(
                    child.absolutePath,
                    ScannedTrack(
                        path = child.absolutePath,
                        title = title,
                        groupKey = parentPath,
                        groupTitle = parentName,
                        groupSubtitle = parentPath
                    )
                )
            }
        }
    }

    private fun scanMediaStore(folderPath: String, output: MutableMap<String, ScannedTrack>) {
        val normalized = folderPath
            .replace('\\', '/')
            .trimEnd('/')
        if (normalized.isBlank()) return

        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.RELATIVE_PATH
        )
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Audio.Media.DATA)
        }

        val basePath = if (normalized.startsWith("/storage/emulated/0/")) {
            normalized.removePrefix("/storage/emulated/0/")
        } else if (normalized.startsWith("/sdcard/")) {
            normalized.removePrefix("/sdcard/")
        } else {
            null
        }?.trim('/')

        val relPrefix = basePath?.let {
            if (it.isEmpty()) null else "$it/"
        } ?: return

        val selection = "${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
        val selectionArgs = arrayOf("$relPrefix%")
        val audioUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

        contentResolver.query(
            audioUri,
            projection.toTypedArray(),
            selection,
            selectionArgs,
            null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val displayNameIndex =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val relativeIndex =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
            val dataIndex = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIndex)
                val displayName = normalizeDisplayName(cursor.getString(displayNameIndex) ?: "audio_file")
                if (!isSupportedFileName(displayName)) {
                    continue
                }
                val relative = normalizeDisplayName(cursor.getString(relativeIndex)?.trimEnd('/') ?: "")
                val title = displayName.substringBeforeLast('.', displayName)
                val fullPath = if (dataIndex >= 0) cursor.getString(dataIndex) else null
                val contentPath = ContentUris.withAppendedId(audioUri, id).toString()

                val groupTitle = relative.substringAfterLast('/', missingDelimiterValue = relative)
                    .ifBlank { relPrefix.trimEnd('/').substringAfterLast('/') }
                val groupSubtitle = relative.ifBlank { relPrefix.trimEnd('/') }
                val groupKey = "ms:${relative.ifBlank { relPrefix }}"
                val playablePath = fullPath?.takeIf { it.isNotBlank() } ?: contentPath

                output.putIfAbsent(
                    playablePath,
                    ScannedTrack(
                        path = playablePath,
                        title = title,
                        groupKey = groupKey,
                        groupTitle = groupTitle.ifBlank { "Folder" },
                        groupSubtitle = groupSubtitle
                    )
                )
            }
        }
    }

    private fun normalizeDisplayName(raw: String): String {
        var text = raw.trim()
        if (text.isEmpty()) return text

        text = tryDecodePercent(text)

        val maybeFixed = tryLatin1ToUtf8(text)
        if (looksLikeMojibake(text) && !looksLikeMojibake(maybeFixed)) {
            text = maybeFixed
        }
        return text.trim()
    }

    private fun tryDecodePercent(value: String): String {
        if (!value.contains('%')) return value
        return try {
            URLDecoder.decode(value, StandardCharsets.UTF_8.name())
        } catch (_: Exception) {
            value
        }
    }

    private fun tryLatin1ToUtf8(value: String): String {
        return try {
            String(value.toByteArray(Charsets.ISO_8859_1), Charsets.UTF_8)
        } catch (_: Exception) {
            value
        }
    }

    private fun looksLikeMojibake(value: String): Boolean {
        if (value.isEmpty()) return false
        val pattern = Regex("[ÃÂÅÆÇÐÑØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ�]")
        return pattern.containsMatchIn(value)
    }

    private fun isSupportedDocumentFile(file: DocumentFile): Boolean {
        val mime = file.type?.lowercase(Locale.US)
        if (mime != null && (mime.startsWith("audio/") || mime == "application/ogg")) {
            return true
        }
        val name = file.name ?: return false
        return isSupportedFileName(name)
    }

    private fun isSupportedFileName(name: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase(Locale.US)
        if (extension.isBlank()) {
            return true
        }
        if (blockedExtensions.contains(extension)) {
            return false
        }
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?.lowercase(Locale.US)
        if (mime == null) {
            return true
        }
        return mime.startsWith("audio/") || mime == "application/ogg"
    }

    private fun resolveTrackCover(trackPath: String, groupKey: String?): String? {
        if (!trackPath.startsWith("content://")) {
            return null
        }

        val rootTreeUri = when {
            groupKey.isNullOrBlank() -> null
            groupKey.contains("::") -> groupKey.substringBefore("::")
            else -> groupKey
        }?.takeIf { it.startsWith("content://") } ?: return null

        val relativeDirectory = when {
            groupKey.isNullOrBlank() -> ""
            groupKey.contains("::") -> groupKey.substringAfter("::", "")
            else -> ""
        }

        val treeRoot = DocumentFile.fromTreeUri(this, Uri.parse(rootTreeUri))
            ?: DocumentFile.fromSingleUri(this, Uri.parse(rootTreeUri))
            ?: return null
        if (!treeRoot.exists()) return null

        val candidateDirectories = resolveCandidateDocumentDirectories(
            treeRoot,
            relativeDirectory
        )

        candidateDirectories.forEach { directory ->
            val cover = findPreferredCoverInDocumentDirectory(directory) ?: return@forEach
            return cacheDocumentCover(cover, trackPath)
        }
        return null
    }

    private fun resolveCandidateDocumentDirectories(
        root: DocumentFile,
        relativeDirectory: String
    ): List<DocumentFile> {
        val visited = mutableListOf<DocumentFile>()
        var current: DocumentFile = root
        visited.add(current)
        if (relativeDirectory.isBlank()) {
            return visited.asReversed()
        }
        for (segment in relativeDirectory.split('/')) {
            if (segment.isBlank()) continue
            val next = current.listFiles().firstOrNull {
                it.isDirectory && normalizeDisplayName(it.name?.trim().orEmpty()) == segment
            } ?: break
            current = next
            visited.add(current)
        }
        return visited.asReversed()
    }

    private fun resolveRelativeDocumentDirectory(
        root: DocumentFile,
        relativeDirectory: String
    ): DocumentFile? {
        if (relativeDirectory.isBlank()) return root
        var current: DocumentFile? = root
        for (segment in relativeDirectory.split('/')) {
            if (segment.isBlank()) continue
            current = current?.listFiles()?.firstOrNull {
                it.isDirectory && normalizeDisplayName(it.name?.trim().orEmpty()) == segment
            } ?: return null
        }
        return current
    }

    private fun findPreferredCoverInDocumentDirectory(directory: DocumentFile): DocumentFile? {
        val images = collectImageDocuments(directory)
        if (images.isEmpty()) return null
        return images.sortedWith { left, right ->
            compareCoverNames(
                normalizeDisplayName(left.name ?: left.uri.lastPathSegment ?: ""),
                normalizeDisplayName(right.name ?: right.uri.lastPathSegment ?: "")
            )
        }.firstOrNull()
    }

    private fun collectImageDocuments(directory: DocumentFile): List<DocumentFile> {
        return try {
            val images = mutableListOf<DocumentFile>()
            val pending = java.util.ArrayDeque<DocumentFile>()
            pending.add(directory)
            while (pending.isNotEmpty()) {
                val current = pending.removeFirst()
                for (child in current.listFiles()) {
                    when {
                        child.isDirectory -> pending.addLast(child)
                        child.isFile && isSupportedImageDocument(child) -> images.add(child)
                    }
                }
            }
            images
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun isSupportedImageDocument(file: DocumentFile): Boolean {
        val mime = file.type?.lowercase(Locale.US)
        if (mime != null && mime.startsWith("image/")) {
            return true
        }
        val extension = file.name
            ?.substringAfterLast('.', "")
            ?.lowercase(Locale.US)
            .orEmpty()
        return extension in supportedImageExtensions
    }

    private fun compareCoverNames(leftNameRaw: String, rightNameRaw: String): Int {
        val leftName = leftNameRaw.substringBeforeLast('.', leftNameRaw).lowercase(Locale.US)
        val rightName = rightNameRaw.substringBeforeLast('.', rightNameRaw).lowercase(Locale.US)
        val scoreCompare = coverPriority(leftName).compareTo(coverPriority(rightName))
        if (scoreCompare != 0) return scoreCompare
        val nameCompare = leftName.compareTo(rightName)
        if (nameCompare != 0) return nameCompare
        return leftNameRaw.lowercase(Locale.US).compareTo(rightNameRaw.lowercase(Locale.US))
    }

    private fun coverPriority(baseName: String): Int {
        val exactMatchIndex = preferredCoverBasenames.indexOf(baseName)
        if (exactMatchIndex >= 0) {
            return exactMatchIndex
        }
        for (i in preferredCoverBasenames.indices) {
            if (baseName.contains(preferredCoverBasenames[i])) {
                return 100 + i
            }
        }
        return 200
    }

    private fun cacheDocumentCover(file: DocumentFile, trackPath: String): String? {
        val extension = file.name
            ?.substringAfterLast('.', "")
            ?.ifBlank { "img" }
            ?: "img"
        val coverDir = File(cacheDir, "music_player_covers")
        if (!coverDir.exists()) {
            coverDir.mkdirs()
        }
        val outputFile = File(
            coverDir,
            "cover_${kotlin.math.abs(trackPath.hashCode())}.$extension"
        )
        if (outputFile.exists() && outputFile.length() > 0) {
            return outputFile.absolutePath
        }

        return try {
            contentResolver.openInputStream(file.uri)?.use { input ->
                FileOutputStream(outputFile).use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            } ?: return null
            outputFile.absolutePath
        } catch (_: Exception) {
            if (outputFile.exists()) {
                outputFile.delete()
            }
            null
        }
    }
}
