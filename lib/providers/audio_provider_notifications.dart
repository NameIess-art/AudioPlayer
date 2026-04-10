part of 'audio_provider.dart';

extension AudioProviderNotifications on AudioProvider {
  bool get _hasActivePlaybackSession => activeSessions.any(
    (session) => session.state.playing || session.isLoading,
  );

  PlaybackNotificationSnapshot? _buildMediaSessionSnapshot() {
    if (!_shouldUseUnifiedPlaybackNotifications) {
      return _buildNotificationSnapshot();
    }
    if (!_hasActivePlaybackSession) {
      return null;
    }
    return _buildNotificationSnapshot();
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
      onNotificationDeleted: dismissNotificationsAfterPauseAll,
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

  Future<void> dismissNotificationsAfterPauseAll() async {
    _notificationsDismissedWhilePaused = true;
    await pauseAllSessions();
    await _clearUnifiedPlaybackNotificationsOnPlatform();
    _notificationHandler.updateSnapshot(null);
    _notificationFocusSessionId = _preferredSingleSessionId;
    _notifyListeners();
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
    if (_shouldUseUnifiedPlaybackNotifications) {
      _notificationActionRefreshTimer?.cancel();
      _notificationActionRefreshTimer = null;
      return;
    }

    _syncNotificationState();
    _notifyListeners();

    _notificationActionRefreshTimer?.cancel();
    _notificationActionRefreshTimer = Timer(
      const Duration(milliseconds: 220),
      () {
        _notificationActionRefreshTimer = null;
        _syncNotificationState();
        _notifyListeners();
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
        AudioProvider._androidGroupSummaryKey: 1,
        'android_group_key': AudioProvider._androidNotificationGroupKey,
        AudioProvider._androidSummaryTitleKey: 'AudioPlayer',
        AudioProvider._androidSummaryTextKey: _notificationSummaryText(
          sessions,
        ),
        AudioProvider._androidSummaryLinesKey: titles.join('\n'),
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
          _notifyListeners();
        }
      }

      return coverPath;
    });
  }

  Future<String?> _resolveContentCoverPathForTrack(MusicTrack track) async {
    try {
      return await AudioProvider._fileCacheChannel.invokeMethod<String>(
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
        _notifyListeners();
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
        if (AudioProvider._supportedImageExtensions.contains(extension)) {
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

  Future<void> _clearUnifiedPlaybackNotificationsOnPlatform() async {
    _unifiedNotificationSyncKey = null;
    try {
      await AudioProvider._notificationsChannel.invokeMethod<void>(
        'clearUnifiedPlaybackNotifications',
      );
    } on MissingPluginException {
      // The Android notifications channel is not available on this platform.
    } catch (e) {
      debugPrint('AudioProvider._clearUnifiedPlaybackNotifications error: $e');
    }
  }

  void _syncNotificationState({bool immediateUnifiedSync = false}) {
    if (_notificationsDismissedWhilePaused && !_hasPlaybackToKeepAlive) {
      _unifiedNotificationSyncTimer?.cancel();
      _unifiedNotificationSyncTimer = null;
      _notificationHandler.updateSnapshot(null);
      _requestUnifiedPlaybackNotificationFlush();
      return;
    }
    if (_shouldUseUnifiedPlaybackNotifications) {
      _notificationHandler.updateSnapshot(_buildMediaSessionSnapshot());
      if (immediateUnifiedSync) {
        _unifiedNotificationSyncTimer?.cancel();
        _unifiedNotificationSyncTimer = null;
        _requestUnifiedPlaybackNotificationFlush();
      } else {
        _scheduleUnifiedPlaybackNotificationSync();
      }
      return;
    }

    _unifiedNotificationSyncTimer?.cancel();
    _unifiedNotificationSyncTimer = null;
    _notificationHandler.updateSnapshot(_buildNotificationSnapshot());
    _requestUnifiedPlaybackNotificationFlush();
  }

  void _scheduleUnifiedPlaybackNotificationSync() {
    if (!_shouldUseUnifiedPlaybackNotifications) {
      _unifiedNotificationSyncTimer?.cancel();
      _unifiedNotificationSyncTimer = null;
      _requestUnifiedPlaybackNotificationFlush();
      return;
    }
    if (_unifiedNotificationSyncTimer != null) {
      return;
    }
    _unifiedNotificationSyncTimer = Timer(
      AudioProvider._unifiedNotificationDebounceInterval,
      () {
        _unifiedNotificationSyncTimer = null;
        _requestUnifiedPlaybackNotificationFlush();
      },
    );
  }

  void _requestUnifiedPlaybackNotificationFlush() {
    _unifiedNotificationSyncPending = true;
    if (_unifiedNotificationSyncInFlight) {
      return;
    }
    _unifiedNotificationSyncInFlight = true;
    unawaited(_flushUnifiedPlaybackNotificationState());
  }

  Future<void> _flushUnifiedPlaybackNotificationState() async {
    try {
      while (_unifiedNotificationSyncPending) {
        _unifiedNotificationSyncPending = false;
        final shouldShowUnifiedNotifications =
            !_notificationsDismissedWhilePaused &&
            _shouldUseUnifiedPlaybackNotifications;
        if (!shouldShowUnifiedNotifications) {
          await _clearUnifiedPlaybackNotificationsOnPlatform();
          continue;
        }
        await _syncUnifiedPlaybackNotifications();
      }
    } finally {
      _unifiedNotificationSyncInFlight = false;
      if (_unifiedNotificationSyncPending) {
        _requestUnifiedPlaybackNotificationFlush();
      }
    }
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
        await _clearUnifiedPlaybackNotificationsOnPlatform();
      } else {
        await AudioProvider._notificationsChannel.invokeMethod<void>(
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
    _notifyListeners();
  }

  Future<void> selectNotificationSessionFromQueue(int index) async {
    final sessions = _notificationQueueSessions;
    if (index < 0 || index >= sessions.length) return;
    _notificationFocusSessionId = sessions[index].id;
    _syncNotificationState();
    _notifyListeners();
  }

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
        _notifyListeners();
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
      ? AudioProvider._multiSessionNotificationRefreshInterval
      : AudioProvider._notificationProgressRefreshInterval;

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
}
