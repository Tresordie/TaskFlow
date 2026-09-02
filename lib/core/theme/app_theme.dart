import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'font_stack.dart';

enum AppThemeMode {
  indigoLight,
  freshGreen,
  sunsetOrange,
  lavenderPurple,
  warmSand,
  // v1.7.0: three muted-quality light themes.
  celadon,
  inkBlue,
  dustyRose,
  dark,
  nordNight,
  // v1.4.96: Catppuccin — four flavours × two accents.
  catLatteLavender,
  catLatteMauve,
  catFrappeMauve,
  catFrappeSapphire,
  catMacchiatoMauve,
  catMacchiatoTeal,
  catMochaMauve,
  catMochaLavender;

  String get label {
    switch (this) {
      case AppThemeMode.indigoLight:
        return 'Indigo Light';
      case AppThemeMode.freshGreen:
        return 'Fresh Green';
      case AppThemeMode.sunsetOrange:
        return 'Sunset Orange';
      case AppThemeMode.lavenderPurple:
        return 'Lavender Purple';
      case AppThemeMode.warmSand:
        return 'Warm Sand';
      case AppThemeMode.celadon:
        return 'Celadon';
      case AppThemeMode.inkBlue:
        return 'Ink Blue';
      case AppThemeMode.dustyRose:
        return 'Dusty Rose';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.nordNight:
        return 'Nord Night';
      case AppThemeMode.catLatteLavender:
        return 'Catppuccin Latte · Lavender';
      case AppThemeMode.catLatteMauve:
        return 'Catppuccin Latte · Mauve';
      case AppThemeMode.catFrappeMauve:
        return 'Catppuccin Frappé · Mauve';
      case AppThemeMode.catFrappeSapphire:
        return 'Catppuccin Frappé · Sapphire';
      case AppThemeMode.catMacchiatoMauve:
        return 'Catppuccin Macchiato · Mauve';
      case AppThemeMode.catMacchiatoTeal:
        return 'Catppuccin Macchiato · Teal';
      case AppThemeMode.catMochaMauve:
        return 'Catppuccin Mocha · Mauve';
      case AppThemeMode.catMochaLavender:
        return 'Catppuccin Mocha · Lavender';
    }
  }

  String get labelZh {
    switch (this) {
      case AppThemeMode.indigoLight:
        return '默认靛蓝';
      case AppThemeMode.freshGreen:
        return '清新淡绿';
      case AppThemeMode.sunsetOrange:
        return '日落橙';
      case AppThemeMode.lavenderPurple:
        return '薰衣草紫';
      case AppThemeMode.warmSand:
        return '暖沙';
      case AppThemeMode.celadon:
        return '青瓷';
      case AppThemeMode.inkBlue:
        return '黛蓝';
      case AppThemeMode.dustyRose:
        return '胭脂';
      case AppThemeMode.dark:
        return '暗夜模式';
      case AppThemeMode.nordNight:
        return '极夜蓝';
      case AppThemeMode.catLatteLavender:
        return '拿铁 · 薰衣草';
      case AppThemeMode.catLatteMauve:
        return '拿铁 · 木槿紫';
      case AppThemeMode.catFrappeMauve:
        return '冰沙 · 木槿紫';
      case AppThemeMode.catFrappeSapphire:
        return '冰沙 · 蓝晶';
      case AppThemeMode.catMacchiatoMauve:
        return '玛奇朵 · 木槿紫';
      case AppThemeMode.catMacchiatoTeal:
        return '玛奇朵 · 青碧';
      case AppThemeMode.catMochaMauve:
        return '摩卡 · 木槿紫';
      case AppThemeMode.catMochaLavender:
        return '摩卡 · 薰衣草';
    }
  }

  ThemePalette get palette {
    switch (this) {
      case AppThemeMode.indigoLight:
        return AppColors.indigoLight;
      case AppThemeMode.freshGreen:
        return AppColors.freshGreen;
      case AppThemeMode.sunsetOrange:
        return AppColors.sunsetOrange;
      case AppThemeMode.lavenderPurple:
        return AppColors.lavenderPurple;
      case AppThemeMode.warmSand:
        return AppColors.warmSand;
      case AppThemeMode.celadon:
        return AppColors.celadon;
      case AppThemeMode.inkBlue:
        return AppColors.inkBlue;
      case AppThemeMode.dustyRose:
        return AppColors.dustyRose;
      case AppThemeMode.dark:
        return AppColors.dark;
      case AppThemeMode.nordNight:
        return AppColors.nordNight;
      case AppThemeMode.catLatteLavender:
        return AppColors.catLatteLavender;
      case AppThemeMode.catLatteMauve:
        return AppColors.catLatteMauve;
      case AppThemeMode.catFrappeMauve:
        return AppColors.catFrappeMauve;
      case AppThemeMode.catFrappeSapphire:
        return AppColors.catFrappeSapphire;
      case AppThemeMode.catMacchiatoMauve:
        return AppColors.catMacchiatoMauve;
      case AppThemeMode.catMacchiatoTeal:
        return AppColors.catMacchiatoTeal;
      case AppThemeMode.catMochaMauve:
        return AppColors.catMochaMauve;
      case AppThemeMode.catMochaLavender:
        return AppColors.catMochaLavender;
    }
  }

  Brightness get brightness {
    switch (this) {
      case AppThemeMode.indigoLight:
      case AppThemeMode.freshGreen:
      case AppThemeMode.sunsetOrange:
      case AppThemeMode.lavenderPurple:
      case AppThemeMode.warmSand:
      case AppThemeMode.celadon:
      case AppThemeMode.inkBlue:
      case AppThemeMode.dustyRose:
      case AppThemeMode.catLatteLavender:
      case AppThemeMode.catLatteMauve:
        return Brightness.light;
      case AppThemeMode.dark:
      case AppThemeMode.nordNight:
      case AppThemeMode.catFrappeMauve:
      case AppThemeMode.catFrappeSapphire:
      case AppThemeMode.catMacchiatoMauve:
      case AppThemeMode.catMacchiatoTeal:
      case AppThemeMode.catMochaMauve:
      case AppThemeMode.catMochaLavender:
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
      // v1.5.2 font upgrade: Manrope (Latin, variable) × MiSans (CJK).
      // The fallback chain owns Chinese glyphs, digits/punctuation
      // attribution and the emoji owner — see FontStack. Rule: never set
      // fontFamily alone where Chinese may render.
      fontFamily: FontStack.latin,
      fontFamilyFallback: FontStack.fallback,
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
