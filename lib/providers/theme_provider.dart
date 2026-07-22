import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';

/// Global theme mode provider.
/// The selection is persisted to disk (shared_preferences) and restored
/// automatically the next time the app starts.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  static const _storageKey = 'settings.themeMode';

  ThemeModeNotifier() : super(AppThemeMode.freshGreen) {
    _restore();
  }

  /// Loads the persisted theme (if any) shortly after startup. The app
  /// starts with the default theme and switches as soon as the saved
  /// value arrives — typically within the first frame.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved == null) return;
      for (final mode in AppThemeMode.values) {
        if (mode.name == saved) {
          if (mode != state) state = mode;
          return;
        }
      }
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  void setTheme(AppThemeMode mode) {
    state = mode;
    _persist();
  }

  void cycleTheme() {
    final values = AppThemeMode.values;
    final nextIndex = (values.indexOf(state) + 1) % values.length;
    state = values[nextIndex];
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, state.name);
    } catch (_) {
      // Best-effort.
    }
  }
}
