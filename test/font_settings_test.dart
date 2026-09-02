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

  group('AppFonts preset curation (v1.4.22 → v1.8.0 cull)', () {
    test('standalone presets carry no Latin-only / mono / display fonts', () {
      // v1.8.0: the only standalone preset left is 'system' (fontFamily
      // null) — every downloadable font lives in one of the three pairing
      // presets, so this curation rule is trivially satisfied but kept as a
      // guard against reintroducing bare Latin-only options.
      final families = AppFonts.presets
          .where((f) => f.cjkFamily == null)
          .map((f) => f.fontFamily)
          .toSet();
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

    test('v1.8.0: Noto Sans SC exists only as a pairing CJK half', () {
      // v1.8.0 (user request): the standalone Noto Sans SC preset was
      // removed along with the serif/script/ZCOOL options — the family now
      // appears solely as the CJK half of jakartaNoto / lexendNoto.
      final standalone = AppFonts.presets
          .where((f) => f.cjkFamily == null)
          .map((f) => f.fontFamily)
          .toSet();
      expect(standalone.contains('Noto Sans SC'), isFalse);
      final pairingHalves = AppFonts.presets
          .map((f) => f.cjkFamily)
          .whereType<String>()
          .toSet();
      expect(pairingHalves, contains('Noto Sans SC'));
      // The v1.4.24/25 removals stay removed everywhere.
      expect(AppFonts.presets.where((f) => f.fontFamily == 'Noto Serif SC'),
          isEmpty);
      expect(
          AppFonts.presets.where((f) => f.cjkFamily == 'LXGW WenKai TC'),
          isEmpty);
      expect(AppFonts.presets.where((f) => f.fontFamily == 'ZCOOL XiaoWei'),
          isEmpty);
    });

    test('every preset id is unique and non-empty', () {
      final ids = AppFonts.presets.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id.isNotEmpty, isTrue);
      }
    });
  });

  group('AppFonts default font (v1.4.23 → v1.5.2)', () {
    test('defaults to the bundled system stack (Manrope × MiSans)', () {
      // v1.5.2: the default is the SYSTEM preset — ThemeData supplies the
      // bundled Manrope (Latin) + MiSans (CJK) stack, so first launch and
      // offline use never flash unregistered fonts.
      expect(AppFonts.defaultFont.id, 'system');
      expect(AppFonts.defaultFont.fontFamily, isNull);
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
