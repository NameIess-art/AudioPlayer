import 'dart:ui';

import 'package:flutter/material.dart';

class TopGlassPanel extends StatelessWidget {
  const TopGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(10, 10, 10, 10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.65),
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
