import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/theme/app_colors.dart';
import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/presentation/shared/glass_sheen.dart';
import 'package:taskflow/presentation/shared/timeline_rail.dart';
import 'package:taskflow/providers/board_card_style_provider.dart';

/// v1.12.42 light-theme contrast pass (user: 浅色主题的 GUI 预览效果很差，
/// 尤其是暖沙和黛蓝；深色主题没问题).
///
/// The light palettes were never the problem — the *rendering* was: a dark-first
/// glass recipe left a 72% white card on a 96% white canvas, a 14% white
/// specular wash fogged it further, card hairlines ran at 30% outline,
/// struck-through titles at 40% ink, and `ColorScheme.secondary` carried the
/// pale `primaryLight` accent that is a fine highlight on a dark board and
/// unreadable text on paper. Every rule below pins one of those regressions
/// with a measured WCAG ratio, so the light themes cannot drift back to haze.
void main() {
  const lightThemes = [AppThemeMode.warmSand, AppThemeMode.inkBlue];

  /// WCAG 2.1 contrast ratio between two opaque colors.
  double contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// `fg` (carrying its own alpha) composited over an opaque `bg`.
  Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

  group('light theme ink is measurable, not vibes', () {
    for (final mode in lightThemes) {
      final theme = AppTheme.buildTheme(mode);
      final cs = theme.colorScheme;
      final card = theme.cardTheme.color ?? cs.surface;

      test('$mode: body ink clears AAA on canvas and card', () {
        expect(contrast(cs.onSurface, cs.surface), greaterThanOrEqualTo(7.0),
            reason: '${mode.name}: ink on the panel surface');
        expect(contrast(cs.onSurface, card), greaterThanOrEqualTo(7.0),
            reason: '${mode.name}: ink on a card');
      });

      test('$mode: secondary ink and the accent stay readable', () {
        expect(contrast(cs.secondary, card), greaterThanOrEqualTo(4.5),
            reason: '${mode.name}: secondary labels / icons on a card');
        expect(contrast(cs.primary, cs.surface), greaterThanOrEqualTo(3.0),
            reason: '${mode.name}: accent stays visible on the surface');
      });

      test('$mode: a struck-through title is still readable', () {
        final struck = over(
            cs.onSurface
                .withOpacity(AppColors.dimmedTitleOpacity(cs.brightness)),
            card);
        expect(contrast(struck, card), greaterThanOrEqualTo(4.5),
            reason: '${mode.name}: completed / archived titles');
      });

      test('$mode: muted and faint text stay inside budget', () {
        final muted = over(
            cs.onSurface.withOpacity(AppColors.mutedTextOpacity(cs.brightness)),
            card);
        expect(contrast(muted, card), greaterThanOrEqualTo(4.5),
            reason: '${mode.name}: dates, counts, hints');
        final faint = over(
            cs.onSurface.withOpacity(AppColors.faintTextOpacity(cs.brightness)),
            card);
        expect(contrast(faint, card), greaterThanOrEqualTo(3.0),
            reason: '${mode.name}: placeholders, empty states');
      });

      test('$mode: the card hairline separates it from the canvas', () {
        final hairline = over(
            cs.outline.withOpacity(AppColors.cardBorderOpacity(cs.brightness)),
            card);
        expect(contrast(hairline, cs.surface), greaterThan(1.10),
            reason: '${mode.name}: an invisible edge is no edge at all');
      });
    }

    test('the light rules are stricter than the dark rules', () {
      // That is the whole point of the split: one alpha, two meanings.
      expect(AppColors.dimmedTitleOpacity(Brightness.light),
          greaterThan(AppColors.dimmedTitleOpacity(Brightness.dark)));
      expect(AppColors.mutedTextOpacity(Brightness.light),
          greaterThan(AppColors.mutedTextOpacity(Brightness.dark)));
      expect(AppColors.cardBorderOpacity(Brightness.light),
          greaterThan(AppColors.cardBorderOpacity(Brightness.dark)));
    });
  });

  group('glass that works on paper', () {
    test('a paper card keeps a firmer fill than a dark one', () {
      expect(BoardCardStyle.iosGlassDefaultOpacityLight,
          greaterThan(BoardCardStyle.iosGlassDefaultOpacity));
      expect(BoardGlassSpec.panelOpacityFloorLight,
          greaterThan(BoardGlassSpec.panelOpacityFloor));
    });

    test('the specular wash fades on light themes', () {
      expect(GlassSheen.topAlphaFor(Brightness.light),
          lessThan(GlassSheen.topAlphaFor(Brightness.dark)),
          reason: 'white on white is haze, not glass');
      expect(GlassSheen.bottomAlphaFor(Brightness.light),
          lessThanOrEqualTo(GlassSheen.bottomAlphaFor(Brightness.dark)));
    });

    test('fillOver follows the brightness it is handed', () {
      final base = Colors.white.withOpacity(0.92);
      final light = GlassSheen.fillOver(base, brightness: Brightness.light);
      final dark = GlassSheen.fillOver(base, brightness: Brightness.dark);
      expect(light.colors.first.opacity, lessThan(dark.colors.first.opacity));
      expect(light.colors[1], base, reason: 'the mid stop stays the pure fill');
    });
  });

  group('timeline spine on paper', () {
    testWidgets('the spine renders no channel at all', (tester) async {
      // v1.12.42 killed the near-white blob, v1.12.43 the stroke, v1.12.45 the
      // recess itself: a wide pale pillar per row is exactly what the user kept
      // calling 外框. The rail is now line + node, so nothing in it may be as
      // wide as the old channel, and nothing may be stroked.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.buildTheme(AppThemeMode.inkBlue),
        home: const Scaffold(
          body: SizedBox(
            height: 200,
            child: TimelineRail(
              node: SizedBox.shrink(),
              accentColor: Color(0xFF3F6C99),
            ),
          ),
        ),
      ));

      const channelWidth =
          26.0; // the default TimelineRail.grooveWidth - the old pillar
      for (final box in tester.widgetList<Container>(find.byType(Container))) {
        final maxW = box.constraints?.maxWidth ?? -1;
        expect(maxW < channelWidth, isTrue,
            reason: 'a box as wide as the old channel came back ($maxW)');
        final d = box.decoration;
        expect(d is BoxDecoration && d.border != null, isFalse,
            reason: 'an outline came back');
      }
      expect(find.byType(TimelineSpine), findsNWidgets(2));
    });
  });

  group('user-picked accents stay readable (v1.12.42)', () {
    test('a pastel project colour is pushed to AA on a white card', () {
      const pastel = Color(0xFFF8BBD0); // the board’s “Metro” pink
      const surface = Color(0xFFFFFFFF);
      expect(AppColors.contrast(pastel, surface), lessThan(4.5),
          reason: 'the fixture must be the unreadable case');
      final ink = AppColors.legibleInk(pastel, surface);
      expect(AppColors.contrast(ink, surface), greaterThanOrEqualTo(4.5));
      expect(ink, isNot(pastel));
    });

    test('ink that already clears AA is left alone', () {
      const ink = Color(0xFF2C3A4D);
      expect(AppColors.legibleInk(ink, const Color(0xFFFFFFFF)), ink);
    });

    test('on a dark board the accent is lifted, never darkened', () {
      const surface = Color(0xFF1E1E2E);
      final ink = AppColors.legibleInk(const Color(0xFF3A2A31), surface);
      expect(AppColors.contrast(ink, surface), greaterThanOrEqualTo(4.5));
      expect(ink.computeLuminance(),
          greaterThan(const Color(0xFF3A2A31).computeLuminance()));
    });
  });
}
