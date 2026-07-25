import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:taskflow/app/app.dart';
import 'package:taskflow/core/markdown/latex_support.dart';
import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/presentation/shared/app_shell.dart';
import 'package:taskflow/presentation/shared/custom_title_bar.dart';
import 'package:taskflow/presentation/shared/wheel_forward.dart';
import 'package:taskflow/presentation/task_detail/task_detail_screen.dart';
import 'package:taskflow/providers/task_providers.dart';

Widget _latexBody(String data) {
  const style = TextStyle(fontSize: 14, color: Colors.black);
  return MaterialApp(
    home: Scaffold(
      body: MarkdownBody(
        data: data,
        styleSheet: MarkdownStyleSheet(
          p: style,
          textAlign: WrapAlignment.start,
        ),
        inlineSyntaxes: LatexMarkdown.syntaxes(),
        builders: LatexMarkdown.builders(style),
      ),
    ),
  );
}

void main() {
  testWidgets('valid inline LaTeX renders a Math widget', (tester) async {
    await tester.pumpWidget(_latexBody(r'Energy: $E=mc^2$'));
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets(r'display LaTeX ($$..$$) renders a Math widget', (tester) async {
    await tester.pumpWidget(_latexBody(r'$$\frac{a}{b}$$'));
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('malformed TeX never crashes the log view', (tester) async {
    // Depending on the flutter_math_fork version, malformed TeX either
    // renders leniently (Math widget) or throws during build — in the
    // latter case LatexBuilder falls back to raw red-italic source text.
    // Either way: no exception may escape and *something* must render.
    await tester.pumpWidget(_latexBody(r'$\frac{1}{2$'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final renderedMath = find.byType(Math).evaluate().isNotEmpty;
    final renderedFallback = find.textContaining('frac').evaluate().isNotEmpty;
    expect(renderedMath || renderedFallback, isTrue);
  });

  testWidgets('CustomTitleBar renders app name on desktop', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomTitleBar())),
    );
    await tester.pumpAndSettle();
    // `flutter test` always runs on a desktop host VM, where the custom
    // title bar is rendered (it shrinks away only on iOS/Android devices).
    expect(find.text('TaskFlow'), findsOneWidget);
  });

  testWidgets(
      'execution log entries support cross-block drag selection via the app-wide SelectionArea',
      (tester) async {
    // Selection history: v1.2.9 added a screen-local SelectionArea; v1.4.24
    // added an app-wide one in MaterialApp.builder (broken: it sits above
    // the Navigator's Overlay, which SelectionArea's SelectableRegion
    // requires); v1.4.25 moved it into AppShell but markdown still rendered
    // as SelectableText (selectable: true), whose per-block gesture
    // detectors only allowed single-block selection — no cross-block drag,
    // no select-all. v1.4.26 renders markdown as Text.rich (selectable:
    // false), which registers with the SelectionArea for unified
    // cross-block selection. Mirror AppShell here: one SelectionArea
    // wrapping the page inside the route.
    await tester.binding.setSurfaceSize(const Size(1280, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));

    final task = Task()
      ..id = 1
      ..uid = 'sel'
      ..title = 'Selectable task title'
      ..description = 'Selectable description text'
      ..status = TaskStatus.inProgress
      ..createdAt = DateTime(2026, 7, 22, 9, 0);
    task.executionLog.add(ExecutionEntry()
      ..uid = 'e1'
      ..content = 'first selectable log entry body'
      ..type = EntryType.note
      ..timestamp = DateTime(2026, 7, 22, 10, 30));
    task.executionLog.add(ExecutionEntry()
      ..uid = 'e2'
      ..content = 'second selectable log entry body'
      ..type = EntryType.note
      ..timestamp = DateTime(2026, 7, 22, 11, 0));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskListProvider.overrideWith((ref) => _StaticTasks([task])),
        ],
        // Replicate production exactly: use the app's real scroll
        // behavior (AppScrollBehavior deliberately excludes mouse drag
        // devices so mouse drags select text instead of scrolling).
        child: MaterialApp(
          scrollBehavior: AppScrollBehavior(),
          home: SelectionArea(child: TaskDetailScreen(taskId: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);

    // Both entries render through AppMarkdownBody as Text.rich and are
    // registered with the SelectionArea. The log lists entries
    // newest-first, so the SECOND entry (11:00) renders ABOVE the first
    // (10:30). Drag the mouse top-down across both: the unified selection
    // must cover BOTH paragraphs (this is the block selection the user
    // performs).
    final topFinder = find.textContaining('second selectable log entry body',
        findRichText: true);
    final bottomFinder = find.textContaining('first selectable log entry body',
        findRichText: true);
    expect(topFinder, findsOneWidget);
    expect(bottomFinder, findsOneWidget);

    final topRect = tester.getRect(topFinder);
    final bottomRect = tester.getRect(bottomFinder);
    final gesture = await tester.startGesture(
      topRect.topLeft + const Offset(2, 2),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    // Incremental moves with pumps in between, mirroring Flutter's own
    // scrollable_selection_test gesture sequence.
    await gesture.moveTo(topRect.bottomRight - const Offset(2, 2));
    await tester.pump();
    await gesture.moveTo(bottomRect.bottomRight - const Offset(2, 2));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final topParagraph = tester.renderObject<RenderParagraph>(topFinder);
    final bottomParagraph = tester.renderObject<RenderParagraph>(bottomFinder);
    expect(topParagraph.selections.any((s) => !s.isCollapsed), isTrue,
        reason: 'cross-block drag must select the top entry');
    expect(bottomParagraph.selections.any((s) => !s.isCollapsed), isTrue,
        reason: 'cross-block drag must extend into the bottom entry');
  });

  testWidgets(
      'production shell: rich-markdown log entry supports cross-block drag selection',
      (tester) async {
    // v1.4.27 repro harness: after v1.4.26 the simplified selection test
    // passed while the real app still failed for the user. This test
    // closes the fidelity gap — it mounts the page through the REAL
    // production tree (GoRouter ShellRoute -> AppShell with sidebar,
    // rounded panel, custom title bar and the app-wide SelectionArea,
    // AppTheme, AppScrollBehavior) and feeds the log a rich markdown
    // entry shaped like real user content (emoji section headers, bold,
    // bullet + numbered lists with nesting) instead of a plain one-liner.
    await tester.binding.setSurfaceSize(const Size(1280, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));

    const richContent = '📄 **Work Summary**\n'
        '- Foxlink provided a list of incoming materials with serial numbers (SN) for the FATP assembly line.\n'
        '- The current mapping file does not include the left brake lever, right brake lever, and caliper.\n'
        '- The SNs for these three items are already stored in the SFC database.\n'
        '\n'
        '📄 **Detailed Breakdown**\n'
        '1. **Confirmation of SN Coverage**\n'
        '   Compared the bill of materials with the mapping file.\n'
        '2. **Feasibility of Adding Items**\n'
        '   - Cosmo bikes have already shipped and deployed.\n'
        '   - Only one master mapping file per work order is allowed.\n'
        '3. **Effective Date and Follow-up Arrangements**\n'
        '   Implementation by Foxlink, effective from the next production batch.';

    final task = Task()
      ..id = 1
      ..uid = 'rich'
      ..title = 'Cosmo Left/Right brake lever and caliper mapping'
      ..status = TaskStatus.inProgress
      ..createdAt = DateTime(2026, 7, 25, 12, 14);
    task.executionLog.add(ExecutionEntry()
      ..uid = 'r1'
      ..content = richContent
      ..type = EntryType.note
      ..timestamp = DateTime(2026, 7, 25, 12, 54));

    // Same route structure as lib/app/router.dart: the detail page is a
    // child of the ShellRoute, so AppShell (and its SelectionArea) wraps
    // it exactly as in production.
    final router = GoRouter(
      initialLocation: '/task/1',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/task/:id',
              pageBuilder: (context, state) => MaterialPage(
                child: TaskDetailScreen(
                    taskId: int.parse(state.pathParameters['id']!)),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskListProvider.overrideWith((ref) => _StaticTasks([task])),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          scrollBehavior: AppScrollBehavior(),
          theme: AppTheme.buildTheme(AppThemeMode.indigoLight),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The app-wide SelectionArea comes from AppShell — exactly one.
    expect(find.byType(SelectionArea), findsOneWidget);

    final headFinder = find.textContaining('Work Summary', findRichText: true);
    final bulletFinder = find.textContaining(
        'current mapping file does not include',
        findRichText: true);
    final tailFinder =
        find.textContaining('Detailed Breakdown', findRichText: true);
    expect(headFinder, findsOneWidget);
    expect(bulletFinder, findsOneWidget);
    expect(tailFinder, findsOneWidget);

    final headRect = tester.getRect(headFinder);
    final tailRect = tester.getRect(tailFinder);
    final start = headRect.topLeft + const Offset(2, 2);
    final end = tailRect.bottomRight - const Offset(2, 2);
    final gesture =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();

    // Incremental descent across the markdown blocks (Flutter's own
    // scrollable_selection_test pattern).
    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / steps)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    RenderParagraph paragraphOf(Finder f) =>
        tester.renderObject<RenderParagraph>(f);
    expect(
        paragraphOf(headFinder).selections.any((s) => !s.isCollapsed), isTrue,
        reason: 'section header block must be selected');
    expect(
        paragraphOf(bulletFinder).selections.any((s) => !s.isCollapsed), isTrue,
        reason: 'middle bullet block must be inside the selection range');
    expect(
        paragraphOf(tailFinder).selections.any((s) => !s.isCollapsed), isTrue,
        reason: 'tail block must be selected');
  });

  testWidgets(
      'add-child field nests one level below the tapped parent, not the last descendant',
      (tester) async {
    // Regression (v1.4.11): when "+" was tapped on a row that already had
    // children, the inline field attached to the subtree's LAST descendant
    // — rendering one level too deep and nesting new children under the
    // wrong parent.
    // Desktop-like surface: the default 800x600 test window is too short
    // for the detail screen and would squeeze the Execution Log section.
    await tester.binding.setSurfaceSize(const Size(1280, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final task = Task()
      ..id = 1
      ..uid = 'nest'
      ..title = 'Nested checklist'
      ..status = TaskStatus.inProgress
      ..createdAt = DateTime(2026, 7, 22, 9, 0);
    task.subSteps = [
      SubStep()
        ..uid = 'p'
        ..title = 'parent step'
        ..depth = 0,
      SubStep()
        ..uid = 'c'
        ..title = 'child step'
        ..depth = 1
        ..parentUid = 'p',
    ];

    final notifier = _CapturingTasks([task]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskListProvider.overrideWith((ref) => notifier),
        ],
        child: const MaterialApp(home: TaskDetailScreen(taskId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    // Tap "+" on the PARENT row (first in DFS order).
    final addButtons = find.byTooltip('Add nested sub-step');
    expect(addButtons, findsNWidgets(2));
    await tester.tap(addButtons.first);
    await tester.pumpAndSettle();

    final field = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == 'Add nested sub-step…');
    expect(field, findsOneWidget);

    // The field must sit exactly one indent level below the parent —
    // aligned with the existing child row — not a full extra level down.
    final parentLeft = tester.getTopLeft(find.text('parent step')).dx;
    final childLeft = tester.getTopLeft(find.text('child step')).dx;
    final fieldLeft = tester.getTopLeft(field).dx;
    final oneLevel = childLeft - parentLeft;
    expect(
      (fieldLeft - parentLeft - oneLevel).abs(),
      lessThan((fieldLeft - parentLeft - 2 * oneLevel).abs()),
      reason: 'field should be ~one indent level deep, not two',
    );

    // Submitting must attach the new child to the tapped parent.
    await tester.enterText(field, 'new child');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(notifier.lastParentUid, 'p');
  });

  testWidgets(
      'WheelForward scrolls the primary list when wheeling over the header',
      (tester) async {
    late ScrollController primary;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              primary = PrimaryScrollController.of(context);
              return Column(
                children: [
                  WheelForward(
                    child: Container(
                      height: 100,
                      color: const Color(0xFFEEEEEE),
                      child: const Text('fixed header'),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: List.generate(
                        50,
                        (i) => SizedBox(height: 60, child: Text('row $i')),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(primary.position.pixels, 0.0);

    // Wheel over the FIXED HEADER (y=50 is inside the 100px header), not the
    // list: WheelForward must forward it to the primary scrollable.
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(400, 50),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();
    expect(primary.position.pixels, greaterThan(0.0));
  });
}

/// Serves a fixed task list without ever opening the Isar database (the
/// real [TaskListNotifier] kicks off a DB load in its constructor).
class _StaticTasks extends TaskListNotifier {
  _StaticTasks(List<Task> tasks) : super(TaskRepository()) {
    state = AsyncValue.data(tasks);
  }

  @override
  Future<void> loadTasks() async {} // no DB in widget tests
}

/// Like [_StaticTasks] but records the parentUid passed to addSubStep so
/// tests can assert which parent a nested sub-step attaches to.
class _CapturingTasks extends _StaticTasks {
  _CapturingTasks(super.tasks);

  String? lastParentUid;

  @override
  Future<void> addSubStep(int taskId, String title, {String? parentUid}) async {
    lastParentUid = parentUid;
  }
}
