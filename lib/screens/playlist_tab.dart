import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'dart:math';

import '../providers/audio_provider.dart';

class PlaylistTab extends StatelessWidget {
  const PlaylistTab({super.key});

  Future<void> _confirmClearAll(BuildContext context, AudioProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除所有任务'),
        content: const Text('确认要停止并移除所有播放任务吗？'),
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
            child: const Text('全部移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.clearAllSessions();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('已清空所有播放任务')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();
    final sessions = provider.activeSessions;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.dashboard_rounded, size: 28),
                const SizedBox(width: 12),
                Text(
                  '运行中的播放任务',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: sessions.isEmpty ? null : () {
                    provider.pauseAllSessions();
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(const SnackBar(content: Text('已暂停全部播放')));
                  },
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  tooltip: '全部暂停',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: sessions.isEmpty ? null : () => _confirmClearAll(context, provider),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: '清空列表',
                ),
              ],
            ),
          ),

          Expanded(
            child: sessions.isEmpty
                ? const Center(
                    child: Text('当前没有任务在播放\n请从文件管理去添加音乐', textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: sessions.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _SessionCard(
                        key: ValueKey(session.id),
                        session: session,
                        provider: provider,
                        index: index,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Card (stateful – supports collapsed/expanded)
// ─────────────────────────────────────────────────────────────────────────────

class _SessionCard extends StatefulWidget {
  const _SessionCard({
    required super.key,
    required this.session,
    required this.provider,
    required this.index,
  });

  final PlaybackSession session;
  final AudioProvider provider;
  final int index;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = false;

  PlaybackSession get session => widget.session;
  AudioProvider get provider => widget.provider;

  void _showTrackSwitcher(BuildContext context) {
    final siblings = provider.tracksInSameGroup(session.currentTrackPath);
    if (siblings.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('该文件夹内没有其他曲目')));
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
                      Icon(Icons.folder_open_rounded, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '切换曲目',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                          isCurrent ? Icons.volume_up_rounded : Icons.music_note_rounded,
                          color: isCurrent ? Theme.of(ctx).colorScheme.primary : null,
                        ),
                        title: Text(
                          track.displayName,
                          maxLines: 3,
                          softWrap: true,
                          style: isCurrent
                              ? TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(ctx).colorScheme.primary,
                                )
                              : null,
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary)
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
    final track = provider.trackByPath(session.currentTrackPath);
    final displayName = track?.displayName ?? path.basenameWithoutExtension(session.currentTrackPath);
    final folderName = (track != null && !track.isSingle) ? track.groupTitle : null;
    final isPlaying = session.state.playing;
    final hasSiblings = provider.tracksInSameGroup(session.currentTrackPath).length > 1;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPlaying ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant,
          width: isPlaying ? 2 : 1,
        ),
        boxShadow: [
          if (isPlaying)
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Folder tag (only when track belongs to a named folder) ──────
          if (folderName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      folderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Main row: title + controls ──────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, folderName != null ? 4 : 12, 6, _expanded ? 4 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Track name
                Expanded(
                  child: Text(
                    displayName,
                    maxLines: 3,
                    softWrap: true,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPlaying ? cs.primary : null,
                    ),
                  ),
                ),

                // Controls (loading spinner or buttons)
                if (session.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 20),
                    tooltip: '上一首',
                    onPressed: () => provider.seekSessionToPrev(session.id),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  IconButton.filled(
                    icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 20),
                    tooltip: isPlaying ? '暂停' : '播放',
                    onPressed: () => provider.toggleSessionPlayPause(session.id),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                    tooltip: '下一首',
                    onPressed: () => provider.seekSessionToNext(session.id),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],

                // Expand / Collapse toggle
                IconButton(
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, size: 22),
                  ),
                  tooltip: _expanded ? '收起' : '展开',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  visualDensity: VisualDensity.compact,
                ),

                // Close
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '结束任务',
                  onPressed: () => provider.removeSession(session.id),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // ── Expanded detail section ─────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12, thickness: 0.5),

                  // Progress bar
                  _ProgressBar(player: session.player, sessionId: session.id, provider: provider),
                  const SizedBox(height: 8),

                  // Bottom row: Loop dropdown + optional switch track + Volume
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<SessionLoopMode>(
                              value: session.loopMode,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down_rounded),
                              style: Theme.of(context).textTheme.bodySmall,
                              items: SessionLoopMode.values.map((mode) {
                                return DropdownMenuItem(
                                  value: mode,
                                  child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) provider.setSessionLoopMode(session.id, val);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (hasSiblings)
                        IconButton.outlined(
                          icon: const Icon(Icons.queue_music_rounded, size: 18),
                          tooltip: '切换曲目',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _showTrackSwitcher(context),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Icon(
                              session.volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                ),
                                child: Slider(
                                  value: session.volume,
                                  min: 0,
                                  max: 1,
                                  onChanged: (val) => provider.setSessionVolume(session.id, val),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress bar widget
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player, required this.sessionId, required this.provider});

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
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    min: 0,
                    max: max(1, duration.inMilliseconds).toDouble(),
                    value: position.inMilliseconds.clamp(0, max(1, duration.inMilliseconds)).toDouble(),
                    onChanged: (value) {
                      if (duration.inMilliseconds > 0) {
                        provider.seekSession(sessionId, Duration(milliseconds: value.round()));
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                      Text(_fmt(duration), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
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
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
