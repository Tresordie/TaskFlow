import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a font choice — either a preset (Google Fonts) or a system font.
class FontOption {
  final String id;
  final String labelZh;
  final String labelEn;
  final String? fontFamily; // null = system default
  final bool isGoogleFont; // true = download via google_fonts package

  const FontOption({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    this.fontFamily,
    this.isGoogleFont = false,
  });
}

/// All available font options: presets + common system fonts.
class AppFonts {
  AppFonts._();

  /// Curated presets focused on crisp, beautiful mixed Chinese + English
  /// rendering. (v1.4.22: removed Latin-only / mono / display fonts — Inter,
  /// Roboto, Lato, Poppins-style duplicates, Montserrat, Merriweather,
  /// JetBrains Mono, Source Code Pro — in favor of CJK-capable families.)
  static const List<FontOption> presets = [
    FontOption(
      id: 'system',
      labelZh: '系统默认',
      labelEn: 'System Default',
    ),
    FontOption(
      id: 'notoSansSC',
      labelZh: 'Noto Sans SC (思源黑体 · 中英混排清晰)',
      labelEn: 'Noto Sans SC',
      fontFamily: 'Noto Sans SC',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'notoSerifSC',
      labelZh: 'Noto Serif SC (思源宋体 · 中英混排优雅)',
      labelEn: 'Noto Serif SC',
      fontFamily: 'Noto Serif SC',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'lxgwWenKaiTC',
      labelZh: 'LXGW WenKai (霞鹜文楷 · 中英混排美观)',
      labelEn: 'LXGW WenKai TC',
      fontFamily: 'LXGW WenKai TC',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'poppins',
      labelZh: 'Poppins (几何圆润 · 英文为主)',
      labelEn: 'Poppins',
      fontFamily: 'Poppins',
      isGoogleFont: true,
    ),
  ];

  /// Common system fonts available on Windows / macOS
  static const List<FontOption> systemFonts = [
    // Windows
    FontOption(
      id: 'sys_segoe',
      labelZh: 'Segoe UI (Windows 界面)',
      labelEn: 'Segoe UI',
      fontFamily: 'Segoe UI',
    ),
    FontOption(
      id: 'sys_yahei',
      labelZh: '微软雅黑',
      labelEn: 'Microsoft YaHei',
      fontFamily: 'Microsoft YaHei',
    ),
    FontOption(
      id: 'sys_simsun',
      labelZh: '宋体',
      labelEn: 'SimSun',
      fontFamily: 'SimSun',
    ),
    FontOption(
      id: 'sys_simhei',
      labelZh: '黑体',
      labelEn: 'SimHei',
      fontFamily: 'SimHei',
    ),
    FontOption(
      id: 'sys_consolas',
      labelZh: 'Consolas (等宽)',
      labelEn: 'Consolas',
      fontFamily: 'Consolas',
    ),
    FontOption(
      id: 'sys_calibri',
      labelZh: 'Calibri',
      labelEn: 'Calibri',
      fontFamily: 'Calibri',
    ),
    FontOption(
      id: 'sys_cambria',
      labelZh: 'Cambria (衬线)',
      labelEn: 'Cambria',
      fontFamily: 'Cambria',
    ),
    FontOption(
      id: 'sys_arial',
      labelZh: 'Arial',
      labelEn: 'Arial',
      fontFamily: 'Arial',
    ),
    FontOption(
      id: 'sys_timesnewroman',
      labelZh: 'Times New Roman',
      labelEn: 'Times New Roman',
      fontFamily: 'Times New Roman',
    ),
    FontOption(
      id: 'sys_couriernew',
      labelZh: 'Courier New (等宽)',
      labelEn: 'Courier New',
      fontFamily: 'Courier New',
    ),
    // macOS
    FontOption(
      id: 'sys_pingfang',
      labelZh: '苹方 (macOS 中文)',
      labelEn: 'PingFang SC',
      fontFamily: 'PingFang SC',
    ),
    FontOption(
      id: 'sys_helvetica',
      labelZh: 'Helvetica Neue',
      labelEn: 'Helvetica Neue',
      fontFamily: 'Helvetica Neue',
    ),
    FontOption(
      id: 'sys_menlo',
      labelZh: 'Menlo (macOS 等宽)',
      labelEn: 'Menlo',
      fontFamily: 'Menlo',
    ),
  ];

