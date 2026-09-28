import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/presentation/task_board/task_card_widget.dart';
import 'package:taskflow/presentation/shared/glass_sheen.dart';
import 'package:taskflow/providers/board_card_style_provider.dart';
import 'package:taskflow/providers/app_glass_provider.dart';
import 'package:taskflow/providers/theme_provider.dart';
import 'package:taskflow/core/theme/app_theme.dart';

/// v1.12.3 tests for the Today-board card style settings: opacity bounds,
/// glass mode, the auto-translucency applied when glass is first enabled,
/// persistence/restore, and the TaskCard glass rendering itself.
/// v1.12.33 adds the BoardGlassSpec contract — the single recipe every Today
/// surface (cards, KPI strip, quick-add bar, columns) resolves through.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardCardStyle value object', () {
    test('defaults are opaque, non-glass', () {
      const style = BoardCardStyle();
      expect(style.opacity, 1.0);
      expect(style.glass, isFalse);
      expect(style.blur, BoardCardStyle.defaultBlur);
      expect(style.isDefault, isTrue);
    });

    test('copyWith changes only the given fields', () {
      const style = BoardCardStyle();
      final halfGlass = style.copyWith(opacity: 0.5, glass: true, blur: 22);
      expect(halfGlass.opacity, 0.5);
      expect(halfGlass.glass, isTrue);
      expect(halfGlass.blur, 22);
      expect(halfGlass.isDefault, isFalse);
    });
  });

  group('BoardCardStyleNotifier', () {
    test('defaults to opaque, non-glass', () {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      expect(n.state.opacity, 1.0);
      expect(n.state.glass, isFalse);
    });

    test('setOpacity clamps into 0%–100%', () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setOpacity(-0.1);
      expect(n.state.opacity, BoardCardStyle.minOpacity);
      await n.setOpacity(2.0);
      expect(n.state.opacity, BoardCardStyle.maxOpacity);
      await n.setOpacity(0.05);
      expect(n.state.opacity, 0.05);
      await n.setOpacity(0.7);
      expect(n.state.opacity, 0.7);
    });

    test('setGlass(true) at full opacity drops to the glass default (0.55)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setGlass(true);
      // Frosted glass is invisible on a fully opaque fill — the toggle
      // must make it translucent immediately.
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, BoardCardStyle.glassDefaultOpacity);
    });

    test('setGlass(true, lightTheme) drops to the light default (0.85)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      // v1.12.16: 55% white over light surfaces reads as dim mud — the
      // light-theme auto-drop lands much higher.
      await n.setGlass(true, lightTheme: true);
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, BoardCardStyle.glassDefaultOpacityLight);
    });

    test('setGlass(true) keeps a custom (already translucent) opacity',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setOpacity(0.8);
      await n.setGlass(true);
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, 0.8);
    });

    test('setGlass(false) leaves the opacity untouched', () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setGlass(true); // → glass 0.55
      await n.setGlass(false);
      expect(n.state.glass, isFalse);
      expect(n.state.opacity, 0.55);
    });

    test('reset returns to the default look', () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setGlass(true);
      await n.setOpacity(0.4);
      await n.reset();
      expect(n.state.opacity, 1.0);
      expect(n.state.glass, isFalse);
      expect(n.state.isDefault, isTrue);
    });

    test('setBlur clamps into 4–30', () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setBlur(0);
      expect(n.state.blur, BoardCardStyle.minBlur);
      await n.setBlur(100);
      expect(n.state.blur, BoardCardStyle.maxBlur);
      await n.setBlur(22);
      expect(n.state.blur, 22);
    });

    test('persists opacity and glass, restores them on startup', () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await n.setOpacity(0.65);
      await n.setGlass(true);
      await n.setBlur(22);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('settings.boardCardOpacity'), 0.65);
      expect(prefs.getBool('settings.boardCardGlass'), isTrue);
      expect(prefs.getDouble('settings.boardCardBlur'), 22);

      // A fresh notifier (next app start) restores the same style.
      final restored = BoardCardStyleNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(restored.state.opacity, 0.65);
      expect(restored.state.glass, isTrue);
      expect(restored.state.blur, 22);
    });

    test('restore clamps an out-of-range persisted opacity', () async {
      SharedPreferences.setMockInitialValues({
        'settings.boardCardOpacity': -1.0, // double literal — getDouble casts
        'settings.boardCardGlass': false,
      });
      final n = BoardCardStyleNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state.opacity, BoardCardStyle.minOpacity);
      expect(n.state.glass, isFalse);
    });

    test('absent prefs keep the default (no first-flash of old style)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state.isDefault, isTrue);
    });
  });

  group('TaskCard glass rendering', () {
    Task sampleTask() => Task()
      ..id = 1
      ..uid = 'uid-1'
      ..title = 'Sample task'
      ..status = TaskStatus.planned
      ..priority = Priority.p2Medium
      ..createdAt = DateTime(2026, 9, 1, 10);

    Widget harness(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('glass mode wraps the card in a BackdropFilter', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final notifier = BoardCardStyleNotifier()..setGlass(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boardCardStyleProvider.overrideWith((ref) => notifier),
          ],
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Sample task'), findsOneWidget);
    });

    testWidgets('default style renders no BackdropFilter (non-glass theme)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      // v1.12.32: warmSand / inkBlue now render glass by default, so to keep
      // testing the GLOBAL default contract ("untuned board-card style adds no
      // blur") this runs under a non-glass theme (dark).
      final darkTheme = ThemeModeNotifier()..setTheme(AppThemeMode.dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeModeProvider.overrideWith((ref) => darkTheme),
          ],
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Sample task'), findsOneWidget);
    });

    testWidgets('board-glass theme (inkBlue) renders glass by default',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      // inkBlue is the provider's default theme; with no board-card style set
      // it must still frost its cards (v1.12.32 iOS-glass look).
      await tester.pumpWidget(
        ProviderScope(
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Sample task'), findsOneWidget);
    });

    testWidgets('glass card carries the iOS specular sheen under the content',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      // v1.12.33: the shared GlassSheen is what makes the frost read as a lit
      // slab; it must sit inside the glass card and not swallow pointer events
      // (IgnorePointer is built into the widget).
      expect(find.descendant(
          of: find.byType(TaskCard), matching: find.byType(GlassSheen)),
          findsOneWidget);
      expect(find.text('Sample task'), findsOneWidget);
    });

    testWidgets('non-glass theme paints no sheen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final darkTheme = ThemeModeNotifier()..setTheme(AppThemeMode.dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeModeProvider.overrideWith((ref) => darkTheme),
          ],
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(TaskCard), matching: find.byType(GlassSheen)),
          findsNothing);
    });

    testWidgets('a tuned opacity slider still drives the glass fill',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final notifier = BoardCardStyleNotifier()..setOpacity(0.40);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boardCardStyleProvider.overrideWith((ref) => notifier),
          ],
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      // Contract from v1.12.21: the slider is never bypassed by the theme
      // default — the fill must land at 40% even on a board-glass theme.
      final fills = tester
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(TaskCard), matching: find.byType(DecoratedBox)))
          .map((d) => d.decoration is BoxDecoration
              ? (d.decoration as BoxDecoration).color
              : null)
          .whereType<Color>();
      expect(
        fills.any((c) => (c.opacity - 0.40).abs() < 0.02),
        isTrue,
        reason: 'expected a 40%-alpha glass fill, got $fills',
      );
    });
  });

  group('BoardGlassSpec (theme glass merged with the user style)', () {
    test('plain theme + default style stays solid', () {
      final spec =
          BoardGlassSpec.resolve(const BoardCardStyle(), themeGlass: false);
      expect(spec.glass, isFalse);
      expect(spec.opacity, 1.0);
      expect(spec.blur, BoardCardStyle.defaultBlur);
    });

    test('board-glass theme frosts an untouched style at the iOS default', () {
      final spec =
          BoardGlassSpec.resolve(const BoardCardStyle(), themeGlass: true);
      expect(spec.glass, isTrue);
      expect(spec.opacity, BoardCardStyle.iosGlassDefaultOpacity);
    });

    test('board-glass theme honors a slider the user has tuned', () {
      final spec = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.95), themeGlass: true);
      expect(spec.glass, isTrue);
      expect(spec.opacity, 0.95);
    });

    test('explicit glass wins on a theme without boardGlass', () {
      final spec = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.6, glass: true, blur: 22),
          themeGlass: false);
      expect(spec.glass, isTrue);
      expect(spec.opacity, 0.6);
      expect(spec.blur, 22);
    });

    test('v1.12.33: panels follow Interface Glass, not the card slider', () {
      final spec = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.15, glass: true, blur: 12),
          themeGlass: false,
          appGlass: const AppGlassStyle(
              glass: true, opacity: 0.6, blur: 22));
      // The card fill stays at the user's 15%…
      expect(spec.opacity, 0.15);
      // …but the KPI strip / quick-add bar are interface panels: they take the
      // interface opacity and blur.
      expect(spec.panelOpacity, 0.6);
      expect(spec.panelBlur, 22);
    });

    test('v1.12.33: panel fill never drops below the readability floor', () {
      final spec = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.15, glass: true),
          themeGlass: true);
      expect(spec.opacity, 0.15);
      expect(spec.panelOpacity, BoardGlassSpec.panelOpacityFloor);
      // Interface Glass can also be dragged low — same floor applies.
      final lowInterface = BoardGlassSpec.resolve(
          const BoardCardStyle(),
          themeGlass: false,
          appGlass: const AppGlassStyle(glass: true, opacity: 0.2));
      expect(lowInterface.panelOpacity,
          BoardGlassSpec.panelOpacityFloor);
    });

    test('the resolved spec is what the provider exposes for inkBlue',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Default theme is inkBlue (a board-glass theme) with an untuned style.
      final spec = container.read(boardGlassSpecProvider);
      expect(spec.glass, isTrue);
      expect(spec.opacity, BoardCardStyle.iosGlassDefaultOpacity);
      // ...and the same recipe reaches the whole board through one provider.
      container.read(themeModeProvider.notifier).setTheme(AppThemeMode.dark);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final darkSpec = container.read(boardGlassSpecProvider);
      expect(darkSpec.glass, isFalse);
      expect(darkSpec.opacity, 1.0);
    });
  });

  group('GlassSheen.fillOver', () {
    test('composites the specular profile over the base fill', () {
      final gradient = GlassSheen.fillOver(Colors.white.withOpacity(0.72));
      expect(gradient.colors.first.alpha, greaterThan(255 * 0.72 - 1));
      expect(gradient.colors.last.a, lessThan(1.0));
      expect(gradient.colors[1].a, moreOrLessEquals(0.72, epsilon: 0.01));
      expect(gradient.stops, [0.0, 0.45, 1.0]);
    });

    // v1.12.34 contract: the user rejected the v1.12.33 look as "弯曲立体感太强"
    // (a bright top wash AND a bright bottom rim with a hard inner rim reads as
    // a lens bulging out of the card). Glass must stay a FLAT lit slab, so the
    // specular values are capped — raising them again is a deliberate change,
    // not a silent regression.
    test('stays flat: no lens bulge', () {
      const sheen = GlassSheen();
      expect(sheen.topAlpha, lessThanOrEqualTo(0.16));
      expect(sheen.bottomAlpha, lessThanOrEqualTo(0.05));
      expect(sheen.rimAlpha, 0.0);
      expect(sheen.topFade, lessThanOrEqualTo(0.5));
    });

    test('fillOver mirrors the same flat profile', () {
      const sheen = GlassSheen();
      final gradient = GlassSheen.fillOver(Colors.white.withOpacity(0.72));
      expect(gradient.stops!.first, 0.0);
      expect(gradient.stops![1], sheen.topFade);
      // Top wash adds at most ~14% white; the bottom stays near the base.
      final base = Colors.white.withOpacity(0.72);
      final topGain = gradient.colors.first.a - base.a;
      final bottomGain = gradient.colors.last.a - base.a;
      expect(topGain, lessThanOrEqualTo(0.16));
      expect(bottomGain, lessThanOrEqualTo(0.05));
    });
  });
}
