import 'package:flutter/material.dart';

import '../../data/models/task.dart';

/// Theme palette definitions for TaskFlow.
/// Each palette provides a complete set of colors for a theme variant.
class ThemePalette {
  final Color bg;
  final Color surface;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color primaryGhost; // very light tint for backgrounds

  const ThemePalette({
    required this.bg,
    required this.surface,
    required this.card,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryGhost,
  });
}

class AppColors {
  AppColors._();

  // ─── Priority colors (shared across themes) ───
  static const Color p0Critical = Color(0xFFEF4444);
  static const Color p1High = Color(0xFFF97316);
  static const Color p2Medium = Color(0xFF3B82F6);
  static const Color p3Low = Color(0xFF9CA3AF);

  // ─── Semantic colors ───
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── GFM alert semantic colors (v1.5.3) ───
  // The five `> [!TYPE]` alert accents, defined centrally (never hardcoded
  // at call sites) with light/dark variants tuned for readable contrast on
  // all 13 themes — the pale surfaces of the light variants and the deep
  // Catppuccin dark bases alike. NOTE blue / TIP green / IMPORTANT purple /
  // WARNING amber / CAUTION red, following GitHub's semantics.
  static const Map<String, (Color, Color)> _alertAccents = {
    'note': (Color(0xFF2563EB), Color(0xFF79B8FF)),
    'tip': (Color(0xFF16A34A), Color(0xFF56D364)),
    'important': (Color(0xFF8250DF), Color(0xFFA371F7)),
    'warning': (Color(0xFFB45309), Color(0xFFD29922)),
    'caution': (Color(0xFFDC2626), Color(0xFFF85149)),
  };

  /// Accent color of a GFM alert [type] ('note' | 'tip' | 'important' |
  /// 'warning' | 'caution') for the given theme [brightness]. Unknown types
  /// fall back to the NOTE accent.
  static Color alertAccent(String type, Brightness brightness) {
    final pair = _alertAccents[type.toLowerCase()] ?? _alertAccents['note']!;
    return brightness == Brightness.dark ? pair.$2 : pair.$1;
  }

  /// Tinted container background for a GFM alert — the accent at low
  /// opacity, so it stays readable in both light and dark themes.
  static Color alertBackground(String type, Brightness brightness) =>
      alertAccent(type, brightness)
          .withOpacity(brightness == Brightness.dark ? 0.14 : 0.08);

