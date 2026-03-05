import 'package:flutter/material.dart';
import 'package:text_scroll/text_scroll.dart';

class ScrollingText extends StatelessWidget {
  const ScrollingText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return TextScroll(
      text,
      mode: TextScrollMode.bouncing,
      velocity: const Velocity(pixelsPerSecond: Offset(30, 0)),
      delayBefore: const Duration(seconds: 2),
      pauseBetween: const Duration(seconds: 2),
      style: style,
      textAlign: textAlign ?? TextAlign.left,
      fadedBorder: true,
      fadedBorderWidth: 0.05,
      selectable: false,
    );
  }
}
