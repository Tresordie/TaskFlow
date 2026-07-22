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

  static const List<FontOption> presets = [
    FontOption(
      id: 'system',
      labelZh: '系统默认',
      labelEn: 'System Default',
    ),
    FontOption(
      id: 'inter',
      labelZh: 'Inter (现代无衬线)',
      labelEn: 'Inter',
      fontFamily: 'Inter',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'notoSansSC',
      labelZh: 'Noto Sans SC (思源黑体)',
      labelEn: 'Noto Sans SC',
      fontFamily: 'Noto Sans SC',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'jetbrainsMono',
      labelZh: 'JetBrains Mono (等宽)',
      labelEn: 'JetBrains Mono',
      fontFamily: 'JetBrains Mono',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'roboto',
      labelZh: 'Roboto (Android 经典)',
      labelEn: 'Roboto',
      fontFamily: 'Roboto',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'lato',
      labelZh: 'Lato (温暖人文)',
      labelEn: 'Lato',
      fontFamily: 'Lato',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'poppins',
      labelZh: 'Poppins (几何圆润)',
      labelEn: 'Poppins',
      fontFamily: 'Poppins',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'montserrat',
      labelZh: 'Montserrat (现代都市)',
      labelEn: 'Montserrat',
      fontFamily: 'Montserrat',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'merriweather',
      labelZh: 'Merriweather (优雅衬线)',
      labelEn: 'Merriweather',
      fontFamily: 'Merriweather',
      isGoogleFont: true,
    ),
    FontOption(
      id: 'sourceCodePro',
      labelZh: 'Source Code Pro (等宽)',
      labelEn: 'Source Code Pro',
      fontFamily: 'Source Code Pro',
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
