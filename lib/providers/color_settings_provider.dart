import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-assigned colors for projects and tags.
///
/// Colors are stored as name → ARGB-int maps and persisted to disk
/// (shared_preferences) so they survive restarts and app updates. A
/// missing entry means "use the default rendering".
class ColorSettings {
  final Map<String, int> projectColors;
  final Map<String, int> tagColors;

  const ColorSettings({
    this.projectColors = const {},
    this.tagColors = const {},
  });

  Color? projectColor(String name) => _decode(projectColors[name]);
  Color? tagColor(String name) => _decode(tagColors[name]);

  static Color? _decode(int? argb) => argb == null ? null : Color(argb);

  ColorSettings copyWith({
    Map<String, int>? projectColors,
    Map<String, int>? tagColors,
  }) =>
      ColorSettings(
        projectColors: projectColors ?? this.projectColors,
        tagColors: tagColors ?? this.tagColors,
      );
}

final colorSettingsProvider =
    StateNotifierProvider<ColorSettingsNotifier, ColorSettings>((ref) {
  return ColorSettingsNotifier();
});

class ColorSettingsNotifier extends StateNotifier<ColorSettings> {
  static const _kProjects = 'settings.colors.projects';
  static const _kTags = 'settings.colors.tags';

  ColorSettingsNotifier() : super(const ColorSettings()) {
    _restore();
  }

  /// Loads the persisted color maps shortly after startup (best-effort,
  /// mirrors the theme/font providers).
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ColorSettings(
        projectColors: _decodeMap(prefs.getString(_kProjects)),
        tagColors: _decodeMap(prefs.getString(_kTags)),
      );
    } catch (_) {
      // Persistence is best-effort; never block the app over it.
    }
  }

  Map<String, int> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        return {
          for (final e in m.entries) e.key.toString(): (e.value as num).toInt(),
        };
      }
    } catch (_) {}
    return const {};
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProjects, jsonEncode(state.projectColors));
      await prefs.setString(_kTags, jsonEncode(state.tagColors));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Sets the color for project [name]. Pass `null` to clear it back to
  /// the default rendering.
  void setProjectColor(String name, Color? color) {
    final map = Map<String, int>.from(state.projectColors);
    if (color == null) {
      map.remove(name);
    } else {
      map[name] = color.value;
    }
    state = state.copyWith(projectColors: map);
    _persist();
  }

  /// Sets the color for tag [name]. Pass `null` to clear it.
  void setTagColor(String name, Color? color) {
    final map = Map<String, int>.from(state.tagColors);
    if (color == null) {
      map.remove(name);
    } else {
      map[name] = color.value;
    }
    state = state.copyWith(tagColors: map);
    _persist();
  }
}
