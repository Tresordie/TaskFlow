import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/providers/font_provider.dart';

/// Regression tests for the font settings:
///  - v1.4.22: preset list drops Latin-only / mono / display fonts and adds
///    CJK-capable families for crisp mixed Chinese + English rendering;
///  - v1.4.23: default font is Noto Sans SC (system/Segoe's CJK fallback —
///    Microsoft YaHei — renders too light), and the global font weight is a
///    numeric 100–900 value with migration from the old 4-option index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppFonts preset curation (v1.4.22)', () {
    test('removed Latin-only / mono / display fonts are gone', () {
      final families = AppFonts.presets.map((f) => f.fontFamily).toSet();
      const removed = [
        'Inter',
        'Roboto',
        'Lato',
        'Montserrat',
        'Merriweather',
        'JetBrains Mono',
        'Source Code Pro',
      ];
      for (final r in removed) {
        expect(families.contains(r), isFalse, reason: '$r should be removed');
      }
    });

    test('v1.4.24/25: serif/regular-script/ZCOOL fonts removed', () {
      final families = AppFonts.presets.map((f) => f.fontFamily).toSet();
      // Removed per user request (v1.4.24: serif + regular script;
      // v1.4.25: ZCOOL families).
      expect(families.contains('Noto Serif SC'), isFalse);
      expect(families.contains('LXGW WenKai TC'), isFalse);
      expect(families.contains('ZCOOL XiaoWei'), isFalse);
      expect(families.contains('ZCOOL QingKe HuangYou'), isFalse);
      // Noto Sans SC stays as the curated mixed CN/EN preset.
      expect(families.contains('Noto Sans SC'), isTrue);
    });

    test('every preset id is unique and non-empty', () {
      final ids = AppFonts.presets.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id.isNotEmpty, isTrue);
      }
    });
  });

  group('AppFonts default font (v1.4.23)', () {
    test('defaults to Noto Sans SC so Chinese is not rendered too light', () {
      expect(AppFonts.defaultFont.id, 'notoSansSC');
      expect(AppFonts.defaultFont.fontFamily, 'Noto Sans SC');
      expect(AppFonts.defaultFont.isGoogleFont, isTrue);
    });
  });

  group('FontWeightNotifier (numeric, v1.4.23)', () {
    test('defaults to 400 (Regular)', () {
      SharedPreferences.setMockInitialValues({});
      final n = FontWeightNotifier();
      expect(n.state, 400);
      expect(n.fontWeight, FontWeight.w400);
    });

    test('weightFrom maps values onto FontWeight', () {
      expect(FontWeightNotifier.weightFrom(100), FontWeight.w100);
      expect(FontWeightNotifier.weightFrom(400), FontWeight.w400);
      expect(FontWeightNotifier.weightFrom(600), FontWeight.w600);
      expect(FontWeightNotifier.weightFrom(900), FontWeight.w900);
    });

    test('setWeight clamps into 100–900 and rounds to the nearest 100', () {
      SharedPreferences.setMockInitialValues({});
      final n = FontWeightNotifier();
      n.setWeight(550);
      expect(n.state, 600); // rounds to nearest hundred
      n.setWeight(5000);
      expect(n.state, 900); // clamps high
      n.setWeight(-50);
      expect(n.state, 100); // clamps low
    });

    test('reset returns to 400', () {
      SharedPreferences.setMockInitialValues({});
      final n = FontWeightNotifier();
      n.setWeight(700);
      expect(n.state, 700);
      n.reset();
      expect(n.state, 400);
    });

    test('restores a persisted numeric weight', () async {
      SharedPreferences.setMockInitialValues({'settings.fontWeight': 500});
      final n = FontWeightNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, 500);
    });

    test('migrates a legacy v1.4.22 index (0–3) to the actual weight',
        () async {
      // Legacy index 2 == Medium (500).
      SharedPreferences.setMockInitialValues({'settings.fontWeight': 2});
      final n = FontWeightNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, 500);
    });

    test('ignores an out-of-range persisted value', () async {
      SharedPreferences.setMockInitialValues({'settings.fontWeight': 5000});
      final n = FontWeightNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, 400);
    });
  });
}
