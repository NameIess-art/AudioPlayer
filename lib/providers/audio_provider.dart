import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

import '../services/playback_notification_handler.dart';
import '../services/subtitle_parser.dart';

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
        return 'Single loop';
      case SessionLoopMode.crossRandom:
        return 'Shuffle (cross-folder)';
      case SessionLoopMode.folderSequential:
        return 'Sequential (current folder)';
      case SessionLoopMode.crossSequential:
        return 'Sequential (cross-folder)';
      case SessionLoopMode.folderRandom:
        return 'Shuffle (current folder)';
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
  final int depth;
  final List<LibraryNode> children = [];
  List<MusicTrack>? _allTracksCache;
  MusicTrack? _firstTrackCache;
  int? _cachedTotalTrackCount;
  int? _cachedLeafFolderCount;

  FolderNode(this.name, this.path, {this.depth = 0});

  bool get isModuleNode {
    return depth == 0;
  }

  /// Recursively get all tracks inside this folder
  List<MusicTrack> get allTracks {
    final cached = _allTracksCache;
    if (cached != null) {
      return cached;
    }

    final list = <MusicTrack>[];
    for (final child in children) {
      if (child is TrackNode) {
        list.add(child.track);
      } else if (child is FolderNode) {
        list.addAll(child.allTracks);
      }
    }
    _allTracksCache = list;
    return list;
  }

  MusicTrack? get firstTrack {
    final cached = _firstTrackCache;
    if (cached != null) {
      return cached;
    }

    for (final child in children) {
      if (child is TrackNode) {
        _firstTrackCache = child.track;
        return child.track;
      }
      if (child is FolderNode) {
        final nested = child.firstTrack;
        if (nested != null) {
          _firstTrackCache = nested;
          return nested;
        }
      }
    }
    return null;
  }

  int get totalTrackCount => _cachedTotalTrackCount ?? allTracks.length;

  int get leafFolderCount {
    return _cachedLeafFolderCount ??
        children.whereType<FolderNode>().fold<int>(
          0,
          (total, folder) => total + folder.leafFolderCount,
        );
  }

  void cacheTreeMetrics({
    required int totalTrackCount,
    required int leafFolderCount,
    required MusicTrack? firstTrack,
  }) {
    _cachedTotalTrackCount = totalTrackCount;
    _cachedLeafFolderCount = leafFolderCount;
    _firstTrackCache = firstTrack;
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

class _LibraryTreeSnapshot {
  const _LibraryTreeSnapshot({
    required this.tree,
    required this.leafFolderCount,
  });

  final List<LibraryNode> tree;
  final int leafFolderCount;
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
const _kWatchedLibrariesKey = 'watched_libraries_v1';
const _kTimerSettingsKey = 'timer_settings_v1';
const _kTimerRuntimeKey = 'timer_runtime_v1';
const _kConverterSettingsKey = 'converter_settings_v1';
const _kPlaybackSettingsKey = 'playback_settings_v1';

class AudioProvider with ChangeNotifier {
  static const Set<String> _supportedImageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.gif',
  };
  static const Duration _notificationProgressRefreshInterval = Duration(
    milliseconds: 750,
  );
  static const Duration _multiSessionNotificationRefreshInterval = Duration(
    milliseconds: 1500,
  );
  static const MethodChannel _powerChannel = MethodChannel(
    'music_player/power',
  );
  static const MethodChannel _fileCacheChannel = MethodChannel(
    'music_player/file_cache',
  );
  static const MethodChannel _notificationsChannel = MethodChannel(
    'music_player/notifications',
  );
  final PlaybackNotificationHandler _notificationHandler;
  final List<MusicTrack> _library = [];
  final Map<String, MusicTrack> _libraryByPath = {};
  final Map<String, List<MusicTrack>> _tracksByGroup = {};
  List<MusicTrack> _sortedLibraryTracks = const <MusicTrack>[];
  final Map<String, PlaybackSession> _sessions = {};
  final Map<String, Future<SubtitleTrack?>> _subtitleTrackFutures = {};
  final Map<String, SubtitleTrack?> _subtitleTracks = {};
  final Map<String, String?> _notificationSubtitleTexts = {};
  final Map<String, String> _notificationSubtitleTrackPaths = {};
  final Map<String, Future<String?>> _coverPathFutures = {};
  final Map<String, String?> _resolvedCoverPaths = {};
  final Map<String, Future<String?>> _notificationCoverPathFutures = {};
  final Map<String, String?> _resolvedNotificationCoverPaths = {};
  String? _notificationFocusSessionId;
  String? _unifiedNotificationSyncKey;
  Timer? _notificationProgressRefreshTimer;
  String? _queuedNotificationRefreshSessionId;

  // Ordered list of groupKeys (for drag-reorder persistence)
  final List<String> _groupOrder = [];
  final Set<String> _groupOrderSet = <String>{};
  // Ordered list of sessionIds (for drag-reorder persistence, newest-first)
  final List<String> _sessionOrder = [];
  // Paths of folder roots selected by the user (watched for auto-rescan)
  final List<String> _watchedFolders = [];
  final List<String> _watchedLibraries = [];

  // Video conversion settings (configured from Settings tab).
  String _converterFormat = 'mp3';
  String _converterBitrate = '320k';
  bool _multiThreadPlaybackEnabled = false;

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
  static const String _androidNotificationGroupKey =
      'com.example.music_player.PLAYBACK_GROUP';
  static const String _androidGroupSummaryKey = 'android_group_summary';
  static const String _androidSummaryTitleKey = 'android_summary_title';
  static const String _androidSummaryTextKey = 'android_summary_text';
  static const String _androidSummaryLinesKey = 'android_summary_lines';

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
  bool _timerWaitingForPlayback = false;
  TimerMode _timerDraftMode = TimerMode.manual;
  Duration _timerDraftDuration = const Duration(minutes: 30);
  int _timerGeneration = 0;
  bool _keepCpuAwake = false;
  bool _keepAliveHasPlayback = false;
  bool _keepAliveHasTimer = false;
  bool _activeSessionsDirty = true;
  List<PlaybackSession> _activeSessionsCache = const <PlaybackSession>[];
  bool _libraryTreeDirty = true;
  List<LibraryNode> _cachedLibraryTree = const <LibraryNode>[];
  int _cachedLibraryLeafFolderCount = 0;
  Timer? _saveSessionStateTimer;
  Timer? _saveSessionOrderTimer;
  Future<void> _sessionPreparationQueue = Future<void>.value();
  Timer? _notificationActionRefreshTimer;

  // Tracks paused when the timer expired (for auto-resume)
  final List<String> _pausedByTimerPaths = [];

  // Auto-resume (clock-time alarm style)
  bool _autoResumeEnabled = false;
  int _autoResumeHour = 7;
  int _autoResumeMinute = 0;
  Timer? _autoResumeTimer;
  DateTime? _autoResumeAt;

  // Getters
  TimerMode? get timerMode => _timerMode;
  Duration? get timerDuration => _timerDuration;
  TimerMode get timerDraftMode => _timerDraftMode;
  Duration get timerDraftDuration => _timerDraftDuration;
  bool get timerActive => _timerActive;
  Duration? get timerRemaining => _timerRemaining;
  bool get autoResumeEnabled => _autoResumeEnabled;
  int get autoResumeHour => _autoResumeHour;
  int get autoResumeMinute => _autoResumeMinute;
  List<String> get pausedByTimerPaths => List.unmodifiable(_pausedByTimerPaths);
  String get converterFormat => _converterFormat;
  String get converterBitrate => _converterBitrate;
  bool get multiThreadPlaybackEnabled => _multiThreadPlaybackEnabled;

  List<MusicTrack> get library => List.unmodifiable(_library);
  int get libraryTrackCount => _library.length;
  List<String> get watchedFolders => List.unmodifiable(_watchedFolders);
  List<String> get watchedLibraries => List.unmodifiable(_watchedLibraries);
  int get watchedFolderCount => _watchedFolders.length;
  List<LibraryNode> get libraryTree {
    if (_libraryTreeDirty) {
      final snapshot = _buildLibraryTreeSnapshot();
      _cachedLibraryTree = snapshot.tree;
      _cachedLibraryLeafFolderCount = snapshot.leafFolderCount;
      _libraryTreeDirty = false;
    }
    return _cachedLibraryTree;
  }

  int get libraryLeafFolderCount {
    if (_libraryTreeDirty) {
      final _ = libraryTree;
    }
    return _cachedLibraryLeafFolderCount;
  }

  int get playingSessionCount =>
      _sessions.values.where((session) => session.state.playing).length;

  List<PlaybackSession> get activeSessions {
    if (_activeSessionsDirty) {
      final result = <PlaybackSession>[];
      for (final id in _sessionOrder) {
        final session = _sessions[id];
        if (session != null) {
          result.add(session);
        }
      }
      for (final session in _sessions.values) {
        if (!_sessionOrder.contains(session.id)) {
          result.add(session);
        }
      }
      _activeSessionsCache = List<PlaybackSession>.unmodifiable(result);
      _activeSessionsDirty = false;
    }
    return _activeSessionsCache;
  }

  bool get isScanning => _isScanning;

  AudioProvider({required PlaybackNotificationHandler notificationHandler})
    : _notificationHandler = notificationHandler {
    _bindNotificationHandler();
    _loadData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoResumeTimer?.cancel();
    _saveSessionStateTimer?.cancel();
    _saveSessionOrderTimer?.cancel();
    _notificationProgressRefreshTimer?.cancel();
    _notificationActionRefreshTimer?.cancel();
    unawaited(
      _setKeepCpuAwake(false, hasActivePlayback: false, hasActiveTimer: false),
    );
    unawaited(_deactivateAudioSession());
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    super.dispose();
  }

  void _markActiveSessionsDirty() {
    _activeSessionsDirty = true;
  }

  void _markLibraryStructureDirty() {
    _libraryTreeDirty = true;
  }

  void _rebuildLibraryIndexes() {
    final tracksByGroup = <String, List<MusicTrack>>{};
    _libraryByPath
      ..clear()
      ..addEntries(_library.map((track) => MapEntry(track.path, track)));
    for (final track in _library) {
      tracksByGroup
          .putIfAbsent(track.groupKey, () => <MusicTrack>[])
          .add(track);
    }
    for (final entry in tracksByGroup.entries) {
      entry.value.sort(getTrackComparator);
    }
    _tracksByGroup
      ..clear()
      ..addAll(
        tracksByGroup.map(
          (groupKey, tracks) =>
              MapEntry(groupKey, List<MusicTrack>.unmodifiable(tracks)),
        ),
      );
    _sortedLibraryTracks = List<MusicTrack>.unmodifiable(
      _library.toList()..sort(getTrackComparator),
    );
    _groupOrderSet
      ..clear()
      ..addAll(_groupOrder);
    _markLibraryStructureDirty();
  }

  void _syncGroupOrderFromLibrary() {
    final activeGroupKeys = _library.map((track) => track.groupKey).toSet();
    _groupOrder.removeWhere((groupKey) => !activeGroupKeys.contains(groupKey));
    for (final groupKey in activeGroupKeys) {
      if (_groupOrderSet.add(groupKey)) {
        _groupOrder.add(groupKey);
      }
    }
    _groupOrderSet
      ..clear()
      ..addAll(_groupOrder);
  }

  void _bindNotificationHandler() {
    _notificationHandler.bindCallbacks(
      onPlay: playPrimarySessionFromNotification,
      onPlayFromMediaId: playNotificationSessionById,
      onPause: pausePrimarySessionFromNotification,
      onStop: stopPrimarySessionFromNotification,
      onSkipToNext: skipPrimarySessionToNextFromNotification,
      onSkipToPrevious: skipPrimarySessionToPreviousFromNotification,
      onSeek: seekPrimarySessionFromNotification,
      onTogglePlayPause: togglePrimarySessionPlayPauseFromNotification,
      onToggleSessionPlayback: toggleSessionPlaybackFromNotification,
      onSkipToPreviousSession: skipNotificationSessionToPreviousById,
      onSkipToNextSession: skipNotificationSessionToNextById,
    );
    _syncNotificationState();
  }

  Future<void> playPrimarySessionFromNotification() async {
    final session = _resolveNotificationSession();
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    await _resumeNotificationSession(session);
    _scheduleNotificationActionRefresh();
  }

  Future<void> playNotificationSessionById(String mediaId) async {
    final session = _resolveNotificationSession(mediaId);
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    await _resumeNotificationSession(session);
    _scheduleNotificationActionRefresh();
  }

  Future<void> pausePrimarySessionFromNotification() async {
    final session = _notificationActionSession;
    if (session == null || !session.state.playing) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await session.player.pause();
    _scheduleNotificationActionRefresh();
  }

  Future<void> togglePrimarySessionPlayPauseFromNotification() async {
    final session = _resolveNotificationSession();
    if (session == null || session.isLoading) {
      _scheduleNotificationActionRefresh();
      return;
    }
    if (session.state.playing) {
      await session.player.pause();
      _scheduleNotificationActionRefresh();
      return;
    }
    await _resumeNotificationSession(session);
    _scheduleNotificationActionRefresh();
  }

  Future<void> stopPrimarySessionFromNotification() async {
    final session = _notificationActionSession;
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await session.player.pause();
    _scheduleNotificationActionRefresh();
  }

  Future<void> skipPrimarySessionToNextFromNotification() async {
    final session = _notificationActionSession;
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await seekSessionToNext(session.id);
    _scheduleNotificationActionRefresh();
  }

  Future<void> skipPrimarySessionToPreviousFromNotification() async {
    final session = _notificationActionSession;
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await seekSessionToPrev(session.id);
    _scheduleNotificationActionRefresh();
  }

  Future<void> toggleSessionPlaybackFromNotification(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await toggleSessionPlayPause(session.id);
    _scheduleNotificationActionRefresh();
  }

  Future<void> skipNotificationSessionToPreviousById(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await seekSessionToPrev(session.id);
    _scheduleNotificationActionRefresh();
  }

  Future<void> skipNotificationSessionToNextById(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await seekSessionToNext(session.id);
    _scheduleNotificationActionRefresh();
  }

  Future<void> seekPrimarySessionFromNotification(Duration position) async {
    final session = _notificationActionSession;
    if (session == null) {
      _scheduleNotificationActionRefresh();
      return;
    }
    _notificationFocusSessionId = session.id;
    await seekSession(session.id, position);
    _scheduleNotificationActionRefresh();
  }

  List<PlaybackSession> get _singleThreadNotificationSessions {
    final sessions = activeSessions;
    if (sessions.isEmpty) {
      return const <PlaybackSession>[];
    }
    final visibleSessions = sessions
        .where((session) => session.state.playing || session.isLoading)
        .toList(growable: false);
    if (visibleSessions.isNotEmpty) {
      return visibleSessions;
    }
    final retainedSession = _focusedSessionFrom(sessions);
    if (retainedSession == null) {
      return const <PlaybackSession>[];
    }
    return <PlaybackSession>[retainedSession];
  }

  List<PlaybackSession> get _notificationQueueSessions {
    return _multiThreadPlaybackEnabled
        ? activeSessions
        : _singleThreadNotificationSessions;
  }

  PlaybackSession? _focusedSessionFrom(Iterable<PlaybackSession> sessions) {
    final focusedId = _notificationFocusSessionId;
    if (focusedId != null) {
      for (final session in sessions) {
        if (session.id == focusedId) return session;
      }
    }
    final fallback = sessions.isNotEmpty ? sessions.first : null;
    _notificationFocusSessionId = fallback?.id;
    return fallback;
  }

  PlaybackSession? get _notificationFocusedSession {
    return _focusedSessionFrom(_notificationQueueSessions);
  }

  PlaybackSession? get _notificationActionSession {
    final focused = _focusedSessionFrom(activeSessions);
    if (focused != null) {
      return focused;
    }
    return _focusedSessionFrom(_notificationQueueSessions);
  }

  PlaybackSession? _resolveNotificationSession([String? sessionId]) {
    if (sessionId != null) {
      final matchedSession = _sessions[sessionId];
      if (matchedSession != null) {
        _notificationFocusSessionId = matchedSession.id;
        return matchedSession;
      }
    }
    final focusedSession = _notificationActionSession;
    if (focusedSession != null) {
      _notificationFocusSessionId = focusedSession.id;
    }
    return focusedSession;
  }

  void _scheduleNotificationActionRefresh() {
    _syncNotificationState();
    notifyListeners();
    _notificationActionRefreshTimer?.cancel();
    _notificationActionRefreshTimer = Timer(
      const Duration(milliseconds: 220),
      () {
        _notificationActionRefreshTimer = null;
        _syncNotificationState();
        notifyListeners();
      },
    );
  }

  Future<void> _resumeNotificationSession(PlaybackSession session) async {
    if (session.isLoading || session.state.playing) return;
    _notificationFocusSessionId = session.id;
    if (session.state.processingState == ProcessingState.completed) {
      await _prepareAndPlay(session, nextPath: session.currentTrackPath);
      return;
    }
    await _startSessionPlayback(session, shouldStartTriggerCountdown: true);
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  PlaybackNotificationSnapshot? _buildNotificationSnapshot() {
    final sessions = _notificationQueueSessions;
    if (sessions.isEmpty) {
      _notificationFocusSessionId = null;
      return null;
    }

    if (sessions.length > 1) {
      final hasPlayingSession = sessions.any(
        (session) => session.state.playing,
      );
      final focusedSession = _notificationFocusedSession;
      if (focusedSession == null) return null;
      _notificationFocusSessionId = focusedSession.id;
      final mediaItem = _summaryMediaItemForSessions(sessions);

      return PlaybackNotificationSnapshot(
        queue: <MediaItem>[mediaItem],
        queueIndex: 0,
        mediaItem: mediaItem,
        playing: hasPlayingSession,
        processingState: _mapProcessingState(
          focusedSession.state.processingState,
        ),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        hasPrevious: false,
        hasNext: false,
        showTransportControls: false,
      );
    }

    final session = _notificationFocusedSession;
    if (session == null) return null;

    _notificationFocusSessionId = session.id;
    final mediaItem = _mediaItemForSession(session);
    final previousPath = _nextPathFor(session, forward: false);
    final nextPath = _nextPathFor(session, forward: true);

    return PlaybackNotificationSnapshot(
      queue: <MediaItem>[mediaItem],
      queueIndex: 0,
      mediaItem: mediaItem,
      playing: session.state.playing,
      processingState: _mapProcessingState(session.state.processingState),
      updatePosition: session.player.position,
      bufferedPosition: session.player.bufferedPosition,
      speed: session.player.speed,
      hasPrevious: previousPath != null,
      hasNext: nextPath != null,
    );
  }

  String _notificationTitleForSession(PlaybackSession session) {
    final track = trackByPath(session.currentTrackPath);
    return track?.displayName ??
        path.basenameWithoutExtension(session.currentTrackPath);
  }

  List<String> _notificationOverviewTitles(Iterable<PlaybackSession> sessions) {
    final uniqueTitles = <String>{};
    for (final session in sessions) {
      final title = _notificationTitleForSession(session);
      if (title.isNotEmpty) {
        uniqueTitles.add(title);
      }
    }
    return uniqueTitles.toList(growable: false);
  }

  String _notificationSummaryText(List<PlaybackSession> sessions) {
    final titles = _notificationOverviewTitles(sessions);
    if (titles.isEmpty) {
      return '${sessions.length} active sessions';
    }
    if (titles.length == 1) {
      return titles.first;
    }
    if (titles.length == 2) {
      return '${titles[0]} / ${titles[1]}';
    }
    return '${titles.first} +${titles.length - 1}';
  }

  MediaItem _summaryMediaItemForSessions(List<PlaybackSession> sessions) {
    final titles = _notificationOverviewTitles(sessions);
    return MediaItem(
      id: 'notification_summary',
      title: 'AudioPlayer',
      album: 'AudioPlayer',
      artist: _notificationSummaryText(sessions),
      displayTitle: 'AudioPlayer',
      displaySubtitle: _notificationSummaryText(sessions),
      displayDescription: null,
      extras: <String, dynamic>{
        _androidGroupSummaryKey: 1,
        'android_group_key': _androidNotificationGroupKey,
        _androidSummaryTitleKey: 'AudioPlayer',
        _androidSummaryTextKey: _notificationSummaryText(sessions),
        _androidSummaryLinesKey: titles.join('\n'),
      },
    );
  }

  MediaItem _mediaItemForSession(PlaybackSession session) {
    final track = trackByPath(session.currentTrackPath);
    final displayName = _notificationTitleForSession(session);
    final groupTitle = track?.groupTitle ?? 'Audio';
    final notificationSubtitle = _notificationSubtitleForSession(session);
    return MediaItem(
      id: session.id,
      title: displayName,
      album: groupTitle,
      artist: notificationSubtitle ?? groupTitle,
      artUri: _notificationArtUriForTrack(track),
      duration: session.player.duration,
      displayTitle: displayName,
      displaySubtitle: notificationSubtitle ?? groupTitle,
      displayDescription: notificationSubtitle ?? groupTitle,
      extras: const <String, dynamic>{},
    );
  }

  Uri? _notificationArtUriForTrack(MusicTrack? track) {
    final coverSearchKey = _notificationCoverSearchKey(track);
    if (coverSearchKey == null) {
      return null;
    }
    final coverPath = _resolvedNotificationCoverPaths[coverSearchKey];
    if (!_resolvedNotificationCoverPaths.containsKey(coverSearchKey)) {
      unawaited(_resolveNotificationCoverPathForTrack(track));
      return null;
    }
    if (coverPath == null || coverPath.isEmpty) return null;
    return Uri.file(coverPath);
  }

  String? coverPathForTrack(MusicTrack? track) {
    final coverSearchKey = _notificationCoverSearchKey(track);
    if (coverSearchKey == null) {
      return null;
    }
    return _resolvedNotificationCoverPaths[coverSearchKey];
  }

  Future<String?> coverPathFutureForTrack(MusicTrack? track) {
    return _resolveNotificationCoverPathForTrack(track);
  }

  Future<String?> coverPathFutureForFolder(String folderPath) {
    if (folderPath.startsWith('content://')) {
      return Future<String?>.value(null);
    }
    return _resolveCoverPathForFolder(folderPath);
  }

  String? _notificationCoverSearchKey(MusicTrack? track) {
    if (track == null) {
      return null;
    }
    if (track.path.startsWith('content://')) {
      final groupKey = track.groupKey.trim();
      if (groupKey.isNotEmpty) {
        return 'content:$groupKey';
      }
      return 'content:${track.path}';
    }
    final directoryPath = path.dirname(track.path);
    if (directoryPath.isEmpty || directoryPath == '.') {
      return null;
    }
    return path.normalize(directoryPath);
  }

  Future<String?> _resolveNotificationCoverPathForTrack(MusicTrack? track) {
    final coverSearchKey = _notificationCoverSearchKey(track);
    if (coverSearchKey == null) {
      return Future<String?>.value(null);
    }
    if (_resolvedNotificationCoverPaths.containsKey(coverSearchKey)) {
      return Future<String?>.value(
        _resolvedNotificationCoverPaths[coverSearchKey],
      );
    }

    return _notificationCoverPathFutures.putIfAbsent(coverSearchKey, () async {
      String? coverPath;
      if (track != null) {
        if (track.path.startsWith('content://')) {
          coverPath = await _resolveContentCoverPathForTrack(track);
        } else {
          for (final candidateDirectory
              in _notificationCoverCandidateDirectories(track)) {
            coverPath = await _findNotificationCoverPath(candidateDirectory);
            if (coverPath != null) {
              break;
            }
          }
        }
      }

      _notificationCoverPathFutures.remove(coverSearchKey);
      final previous = _resolvedNotificationCoverPaths[coverSearchKey];
      _resolvedNotificationCoverPaths[coverSearchKey] = coverPath;

      if (previous != coverPath) {
        final focusedTrack = trackByPath(
          _notificationFocusedSession?.currentTrackPath ?? '',
        );
        if (_notificationCoverSearchKey(focusedTrack) == coverSearchKey) {
          _syncNotificationState();
          notifyListeners();
        }
      }

      return coverPath;
    });
  }

  Future<String?> _resolveContentCoverPathForTrack(MusicTrack track) async {
    try {
      return await _fileCacheChannel.invokeMethod<String>(
        'resolveTrackCover',
        <String, dynamic>{'path': track.path, 'groupKey': track.groupKey},
      );
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('AudioProvider._resolveContentCoverPathForTrack error: $e');
      return null;
    }
  }

  List<String> _notificationCoverCandidateDirectories(MusicTrack track) {
    final coverSearchKey = _notificationCoverSearchKey(track);
    if (coverSearchKey == null) {
      return const <String>[];
    }

    final directories = <String>[coverSearchKey];
    for (final watchedFolder in _watchedFolders) {
      if (watchedFolder.startsWith('content://')) {
        continue;
      }
      final normalizedRoot = path.normalize(watchedFolder);
      if (!_isPathWithinOrEqual(coverSearchKey, normalizedRoot)) {
        continue;
      }

      var current = coverSearchKey;
      while (!path.equals(current, normalizedRoot)) {
        final parent = path.dirname(current);
        if (parent == current || directories.contains(parent)) {
          break;
        }
        directories.add(parent);
        current = parent;
      }
    }
    return directories;
  }

  bool _isPathWithinOrEqual(String pathValue, String rootPath) {
    return path.equals(pathValue, rootPath) ||
        path.isWithin(rootPath, pathValue);
  }

  Future<String?> _resolveCoverPathForFolder(String folderPath) {
    if (_resolvedCoverPaths.containsKey(folderPath)) {
      return Future<String?>.value(_resolvedCoverPaths[folderPath]);
    }

    return _coverPathFutures.putIfAbsent(folderPath, () async {
      final coverPath = await _findNotificationCoverPath(folderPath);
      _coverPathFutures.remove(folderPath);

      final previous = _resolvedCoverPaths[folderPath];
      _resolvedCoverPaths[folderPath] = coverPath;

      if (previous != coverPath) {
        notifyListeners();
      }

      return coverPath;
    });
  }

  Future<String?> _findNotificationCoverPath(String folderPath) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) return null;

    final images = <String>[];
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final extension = path.extension(entity.path).toLowerCase();
        if (_supportedImageExtensions.contains(extension)) {
          images.add(entity.path);
        }
      }
    } catch (_) {
      return null;
    }

    if (images.isEmpty) return null;
    images.sort((a, b) {
      final nameResult = path
          .basename(a)
          .toLowerCase()
          .compareTo(path.basename(b).toLowerCase());
      if (nameResult != 0) return nameResult;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return images.first;
  }

  void _clearResolvedCoverPaths() {
    _coverPathFutures.clear();
    _resolvedCoverPaths.clear();
    _notificationCoverPathFutures.clear();
    _resolvedNotificationCoverPaths.clear();
  }

  void _syncNotificationState() {
    _notificationHandler.updateSnapshot(_buildNotificationSnapshot());
    unawaited(_syncUnifiedPlaybackNotifications());
  }

  void _scheduleFocusedNotificationRefresh(
    String sessionId, {
    bool immediate = false,
  }) {
    if (_notificationFocusedSession?.id != sessionId) {
      return;
    }

    if (_shouldUseUnifiedPlaybackNotifications) {
      immediate = false;
    }

    if (immediate) {
      _notificationProgressRefreshTimer?.cancel();
      _notificationProgressRefreshTimer = null;
      _queuedNotificationRefreshSessionId = null;
      _syncNotificationState();
      return;
    }

    _queuedNotificationRefreshSessionId = sessionId;
    if (_notificationProgressRefreshTimer != null) {
      return;
    }

    _notificationProgressRefreshTimer = Timer(_notificationRefreshInterval, () {
      _notificationProgressRefreshTimer = null;
      final queuedSessionId = _queuedNotificationRefreshSessionId;
      _queuedNotificationRefreshSessionId = null;
      if (queuedSessionId == null ||
          _notificationFocusedSession?.id != queuedSessionId) {
        return;
      }
      _syncNotificationState();
    });
  }

  Future<void> _syncUnifiedPlaybackNotifications() async {
    final sessionsToShow = _shouldUseUnifiedPlaybackNotifications
        ? activeSessions
        : const <PlaybackSession>[];
    final showUnifiedSummary = sessionsToShow.isNotEmpty;
    final summaryText = showUnifiedSummary
        ? _notificationSummaryText(sessionsToShow)
        : null;
    final summaryLines = showUnifiedSummary
        ? _notificationOverviewTitles(sessionsToShow)
        : const <String>[];

    final payload = sessionsToShow
        .map((session) {
          final title = _notificationTitleForSession(session);
          final subtitle = _notificationSubtitleForSession(session);
          final track = trackByPath(session.currentTrackPath);
          final artPath = coverPathForTrack(track);
          return <String, dynamic>{
            'id': session.id,
            'title': title,
            if (subtitle != null && subtitle.isNotEmpty) 'subtitle': subtitle,
            if (artPath != null && artPath.isNotEmpty) 'artPath': artPath,
            'playing': session.state.playing,
            'hasPrevious': _nextPathFor(session, forward: false) != null,
            'hasNext': _nextPathFor(session, forward: true) != null,
          };
        })
        .toList(growable: false);

    final nextSyncKey = json.encode(<String, dynamic>{
      'items': payload,
      'showSummary': showUnifiedSummary,
      'summaryText': summaryText,
      'summaryLines': summaryLines,
    });
    if (_unifiedNotificationSyncKey == nextSyncKey) {
      return;
    }

    try {
      if (payload.isEmpty) {
        await _notificationsChannel.invokeMethod<void>(
          'clearUnifiedPlaybackNotifications',
        );
      } else {
        await _notificationsChannel.invokeMethod<void>(
          'syncUnifiedPlaybackNotifications',
          <String, dynamic>{
            'items': payload,
            'showSummary': showUnifiedSummary,
            'summaryText': summaryText,
            'summaryLines': summaryLines,
          },
        );
      }
      _unifiedNotificationSyncKey = nextSyncKey;
    } on MissingPluginException {
      debugPrint(
        'AudioProvider._syncUnifiedPlaybackNotifications: notifications '
        'channel not ready yet; will retry on next sync.',
      );
    } catch (e) {
      debugPrint('AudioProvider._syncUnifiedPlaybackNotifications error: $e');
    }
  }

  void refreshNotificationState() {
    _syncNotificationState();
    notifyListeners();
  }

  Future<void> selectNotificationSessionFromQueue(int index) async {
    final sessions = _notificationQueueSessions;
    if (index < 0 || index >= sessions.length) return;
    _notificationFocusSessionId = sessions[index].id;
    _syncNotificationState();
    notifyListeners();
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
      _rebuildLibraryIndexes();
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
      _groupOrderSet
        ..clear()
        ..addAll(list);
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
      _markActiveSessionsDirty();
    } catch (_) {}
  }

  Future<void> _saveSessionOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSessionOrderKey, json.encode(_sessionOrder));
    } catch (_) {}
  }

  void _scheduleSaveSessionOrder({
    Duration delay = const Duration(milliseconds: 180),
  }) {
    _saveSessionOrderTimer?.cancel();
    _saveSessionOrderTimer = Timer(delay, () {
      unawaited(_saveSessionOrder());
    });
  }

  // ---------------------------------------------------------------------------
  // Session persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadData() async {
    await _loadLibrary();
    await _loadGroupOrder();
    _syncGroupOrderFromLibrary();
    _markLibraryStructureDirty();
    await _loadSessionOrder();
    await _loadWatchedFolders();
    await _loadWatchedLibraries();
    await _loadPlaybackSettings();
    await _loadConverterSettings();
    await _loadTimerSettings();
    await _loadSessions();
    if (!_multiThreadPlaybackEnabled) {
      await _enforceSingleThreadPlayback();
    }
    await _loadTimerRuntime();
    _syncKeepCpuAwake();
    notifyListeners();
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
        final restoredSessionId = item['id'] as String? ?? _nextSessionId();
        final session = PlaybackSession(
          id: restoredSessionId,
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
        _markActiveSessionsDirty();
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
          _ensureSubtitleTrackLoaded(track.path);
          _refreshNotificationSubtitleForSession(
            session,
            syncNotification: false,
          );
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
      _markActiveSessionsDirty();
      _notificationFocusSessionId = _sessionOrder.isNotEmpty
          ? _sessionOrder.first
          : restoredIds.isNotEmpty
          ? restoredIds.first
          : null;

      _syncNotificationState();
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
                'id': s.id,
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

  void _scheduleSaveSessionState({
    Duration delay = const Duration(milliseconds: 220),
  }) {
    _saveSessionStateTimer?.cancel();
    _saveSessionStateTimer = Timer(delay, () {
      unawaited(_saveSessionState());
    });
  }

  void _scheduleSessionPersistence() {
    _scheduleSaveSessionState();
    _scheduleSaveSessionOrder();
  }

  Future<void> _loadPlaybackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPlaybackSettingsKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw) as Map<String, dynamic>;
      _multiThreadPlaybackEnabled =
          map['multiThreadPlaybackEnabled'] as bool? ?? false;
    } catch (_) {}
  }

  Future<void> _savePlaybackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode({
        'multiThreadPlaybackEnabled': _multiThreadPlaybackEnabled,
      });
      await prefs.setString(_kPlaybackSettingsKey, encoded);
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

  Future<void> _loadWatchedLibraries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kWatchedLibrariesKey);
      if (raw == null || raw.isEmpty) return;
      final list = (json.decode(raw) as List<dynamic>).cast<String>();
      _watchedLibraries.clear();
      _watchedLibraries.addAll(list);
    } catch (_) {}
  }

  Future<void> _saveWatchedLibraries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kWatchedLibrariesKey,
        json.encode(_watchedLibraries),
      );
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
      final draftModeIndex = map['timerDraftMode'] as int?;
      final draftDurationMs = map['timerDraftDurationMs'] as int?;
      if (draftModeIndex != null &&
          draftModeIndex >= 0 &&
          draftModeIndex < TimerMode.values.length) {
        _timerDraftMode = TimerMode.values[draftModeIndex];
      }
      if (draftDurationMs != null && draftDurationMs > 0) {
        _timerDraftDuration = Duration(milliseconds: draftDurationMs);
      }
    } catch (_) {}
  }

  Future<void> _saveTimerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode({
        'autoResumeEnabled': _autoResumeEnabled,
        'autoResumeHour': _autoResumeHour,
        'autoResumeMinute': _autoResumeMinute,
        'timerDraftMode': _timerDraftMode.index,
        'timerDraftDurationMs': _timerDraftDuration.inMilliseconds,
      });
      await prefs.setString(_kTimerSettingsKey, encoded);
    } catch (_) {}
  }

  void setTimerDraft(TimerMode mode, Duration duration) {
    final normalizedDuration = duration > Duration.zero
        ? duration
        : const Duration(minutes: 30);
    if (_timerDraftMode == mode && _timerDraftDuration == normalizedDuration) {
      return;
    }
    _timerDraftMode = mode;
    _timerDraftDuration = normalizedDuration;
    notifyListeners();
    unawaited(_saveTimerSettings());
  }

  Future<void> _loadTimerRuntime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTimerRuntimeKey);
      if (raw == null || raw.isEmpty) return;

      final map = json.decode(raw) as Map<String, dynamic>;
      final now = DateTime.now();

      final durationMs = map['timerDurationMs'] as int?;
      final timerModeIndex = map['timerMode'] as int?;
      final waitingForPlayback =
          map['timerWaitingForPlayback'] as bool? ?? false;
      final timerEndsAtMs = map['timerEndsAtMs'] as int?;
      final autoResumeAtMs = map['autoResumeAtMs'] as int?;
      final pausedPaths =
          (map['pausedByTimerPaths'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();

      _pausedByTimerPaths
        ..clear()
        ..addAll(pausedPaths);
      _autoResumeAt = autoResumeAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(autoResumeAtMs);

      if (timerModeIndex != null &&
          timerModeIndex >= 0 &&
          timerModeIndex < TimerMode.values.length) {
        _timerMode = TimerMode.values[timerModeIndex];
      }
      if (durationMs != null && durationMs > 0) {
        _timerDuration = Duration(milliseconds: durationMs);
      }

      if (_timerDuration != null && waitingForPlayback) {
        _timerRemaining = _timerDuration;
        _timerWaitingForPlayback = true;
        _timerActive = false;
      }

      if (timerEndsAtMs != null && _timerDuration != null) {
        final restoredEndsAt = DateTime.fromMillisecondsSinceEpoch(
          timerEndsAtMs,
        );
        if (restoredEndsAt.isAfter(now)) {
          final generation = ++_timerGeneration;
          _timerEndsAt = restoredEndsAt;
          _timerActive = true;
          _timerWaitingForPlayback = false;
          final remaining = restoredEndsAt.difference(now);
          _timerRemaining = Duration(
            seconds: (remaining.inMilliseconds + 999) ~/ 1000,
          );
          _countdownTimer?.cancel();
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (generation != _timerGeneration) return;
            _tickCountdown();
          });
        } else {
          _timerEndsAt = null;
          _timerActive = false;
          _timerRemaining = Duration.zero;
        }
      }

      if (_autoResumeAt != null) {
        if (_autoResumeAt!.isAfter(now) && _pausedByTimerPaths.isNotEmpty) {
          _scheduleAutoResumeTimer(_autoResumeAt!);
        } else if (_pausedByTimerPaths.isNotEmpty) {
          await _resumeTimerPausedSessions();
        } else {
          _autoResumeAt = null;
        }
      }

      _syncNotificationState();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveTimerRuntime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRuntime =
          _timerMode != null ||
          _timerDuration != null ||
          _timerActive ||
          _timerWaitingForPlayback ||
          _autoResumeAt != null ||
          _pausedByTimerPaths.isNotEmpty;
      if (!hasRuntime) {
        await prefs.remove(_kTimerRuntimeKey);
        return;
      }

      final encoded = json.encode({
        'timerMode': _timerMode?.index,
        'timerDurationMs': _timerDuration?.inMilliseconds,
        'timerWaitingForPlayback': _timerWaitingForPlayback,
        'timerEndsAtMs': _timerEndsAt?.millisecondsSinceEpoch,
        'autoResumeAtMs': _autoResumeAt?.millisecondsSinceEpoch,
        'pausedByTimerPaths': _pausedByTimerPaths,
      });
      await prefs.setString(_kTimerRuntimeKey, encoded);
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

  Future<void> setMultiThreadPlaybackEnabled(bool enabled) async {
    if (_multiThreadPlaybackEnabled == enabled) return;
    _multiThreadPlaybackEnabled = enabled;
    if (!enabled) {
      await _resetSessionsForSingleThreadMode();
    }
    notifyListeners();
    unawaited(_savePlaybackSettings());
  }

  /// Register [folderPath] as a watched folder (idempotent).
  void addWatchedFolder(String folderPath, {bool notify = true}) {
    if (!_watchedFolders.contains(folderPath)) {
      _watchedFolders.add(folderPath);
      _clearResolvedCoverPaths();
      _markLibraryStructureDirty();
      unawaited(_saveWatchedFolders());
      if (notify) {
        notifyListeners();
      }
    }
  }

  void addWatchedLibrary(String folderPath, {bool notify = true}) {
    if (!_watchedLibraries.contains(folderPath)) {
      _watchedLibraries.add(folderPath);
      unawaited(_saveWatchedLibraries());
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// Stop watching [folderPath].
  void removeWatchedFolder(String folderPath, {bool notify = true}) {
    if (_watchedFolders.remove(folderPath)) {
      _clearResolvedCoverPaths();
      _markLibraryStructureDirty();
      unawaited(_saveWatchedFolders());
      if (notify) {
        notifyListeners();
      }
    }
  }

  void removeWatchedLibrary(String folderPath, {bool notify = true}) {
    if (_watchedLibraries.remove(folderPath)) {
      unawaited(_saveWatchedLibraries());
      if (notify) {
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Library management
  // ---------------------------------------------------------------------------

  void setScanning(bool scanning) {
    if (_isScanning == scanning) return;
    _isScanning = scanning;
    notifyListeners();
  }

  void addTracks(
    List<MusicTrack> newTracks, {
    bool notify = true,
    bool persist = true,
  }) {
    if (newTracks.isEmpty) return;

    final toAdd = <MusicTrack>[];
    var didChangeGroupOrder = false;
    for (final track in newTracks) {
      if (_libraryByPath.containsKey(track.path)) {
        continue;
      }
      _library.add(track);
      _libraryByPath[track.path] = track;
      toAdd.add(track);
      if (_groupOrderSet.add(track.groupKey)) {
        _groupOrder.add(track.groupKey);
        didChangeGroupOrder = true;
      }
    }

    if (toAdd.isNotEmpty) {
      _clearResolvedCoverPaths();
      _rebuildLibraryIndexes();
      if (notify) {
        notifyListeners();
      }
      if (persist) {
        _saveLibrary();
        if (didChangeGroupOrder) {
          _saveGroupOrder();
        }
      }
    }
  }

  Future<void> removeTrackFromLibrary(String trackPath) async {
    final removedTrack = _libraryByPath.remove(trackPath);
    if (removedTrack == null) return;

    _library.removeWhere((track) => track.path == trackPath);
    _clearResolvedCoverPaths();

    final sessionsToRemove = _sessions.values
        .where((s) => s.currentTrackPath == trackPath)
        .map((s) => s.id)
        .toList();
    if (sessionsToRemove.isNotEmpty) {
      await _removeSessions(sessionsToRemove, persist: false, notify: false);
    }

    if (!_library.any((track) => track.groupKey == removedTrack.groupKey)) {
      _groupOrder.remove(removedTrack.groupKey);
      _groupOrderSet.remove(removedTrack.groupKey);
    }

    _rebuildLibraryIndexes();
    notifyListeners();
    _saveLibrary();
    _saveGroupOrder();
  }

  /// Remove an entire folder (node) from the library, including all its tracks
  /// and any active sessions playing those tracks.
  Future<void> removeFolderFromLibrary(String folderPath) async {
    _clearResolvedCoverPaths();
    final trackPaths = _library
        .where((track) => track.path.startsWith(folderPath))
        .map((track) => track.path)
        .toSet();
    if (trackPaths.isEmpty && !_watchedFolders.contains(folderPath)) {
      return;
    }

    final sessionsToRemove = _sessions.values
        .where((s) => trackPaths.contains(s.currentTrackPath))
        .map((s) => s.id)
        .toList();
    if (sessionsToRemove.isNotEmpty) {
      await _removeSessions(sessionsToRemove, persist: false, notify: false);
    }

    _library.removeWhere((track) => track.path.startsWith(folderPath));
    for (final trackPath in trackPaths) {
      _libraryByPath.remove(trackPath);
    }
    _groupOrder.removeWhere((key) => key.startsWith(folderPath));
    _groupOrderSet
      ..clear()
      ..addAll(_groupOrder);

    if (_watchedFolders.contains(folderPath)) {
      _watchedFolders.remove(folderPath);
      unawaited(_saveWatchedFolders());
    }

    _rebuildLibraryIndexes();
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

  List<LibraryNode> buildLibraryTree() => libraryTree;

  _LibraryTreeSnapshot _buildLibraryTreeSnapshot() {
    final rootNodes = <String, FolderNode>{};
    final folderIndexByPath = <String, Map<String, FolderNode>>{};
    final singleFiles = <TrackNode>[];
    final watchedRoots = _watchedFolders.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));

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
      for (final root in watchedRoots) {
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
        rootNodes[matchedRoot] = FolderNode(rootName, matchedRoot, depth: 0);
        folderIndexByPath[matchedRoot] = <String, FolderNode>{};
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

          final childFolders = folderIndexByPath.putIfAbsent(
            currentNode.path,
            () => <String, FolderNode>{},
          );
          final existingFolder = childFolders[part];
          if (existingFolder == null) {
            final newFolder = FolderNode(
              part,
              currentPath,
              depth: currentNode.depth + 1,
            );
            currentNode.children.add(newFolder);
            childFolders[part] = newFolder;
            folderIndexByPath[currentPath] = <String, FolderNode>{};
            currentNode = newFolder;
          } else {
            currentNode = existingFolder;
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
    var leafFolderCount = 0;

    final roots = rootNodes.values.toList();
    for (final root in roots) {
      sortFolder(root);
      _cacheFolderTreeMetrics(root);
      leafFolderCount += root.leafFolderCount;
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

    return _LibraryTreeSnapshot(
      tree: List<LibraryNode>.unmodifiable(topLevel),
      leafFolderCount: leafFolderCount,
    );
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
        r'[\\u00C0-\\u00FF]{2,}|[\\u4E00-\\u9FFF][\\u0080-\\u00FF]';
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

  void _cacheFolderTreeMetrics(FolderNode folder) {
    var totalTrackCount = 0;
    var childLeafFolderCount = 0;
    var hasChildFolder = false;
    MusicTrack? firstTrack;

    for (final child in folder.children) {
      if (child is TrackNode) {
        totalTrackCount++;
        firstTrack ??= child.track;
        continue;
      }
      if (child is FolderNode) {
        hasChildFolder = true;
        _cacheFolderTreeMetrics(child);
        totalTrackCount += child.totalTrackCount;
        childLeafFolderCount += child.leafFolderCount;
        firstTrack ??= child.firstTrack;
      }
    }

    folder.cacheTreeMetrics(
      totalTrackCount: totalTrackCount,
      leafFolderCount: hasChildFolder ? childLeafFolderCount : 1,
      firstTrack: firstTrack,
    );
  }

  MusicTrack? trackByPath(String trackPath) => _libraryByPath[trackPath];

  PlaybackSession? sessionById(String sessionId) => _sessions[sessionId];
  String? sessionTrackPath(String sessionId) =>
      _sessions[sessionId]?.currentTrackPath;
  bool isTrackActive(String trackPath) =>
      _sessions.values.any((session) => session.currentTrackPath == trackPath);

  Future<SubtitleTrack?> subtitleTrackForPath(String trackPath) {
    return _subtitleTrackFutures.putIfAbsent(trackPath, () async {
      final subtitleTrack = await loadSubtitleTrackForAudio(trackPath);
      _subtitleTracks[trackPath] = subtitleTrack;

      var shouldRefreshNotification = false;
      for (final session in _sessions.values) {
        if (session.currentTrackPath != trackPath) continue;
        final changed = _refreshNotificationSubtitleForSession(
          session,
          syncNotification: false,
        );
        if (changed && _notificationFocusedSession?.id == session.id) {
          shouldRefreshNotification = true;
        }
      }

      if (shouldRefreshNotification) {
        _syncNotificationState();
        notifyListeners();
      }
      return subtitleTrack;
    });
  }

  String? subtitleTextForTrackAt(
    String trackPath,
    Duration position, {
    SubtitleTrack? subtitleTrack,
  }) {
    final resolvedTrack = subtitleTrack;
    final cue = resolvedTrack?.cueAt(position);
    if (cue == null) return null;
    final text = cue.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _notificationSubtitleForSession(PlaybackSession session) {
    _ensureSubtitleTrackLoaded(session.currentTrackPath);
    if (_notificationSubtitleTrackPaths[session.id] !=
            session.currentTrackPath ||
        !_notificationSubtitleTexts.containsKey(session.id)) {
      _refreshNotificationSubtitleForSession(session, syncNotification: false);
    }
    return _notificationSubtitleTexts[session.id];
  }

  bool get _shouldUseUnifiedPlaybackNotifications =>
      _multiThreadPlaybackEnabled && activeSessions.length > 1;

  Duration get _notificationRefreshInterval =>
      _shouldUseUnifiedPlaybackNotifications
      ? _multiSessionNotificationRefreshInterval
      : _notificationProgressRefreshInterval;

  void _ensureSubtitleTrackLoaded(String trackPath) {
    if (_subtitleTracks.containsKey(trackPath) ||
        _subtitleTrackFutures.containsKey(trackPath)) {
      return;
    }
    unawaited(subtitleTrackForPath(trackPath));
  }

  bool _refreshNotificationSubtitleForSession(
    PlaybackSession session, {
    Duration? position,
    bool syncNotification = true,
  }) {
    final trackPath = session.currentTrackPath;
    _ensureSubtitleTrackLoaded(trackPath);
    final nextText = subtitleTextForTrackAt(
      trackPath,
      position ?? session.player.position,
      subtitleTrack: _subtitleTracks[trackPath],
    );
    final previousText = _notificationSubtitleTexts[session.id];
    final previousTrackPath = _notificationSubtitleTrackPaths[session.id];
    if (previousTrackPath == trackPath && previousText == nextText) {
      return false;
    }

    _notificationSubtitleTexts[session.id] = nextText;
    _notificationSubtitleTrackPaths[session.id] = trackPath;

    if (syncNotification && _notificationFocusedSession?.id == session.id) {
      _syncNotificationState();
    }
    return true;
  }

  void _clearNotificationSubtitleForSession(String sessionId) {
    _notificationSubtitleTexts.remove(sessionId);
    _notificationSubtitleTrackPaths.remove(sessionId);
  }

  /// Returns all tracks that belong to the same folder group as the given track.
  List<MusicTrack> tracksInSameGroup(String trackPath) {
    final track = trackByPath(trackPath);
    if (track == null) return [];
    return _tracksByGroup[track.groupKey] ?? const <MusicTrack>[];
  }

  // ---------------------------------------------------------------------------
  // Session management (concurrent playback)
  // ---------------------------------------------------------------------------

  Future<void> spawnSession(MusicTrack track) async {
    final session = _createSessionForTrack(track);
    _registerSession(session);
    _scheduleSessionPersistence();
    unawaited(
      _enqueueSessionPreparation(session, nextPath: track.path, autoPlay: true),
    );
  }

  PlaybackSession _createSessionForTrack(
    MusicTrack track, {
    SessionLoopMode loopMode = SessionLoopMode.folderSequential,
    double volume = 1.0,
  }) {
    final player = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    return PlaybackSession(
      id: _nextSessionId(),
      player: player,
      currentTrackPath: track.path,
      loopMode: loopMode,
      nonSingleLoopMode: loopMode == SessionLoopMode.single
          ? SessionLoopMode.folderSequential
          : loopMode,
      volume: volume,
      createdAt: DateTime.now(),
      state: player.playerState,
    )..isLoading = true;
  }

  void _registerSession(PlaybackSession session) {
    _sessions[session.id] = session;
    _notificationFocusSessionId = session.id;
    _sessionOrder.insert(0, session.id);
    _markActiveSessionsDirty();
    _bindSessionListeners(session);
    _syncNotificationState();
    notifyListeners();
  }

  Future<void> _enqueueSessionPreparation(
    PlaybackSession session, {
    required String nextPath,
    required bool autoPlay,
  }) {
    _sessionPreparationQueue = _sessionPreparationQueue.catchError((_) {}).then(
      (_) async {
        if (!_sessions.containsKey(session.id)) return;
        await _prepareAndPlay(
          session,
          nextPath: nextPath,
          autoPlay: autoPlay,
          markLoading: false,
        );
      },
    );
    return _sessionPreparationQueue;
  }

  void _bindSessionListeners(PlaybackSession session) {
    final stateSub = session.player.playerStateStream.listen((state) {
      if (!_sessions.containsKey(session.id)) return;

      final previousProcessing = session.state.processingState;
      session.state = state;
      _syncKeepCpuAwake();
      _syncNotificationState();
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

    final positionSub = session.player.positionStream.listen((position) {
      if (!_sessions.containsKey(session.id)) return;
      if (_notificationFocusedSession?.id != session.id) return;
      final changed = _refreshNotificationSubtitleForSession(
        session,
        position: position,
        syncNotification: false,
      );
      _scheduleFocusedNotificationRefresh(session.id, immediate: changed);
    });
    session.subscriptions.add(positionSub);

    final durationSub = session.player.durationStream.listen((_) {
      if (!_sessions.containsKey(session.id)) return;
      _scheduleFocusedNotificationRefresh(session.id, immediate: true);
    });
    session.subscriptions.add(durationSub);

    final bufferedPositionSub = session.player.bufferedPositionStream.listen((
      _,
    ) {
      if (!_sessions.containsKey(session.id)) return;
      _scheduleFocusedNotificationRefresh(session.id);
    });
    session.subscriptions.add(bufferedPositionSub);
  }

  Future<void> _prepareAndPlay(
    PlaybackSession session, {
    required String nextPath,
    bool autoPlay = true,
    bool markLoading = true,
  }) async {
    if (!_sessions.containsKey(session.id)) return;

    // Bump the generation counter so any stale completion callbacks from the
    // previous source are ignored.
    session.loadGeneration++;
    if (markLoading) {
      session.isLoading = true;
      notifyListeners();
    }
    var prepared = false;

    try {
      session.currentTrackPath = nextPath;
      _ensureSubtitleTrackLoaded(nextPath);
      _refreshNotificationSubtitleForSession(
        session,
        position: Duration.zero,
        syncNotification: false,
      );
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
      prepared = true;
    } catch (e) {
      debugPrint('AudioProvider._prepareAndPlay error: $e');
    } finally {
      if (_sessions.containsKey(session.id)) {
        session.isLoading = false;
        _syncNotificationState();
        notifyListeners();
      }
    }
    // Fire play() without awaiting: on Android with handleAudioSessionActivation=false
    // the Future never resolves, which would permanently block the finally block above.
    if (_sessions.containsKey(session.id) && autoPlay && prepared) {
      await _startSessionPlayback(session, shouldStartTriggerCountdown: true);
    } else if (_sessions.containsKey(session.id)) {
      _syncNotificationState();
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
        await _prepareAndPlay(session, nextPath: session.currentTrackPath);
      } else {
        // Keep this non-blocking: with handleAudioSessionActivation=false on
        // some Android devices play() Future may never complete.
        await _startSessionPlayback(session, shouldStartTriggerCountdown: true);
      }
    }
  }

  Future<void> removeSession(String sessionId) async {
    await _removeSessions([sessionId]);
  }

  Future<void> _removeSessions(
    Iterable<String> sessionIds, {
    bool persist = true,
    bool notify = true,
  }) async {
    final removedSessions = <PlaybackSession>[];
    var removedAny = false;

    for (final sessionId in LinkedHashSet<String>.from(sessionIds)) {
      final session = _sessions.remove(sessionId);
      if (session == null) continue;
      removedAny = true;
      removedSessions.add(session);
      _clearNotificationSubtitleForSession(sessionId);
      if (_notificationFocusSessionId == sessionId) {
        _notificationFocusSessionId = null;
      }
      _sessionOrder.remove(sessionId);
    }

    if (!removedAny) return;

    _markActiveSessionsDirty();
    await Future.wait(
      removedSessions.map((session) async {
        await session.player.stop();
        session.dispose();
      }),
    );
    _syncKeepCpuAwake();
    _syncNotificationState();
    if (notify) {
      notifyListeners();
    }
    if (persist) {
      _scheduleSaveSessionState();
      _scheduleSaveSessionOrder();
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
    _syncNotificationState();
    notifyListeners();
    _scheduleSaveSessionState();
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

  Future<void> setSessionVolume(
    String sessionId,
    double volume, {
    bool persist = true,
    bool notify = true,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    final nextVolume = volume.clamp(0.0, 1.0);
    if ((session.volume - nextVolume).abs() < 0.001) {
      if (persist) {
        _scheduleSaveSessionState();
      }
      return;
    }
    session.volume = nextVolume;
    await session.player.setVolume(session.volume);
    if (notify) {
      notifyListeners();
    }
    if (persist) {
      _scheduleSaveSessionState();
    }
  }

  Future<void> seekSession(String sessionId, Duration position) async {
    final session = _sessions[sessionId];
    if (session != null) {
      await session.player.seek(position);
      _refreshNotificationSubtitleForSession(
        session,
        position: position,
        syncNotification: false,
      );
      _scheduleFocusedNotificationRefresh(session.id, immediate: true);
    }
  }

  /// Switch the current track of a session to a new path and start playing.
  Future<void> switchSessionTrack(String sessionId, String newPath) async {
    final session = _sessions[sessionId];
    if (session == null || session.isLoading) return;
    await _prepareAndPlay(session, nextPath: newPath);
    _scheduleSaveSessionState();
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
      _refreshNotificationSubtitleForSession(
        session,
        position: Duration.zero,
        syncNotification: false,
      );
      _scheduleFocusedNotificationRefresh(session.id, immediate: true);
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
    await _removeSessions(_sessions.keys.toList());
  }

  // ---------------------------------------------------------------------------
  // Timer management
  // ---------------------------------------------------------------------------

  /// Configure timer mode and duration. Does NOT start the countdown yet
  /// (for manual mode the user taps "start"; for trigger mode the countdown
  /// starts automatically when any audio begins playing).
  void configureTimer(TimerMode mode, Duration duration) {
    _timerDraftMode = mode;
    _timerDraftDuration = duration > Duration.zero
        ? duration
        : const Duration(minutes: 30);
    _cancelTimerInternal();
    _timerMode = mode;
    _timerDuration = duration;
    _timerRemaining = duration;
    _timerEndsAt = null;
    _timerActive = false;
    _timerWaitingForPlayback = mode == TimerMode.trigger;
    if (mode == TimerMode.trigger && _hasPlayingSession) {
      startCountdown();
      return;
    }
    _syncKeepCpuAwake();
    notifyListeners();
    unawaited(_saveTimerSettings());
    unawaited(_saveTimerRuntime());
  }

  /// Start the countdown immediately (used for manual mode and internally).
  void startCountdown() {
    if (_timerDuration == null || _timerActive) return;
    _countdownTimer?.cancel();
    final generation = ++_timerGeneration;
    _timerActive = true;
    _timerWaitingForPlayback = false;
    _timerRemaining = _timerDuration;
    _timerEndsAt = DateTime.now().add(_timerDuration!);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (generation != _timerGeneration) return;
      _tickCountdown();
    });
    _syncKeepCpuAwake();
    notifyListeners();
    unawaited(_saveTimerRuntime());
  }

  /// Cancel a running or configured timer.
  void cancelTimer() {
    _cancelTimerInternal();
    _timerMode = null;
    _timerDuration = null;
    _timerRemaining = null;
    _timerEndsAt = null;
    _timerWaitingForPlayback = false;
    _pausedByTimerPaths.clear();
    _syncKeepCpuAwake();
    notifyListeners();
    unawaited(_saveTimerRuntime());
  }

  void _cancelTimerInternal() {
    _timerGeneration++;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timerEndsAt = null;
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
    _autoResumeAt = null;
    _timerActive = false;
    _timerWaitingForPlayback = false;
    _syncKeepCpuAwake();
    unawaited(_saveTimerRuntime());
  }

  void _onTimerExpired() {
    _timerGeneration++;
    _timerActive = false;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timerEndsAt = null;
    _timerWaitingForPlayback = false;

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
      _scheduleAutoResumeTimer(
        _nextClockTime(_autoResumeHour, _autoResumeMinute),
      );
    }
    _syncKeepCpuAwake();
    unawaited(_saveTimerRuntime());
  }

  void _onAutoResume() {
    _autoResumeTimer = null;
    _autoResumeAt = null;
    unawaited(_saveTimerRuntime());
    unawaited(_resumeTimerPausedSessions());
  }

  void _resetTimerAfterAutoResumeSuccess() {
    _timerMode = null;
    _timerDuration = null;
    _timerActive = false;
    _timerRemaining = null;
    _timerEndsAt = null;
    _timerWaitingForPlayback = false;
  }

  Future<void> _resumeTimerPausedSessions() async {
    final activated = await _activateAudioSessionForPlayback();
    if (!activated) return;

    final resumableSessions = _sessions.values
        .where((s) => _pausedByTimerPaths.contains(s.currentTrackPath))
        .toList();

    if (resumableSessions.isEmpty) {
      _pausedByTimerPaths.clear();
      _syncKeepCpuAwake();
      notifyListeners();
      await _saveTimerRuntime();
      return;
    }

    // Resume sessions that were paused by the timer
    for (final session in resumableSessions) {
      await _startSessionPlayback(session, shouldStartTriggerCountdown: false);
    }
    _pausedByTimerPaths.clear();
    _autoResumeAt = null;
    _resetTimerAfterAutoResumeSuccess();
    _syncKeepCpuAwake();
    notifyListeners();
    await _saveTimerRuntime();
  }

  void setAutoResume(bool enabled, int hour, int minute) {
    _autoResumeEnabled = enabled;
    _autoResumeHour = hour;
    _autoResumeMinute = minute;
    if (!enabled) {
      _autoResumeTimer?.cancel();
      _autoResumeTimer = null;
      _autoResumeAt = null;
    } else if (_pausedByTimerPaths.isNotEmpty) {
      _scheduleAutoResumeTimer(_nextClockTime(hour, minute));
    }
    _syncKeepCpuAwake();
    notifyListeners();
    unawaited(_saveTimerSettings());
    unawaited(_saveTimerRuntime());
  }

  DateTime _nextClockTime(int hour, int minute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  void _scheduleAutoResumeTimer(DateTime target) {
    _autoResumeTimer?.cancel();
    _autoResumeAt = target;
    final delay = target.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _onAutoResume();
      return;
    }
    _autoResumeTimer = Timer(delay, _onAutoResume);
  }

  void _maybeStartTriggerCountdown() {
    if (_timerMode != TimerMode.trigger ||
        _timerDuration == null ||
        _timerActive ||
        !_timerWaitingForPlayback) {
      return;
    }
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

  bool get _hasPlayingSession => _sessions.values.any((s) => s.state.playing);

  String _nextSessionId() {
    _sessionSeed += 1;
    return 'session_${DateTime.now().microsecondsSinceEpoch}_$_sessionSeed';
  }

  bool get _hasPlaybackToKeepAlive =>
      _sessions.values.any((s) => s.state.playing || s.isLoading);

  bool get _hasRetainedPlaybackSession => _sessions.isNotEmpty;

  bool get _hasPendingAutoResume =>
      _autoResumeAt != null && _pausedByTimerPaths.isNotEmpty;

  void _syncKeepCpuAwake() {
    final hasPlayback = _hasPlaybackToKeepAlive;
    final hasTimer =
        _timerActive || _timerWaitingForPlayback || _hasPendingAutoResume;
    final shouldKeepAwake = hasPlayback || hasTimer;
    if (_keepCpuAwake == shouldKeepAwake &&
        _keepAliveHasPlayback == hasPlayback &&
        _keepAliveHasTimer == hasTimer) {
      return;
    }
    _keepCpuAwake = shouldKeepAwake;
    _keepAliveHasPlayback = hasPlayback;
    _keepAliveHasTimer = hasTimer;
    unawaited(
      _setKeepCpuAwake(
        shouldKeepAwake,
        hasActivePlayback: hasPlayback,
        hasActiveTimer: hasTimer,
      ),
    );
    if (!hasPlayback && !_hasRetainedPlaybackSession) {
      unawaited(_deactivateAudioSession());
    }
  }

  Future<void> _setKeepCpuAwake(
    bool enabled, {
    required bool hasActivePlayback,
    required bool hasActiveTimer,
  }) async {
    try {
      await _powerChannel.invokeMethod<void>('setKeepCpuAwake', {
        'enabled': enabled,
        'hasActivePlayback': hasActivePlayback,
        'hasActiveTimer': hasActiveTimer,
      });
    } on MissingPluginException {
      // Non-Android platforms don't expose this channel.
    } catch (e) {
      debugPrint('AudioProvider._setKeepCpuAwake error: $e');
    }
  }

  Future<bool> _activateAudioSessionForPlayback() async {
    try {
      final audioSession = await AudioSession.instance;
      return await audioSession.setActive(true);
    } catch (e) {
      debugPrint('AudioProvider._activateAudioSessionForPlayback error: $e');
      return true;
    }
  }

  Future<void> _deactivateAudioSession() async {
    try {
      final audioSession = await AudioSession.instance;
      await audioSession.setActive(false);
    } catch (e) {
      debugPrint('AudioProvider._deactivateAudioSession error: $e');
    }
  }

  Future<void> _startSessionPlayback(
    PlaybackSession session, {
    required bool shouldStartTriggerCountdown,
  }) async {
    if (!_sessions.containsKey(session.id)) return;
    if (!_multiThreadPlaybackEnabled) {
      await _enforceSingleThreadPlayback(preferredSessionId: session.id);
    }
    if (!_sessions.containsKey(session.id)) return;
    final activated = await _activateAudioSessionForPlayback();
    if (!_sessions.containsKey(session.id)) return;
    if (!activated) {
      debugPrint(
        'AudioProvider._startSessionPlayback: audio session activation '
        'returned false; continuing playback attempt.',
      );
    }

    _notificationFocusSessionId = session.id;
    unawaited(session.player.play());
    _syncKeepCpuAwake();
    if (shouldStartTriggerCountdown) {
      _maybeStartTriggerCountdown();
    }
  }

  Future<void> _resetSessionsForSingleThreadMode() async {
    if (_sessions.isEmpty) {
      _notificationFocusSessionId = null;
      _syncNotificationState();
      return;
    }

    await Future.wait(
      _sessions.values.map((session) => session.player.pause()),
    );
    _syncKeepCpuAwake();
    _notificationFocusSessionId = null;
    _syncNotificationState();
    notifyListeners();
  }

  Future<void> _enforceSingleThreadPlayback({
    String? preferredSessionId,
  }) async {
    final keepSessionId =
        (preferredSessionId != null &&
            _sessions.containsKey(preferredSessionId))
        ? preferredSessionId
        : _preferredSingleSessionId;
    if (keepSessionId == null) return;

    final sessionsToPause = _sessions.values
        .where(
          (session) => session.id != keepSessionId && session.state.playing,
        )
        .toList(growable: false);
    _notificationFocusSessionId = keepSessionId;
    if (sessionsToPause.isEmpty) {
      _syncNotificationState();
      notifyListeners();
      return;
    }

    await Future.wait(sessionsToPause.map((session) => session.player.pause()));
    _notificationFocusSessionId = keepSessionId;
    _syncKeepCpuAwake();
    _syncNotificationState();
    notifyListeners();
  }

  String? get _preferredSingleSessionId {
    for (final session in activeSessions) {
      if (session.state.playing) return session.id;
    }
    final sessions = activeSessions;
    if (sessions.isEmpty) return null;
    return sessions.first.id;
  }

  /// Reorder sessions in the display list.
  void reorderSessions(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sessionOrder.length) return;
    if (newIndex < 0 || newIndex > _sessionOrder.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = _sessionOrder.removeAt(oldIndex);
    _sessionOrder.insert(newIndex, moved);
    _markActiveSessionsDirty();
    _syncNotificationState();
    notifyListeners();
    _scheduleSaveSessionOrder();
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
      // Same track 闂?just rewind and play (shouldn't happen for non-single modes
      // unless there's only 1 track in the scope).
      await session.player.seek(Duration.zero);
      await _startSessionPlayback(session, shouldStartTriggerCountdown: false);
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
          final all = _sortedLibraryTracks
              .map((track) => track.path)
              .toList(growable: false);
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
            _tracksByGroup[currentTrack.groupKey] ?? const <MusicTrack>[];
        if (scope.isEmpty) return currentTrack.path;
        final idx = scope.indexWhere((t) => t.path == currentTrack.path);
        if (idx < 0) return scope.first.path;
        final next = (idx + (forward ? 1 : -1) + scope.length) % scope.length;
        return scope[next].path;

      case SessionLoopMode.crossSequential:
        final all = _sortedLibraryTracks;
        final idx = all.indexWhere((t) => t.path == currentTrack.path);
        if (idx < 0) return all.first.path;
        final next = (idx + (forward ? 1 : -1) + all.length) % all.length;
        return all[next].path;

      case SessionLoopMode.folderRandom:
        if (forward) {
          final scope =
              (_tracksByGroup[currentTrack.groupKey] ?? const <MusicTrack>[])
                  .map((track) => track.path)
                  .toList(growable: false);
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
