import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.12.3: appearance of the task cards on the Today dashboard —
/// background opacity and an optional frosted-glass (glassmorphism)
/// mode. Opacity below 100% lets the board canvas and its ambient orbs
/// show through the cards; glass mode adds a backdrop blur plus a
/// bright rim so the cards read as frosted glass.
/// v1.12.4: the glass blur strength is user-adjustable (sigma 4–30,
/// default 14).
class BoardCardStyle {
  /// 1.0 = opaque (the historic card look).
  final double opacity;

  /// Frosted-glass mode: backdrop blur + translucent fill + bright rim.
  final bool glass;

  /// Backdrop blur sigma used while glass mode is on (v1.12.4).
  final double blur;

  const BoardCardStyle({
    this.opacity = 1.0,
    this.glass = false,
    this.blur = defaultBlur,
  });

  static const minOpacity = 0.0;
  static const maxOpacity = 1.0;

  /// Opacity applied automatically when glass is switched on while the
  /// card is still fully opaque — frosted glass needs translucency to be
  /// visible at all. The user can tune the slider afterwards.
  /// v1.12.16: theme-aware — dark glass columns make 55% look great, but
  /// on LIGHT themes 55% white over the pale surfaces reads as dim mud, so
  /// enabling glass there drops to 85% instead (see [glassDefaultOpacityLight]).
  static const glassDefaultOpacity = 0.55;
  static const glassDefaultOpacityLight = 0.85;

  /// Blur floor keeps the effect meaningful — 0 would just duplicate
  /// "glass off" (plain translucency, no frosting).
  static const minBlur = 4.0;
  static const maxBlur = 30.0;
  static const defaultBlur = 14.0;

  bool get isDefault =>
      opacity == 1.0 && !glass && blur == defaultBlur;

  BoardCardStyle copyWith(
          {double? opacity, bool? glass, double? blur}) =>
      BoardCardStyle(
        opacity: opacity ?? this.opacity,
        glass: glass ?? this.glass,
        blur: blur ?? this.blur,
      );
}

final boardCardStyleProvider =
    StateNotifierProvider<BoardCardStyleNotifier, BoardCardStyle>((ref) {
  return BoardCardStyleNotifier();
});

class BoardCardStyleNotifier extends StateNotifier<BoardCardStyle> {
  static const _opacityKey = 'settings.boardCardOpacity';
  static const _glassKey = 'settings.boardCardGlass';
  static const _blurKey = 'settings.boardCardBlur';

  /// Serializes overlapping writes: _persist is fire-and-forget, so two
  /// setters in the same tick would otherwise interleave their awaits and
  /// let the EARLIER call clobber the later one's values. Chaining keeps
  /// call order, and each run snapshots the state at its own turn so the
  /// last setter always wins.
  Future<void>? _persistChain;

  BoardCardStyleNotifier() : super(const BoardCardStyle()) {
    _restore();
  }

  /// Loads the persisted style (if any) shortly after startup.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final opacity = prefs.getDouble(_opacityKey);
      final glass = prefs.getBool(_glassKey);
      final blur = prefs.getDouble(_blurKey);
      if (opacity == null && glass == null && blur == null) return;
      state = BoardCardStyle(
        opacity: opacity == null
            ? 1.0
            : opacity.clamp(
                BoardCardStyle.minOpacity, BoardCardStyle.maxOpacity),
        glass: glass ?? false,
        blur: blur == null
            ? BoardCardStyle.defaultBlur
            : blur.clamp(BoardCardStyle.minBlur, BoardCardStyle.maxBlur),
      );
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  /// Persists; the returned future completes when THIS call's values are
  /// on disk (mock store) — awaited by tests to dodge the async race.
  Future<void> setOpacity(double value) {
    state = state.copyWith(
        opacity: value.clamp(BoardCardStyle.minOpacity,
            BoardCardStyle.maxOpacity));
    return _persist();
  }

  Future<void> setGlass(bool value, {bool lightTheme = false}) {
    var next = state.copyWith(glass: value);
    if (value && state.opacity >= 1.0) {
      next = next.copyWith(
          opacity: lightTheme
              ? BoardCardStyle.glassDefaultOpacityLight
              : BoardCardStyle.glassDefaultOpacity);
    }
    state = next;
    return _persist();
  }

  /// v1.12.4: backdrop blur strength for glass mode.
  Future<void> setBlur(double value) {
    state = state.copyWith(
        blur:
            value.clamp(BoardCardStyle.minBlur, BoardCardStyle.maxBlur));
    return _persist();
  }

  Future<void> reset() {
    state = const BoardCardStyle();
    return _persist();
  }

  Future<void> _persist() {
    final snapshot = state;
    final run = (_persistChain ?? Future<void>.value()).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_opacityKey, snapshot.opacity);
        await prefs.setBool(_glassKey, snapshot.glass);
        await prefs.setDouble(_blurKey, snapshot.blur);
      } catch (_) {
        // Best-effort.
      }
    });
    _persistChain = run;
    return run;
  }
}
