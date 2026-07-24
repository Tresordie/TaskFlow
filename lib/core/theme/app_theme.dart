import 'package:flutter/material.dart';
import 'app_colors.dart';

enum AppThemeMode {
  indigoLight,
  freshGreen,
  oceanBlue,
  sunsetOrange,
  sakuraPink,
  lavenderPurple,
  dark;

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
      // Segoe UI is the Windows system font (excellent Latin rendering);
      // when unavailable Flutter falls back to bundled Roboto. The
      // fallback chain gives CJK glyphs a consistent modern sans
      // (YaHei on Windows, PingFang/Hiragino on macOS) so mixed
      // Chinese/English text renders evenly.
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Hiragino Sans GB',
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
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border, width: 1),
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
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: p.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          color: p.textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: p.textSecondary,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: p.textSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? p.bg : p.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.primaryGhost,
        selectedColor: p.primary.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: p.primary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: p.surface,
      ),
    );
  }

  // Legacy getters for backward compatibility
  static ThemeData get light => buildTheme(AppThemeMode.indigoLight);
  static ThemeData get dark => buildTheme(AppThemeMode.dark);
}
