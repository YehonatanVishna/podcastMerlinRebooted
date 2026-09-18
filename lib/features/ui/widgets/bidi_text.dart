import 'package:flutter/material.dart';
import '../../../core/utils/bidi_utils.dart';

/// An auto-directional [Text] widget that inspects content to dynamically
/// set [textDirection] and [textAlign].
///
/// Ensures correct truncation ellipsis positioning and prevents trailing
/// neutral punctuation ('?', '!', '.') from jumping across the string.
class BidiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool softWrap;

  const BidiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = BidiUtils.isRtl(text);
    final direction = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final alignment = textAlign ?? (isRtl ? TextAlign.right : TextAlign.left);

    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textDirection: direction,
      textAlign: alignment,
      softWrap: softWrap,
    );
  }
}
