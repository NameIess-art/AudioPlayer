import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

enum SessionLoopMode {
  single,
  crossRandom,
  folderSequential,
  crossSequential,
  folderRandom,
}

enum TimerMode { manual, trigger }

extension SessionLoopModeExtension on SessionLoopMode {
  String get label {
    switch (this) {
      case SessionLoopMode.single:
        return '单曲循环';
      case SessionLoopMode.crossRandom:
        return '随机循环（跨文件夹）';
      case SessionLoopMode.folderSequential:
        return '顺序循环（当前文件夹）';
      case SessionLoopMode.crossSequential:
        return '顺序循环（跨文件夹）';
      case SessionLoopMode.folderRandom:
        return '随机循环（当前文件夹）';
    }
  }
}

class MusicTrack {
  const MusicTrack({
    required this.path,
    required this.displayName,
    required this.groupKey,
    required this.groupTitle,
    required this.groupSubtitle,
    required this.isSingle,
  });

  final String path;
  final String displayName;
  final String groupKey;
  final String groupTitle;
  final String groupSubtitle;
  final bool isSingle;

  Map<String, dynamic> toJson() => {
    'path': path,
    'displayName': displayName,
    'groupKey': groupKey,
    'groupTitle': groupTitle,
    'groupSubtitle': groupSubtitle,
    'isSingle': isSingle,
  };

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    path: json['path'] as String,
    displayName: json['displayName'] as String,
    groupKey: json['groupKey'] as String,
    groupTitle: json['groupTitle'] as String,
    groupSubtitle: json['groupSubtitle'] as String,
    isSingle: json['isSingle'] as bool? ?? false,
  );
}

abstract class LibraryNode {
  String get name;
  String get path;
}

class FolderNode extends LibraryNode {
  @override
  final String name;
  @override
  final String path;
  final List<LibraryNode> children = [];

  FolderNode(this.name, this.path);

  /// Recursively get all tracks inside this folder
  List<MusicTrack> get allTracks {
    final list = <MusicTrack>[];
    for (final child in children) {
      if (child is TrackNode) {
        list.add(child.track);
      } else if (child is FolderNode) {
        list.addAll(child.allTracks);
      }
    }
    return list;
  }

  int get leafFolderCount {
    final childFolders = children.whereType<FolderNode>().toList();
    if (childFolders.isEmpty) return 1;
    return childFolders.fold<int>(
      0,
      (total, folder) => total + folder.leafFolderCount,
    );
  }
}

class TrackNode extends LibraryNode {
  final MusicTrack track;
  TrackNode(this.track);

  @override
  String get name => track.displayName;
  @override
  String get path => track.path;
}

class PlaybackSession {
  PlaybackSession({
    required this.id,
    required this.player,
    required this.currentTrackPath,
    required this.loopMode,
    required this.nonSingleLoopMode,
    required this.volume,
    required this.createdAt,
    required this.state,
  });

  final String id;
  final AudioPlayer player;
  final DateTime createdAt;

  String currentTrackPath;
  String? loadedPath;
  SessionLoopMode loopMode;
  SessionLoopMode nonSingleLoopMode;
  double volume;
  PlayerState state;

  /// True while setAudioSource / play sequence is in progress.
  bool isLoading = false;

  /// Monotonically incremented each time we start loading so stale completions
  /// from previous loads do not accidentally trigger auto-advance.
  int loadGeneration = 0;
  List<StreamSubscription> subscriptions = [];

  void dispose() {
    for (var sub in subscriptions) {
      sub.cancel();
    }
    player.dispose();
  }
}

const _kLibraryKey = 'music_library_v1';
const _kSessionsKey = 'active_sessions_v1';
const _kGroupOrderKey = 'group_order_v1';
const _kSessionOrderKey = 'session_order_v1';
const _kWatchedFoldersKey = 'watched_folders_v1';
const _kTimerSettingsKey = 'timer_settings_v1';
const _kConverterSettingsKey = 'converter_settings_v1';

class AudioProvider with ChangeNotifier {
  static const MethodChannel _powerChannel = MethodChannel(
    'music_player/power',
  );
  final List<MusicTrack> _library = [];
  final Map<String, PlaybackSession> _sessions = {};

  // Ordered list of groupKeys (for drag-reorder persistence)
  final List<String> _groupOrder = [];
  // Ordered list of sessionIds (for drag-reorder persistence, newest-first)
  final List<String> _sessionOrder = [];
  // Paths of folder roots selected by the user (watched for auto-rescan)
  final List<String> _watchedFolders = [];

  // Video conversion settings (configured from Settings tab).
  String _converterFormat = 'mp3';
  String _converterBitrate = '320k';

  static const List<String> converterFormats = [
    'mp3',
    'flac',
    'wav',
    'aac',
    'ogg',
  ];
  static const List<String> converterBitrates = [
    '128k',
    '192k',
    '256k',
    '320k',
  ];

  int _sessionSeed = 0;
  bool _isScanning = false;

