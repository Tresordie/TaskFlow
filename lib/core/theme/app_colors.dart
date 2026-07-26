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
  // v1.4.29: textSecondary deepened a touch (475569 → 526077) for better
  // contrast on white; primaryGhost softened so tinted backgrounds feel
  // lighter and airier.
  static const ThemePalette indigoLight = ThemePalette(
    bg: Color(0xFFF7F8FC),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE4E8F0),
    textPrimary: Color(0xFF1A2233),
    textSecondary: Color(0xFF526077),
    primary: Color(0xFF6366F1),
    primaryLight: Color(0xFF818CF8),
    primaryDark: Color(0xFF4F46E5),
    primaryGhost: Color(0xFFF0F1FE),
  );

  // ─── Fresh Green (清新淡绿) ───
  static const ThemePalette freshGreen = ThemePalette(
    bg: Color(0xFFF0F9F4),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFAFFFE),
    border: Color(0xFFD1E7DD),
    textPrimary: Color(0xFF1B3A2D),
    textSecondary: Color(0xFF4A6E5B),
    primary: Color(0xFF34A853),
    primaryLight: Color(0xFF66BB6A),
    primaryDark: Color(0xFF2E7D42),
    primaryGhost: Color(0xFFE8F5E9),
  );

  // ─── Ocean Blue (海洋蓝) ───
  static const ThemePalette oceanBlue = ThemePalette(
    bg: Color(0xFFF0F7FF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFBFDFF),
    border: Color(0xFFD6E6F5),
    textPrimary: Color(0xFF16324F),
    textSecondary: Color(0xFF49637E),
    primary: Color(0xFF0EA5E9),
    primaryLight: Color(0xFF38BDF8),
    primaryDark: Color(0xFF0284C7),
    primaryGhost: Color(0xFFE0F2FE),
  );

  // ─── Sunset Orange (日落橙) ───
  static const ThemePalette sunsetOrange = ThemePalette(
    bg: Color(0xFFFFF7ED),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFBF5),
    border: Color(0xFFFED7AA),
    textPrimary: Color(0xFF431407),
    textSecondary: Color(0xFF7E5741),
    primary: Color(0xFFF97316),
    primaryLight: Color(0xFFFB923C),
    primaryDark: Color(0xFFEA580C),
    primaryGhost: Color(0xFFFFEDD5),
  );

  // ─── Sakura Pink (樱花粉) ───
  static const ThemePalette sakuraPink = ThemePalette(
    bg: Color(0xFFFFF5F7),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFBFC),
    border: Color(0xFFFBCFE8),
    textPrimary: Color(0xFF500724),
    textSecondary: Color(0xFF81586D),
    primary: Color(0xFFEC4899),
    primaryLight: Color(0xFFF472B6),
    primaryDark: Color(0xFFDB2777),
    primaryGhost: Color(0xFFFCE7F3),
  );

  // ─── Lavender Purple (薰衣草紫) ───
  static const ThemePalette lavenderPurple = ThemePalette(
    bg: Color(0xFFFAF5FF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFDFAFF),
    border: Color(0xFFE9D5FF),
    textPrimary: Color(0xFF3B0764),
    textSecondary: Color(0xFF67577E),
    primary: Color(0xFFA855F7),
    primaryLight: Color(0xFFC084FC),
    primaryDark: Color(0xFF9333EA),
    primaryGhost: Color(0xFFF3E8FF),
  );

  // ─── Dark ───
  // v1.4.29: card lifted slightly above surface (1E293B → 253047) so panels
  // read as distinct layers instead of one flat grey. Text tones are pulled
  // DOWN from near-white to a soft warm-grey (F1F5F9 → CBD4E1) — full-white
  // text on a dark background is glaring/harsh; the softer tone keeps contrast
  // comfortable for long reading while staying clearly legible.
  static const ThemePalette dark = ThemePalette(
    bg: Color(0xFF0B1120),
    surface: Color(0xFF1A2333),
    card: Color(0xFF253047),
    border: Color(0xFF36435C),
    textPrimary: Color(0xFFCBD4E1),
    textSecondary: Color(0xFF9AA9BF),
    primary: Color(0xFF818CF8),
    primaryLight: Color(0xFFA5B4FC),
    primaryDark: Color(0xFF6366F1),
    primaryGhost: Color(0xFF232055),
  );

  // ─── Legacy aliases (for existing code compatibility) ───
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFCBD4E1);
  static const Color darkTextSecondary = Color(0xFF9AA9BF);
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
