import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/markdown/latex_support.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
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

  testWidgets('task detail read-only content sits in a SelectionArea',
      (tester) async {
    // v1.2.9: task content and Execution Log entries must be selectable
    // and copyable in display mode. Plain Text / MarkdownBody are NOT
    // selectable by default — the whole screen must live under a
    // SelectionArea for mouse selection + Ctrl-C / right-click copy.
    final task = Task()
      ..id = 1
      ..uid = 'sel'
      ..title = 'Selectable task title'
      ..description = 'Selectable description text'
      ..status = TaskStatus.inProgress
      ..createdAt = DateTime(2026, 7, 22, 9, 0);
    task.executionLog.add(ExecutionEntry()
      ..uid = 'e1'
      ..content = 'selectable log entry body'
      ..type = EntryType.note
      ..timestamp = DateTime(2026, 7, 22, 10, 30));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskListProvider.overrideWith((ref) => _StaticTasks([task])),
        ],
        child: const MaterialApp(home: TaskDetailScreen(taskId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('Selectable task title'), findsOneWidget);
    // The log entry is rendered through MarkdownBody (RichText), hence
    // findRichText.
    expect(
      find.textContaining('selectable log entry body', findRichText: true),
      findsOneWidget,
    );
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
