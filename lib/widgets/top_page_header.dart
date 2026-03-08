import 'package:flutter/material.dart';

class TopPageHeader extends StatelessWidget {
  const TopPageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.titleSuffix,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
    this.bottomSpacing = 20,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget? titleSuffix;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: cs.primaryContainer.withValues(alpha: 0.9),
                ),
                child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
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
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (titleSuffix != null) ...[
                          const SizedBox(width: 8),
                          titleSuffix!,
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
          SizedBox(height: bottomSpacing),
        ],
      ),
    );
  }
}
