import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/utils/bidi_utils.dart';

void main() {
  group('BidiUtils Tests', () {
    test('Detects RTL Hebrew text correctly', () {
      expect(BidiUtils.isRtl('שלום עולם'), isTrue);
      expect(BidiUtils.isRtl('טייק אחד - פרק 11'), isTrue);
      expect(BidiUtils.isRtl('שיחות מהבגאז׳'), isTrue);
    });

    test('Detects LTR English text correctly', () {
      expect(BidiUtils.isRtl('The Daily Podcast'), isFalse);
      expect(BidiUtils.isRtl('Episode 142 - Technology News'), isFalse);
    });

    test('Handles mixed text with dominant RTL', () {
      expect(BidiUtils.isRtl('פרק 42: Podcast Merlin Rebooted'), isTrue);
    });

    test('Handles mixed text with dominant LTR', () {
      expect(BidiUtils.isRtl('Episode 42: פרק מיוחד'), isFalse);
    });

    test('Handles empty and null strings safely', () {
      expect(BidiUtils.isRtl(null), isFalse);
      expect(BidiUtils.isRtl(''), isFalse);
      expect(BidiUtils.isRtl('   '), isFalse);
    });

    test('Returns correct TextDirection', () {
      expect(BidiUtils.getDirection('שלום'), equals(TextDirection.rtl));
      expect(BidiUtils.getDirection('Hello'), equals(TextDirection.ltr));
    });

    test('Returns correct TextAlign', () {
      expect(BidiUtils.getAlignment('שלום'), equals(TextAlign.right));
      expect(BidiUtils.getAlignment('Hello'), equals(TextAlign.left));
      expect(BidiUtils.getAlignment('שלום', fallback: TextAlign.center), equals(TextAlign.center));
    });

    test('Isolates BiDi Unicode characters properly', () {
      final isolatedRtl = BidiUtils.isolateBidi('שלום?');
      expect(isolatedRtl.startsWith('\u2067'), isTrue);
      expect(isolatedRtl.endsWith('\u2069'), isTrue);

      final isolatedLtr = BidiUtils.isolateBidi('Hello!');
      expect(isolatedLtr.startsWith('\u2066'), isTrue);
      expect(isolatedLtr.endsWith('\u2069'), isTrue);
    });
  });
}
