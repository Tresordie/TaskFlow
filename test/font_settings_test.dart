import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/providers/font_provider.dart';

/// Regression tests for the v1.4.22 font settings rework:
///  - the preset list drops Latin-only / mono / display fonts and adds
///    CJK-capable families for crisp mixed Chinese + English rendering;
///  - the new global font-weight provider defaults to Regular, persists its
///    choice, and exposes exactly the four curated weight options.
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

    test('adds CJK-capable fonts for mixed CN/EN rendering', () {
      final families = AppFonts.presets.map((f) => f.fontFamily).toSet();
      expect(families.contains('Noto Sans SC'), isTrue);
      expect(families.contains('Noto Serif SC'), isTrue);
      expect(families.contains('LXGW WenKai TC'), isTrue);
    });

    test('every preset id is unique and non-empty', () {
      final ids = AppFonts.presets.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id.isNotEmpty, isTrue);
      }
    });
  });

  group('FontWeightNotifier', () {
    test('defaults to Regular (w400)', () {
      SharedPreferences.setMockInitialValues({});
      final n = FontWeightNotifier();
      expect(n.state.weight, FontWeight.w400);
      expect(n.state.id, 'regular');
    });

    test('exposes exactly four ordered weight options', () {
      expect(FontWeightNotifier.options.length, 4);
      expect(
        FontWeightNotifier.options.map((o) => o.weight).toList(),
        [FontWeight.w300, FontWeight.w400, FontWeight.w500, FontWeight.w600],
      );
    });

    test('setWeight changes state and reset returns to Regular', () {
      SharedPreferences.setMockInitialValues({});
      final n = FontWeightNotifier();
      n.setWeight(FontWeightNotifier.options[3]); // semi-bold
      expect(n.state.weight, FontWeight.w600);
      n.reset();
      expect(n.state.weight, FontWeight.w400);
    });

    test('restores a persisted weight index', () async {
      SharedPreferences.setMockInitialValues({'settings.fontWeight': 2});
      final n = FontWeightNotifier();
      // _restore() runs asynchronously right after construction.
      await Future<void>.delayed(Duration.zero);
      expect(n.state.weight, FontWeight.w500);
    });

    test('ignores an out-of-range persisted index', () async {
      SharedPreferences.setMockInitialValues({'settings.fontWeight': 99});
      final n = FontWeightNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state.weight, FontWeight.w400);
    });
  });
}
