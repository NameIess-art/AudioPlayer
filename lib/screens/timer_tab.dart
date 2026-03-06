import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';

class TimerTab extends StatefulWidget {
  const TimerTab({super.key});

  @override
  State<TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<TimerTab> {
  // Duration picker state
  int _hours = 0;
  int _minutes = 30;
  int _seconds = 0;

  TimerMode _selectedMode = TimerMode.manual;

  Duration get _pickedDuration =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  String _fmtClockTime(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _durationIsZero => _pickedDuration == Duration.zero;

  void _onConfirm(AudioProvider provider) {
    if (_durationIsZero) return;
    provider.configureTimer(_selectedMode, _pickedDuration);
    if (_selectedMode == TimerMode.manual) {
      provider.startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final timerConfigured = provider.timerDuration != null;
    final timerActive = provider.timerActive;
    final timerExpired = timerConfigured && !timerActive &&
        provider.timerRemaining != null &&
        provider.timerRemaining! <= Duration.zero;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.timer_rounded, size: 28),
              const SizedBox(width: 12),
              Text(
                '计时',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Active Countdown Display ──────────────────────────────────────
          if (timerActive || timerExpired) ...[
            _CountdownCard(
              provider: provider,
              timerExpired: timerExpired,
              fmtDuration: _fmtDuration,
              cs: cs,
            ),
            const SizedBox(height: 20),
          ],

          // ── Configuration Card (hidden while countdown is running) ────────
          if (!timerActive) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设置倒计时',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Duration picker
                    _DurationPicker(
                      hours: _hours,
                      minutes: _minutes,
                      seconds: _seconds,
                      onChanged: (h, m, s) =>
                          setState(() {
                            _hours = h;
                            _minutes = m;
                            _seconds = s;
                          }),
                    ),
                    const SizedBox(height: 20),

                    // Mode selector
                    Text(
                      '倒计时方式',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    _ModeSelector(
                      value: _selectedMode,
                      onChanged: (mode) => setState(() => _selectedMode = mode),
                    ),
                    const SizedBox(height: 16),

                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _durationIsZero ? null : () => _onConfirm(provider),
                        icon: Icon(
                          _selectedMode == TimerMode.manual
                              ? Icons.play_arrow_rounded
                              : Icons.schedule_rounded,
                        ),
                        label: Text(
                          _selectedMode == TimerMode.manual
                              ? '确认并立即开始'
                              : '确认（播放后自动开始）',
                        ),
                      ),
                    ),

                    if (_durationIsZero)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '请先设置倒计时时长',
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Cancel button (visible when timer is configured / active)
          if (timerConfigured) ...[
            OutlinedButton.icon(
              onPressed: provider.cancelTimer,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('取消计时'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Auto-resume Card ──────────────────────────────────────────────
          if (timerConfigured) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('倒计时结束后自动恢复播放'),
                      subtitle: const Text('在指定延迟后重新播放被暂停的音频'),
                      secondary: const Icon(Icons.restore_rounded),
                      value: provider.autoResumeEnabled,
                      onChanged: (val) {
                        provider.setAutoResume(val, provider.autoResumeHour, provider.autoResumeMinute);
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    if (provider.autoResumeEnabled) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.alarm_rounded),
                        title: Text(
                          '开始时间：${_fmtClockTime(provider.autoResumeHour, provider.autoResumeMinute)}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: const Text('倒计时结束后，在此时间点恢复播放'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                                hour: provider.autoResumeHour, minute: provider.autoResumeMinute),
                            helpText: '选择自动恢复时间',
                            builder: (ctx, child) => MediaQuery(
                              data: MediaQuery.of(ctx)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            provider.setAutoResume(
                                provider.autoResumeEnabled,
                                picked.hour,
                                picked.minute);
                          }
                        },
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(16)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Hint when nothing is configured
          if (!timerConfigured) ...[
            const SizedBox(height: 16),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '设置倒计时后，可在此处启用自动恢复播放功能',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown card
// ─────────────────────────────────────────────────────────────────────────────

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.provider,
    required this.timerExpired,
    required this.fmtDuration,
    required this.cs,
  });

  final AudioProvider provider;
  final bool timerExpired;
  final String Function(Duration) fmtDuration;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final remaining = provider.timerRemaining ?? Duration.zero;
    final modeLabel = provider.timerMode == TimerMode.manual
        ? '手动开始'
        : '播放后自动开始';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: timerExpired
              ? [cs.errorContainer, cs.errorContainer.withValues(alpha: 0.6)]
              : [
                  cs.primaryContainer,
                  cs.primaryContainer.withValues(alpha: 0.6),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: timerExpired
              ? cs.error.withValues(alpha: 0.4)
              : cs.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            timerExpired ? Icons.alarm_off_rounded : Icons.timer_rounded,
            size: 36,
            color: timerExpired ? cs.error : cs.primary,
          ),
          const SizedBox(height: 12),
          Text(
            timerExpired ? '倒计时已结束' : '倒计时进行中',
            style: TextStyle(
              fontSize: 13,
              color: timerExpired ? cs.error : cs.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            fmtDuration(remaining),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: timerExpired ? cs.error : cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: timerExpired
                  ? cs.error.withValues(alpha: 0.12)
                  : cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.timerMode == TimerMode.manual
                      ? Icons.play_arrow_rounded
                      : Icons.schedule_rounded,
                  size: 14,
                  color: timerExpired ? cs.error : cs.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  modeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: timerExpired ? cs.error : cs.primary,
                  ),
                ),
              ],
            ),
          ),
          if (timerExpired && provider.pausedByTimerPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '已暂停 ${provider.pausedByTimerPaths.length} 个音频',
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ],
          if (timerExpired && provider.autoResumeEnabled) ...[
            const SizedBox(height: 4),
            Text(
              '将在 ${provider.autoResumeHour.toString().padLeft(2, '0')}:${provider.autoResumeMinute.toString().padLeft(2, '0')} 自动恢复',
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duration picker
// ─────────────────────────────────────────────────────────────────────────────

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onChanged,
  });

  final int hours;
  final int minutes;
  final int seconds;
  final void Function(int h, int m, int s) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget picker(String label, int value, int max, void Function(int) onChange) {
      return Expanded(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value,
                  isExpanded: true,
                  alignment: Alignment.center,
                  items: List.generate(max + 1, (i) => i)
                      .map((v) => DropdownMenuItem(
                            value: v,
                            alignment: Alignment.center,
                            child: Text(
                              v.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChange(v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Row(
      children: [
        picker('小时', hours, 5, (v) => onChanged(v, minutes, seconds)),
        const SizedBox(width: 4),
        Center(
          child: Text(
            ':',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 4),
        picker('分钟', minutes, 59, (v) => onChanged(hours, v, seconds)),
        const SizedBox(width: 4),
        Center(
          child: Text(
            ':',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 4),
        picker('秒', seconds, 59, (v) => onChanged(hours, minutes, v)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode selector
// ─────────────────────────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});

  final TimerMode value;
  final ValueChanged<TimerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget modeCard(TimerMode mode, String title, String subtitle, IconData icon) {
      final selected = value == mode;
      return GestureDetector(
        onTap: () => onChanged(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? cs.primary : cs.outline,
                    width: selected ? 6 : 2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon,
                  size: 20,
                  color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: selected ? cs.primary : null)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        modeCard(
          TimerMode.manual,
          '手动开始',
          '确认后立即开始倒计时',
          Icons.play_circle_outline_rounded,
        ),
        modeCard(
          TimerMode.trigger,
          '播放后自动开始',
          '确认后，当有音频开始播放时自动启动倒计时',
          Icons.sensors_rounded,
        ),
      ],
    );
  }
}
