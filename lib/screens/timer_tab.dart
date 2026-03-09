import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/top_page_header.dart';

class TimerTab extends StatefulWidget {
  const TimerTab({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  State<TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<TimerTab> {
  int _hours = 0;
  int _minutes = 30;
  int _seconds = 0;
  TimerMode _selectedMode = TimerMode.manual;

  Duration get _pickedDuration =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  bool get _durationIsZero => _pickedDuration == Duration.zero;

  String _fmtClockTime(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onConfirm(AudioProvider provider) {
    if (_durationIsZero) return;
    provider.configureTimer(_selectedMode, _pickedDuration);
    if (_selectedMode == TimerMode.manual) {
      provider.startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final provider = context.watch<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final timerConfigured = provider.timerDuration != null;
    final timerActive = provider.timerActive;
    final timerExpired =
        timerConfigured &&
        !timerActive &&
        provider.timerRemaining != null &&
        provider.timerRemaining! <= Duration.zero;
    final timerWaitingTrigger =
        timerConfigured &&
        !timerActive &&
        !timerExpired &&
        provider.timerMode == TimerMode.trigger &&
        provider.timerRemaining != null &&
        provider.timerRemaining! > Duration.zero;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (widget.showHeader)
            TopPageHeader(
              icon: Icons.timer_rounded,
              title: i18n.tr('timer_title'),
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              bottomSpacing: 16,
            ),
          if (timerActive || timerExpired || timerWaitingTrigger) ...[
            _CountdownCard(
              provider: provider,
              timerExpired: timerExpired,
              waitingTrigger: timerWaitingTrigger,
              fmtDuration: _fmtDuration,
              cs: cs,
            ),
            const SizedBox(height: 16),
          ],
          if (!timerActive && !timerWaitingTrigger) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.tr('set_countdown'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DurationPicker(
                      hours: _hours,
                      minutes: _minutes,
                      seconds: _seconds,
                      onChanged: (h, m, s) => setState(() {
                        _hours = h;
                        _minutes = m;
                        _seconds = s;
                      }),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      i18n.tr('start_mode'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    _ModeSelector(
                      value: _selectedMode,
                      onChanged: (mode) => setState(() => _selectedMode = mode),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _durationIsZero
                          ? null
                          : () => _onConfirm(provider),
                      icon: Icon(
                        _selectedMode == TimerMode.manual
                            ? Icons.play_arrow_rounded
                            : Icons.schedule_rounded,
                      ),
                      label: Text(
                        _selectedMode == TimerMode.manual
                            ? i18n.tr('confirm_start_now')
                            : i18n.tr('confirm_wait_playback'),
                      ),
                    ),
                    if (_durationIsZero)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          i18n.tr('set_duration_first'),
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (timerConfigured) ...[
            OutlinedButton.icon(
              onPressed: provider.cancelTimer,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(i18n.tr('cancel_timer')),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (timerConfigured)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text(i18n.tr('auto_resume_after_timer')),
                      subtitle: Text(i18n.tr('auto_resume_subtitle')),
                      secondary: const Icon(Icons.restore_rounded),
                      value: provider.autoResumeEnabled,
                      onChanged: (val) {
                        provider.setAutoResume(
                          val,
                          provider.autoResumeHour,
                          provider.autoResumeMinute,
                        );
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
                          i18n.tr('resume_time', {
                            'time': _fmtClockTime(
                              provider.autoResumeHour,
                              provider.autoResumeMinute,
                            ),
                          }),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(i18n.tr('tap_choose_resume_time')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: provider.autoResumeHour,
                              minute: provider.autoResumeMinute,
                            ),
                            helpText: i18n.tr('choose_auto_resume_time'),
                            builder: (ctx, child) => MediaQuery(
                              data: MediaQuery.of(
                                ctx,
                              ).copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            provider.setAutoResume(
                              provider.autoResumeEnabled,
                              picked.hour,
                              picked.minute,
                            );
                          }
                        },
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  i18n.tr('set_timer_to_enable_auto_resume'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.provider,
    required this.timerExpired,
    required this.waitingTrigger,
    required this.fmtDuration,
    required this.cs,
  });

  final AudioProvider provider;
  final bool timerExpired;
  final bool waitingTrigger;
  final String Function(Duration) fmtDuration;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final remaining = provider.timerRemaining ?? Duration.zero;
    final modeLabel = waitingTrigger
        ? i18n.tr('wait_play_trigger')
        : provider.timerMode == TimerMode.manual
        ? i18n.tr('manual_start')
        : i18n.tr('auto_start_after_play');
    final title = timerExpired
        ? i18n.tr('countdown_finished')
        : waitingTrigger
        ? i18n.tr('waiting_to_start_countdown')
        : i18n.tr('counting_down');
    final accent = timerExpired
        ? cs.error
        : waitingTrigger
        ? cs.onSurfaceVariant
        : cs.primary;
    final timeColor = timerExpired
        ? cs.error
        : waitingTrigger
        ? cs.onSurface
        : cs.onPrimaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: timerExpired
              ? [cs.errorContainer, cs.errorContainer.withValues(alpha: 0.6)]
              : waitingTrigger
              ? [
                  cs.surfaceContainerHighest,
                  cs.surfaceContainerHighest.withValues(alpha: 0.82),
                ]
              : [
                  cs.primaryContainer,
                  cs.primaryContainer.withValues(alpha: 0.62),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: timerExpired
              ? cs.error.withValues(alpha: 0.4)
              : waitingTrigger
              ? cs.outline.withValues(alpha: 0.5)
              : cs.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            timerExpired
                ? Icons.alarm_off_rounded
                : waitingTrigger
                ? Icons.schedule_rounded
                : Icons.timer_rounded,
            size: 36,
            color: accent,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: accent,
              fontWeight: FontWeight.w600,
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
              color: timeColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: timerExpired
                  ? cs.error.withValues(alpha: 0.12)
                  : waitingTrigger
                  ? cs.outline.withValues(alpha: 0.12)
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
                  color: accent,
                ),
                const SizedBox(width: 4),
                Text(modeLabel, style: TextStyle(fontSize: 12, color: accent)),
              ],
            ),
          ),
          if (timerExpired && provider.pausedByTimerPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              i18n.tr('paused_audio_count', {
                'count': provider.pausedByTimerPaths.length,
              }),
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ],
          if (timerExpired && provider.autoResumeEnabled) ...[
            const SizedBox(height: 4),
            Text(
              i18n.tr('auto_resume_at', {
                'time':
                    '${provider.autoResumeHour.toString().padLeft(2, '0')}:${provider.autoResumeMinute.toString().padLeft(2, '0')}',
              }),
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ],
        ],
      ),
    );
  }
}

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
    final i18n = context.watch<AppLanguageProvider>();
    final cs = Theme.of(context).colorScheme;

    Widget picker(
      String label,
      int value,
      int max,
      void Function(int) onChange,
    ) {
      return Expanded(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value,
                  isExpanded: true,
                  alignment: Alignment.center,
                  icon: const Icon(Icons.expand_more_rounded, size: 20),
                  iconEnabledColor: cs.onSurfaceVariant,
                  menuMaxHeight: 280,
                  borderRadius: BorderRadius.circular(12),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  items: List.generate(max + 1, (i) => i)
                      .map(
                        (v) => DropdownMenuItem(
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
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChange(v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        picker(
          i18n.tr('hour'),
          hours,
          5,
          (v) => onChanged(v, minutes, seconds),
        ),
        const SizedBox(width: 4),
        Center(
          child: Text(
            ':',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 4),
        picker(
          i18n.tr('minute'),
          minutes,
          59,
          (v) => onChanged(hours, v, seconds),
        ),
        const SizedBox(width: 4),
        Center(
          child: Text(
            ':',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 4),
        picker(
          i18n.tr('second'),
          seconds,
          59,
          (v) => onChanged(hours, minutes, v),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});

  final TimerMode value;
  final ValueChanged<TimerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final cs = Theme.of(context).colorScheme;

    Widget modeCard(
      TimerMode mode,
      String title,
      String subtitle,
      IconData icon,
    ) {
      final selected = value == mode;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
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
              const SizedBox(width: 8),
              Icon(
                icon,
                size: 20,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? cs.primary : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
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
          i18n.tr('manual_start'),
          i18n.tr('manual_start_subtitle'),
          Icons.play_circle_outline_rounded,
        ),
        modeCard(
          TimerMode.trigger,
          i18n.tr('auto_start_after_play'),
          i18n.tr('trigger_start_subtitle'),
          Icons.sensors_rounded,
        ),
      ],
    );
  }
}
