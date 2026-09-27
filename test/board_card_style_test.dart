import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/presentation/task_board/task_card_widget.dart';
import 'package:taskflow/providers/board_card_style_provider.dart';

/// v1.12.3 tests for the Today-board card style settings: opacity bounds,
/// glass mode, the auto-translucency applied when glass is first enabled,
/// persistence/restore, and the TaskCard glass rendering itself.
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

    testWidgets('default style renders no BackdropFilter', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: harness(TaskCard(task: sampleTask())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Sample task'), findsOneWidget);
    });
  });
}
