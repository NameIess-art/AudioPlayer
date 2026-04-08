import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/playback_notification_handler.dart';

void main() {
  test('playFromMediaId forwards notification resume callback', () async {
    final handler = PlaybackNotificationHandler();
    String? mediaId;

    handler.bindCallbacks(
      onPlayFromMediaId: (id) async {
        mediaId = id;
      },
    );

    await handler.playFromMediaId('session_1');

    expect(mediaId, 'session_1');
  });

  test('playMediaItem forwards media item id to resume callback', () async {
    final handler = PlaybackNotificationHandler();
    String? mediaId;

    handler.bindCallbacks(
      onPlayFromMediaId: (id) async {
        mediaId = id;
      },
    );

    await handler.playMediaItem(
      const MediaItem(id: 'session_1', title: 'Track 1'),
    );

    expect(mediaId, 'session_1');
  });

  test('media button click still toggles play pause callback', () async {
    final handler = PlaybackNotificationHandler();
    var toggleCount = 0;

    handler.bindCallbacks(
      onTogglePlayPause: () async {
        toggleCount++;
      },
    );

    await handler.click();

    expect(toggleCount, 1);
  });

  test('notification snapshot uses native playPause control', () {
    final handler = PlaybackNotificationHandler();

    handler.updateSnapshot(
      const PlaybackNotificationSnapshot(
        queue: <MediaItem>[MediaItem(id: 'session_1', title: 'Track 1')],
        queueIndex: 0,
        mediaItem: MediaItem(id: 'session_1', title: 'Track 1'),
        playing: false,
        processingState: AudioProcessingState.ready,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        hasPrevious: false,
        hasNext: false,
      ),
    );

    final state = handler.playbackState.value;

    expect(state.controls, hasLength(1));
    expect(state.controls.single.action, MediaAction.playPause);
  });

  test('session custom action forwards session id', () async {
    final handler = PlaybackNotificationHandler();
    String? toggledSessionId;

    handler.bindCallbacks(
      onToggleSessionPlayback: (sessionId) async {
        toggledSessionId = sessionId;
      },
    );

    await handler.customAction(
      PlaybackNotificationHandler.toggleSessionPlaybackAction,
      const {PlaybackNotificationHandler.sessionIdExtrasKey: 'session_42'},
    );

    expect(toggledSessionId, 'session_42');
  });

  test('session previous action forwards session id', () async {
    final handler = PlaybackNotificationHandler();
    String? previousSessionId;

    handler.bindCallbacks(
      onSkipToPreviousSession: (sessionId) async {
        previousSessionId = sessionId;
      },
    );

    await handler.customAction(
      PlaybackNotificationHandler.sessionSkipPreviousAction,
      const {PlaybackNotificationHandler.sessionIdExtrasKey: 'session_prev'},
    );

    expect(previousSessionId, 'session_prev');
  });

  test('grouped summary snapshot hides transport controls', () {
    final handler = PlaybackNotificationHandler();

    handler.updateSnapshot(
      const PlaybackNotificationSnapshot(
        queue: <MediaItem>[MediaItem(id: 'summary', title: 'AsmrPlayer')],
        queueIndex: 0,
        mediaItem: MediaItem(id: 'summary', title: 'AsmrPlayer'),
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        hasPrevious: false,
        hasNext: false,
        showTransportControls: false,
      ),
    );

    final state = handler.playbackState.value;

    expect(state.controls, isEmpty);
    expect(state.systemActions, isEmpty);
  });

  test('session next action forwards session id', () async {
    final handler = PlaybackNotificationHandler();
    String? nextSessionId;

    handler.bindCallbacks(
      onSkipToNextSession: (sessionId) async {
        nextSessionId = sessionId;
      },
    );

    await handler.customAction(
      PlaybackNotificationHandler.sessionSkipNextAction,
      const {PlaybackNotificationHandler.sessionIdExtrasKey: 'session_next'},
    );

    expect(nextSessionId, 'session_next');
  });

  test('notification delete forwards dismiss callback', () async {
    final handler = PlaybackNotificationHandler();
    var dismissCount = 0;

    handler.bindCallbacks(
      onNotificationDeleted: () async {
        dismissCount++;
      },
    );

    await handler.onNotificationDeleted();

    expect(dismissCount, 1);
  });
}
