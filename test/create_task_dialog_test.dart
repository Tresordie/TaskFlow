import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/providers/task_providers.dart';
import 'package:taskflow/presentation/task_board/create_task_dialog.dart';

/// v1.12.46: the full New Task form behind the kanban column inline-add and
/// the top quick-add bar's "more options" buttons. These tests drive the
/// dialog standalone (no board behind it → pumpAndSettle is safe) with a
/// capturing fake repo, so every field's value reaching createTask is
/// asserted, not just rendered.
class _CapturingRepo extends TaskRepository {
  Map<String, Object?>? lastCreate;

  @override
  Future<List<Task>> getAllTasks() async => const [];

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
    lastCreate = {
      'title': title,
      'description': description,
      'priority': priority,
      'tags': tags,
      'subSteps': subSteps,
      'dueDate': dueDate,
      'project': project,
      'status': status,
    };
    return 1;
  }
}

Future<({WidgetTester tester, _CapturingRepo repo})> pumpDialog(
    WidgetTester tester,
    {CreateTaskDialog Function()? dialog}) async {
  SharedPreferences.setMockInitialValues({});
  // The full form is ~850px tall — give it a viewport where nothing is
  // below the fold, so taps on the action row land.
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _CapturingRepo();
  await tester.pumpWidget(ProviderScope(
    overrides: [taskRepositoryProvider.overrideWith((ref) => repo)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) =>
                  dialog?.call() ?? const CreateTaskDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (tester: tester, repo: repo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows every field and gates Create on the title',
      (tester) async {
    await pumpDialog(tester);

    for (final label in [
      'Title',
      'Project',
      'Due Date',
      'Description',
      'Priority',
      'Tags',
      'Sub-tasks',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing $label');
    }
    expect(find.text('New Task'), findsOneWidget);

    final create = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create'));
    expect(create.onPressed, isNull, reason: 'Create must be disabled empty');
  });

  testWidgets('all fields reach createTask', (tester) async {
    final ctx = await pumpDialog(tester);
    final t = ctx.tester;

    await t.enterText(find.byType(TextField).first, 'Full task');
    await t.enterText(
        find.widgetWithText(TextField, 'Project name (e.g. Cosmo, Metro)'),
        'Cosmo');
    await t.enterText(
        find.widgetWithText(
            TextField, 'Add more details (optional, Markdown supported)'),
        'Run the dyno sweep');
    await t.tap(find.text('P1 High'));
    await t.enterText(find.widgetWithText(TextField, 'Tags (a, b)'),
        'alpha, beta');
    await t.enterText(
        find.widgetWithText(TextField, 'Add a sub-task and press Enter'),
        'Torque check');
    await t.tap(find.widgetWithIcon(IconButton, Icons.add));
    await t.pumpAndSettle();
    expect(find.text('Torque check'), findsOneWidget,
        reason: 'sub-step chip must appear');

    await t.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await t.pumpAndSettle();

    expect(find.text('New Task'), findsNothing, reason: 'dialog must close');
    final c = ctx.repo.lastCreate!;
    expect(c['title'], 'Full task');
    expect(c['description'], 'Run the dyno sweep');
    expect(c['priority'], Priority.p1High);
    expect(c['tags'], ['alpha', 'beta']);
    expect(c['subSteps'], ['Torque check']);
    expect(c['project'], 'Cosmo');
    expect(c['dueDate'], isNull);
    expect(c['status'], TaskStatus.planned);
  });

  testWidgets('initial* values pre-fill title, project, priority, due, status',
      (tester) async {
    final due = DateTime(2026, 11, 3);
    final ctx = await pumpDialog(
      tester,
      dialog: () => CreateTaskDialog(
        initialTitle: 'Drafted in the column',
        initialStatus: TaskStatus.blocked,
        initialPriority: Priority.p0Critical,
        initialProject: 'Metro',
        initialDueDate: due,
      ),
    );
    final t = ctx.tester;

    expect(
        t.widget<TextField>(find.byType(TextField).first)
            .controller!
            .text,
        'Drafted in the column');
    expect(find.text('Metro'), findsWidgets); // project field prefilled
    expect(find.textContaining('2026-11-03'), findsOneWidget,
        reason: 'due chip shows the prefilled date');
    // P0 selected → its label is rendered in the selected style; just
    // confirm the chip exists and P2 is not implied by submitting.
    expect(find.text('P0 Critical'), findsOneWidget);

    await t.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await t.pumpAndSettle();
    final c = ctx.repo.lastCreate!;
    expect(c['status'], TaskStatus.blocked);
    expect(c['priority'], Priority.p0Critical);
    expect(c['project'], 'Metro');
    expect(c['dueDate'], due);
  });

  testWidgets('cancel creates nothing', (tester) async {
    final ctx = await pumpDialog(tester);
    await ctx.tester.enterText(find.byType(TextField).first, 'Never saved');
    await ctx.tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await ctx.tester.pumpAndSettle();

    expect(find.text('New Task'), findsNothing);
    expect(ctx.repo.lastCreate, isNull);
  });
}
