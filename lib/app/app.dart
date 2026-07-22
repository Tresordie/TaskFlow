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

    var theme = AppTheme.buildTheme(themeMode);

    // Apply selected font
    if (font.fontFamily != null) {
      theme = _applyFont(theme, font);
    }

    return MaterialApp.router(
      title: 'TaskFlow',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
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
      // Download via google_fonts package
      final textTheme = _googleFontTextTheme(family, theme.brightness);
      return theme.copyWith(textTheme: textTheme);
    }

    // System font: apply fontFamily directly to all text styles
    final base = theme.textTheme;
    return theme.copyWith(
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.copyWith(fontFamily: family),
        headlineMedium: base.headlineMedium?.copyWith(fontFamily: family),
        titleLarge: base.titleLarge?.copyWith(fontFamily: family),
        titleMedium: base.titleMedium?.copyWith(fontFamily: family),
        bodyLarge: base.bodyLarge?.copyWith(fontFamily: family),
        bodyMedium: base.bodyMedium?.copyWith(fontFamily: family),
        labelSmall: base.labelSmall?.copyWith(fontFamily: family),
      ),
    );
  }

  TextTheme _googleFontTextTheme(String family, Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    switch (family) {
      case 'Inter':
        return GoogleFonts.interTextTheme(base);
      case 'Noto Sans SC':
        return GoogleFonts.notoSansScTextTheme(base);
      case 'JetBrains Mono':
        return GoogleFonts.jetBrainsMonoTextTheme(base);
      case 'Roboto':
        return GoogleFonts.robotoTextTheme(base);
      case 'Lato':
        return GoogleFonts.latoTextTheme(base);
      case 'Poppins':
        return GoogleFonts.poppinsTextTheme(base);
      case 'Montserrat':
        return GoogleFonts.montserratTextTheme(base);
      case 'Merriweather':
        return GoogleFonts.merriweatherTextTheme(base);
      case 'Source Code Pro':
        return GoogleFonts.sourceCodeProTextTheme(base);
      default:
        return base;
    }
  }
}