  static List<FontOption> get all => [...presets, ...systemFonts];
}

final fontProvider = StateNotifierProvider<FontNotifier, FontOption>((ref) {
  return FontNotifier();
});

class FontNotifier extends StateNotifier<FontOption> {
  static const _storageKey = 'settings.fontId';
  static const _customPrefix = 'custom_';

  FontNotifier() : super(AppFonts.presets[0]) {
    _restore();
  }

  /// Loads the persisted font (if any) shortly after startup. The app
  /// starts with the default font and switches as soon as the saved
  /// value arrives — typically within the first frame.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_storageKey);
      if (savedId == null) return;

      if (savedId.startsWith(_customPrefix)) {
        final family = savedId.substring(_customPrefix.length);
        if (family.isNotEmpty) {
          state = FontOption(
            id: savedId,
            labelZh: family,
            labelEn: family,
            fontFamily: family,
          );
        }
        return;
      }

      for (final font in AppFonts.all) {
        if (font.id == savedId) {
          state = font;
          return;
        }
      }
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  void setFont(FontOption font) {
    state = font;
    _persist();
  }

  void setCustomFont(String familyName) {
    state = FontOption(
      id: '$_customPrefix$familyName',
      labelZh: familyName,
      labelEn: familyName,
      fontFamily: familyName,
    );
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, state.id);
    } catch (_) {
      // Best-effort.
    }
  }
}

/// Global font size scale (1.0 = 100%). Applied app-wide via
/// MediaQuery.textScaler and persisted across restarts.
final fontScaleProvider =
    StateNotifierProvider<FontScaleNotifier, double>((ref) {
  return FontScaleNotifier();
});

class FontScaleNotifier extends StateNotifier<double> {
  static const _storageKey = 'settings.fontScale';
  static const minScale = 0.8;
  static const maxScale = 1.4;

  FontScaleNotifier() : super(1.0) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_storageKey);
      if (saved != null && saved >= minScale && saved <= maxScale) {
        state = saved;
      }
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  void setScale(double scale) {
    state = scale.clamp(minScale, maxScale);
    _persist();
  }

  void reset() {
    state = 1.0;
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_storageKey, state);
    } catch (_) {
      // Best-effort.
    }
  }
}

/// A selectable global font-weight option.
class FontWeightOption {
  final String id;
  final String labelZh;
  final String labelEn;
  final FontWeight weight;

  const FontWeightOption({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.weight,
  });
}

/// Global font weight (applied app-wide to body text; headings that already
/// use a heavier weight keep their own). Persisted across restarts.
final fontWeightProvider =
    StateNotifierProvider<FontWeightNotifier, FontWeightOption>((ref) {
  return FontWeightNotifier();
});

class FontWeightNotifier extends StateNotifier<FontWeightOption> {
  static const _storageKey = 'settings.fontWeight';

  static const List<FontWeightOption> options = [
    FontWeightOption(
      id: 'light',
      labelZh: '偏细',
      labelEn: 'Light',
      weight: FontWeight.w300,
    ),
    FontWeightOption(
      id: 'regular',
      labelZh: '标准',
      labelEn: 'Regular',
      weight: FontWeight.w400,
    ),
    FontWeightOption(
      id: 'medium',
      labelZh: '适中',
      labelEn: 'Medium',
      weight: FontWeight.w500,
    ),
    FontWeightOption(
      id: 'semibold',
      labelZh: '加粗',
      labelEn: 'Semi-bold',
      weight: FontWeight.w600,
    ),
  ];

  FontWeightNotifier() : super(options[1]) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_storageKey);
      if (saved != null && saved >= 0 && saved < options.length) {
        state = options[saved];
      }
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  void setWeight(FontWeightOption option) {
    state = option;
    _persist();
  }

  void reset() {
    state = options[1];
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey, options.indexOf(state));
    } catch (_) {
      // Best-effort.
    }
  }
}