  // ---------------------------------------------------------------------------
  // Timer state
  // ---------------------------------------------------------------------------
  TimerMode? _timerMode;
  Duration? _timerDuration;
  bool _timerActive = false;
  Duration? _timerRemaining;
  DateTime? _timerEndsAt;
  Timer? _countdownTimer;
  bool _keepCpuAwake = false;

  // Tracks paused when the timer expired (for auto-resume)
  final List<String> _pausedByTimerPaths = [];

  // Auto-resume (clock-time alarm style)
  bool _autoResumeEnabled = false;
  int _autoResumeHour = 7;
  int _autoResumeMinute = 0;
  Timer? _autoResumeTimer;

  // Getters
  TimerMode? get timerMode => _timerMode;
  Duration? get timerDuration => _timerDuration;
  bool get timerActive => _timerActive;
  Duration? get timerRemaining => _timerRemaining;
  bool get autoResumeEnabled => _autoResumeEnabled;
  int get autoResumeHour => _autoResumeHour;
  int get autoResumeMinute => _autoResumeMinute;
  List<String> get pausedByTimerPaths => List.unmodifiable(_pausedByTimerPaths);
  String get converterFormat => _converterFormat;
  String get converterBitrate => _converterBitrate;

  List<MusicTrack> get library => _library;
  List<String> get watchedFolders => List.unmodifiable(_watchedFolders);

  List<PlaybackSession> get activeSessions {
    // Return sessions in _sessionOrder, newest-first for any not yet in order
    final result = <PlaybackSession>[];
    for (final id in _sessionOrder) {
      final s = _sessions[id];
      if (s != null) result.add(s);
    }
    // Any sessions not in _sessionOrder (shouldn't normally happen, but be safe)
    for (final s in _sessions.values) {
      if (!_sessionOrder.contains(s.id)) result.add(s);
    }
    return result;
  }

  bool get isScanning => _isScanning;

