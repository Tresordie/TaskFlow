// Release-mode repro for the "Execution Log cannot be selected" bug.
//
// The widget test `production shell: rich-markdown log entry supports
// cross-block drag selection` passes in `flutter test` (debug), and the
// standalone DEBUG exe selects fine — but the standalone RELEASE exe does
// not. This integration test mounts the exact same production tree and runs
// it under `flutter test integration_test -d windows --release` (AOT,
// asserts off) to decide whether the failure reproduces with synthesized
// pointer events in release mode:
//   * FAILS here  -> framework/app-level debug-vs-release code divergence
//                    (bisect inside the framework/app).
//   * PASSES here -> release framework selection logic is fine with proper
//                    pointer events; the standalone-exe failure must come
//                    from real OS event delivery / engine differences.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:taskflow/app/app.dart';
import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/presentation/shared/app_shell.dart';
import 'package:taskflow/presentation/task_detail/task_detail_screen.dart';
import 'package:taskflow/providers/task_providers.dart';

class _StaticTasks extends TaskListNotifier {
  _StaticTasks(List<Task> tasks) : super(TaskRepository()) {
    state = AsyncValue.data(tasks);
  }

  @override
  Future<void> loadTasks() async {} // no DB needed
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RELEASE: production shell cross-block drag selection',
      (tester) async {
    debugPrint('SELDIAG mode: kReleaseMode=$kReleaseMode kDebugMode=$kDebugMode '
        'kProfileMode=$kProfileMode');

    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    expect(find.byType(SelectionArea), findsOneWidget,
        reason: 'app-wide SelectionArea must be present');

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
    debugPrint('SELDIAG drag start=$start end=$end');

    final gesture =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();

    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / steps)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    RenderParagraph paragraphOf(Finder f) =>
        tester.renderObject<RenderParagraph>(f);

    final headSel = paragraphOf(headFinder).selections;
    final bulletSel = paragraphOf(bulletFinder).selections;
    final tailSel = paragraphOf(tailFinder).selections;
    debugPrint('SELDIAG headSel=$headSel');
    debugPrint('SELDIAG bulletSel=$bulletSel');
    debugPrint('SELDIAG tailSel=$tailSel');

    expect(headSel.any((s) => !s.isCollapsed), isTrue,
        reason: 'RELEASE: section header block must be selected');
    expect(bulletSel.any((s) => !s.isCollapsed), isTrue,
        reason: 'RELEASE: middle bullet block must be inside the selection');
    expect(tailSel.any((s) => !s.isCollapsed), isTrue,
        reason: 'RELEASE: tail block must be selected');
  });
}
