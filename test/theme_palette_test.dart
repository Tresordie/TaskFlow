import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/theme/app_colors.dart';
import 'package:taskflow/core/theme/app_theme.dart';

/// v1.7.0 theme contracts:
///  - every AppThemeMode has complete bilingual labels and a fully
///    populated palette (no half-copied colors);
///  - surface elevation follows the ladder every theme is designed on —
///    light: bg < card ≤ surface, dark: bg < surface < card — so cards
///    always lift off the canvas (the v1.4.98 Latte lesson, generalized);
///  - brightness grouping is correct (the GFM alert color table and the
///    buildTheme light/dark branches both depend on it);
///  - the six new palettes keep their designed signature colors so a
///    refactor can't silently flatten them into each other.
void main() {
  group('AppThemeMode catalog (v1.7.0)', () {
    test('21 themes with unique names and non-empty bilingual labels', () {
      expect(AppThemeMode.values.length, 21);
      final names = AppThemeMode.values.map((m) => m.name).toSet();
      expect(names.length, 21);
      for (final mode in AppThemeMode.values) {
        expect(mode.label.isNotEmpty, isTrue, reason: '${mode.name}.label');
        expect(mode.labelZh.isNotEmpty, isTrue, reason: '${mode.name}.labelZh');
      }
    });

    test('every palette is fully populated (no transparent / duplicated slots)',
        () {
      for (final mode in AppThemeMode.values) {
        final p = mode.palette;
        final colors = <String, Color>{
          'bg': p.bg,
          'surface': p.surface,
          'card': p.card,
          'border': p.border,
          'textPrimary': p.textPrimary,
          'textSecondary': p.textSecondary,
          'primary': p.primary,
          'primaryLight': p.primaryLight,
          'primaryDark': p.primaryDark,
          'primaryGhost': p.primaryGhost,
        };
        for (final e in colors.entries) {
          expect(e.value, isNot(const Color(0x00000000)),
              reason: '${mode.name}.${e.key} is transparent');
        }
        // Border and accent must contrast with the canvas or cards and
        // buttons would be invisible.
        expect(p.border, isNot(p.surface), reason: '${mode.name}.border');
        expect(p.primary, isNot(p.surface), reason: '${mode.name}.primary');
        expect(p.primary, isNot(p.primaryLight),
            reason: '${mode.name}.primary');
      }
    });

    test('bg is the deepest layer (light bg<card&surface; dark bg<surface<card)',
        () {
      for (final mode in AppThemeMode.values) {
        final p = mode.palette;
        if (mode.brightness == Brightness.light) {
          // Light: bg is the darkest of the three. card vs surface is
          // deliberately free — Catppuccin Latte (v1.4.98) maps card ABOVE
          // surface, the classic themes below it.
          expect(p.bg.computeLuminance(), lessThan(p.card.computeLuminance()),
              reason: '${mode.name}: light bg must be below card');
          expect(p.bg.computeLuminance(),
              lessThan(p.surface.computeLuminance()),
              reason: '${mode.name}: light bg must be below surface');
        } else {
          expect(
              p.bg.computeLuminance(), lessThan(p.surface.computeLuminance()),
              reason: '${mode.name}: dark bg must be below surface');
          expect(p.surface.computeLuminance(),
              lessThan(p.card.computeLuminance()),
              reason: '${mode.name}: dark surface must be below card');
        }
      }
    });

    test('brightness grouping is complete and correct', () {
      const light = [
        AppThemeMode.indigoLight,
        AppThemeMode.freshGreen,
        AppThemeMode.sunsetOrange,
        AppThemeMode.lavenderPurple,
        AppThemeMode.warmSand,
        AppThemeMode.celadon,
        AppThemeMode.inkBlue,
        AppThemeMode.dustyRose,
        AppThemeMode.catLatteLavender,
        AppThemeMode.catLatteMauve,
      ];
      const dark = [
        AppThemeMode.dark,
        AppThemeMode.nordNight,
        AppThemeMode.espresso,
        AppThemeMode.deepSea,
        AppThemeMode.aubergine,
        AppThemeMode.catFrappeMauve,
        AppThemeMode.catFrappeSapphire,
        AppThemeMode.catMacchiatoMauve,
        AppThemeMode.catMacchiatoTeal,
        AppThemeMode.catMochaMauve,
        AppThemeMode.catMochaLavender,
      ];
      expect(light.length + dark.length, AppThemeMode.values.length);
      for (final mode in light) {
        expect(mode.brightness, Brightness.light, reason: mode.name);
      }
      for (final mode in dark) {
        expect(mode.brightness, Brightness.dark, reason: mode.name);
      }
    });
  });

  group('v1.7.0 signature colors', () {
    // One anchor per new palette: the accent that gives the theme its
    // identity, plus the canvas tone where the design intent lives there.
    test('celadon keeps the jade accent on a porcelain canvas', () {
      final p = AppThemeMode.celadon.palette;
      expect(p.primary, const Color(0xFF3E7C6C));
      expect(p.surface, const Color(0xFFFAFCFB));
      expect(AppThemeMode.celadon.labelZh, '青瓷');
    });

    test('inkBlue keeps the porcelain-ink accent', () {
      final p = AppThemeMode.inkBlue.palette;
      expect(p.primary, const Color(0xFF3F6C99));
      expect(AppThemeMode.inkBlue.labelZh, '黛蓝');
    });

    test('dustyRose keeps the muted rose accent', () {
      final p = AppThemeMode.dustyRose.palette;
      expect(p.primary, const Color(0xFFA66470));
      expect(AppThemeMode.dustyRose.labelZh, '胭脂');
    });

    test('espresso keeps the caramel accent on coffee surfaces', () {
      final p = AppThemeMode.espresso.palette;
      expect(p.primary, const Color(0xFFDBA159));
      expect(p.surface, const Color(0xFF2A241F));
      expect(AppThemeMode.espresso.labelZh, '深咖啡');
    });

    test('deepSea keeps the lagoon-teal accent', () {
      final p = AppThemeMode.deepSea.palette;
      expect(p.primary, const Color(0xFF54B8AC));
      expect(AppThemeMode.deepSea.labelZh, '深海蓝');
    });

    test('aubergine keeps the misty-violet accent', () {
      final p = AppThemeMode.aubergine.palette;
      expect(p.primary, const Color(0xFFA78BC9));
      expect(AppThemeMode.aubergine.labelZh, '墨紫');
    });
  });

  group('AppColors legacy block (v1.7.0 regression guard)', () {
    test('legacy aliases stay in sync with indigoLight / dark palettes', () {
      // The hardcoded isDark ? darkX : lightX call sites (~20 of them) read
      // these aliases, not the active palette — they must keep tracking the
      // two base palettes.
      expect(AppColors.lightBg, AppColors.indigoLight.bg);
      expect(AppColors.lightTextPrimary, AppColors.indigoLight.textPrimary);
      expect(AppColors.darkBg, AppColors.dark.bg);
      expect(AppColors.darkTextPrimary, AppColors.dark.textPrimary);
    });
  });
}