  AudioProvider() {
    _loadData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoResumeTimer?.cancel();
    unawaited(_setKeepCpuAwake(false));
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Library persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLibraryKey);
      if (raw == null || raw.isEmpty) return;
      final list = json.decode(raw) as List<dynamic>;
      final tracks = list
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList();
      _library.addAll(tracks);
      notifyListeners();
    } catch (_) {
      // If loading fails we just start with an empty library
    }
  }

  Future<void> _saveLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_library.map((t) => t.toJson()).toList());
      await prefs.setString(_kLibraryKey, encoded);
    } catch (_) {}
  }

  Future<void> _loadGroupOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kGroupOrderKey);
      if (raw == null || raw.isEmpty) return;
      final list = (json.decode(raw) as List<dynamic>).cast<String>();
      _groupOrder.clear();
      _groupOrder.addAll(list);
    } catch (_) {}
  }

  Future<void> _saveGroupOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGroupOrderKey, json.encode(_groupOrder));
    } catch (_) {}
  }

  Future<void> _loadSessionOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionOrderKey);
      if (raw == null || raw.isEmpty) return;
      final list = (json.decode(raw) as List<dynamic>).cast<String>();
      _sessionOrder.clear();
      _sessionOrder.addAll(list);
    } catch (_) {}
  }

  Future<void> _saveSessionOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSessionOrderKey, json.encode(_sessionOrder));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Session persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadData() async {
    await _loadLibrary();
    await _loadGroupOrder();
    await _loadSessionOrder();
    await _loadWatchedFolders();
    await _loadConverterSettings();
    await _loadTimerSettings();
    await _loadSessions();
    _syncKeepCpuAwake();
  }

  Future<void> _loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionsKey);
      if (raw == null || raw.isEmpty) return;
      final list = json.decode(raw) as List<dynamic>;

      // Restore sessions in saved order (oldest-first storage)
      final restoredIds = <String>[];
      for (final item in list.whereType<Map<String, dynamic>>()) {
        final trackPath = item['path'] as String?;
        if (trackPath == null) continue;
        final track = trackByPath(trackPath);
        if (track == null) continue; // Library may have been cleared

        final loopModeIndex =
            item['loopMode'] as int? ?? SessionLoopMode.folderSequential.index;
        final loopMode = SessionLoopMode
            .values[loopModeIndex.clamp(0, SessionLoopMode.values.length - 1)];
        final volume = (item['volume'] as num?)?.toDouble() ?? 1.0;

        // Spawn a paused session (avoids blasting audio on startup).
        final player = AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        );
        final session = PlaybackSession(
          id: 'session_${++_sessionSeed}',
          player: player,
          currentTrackPath: track.path,
          loopMode: loopMode,
          nonSingleLoopMode: loopMode == SessionLoopMode.single
              ? SessionLoopMode.folderSequential
              : loopMode,
          volume: volume,
          createdAt: DateTime.now(),
          state: player.playerState,
        );
        _sessions[session.id] = session;
        _bindSessionListeners(session);
        restoredIds.add(session.id);

        // Load the source so the duration/progress bar shows immediately
        // but keep it paused.
        try {
          final uri = track.path.startsWith('content://')
              ? Uri.parse(track.path)
              : Uri.file(track.path);
          await player.setAudioSource(AudioSource.uri(uri));
          await player.setVolume(volume);
          await player.setLoopMode(
            loopMode == SessionLoopMode.single ? LoopMode.one : LoopMode.off,
          );
          session.loadedPath = track.path;
        } catch (_) {}
      }

      // Merge persisted session order with restored IDs
      // Keep any IDs from _sessionOrder that were restored, then append new ones
      final validOrdered = _sessionOrder
          .where((id) => restoredIds.contains(id))
          .toList();
      for (final id in restoredIds) {
        if (!validOrdered.contains(id)) validOrdered.add(id);
      }
      _sessionOrder.clear();
      _sessionOrder.addAll(validOrdered);

      if (_sessions.isNotEmpty) notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveSessionState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save in display order (as stored in _sessionOrder)
      final ordered = _sessionOrder
          .map((id) => _sessions[id])
          .whereType<PlaybackSession>()
          .toList();
      final encoded = json.encode(
        ordered
            .map(
              (s) => {
                'path': s.currentTrackPath,
                'loopMode': s.loopMode.index,
                'volume': s.volume,
              },
            )
            .toList(),
      );
      await prefs.setString(_kSessionsKey, encoded);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Watched folders persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadWatchedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kWatchedFoldersKey);
      if (raw == null || raw.isEmpty) return;
      final list = (json.decode(raw) as List<dynamic>).cast<String>();
      _watchedFolders.clear();
      _watchedFolders.addAll(list);
    } catch (_) {}
  }

  Future<void> _saveWatchedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kWatchedFoldersKey, json.encode(_watchedFolders));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Timer Settings persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadTimerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTimerSettingsKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw) as Map<String, dynamic>;
      _autoResumeEnabled = map['autoResumeEnabled'] as bool? ?? false;
      _autoResumeHour = map['autoResumeHour'] as int? ?? 7;
      _autoResumeMinute = map['autoResumeMinute'] as int? ?? 0;
    } catch (_) {}
  }

  Future<void> _saveTimerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode({
        'autoResumeEnabled': _autoResumeEnabled,
        'autoResumeHour': _autoResumeHour,
        'autoResumeMinute': _autoResumeMinute,
      });
      await prefs.setString(_kTimerSettingsKey, encoded);
    } catch (_) {}
  }

  Future<void> _loadConverterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kConverterSettingsKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw) as Map<String, dynamic>;

      final savedFormat = map['format'] as String?;
      final savedBitrate = map['bitrate'] as String?;

      if (savedFormat != null && converterFormats.contains(savedFormat)) {
        _converterFormat = savedFormat;
      }
      if (savedBitrate != null && converterBitrates.contains(savedBitrate)) {
        _converterBitrate = savedBitrate;
      }
    } catch (_) {}
  }

  Future<void> _saveConverterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode({
        'format': _converterFormat,
        'bitrate': _converterBitrate,
      });
      await prefs.setString(_kConverterSettingsKey, encoded);
    } catch (_) {}
  }

  void setConverterSettings({String? format, String? bitrate}) {
    var changed = false;
    if (format != null &&
        converterFormats.contains(format) &&
        format != _converterFormat) {
      _converterFormat = format;
      changed = true;
    }
    if (bitrate != null &&
        converterBitrates.contains(bitrate) &&
        bitrate != _converterBitrate) {
      _converterBitrate = bitrate;
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    unawaited(_saveConverterSettings());
  }

  /// Register [folderPath] as a watched folder (idempotent).
  void addWatchedFolder(String folderPath) {
    if (!_watchedFolders.contains(folderPath)) {
      _watchedFolders.add(folderPath);
      unawaited(_saveWatchedFolders());
    }
  }

  /// Stop watching [folderPath].
  void removeWatchedFolder(String folderPath) {
    if (_watchedFolders.remove(folderPath)) {
      unawaited(_saveWatchedFolders());
    }
  }

  // ---------------------------------------------------------------------------
  // Library management
  // ---------------------------------------------------------------------------

  void setScanning(bool scanning) {
    _isScanning = scanning;
    notifyListeners();
  }

  void addTracks(List<MusicTrack> newTracks) {
    final existingPaths = _library.map((t) => t.path).toSet();
    final toAdd = newTracks
        .where((t) => !existingPaths.contains(t.path))
        .toList();
    if (toAdd.isNotEmpty) {
      _library.addAll(toAdd);
      // Add new groupKeys to _groupOrder if not already present
      for (final t in toAdd) {
        if (!_groupOrder.contains(t.groupKey)) {
          _groupOrder.add(t.groupKey);
        }
      }
      notifyListeners();
      _saveLibrary();
      _saveGroupOrder();
    }
  }

  void removeTrackFromLibrary(String trackPath) {
    _library.removeWhere((t) => t.path == trackPath);

    final sessionsToRemove = _sessions.values
        .where((s) => s.currentTrackPath == trackPath)
        .map((s) => s.id)
        .toList();
    for (final id in sessionsToRemove) {
      removeSession(id);
    }

    notifyListeners();
    _saveLibrary();
  }

  /// Remove an entire folder (node) from the library, including all its tracks
  /// and any active sessions playing those tracks.
  void removeFolderFromLibrary(String folderPath) {
    // Collect track paths belonging to this folder (starts with folderPath)
    final trackPaths = _library
        .where((t) => t.path.startsWith(folderPath))
        .map((t) => t.path)
        .toSet();

    // Stop and remove active sessions for tracks in this folder
    final sessionsToRemove = _sessions.values
        .where((s) => trackPaths.contains(s.currentTrackPath))
        .map((s) => s.id)
        .toList();
    for (final id in sessionsToRemove) {
      removeSession(id);
    }

    // Remove tracks from library
    _library.removeWhere((t) => t.path.startsWith(folderPath));

    // Remove from group order
    _groupOrder.removeWhere((key) => key.startsWith(folderPath));

    // Remove from watched folders if it's a root
    if (_watchedFolders.contains(folderPath)) {
      _watchedFolders.remove(folderPath);
      unawaited(_saveWatchedFolders());
    }

    notifyListeners();
    _saveLibrary();
    _saveGroupOrder();
  }

  int getTrackComparator(MusicTrack a, MusicTrack b) {
    final groupResult = a.groupTitle.toLowerCase().compareTo(
      b.groupTitle.toLowerCase(),
    );
    if (groupResult != 0) return groupResult;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  List<LibraryNode> buildLibraryTree() {
    final rootNodes = <String, FolderNode>{};
    final singleFiles = <TrackNode>[];

    // Identify roots: we'll use the tracked groupKeys or watched folders as base roots.
    // To present a nice tree, we figure out the relative paths from the roots.
    for (final track in _library) {
      if (track.isSingle) {
        singleFiles.add(TrackNode(track));
        continue;
      }

      // Start building from the track's folder up to the root
      String dirPath = track.groupKey;

      // If we don't have a top-level node for this dir yet, we create the chain
      // First, find if this dir belongs to any root we already know
      String? matchedRoot;
      for (final root in _watchedFolders) {
        if (dirPath.startsWith(root)) {
          matchedRoot = root;
          break;
        }
      }

      // Fallback: if not in watched folder, treat groupKey as its own root
      matchedRoot ??= dirPath;

      // Ensure root exists
      if (!rootNodes.containsKey(matchedRoot)) {
        final rootName = _resolveRootNodeName(matchedRoot, track);
        rootNodes[matchedRoot] = FolderNode(rootName, matchedRoot);
      }

      // Build intermediate folders
      FolderNode currentNode = rootNodes[matchedRoot]!;
      final rootDisplayName = currentNode.name;

      if (dirPath != matchedRoot && dirPath.length > matchedRoot.length) {
        // e.g. matchedRoot: /a/b, dirPath: /a/b/c/d
        String relDir = dirPath.substring(matchedRoot.length);
        if (relDir.startsWith('::')) {
          // Android SAF groupKey format: "<rootUri>::<relative/path>"
          relDir = relDir.substring(2);
        }
        if (relDir.startsWith(path.separator)) relDir = relDir.substring(1);

        final parts = relDir.split(RegExp(r'[\\/]+'));
        String currentPath = matchedRoot;

        for (final rawPart in parts) {
          final part = _sanitizeFolderPart(rawPart, rootDisplayName);
          if (part.isEmpty) continue;
          currentPath = currentPath.endsWith(path.separator)
              ? currentPath + part
              : currentPath + path.separator + part;

          // Find or create child folder
          int childIdx = currentNode.children.indexWhere(
            (c) => c is FolderNode && c.name == part,
          );
          if (childIdx == -1) {
            final newFolder = FolderNode(part, currentPath);
            currentNode.children.add(newFolder);
            currentNode = newFolder;
          } else {
            currentNode = currentNode.children[childIdx] as FolderNode;
          }
        }
      }

      // Finally add the track to the current (deepest) folder node
      currentNode.children.add(TrackNode(track));
    }

    // Sort the tree
    void sortFolder(FolderNode folder) {
      folder.children.sort((a, b) {
        // Folders before files
        if (a is FolderNode && b is TrackNode) return -1;
        if (a is TrackNode && b is FolderNode) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      for (final child in folder.children) {
        if (child is FolderNode) sortFolder(child);
      }
    }

    final topLevel = <LibraryNode>[];

    // Convert root map to list and sort them
    final roots = rootNodes.values.toList();
    for (final root in roots) {
      sortFolder(root);
      topLevel.add(root);
    }

    topLevel.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // Add single files at the end
    singleFiles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    topLevel.addAll(singleFiles);

    return topLevel;
  }

  String _resolveRootNodeName(String rootPath, MusicTrack track) {
    final subtitle = _normalizeDisplaySegment(track.groupSubtitle);
    if (subtitle.isNotEmpty) {
      final fromSubtitle = _normalizeDisplaySegment(
        subtitle.split('/').first.trim(),
      );
      if (fromSubtitle.isNotEmpty && fromSubtitle != rootPath) {
        return fromSubtitle;
      }
    }

    final decodedTreeName = _decodeTreeRootName(rootPath);
    if (decodedTreeName != null && decodedTreeName.isNotEmpty) {
      return decodedTreeName;
    }

    final baseName = _normalizeDisplaySegment(path.basename(rootPath));
    return baseName.isEmpty ? rootPath : baseName;
  }

  String? _decodeTreeRootName(String rawPath) {
    if (!rawPath.startsWith('content://')) return null;
    final uri = Uri.tryParse(rawPath);
    if (uri == null) return null;

    final segments = uri.pathSegments;
    final treeIndex = segments.indexOf('tree');
    if (treeIndex < 0 || treeIndex + 1 >= segments.length) return null;

    final documentId = _safeUriDecode(segments[treeIndex + 1]);
    if (documentId.isEmpty) return null;
    final lastPart = documentId.split('/').last;
    final colonIndex = lastPart.lastIndexOf(':');
    if (colonIndex >= 0 && colonIndex + 1 < lastPart.length) {
      return _normalizeDisplaySegment(
        lastPart.substring(colonIndex + 1).trim(),
      );
    }
    return _normalizeDisplaySegment(lastPart.trim());
  }

  String _normalizeDisplaySegment(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return normalized;

    normalized = _safeUriDecode(normalized);

    // Some SAF providers return mojibake-like latin1-decoded UTF-8 names.
    final maybeFixed = _tryLatin1ToUtf8(normalized);
    if (_looksLikeMojibake(normalized) && !_looksLikeMojibake(maybeFixed)) {
      normalized = maybeFixed;
    }
    return normalized;
  }

  String _safeUriDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  String _tryLatin1ToUtf8(String input) {
    try {
      return utf8.decode(latin1.encode(input), allowMalformed: false);
    } catch (_) {
      return input;
    }
  }

  bool _looksLikeMojibake(String value) {
    const mojibakePattern =
        r'[ÃÂÅÆÇÐÑØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ�]';
    return RegExp(mojibakePattern).hasMatch(value);
  }

  String _sanitizeFolderPart(String rawPart, String rootDisplayName) {
    var part = _normalizeDisplaySegment(rawPart);
    if (part.isEmpty) return part;

    part = part.replaceFirst(
      RegExp(r'^document[\\/]+', caseSensitive: false),
      '',
    );
    if (part.isEmpty) return part;

    if (part.contains('::')) {
      part = part.split('::').last;
    }

    part = _normalizeDisplaySegment(part);
    if (part.startsWith('primary:') ||
        part.startsWith('home:') ||
        part.startsWith('raw:')) {
      final idx = part.indexOf(':');
      if (idx >= 0 && idx + 1 < part.length) {
        part = part.substring(idx + 1);
      }
    }

    if (part.contains('/')) {
      part = part.split('/').last;
    }
    part = part.trim();

    if (part.toLowerCase() == 'document') return '';
    if (part == rootDisplayName) return '';
    return part;
  }

  MusicTrack? trackByPath(String trackPath) {
    for (final track in _library) {
      if (track.path == trackPath) return track;
    }
    return null;
  }

  /// Returns all tracks that belong to the same folder group as the given track.
  List<MusicTrack> tracksInSameGroup(String trackPath) {
    final track = trackByPath(trackPath);
    if (track == null) return [];
    return _library.where((t) => t.groupKey == track.groupKey).toList()
      ..sort(getTrackComparator);
  }

  // ---------------------------------------------------------------------------
  // Session management (concurrent playback)
  // ---------------------------------------------------------------------------

  Future<void> spawnSession(MusicTrack track) async {
    final player = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    final session = PlaybackSession(
      id: 'session_${++_sessionSeed}',
      player: player,
      currentTrackPath: track.path,
      loopMode: SessionLoopMode.folderSequential,
      nonSingleLoopMode: SessionLoopMode.folderSequential,
      volume: 1.0,
      createdAt: DateTime.now(),
      state: player.playerState,
    );

    _sessions[session.id] = session;
    // Insert at the front of session order (newest first in display)
    _sessionOrder.insert(0, session.id);
    _bindSessionListeners(session);
    notifyListeners();

    await _prepareAndPlay(session, nextPath: track.path, autoPlay: false);
    unawaited(_saveSessionState());
    unawaited(_saveSessionOrder());
  }

  void _bindSessionListeners(PlaybackSession session) {
    final stateSub = session.player.playerStateStream.listen((state) {
      if (!_sessions.containsKey(session.id)) return;

      final previousProcessing = session.state.processingState;
      session.state = state;
      _syncKeepCpuAwake();
      notifyListeners();

      // Only trigger auto-advance when:
      //  1. The track actually just reached the end (idle after playing),
      //  2. We are NOT currently in the middle of loading a new source, and
      //  3. This listener generation matches the current load generation
      //     (prevents stale completions from an old load from firing).
      final isNewCompletion =
          previousProcessing != ProcessingState.completed &&
          state.processingState == ProcessingState.completed;

      if (isNewCompletion && !session.isLoading) {
        _handleSessionCompleted(session.id);
      }
    });
    session.subscriptions.add(stateSub);
  }

  Future<void> _prepareAndPlay(
    PlaybackSession session, {
    required String nextPath,
    bool autoPlay = true,
  }) async {
    if (!_sessions.containsKey(session.id)) return;

    // Bump the generation counter so any stale completion callbacks from the
    // previous source are ignored.
    session.loadGeneration++;
    session.isLoading = true;
    final willLoadNewAudio = session.loadedPath != nextPath;
    notifyListeners();

    try {
      session.currentTrackPath = nextPath;
      final uri = nextPath.startsWith('content://')
          ? Uri.parse(nextPath)
          : Uri.file(nextPath);

      // Always set source when path changes; for same-path replays just seek.
      if (session.loadedPath != nextPath) {
        await session.player.setAudioSource(AudioSource.uri(uri));
        session.loadedPath = nextPath;
      } else {
        await session.player.seek(Duration.zero);
      }

      await session.player.setVolume(session.volume);
      // Single-track loop is handled by the player natively; others by our listener.
      await session.player.setLoopMode(
        session.loopMode == SessionLoopMode.single
            ? LoopMode.one
            : LoopMode.off,
      );
    } catch (e) {
      debugPrint('AudioProvider._prepareAndPlay error: $e');
    } finally {
      if (_sessions.containsKey(session.id)) {
        session.isLoading = false;
        notifyListeners();
      }
    }
    // Fire play() without awaiting: on Android with handleAudioSessionActivation=false
    // the Future never resolves, which would permanently block the finally block above.
    if (_sessions.containsKey(session.id) && autoPlay) {
      unawaited(session.player.play());
      _syncKeepCpuAwake();
      // Trigger mode: only restart countdown when a new audio source starts.
      if (_timerMode == TimerMode.trigger &&
          _timerDuration != null &&
          willLoadNewAudio) {
        _resetAndStartCountdown();
      }
    } else if (_sessions.containsKey(session.id)) {
      _syncKeepCpuAwake();
    }
  }

  Future<void> toggleSessionPlayPause(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || session.isLoading) return;

    if (session.state.playing) {
      await session.player.pause();
    } else {
      if (session.state.processingState == ProcessingState.completed) {
        final replayingSameSource =
            session.loadedPath == session.currentTrackPath;
        await _prepareAndPlay(session, nextPath: session.currentTrackPath);
        // Trigger mode: replaying the same completed track from playlist
        // should also start/restart countdown.
        if (replayingSameSource &&
            _timerMode == TimerMode.trigger &&
            _timerDuration != null) {
          _resetAndStartCountdown();
        }
      } else {
        // Keep this non-blocking: with handleAudioSessionActivation=false on
        // some Android devices play() Future may never complete.
        unawaited(session.player.play());
        // Trigger mode: tapping play in playlist should also start/restart countdown.
        if (_timerMode == TimerMode.trigger && _timerDuration != null) {
          _resetAndStartCountdown();
        }
      }
    }
  }

  Future<void> removeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      _sessionOrder.remove(sessionId);
      await session.player.stop();
      session.dispose();
      _syncKeepCpuAwake();
      notifyListeners();
      unawaited(_saveSessionState());
      unawaited(_saveSessionOrder());
    }
  }

  Future<void> setSessionLoopMode(
    String sessionId,
    SessionLoopMode mode,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.loopMode = mode;
    if (mode != SessionLoopMode.single) {
      session.nonSingleLoopMode = mode;
    }
    await session.player.setLoopMode(
      mode == SessionLoopMode.single ? LoopMode.one : LoopMode.off,
    );
    notifyListeners();
    unawaited(_saveSessionState());
  }

  bool _isShuffleMode(SessionLoopMode mode) {
    return mode == SessionLoopMode.crossRandom ||
        mode == SessionLoopMode.folderRandom;
  }

  bool _isCrossFolderMode(SessionLoopMode mode) {
    return mode == SessionLoopMode.crossRandom ||
        mode == SessionLoopMode.crossSequential;
  }

  Future<void> toggleSessionSingleLoop(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    if (session.loopMode == SessionLoopMode.single) {
      await setSessionLoopMode(sessionId, session.nonSingleLoopMode);
      return;
    }
    session.nonSingleLoopMode = session.loopMode;
    await setSessionLoopMode(sessionId, SessionLoopMode.single);
  }

  Future<void> toggleSessionShuffle(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || session.loopMode == SessionLoopMode.single) return;
    final isCrossFolder = _isCrossFolderMode(session.loopMode);
    final isShuffle = _isShuffleMode(session.loopMode);
    final nextMode = isShuffle
        ? (isCrossFolder
              ? SessionLoopMode.crossSequential
              : SessionLoopMode.folderSequential)
        : (isCrossFolder
              ? SessionLoopMode.crossRandom
              : SessionLoopMode.folderRandom);
    await setSessionLoopMode(sessionId, nextMode);
  }

  Future<void> toggleSessionCrossFolder(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || session.loopMode == SessionLoopMode.single) return;
    final isCrossFolder = _isCrossFolderMode(session.loopMode);
    final isShuffle = _isShuffleMode(session.loopMode);
    final nextMode = isCrossFolder
        ? (isShuffle
              ? SessionLoopMode.folderRandom
              : SessionLoopMode.folderSequential)
        : (isShuffle
              ? SessionLoopMode.crossRandom
              : SessionLoopMode.crossSequential);
    await setSessionLoopMode(sessionId, nextMode);
  }

  Future<void> setSessionVolume(String sessionId, double volume) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.volume = volume.clamp(0.0, 1.0);
    await session.player.setVolume(session.volume);
    notifyListeners();
    unawaited(_saveSessionState());
  }

  Future<void> seekSession(String sessionId, Duration position) async {
    final session = _sessions[sessionId];
    if (session != null) {
      await session.player.seek(position);
    }
  }

  /// Switch the current track of a session to a new path and start playing.
  Future<void> switchSessionTrack(String sessionId, String newPath) async {
    final session = _sessions[sessionId];
    if (session == null || session.isLoading) return;
    await _prepareAndPlay(session, nextPath: newPath);
    unawaited(_saveSessionState());
  }

  /// Skip to the next track according to the session's current loop mode.
  Future<void> seekSessionToNext(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || session.isLoading) return;
    final nextPath = _nextPathFor(session, forward: true);
    if (nextPath != null) {
      await _prepareAndPlay(session, nextPath: nextPath);
    }
  }

  /// Skip to the previous track according to the session's current loop mode.
  Future<void> seekSessionToPrev(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || session.isLoading) return;
    // If more than 3 s into the track, just restart it.
    if ((session.player.position.inSeconds) > 3) {
      await session.player.seek(Duration.zero);
      return;
    }
    final prevPath = _nextPathFor(session, forward: false);
    if (prevPath != null) {
      await _prepareAndPlay(session, nextPath: prevPath);
    }
  }

  Future<void> pauseAllSessions() async {
    await Future.wait(_sessions.values.map((s) => s.player.pause()));
    _syncKeepCpuAwake();
  }

  Future<void> clearAllSessions() async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      await removeSession(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Timer management
  // ---------------------------------------------------------------------------

  /// Configure timer mode and duration. Does NOT start the countdown yet
  /// (for manual mode the user taps "start"; for trigger mode the countdown
  /// starts automatically when any audio begins playing).
  void configureTimer(TimerMode mode, Duration duration) {
    _cancelTimerInternal();
    _timerMode = mode;
    _timerDuration = duration;
    _timerRemaining = duration;
    _timerEndsAt = null;
    _timerActive = false;
    _syncKeepCpuAwake();
    notifyListeners();
  }

  /// Start the countdown immediately (used for manual mode and internally).
  void startCountdown() {
    if (_timerDuration == null || _timerActive) return;
    _timerActive = true;
    _timerRemaining = _timerDuration;
    _timerEndsAt = DateTime.now().add(_timerDuration!);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickCountdown(),
    );
    _syncKeepCpuAwake();
    notifyListeners();
  }

  /// Cancel a running or configured timer.
  void cancelTimer() {
    _cancelTimerInternal();
    _timerMode = null;
    _timerDuration = null;
    _timerRemaining = null;
    _timerEndsAt = null;
    _pausedByTimerPaths.clear();
    _syncKeepCpuAwake();
    notifyListeners();
  }

  void _cancelTimerInternal() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timerEndsAt = null;
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
    _timerActive = false;
    _syncKeepCpuAwake();
  }

  void _onTimerExpired() {
    _timerActive = false;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timerEndsAt = null;

    // Remember which sessions were playing so we can resume them
    _pausedByTimerPaths.clear();
    for (final s in _sessions.values) {
      if (s.state.playing) {
        _pausedByTimerPaths.add(s.currentTrackPath);
      }
    }

    // Pause all
    for (final s in _sessions.values) {
      s.player.pause();
    }

    notifyListeners();

    // Schedule auto-resume at the configured clock time if enabled
    if (_autoResumeEnabled) {
      _autoResumeTimer?.cancel();
      final delay = _delayUntilClockTime(_autoResumeHour, _autoResumeMinute);
      _autoResumeTimer = Timer(delay, _onAutoResume);
    }
    _syncKeepCpuAwake();
  }

  void _onAutoResume() {
    _autoResumeTimer = null;
    // Resume sessions that were paused by the timer
    for (final s in _sessions.values) {
      if (_pausedByTimerPaths.contains(s.currentTrackPath)) {
        s.player.play();
      }
    }
    _pausedByTimerPaths.clear();
    _syncKeepCpuAwake();
    notifyListeners();
  }

  void setAutoResume(bool enabled, int hour, int minute) {
    _autoResumeEnabled = enabled;
    _autoResumeHour = hour;
    _autoResumeMinute = minute;
    _syncKeepCpuAwake();
    notifyListeners();
    unawaited(_saveTimerSettings());
  }

  /// Returns the Duration until the next occurrence of [hour]:[minute].
  /// If that time has already passed today, schedules for tomorrow.
  Duration _delayUntilClockTime(int hour, int minute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }

  /// Restart countdown from _timerDuration (cancels any in-progress timer).
  void _resetAndStartCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timerEndsAt = null;
    _timerActive = false;
    startCountdown();
  }

  void _tickCountdown() {
    if (!_timerActive || _timerEndsAt == null) return;
    final remaining = _timerEndsAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _timerRemaining = Duration.zero;
      notifyListeners();
      _onTimerExpired();
      return;
    }

    final roundedSeconds = (remaining.inMilliseconds + 999) ~/ 1000;
    final next = Duration(seconds: roundedSeconds);
    if (next == _timerRemaining) return;
    _timerRemaining = next;
    notifyListeners();
  }

  bool get _shouldKeepCpuAwake {
    final anyPlaying = _sessions.values.any((s) => s.state.playing);
    return anyPlaying || _timerActive;
  }

  void _syncKeepCpuAwake() {
    final shouldKeepAwake = _shouldKeepCpuAwake;
    if (_keepCpuAwake == shouldKeepAwake) return;
    _keepCpuAwake = shouldKeepAwake;
    unawaited(_setKeepCpuAwake(shouldKeepAwake));
  }

  Future<void> _setKeepCpuAwake(bool enabled) async {
    try {
      await _powerChannel.invokeMethod<void>('setKeepCpuAwake', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Non-Android platforms don't expose this channel.
    } catch (e) {
      debugPrint('AudioProvider._setKeepCpuAwake error: $e');
    }
  }

  /// Reorder sessions in the display list.
  void reorderSessions(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sessionOrder.length) return;
    if (newIndex < 0 || newIndex > _sessionOrder.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = _sessionOrder.removeAt(oldIndex);
    _sessionOrder.insert(newIndex, moved);
    notifyListeners();
    unawaited(_saveSessionOrder());
  }

  // ---------------------------------------------------------------------------
  // Completion / auto-advance
  // ---------------------------------------------------------------------------

  Future<void> _handleSessionCompleted(String sessionId) async {
    final session = _sessions[sessionId];
    // Guard: don't advance if already loading, or if single-loop (player handles it)
    if (session == null || session.isLoading) return;
    if (session.loopMode == SessionLoopMode.single) {
      return; // LoopMode.one handles it
    }

    final nextPath = _nextPathFor(session, forward: true);
    if (nextPath == null) return;

    if (nextPath == session.currentTrackPath) {
      // Same track – just rewind and play (shouldn't happen for non-single modes
      // unless there's only 1 track in the scope).
      await session.player.seek(Duration.zero);
      await session.player.play();
    } else {
      await _prepareAndPlay(session, nextPath: nextPath);
    }
  }

  /// Returns the next (forward=true) or previous (forward=false) track path
  /// for the given session according to its loop mode.
  String? _nextPathFor(PlaybackSession session, {required bool forward}) {
    final currentTrack = trackByPath(session.currentTrackPath);
    if (currentTrack == null || _library.isEmpty) return null;

    switch (session.loopMode) {
      case SessionLoopMode.single:
        return currentTrack.path;

      case SessionLoopMode.crossRandom:
        if (forward) {
          final all = _library.map((t) => t.path).toList();
          if (all.length == 1) return all.first;
          final rnd = Random();
          String candidate = all[rnd.nextInt(all.length)];
          int guard = 0;
          while (candidate == currentTrack.path && guard < 10) {
            candidate = all[rnd.nextInt(all.length)];
            guard++;
          }
          return candidate;
        } else {
          // Prev in random: just random too
          return _nextPathFor(session, forward: true);
        }

      case SessionLoopMode.folderSequential:
        final scope =
            _library.where((t) => t.groupKey == currentTrack.groupKey).toList()
              ..sort(getTrackComparator);
        if (scope.isEmpty) return currentTrack.path;
        final idx = scope.indexWhere((t) => t.path == currentTrack.path);
        if (idx < 0) return scope.first.path;
        final next = (idx + (forward ? 1 : -1) + scope.length) % scope.length;
        return scope[next].path;

      case SessionLoopMode.crossSequential:
        final all = [..._library]..sort(getTrackComparator);
        final idx = all.indexWhere((t) => t.path == currentTrack.path);
        if (idx < 0) return all.first.path;
        final next = (idx + (forward ? 1 : -1) + all.length) % all.length;
        return all[next].path;

      case SessionLoopMode.folderRandom:
        if (forward) {
          final scope = _library
              .where((t) => t.groupKey == currentTrack.groupKey)
              .map((t) => t.path)
              .toList();
          if (scope.isEmpty) return currentTrack.path;
          if (scope.length == 1) return scope.first;
          final rnd = Random();
          String candidate = scope[rnd.nextInt(scope.length)];
          int guard = 0;
          while (candidate == currentTrack.path && guard < 10) {
            candidate = scope[rnd.nextInt(scope.length)];
            guard++;
          }
          return candidate;
        } else {
          // Prev in random: just random too
          return _nextPathFor(session, forward: true);
        }
    }
  }
}
