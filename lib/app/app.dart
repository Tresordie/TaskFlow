import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/font_stack.dart';
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
      //
      // NOTE: text selection (SelectionArea) must NOT be installed here —
      // this builder sits ABOVE the Navigator's Overlay, and SelectionArea
      // builds a SelectableRegion that requires an Overlay ancestor (it
      // throws in debug and silently breaks selection in release). The
      // single app-wide SelectionArea lives in AppShell instead (v1.4.25).
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
      var textTheme = _googleFontTextTheme(family, theme.textTheme);
      // v1.4.99: Chinese-English pairing — the paired CJK family becomes
      // the FIRST fallback on every style, so Latin renders in the Latin
      // face and CJK glyphs fall through to the paired Chinese face.
      if (font.cjkFamily != null) {
        _ensureCjkFontLoaded(font.cjkFamily!);
        textTheme = _applyCjkFallback(textTheme, family, font.cjkFamily!);
      }
      return theme.copyWith(textTheme: textTheme);
    }

    // Bundled / system font (v1.5.2): apply the family to every text
    // style, and for pairing presets attach the CJK fallback chain —
    // setting fontFamily alone is forbidden where Chinese may render.
    var textTheme = theme.textTheme.apply(fontFamily: family);
    if (font.cjkFamily != null) {
      textTheme = _applyCjkFallback(textTheme, family, font.cjkFamily!);
    }
    return theme.copyWith(textTheme: textTheme);
  }

  /// v1.4.99: triggers the google_fonts download/registration of a paired
  /// CJK family. Once loaded the family name resolves everywhere, so plain
  /// fontFamilyFallback entries work. MiSans needs no download — it is
  /// either bundled as an asset font or installed on the system.
  void _ensureCjkFontLoaded(String family) {
    switch (family) {
      case 'Noto Sans SC':
        GoogleFonts.notoSansSc();
      case 'Noto Serif SC':
        GoogleFonts.notoSerifSc();
      case 'LXGW WenKai TC':
        GoogleFonts.lxgwWenKaiTc();
      default:
        break;
    }
  }

  /// Sets fontFamily + the shared pairing fallback chain (paired CJK
  /// family first, bundled safety nets + emoji owner after) on every text
  /// style (v1.5.2: chain centralized in FontStack).
  TextTheme _applyCjkFallback(TextTheme t, String latin, String cjkFamily) {
    final fb = FontStack.pairingFallback(cjkFamily);
    TextStyle? fix(TextStyle? s) =>
        s?.copyWith(fontFamily: latin, fontFamilyFallback: fb);
    return t.copyWith(
      displayLarge: fix(t.displayLarge),
      displayMedium: fix(t.displayMedium),
      displaySmall: fix(t.displaySmall),
      headlineLarge: fix(t.headlineLarge),
      headlineMedium: fix(t.headlineMedium),
      headlineSmall: fix(t.headlineSmall),
      titleLarge: fix(t.titleLarge),
      titleMedium: fix(t.titleMedium),
      titleSmall: fix(t.titleSmall),
      bodyLarge: fix(t.bodyLarge),
      bodyMedium: fix(t.bodyMedium),
      bodySmall: fix(t.bodySmall),
      labelLarge: fix(t.labelLarge),
      labelMedium: fix(t.labelMedium),
      labelSmall: fix(t.labelSmall),
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
      case 'Poppins':
        return GoogleFonts.poppinsTextTheme(base);
      case 'Lora':
        return GoogleFonts.loraTextTheme(base);
      case 'Nunito':
        return GoogleFonts.nunitoTextTheme(base);
      // v1.7.0: register the new pairing presets…
      case 'Inter':
        return GoogleFonts.interTextTheme(base);
      case 'Plus Jakarta Sans':
        return GoogleFonts.plusJakartaSansTextTheme(base);
      case 'Lexend':
        return GoogleFonts.lexendTextTheme(base);
      // …and fix the v1.6.0 pairings whose download branches were missing.
      case 'IBM Plex Sans':
        return GoogleFonts.ibmPlexSansTextTheme(base);
      case 'Outfit':
        return GoogleFonts.outfitTextTheme(base);
      default:
        return base;
    }
  }
}

/// Desktop [ScrollBehavior]: wheel / trackpad / touch scroll as usual, but
/// mouse drag is deliberately NOT a scroll device (v1.4.26). Under the
/// app-wide SelectionArea a mouse drag means text selection (block select
/// + copy); if scrollables also claimed vertical mouse drags they would
/// win the gesture arena and scroll the list instead of selecting. This
/// mirrors the standard desktop model (browsers, editors): mouse drag =
/// select, wheel = scroll.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
