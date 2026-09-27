import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/presentation/shared/glass_panel.dart';
import 'package:taskflow/providers/app_glass_provider.dart';

/// v1.12.5 tests for the app-wide interface glass: the AppGlassStyle
/// provider (bounds / auto-translucency on enable / persistence), the
/// theme-level translucent surface & card colors (scaffold stays opaque),
/// and the shared GlassPanel wrapper.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppGlassStyle value object', () {
    test('defaults are off, opaque', () {
      const style = AppGlassStyle();
      expect(style.glass, isFalse);
      expect(style.opacity, 1.0);
      expect(style.blur, AppGlassStyle.defaultBlur);
      expect(style.isDefault, isTrue);
    });

    test('copyWith changes only the given fields', () {
      const style = AppGlassStyle();
      final on = style.copyWith(glass: true, opacity: 0.8, blur: 22);
      expect(on.glass, isTrue);
      expect(on.opacity, 0.8);
      expect(on.blur, 22);
      expect(on.isDefault, isFalse);
    });
  });

  group('AppGlassStyleNotifier', () {
    test('defaults to off, opaque, default blur', () {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      expect(n.state.glass, isFalse);
      expect(n.state.opacity, 1.0);
      expect(n.state.blur, AppGlassStyle.defaultBlur);
    });

    test('setGlass(true) at full opacity drops to the enable default (0.75)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      await n.setGlass(true);
      // Panels carry body text directly — a too-low opacity would hurt
      // readability, so the auto-drop is conservative (vs cards' 0.55).
      // v1.12.6: 0.85 → 0.75 so the effect is actually visible.
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, AppGlassStyle.enableDefaultOpacity);
    });

    test('setGlass(true) keeps a custom (already translucent) opacity',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      await n.setOpacity(0.6);
      await n.setGlass(true);
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, 0.6);
    });

    test('setOpacity clamps into 0%–100%', () async {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      await n.setOpacity(-0.1);
      expect(n.state.opacity, AppGlassStyle.minOpacity);
      await n.setOpacity(2.0);
      expect(n.state.opacity, AppGlassStyle.maxOpacity);
      await n.setOpacity(0.1);
      expect(n.state.opacity, 0.1);
      await n.setOpacity(0.0);
      expect(n.state.opacity, 0.0);
    });

    test('setBlur clamps into 4–30', () async {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      await n.setBlur(0);
      expect(n.state.blur, AppGlassStyle.minBlur);
      await n.setBlur(100);
      expect(n.state.blur, AppGlassStyle.maxBlur);
      await n.setBlur(20);
      expect(n.state.blur, 20);
    });

    test('reset returns to the default look', () async {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      await n.setGlass(true);
      await n.setBlur(25);
      await n.reset();
      expect(n.state.isDefault, isTrue);
    });

    test('persists glass/opacity/blur, restores them on startup', () async {
      SharedPreferences.setMockInitialValues({});
      final n = AppGlassStyleNotifier();
      await n.setGlass(true);
      await n.setBlur(20);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings.appGlass'), isTrue);
      expect(prefs.getDouble('settings.appGlassOpacity'),
          AppGlassStyle.enableDefaultOpacity);
      expect(prefs.getDouble('settings.appGlassBlur'), 20);

      // A fresh notifier (next app start) restores the same style.
      final restored = AppGlassStyleNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(restored.state.glass, isTrue);
      expect(restored.state.opacity, AppGlassStyle.enableDefaultOpacity);
      expect(restored.state.blur, 20);
    });

    test('restore clamps out-of-range persisted values', () async {
      SharedPreferences.setMockInitialValues({
        'settings.appGlass': true,
        'settings.appGlassOpacity': -1.0, // double literal — getDouble casts
        'settings.appGlassBlur': 100.0,
      });
      final n = AppGlassStyleNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, AppGlassStyle.minOpacity);
      expect(n.state.blur, AppGlassStyle.maxBlur);
    });
  });

  group('AppTheme.buildTheme glass params', () {
    test('default theme keeps opaque surface/card/scaffold', () {
      final theme = AppTheme.buildTheme(AppThemeMode.inkBlue);
      expect(theme.colorScheme.surface.alpha, 255);
      expect(theme.cardTheme.color!.alpha, 255);
      expect(theme.scaffoldBackgroundColor.alpha, 255);
    });

    test('glass theme: translucent surface/card, OPAQUE scaffold', () {
      final theme = AppTheme.buildTheme(
        AppThemeMode.inkBlue,
        glass: true,
        glassOpacity: 0.8,
      );
      expect(theme.colorScheme.surface.alpha, lessThan(255));
      expect(theme.cardTheme.color!.alpha, lessThan(255));
      // The scaffold sits under everything — it must never show the
      // black window through, glass or not.
      expect(theme.scaffoldBackgroundColor.alpha, 255);
    });

    test('glass opacity is clamped into 0%–100%', () {
      final theme = AppTheme.buildTheme(
        AppThemeMode.inkBlue,
        glass: true,
        glassOpacity: -1.0,
      );
      // Full range is allowed now — below 0 clamps to fully transparent.
      expect(theme.colorScheme.surface.alpha, 0);
      final opaque = AppTheme.buildTheme(
        AppThemeMode.inkBlue,
        glass: true,
        glassOpacity: 2.0,
      );
      expect(opaque.colorScheme.surface.alpha, 255);
    });
  });

  group('GlassPanel widget', () {
    Widget harness(Widget child) => MaterialApp(
          home: Scaffold(body: child),
        );

    testWidgets('glass on wraps the child in a BackdropFilter',
        (tester) async {
      await tester.pumpWidget(
        harness(const GlassPanel(
          glass: true,
          blur: 20,
          borderRadius: BorderRadius.all(Radius.circular(14)),
          child: SizedBox(width: 100, height: 50),
        )),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      final filter =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, isA<ImageFilter>());
    });

    testWidgets('glass off renders the child untouched', (tester) async {
      await tester.pumpWidget(
        harness(const GlassPanel(
          glass: false,
          child: SizedBox(width: 100, height: 50),
        )),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
