import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import 'video_converter_tab.dart';
import '../widgets/top_page_header.dart';

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  static const MethodChannel _fileCacheChannel = MethodChannel(
    'music_player/file_cache',
  );

  Future<void> _openVideoConverterPage() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VideoConverterTab()));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshWatchedFolders(silent: true);
    });
  }

  Future<void> _refreshWatchedFolders({bool silent = false}) async {
    final i18n = context.read<AppLanguageProvider>();
    final provider = context.read<AudioProvider>();
    final watchedFolders = provider.watchedFolders;
    if (watchedFolders.isEmpty) return;

    final permissionGranted = await _ensureReadPermission();
    if (!permissionGranted) {
      if (!silent) _showSnack(i18n.tr('need_storage_permission_scan_folder'));
      return;
    }

    if (!mounted) return;
    provider.setScanning(true);
    var totalAdded = 0;
    try {
      for (final folderPath in watchedFolders) {
        final nativeTracks = await _scanFolderViaNative(folderPath);
        if (nativeTracks != null) {
          final toAdd = nativeTracks
              .map(
                (t) => MusicTrack(
                  path: t.path,
                  displayName:
                      t.displayName ?? path.basenameWithoutExtension(t.path),
                  groupKey: t.groupKey,
                  groupTitle: t.groupTitle,
                  groupSubtitle: t.groupSubtitle,
                  isSingle: t.isSingle,
                ),
              )
              .toList();
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
          _showSnack(
            totalAdded > 0
                ? i18n.tr('refresh_done_added', {'count': totalAdded})
                : i18n.tr('refresh_done_no_new'),
          );
        }
      }
    }
  }

  Future<void> _addFolder() async {
    final i18n = context.read<AppLanguageProvider>();
    final permissionGranted = await _ensureReadPermission();
    if (!permissionGranted) {
      _showSnack(i18n.tr('need_storage_permission_import_audio'));
      return;
    }

    final folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: i18n.tr('choose_music_folder'),
    );
    if (folderPath == null || folderPath.isEmpty) return;
    await _addFolderFromPath(folderPath);
  }

  Future<void> _addFolderFromPath(String folderPath) async {
    final i18n = context.read<AppLanguageProvider>();
    if (!mounted) return;
    context.read<AudioProvider>().setScanning(true);

    final provider = context.read<AudioProvider>();
    var added = 0;

    try {
      final nativeTracks = await _scanFolderViaNative(folderPath);
      if (nativeTracks != null) {
        final toAdd = nativeTracks
            .map(
              (t) => MusicTrack(
                path: t.path,
                displayName:
                    t.displayName ?? path.basenameWithoutExtension(t.path),
                groupKey: t.groupKey,
                groupTitle: t.groupTitle,
                groupSubtitle: t.groupSubtitle,
                isSingle: t.isSingle,
              ),
            )
            .toList();

        final beforeCount = provider.library.length;
        provider.addTracks(toAdd);
        added = provider.library.length - beforeCount;
      } else {
        added = await _importFolderIncrementally(folderPath, provider);
      }
    } finally {
      if (mounted) {
        provider.setScanning(false);
        provider.addWatchedFolder(folderPath);
        _showSnack(i18n.tr('import_done_added', {'count': added}));
      }
    }
  }

  Future<void> _addFiles() async {
    final i18n = context.read<AppLanguageProvider>();
    final permissionGranted = await _ensureReadPermission();
    if (!permissionGranted) {
      _showSnack(i18n.tr('need_storage_permission_import_audio'));
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: true,
      type: FileType.any,
      dialogTitle: i18n.tr('choose_audio_files'),
    );
    if (result == null) return;

    if (!mounted) return;
    context.read<AudioProvider>().setScanning(true);

    try {
      final resolvedPaths = <String>[];
      for (var i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        final rawPath = file.path;
        final needsCopy =
            rawPath == null ||
            rawPath.isEmpty ||
            rawPath.startsWith('content://');

        if (!needsCopy) {
          resolvedPaths.add(path.normalize(rawPath));
          continue;
        }

        final cachedPath = await _cachePickedFile(file, i);
        if (cachedPath != null) {
          resolvedPaths.add(path.normalize(cachedPath));
        }
      }

      final candidates = resolvedPaths
          .where(_isSupportedAudioFile)
          .map(
            (p) => MusicTrack(
              path: p,
              displayName: path.basenameWithoutExtension(p),
              groupKey: '__single_files__',
              groupTitle: i18n.tr('imported_files'),
              groupSubtitle: i18n.tr('manually_selected_files'),
              isSingle: true,
            ),
          )
          .toList();

      if (mounted) {
        final provider = context.read<AudioProvider>();
        final beforeCount = provider.library.length;
        provider.addTracks(candidates);
        final added = provider.library.length - beforeCount;
        _showSnack(i18n.tr('import_done_added', {'count': added}));
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
        final cacheDir = Directory(
          path.join(Directory.systemTemp.path, 'music_player_imports'),
        );
        if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

        final extension = path.extension(file.name);
        final outPath = path.join(
          cacheDir.path,
          '${DateTime.now().microsecondsSinceEpoch}_$index${extension.isEmpty ? '.bin' : extension}',
        );

        final sink = File(outPath).openWrite();
        await stream.pipe(sink);
        await sink.close();
        return outPath;
      } catch (_) {}
    }

    if (Platform.isAndroid &&
        identifier != null &&
        identifier.startsWith('content://')) {
      try {
        return await _fileCacheChannel.invokeMethod<String>('cacheFromUri', {
          'uri': identifier,
          'name': file.name,
          'index': index,
        });
      } catch (_) {}
    }
    return null;
  }

  Future<List<_ScannedTrack>?> _scanFolderViaNative(String folderPath) async {
    if (!Platform.isAndroid) return null;
    try {
      final data = await _fileCacheChannel.invokeMethod<List<dynamic>>(
        'scanFolder',
        {'folder': folderPath},
      );
      if (data == null) return null;

      final scanned = <_ScannedTrack>[];
      for (final item in data) {
        if (item is! Map) continue;
        final map = item.cast<Object?, Object?>();
        final scannedPath = map['path']?.toString().trim();
        if (scannedPath == null ||
            scannedPath.isEmpty ||
            !_isSupportedAudioFile(scannedPath)) {
          continue;
        }

        final nativeGroupKey = map['groupKey']?.toString().trim();
        final nativeGroupTitle = map['groupTitle']?.toString().trim();
        final nativeGroupSubtitle = map['groupSubtitle']?.toString().trim();

        final groupKey = (nativeGroupKey?.isNotEmpty ?? false)
            ? nativeGroupKey!
            : path.dirname(scannedPath);
        final groupTitle = (nativeGroupTitle?.isNotEmpty ?? false)
            ? nativeGroupTitle!
            : path.basename(groupKey);
        final groupSubtitle = (nativeGroupSubtitle?.isNotEmpty ?? false)
            ? nativeGroupSubtitle!
            : groupKey;
        final displayName = map['title']?.toString().trim();
        final resolvedPath = scannedPath.startsWith('content://')
            ? scannedPath
            : path.normalize(scannedPath);

        scanned.add(
          _ScannedTrack(
            path: resolvedPath,
            groupKey: groupKey,
            groupTitle: groupTitle,
            groupSubtitle: groupSubtitle,
            isSingle: false,
            displayName: displayName?.isEmpty ?? true ? null : displayName,
          ),
        );
      }
      return scanned;
    } catch (_) {
      return null;
    }
  }

  Future<int> _importFolderIncrementally(
    String folderPath,
    AudioProvider provider,
  ) async {
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

        batch.add(
          MusicTrack(
            path: absolutePath,
            displayName: path.basenameWithoutExtension(absolutePath),
            groupKey: parentFolder,
            groupTitle: folderName.isEmpty ? parentFolder : folderName,
            groupSubtitle: parentFolder,
            isSingle: false,
          ),
        );
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
    if (filePath.toLowerCase().endsWith('.flac') ||
        filePath.toLowerCase().endsWith('.wav')) {
      return true;
    }
    final mimeType = lookupMimeType(filePath);
    if (mimeType == null) return true;
    return mimeType.startsWith('audio/') || mimeType == 'application/ogg';
  }

  Future<bool> _ensureReadPermission() async {
    if (!Platform.isAndroid) return true;
    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;
    final statuses = await [Permission.audio, Permission.storage].request();
    return statuses.values.any(
      (status) => status.isGranted || status.isLimited,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.watch<AudioProvider>();
    final tree = provider.buildLibraryTree();
    final cs = Theme.of(context).colorScheme;
    final leafFolderCount = tree.whereType<FolderNode>().fold<int>(
      0,
      (count, folder) => count + folder.leafFolderCount,
    );

    return SafeArea(
      child: Column(
        children: [
          TopPageHeader(
            icon: Icons.library_music_rounded,
            title: i18n.tr('music_library'),
            trailing: SizedBox(
              width: 112,
              height: 44,
              child: provider.isScanning
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Semantics(
                          button: true,
                          label: i18n.tr('refresh_watched_folder'),
                          child: IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: i18n.tr('refresh_watched_folder'),
                            onPressed: provider.watchedFolders.isEmpty
                                ? null
                                : () => _refreshWatchedFolders(),
                          ),
                        ),
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          tooltip: i18n.tr('more_actions'),
                          onSelected: (value) {
                            if (value == 0) _addFolder();
                            if (value == 1) _addFiles();
                            if (value == 2) _openVideoConverterPage();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 0,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.create_new_folder_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(i18n.tr('import_folder')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 1,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.upload_file_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(i18n.tr('import_file')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 2,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.video_library_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(i18n.tr('video_to_audio')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            bottomSpacing: 10,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MetricChip(
                  icon: Icons.music_note_rounded,
                  text: i18n.tr('audio_count', {
                    'count': provider.library.length,
                  }),
                ),
                _MetricChip(
                  icon: Icons.folder_rounded,
                  text: i18n.tr('folder_count', {'count': leafFolderCount}),
                ),
              ],
            ),
          ),
          Expanded(
            child: tree.isEmpty
                ? _LibraryEmptyState(
                    onImportFolder: _addFolder,
                    onImportFile: _addFiles,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
                    itemCount: tree.length,
                    itemBuilder: (context, index) {
                      final node = tree[index];
                      return _LibraryTreeItem(
                        key: ValueKey(node.path),
                        node: node,
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({
    required this.onImportFolder,
    required this.onImportFile,
  });

  final VoidCallback onImportFolder;
  final VoidCallback onImportFile;

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.audio_file_rounded,
                    size: 30,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  i18n.tr('no_audio_files'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  i18n.tr('import_audio_hint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onImportFolder,
                      icon: const Icon(Icons.create_new_folder_rounded),
                      label: Text(i18n.tr('import_folder')),
                    ),
                    OutlinedButton.icon(
                      onPressed: onImportFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(i18n.tr('import_file')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

  Future<void> _confirmRemoveFolder(
    BuildContext context,
    AudioProvider provider,
  ) async {
    final i18n = context.read<AppLanguageProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.tr('remove_folder')),
        content: Text(i18n.tr('remove_folder_confirm', {'name': folder.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(i18n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(i18n.tr('remove')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      provider.removeFolderFromLibrary(folder.path);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('removed_prefix', {'name': folder.name})),
          ),
        );
    }
  }

  void _playFolder(BuildContext context, AudioProvider provider) {
    final i18n = context.read<AppLanguageProvider>();
    final tracks = folder.allTracks;
    if (tracks.isEmpty) return;
    provider.spawnSession(tracks.first);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            i18n.tr('session_created', {'name': tracks.first.displayName}),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.watch<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outlineVariant),
        borderRadius: radius,
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: radius),
        collapsedShape: RoundedRectangleBorder(borderRadius: radius),
        tilePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        childrenPadding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.folder_rounded,
            color: cs.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: _AdaptiveNameText(folder.name),
        subtitle: Text(
          i18n.tr('items_count', {'count': folder.children.length}),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        trailing: SizedBox(
          width: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                tooltip: i18n.tr('play_first'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _playFolder(context, provider),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: cs.error,
                ),
                tooltip: i18n.tr('remove_audio_folder'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmRemoveFolder(context, provider),
              ),
            ],
          ),
        ),
        children: folder.children
            .map(
              (childNode) => _LibraryTreeItem(
                key: ValueKey(childNode.path),
                node: childNode,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TrackNodeWidget extends StatelessWidget {
  const _TrackNodeWidget({required this.trackNode});

  final TrackNode trackNode;

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.watch<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final track = trackNode.track;
    final isAlreadyPlaying = provider.activeSessions.any(
      (s) => s.currentTrackPath == track.path,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        minVerticalPadding: 10,
        leading: Icon(
          isAlreadyPlaying ? Icons.volume_up_rounded : Icons.music_note_rounded,
          color: isAlreadyPlaying ? cs.primary : cs.onSurfaceVariant,
        ),
        title: _AdaptiveNameText(track.displayName, maxLines: 3),
        trailing: SizedBox(
          width: 82,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  isAlreadyPlaying
                      ? Icons.add_circle_outline_rounded
                      : Icons.play_arrow_rounded,
                ),
                tooltip: isAlreadyPlaying
                    ? i18n.tr('create_another_session')
                    : i18n.tr('play'),
                onPressed: () {
                  provider.spawnSession(track);
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          i18n.tr('session_created', {
                            'name': track.displayName,
                          }),
                        ),
                      ),
                    );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: i18n.tr('remove_audio'),
                onPressed: () {
                  provider.removeTrackFromLibrary(track.path);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _AdaptiveNameText extends StatelessWidget {
  const _AdaptiveNameText(this.text, {this.maxLines = 3});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.16);

    return AutoSizeText(
      text,
      maxLines: maxLines,
      minFontSize: 11,
      stepGranularity: 0.5,
      softWrap: true,
      overflow: TextOverflow.ellipsis,
      style: style,
      overflowReplacement: Text(
        text,
        maxLines: maxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: style?.copyWith(fontSize: 11),
      ),
    );
  }
}
