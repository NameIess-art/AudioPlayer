package com.example.music_player

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import java.util.Locale

class MainActivity : AudioServiceActivity() {
    private val fileCacheChannel = "music_player/file_cache"
    private val powerChannel = "music_player/power"
    private val pickAudioSourceRequestCode = 7001
    private var pendingPickAudioResult: MethodChannel.Result? = null
    private var partialWakeLock: PowerManager.WakeLock? = null
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
                        setKeepCpuAwake(enabled)
                        result.success(null)
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

                            val outDir = File(cacheDir, "music_player_imports")
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

    override fun onDestroy() {
        releaseKeepCpuAwake()
        super.onDestroy()
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

    private fun setKeepCpuAwake(enabled: Boolean) {
        if (!enabled) {
            releaseKeepCpuAwake()
            return
        }
        if (partialWakeLock?.isHeld == true) return

        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            partialWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:audio_timer_lock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: SecurityException) {
            partialWakeLock = null
        } catch (_: RuntimeException) {
            partialWakeLock = null
        }
    }

    private fun releaseKeepCpuAwake() {
        val lock = partialWakeLock ?: return
        try {
            if (lock.isHeld) lock.release()
        } catch (_: RuntimeException) {
            // Ignore stale wakelock state.
        } finally {
            partialWakeLock = null
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
}
