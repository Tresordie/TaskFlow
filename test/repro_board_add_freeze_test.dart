import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/providers/task_providers.dart';
import 'package:taskflow/presentation/task_board/kanban_column.dart';
import 'package:taskflow/presentation/task_board/task_board_screen.dart';

/// In-memory repo so the test drives the REAL screen/notifier stack without
/// Isar. Only the two methods the add flow touches are overridden.
class _FakeRepo extends TaskRepository {
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

void main() {
  Future<_FakeRepo> pumpBoard(WidgetTester tester,
      {bool seedTasks = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo();
    if (seedTasks) {
      // An empty board renders the _EmptyState, not the columns — the
      // inline "+" add field only exists once a column is on screen.
      await repo.createTask(title: 'Seed task');
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [taskRepositoryProvider.overrideWith((ref) => repo)],
      child: MaterialApp(
        theme: AppTheme.buildTheme(AppThemeMode.inkBlue),
        home: const Scaffold(body: TaskBoardScreen()),
      ),
    ));
    // A few frames only: the backdrop orbs animate forever, so
    // pumpAndSettle would never settle regardless of any bug.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return repo;
  }

  testWidgets('quick-add does not hang the board', (tester) async {
    await pumpBoard(tester);

    // Collapsed quick-add bar = exactly one TextField on the page.
    await tester.enterText(find.byType(TextField), 'Repro task');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Repro task'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('column inline add does not hang the board', (tester) async {
    await pumpBoard(tester, seedTasks: true);

    // The To-Do column's "+" opens the inline add field. Regression: the
    // outer Focus and the TextField used to share one FocusNode, which
    // corrupts the focus tree (a node becomes its own ancestor). The debug
    // assert reads "Tried to make a child into a parent of itself"; in a
    // release build it spins the UI isolate and the whole app freezes. Any
    // exception thrown while building the field fails the test below.
    await tester.tap(find.byIcon(Icons.add).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final addField = find.widgetWithText(TextField, 'New task...');
    expect(addField, findsOneWidget);

    // ESC must still close the field (bubbles to the outer Focus).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.widgetWithText(TextField, 'New task...'), findsNothing);

    await tester.tap(find.byIcon(Icons.add).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(addField, 'Column task');
    await tester.tap(find.byIcon(Icons.add_circle).first);

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Column task'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('column inline "more options" opens the composer and creates',
      (tester) async {
    await pumpBoard(tester, seedTasks: true);

    await tester.tap(find.byIcon(Icons.add).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(
        find.widgetWithText(TextField, 'New task...'), 'Composer task');

    // v1.12.46: the edit_note button next to the inline add — scoped to the
    // column because the quick-add bar carries its own composer entry.
    await tester.tap(find.descendant(
        of: find.byType(KanbanColumn), matching: find.byIcon(Icons.edit_note)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('New Task'), findsOneWidget);

    // The typed title is carried into the dialog (first field inside it).
    final dialogTitle = tester.widget<TextField>(find
        .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
        .first);
    expect(dialogTitle.controller!.text, 'Composer task');

    final createBtn = find.widgetWithText(ElevatedButton, 'Create');
    await tester.ensureVisible(createBtn);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(createBtn);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Created card lands on the board, dialog gone, inline field folded.
    expect(find.text('Composer task'), findsOneWidget);
    expect(find.text('New Task'), findsNothing);
    expect(find.widgetWithText(TextField, 'New task...'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
