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

  /// The out-of-the-box font (used until the user picks one).
  ///
  /// v1.4.23: defaults to Noto Sans SC instead of the system font. The system
  /// default renders Latin via Segoe UI but Chinese via the Microsoft YaHei
  /// fallback, which is visibly lighter than the Latin glyphs — so Chinese
  /// text looked too faint. Noto Sans SC covers both scripts with true
  /// 100–900 weights, so mixed Chinese + English renders evenly and crisply.
  static FontOption get defaultFont => presets.firstWhere(
        (f) => f.id == 'notoSansSC',
        orElse: () => presets[0],
      );
}

final fontProvider = StateNotifierProvider<FontNotifier, FontOption>((ref) {
  return FontNotifier();
});

class FontNotifier extends StateNotifier<FontOption> {
  static const _storageKey = 'settings.fontId';
  static const _customPrefix = 'custom_';

  FontNotifier() : super(AppFonts.defaultFont) {
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

/// Global font weight as a numeric value (100–900, step 100, default 400).
/// Applied app-wide as a uniform delta relative to Regular (400) so the whole
/// typographic hierarchy shifts together — headings always stay heavier than
/// body text. Persisted across restarts.
final fontWeightProvider = StateNotifierProvider<FontWeightNotifier, int>((
  ref,
) {
  return FontWeightNotifier();
});

class FontWeightNotifier extends StateNotifier<int> {
  static const _storageKey = 'settings.fontWeight';
  static const minWeight = 100;
  static const maxWeight = 900;
  static const defaultWeight = 400;

  /// v1.4.22 stored an index (0–3) into a fixed 4-option list instead of the
  /// weight itself. Used to migrate old values on first load.
  static const _legacyWeights = [300, 400, 500, 600];

  FontWeightNotifier() : super(defaultWeight) {
    _restore();
  }

  /// Maps a numeric weight (e.g. 500) to the matching [FontWeight].
  static FontWeight weightFrom(int value) {
    final index = ((value ~/ 100) - 1).clamp(0, FontWeight.values.length - 1);
    return FontWeight.values[index];
  }

  /// The current state as a [FontWeight].
  FontWeight get fontWeight => weightFrom(state);

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_storageKey);
      if (saved == null) return;
      if (saved >= 0 && saved < _legacyWeights.length) {
        // Legacy index from v1.4.22 — migrate to the actual weight value.
        state = _legacyWeights[saved];
      } else if (saved >= minWeight && saved <= maxWeight) {
        state = _normalize(saved);
      }
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  void setWeight(int weight) {
    state = _normalize(weight);
    _persist();
  }

  void reset() {
    state = defaultWeight;
    _persist();
  }

  /// Clamps into 100–900 and rounds to the nearest hundred so the value
  /// always maps onto a real [FontWeight].
  static int _normalize(int weight) {
    final clamped = weight.clamp(minWeight, maxWeight);
    return (clamped / 100).round() * 100;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey, state);
    } catch (_) {
      // Best-effort.
    }
  }
}
