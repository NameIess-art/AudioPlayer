import 'package:flutter/material.dart';

class TopPageHeader extends StatelessWidget {
  const TopPageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.titleSuffix,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
    this.bottomSpacing = 20,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget? titleSuffix;
  final String? subtitle;
  final int subtitleMaxLines;
  final EdgeInsetsGeometry padding;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.78),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: cs.primaryContainer,
                  ),
                  child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (titleSuffix != null) ...[
                            const SizedBox(width: 8),
                            titleSuffix!,
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11,
                                height: 1.2,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
          SizedBox(height: bottomSpacing),
        ],
      ),
    );
  }
}
