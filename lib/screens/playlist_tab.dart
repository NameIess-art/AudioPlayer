import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/top_page_header.dart';

class PlaylistTab extends StatelessWidget {
  const PlaylistTab({super.key});

  Future<void> _confirmClearAll(
    BuildContext context,
    AudioProvider provider,
  ) async {
    final i18n = context.read<AppLanguageProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.tr('clear_all_sessions')),
        content: Text(i18n.tr('stop_remove_all_sessions')),
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
            child: Text(i18n.tr('clear')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.clearAllSessions();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(i18n.tr('all_sessions_cleared'))),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.watch<AudioProvider>();
    final sessions = provider.activeSessions;
    final playingCount = sessions.where((s) => s.state.playing).length;

    return SafeArea(
      child: Column(
        children: [
          TopPageHeader(
            icon: Icons.graphic_eq_rounded,
            title: i18n.tr('playback_sessions'),
            trailing: SizedBox(
              width: 112,
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    button: true,
                    label: i18n.tr('pause_all_sessions'),
                    child: IconButton(
                      onPressed: sessions.isEmpty
                          ? null
                          : () {
                              provider.pauseAllSessions();
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(i18n.tr('all_paused')),
                                  ),
                                );
                            },
                      icon: const Icon(Icons.pause_circle_outline_rounded),
                      tooltip: i18n.tr('pause_all_sessions'),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: i18n.tr('clear_all_sessions'),
                    child: IconButton(
                      onPressed: sessions.isEmpty
                          ? null
                          : () => _confirmClearAll(context, provider),
                      icon: const Icon(Icons.delete_sweep_rounded),
                      tooltip: i18n.tr('clear_all_sessions'),
                    ),
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
                  icon: Icons.queue_music_rounded,
                  text: i18n.tr('sessions_count', {'count': sessions.length}),
                ),
                _MetricChip(
                  icon: Icons.play_circle_rounded,
                  text: i18n.tr('playing_count', {'count': playingCount}),
                ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? const _SessionsEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
                    itemCount: sessions.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _SessionCard(
                        key: ValueKey(session.id),
                        session: session,
                        provider: provider,
                      );
                    },
                  ),
          ),
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

class _SessionsEmptyState extends StatelessWidget {
  const _SessionsEmptyState();

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
                    Icons.queue_music_rounded,
                    size: 30,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  i18n.tr('no_active_sessions'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  i18n.tr('go_library_hint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  const _SessionCard({
    required super.key,
    required this.session,
    required this.provider,
  });

  final PlaybackSession session;
  final AudioProvider provider;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = false;

  PlaybackSession get session => widget.session;
  AudioProvider get provider => widget.provider;

  bool _isSingleLoop(SessionLoopMode mode) => mode == SessionLoopMode.single;

  bool _isShuffleLoop(SessionLoopMode mode) {
    return mode == SessionLoopMode.crossRandom ||
        mode == SessionLoopMode.folderRandom;
  }

  bool _isCrossFolderLoop(SessionLoopMode mode) {
    return mode == SessionLoopMode.crossRandom ||
        mode == SessionLoopMode.crossSequential;
  }

  String _loopModeSummary(SessionLoopMode mode) {
    final i18n = context.read<AppLanguageProvider>();
    if (_isSingleLoop(mode)) return i18n.tr('single_loop');
    final scope = _isCrossFolderLoop(mode)
        ? i18n.tr('cross_folder')
        : i18n.tr('current_folder');
    final order = _isShuffleLoop(mode)
        ? i18n.tr('random_order')
        : i18n.tr('sequential_order');
    return '$order · $scope';
  }

  Widget _buildLoopModeButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required bool active,
    required bool disabled,
    required VoidCallback? onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: disabled ? null : onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: active
            ? cs.primaryContainer
            : cs.surfaceContainerHighest.withValues(alpha: 0.9),
        side: BorderSide(
          color: active ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant,
        ),
      ),
      icon: Icon(
        icon,
        size: 18,
        color: disabled
            ? cs.onSurface.withValues(alpha: 0.35)
            : active
            ? cs.primary
            : cs.onSurfaceVariant,
      ),
    );
  }

  void _showTrackSwitcher(BuildContext context) {
    final i18n = context.read<AppLanguageProvider>();
    final siblings = provider.tracksInSameGroup(session.currentTrackPath);
    if (siblings.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(i18n.tr('no_other_audio_in_folder'))),
        );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          i18n.tr('switch_audio'),
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: siblings.length,
                    itemBuilder: (_, i) {
                      final track = siblings[i];
                      final isCurrent = track.path == session.currentTrackPath;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.volume_up_rounded
                              : Icons.music_note_rounded,
                          color: isCurrent
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          track.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: isCurrent
                              ? TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(ctx).colorScheme.primary,
                                )
                              : null,
                        ),
                        trailing: isCurrent
                            ? Icon(
                                Icons.check_rounded,
                                color: Theme.of(ctx).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (!isCurrent) {
                            provider.switchSessionTrack(session.id, track.path);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final track = provider.trackByPath(session.currentTrackPath);
    final displayName =
        track?.displayName ??
        path.basenameWithoutExtension(session.currentTrackPath);
    final folderName = (track != null && !track.isSingle)
        ? track.groupTitle
        : null;
    final isPlaying = session.state.playing;
    final hasSiblings =
        provider.tracksInSameGroup(session.currentTrackPath).length > 1;
    final singleLoopEnabled = _isSingleLoop(session.loopMode);
    final shuffleEnabled = _isShuffleLoop(session.loopMode);
    final crossFolderEnabled = _isCrossFolderLoop(session.loopMode);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPlaying
              ? cs.primary.withValues(alpha: 0.65)
              : cs.outlineVariant,
          width: isPlaying ? 1.6 : 1,
        ),
        boxShadow: [
          if (isPlaying)
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (folderName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      folderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              folderName != null ? 6 : 12,
              8,
              _expanded ? 4 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isPlaying ? cs.primary : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loopModeSummary(session.loopMode),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 20),
                    tooltip: context.read<AppLanguageProvider>().tr(
                      'previous_track',
                    ),
                    onPressed: () => provider.seekSessionToPrev(session.id),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton.filled(
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 20,
                    ),
                    tooltip: isPlaying
                        ? context.read<AppLanguageProvider>().tr('pause')
                        : context.read<AppLanguageProvider>().tr('play'),
                    onPressed: () =>
                        provider.toggleSessionPlayPause(session.id),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                    tooltip: context.read<AppLanguageProvider>().tr(
                      'next_track',
                    ),
                    onPressed: () => provider.seekSessionToNext(session.id),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                IconButton(
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, size: 22),
                  ),
                  tooltip: _expanded
                      ? context.read<AppLanguageProvider>().tr('collapse')
                      : context.read<AppLanguageProvider>().tr('expand'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: context.read<AppLanguageProvider>().tr(
                    'end_session',
                  ),
                  onPressed: () => provider.removeSession(session.id),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 12, color: cs.outlineVariant),
                        _ProgressBar(
                          player: session.player,
                          sessionId: session.id,
                          provider: provider,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildLoopModeButton(
                              context: context,
                              icon: Icons.repeat_one_rounded,
                              tooltip: context.read<AppLanguageProvider>().tr(
                                'single_loop',
                              ),
                              active: singleLoopEnabled,
                              disabled: false,
                              onPressed: () =>
                                  provider.toggleSessionSingleLoop(session.id),
                            ),
                            const SizedBox(width: 6),
                            _buildLoopModeButton(
                              context: context,
                              icon: shuffleEnabled
                                  ? Icons.shuffle_rounded
                                  : Icons.repeat_rounded,
                              tooltip: shuffleEnabled
                                  ? context.read<AppLanguageProvider>().tr(
                                      'random_play',
                                    )
                                  : context.read<AppLanguageProvider>().tr(
                                      'sequential_play',
                                    ),
                              active: shuffleEnabled,
                              disabled: singleLoopEnabled,
                              onPressed: () =>
                                  provider.toggleSessionShuffle(session.id),
                            ),
                            const SizedBox(width: 6),
                            _buildLoopModeButton(
                              context: context,
                              icon: crossFolderEnabled
                                  ? Icons.folder_copy_rounded
                                  : Icons.folder_rounded,
                              tooltip: crossFolderEnabled
                                  ? context.read<AppLanguageProvider>().tr(
                                      'cross_folder_play',
                                    )
                                  : context.read<AppLanguageProvider>().tr(
                                      'current_folder_only',
                                    ),
                              active: crossFolderEnabled,
                              disabled: singleLoopEnabled,
                              onPressed: () =>
                                  provider.toggleSessionCrossFolder(session.id),
                            ),
                            const Spacer(),
                            if (hasSiblings)
                              IconButton.outlined(
                                icon: const Icon(
                                  Icons.queue_music_rounded,
                                  size: 18,
                                ),
                                tooltip: context.read<AppLanguageProvider>().tr(
                                  'switch_audio',
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showTrackSwitcher(context),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              session.volume == 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_down_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.5,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 10,
                                  ),
                                ),
                                child: Slider(
                                  value: session.volume,
                                  min: 0,
                                  max: 1,
                                  onChanged: (val) => provider.setSessionVolume(
                                    session.id,
                                    val,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.player,
    required this.sessionId,
    required this.provider,
  });

  final AudioPlayer player;
  final String sessionId;
  final AudioProvider provider;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, snapshot) {
        final duration = snapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, snapshot) {
            var position = snapshot.data ?? Duration.zero;
            if (position > duration) position = duration;

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: max(1, duration.inMilliseconds).toDouble(),
                    value: position.inMilliseconds
                        .clamp(0, max(1, duration.inMilliseconds))
                        .toDouble(),
                    onChanged: (value) {
                      if (duration.inMilliseconds > 0) {
                        provider.seekSession(
                          sessionId,
                          Duration(milliseconds: value.round()),
                        );
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(position),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                      Text(
                        _fmt(duration),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }
}
