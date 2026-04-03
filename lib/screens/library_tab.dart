import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/app_feedback.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/mobile_overlay_inset.dart';
import '../widgets/top_page_header.dart';
import 'video_converter_tab.dart';

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
          provider.addTracks(toAdd, notify: false);
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
    final provider = context.read<AudioProvider>();
    if (!mounted) return;
    provider.setScanning(true);

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
        provider.addTracks(toAdd, notify: false);
        added = provider.library.length - beforeCount;
      } else {
        added = await _importFolderIncrementally(folderPath, provider);
      }
    } finally {
      if (mounted) {
        provider.addWatchedFolder(folderPath, notify: false);
        provider.setScanning(false);
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
        provider.addTracks(candidates, notify: false);
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
          provider.addTracks(batch, notify: false);
          batch.clear();
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    provider.addTracks(batch, notify: false);
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
    final leafFolderCount = context.select<AudioProvider, int>(
      (value) => value.libraryLeafFolderCount,
    );
    final bottomInset = max(132.0, MobileOverlayInset.of(context));
    final _ =
        '${i18n.tr('audio_count', {'count': provider.library.length})} 路 '
        '${i18n.tr('folder_count', {'count': leafFolderCount})}';

    return SafeArea(
      child: Column(
        children: [
          TopPageHeader(
            icon: Icons.library_music_rounded,
            title: i18n.tr('music_library'),
            subtitle: i18n.tr(
              'audio_count',
              {'count': provider.library.length},
            ),
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
          Expanded(
            child: tree.isEmpty
                ? _LibraryEmptyState(
                    onImportFolder: _addFolder,
                    onImportFile: _addFiles,
                    bottomInset: bottomInset,
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset),
                    cacheExtent: 720,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
        ],
      ),
    );
  }
}

void _showSessionCreatedSnack(BuildContext context, String message) {
  showAppSnackBar(
    context,
    message,
    tone: AppFeedbackTone.success,
    icon: Icons.queue_music_rounded,
  );
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({
    required this.onImportFolder,
    required this.onImportFile,
    required this.bottomInset,
  });

  final VoidCallback onImportFolder;
  final VoidCallback onImportFile;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, bottomInset),
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

class _FolderNodeWidget extends StatefulWidget {
  const _FolderNodeWidget({required this.folder});

  final FolderNode folder;

  @override
  State<_FolderNodeWidget> createState() => _FolderNodeWidgetState();
}

class _FolderNodeWidgetState extends State<_FolderNodeWidget> {
  final ExpansibleController _expansionController = ExpansibleController();
  bool _expanded = false;

  Future<void> _confirmRemoveFolder(
    BuildContext context,
    AudioProvider provider,
  ) async {
    final i18n = context.read<AppLanguageProvider>();
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: i18n.tr('remove_folder'),
      message: i18n.tr(
        'remove_folder_confirm',
        {'name': widget.folder.name},
      ),
      cancelLabel: i18n.tr('cancel'),
      confirmLabel: i18n.tr('remove'),
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed == true && context.mounted) {
      await provider.removeFolderFromLibrary(widget.folder.path);
    }
  }

  void _playFolder(BuildContext context, AudioProvider provider) {
    final i18n = context.read<AppLanguageProvider>();
    final firstTrack = widget.folder.firstTrack;
    if (firstTrack == null) return;
    Feedback.forTap(context);
    unawaited(provider.spawnSession(firstTrack));
    _showSessionCreatedSnack(
      context,
      i18n.tr('session_created', {'name': firstTrack.displayName}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.read<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final isRootFolder = widget.folder.depth == 0;
    final cardShape = RoundedRectangleBorder(
      side: BorderSide(color: cs.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    );
    final groupLabel = isRootFolder
        ? ''
        : path.basename(path.dirname(widget.folder.path));

    return _SwipeRevealCard(
      margin: const EdgeInsets.only(bottom: 6),
      shape: cardShape,
      actionLabel: i18n.tr('remove'),
      removeTooltip: i18n.tr('remove_audio_folder'),
      onRemove: () => _confirmRemoveFolder(context, provider),
      onWillReveal: _expansionController.collapse,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
        color: cs.surface,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            controller: _expansionController,
            onExpansionChanged: (expanded) {
              if (_expanded == expanded) return;
              setState(() {
                _expanded = expanded;
              });
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            tilePadding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            leading: isRootFolder
                ? _LibraryCoverThumbnail(
                    coverPathFuture: provider.coverPathFutureForFolder(
                      widget.folder.path,
                    ),
                    title: widget.folder.name,
                  )
                : null,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groupLabel.isNotEmpty)
                  Text(
                    groupLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
                  ),
                if (groupLabel.isNotEmpty) const SizedBox(height: 3),
                Text(
                  widget.folder.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1.06,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: _LibraryMetaChip(
                    icon: Icons.library_music_rounded,
                    text: i18n.tr('audio_count', {
                      'count': widget.folder.totalTrackCount,
                    }),
                  ),
                ),
              ],
            ),
            trailing: SizedBox(
              width: 78,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _playFolder(context, provider),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  ),
                  const SizedBox(width: 4),
                  IgnorePointer(
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            children: widget.folder.children
                .map(
                  (childNode) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _LibraryTreeItem(
                      key: ValueKey(childNode.path),
                      node: childNode,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _TrackNodeWidget extends StatelessWidget {
  const _TrackNodeWidget({required this.trackNode});

  final TrackNode trackNode;

  Future<void> _confirmRemoveTrack(
    BuildContext context,
    AudioProvider provider,
    MusicTrack track,
  ) async {
    final i18n = context.read<AppLanguageProvider>();
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: i18n.tr('remove_audio'),
      message: track.displayName,
      cancelLabel: i18n.tr('cancel'),
      confirmLabel: i18n.tr('remove'),
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed == true && context.mounted) {
      await provider.removeTrackFromLibrary(track.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.read<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final track = trackNode.track;
    final isAlreadyPlaying = context.select<AudioProvider, bool>(
      (value) => value.isTrackActive(track.path),
    );
    final folderName = track.isSingle ? i18n.tr('imported_files') : track.groupTitle;
    final cardShape = RoundedRectangleBorder(
      side: BorderSide(
        color: isAlreadyPlaying
            ? cs.primary.withValues(alpha: 0.48)
            : cs.outlineVariant,
      ),
      borderRadius: BorderRadius.circular(14),
    );

    return _SwipeRevealCard(
      margin: const EdgeInsets.only(bottom: 6),
      shape: cardShape,
      actionLabel: i18n.tr('remove'),
      removeTooltip: i18n.tr('remove_audio'),
      onRemove: () => _confirmRemoveTrack(context, provider, track),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
        color: cs.surface,
        child: SizedBox(
          height: 88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          height: 1.06,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: () {
                    Feedback.forTap(context);
                    unawaited(provider.spawnSession(track));
                    _showSessionCreatedSnack(
                      context,
                      i18n.tr('session_created', {'name': track.displayName}),
                    );
                  },
                  icon: Icon(
                    isAlreadyPlaying
                        ? Icons.add_circle_outline_rounded
                        : Icons.play_arrow_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeRevealCard extends StatefulWidget {
  const _SwipeRevealCard({
    required this.child,
    required this.onRemove,
    required this.actionLabel,
    required this.removeTooltip,
    required this.shape,
    this.margin = EdgeInsets.zero,
    this.onWillReveal,
  });

  final Widget child;
  final VoidCallback onRemove;
  final String actionLabel;
  final String removeTooltip;
  final ShapeBorder shape;
  final EdgeInsets margin;
  final VoidCallback? onWillReveal;

  @override
  State<_SwipeRevealCard> createState() => _SwipeRevealCardState();
}

class _SwipeRevealCardState extends State<_SwipeRevealCard> {
  static const double _actionWidth = 128;

  double _revealedWidth = 0;

  bool get _isOpen => _revealedWidth > (_actionWidth * 0.5);

  void _closePane() {
    if (_revealedWidth == 0) return;
    setState(() {
      _revealedWidth = 0;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final nextWidth = (_revealedWidth - details.delta.dx).clamp(
      0.0,
      _actionWidth,
    );
    if (nextWidth == _revealedWidth) return;
    if (_revealedWidth == 0 && nextWidth > 0) {
      HapticFeedback.selectionClick();
      widget.onWillReveal?.call();
    }
    setState(() {
      _revealedWidth = nextWidth;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen =
        velocity < -180 || (velocity.abs() < 180 && _revealedWidth > 44);
    setState(() {
      _revealedWidth = shouldOpen ? _actionWidth : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final cs = Theme.of(context).colorScheme;
    final revealProgress = (_revealedWidth / _actionWidth).clamp(0.0, 1.0);

    return TapRegion(
      onTapOutside: (_) => _closePane(),
      child: Padding(
        padding: widget.margin,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _handleHorizontalDragUpdate,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.errorContainer.withValues(alpha: 0.94),
                        cs.errorContainer.withValues(alpha: 0.82),
                      ],
                    ),
                    shape: widget.shape,
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 18, right: 86),
                          child: AnimatedOpacity(
                            opacity: 0.24 + (revealProgress * 0.76),
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.error.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: cs.error.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.swipe_left_rounded,
                                        size: 14,
                                        color: cs.error,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.actionLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: cs.error,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.removeTooltip,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: cs.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: AnimatedScale(
                            scale: 0.92 + (revealProgress * 0.08),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutBack,
                            child: IconButton.filled(
                              onPressed: () {
                                Feedback.forTap(context);
                                HapticFeedback.mediumImpact();
                                _closePane();
                                widget.onRemove();
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                                minimumSize: const Size(54, 54),
                                maximumSize: const Size(54, 54),
                              ),
                              tooltip: i18n.tr('remove'),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _revealedWidth),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(-value, 0),
                    child: child,
                  );
                },
                child: IgnorePointer(ignoring: _isOpen, child: widget.child),
              ),
              if (_isOpen)
                Positioned.fill(
                  right: _actionWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _closePane,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryCoverThumbnail extends StatelessWidget {
  const _LibraryCoverThumbnail({
    required this.coverPathFuture,
    required this.title,
  });

  final Future<String?> coverPathFuture;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget fallback() {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer,
              cs.secondaryContainer.withValues(alpha: 0.92),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.photo_album_rounded,
            size: 28,
            color: cs.onPrimaryContainer,
          ),
        ),
      );
    }

    return SizedBox(
      width: 78,
      height: 78,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FutureBuilder<String?>(
          future: coverPathFuture,
          builder: (context, snapshot) {
            final coverPath = snapshot.data;
            if (coverPath == null || coverPath.isEmpty) {
              return fallback();
            }
            return Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            );
          },
        ),
      ),
    );
  }
}

class _LibraryMetaChip extends StatelessWidget {
  const _LibraryMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            icon,
            size: 12,
            color: cs.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                fontSize: 9,
              ),
            ),
          ),
        ],
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
