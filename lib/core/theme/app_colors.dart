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

  // ─── Default (Indigo) Light ───
  // v1.4.39: textPrimary softened from near-black (1A2233) to a deep blue-
  // slate (273350) and the background lifted a touch — the old near-black
  // text on pale grey read as "heavy/dull". Contrast stays comfortably
  // above WCAG AA while the whole canvas feels lighter and airier.
  static const ThemePalette indigoLight = ThemePalette(
    bg: Color(0xFFF8F9FE),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE4E8F0),
    textPrimary: Color(0xFF273350),
    textSecondary: Color(0xFF5F6E88),
    primary: Color(0xFF6366F1),
    primaryLight: Color(0xFF818CF8),
    primaryDark: Color(0xFF4F46E5),
    primaryGhost: Color(0xFFF0F1FE),
  );

  // ─── Fresh Green (清新淡绿) ───
  static const ThemePalette freshGreen = ThemePalette(
    bg: Color(0xFFF2FBF6),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFBFFFE),
    border: Color(0xFFD1E7DD),
    textPrimary: Color(0xFF23503C),
    textSecondary: Color(0xFF567E6A),
    primary: Color(0xFF34A853),
    primaryLight: Color(0xFF66BB6A),
    primaryDark: Color(0xFF2E7D42),
    primaryGhost: Color(0xFFE8F5E9),
  );

  // ─── Ocean Blue (海洋蓝) ───
  static const ThemePalette oceanBlue = ThemePalette(
    bg: Color(0xFFF2F8FF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFCFDFF),
    border: Color(0xFFD6E6F5),
    textPrimary: Color(0xFF1F4266),
    textSecondary: Color(0xFF55718C),
    primary: Color(0xFF0EA5E9),
    primaryLight: Color(0xFF38BDF8),
    primaryDark: Color(0xFF0284C7),
    primaryGhost: Color(0xFFE0F2FE),
  );

  // ─── Sunset Orange (日落橙) ───
  static const ThemePalette sunsetOrange = ThemePalette(
    bg: Color(0xFFFFF8F0),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFCF7),
    border: Color(0xFFFED7AA),
    textPrimary: Color(0xFF57281A),
    textSecondary: Color(0xFF8C6650),
    primary: Color(0xFFF97316),
    primaryLight: Color(0xFFFB923C),
    primaryDark: Color(0xFFEA580C),
    primaryGhost: Color(0xFFFFEDD5),
  );

  // ─── Sakura Pink (樱花粉) ───
  static const ThemePalette sakuraPink = ThemePalette(
    bg: Color(0xFFFFF6F8),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFCFD),
    border: Color(0xFFFBCFE8),
    textPrimary: Color(0xFF63183A),
    textSecondary: Color(0xFF8F687D),
    primary: Color(0xFFEC4899),
    primaryLight: Color(0xFFF472B6),
    primaryDark: Color(0xFFDB2777),
    primaryGhost: Color(0xFFFCE7F3),
  );

  // ─── Lavender Purple (薰衣草紫) ───
  static const ThemePalette lavenderPurple = ThemePalette(
    bg: Color(0xFFFBF6FF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFEFBFF),
    border: Color(0xFFE9D5FF),
    textPrimary: Color(0xFF4A1B78),
    textSecondary: Color(0xFF756590),
    primary: Color(0xFFA855F7),
    primaryLight: Color(0xFFC084FC),
    primaryDark: Color(0xFF9333EA),
    primaryGhost: Color(0xFFF3E8FF),
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

  // ─── Legacy aliases (for existing code compatibility) ───
  // v1.4.39: kept in sync with the indigo-light / dark palettes above so the
  // hard-coded `isDark ? darkX : lightX` usages (dates, tags, icons, meta)
  // brighten together with the rest of the theme instead of staying dim.
  static const Color lightBg = Color(0xFFF8F9FE);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE4E8F0);
  static const Color lightTextPrimary = Color(0xFF273350);
  static const Color lightTextSecondary = Color(0xFF5F6E88);
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