  // ─── Default (Indigo) Light ───
  // v1.4.39: textPrimary softened from near-black (1A2233) to a deep blue-
  // slate (273350) and the background lifted a touch — the old near-black
  // text on pale grey read as "heavy/dull". Contrast stays comfortably
  // above WCAG AA while the whole canvas feels lighter and airier.
  static const ThemePalette indigoLight = ThemePalette(
    bg: Color(0xFFF7F8FD),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFDFE3F0),
    textPrimary: Color(0xFF24304E),
    textSecondary: Color(0xFF58678C),
    primary: Color(0xFF6366F1),
    primaryLight: Color(0xFF818CF8),
    primaryDark: Color(0xFF4F46E5),
    primaryGhost: Color(0xFFEDF0FE),
  );

  // ─── Fresh Green (清新淡绿) ───
  static const ThemePalette freshGreen = ThemePalette(
    bg: Color(0xFFF0FAF4),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFBFFFD),
    border: Color(0xFFC7E0D3),
    textPrimary: Color(0xFF1F4D38),
    textSecondary: Color(0xFF4E7A63),
    primary: Color(0xFF34A853),
    primaryLight: Color(0xFF66BB6A),
    primaryDark: Color(0xFF2E7D42),
    primaryGhost: Color(0xFFE2F4E7),
  );

  // ─── Sunset Orange (日落橙) ───
  static const ThemePalette sunsetOrange = ThemePalette(
    bg: Color(0xFFFFF6EC),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFCF7),
    border: Color(0xFFF8CF9F),
    textPrimary: Color(0xFF542516),
    textSecondary: Color(0xFF8A6248),
    primary: Color(0xFFF97316),
    primaryLight: Color(0xFFFB923C),
    primaryDark: Color(0xFFEA580C),
    primaryGhost: Color(0xFFFFEAD0),
  );

  // ─── Lavender Purple (薰衣草紫) ───
  static const ThemePalette lavenderPurple = ThemePalette(
    bg: Color(0xFFFAF4FE),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFEFBFF),
    border: Color(0xFFE0C9F8),
    textPrimary: Color(0xFF46176F),
    textSecondary: Color(0xFF71608F),
    primary: Color(0xFFA855F7),
    primaryLight: Color(0xFFC084FC),
    primaryDark: Color(0xFF9333EA),
    primaryGhost: Color(0xFFF1E4FD),
  );

  // ─── Dark ───
  // v1.4.39: the whole dark palette is lifted noticeably — the previous
  // near-black surfaces (0B1120 / 1A2333) and muted text (CBD4E1) read as
  // "too dim/dull". Surfaces move up to a soft charcoal-blue, borders get a
  // touch more presence, and text brightens to a clear off-white (E4EAF4)
  // that stays below pure white to avoid glare while feeling fresh and
  // readable. The primary indigo is nudged brighter for more vibrancy.
  static const ThemePalette dark = ThemePalette(
    bg: Color(0xFF142036),
    surface: Color(0xFF1E2B42),
    card: Color(0xFF273650),
    border: Color(0xFF3E5070),
    textPrimary: Color(0xFFE4EAF4),
    textSecondary: Color(0xFFB7C3D8),
    primary: Color(0xFF8F9AFF),
    primaryLight: Color(0xFFB8C3FF),
    primaryDark: Color(0xFF6E74F2),
    primaryGhost: Color(0xFF2C3066),
  );

  // ─── Nord Night (极夜蓝, v1.6.0) ───
  // Official Nord palette (nordtheme.com): polar-night surfaces with the
  // frost-blue accent. Cool, calm and low-contrast — a dark theme built
  // for long engineering sessions rather than punchy vibrancy.
  static const ThemePalette nordNight = ThemePalette(
    bg: Color(0xFF242933),
    surface: Color(0xFF2E3440),
    card: Color(0xFF3B4252),
    border: Color(0xFF434C5E),
    textPrimary: Color(0xFFECEFF4),
    textSecondary: Color(0xFFD8DEE9),
    primary: Color(0xFF88C0D0),
    primaryLight: Color(0xFF8FBCBB),
    primaryDark: Color(0xFF5E81AC),
    primaryGhost: Color(0xFF35404D),
  );

  // ─── Warm Sand (暖沙, v1.6.0) ───
  // A warm paper-like light theme: soft sand canvas, deep umber text and a
  // caramel accent. Reads like a well-lit notebook — gentler than the cool
  // indigo default for users who prefer warm neutrals.
  static const ThemePalette warmSand = ThemePalette(
    bg: Color(0xFFFAF6F0),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFDFAF5),
    border: Color(0xFFE8DCC8),
    textPrimary: Color(0xFF4A3F35),
    textSecondary: Color(0xFF8A7A66),
    primary: Color(0xFFA9713B),
    primaryLight: Color(0xFFC99A6B),
    primaryDark: Color(0xFF8A5A2B),
    primaryGhost: Color(0xFFF5EBDD),
  );

  // ═════════════ Catppuccin (v1.4.96) ═════════════
  // Official Catppuccin palette (github.com/catppuccin/catppuccin), four
  // flavours × two accent variants each. No pure black/white anywhere —
  // soft pastels on tinted surfaces for a breathable, premium feel.
  //
  // Contrast map (WCAG):
  //   Latte   text #4C4F69 on base #EFF1F5 ≈ 8.0:1 (AAA)
  //           subtext0 #6C6F85 on base     ≈ 5.5:1 (AA)
  //           mauve #8839EF on base        ≈ 6.0:1 (AA)
  //   Dark flavours: text on base ≈ 11–13:1 (AAA); subtext0 ≈ 6–7:1 (AA);
  //   pastel accents on base ≈ 7–10:1 (AA/AAA for text + UI components).
  // Surface ladder per flavour (bg < surface < card, ascending elevation):
  //   light: base → mantle → soft off-white card
  //   dark:  base → surface0 → surface1 (border = surface2).

  // ─── Catppuccin Latte · Lavender (拿铁 · 薰衣草) ───
  // v1.4.98: clarity fix — the previous mapping put surface darker than bg,
  // which read as washed-out. Now surface and card sit ABOVE bg (brighter,
  // near-white) so cards visibly lift off the canvas; border is stronger
  // and secondary text is crisper.
  static const ThemePalette catLatteLavender = ThemePalette(
    bg: Color(0xFFEFF1F5),
    surface: Color(0xFFF9FAFD),
    card: Color(0xFFFEFEFF),
    border: Color(0xFFC8CDE0),
    textPrimary: Color(0xFF4C4F69),
    textSecondary: Color(0xFF5A5E73),
    primary: Color(0xFF7287FD),
    primaryLight: Color(0xFF8C9BFE),
    primaryDark: Color(0xFF5C70E9),
    primaryGhost: Color(0xFFE9ECFE),
  );

  // ─── Catppuccin Latte · Mauve (拿铁 · 木槿紫) ───
  static const ThemePalette catLatteMauve = ThemePalette(
    bg: Color(0xFFEFF1F5),
    surface: Color(0xFFF9FAFD),
    card: Color(0xFFFEFEFF),
    border: Color(0xFFC8CDE0),
    textPrimary: Color(0xFF4C4F69),
    textSecondary: Color(0xFF5A5E73),
    primary: Color(0xFF8839EF),
    primaryLight: Color(0xFF9F5CF3),
    primaryDark: Color(0xFF7029CC),
    primaryGhost: Color(0xFFF1E9FC),
  );

  // ─── Catppuccin Frappé · Mauve (冰沙 · 木槿紫) ───
  static const ThemePalette catFrappeMauve = ThemePalette(
    bg: Color(0xFF303446),
    surface: Color(0xFF414559),
    card: Color(0xFF51576D),
    border: Color(0xFF626880),
    textPrimary: Color(0xFFC6D0F5),
    textSecondary: Color(0xFFA5ADCE),
    primary: Color(0xFFCA9EE6),
    primaryLight: Color(0xFFDDB9EF),
    primaryDark: Color(0xFFAE82CE),
    primaryGhost: Color(0xFF4C4470),
  );

  // ─── Catppuccin Frappé · Sapphire (冰沙 · 蓝晶) ───
  static const ThemePalette catFrappeSapphire = ThemePalette(
    bg: Color(0xFF303446),
    surface: Color(0xFF414559),
    card: Color(0xFF51576D),
    border: Color(0xFF626880),
    textPrimary: Color(0xFFC6D0F5),
    textSecondary: Color(0xFFA5ADCE),
    primary: Color(0xFF85C1DC),
    primaryLight: Color(0xFFA3D2E6),
    primaryDark: Color(0xFF6AA8C4),
    primaryGhost: Color(0xFF3D5170),
  );

  // ─── Catppuccin Macchiato · Mauve (玛奇朵 · 木槿紫) ───
  static const ThemePalette catMacchiatoMauve = ThemePalette(
    bg: Color(0xFF24273A),
    surface: Color(0xFF363A4F),
    card: Color(0xFF494D64),
    border: Color(0xFF5B6078),
    textPrimary: Color(0xFFCAD3F5),
    textSecondary: Color(0xFFA5ADCB),
    primary: Color(0xFFC6A0F6),
    primaryLight: Color(0xFFD8BDF9),
    primaryDark: Color(0xFFA982DC),
    primaryGhost: Color(0xFF41396B),
  );

  // ─── Catppuccin Macchiato · Teal (玛奇朵 · 青碧) ───
  static const ThemePalette catMacchiatoTeal = ThemePalette(
    bg: Color(0xFF24273A),
    surface: Color(0xFF363A4F),
    card: Color(0xFF494D64),
    border: Color(0xFF5B6078),
    textPrimary: Color(0xFFCAD3F5),
    textSecondary: Color(0xFFA5ADCB),
    primary: Color(0xFF8BD5CA),
    primaryLight: Color(0xFFA7E1D8),
    primaryDark: Color(0xFF6FB8AC),
    primaryGhost: Color(0xFF34515B),
  );

  // ─── Catppuccin Mocha · Mauve (摩卡 · 木槿紫) ───
  static const ThemePalette catMochaMauve = ThemePalette(
    bg: Color(0xFF1E1E2E),
    surface: Color(0xFF313244),
    card: Color(0xFF45475A),
    border: Color(0xFF585B70),
    textPrimary: Color(0xFFCDD6F4),
    textSecondary: Color(0xFFA6ADC8),
    primary: Color(0xFFCBA6F7),
    primaryLight: Color(0xFFDEC0FA),
    primaryDark: Color(0xFFAE85DF),
    primaryGhost: Color(0xFF3C3356),
  );

  // ─── Catppuccin Mocha · Lavender (摩卡 · 薰衣草) ───
  static const ThemePalette catMochaLavender = ThemePalette(
    bg: Color(0xFF1E1E2E),
    surface: Color(0xFF313244),
    card: Color(0xFF45475A),
    border: Color(0xFF585B70),
    textPrimary: Color(0xFFCDD6F4),
    textSecondary: Color(0xFFA6ADC8),
    primary: Color(0xFFB4BEFE),
    primaryLight: Color(0xFFC9D1FE),
    primaryDark: Color(0xFF949FE4),
    primaryGhost: Color(0xFF333757),
  );

  // ─── Legacy aliases (for existing code compatibility) ───
  // v1.4.39: kept in sync with the indigo-light / dark palettes above so the
  // hard-coded `isDark ? darkX : lightX` usages (dates, tags, icons, meta)
  // brighten together with the rest of the theme instead of staying dim.
  static const Color lightBg = Color(0xFFF7F8FD);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFDFE3F0);
  static const Color lightTextPrimary = Color(0xFF24304E);
  static const Color lightTextSecondary = Color(0xFF58678C);
  static const Color darkBg = Color(0xFF142036);
  static const Color darkSurface = Color(0xFF1E2B42);
  static const Color darkCard = Color(0xFF273650);
  static const Color darkBorder = Color(0xFF3E5070);
  static const Color darkTextPrimary = Color(0xFFE4EAF4);
  static const Color darkTextSecondary = Color(0xFFB7C3D8);
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);

  static Color priorityColor(int priority) {
    switch (priority) {
      case 0:
        return p0Critical;
      case 1:
        return p1High;
      case 2:
        return p2Medium;
      default:
        return p3Low;
    }
  }

  /// Single source of truth for status colors, shared by the task detail
  /// page, timeline, and board group headers so they always agree.
  static Color statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.planned:
        return lightTextSecondary;
      case TaskStatus.inProgress:
        return info;
      case TaskStatus.completed:
        return success;
      case TaskStatus.archived:
        return p3Low;
      case TaskStatus.blocked:
        return error;
    }
  }
}
