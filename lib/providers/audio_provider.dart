import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;


enum SessionLoopMode { single, random, folder, crossFolder }

extension SessionLoopModeExtension on SessionLoopMode {
  String get label {
    switch (this) {
      case SessionLoopMode.single:
        return '单曲循环';
      case SessionLoopMode.random:
        return '随机循环';
      case SessionLoopMode.folder:
        return '文件夹循环';
      case SessionLoopMode.crossFolder:
        return '全部循环';
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

class AudioProvider with ChangeNotifier {
  final List<MusicTrack> _library = [];
  final Map<String, PlaybackSession> _sessions = {};

  // Ordered list of groupKeys (for drag-reorder persistence)
  final List<String> _groupOrder = [];
  // Ordered list of sessionIds (for drag-reorder persistence, newest-first)
  final List<String> _sessionOrder = [];
  // Paths of folder roots selected by the user (watched for auto-rescan)
  final List<String> _watchedFolders = [];

  int _sessionSeed = 0;
  bool _isScanning = false;

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
    await _loadSessions();
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

        final loopModeIndex = item['loopMode'] as int? ?? SessionLoopMode.folder.index;
        final loopMode = SessionLoopMode.values[loopModeIndex.clamp(0, SessionLoopMode.values.length - 1)];
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
              loopMode == SessionLoopMode.single ? LoopMode.one : LoopMode.off);
          session.loadedPath = track.path;
        } catch (_) {}
      }

      // Merge persisted session order with restored IDs
      // Keep any IDs from _sessionOrder that were restored, then append new ones
      final validOrdered = _sessionOrder.where((id) => restoredIds.contains(id)).toList();
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
      final encoded = json.encode(ordered.map((s) => {
        'path': s.currentTrackPath,
        'loopMode': s.loopMode.index,
        'volume': s.volume,
      }).toList());
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
    final toAdd = newTracks.where((t) => !existingPaths.contains(t.path)).toList();
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
    final groupResult = a.groupTitle.toLowerCase().compareTo(b.groupTitle.toLowerCase());
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
        final rootName = path.basename(matchedRoot);
        rootNodes[matchedRoot] = FolderNode(rootName.isEmpty ? matchedRoot : rootName, matchedRoot);
      }

      // Build intermediate folders
      FolderNode currentNode = rootNodes[matchedRoot]!;
      
      if (dirPath != matchedRoot && dirPath.length > matchedRoot.length) {
        // e.g. matchedRoot: /a/b, dirPath: /a/b/c/d
        String relDir = dirPath.substring(matchedRoot.length);
        if (relDir.startsWith(path.separator)) relDir = relDir.substring(1);
        
        final parts = relDir.split(path.separator);
        String currentPath = matchedRoot;
        
        for (final part in parts) {
          if (part.isEmpty) continue;
          currentPath = currentPath.endsWith(path.separator) 
              ? currentPath + part 
              : currentPath + path.separator + part;
              
          // Find or create child folder
          int childIdx = currentNode.children.indexWhere((c) => c is FolderNode && c.name == part);
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
    
    topLevel.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    
    // Add single files at the end
    singleFiles.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    topLevel.addAll(singleFiles);

    return topLevel;
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
    return _library
        .where((t) => t.groupKey == track.groupKey)
        .toList()
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
      loopMode: SessionLoopMode.folder,
      volume: 1.0,
      createdAt: DateTime.now(),
      state: player.playerState,
    );

    _sessions[session.id] = session;
    // Insert at the front of session order (newest first in display)
    _sessionOrder.insert(0, session.id);
    _bindSessionListeners(session);
    notifyListeners();

    await _prepareAndPlay(session, nextPath: track.path);
    unawaited(_saveSessionState());
    unawaited(_saveSessionOrder());
  }

  void _bindSessionListeners(PlaybackSession session) {
    final stateSub = session.player.playerStateStream.listen((state) {
      if (!_sessions.containsKey(session.id)) return;

      final previousProcessing = session.state.processingState;
      session.state = state;
      notifyListeners();

      // Only trigger auto-advance when:
      //  1. The track actually just reached the end (idle after playing),
      //  2. We are NOT currently in the middle of loading a new source, and
      //  3. This listener generation matches the current load generation
      //     (prevents stale completions from an old load from firing).
      final isNewCompletion = previousProcessing != ProcessingState.completed
          && state.processingState == ProcessingState.completed;

      if (isNewCompletion && !session.isLoading) {
        _handleSessionCompleted(session.id);
      }
    });
    session.subscriptions.add(stateSub);
  }

  Future<void> _prepareAndPlay(PlaybackSession session, {required String nextPath}) async {
    if (!_sessions.containsKey(session.id)) return;

    // Bump the generation counter so any stale completion callbacks from the
    // previous source are ignored.
    session.loadGeneration++;
    session.isLoading = true;
    notifyListeners();

    try {
      session.currentTrackPath = nextPath;
      final uri = nextPath.startsWith('content://') ? Uri.parse(nextPath) : Uri.file(nextPath);

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
          session.loopMode == SessionLoopMode.single ? LoopMode.one : LoopMode.off);
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
    if (_sessions.containsKey(session.id)) {
      unawaited(session.player.play());
    }
  }

  Future<void> toggleSessionPlayPause(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || session.isLoading) return;

    if (session.state.playing) {
      await session.player.pause();
    } else {
      if (session.state.processingState == ProcessingState.completed) {
        await _prepareAndPlay(session, nextPath: session.currentTrackPath);
      } else {
        await session.player.play();
      }
    }
  }

  Future<void> removeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      _sessionOrder.remove(sessionId);
      await session.player.stop();
      session.dispose();
      notifyListeners();
      unawaited(_saveSessionState());
      unawaited(_saveSessionOrder());
    }
  }

  Future<void> setSessionLoopMode(String sessionId, SessionLoopMode mode) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.loopMode = mode;
    await session.player.setLoopMode(
        mode == SessionLoopMode.single ? LoopMode.one : LoopMode.off);
    notifyListeners();
    unawaited(_saveSessionState());
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
  }

  Future<void> clearAllSessions() async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      await removeSession(id);
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
    if (session.loopMode == SessionLoopMode.single) return; // LoopMode.one handles it

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

      case SessionLoopMode.random:
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

      case SessionLoopMode.folder:
        final scope = _library
            .where((t) => t.groupKey == currentTrack.groupKey)
            .toList()
          ..sort(getTrackComparator);
        if (scope.isEmpty) return currentTrack.path;
        final idx = scope.indexWhere((t) => t.path == currentTrack.path);
        if (idx < 0) return scope.first.path;
        final next = (idx + (forward ? 1 : -1) + scope.length) % scope.length;
        return scope[next].path;

      case SessionLoopMode.crossFolder:
        final all = [..._library]..sort(getTrackComparator);
        final idx = all.indexWhere((t) => t.path == currentTrack.path);
        if (idx < 0) return all.first.path;
        final next = (idx + (forward ? 1 : -1) + all.length) % all.length;
        return all[next].path;
    }
  }
}
