import 'package:flutter/material.dart';
import 'app_colors.dart';

enum AppThemeMode {
  indigoLight,
  freshGreen,
  oceanBlue,
  sunsetOrange,
  sakuraPink,
  lavenderPurple,
  dark,
  greenDark,
  blueDark,
  orangeDark,
  pinkDark,
  purpleDark;

  String get label {
    switch (this) {
      case AppThemeMode.indigoLight:
        return 'Indigo Light';
      case AppThemeMode.freshGreen:
        return 'Fresh Green';
      case AppThemeMode.oceanBlue:
        return 'Ocean Blue';
      case AppThemeMode.sunsetOrange:
        return 'Sunset Orange';
      case AppThemeMode.sakuraPink:
        return 'Sakura Pink';
      case AppThemeMode.lavenderPurple:
        return 'Lavender Purple';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.greenDark:
        return 'Forest Dark';
      case AppThemeMode.blueDark:
        return 'Ocean Dark';
      case AppThemeMode.orangeDark:
        return 'Ember Dark';
      case AppThemeMode.pinkDark:
        return 'Rose Dark';
      case AppThemeMode.purpleDark:
        return 'Violet Dark';
    }
  }

  String get labelZh {
    switch (this) {
      case AppThemeMode.indigoLight:
        return '默认靛蓝';
      case AppThemeMode.freshGreen:
        return '清新淡绿';
      case AppThemeMode.oceanBlue:
        return '海洋蓝';
      case AppThemeMode.sunsetOrange:
        return '日落橙';
      case AppThemeMode.sakuraPink:
        return '樱花粉';
      case AppThemeMode.lavenderPurple:
        return '薰衣草紫';
      case AppThemeMode.dark:
        return '暗夜模式';
      case AppThemeMode.greenDark:
        return '暗夜青绿';
      case AppThemeMode.blueDark:
        return '暗夜海蓝';
      case AppThemeMode.orangeDark:
        return '暗夜暖橙';
      case AppThemeMode.pinkDark:
        return '暗夜樱粉';
      case AppThemeMode.purpleDark:
        return '暗夜薰紫';
    }
  }

  ThemePalette get palette {
    switch (this) {
      case AppThemeMode.indigoLight:
        return AppColors.indigoLight;
      case AppThemeMode.freshGreen:
        return AppColors.freshGreen;
      case AppThemeMode.oceanBlue:
        return AppColors.oceanBlue;
      case AppThemeMode.sunsetOrange:
        return AppColors.sunsetOrange;
      case AppThemeMode.sakuraPink:
        return AppColors.sakuraPink;
      case AppThemeMode.lavenderPurple:
        return AppColors.lavenderPurple;
      case AppThemeMode.dark:
        return AppColors.dark;
      case AppThemeMode.greenDark:
        return AppColors.greenDark;
      case AppThemeMode.blueDark:
        return AppColors.blueDark;
      case AppThemeMode.orangeDark:
        return AppColors.orangeDark;
      case AppThemeMode.pinkDark:
        return AppColors.pinkDark;
      case AppThemeMode.purpleDark:
        return AppColors.purpleDark;
    }
  }

  Brightness get brightness {
    switch (this) {
      case AppThemeMode.indigoLight:
      case AppThemeMode.freshGreen:
      case AppThemeMode.oceanBlue:
      case AppThemeMode.sunsetOrange:
      case AppThemeMode.sakuraPink:
      case AppThemeMode.lavenderPurple:
        return Brightness.light;
      case AppThemeMode.dark:
      case AppThemeMode.greenDark:
      case AppThemeMode.blueDark:
      case AppThemeMode.orangeDark:
      case AppThemeMode.pinkDark:
      case AppThemeMode.purpleDark:
        return Brightness.dark;
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData buildTheme(AppThemeMode mode) {
    final p = mode.palette;
    final isDark = mode.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: mode.brightness,
      // v1.4.29 aesthetics: bundled Inter for Latin + HarmonyOS Sans SC for
      // CJK. Flutter's per-glyph fallback renders English with Inter and
      // Chinese with HarmonyOS automatically, giving even, modern mixed
      // text on every machine. System fonts remain as a final safety net.
      fontFamily: 'Inter',
      fontFamilyFallback: const [
        'HarmonyOS Sans SC',
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans SC',
        'sans-serif',
      ],
      // Use the surface color for the scaffold background so the window
      // background matches the content panels and title bar. This removes the
      // visible two-color "layered" frame (bg vs surface) around the content.
      scaffoldBackgroundColor: p.surface,
      colorScheme: ColorScheme(
        brightness: mode.brightness,
        primary: p.primary,
        onPrimary: Colors.white,
        secondary: p.primaryLight,
        onSecondary: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
        outline: p.border,
      ),
      cardTheme: CardThemeData(
        // v1.4.24: gentle lift instead of pure-flat — a soft tinted shadow
        // gives the main panels subtle depth. surfaceTintColor is disabled so
        // the card keeps its flat color (no M3 tint overlay).
        elevation: isDark ? 0 : 1,
        shadowColor: p.primary.withOpacity(0.10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border.withOpacity(0.8), width: 1),
        ),
        color: p.card,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      // v1.4.29: a refined type scale tuned for Inter + HarmonyOS Sans SC.
      // Slightly tighter letter-spacing on headings, a touch more line-height
      // on body text, and clearer weight contrast make mixed CJK/Latin text
      // noticeably easier to scan.
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
          letterSpacing: -0.6,
          height: 1.25,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
          letterSpacing: -0.3,
          height: 1.3,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
          letterSpacing: 0,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: p.textPrimary,
          letterSpacing: 0.1,
          height: 1.55,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: p.textSecondary,
          letterSpacing: 0.1,
          height: 1.5,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: p.textSecondary,
          height: 1.3,
        ),
      ),
      // v1.4.29: softer, more refined input fields — a slightly larger
      // radius, a subtle filled tint, and a clearer focus ring.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? p.bg : p.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border.withOpacity(0.9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border.withOpacity(0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // v1.4.29: buttons get a touch more presence — a hair more vertical
      // padding, a semi-bold label, and a soft shadow that lifts on hover.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: p.primary.withOpacity(0.35),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      // v1.4.29: outlined + text buttons share the same radius & label weight
      // so all button types feel like one family.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          side: BorderSide(color: p.border.withOpacity(1.0), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.primaryGhost,
        selectedColor: p.primary.withOpacity(0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: p.primary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.border.withOpacity(0.8),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        backgroundColor: p.surface,
        elevation: isDark ? 0 : 8,
        shadowColor: Colors.black.withOpacity(0.18),
      ),
      // v1.4.29: rounded, floating snackbars + tooltips + popup menus so
      // transient UI matches the card/dialog radius language.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? p.card : const Color(0xFF1E293B),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? p.card : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        elevation: isDark ? 0 : 8,
        shadowColor: Colors.black.withOpacity(0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border.withOpacity(0.7), width: 1),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      // v1.4.24: slim, rounded scrollbars that brighten on hover — a small
      // detail that makes the desktop UI feel much more polished.
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(8),
        crossAxisMargin: 2,
        trackColor: WidgetStateProperty.all(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered)
              ? p.primary.withOpacity(0.45)
              : p.textSecondary.withOpacity(0.28);
        }),
      ),
    );
  }

  // Legacy getters for backward compatibility
  static ThemeData get light => buildTheme(AppThemeMode.indigoLight);
  static ThemeData get dark => buildTheme(AppThemeMode.dark);
}
