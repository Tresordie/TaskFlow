import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_glass_provider.dart';
import 'theme_provider.dart';

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

  /// v1.12.32: fill alpha a board-glass theme (warmSand / inkBlue) uses while
  /// the user has not tuned the opacity slider — translucent enough to read as
  /// iOS frosted glass over the tinted column, still high enough for text.
  static const iosGlassDefaultOpacity = 0.72;

  /// v1.12.42: on a paper canvas a 72% white card is the same colour as the
  /// page behind it, so the light themes lost all surface hierarchy (user:
  /// 暖沙 / 黛蓝 预览效果很差). Light glass keeps the frosting (blur + sheen +
  /// edge) but stays nearly solid.
  /// v1.12.45: 0.92 -> 0.97. Every column is tinted by its own accent
  /// (accent @ 10% over surface), so an 8% bleed painted the Done cards
  /// green-grey and the To Do cards grey - the same card read differently in
  /// different columns, which is what still looked too faint (user).
  /// Frosting stays (blur + sheen + edge); the fill stops dyeing.
  static const iosGlassDefaultOpacityLight = 0.97;

  bool get isDefault => opacity == 1.0 && !glass && blur == defaultBlur;

  BoardCardStyle copyWith({double? opacity, bool? glass, double? blur}) =>
      BoardCardStyle(
        opacity: opacity ?? this.opacity,
        glass: glass ?? this.glass,
        blur: blur ?? this.blur,
      );
}

/// v1.12.33: the single source of truth for "how glassy should the Today
/// dashboard surfaces be", merging the user's Settings style with the theme's
/// own iOS-glass default (`AppThemeMode.boardGlass`). Every Today surface —
/// task cards, KPI stat cards, the quick-add bar, the column wash and the
/// ambient orbs — resolves through this, so the dashboard never mixes a
/// frosted card with a solid slab of the same material.
class BoardGlassSpec {
  /// Glass rendering (backdrop blur + translucent fill + sheen) is on.
  final bool glass;

  /// Fill alpha to use for the glass surface (1.0 = solid).
  final double opacity;

  /// Fill alpha for the dashboard's PANEL surfaces (KPI strip, quick-add
  /// bar). Panels carry more text directly on the canvas than a card does,
  /// so they follow the Interface Glass slider when it is on and never drop
  /// below [panelOpacityFloor] — a 15% card fill is a deliberate choice, the
  /// same value would make the stat strip unreadable.
  final double panelOpacity;

  /// Backdrop blur sigma for the card surfaces.
  final double blur;

  /// Backdrop blur sigma for the panel surfaces (Interface Glass drives the
  /// shell panels, so they match its frosting when it is the active domain).
  final double panelBlur;

  /// Readability floor for [panelOpacity].
  static const panelOpacityFloor = 0.5;

  /// v1.12.42: panels carry text straight onto the canvas, and on paper a
  /// 50% fill lets the ambient gradient bleed through as haze.
  static const panelOpacityFloorLight = 0.88;

  const BoardGlassSpec({
    required this.glass,
    required this.opacity,
    required this.panelOpacity,
    required this.blur,
    required this.panelBlur,
  });

  static BoardGlassSpec resolve(BoardCardStyle style,
      {required bool themeGlass,
      AppGlassStyle? appGlass,
      Brightness brightness = Brightness.dark}) {
    final isLight = brightness == Brightness.light;
    // The theme can lead with glass even when the global toggle is off; the
    // user's own choice always wins when it is on.
    final glass = style.glass || themeGlass;
    // Theme-led glass on an untouched slider falls back to the iOS default so
    // the surface is actually translucent out of the box; a tuned slider is
    // honored as-is (1.0 → solid).
    final opacity = (themeGlass && !style.glass && style.opacity >= 1.0)
        ? (isLight
            ? BoardCardStyle.iosGlassDefaultOpacityLight
            : BoardCardStyle.iosGlassDefaultOpacity)
        : style.opacity;
    // Panels: the Interface Glass domain owns the surfaces around the cards
    // (v1.12.10), so when it is on they take its opacity/blur; otherwise they
    // follow the card recipe, floored for readability.
    final interface = appGlass != null && appGlass.glass;
    final rawPanel = interface ? appGlass.opacity : opacity;
    final floor = isLight ? panelOpacityFloorLight : panelOpacityFloor;
    final panelOpacity = rawPanel < floor ? floor : rawPanel;
    final panelBlur = interface ? appGlass.blur : style.blur;
    return BoardGlassSpec(
      glass: glass,
      opacity: opacity,
      panelOpacity: panelOpacity,
      blur: style.blur,
      panelBlur: panelBlur,
    );
  }
}

/// v1.12.33: the resolved glass recipe for the Today dashboard — watch this
/// instead of combining the card style and the theme flag at every call site.
final boardGlassSpecProvider = Provider<BoardGlassSpec>((ref) {
  final style = ref.watch(boardCardStyleProvider);
  final themeGlass = ref.watch(themeModeProvider.select((m) => m.boardGlass));
  final appGlass = ref.watch(appGlassStyleProvider);
  // v1.12.42: the recipe is brightness-aware — paper needs a firmer fill.
  final brightness = ref.watch(themeModeProvider.select((m) => m.brightness));
  return BoardGlassSpec.resolve(style,
      themeGlass: themeGlass, appGlass: appGlass, brightness: brightness);
});

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
        opacity:
            value.clamp(BoardCardStyle.minOpacity, BoardCardStyle.maxOpacity));
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
        blur: value.clamp(BoardCardStyle.minBlur, BoardCardStyle.maxBlur));
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
