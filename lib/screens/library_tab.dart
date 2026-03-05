import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import 'package:auto_size_text/auto_size_text.dart';

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  static const MethodChannel _fileCacheChannel = MethodChannel('music_player/file_cache');

  @override
  void initState() {
    super.initState();
    // Auto-rescan watched folders once the first frame has rendered so the
    // provider is fully available via context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshWatchedFolders(silent: true);
    });
  }

  /// Re-scan all watched folders and add any new audio files silently.
  /// When [silent] is true no snackbar is shown if there are no new files.
  Future<void> _refreshWatchedFolders({bool silent = false}) async {
    final provider = context.read<AudioProvider>();
    final watchedFolders = provider.watchedFolders;
    if (watchedFolders.isEmpty) return;

    final permissionGranted = await _ensureReadPermission();
    if (!permissionGranted) {
      if (!silent) _showSnack('需要读取权限才能扫描文件夹。');
      return;
    }

    if (!mounted) return;
    provider.setScanning(true);
    int totalAdded = 0;
    try {
      for (final folderPath in watchedFolders) {
        final nativeTracks = await _scanFolderViaNative(folderPath);
        if (nativeTracks != null) {
          final toAdd = nativeTracks.map((t) => MusicTrack(
            path: t.path,
            displayName: t.displayName ?? path.basenameWithoutExtension(t.path),
            groupKey: t.groupKey,
            groupTitle: t.groupTitle,
            groupSubtitle: t.groupSubtitle,
            isSingle: t.isSingle,
          )).toList();
          final before = provider.library.length;
          provider.addTracks(toAdd);
          totalAdded += provider.library.length - before;
        } else {
          totalAdded += await _importFolderIncrementally(folderPath, provider);
        }
      }
    } finally {
      if (mounted) {
        provider.setScanning(false);
        if (!silent || totalAdded > 0) {
          _showSnack(totalAdded > 0 ? '刷新完毕：新增了 $totalAdded 首歌曲。' : '已是最新，没有新文件。');
        }
      }
    }
  }

  Future<void> _addFolder() async {
    final permissionGranted = await _ensureReadPermission();
    if (!permissionGranted) {
      _showSnack('需要读取权限才能导入音频文件。');
      return;
    }

    final folderPath = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择音乐文件夹');
    if (folderPath == null || folderPath.isEmpty) return;

    if (!mounted) return;
    context.read<AudioProvider>().setScanning(true);

    final provider = context.read<AudioProvider>();
    int added = 0;

    try {
      final nativeTracks = await _scanFolderViaNative(folderPath);
      if (nativeTracks != null) {
        final toAdd = nativeTracks.map((t) => MusicTrack(
          path: t.path,
          displayName: t.displayName ?? path.basenameWithoutExtension(t.path),
          groupKey: t.groupKey,
          groupTitle: t.groupTitle,
          groupSubtitle: t.groupSubtitle,
          isSingle: t.isSingle,
        )).toList();

        final beforeCount = provider.library.length;
        provider.addTracks(toAdd);
        added = provider.library.length - beforeCount;
      } else {
        added = await _importFolderIncrementally(folderPath, provider);
      }
    } finally {
      if (mounted) {
        provider.setScanning(false);
        _showSnack('扫完了：新增了 $added 首歌曲。');
        // Register this folder as watched so it is auto-rescanned on next startup.
        provider.addWatchedFolder(folderPath);
      }
    }
  }

  Future<void> _addFiles() async {
    final permissionGranted = await _ensureReadPermission();
    if (!permissionGranted) {
      _showSnack('需要读取权限才能导入音频文件。');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: true,
      type: FileType.any,
      dialogTitle: '选择音乐文件',
    );
    if (result == null) return;

    if (!mounted) return;
    context.read<AudioProvider>().setScanning(true);

    try {
      final resolvedPaths = <String>[];
      for (var i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        final rawPath = file.path;
        final needsCopy = rawPath == null || rawPath.isEmpty || rawPath.startsWith('content://');

        if (!needsCopy) {
          resolvedPaths.add(path.normalize(rawPath));
          continue;
        }

        final cachedPath = await _cachePickedFile(file, i);
        if (cachedPath != null) {
          resolvedPaths.add(path.normalize(cachedPath));
        }
      }

      final candidates = resolvedPaths.where(_isSupportedAudioFile).map((p) => MusicTrack(
        path: p,
        displayName: path.basenameWithoutExtension(p),
        groupKey: '__single_files__',
        groupTitle: '单独添加的文件',
        groupSubtitle: '手动选择的文件',
        isSingle: true,
      )).toList();

      if (mounted) {
        final provider = context.read<AudioProvider>();
        final beforeCount = provider.library.length;
        provider.addTracks(candidates);
        final added = provider.library.length - beforeCount;
        _showSnack('导入完成：新增了 $added 首歌曲。');
      }
    } finally {
      if (mounted) {
        context.read<AudioProvider>().setScanning(false);
      }
    }
  }

  Future<String?> _cachePickedFile(PlatformFile file, int index) async {
    final stream = file.readStream;
    final identifier = file.identifier;

    if (stream != null) {
      try {
        final cacheDir = Directory(path.join(Directory.systemTemp.path, 'music_player_imports'));
        if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

        final extension = path.extension(file.name);
        final outPath = path.join(cacheDir.path, '${DateTime.now().microsecondsSinceEpoch}_$index${extension.isEmpty ? '.bin' : extension}');

        final sink = File(outPath).openWrite();
        await stream.pipe(sink);
        await sink.close();
        return outPath;
      } catch (_) {}
    }

    if (Platform.isAndroid && identifier != null && identifier.startsWith('content://')) {
      try {
        return await _fileCacheChannel.invokeMethod<String>('cacheFromUri', {'uri': identifier, 'name': file.name, 'index': index});
      } catch (_) {}
    }
    return null;
  }

  Future<List<_ScannedTrack>?> _scanFolderViaNative(String folderPath) async {
    if (!Platform.isAndroid) return null;
    try {
      final data = await _fileCacheChannel.invokeMethod<List<dynamic>>('scanFolder', {'folder': folderPath});
      if (data == null) return null;

      final scanned = <_ScannedTrack>[];
      for (final item in data) {
        if (item is! Map) continue;
        final map = item.cast<Object?, Object?>();
        final scannedPath = map['path']?.toString().trim();
        if (scannedPath == null || scannedPath.isEmpty || !_isSupportedAudioFile(scannedPath)) continue;

        final nativeGroupKey = map['groupKey']?.toString().trim();
        final nativeGroupTitle = map['groupTitle']?.toString().trim();
        final nativeGroupSubtitle = map['groupSubtitle']?.toString().trim();

        final groupKey = (nativeGroupKey?.isNotEmpty ?? false) ? nativeGroupKey! : path.dirname(scannedPath);
        final groupTitle = (nativeGroupTitle?.isNotEmpty ?? false) ? nativeGroupTitle! : path.basename(groupKey);
        final groupSubtitle = (nativeGroupSubtitle?.isNotEmpty ?? false) ? nativeGroupSubtitle! : groupKey;
        final displayName = map['title']?.toString().trim();
        final resolvedPath = scannedPath.startsWith('content://') ? scannedPath : path.normalize(scannedPath);

        scanned.add(_ScannedTrack(
          path: resolvedPath,
          groupKey: groupKey,
          groupTitle: groupTitle,
          groupSubtitle: groupSubtitle,
          isSingle: false,
          displayName: displayName?.isEmpty ?? true ? null : displayName,
        ));
      }
      return scanned;
    } catch (_) {
      return null;
    }
  }

  Future<int> _importFolderIncrementally(String folderPath, AudioProvider provider) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return 0;

    final existingPaths = provider.library.map((t) => t.path).toSet();
    final pendingDirs = Queue<Directory>()..add(folder);
    final batch = <MusicTrack>[];
    const batchSize = 350;
    var added = 0;

    while (pendingDirs.isNotEmpty && mounted) {
      final currentDir = pendingDirs.removeFirst();
      late final Stream<FileSystemEntity> stream;
      try {
        stream = currentDir.list(followLinks: false);
      } catch (_) {
        continue;
      }

      await for (final entity in stream.handleError((_) {})) {
        if (entity is Directory) {
          pendingDirs.add(entity);
          continue;
        }
        if (entity is! File) continue;

        final absolutePath = path.normalize(entity.path);
        if (!_isSupportedAudioFile(absolutePath)) continue;
        if (existingPaths.contains(absolutePath)) continue;
        existingPaths.add(absolutePath);

        final parentFolder = path.dirname(absolutePath);
        final folderName = path.basename(parentFolder);

        batch.add(MusicTrack(
          path: absolutePath,
          displayName: path.basenameWithoutExtension(absolutePath),
          groupKey: parentFolder,
          groupTitle: folderName.isEmpty ? parentFolder : folderName,
          groupSubtitle: parentFolder,
          isSingle: false,
        ));
        added++;

        if (batch.length >= batchSize) {
          provider.addTracks(batch);
          batch.clear();
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    provider.addTracks(batch);
    return added;
  }

  bool _isSupportedAudioFile(String filePath) {
    if (filePath.toLowerCase().endsWith('.flac') || filePath.toLowerCase().endsWith('.wav')) return true;
    final mimeType = lookupMimeType(filePath);
    if (mimeType == null) return true;
    return mimeType.startsWith('audio/') || mimeType == 'application/ogg';
  }

  Future<bool> _ensureReadPermission() async {
    if (!Platform.isAndroid) return true;
    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;
    final statuses = await [Permission.audio, Permission.storage].request();
    return statuses.values.any((status) => status.isGranted || status.isLimited);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }



  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.library_music_rounded, size: 28),
                const SizedBox(width: 8),
                Text(
                  '我的音频库',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (provider.library.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '共 ${provider.library.length} 首',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                const Spacer(),
                if (provider.isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: '刷新监听文件夹',
                        onPressed: provider.watchedFolders.isEmpty
                            ? null
                            : () => _refreshWatchedFolders(),
                      ),
                      PopupMenuButton<int>(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        tooltip: '导入音频',
                        onSelected: (value) {
                          if (value == 0) _addFolder();
                          if (value == 1) _addFiles();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 0,
                            child: Row(
                              children: [
                                Icon(Icons.create_new_folder_rounded, size: 20),
                                SizedBox(width: 12),
                                Text('导入文件夹'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 1,
                            child: Row(
                              children: [
                                Icon(Icons.upload_file_rounded, size: 20),
                                SizedBox(width: 12),
                                Text('导入文件'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: provider.library.isEmpty
                ? const Center(
                    child: Text('没有音乐文件，点击上方按钮导入', textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: provider.buildLibraryTree().length,
                    itemBuilder: (context, index) {
                      final node = provider.buildLibraryTree()[index];
                      return _LibraryTreeItem(key: ValueKey(node.path), node: node);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tree Node Item Widget (Recursive)
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryTreeItem extends StatelessWidget {
  const _LibraryTreeItem({super.key, required this.node});

  final LibraryNode node;

  @override
  Widget build(BuildContext context) {
    if (node is FolderNode) {
      return _FolderNodeWidget(folder: node as FolderNode);
    } else if (node is TrackNode) {
      return _TrackNodeWidget(trackNode: node as TrackNode);
    }
    return const SizedBox.shrink();
  }
}

class _FolderNodeWidget extends StatelessWidget {
  const _FolderNodeWidget({required this.folder});

  final FolderNode folder;

  Future<void> _confirmRemoveFolder(BuildContext context, AudioProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除文件夹'),
        content: Text('要从库中移除文件夹\n${folder.name}\n及其所有音频吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      provider.removeFolderFromLibrary(folder.path);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('已移除 ${folder.name}')));
    }
  }

  void _playFolder(BuildContext context, AudioProvider provider) {
    final tracks = folder.allTracks;
    if (tracks.isEmpty) return;
    provider.spawnSession(tracks.first);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('创建并播放任务：${tracks.first.displayName}')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();
    final radius = BorderRadius.circular(16);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: radius,
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: radius),
        collapsedShape: RoundedRectangleBorder(borderRadius: radius),
        childrenPadding: const EdgeInsets.only(left: 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: AutoSizeText(
          folder.name,
          maxLines: 4,
          minFontSize: 9,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          overflow: TextOverflow.visible,
        ),
        subtitle: Text(
          '${folder.children.length} 个项目',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              tooltip: '播放文件夹内所有',
              visualDensity: VisualDensity.compact,
              onPressed: () => _playFolder(context, provider),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(context).colorScheme.error),
              tooltip: '移除文件夹',
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmRemoveFolder(context, provider),
            ),
          ],
        ),
        children: folder.children.map((childNode) => _LibraryTreeItem(key: ValueKey(childNode.path), node: childNode)).toList(),
      ),
    );
  }
}

class _TrackNodeWidget extends StatelessWidget {
  const _TrackNodeWidget({required this.trackNode});

  final TrackNode trackNode;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();
    final track = trackNode.track;
    final isAlreadyPlaying = provider.activeSessions.any((s) => s.currentTrackPath == track.path);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      leading: Icon(
        isAlreadyPlaying ? Icons.volume_up_rounded : Icons.music_note_rounded,
        color: isAlreadyPlaying ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        track.displayName,
        maxLines: 3,
        softWrap: true,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isAlreadyPlaying ? Icons.add_circle_outline_rounded : Icons.play_arrow_rounded),
            tooltip: isAlreadyPlaying ? '再开一个任务' : '播放',
            onPressed: () {
              provider.spawnSession(track);
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text('创建并播放任务：${track.displayName}')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: '移除音频',
            onPressed: () {
              provider.removeTrackFromLibrary(track.path);
            },
          ),
        ],
      ),
    );
  }
}

// Extracted ScannedTrack class goes here
class _ScannedTrack {
  const _ScannedTrack({
    required this.path,
    required this.groupKey,
    required this.groupTitle,
    required this.groupSubtitle,
    required this.isSingle,
    this.displayName,
  });

  final String path;
  final String groupKey;
  final String groupTitle;
  final String groupSubtitle;
  final bool isSingle;
  final String? displayName;
}
