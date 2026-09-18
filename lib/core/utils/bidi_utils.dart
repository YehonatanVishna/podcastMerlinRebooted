import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Centralized utility for handling bidirectional text, RTL detection,
/// and Unicode directional isolation (Hebrew, Arabic, etc.).
class BidiUtils {
  const BidiUtils._();

  /// Returns true if the dominant script of [text] is Right-to-Left (e.g. Hebrew/Arabic).
  ///
  /// Following Unicode Bidirectional Algorithm Rule P2, the base direction of a paragraph
  /// is determined by the first strongly directional character (skipping neutral and weak characters).
  static bool isRtl(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final clean = Bidi.stripHtmlIfNeeded(text);
    return Bidi.startsWithRtl(clean);
  }

  /// Returns the natural [TextDirection] for [text].
  static TextDirection getDirection(String? text) {
    return isRtl(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  /// Returns the natural [TextAlign] for [text] (Right for RTL, Left for LTR).
  static TextAlign getAlignment(String? text, {TextAlign? fallback}) {
    if (fallback != null && fallback != TextAlign.start) return fallback;
    return isRtl(text) ? TextAlign.right : TextAlign.left;
  }

  /// Wraps an inline string with Unicode isolating formatting characters
  /// (\u2067 RLI ... \u2069 PDI for RTL, or \u2066 LRI ... \u2069 PDI for LTR).
  /// This prevents neutral characters (e.g. '?', '!', '-', '/') from jumping
  /// across boundaries when rendered in mixed contexts.
  static String isolateBidi(String text, {bool? isRtl}) {
    final rtl = isRtl ?? BidiUtils.isRtl(text);
    return rtl ? '\u2067$text\u2069' : '\u2066$text\u2069';
  }
}
