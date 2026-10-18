import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/core/theme/app_colors.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/presentation/task_board/task_card_widget.dart';
import 'package:taskflow/presentation/task_board/kanban_column.dart';
import 'package:taskflow/presentation/task_board/task_board_screen.dart';
import 'package:taskflow/presentation/shared/glass_sheen.dart';
import 'package:taskflow/providers/board_card_style_provider.dart';
import 'package:taskflow/providers/app_glass_provider.dart';
import 'package:taskflow/providers/task_providers.dart';
import 'package:taskflow/providers/theme_provider.dart';
import 'package:taskflow/core/theme/app_theme.dart';

/// In-memory repo so the tray-fill probe drives the REAL screen stack
/// without Isar (same shape as repro_board_add_freeze_test's fake).
class _TrayProbeRepo extends TaskRepository {
  final _tasks = <Task>[];
  int _nextId = 1;

  @override
  Future<List<Task>> getAllTasks() async => List.of(_tasks);

  @override
  Future<int> createTask({
    required String title,
    String? description,
    Priority priority = Priority.p2Medium,
    List<String> tags = const [],
    List<String> subSteps = const [],
    DateTime? dueDate,
    String project = '',
    TaskStatus status = TaskStatus.planned,
  }) async {
    final id = _nextId++;
    _tasks.add(Task()
      ..id = id
      ..uid = 'uid-$id'
      ..title = title
      ..priority = priority
      ..status = status
      ..tags = List.of(tags)
      ..project = project
      ..dueDate = dueDate
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now().millisecondsSinceEpoch
      ..sortOrder = id);
    return id;
  }
}

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

    test('setGlass(true, lightTheme) drops to the visible light default (0.62)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = BoardCardStyleNotifier();
      // v1.12.60: the light auto-drop is no longer near-solid — the user
      // asked for visible, adjustable glass on the light Today boards.
      await n.setGlass(true, lightTheme: true);
      expect(n.state.glass, isTrue);
      expect(n.state.opacity, BoardCardStyle.glassDefaultOpacityLight);
      expect(BoardCardStyle.glassDefaultOpacityLight, lessThanOrEqualTo(0.7));
      expect(BoardCardStyle.glassDefaultOpacityLight,
          greaterThan(BoardGlassSpec.cardOpacityFloorLight));
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

    // v1.12.49/60: 0.85 and 0.97 were pipeline-written light-glass auto
    // values — the toggle wrote them, nobody tuned to them. Both migrate to
    // the current visible-glass default; a hand-tuned value is left alone.
    test('restore migrates both old light-glass auto values', () async {
      for (final legacy in [0.85, 0.97]) {
        SharedPreferences.setMockInitialValues({
          'settings.boardCardOpacity': legacy,
          'settings.boardCardGlass': true,
        });
        final n = BoardCardStyleNotifier();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(n.state.opacity, BoardCardStyle.glassDefaultOpacityLight,
            reason: 'legacy $legacy');
      }
    });

    test('restore keeps a hand-tuned opacity near the old default', () async {
      SharedPreferences.setMockInitialValues({
        'settings.boardCardOpacity': 0.80,
        'settings.boardCardGlass': true,
      });
      final n = BoardCardStyleNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.opacity, 0.80);
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

    testWidgets('glass mode wraps the card in a BackdropFilter',
        (tester) async {
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
    // v1.12.44: the whole-card fade applied to completed / archived tasks.
    Future<void> pumpCardWith(
        WidgetTester tester, AppThemeMode mode, TaskStatus status) async {
      SharedPreferences.setMockInitialValues({});
      final notifier = ThemeModeNotifier()..setTheme(mode);
      final task = sampleTask()..status = status;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [themeModeProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            theme: AppTheme.buildTheme(mode),
            home: Scaffold(
              body: Center(
                child: SizedBox(width: 320, child: TaskCard(task: task)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The card-level fade, found as the nearest [AnimatedOpacity] above the
    /// title (the drag proxy is a plain Opacity, so it can't be confused).
    double doneFade(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(find
            .ancestor(
                of: find.text('Sample task'),
                matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;

    testWidgets('v1.12.44: a done card stays solid on paper', (tester) async {
      await pumpCardWith(tester, AppThemeMode.inkBlue, TaskStatus.completed);
      expect(
        doneFade(tester),
        greaterThanOrEqualTo(0.90),
        reason: 'the 78% fade stacked on the struck-through title and the ',
      );
      await pumpCardWith(tester, AppThemeMode.inkBlue, TaskStatus.archived);
      expect(doneFade(tester), greaterThanOrEqualTo(0.90));
    });

    // v1.12.48: dark joined light at the solid end. The old 0.78 was fine for
    // an opaque card, but under glass the fill (0.55) × the fade (0.78) left
    // ~0.43 effective alpha and the done card sank into the column tint
    // (user: 已完成任务太暗淡了). "Done" is carried by the strikethrough and
    // the green status bar, not by the whole card going dim.
    testWidgets('a done card stays solid on the dark board too',
        (tester) async {
      await pumpCardWith(tester, AppThemeMode.dark, TaskStatus.completed);
      expect(doneFade(tester), greaterThanOrEqualTo(0.90));
      await pumpCardWith(tester, AppThemeMode.dark, TaskStatus.archived);
      expect(doneFade(tester), greaterThanOrEqualTo(0.90));
    });

    testWidgets('an open card is never faded', (tester) async {
      await pumpCardWith(tester, AppThemeMode.inkBlue, TaskStatus.inProgress);
      expect(doneFade(tester), 1.0);
    });

    // v1.12.59: paper cards take the Notion skin — flat white page, hairline
    // border, 10px radius and NO left colour rail; the priority property pill
    // carries the colour instead (user: 任务卡像 Notion). The dark board was
    // confirmed good and keeps its v1.12.49 shell (14px, no rail).
    testWidgets('paper cards render the Notion skin', (tester) async {
      await pumpCardWith(tester, AppThemeMode.inkBlue, TaskStatus.inProgress);
      expect(find.byKey(const Key('priority-bar')), findsNothing,
          reason: 'a Notion card has no left colour rail');
      final shell = tester.widget<AnimatedContainer>(
          find.byKey(const Key('task-card-shell')));
      final decoration = shell.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(10),
          reason: 'Notion cards are softly squared, not 14px app slabs');
      final border = (decoration.border! as Border).top;
      expect(border.width, 1);
      expect(
        border.color,
        AppTheme.buildTheme(AppThemeMode.inkBlue)
            .colorScheme
            .outline
            .withValues(alpha: 0.55),
        reason: 'the flat card is separated by a hairline, not elevation',
      );
    });

    testWidgets('the dark board keeps its 14px glass card', (tester) async {
      await pumpCardWith(tester, AppThemeMode.dark, TaskStatus.inProgress);
      expect(find.byKey(const Key('priority-bar')), findsNothing);
      final shell = tester.widget<AnimatedContainer>(
          find.byKey(const Key('task-card-shell')));
      final decoration = shell.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(14));
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
      expect(
          find.descendant(
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
      final notifier = BoardCardStyleNotifier()..setOpacity(0.80);
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
      // default — the fill must land at 80% even on a board-glass theme.
      // (v1.12.49: the old 40% probe now sits below the paper card floor,
      // so the slider value used here is above it.)
      final fills = tester
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(TaskCard), matching: find.byType(DecoratedBox)))
          .map((d) => d.decoration is BoxDecoration
              ? (d.decoration as BoxDecoration).color
              : null)
          .whereType<Color>();
      expect(
        fills.any((c) => (c.opacity - 0.80).abs() < 0.02),
        isTrue,
        reason: 'expected an 80%-alpha glass fill, got $fills',
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
      final spec = BoardGlassSpec.resolve(const BoardCardStyle(opacity: 0.95),
          themeGlass: true);
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

    // v1.12.54 (supersedes the v1.12.50 frost contract): the light tray is
    // PURE accent-tinted transparency — no white frost (user: 浅色主题的任务
    // dashboard的容器可以不用磨砂效果，而是可以调节透明度的效果). The frost
    // was a fixed milky pane whose alpha barely changed the look over a
    // near-white canvas, so the slider had nothing to tune; these pins keep
    // the tray sheer, accent-hued and slider-scaled forever.
    test('v1.12.54: the light tray is pure adjustable tint, no frost', () {
      // Full strength = the same accent@5% the non-glass tray uses.
      final full = BoardGlassSpec.lightTrayTint(AppColors.info);
      expect(full, AppColors.info.withOpacity(0.05));
      // The Interface Glass slider scales it down toward full transparency…
      final sheer =
          BoardGlassSpec.lightTrayTint(AppColors.info, tintScale: 0.2);
      expect(sheer.opacity, closeTo(0.0118, 0.001));
      // …and the milky frost can never come back: at full strength the tint
      // must stay DARKER than the old white-based frost would have been.
      final oldFrost =
          Color.alphaBlend(AppColors.info.withOpacity(0.05), Colors.white)
              .withOpacity(0.55);
      expect(full.computeLuminance(), lessThan(oldFrost.computeLuminance()),
          reason: 'a white-based frost returned');
    });

    /// Pumps the real TaskBoardScreen under [interfaceOpacity] (null =
    /// Interface Glass off) and returns the tray fill color of the first
    /// kanban column — the page-level exit that pins the slider wiring.
    /// Each call runs in its OWN testWidgets: a shared tester would reuse the
    /// kanban AnimatedContainer elements across pumps and smear one state
    /// into the next.
    Future<Color> pumpAndReadTrayFill(WidgetTester tester,
        {double? interfaceOpacity}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _TrayProbeRepo();
      await repo.createTask(title: 'Seed task');
      final theme = ThemeModeNotifier()..setTheme(AppThemeMode.violetDusk);
      final appGlass = AppGlassStyleNotifier();
      if (interfaceOpacity != null) {
        await appGlass.setGlass(true);
        await appGlass.setOpacity(interfaceOpacity);
      }
      await tester.pumpWidget(ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => repo),
          themeModeProvider.overrideWith((ref) => theme),
          appGlassStyleProvider.overrideWith((ref) => appGlass),
        ],
        child: MaterialApp(
          theme: AppTheme.buildTheme(AppThemeMode.violetDusk),
          home: const Scaffold(body: TaskBoardScreen()),
        ),
      ));
      // Fixed long frames: the ambient orbs animate forever (so pumpAndSettle
      // never settles), and the tray's AnimatedContainer must finish its
      // 160ms transition before the fill is read.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final container = tester.widget<AnimatedContainer>(find
          .descendant(
              of: find.byType(KanbanColumn),
              matching: find.byType(AnimatedContainer))
          .first);
      return (container.decoration as BoxDecoration).color!;
    }

    testWidgets('v1.12.54: the board tray fill follows Interface Glass',
        (tester) async {
      // The user's state — Interface Glass at 0.2 — must leave the tray
      // sheer (5% × 0.2 = 1.0%), not the old fixed 0.55 frost.
      final sheer = await pumpAndReadTrayFill(tester, interfaceOpacity: 0.2);
      expect(sheer.opacity, lessThan(0.05),
          reason: 'the tray ignored the Interface Glass slider');
      expect(sheer,
          AppColors.statusColor(TaskStatus.planned).withOpacity(0.010));
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('v1.12.54: Interface Glass off keeps the full reference tint',
        (tester) async {
      // Interface Glass off → full accent@5% tint (never the old frost).
      final full = await pumpAndReadTrayFill(tester);
      expect(full, AppColors.statusColor(TaskStatus.planned).withOpacity(0.05));
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('v1.12.33: panels follow Interface Glass, not the card slider', () {
      final spec = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.15, glass: true, blur: 12),
          themeGlass: false,
          appGlass: const AppGlassStyle(glass: true, opacity: 0.6, blur: 22));
      // The card fill stays at the user's 15%…
      expect(spec.opacity, 0.15);
      // …but the KPI strip / quick-add bar are interface panels: they take the
      // interface opacity and blur.
      expect(spec.panelOpacity, 0.6);
      expect(spec.panelBlur, 22);
    });

    test('v1.12.42: the untuned theme-glass default is brightness-aware', () {
      const untuned = BoardCardStyle();
      expect(
          BoardGlassSpec.resolve(untuned,
                  themeGlass: true, brightness: Brightness.light)
              .opacity,
          BoardCardStyle.iosGlassDefaultOpacityLight);
      expect(
          BoardGlassSpec.resolve(untuned,
                  themeGlass: true, brightness: Brightness.dark)
              .opacity,
          BoardCardStyle.iosGlassDefaultOpacity);
      // A slider the user actually tuned is honoured on either canvas…
      expect(
          BoardGlassSpec.resolve(
                  const BoardCardStyle(opacity: 0.8, glass: true),
                  themeGlass: true,
                  brightness: Brightness.light)
              .opacity,
          0.8);
      // …but v1.12.60: on paper the card fill stops at the readable floor
      // (0.35). 0.2 clamps, and the slider still covers a real 35–100% range
      // instead of the old 75–100% sliver. Dark keeps honouring the low
      // value — that is its look.
      expect(
          BoardGlassSpec.resolve(
                  const BoardCardStyle(opacity: 0.2, glass: true),
                  themeGlass: true,
                  brightness: Brightness.light)
              .opacity,
          BoardGlassSpec.cardOpacityFloorLight);
      expect(
          BoardGlassSpec.resolve(
                  const BoardCardStyle(opacity: 0.2, glass: true),
                  themeGlass: true,
                  brightness: Brightness.dark)
              .opacity,
          0.2);
    });

    test('v1.12.60: light card glass is visible and genuinely adjustable', () {
      // The requested state: the light boards open with frost you can SEE,
      // and the opacity control covers a meaningful range.
      expect(BoardCardStyle.iosGlassDefaultOpacityLight, lessThanOrEqualTo(0.7));
      expect(BoardGlassSpec.cardOpacityFloorLight, lessThanOrEqualTo(0.4));
      expect(BoardCardStyle.iosGlassDefaultOpacityLight,
          greaterThan(BoardGlassSpec.cardOpacityFloorLight));
      // A mid-slider value reaches the rendered fill unchanged.
      final mid = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.5, glass: true),
          themeGlass: true,
          brightness: Brightness.light);
      expect(mid.opacity, 0.5);
      expect(mid.glass, isTrue);
      // Untuned light themes open at the visible default, not at 1.0.
      final untuned = BoardGlassSpec.resolve(const BoardCardStyle(),
          themeGlass: true, brightness: Brightness.light);
      expect(untuned.opacity, BoardCardStyle.iosGlassDefaultOpacityLight);
      expect(untuned.opacity, lessThan(0.75));
    });

    test('v1.12.33: panel fill never drops below the readability floor', () {
      final spec = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.15, glass: true),
          themeGlass: true);
      expect(spec.opacity, 0.15);
      expect(spec.panelOpacity, BoardGlassSpec.panelOpacityFloor);
      // Interface Glass can also be dragged low — same floor applies.
      final lowInterface = BoardGlassSpec.resolve(const BoardCardStyle(),
          themeGlass: false,
          appGlass: const AppGlassStyle(glass: true, opacity: 0.2));
      expect(lowInterface.panelOpacity, BoardGlassSpec.panelOpacityFloor);
      // ...and the paper floor is much firmer (v1.12.42).
      final light = BoardGlassSpec.resolve(
          const BoardCardStyle(opacity: 0.15, glass: true),
          themeGlass: true,
          brightness: Brightness.light);
      expect(light.panelOpacity, BoardGlassSpec.panelOpacityFloorLight);
    });

    test('the resolved spec is what the provider exposes for inkBlue',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Default theme is inkBlue (a board-glass theme) with an untuned style.
      // v1.12.42: paper needs a firmer fill — at the dark 72% default the
      // card was the same colour as the canvas and the board lost hierarchy.
      final spec = container.read(boardGlassSpecProvider);
      expect(spec.glass, isTrue);
      expect(spec.opacity, BoardCardStyle.iosGlassDefaultOpacityLight);
      expect(spec.panelOpacity,
          greaterThanOrEqualTo(BoardGlassSpec.panelOpacityFloorLight));
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
      expect(gradient.stops, [0.0, 0.28, 1.0]);
    });

    // v1.12.34 contract: the user rejected the v1.12.33 look as "弯曲立体感太强"
    // (a bright top wash AND a bright bottom rim with a hard inner rim reads as
    // a lens bulging out of the card). Glass must stay a FLAT lit slab, so the
    // specular values are capped — raising them again is a deliberate change,
    // not a silent regression.
    // v1.12.47: the caps were tightened after the user still read the faces as
    // bent (开面弯曲太厉害) — the old caps allowed the 0.14/0.45 dome back in.
    test('stays flat: no lens bulge', () {
      const sheen = GlassSheen();
      expect(sheen.topAlpha, lessThanOrEqualTo(0.08));
      expect(sheen.bottomAlpha, lessThanOrEqualTo(0.03));
      expect(sheen.rimAlpha, 0.0);
      expect(sheen.topFade, lessThanOrEqualTo(0.30));
    });

    test('fillOver mirrors the same flat profile', () {
      const sheen = GlassSheen();
      final gradient = GlassSheen.fillOver(Colors.white.withOpacity(0.72));
      expect(gradient.stops!.first, 0.0);
      expect(gradient.stops![1], sheen.topFade);
      // Top wash adds at most ~7% white; the bottom stays near the base.
      final base = Colors.white.withOpacity(0.72);
      final topGain = gradient.colors.first.a - base.a;
      final bottomGain = gradient.colors.last.a - base.a;
      expect(topGain, lessThanOrEqualTo(0.16));
      expect(bottomGain, lessThanOrEqualTo(0.05));
    });
  });

  // v1.12.35 regression (user screenshot: the KPI accent icon printed ON TOP
  // of "TO DO" / "IN PROGRESS"). A Stack sizes itself to its non-positioned
  // children under LOOSENED constraints, so wrapping the card content in the
  // glass shell made the content shrink-wrap to the label text — and the
  // `Positioned(right: 10)` chip resolved against that narrow box instead of
  // the card. GlassSurface now pins the content to the full card width, so the
  // chip lands in the same place with glass on and with glass off.
  group('GlassSurface pins the content to the card width', () {
    Widget content() => Stack(
          children: const [
            Positioned(
              right: 10,
              top: 10,
              child: SizedBox(key: Key('chip'), width: 26, height: 26),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 11, 14, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('IN PROGRESS', style: TextStyle(fontSize: 10)),
                  Text('8', style: TextStyle(fontSize: 21)),
                  Text('1 high priority', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        );

    Widget harness(bool glass) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: const Key('cardBox'),
                width: 300,
                height: 90,
                child: Row(
                  children: [
                    Expanded(
                      child: glass
                          ? GlassSurface(
                              borderRadius: 16,
                              blur: 8,
                              color: Colors.white24,
                              rimAlpha: 0.30,
                              content: content(),
                            )
                          : content(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    for (final glass in [false, true]) {
      testWidgets('top-right chip hugs the card edge (glass: $glass)',
          (tester) async {
        await tester.pumpWidget(harness(glass));
        await tester.pumpAndSettle();
        expect(find.text('IN PROGRESS'), findsOneWidget);
        if (glass) expect(find.byType(BackdropFilter), findsOneWidget);

        final box = tester.getRect(find.byKey(const Key('cardBox')));
        final chip = tester.getRect(find.byKey(const Key('chip')));
        final label = tester.getRect(find.text('IN PROGRESS'));
        // The bug: the chip followed the text instead of the card edge.
        expect(chip.right, closeTo(box.right - 10, 0.5));
        expect(chip.left, greaterThan(label.right));
      });
    }
  });
}

