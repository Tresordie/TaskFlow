import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.12.5: app-wide interface glass — applies the frosted-glass look
/// (backdrop blur + translucent panels) to the shell itself: title bar,
/// sidebar and content panel, plus the theme's surface/card colors so
/// ordinary cards across every screen go translucent too.
///
/// Distinct from [BoardCardStyle] (Today board cards only): the panels
/// carry body text directly, so enabling glass drops the opacity to a
/// conservative 85% (not the cards' 55%) to keep text readable.
class AppGlassStyle {
  final bool glass;

  /// 1.0 = panels keep their historic opaque look.
  final double opacity;

  /// Backdrop blur sigma used on the glass panels.
  final double blur;

  const AppGlassStyle({
    this.glass = false,
    this.opacity = 1.0,
    this.blur = defaultBlur,
  });

  /// v1.12.10: 0–100% — the user wants full-range control per area.
  static const minOpacity = 0.0;
  static const maxOpacity = 1.0;

  /// Opacity applied automatically when glass is switched on while the
  /// interface is still fully opaque. The user can tune it afterwards.
  /// v1.12.6: 0.85 → 0.75 — at 0.85 the frosted look was barely visible
  /// over the subtle ambient canvas (user feedback: effect too weak).
  static const enableDefaultOpacity = 0.75;

  /// Blur floor keeps the effect meaningful — 0 would duplicate "glass
  /// off" (plain translucency, no frosting).
  static const minBlur = 4.0;
  static const maxBlur = 30.0;
  static const defaultBlur = 14.0;

  bool get isDefault => !glass && opacity == 1.0 && blur == defaultBlur;

  AppGlassStyle copyWith({bool? glass, double? opacity, double? blur}) =>
      AppGlassStyle(
        glass: glass ?? this.glass,
        opacity: opacity ?? this.opacity,
        blur: blur ?? this.blur,
      );
}

final appGlassStyleProvider =
    StateNotifierProvider<AppGlassStyleNotifier, AppGlassStyle>((ref) {
  return AppGlassStyleNotifier();
});

class AppGlassStyleNotifier extends StateNotifier<AppGlassStyle> {
  static const _glassKey = 'settings.appGlass';
  static const _opacityKey = 'settings.appGlassOpacity';
  static const _blurKey = 'settings.appGlassBlur';

  /// Serializes overlapping writes (same rationale as
  /// BoardCardStyleNotifier._persistChain): each run snapshots the state
  /// at its own turn so the last setter always wins.
  Future<void>? _persistChain;

  AppGlassStyleNotifier() : super(const AppGlassStyle()) {
    _restore();
  }

  /// Loads the persisted style (if any) shortly after startup.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final glass = prefs.getBool(_glassKey);
      final opacity = prefs.getDouble(_opacityKey);
      final blur = prefs.getDouble(_blurKey);
      if (glass == null && opacity == null && blur == null) return;
      state = AppGlassStyle(
        glass: glass ?? false,
        opacity: opacity == null
            ? 1.0
            : opacity.clamp(
                AppGlassStyle.minOpacity, AppGlassStyle.maxOpacity),
        blur: blur == null
            ? AppGlassStyle.defaultBlur
            : blur.clamp(AppGlassStyle.minBlur, AppGlassStyle.maxBlur),
      );
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  Future<void> setGlass(bool value) {
    var next = state.copyWith(glass: value);
    if (value && state.opacity >= 1.0) {
      next = next.copyWith(opacity: AppGlassStyle.enableDefaultOpacity);
    }
    state = next;
    return _persist();
  }

  Future<void> setOpacity(double value) {
    state = state.copyWith(
        opacity: value.clamp(
            AppGlassStyle.minOpacity, AppGlassStyle.maxOpacity));
    return _persist();
  }

  Future<void> setBlur(double value) {
    state = state.copyWith(
        blur: value.clamp(AppGlassStyle.minBlur, AppGlassStyle.maxBlur));
    return _persist();
  }

  Future<void> reset() {
    state = const AppGlassStyle();
    return _persist();
  }

  Future<void> _persist() {
    final snapshot = state;
    final run = (_persistChain ?? Future<void>.value()).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_glassKey, snapshot.glass);
        await prefs.setDouble(_opacityKey, snapshot.opacity);
        await prefs.setDouble(_blurKey, snapshot.blur);
      } catch (_) {
        // Best-effort.
      }
    });
    _persistChain = run;
    return run;
  }
}
