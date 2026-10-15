import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/theme/app_colors.dart';
import 'package:taskflow/core/theme/app_theme.dart';

/// v1.7.0 theme contracts (v1.8.0: the three dark additions were removed
/// again per user request — 18 themes remain):
///  - every AppThemeMode has complete bilingual labels and a fully
///    populated palette (no half-copied colors);
///  - surface elevation follows the ladder every theme is designed on —
///    light: bg < card ≤ surface, dark: bg < surface < card — so cards
///    always lift off the canvas (the v1.4.98 Latte lesson, generalized);
///  - brightness grouping is correct (the GFM alert color table and the
///    buildTheme light/dark branches both depend on it);
///  - the four kept light palettes carry their designed signature colors
///    so a refactor can't silently flatten them into each other.
void main() {
  group('AppThemeMode catalog (v1.7.0, trimmed v1.8.0 / v1.12.17 / v1.12.36 / v1.12.37)',
      () {
    test('11 themes with unique names and non-empty bilingual labels', () {
      expect(AppThemeMode.values.length, 11);
      final names = AppThemeMode.values.map((m) => m.name).toSet();
      expect(names.length, 11);
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
        AppThemeMode.warmSand,
        AppThemeMode.inkBlue,
        AppThemeMode.tealSky,
        AppThemeMode.violetDusk,
      ];
      const dark = [
        AppThemeMode.dark,
        AppThemeMode.nordNight,
        AppThemeMode.notionBoard,
        AppThemeMode.midnightBoard,
        AppThemeMode.catMochaMauve,
        AppThemeMode.catMochaLavender,
        AppThemeMode.glassDashboard,
      ];
      expect(light.length + dark.length, AppThemeMode.values.length);
      for (final mode in light) {
        expect(mode.brightness, Brightness.light, reason: mode.name);
      }
      for (final mode in dark) {
        expect(mode.brightness, Brightness.dark, reason: mode.name);
      }
    });

    // Deleted themes must STAY deleted: the selection persists by enum name,
    // and an unknown stored value falls back to the default (inkBlue), so a
    // resurrected enum slot would silently re-adopt an old user choice — and a
    // re-added one would reappear in Settings without anyone asking.
    test('removed themes stay removed', () {
      const removed = [
        // v1.4.98 / v1.4.99 era
        'blueDark', 'greenDark', 'oceanBlue', 'orangeDark', 'pinkDark',
        'purpleDark', 'sakuraPink',
        // v1.8.0
        'aubergine', 'deepSea', 'espresso',
        // v1.12.17 (11 light themes the user named)
        'celadon', 'dustyRose', 'freshGreen', 'indigoLight', 'lavenderPurple',
        'sunsetOrange',
        // v1.12.17: both Catppuccin Latte (light) flavours
        'catLatteMauve', 'catLatteLavender',
        // v1.12.30
        'frostedGlass',
        // v1.12.36 (Frappé)
        'catFrappeMauve', 'catFrappeSapphire',
        // v1.12.37 (Macchiato)
        'catMacchiatoMauve', 'catMacchiatoTeal',
      ];
      final names = AppThemeMode.values.map((m) => m.name).toSet();
      for (final gone in removed) {
        expect(names, isNot(contains(gone)), reason: '$gone was deleted');
      }
    });
  });

  group('v1.7.0 signature colors (trimmed v1.8.0 + v1.12.17)', () {
    // One anchor per kept palette: the accent that gives the theme its
    // identity, plus the canvas tone where the design intent lives there.
    test('inkBlue keeps the porcelain-ink accent', () {
      final p = AppThemeMode.inkBlue.palette;
      expect(p.primary, const Color(0xFF3F6C99));
      expect(AppThemeMode.inkBlue.labelZh, '黛蓝');
    });

    // v1.12.51: the third light hue. Locked so a refactor can't flatten it
    // into warmSand (umber) or inkBlue (navy), and so its teal identity —
    // the whole reason it exists — survives.
    // v1.12.55: the canvas lock moved to the light family's shared neutral
    // base (F4F5F7) — every light theme now stands on the same neutral page
    // and differs by accent, ghost and ink.
    test('tealSky keeps the serene teal accent + shared neutral canvas', () {
      final p = AppThemeMode.tealSky.palette;
      expect(p.primary, const Color(0xFF2E7D6B));
      expect(p.bg, const Color(0xFFF4F5F7));
      expect(AppThemeMode.tealSky.labelZh, '碧落');
      expect(AppThemeMode.tealSky.brightness, Brightness.light);
      // Joins the polished light glass dashboard (frost trays + glass cards).
      expect(AppThemeMode.tealSky.boardGlass, isTrue);
      expect(AppThemeMode.tealSky.boardTinted, isTrue);
    });

    // v1.12.52: the fourth light hue, from the user's web-dashboard
    // reference. Locked so a refactor can't flatten it into the other three
    // lights — and so it stays the deep amethyst, never drifting back toward
    // the candy lavender pruned in v1.12.17. v1.12.53: the canvas lock moved
    // to the neutral base (F4F5F7) — the theme's identity is its accent, not
    // a violet wash.
    test('violetDusk keeps the deep amethyst accent + neutral canvas', () {
      final p = AppThemeMode.violetDusk.palette;
      expect(p.primary, const Color(0xFF6755C9));
      expect(p.bg, const Color(0xFFF4F5F7));
      expect(AppThemeMode.violetDusk.labelZh, '暮紫');
      expect(AppThemeMode.violetDusk.brightness, Brightness.light);
      // Joins the polished light glass dashboard (frost trays + glass cards).
      expect(AppThemeMode.violetDusk.boardGlass, isTrue);
      expect(AppThemeMode.violetDusk.boardTinted, isTrue);
    });

    test('notionBoard keeps the near-black kanban palette', () {
      final p = AppThemeMode.notionBoard.palette;
      expect(p.primary, const Color(0xFF2383E2));
      expect(p.bg, const Color(0xFF0E0E0E));
      expect(AppThemeMode.notionBoard.labelZh, '墨板');
    });

    test('midnightBoard keeps the cool slate with deep green', () {
      final p = AppThemeMode.midnightBoard.palette;
      expect(p.primary, const Color(0xFF4E8A67));
      expect(p.bg, const Color(0xFF101317));
      expect(AppThemeMode.midnightBoard.labelZh, '午夜看板');
    });

    test('glassDashboard keeps the warm-charcoal + cream reference palette',
        () {
      final p = AppThemeMode.glassDashboard.palette;
      expect(p.primary, const Color(0xFFEFE9DA));
      expect(p.bg, const Color(0xFF2E2B28));
      expect(AppThemeMode.glassDashboard.labelZh, '奶油玻璃');
      expect(AppThemeMode.glassDashboard.brightness, Brightness.dark);
    });
  });

  group('onPrimary contract (v1.12.27)', () {
    test('default palettes stay white-on-accent; cream carries dark text',
        () {
      for (final mode in AppThemeMode.values) {
        final p = mode.palette;
        if (mode == AppThemeMode.glassDashboard) {
          // Cream accent → dark charcoal foreground (readable on cream).
          expect(p.onPrimary.computeLuminance(), lessThan(0.2),
              reason: 'glassDashboard.onPrimary must be dark');
          expect(p.primary.computeLuminance(), greaterThan(0.6),
              reason: 'glassDashboard.primary must stay light (cream)');
        } else {
          // Every pre-existing palette keeps the white convention.
          expect(p.onPrimary, Colors.white, reason: '${mode.name}.onPrimary');
        }
      }
    });

    test('buildTheme wires palette.onPrimary into the color scheme', () {
      final theme =
          AppTheme.buildTheme(AppThemeMode.glassDashboard);
      expect(theme.colorScheme.onPrimary,
          AppThemeMode.glassDashboard.palette.onPrimary);
      final fg = theme.elevatedButtonTheme.style?.foregroundColor;
      expect(fg?.resolve(const {}),
          AppThemeMode.glassDashboard.palette.onPrimary);
    });
  });

  group('AppColors legacy block (v1.7.0 regression guard)', () {
    test('legacy aliases stay in sync with inkBlue / dark palettes', () {
      // The hardcoded isDark ? darkX : lightX call sites (~20 of them) read
      // these aliases, not the active palette — they must keep tracking the
      // two base palettes. v1.12.17: the light anchor moved from the
      // deleted indigoLight to the kept inkBlue.
      expect(AppColors.lightBg, AppColors.inkBlue.bg);
      expect(AppColors.lightTextPrimary, AppColors.inkBlue.textPrimary);
      expect(AppColors.darkBg, AppColors.dark.bg);
      expect(AppColors.darkTextPrimary, AppColors.dark.textPrimary);
    });
  });
}
