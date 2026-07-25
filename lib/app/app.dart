import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../providers/font_provider.dart';
import '../app/router.dart';

class TaskFlowApp extends ConsumerWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final font = ref.watch(fontProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final fontWeightValue = ref.watch(fontWeightProvider);

    var theme = AppTheme.buildTheme(themeMode);

    // Apply selected font
    if (font.fontFamily != null) {
      theme = _applyFont(theme, font);
    }

    // Apply the global font-weight preference (v1.4.22, numeric in v1.4.23).
    theme = _applyWeight(theme, FontWeightNotifier.weightFrom(fontWeightValue));

    return MaterialApp.router(
      title: 'TaskFlow',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      // Desktop-friendly scrolling: allow mouse / trackpad drag-scrolling
      // on every list (wheel scrolling stays enabled by default).
      scrollBehavior: AppScrollBehavior(),
      // Apply the global font size scale to every screen.
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  ThemeData _applyFont(ThemeData theme, FontOption font) {
    final family = font.fontFamily!;

    if (font.isGoogleFont) {
      // Download via google_fonts package. IMPORTANT: use the app's own
      // textTheme as the base so AppTheme's custom sizes, weights, colors
      // and letter-spacing are preserved (v1.4.22 fix — previously the
      // Material defaults were used, which made all text thinner and less
      // legible whenever a Google font was selected).
      final textTheme = _googleFontTextTheme(family, theme.textTheme);
      return theme.copyWith(textTheme: textTheme);
    }

    // System font: apply the family to every text style (v1.4.22: was only
    // 7 hand-picked styles before, leaving e.g. bodySmall/labelLarge on the
    // old family and producing inconsistent rendering).
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: family),
    );
  }

  /// Applies the user's global font-weight preference as a uniform delta
  /// relative to Regular (w400), so the whole typographic hierarchy shifts
  /// together — headings always stay heavier than body text.
  ///
  /// Note: we shift each style manually instead of using
  /// `TextStyle.apply(fontWeightDelta:)` because that API asserts when the
  /// style has no explicit fontWeight — and AppTheme's body styles don't.
  ThemeData _applyWeight(ThemeData theme, FontWeight weight) {
    final delta = weight.index - FontWeight.w400.index;
    if (delta == 0) return theme;

    TextStyle? shift(TextStyle? s) {
      if (s == null) return null;
      final base = s.fontWeight ?? FontWeight.w400;
      final index = (base.index + delta).clamp(0, FontWeight.values.length - 1);
      return s.copyWith(fontWeight: FontWeight.values[index]);
    }

    final t = theme.textTheme;
    return theme.copyWith(
      textTheme: t.copyWith(
        displayLarge: shift(t.displayLarge),
        displayMedium: shift(t.displayMedium),
        displaySmall: shift(t.displaySmall),
        headlineLarge: shift(t.headlineLarge),
        headlineMedium: shift(t.headlineMedium),
        headlineSmall: shift(t.headlineSmall),
        titleLarge: shift(t.titleLarge),
        titleMedium: shift(t.titleMedium),
        titleSmall: shift(t.titleSmall),
        bodyLarge: shift(t.bodyLarge),
        bodyMedium: shift(t.bodyMedium),
        bodySmall: shift(t.bodySmall),
        labelLarge: shift(t.labelLarge),
        labelMedium: shift(t.labelMedium),
        labelSmall: shift(t.labelSmall),
      ),
    );
  }

  TextTheme _googleFontTextTheme(String family, TextTheme base) {
    switch (family) {
      case 'Noto Sans SC':
        return GoogleFonts.notoSansScTextTheme(base);
      case 'Noto Serif SC':
        return GoogleFonts.notoSerifScTextTheme(base);
      case 'LXGW WenKai TC':
        return GoogleFonts.lxgwWenKaiTcTextTheme(base);
      case 'Poppins':
        return GoogleFonts.poppinsTextTheme(base);
      default:
        return base;
    }
  }
}

/// Desktop-friendly [ScrollBehavior]: in addition to the default touch drag
/// and mouse-wheel / trackpad scrolling, let every scrollable be scrolled by
/// pressing and dragging with the mouse pointer (or trackpad / stylus).
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
