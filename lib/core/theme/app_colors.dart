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

  /// v1.12.27: foreground (text / icons) drawn ON primary-filled elements —
  /// buttons, selected chips, active toggles. Defaults to white, which is
  /// what every palette before the cream-accented glass dashboard assumed;
  /// light accents (cream / pastel) set a dark tone instead so labels stay
  /// readable on their own accent.
  final Color onPrimary;

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
    this.onPrimary = Colors.white,
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
    // v1.12.20: Notion-template retune — warm paper canvas, pure-white
    // cards, hairline border, ink+warm-gray text, and Notion's muted brown
    // accent (the tan primary read as muddy against the quieter base).
    bg: Color(0xFFF8F6F1),
    surface: Color(0xFFFEFDFB),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE7E3D8),
    textPrimary: Color(0xFF37352F),
    textSecondary: Color(0xFF7D786E),
    primary: Color(0xFF9F6B53),
    primaryLight: Color(0xFFC29884),
    primaryDark: Color(0xFF825442),
    primaryGhost: Color(0xFFF4ECE5),
  );

  // ─── Ink Blue (黛蓝, v1.7.0) ───
  // Rice-paper canvas with a deep ink-blue accent, like blue-and-white
  // porcelain. Cooler and calmer than the indigo default — a scholarly,
  // understated take on blue.
  static const ThemePalette inkBlue = ThemePalette(
    // v1.12.20: Notion-template retune — quieter porcelain canvas, pure
    // white cards, hairline border; the muted ink-blue accent is kept
    // (already Notion-muted).
    bg: Color(0xFFF5F7F9),
    surface: Color(0xFFFDFDFE),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE4E8EC),
    textPrimary: Color(0xFF2C3A4D),
    textSecondary: Color(0xFF6E7A87),
    primary: Color(0xFF3F6C99),
    primaryLight: Color(0xFF7FA3C4),
    primaryDark: Color(0xFF31547A),
    primaryGhost: Color(0xFFE4ECF4),
  );

  // ═════════════ Board-tinted family (v1.12.19) ═════════════
  // Notion-template-style palettes (user reference screenshots): every
  // kanban column is tinted by its own semantic accent (see the
  // boardTinted recipe in TaskBoardScreen / TaskCard) while the page base
  // stays quiet, so the colorful chips and pills do the talking.
  //
  // Contrast: textPrimary on card ≥ 10:1 (AAA); white on primary ≥ 3.5:1
  // (Material-600 convention, same as the rest of the catalog).
  //
  // v1.12.21: the two light members (creamBoard / pearlBoard) were removed
  // per user request — all light themes are Notion-tuned and board-tinted
  // now (v1.12.20), so a separate light pair was redundant.

  // ─── Midnight Board (午夜看板, v1.12.19) ───
  // Cool slate near-black with a deep green accent — the quiet sibling of
  // the blue-accented 墨板.
  static const ThemePalette midnightBoard = ThemePalette(
    bg: Color(0xFF101317),
    surface: Color(0xFF181C21),
    card: Color(0xFF20252B),
    border: Color(0xFF31383F),
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFF9AA1A9),
    primary: Color(0xFF4E8A67),
    primaryLight: Color(0xFF7FB48F),
    primaryDark: Color(0xFF3D6E50),
    primaryGhost: Color(0xFF1C2E24),
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
  // v1.12.17: both Latte (light) flavours removed per user request — the
  // kept dark flavours start here.
  // v1.12.36: Frappé (冰沙) removed per user request — the two accents only
  // differed in hue (Mauve / Sapphire) on one identical canvas.
  // v1.12.37: Macchiato (玛奇朵) removed the same way per user request —
  // Mocha now carries the Catppuccin family on its own.

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

  // ─── Notion Board (墨板, v1.12.18) ───
  // Notion-template-style near-black kanban: every board column is tinted
  // by its own semantic accent (status / priority / project) and the
  // translucent cards let that tint bleed through — see the notionTint
  // recipe in TaskBoardScreen. Primary = Notion brand blue.
  // Contrast: textPrimary on card ≈ 12.5:1 (AAA); border stays whisper-
  // subtle so the column tints do the talking.
  static const ThemePalette notionBoard = ThemePalette(
    bg: Color(0xFF0E0E0E),
    surface: Color(0xFF151515),
    card: Color(0xFF1C1C1C),
    border: Color(0xFF2E2E2E),
    textPrimary: Color(0xFFEDEDE9),
    textSecondary: Color(0xFF9B9B94),
    primary: Color(0xFF2383E2),
    primaryLight: Color(0xFF5AA7EE),
    primaryDark: Color(0xFF1667B5),
    primaryGhost: Color(0xFF152736),
  );

  // ─── Glass Dashboard (奶油玻璃, v1.12.27) ───
  // Frosted-glass dashboard reference: warm charcoal glass panels layered
  // over a deep taupe canvas, with a cream accent for active pills, buttons
  // and checkmarks — dark charcoal text sits ON the cream (onPrimary), the
  // reverse of the white-on-accent convention the other dark themes use.
  // Contrast: textPrimary on card ≈ 8.2:1 (AAA); cream on card ≈ 7.8:1;
  // onPrimary charcoal on cream ≈ 11:1 (AAA).
  static const ThemePalette glassDashboard = ThemePalette(
    bg: Color(0xFF2E2B28),
    surface: Color(0xFF3B3835),
    card: Color(0xFF4A4640),
    border: Color(0xFF5C564E),
    textPrimary: Color(0xFFF3F0E9),
    textSecondary: Color(0xFFBCB6AB),
    primary: Color(0xFFEFE9DA),
    primaryLight: Color(0xFFF7F3E8),
    primaryDark: Color(0xFFD9D1BC),
    primaryGhost: Color(0xFF33302C),
    onPrimary: Color(0xFF33302B),
  );

  // ─── Legacy aliases (for existing code compatibility) ───
  // v1.4.39: kept in sync with the base light / dark palettes above so the
  // hard-coded `isDark ? darkX : lightX` usages (dates, tags, icons, meta)
  // brighten together with the rest of the theme instead of staying dim.
  // v1.12.17: the light anchor moved from the deleted indigoLight to the
  // kept inkBlue palette.
  static const Color lightBg = Color(0xFFF5F7F9);
  static const Color lightSurface = Color(0xFFFDFDFE);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE4E8EC);
  static const Color lightTextPrimary = Color(0xFF2C3A4D);
  static const Color lightTextSecondary = Color(0xFF6E7A87);
  static const Color darkBg = Color(0xFF142036);
  static const Color darkSurface = Color(0xFF1E2B42);
  static const Color darkCard = Color(0xFF273650);
  static const Color darkBorder = Color(0xFF3E5070);
  static const Color darkTextPrimary = Color(0xFFE4EAF4);
  static const Color darkTextSecondary = Color(0xFFB7C3D8);
  static const Color primary = Color(0xFF3F6C99);
  static const Color primaryLight = Color(0xFF7FA3C4);
  static const Color primaryDark = Color(0xFF31547A);

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
