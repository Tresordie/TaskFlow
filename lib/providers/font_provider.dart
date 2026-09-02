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

  /// v1.4.99: paired CJK family for the Chinese-English pairing presets.
  /// null = use the bundled HarmonyOS Sans SC default.
  final String? cjkFamily;

  const FontOption({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    this.fontFamily,
    this.isGoogleFont = false,
    this.cjkFamily,
  });
}

/// All available font options: presets + common system fonts.
class AppFonts {
  AppFonts._();

  /// Curated presets focused on crisp, beautiful mixed Chinese + English
  /// rendering. (v1.4.24: dropped Noto Serif SC and LXGW WenKai per user
  /// request; v1.4.25: dropped ZCOOL XiaoWei and ZCOOL QingKe HuangYou per
  /// user request — leaving Noto Sans SC as the curated CJK choice.)
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
      id: 'poppins',
      labelZh: 'Poppins (几何圆润 · 英文为主)',
      labelEn: 'Poppins',
      fontFamily: 'Poppins',
      isGoogleFont: true,
    ),
    // v1.4.99: curated Chinese-English pairing presets.
    // v1.5.2: Latin half switched from Inter (unbundled) to the bundled
    // Manrope variable font; preset ids are KEPT so users' saved choices
    // migrate to the new pairing instead of falling back to default.
    FontOption(
      id: 'pairInterNoto',
      labelZh: 'Manrope × 思源黑体（现代均衡）',
      labelEn: 'Manrope + Noto Sans SC',
      fontFamily: 'Manrope',
      cjkFamily: 'Noto Sans SC',
    ),
    FontOption(
      id: 'pairInterMiSans',
      labelZh: 'Manrope × MiSans（屏幕锐利）',
      labelEn: 'Manrope + MiSans',
      fontFamily: 'Manrope',
      cjkFamily: 'MiSans',
    ),
    FontOption(
      id: 'pairLoraSerif',
      labelZh: 'Lora × 思源宋体（文艺优雅）',
      labelEn: 'Lora + Noto Serif SC',
      fontFamily: 'Lora',
      isGoogleFont: true,
      cjkFamily: 'Noto Serif SC',
    ),
    FontOption(
      id: 'pairNunitoWenKai',
      labelZh: 'Nunito × 霞鹜文楷（温暖人文）',
      labelEn: 'Nunito + LXGW WenKai',
      fontFamily: 'Nunito',
      isGoogleFont: true,
      cjkFamily: 'LXGW WenKai TC',
    ),
    // v1.6.0: two more tasteful pairings (Google-hosted, zero bundle cost).
    FontOption(
      id: 'pairPlexNoto',
      labelZh: 'IBM Plex Sans × 思源黑体（工程理性）',
      labelEn: 'IBM Plex Sans + Noto Sans SC',
      fontFamily: 'IBM Plex Sans',
      isGoogleFont: true,
      cjkFamily: 'Noto Sans SC',
    ),
    FontOption(
      id: 'pairOutfitMiSans',
      labelZh: 'Outfit × MiSans（现代几何）',
      labelEn: 'Outfit + MiSans',
      fontFamily: 'Outfit',
      isGoogleFont: true,
      cjkFamily: 'MiSans',
    ),
    // v1.7.0: three more quality CN+EN pairings (Google-hosted, zero bundle
    // cost). Inter pairs with the bundled MiSans; the other two use the
    // downloadable Noto Sans SC.
    FontOption(
      id: 'interMisans',
      labelZh: 'Inter × MiSans（经典均衡）',
      labelEn: 'Inter + MiSans',
      fontFamily: 'Inter',
      isGoogleFont: true,
      cjkFamily: 'MiSans',
    ),
    FontOption(
      id: 'jakartaNoto',
      labelZh: 'Plus Jakarta Sans × 思源黑体（优雅几何）',
      labelEn: 'Plus Jakarta Sans + Noto Sans SC',
      fontFamily: 'Plus Jakarta Sans',
      isGoogleFont: true,
      cjkFamily: 'Noto Sans SC',
    ),
    FontOption(
      id: 'lexendNoto',
      labelZh: 'Lexend × 思源黑体（清晰舒展）',
      labelEn: 'Lexend + Noto Sans SC',
      fontFamily: 'Lexend',
      isGoogleFont: true,
      cjkFamily: 'Noto Sans SC',
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
  /// v1.5.2: defaults to the SYSTEM preset, which now means the bundled
  /// Manrope × MiSans stack (ThemeData fontFamily + FontStack.fallback).
  /// Bundled = offline-first: no google_fonts download before the real
  /// face appears (the old Noto-Sans-SC default flashed system fonts on
  /// first launch / offline).
  static FontOption get defaultFont => presets.firstWhere(
        (f) => f.id == 'system',
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
