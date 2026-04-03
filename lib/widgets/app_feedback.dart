import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppFeedbackTone { info, success, warning, destructive }

OverlayEntry? _activeFeedbackEntry;
Timer? _activeFeedbackTimer;

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppFeedbackTone tone = AppFeedbackTone.info,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 800),
}) {
  _showTopFeedback(
    context,
    message,
    tone: tone,
    icon: icon,
    duration: duration,
  );
}

void showAppToast(
  BuildContext context,
  String message, {
  AppFeedbackTone tone = AppFeedbackTone.info,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 800),
}) {
  _showTopFeedback(
    context,
    message,
    tone: tone,
    icon: icon,
    duration: duration,
  );
}

void _showTopFeedback(
  BuildContext context,
  String message, {
  required AppFeedbackTone tone,
  IconData? icon,
  required Duration duration,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final resolvedIcon = icon ?? _defaultIconForTone(tone);
  HapticFeedback.selectionClick();

  _activeFeedbackTimer?.cancel();
  _activeFeedbackEntry?.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      final topInset = MediaQuery.of(overlayContext).padding.top + 10;

      return Positioned(
        top: topInset,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * -12),
                        child: child,
                      ),
                    );
                  },
                  child: AppFeedbackSurface(
                    tone: tone,
                    icon: resolvedIcon,
                    message: message,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  _activeFeedbackEntry = entry;
  _activeFeedbackTimer = Timer(duration, () {
    if (_activeFeedbackEntry == entry) {
      _activeFeedbackEntry = null;
    }
    entry.remove();
  });
}

class AppFeedbackSurface extends StatelessWidget {
  const AppFeedbackSurface({
    super.key,
    required this.tone,
    required this.icon,
    required this.message,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.borderRadius = 22,
  });

  final AppFeedbackTone tone;
  final IconData icon;
  final String message;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = _accentColor(context, tone);
    final chipBackground = accent.withValues(alpha: 0.08);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface.withValues(alpha: 0.34),
                cs.surfaceContainerHigh.withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: accent.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: chipBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.10)),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null) ...[
                        Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (title != null
                                    ? theme.textTheme.bodyMedium
                                    : theme.textTheme.titleSmall)
                                ?.copyWith(
                                  color: title != null
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                  fontWeight: title != null
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  height: 1.25,
                                ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _accentColor(BuildContext context, AppFeedbackTone tone) {
  final cs = Theme.of(context).colorScheme;
  switch (tone) {
    case AppFeedbackTone.info:
      return cs.primary;
    case AppFeedbackTone.success:
      return Colors.green.shade600;
    case AppFeedbackTone.warning:
      return Colors.orange.shade700;
    case AppFeedbackTone.destructive:
      return cs.error;
  }
}

IconData _defaultIconForTone(AppFeedbackTone tone) {
  switch (tone) {
    case AppFeedbackTone.info:
      return Icons.info_outline_rounded;
    case AppFeedbackTone.success:
      return Icons.check_circle_outline_rounded;
    case AppFeedbackTone.warning:
      return Icons.warning_amber_rounded;
    case AppFeedbackTone.destructive:
      return Icons.delete_outline_rounded;
  }
}
