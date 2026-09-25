import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/providers/task_providers.dart';

/// v1.10.0 / v1.11.0 contract tests for the Today kanban board data layer:
/// column bucketing (per board dimension), in-column ordering, quick
/// filters and KPI stats. All functions under test are pure — no Isar
/// needed.

Task _task(
  int id, {
  TaskStatus status = TaskStatus.planned,
  Priority priority = Priority.p2Medium,
  DateTime? due,
  DateTime? created,
  String project = '',
}) {
  return Task()
    ..id = id
    ..uid = 'uid-$id'
    ..title = 'Task $id'
    ..status = status
    ..priority = priority
    ..createdAt = created ?? DateTime(2026, 9, 1, 10)
    ..dueDate = due
    ..project = project;
}

void main() {
  group('buildKanbanColumns · status dimension', () {
    test('buckets tasks into the four fixed columns in order', () {
      final columns = buildKanbanColumns([
        _task(1, status: TaskStatus.blocked),
        _task(2, status: TaskStatus.completed),
        _task(3, status: TaskStatus.inProgress),
        _task(4, status: TaskStatus.planned),
      ], BoardDimension.status);

      expect(columns.map((c) => c.key).toList(), [
        TaskStatus.planned.name,
        TaskStatus.inProgress.name,
        TaskStatus.completed.name,
        TaskStatus.blocked.name,
      ]);
      expect(columns[0].tasks.map((t) => t.id), [4]);
      expect(columns[1].tasks.map((t) => t.id), [3]);
      expect(columns[2].tasks.map((t) => t.id), [2]);
      expect(columns[3].tasks.map((t) => t.id), [1]);
    });

    test('archived tasks render in the Done column (app-wide convention)',
        () {
      final columns = buildKanbanColumns([
        _task(1, status: TaskStatus.archived),
        _task(2, status: TaskStatus.completed),
      ], BoardDimension.status);
      expect(columns[2].tasks.map((t) => t.id).toSet(), {1, 2});
    });
  });

  group('buildKanbanColumns · priority dimension', () {
    test('buckets into the four fixed P0–P3 columns, empty ones included',
        () {
      final columns = buildKanbanColumns([
        _task(1, priority: Priority.p3Low),
        _task(2, priority: Priority.p0Critical),
      ], BoardDimension.priority);

      expect(columns.map((c) => c.key).toList(), ['0', '1', '2', '3']);
      expect(columns[0].tasks.map((t) => t.id), [2]);
      expect(columns[1].tasks, isEmpty);
      expect(columns[2].tasks, isEmpty);
      expect(columns[3].tasks.map((t) => t.id), [1]);
    });
  });

  group('buildKanbanColumns · project dimension', () {
    test('one column per project, alphabetical, No Project last', () {
      final columns = buildKanbanColumns([
        _task(1, project: 'Cosmo'),
        _task(2, project: 'alpha'),
        _task(3),
        _task(4, project: 'Cosmo'),
      ], BoardDimension.project);

      expect(columns.map((c) => c.key).toList(), ['alpha', 'Cosmo', '']);
      expect(columns[0].tasks.map((t) => t.id), [2]);
      expect(columns[1].tasks.map((t) => t.id).toSet(), {1, 4});
      expect(columns[2].tasks.map((t) => t.id), [3]);
    });

    test('always yields at least one column even with no tasks', () {
      final columns = buildKanbanColumns(const [], BoardDimension.project);
      expect(columns.map((c) => c.key), ['']);
      expect(columns.single.tasks, isEmpty);
    });
  });

  group('sortKanbanTasks', () {
    test('earliest due first, no due date last, then priority, then newest',
        () {
      final list = [
        _task(1, due: DateTime(2026, 9, 10), priority: Priority.p2Medium),
        _task(2, due: null, priority: Priority.p0Critical),
        _task(3, due: DateTime(2026, 9, 5), priority: Priority.p3Low),
        _task(4,
            due: null,
            priority: Priority.p2Medium,
            created: DateTime(2026, 9, 2)),
        _task(5,
            due: null,
            priority: Priority.p1High,
            created: DateTime(2026, 9, 8)),
      ];
      final sorted = sortKanbanTasks(list);
      // Dated tasks by due date asc; undated by priority asc (P0 first)
      // then newest first.
      expect(sorted.map((t) => t.id).toList(), [3, 1, 2, 5, 4]);
    });
  });

  group('applyBoardQuickFilter', () {
    final now = DateTime(2026, 9, 25, 15);
    test('all keeps everything', () {
      final tasks = [
        _task(1, due: DateTime(2026, 9, 25)),
        _task(2),
      ];
      expect(applyBoardQuickFilter(tasks, BoardQuickFilter.all, now).length, 2);
    });

    test('dueToday keeps only tasks due on the same day', () {
      final tasks = [
        _task(1, due: DateTime(2026, 9, 25, 9)),
        _task(2, due: DateTime(2026, 9, 24)),
        _task(3),
      ];
      expect(
        applyBoardQuickFilter(tasks, BoardQuickFilter.dueToday, now)
            .map((t) => t.id),
        [1],
      );
    });

    test('highPriority keeps only P0 and P1', () {
      final tasks = [
        _task(1, priority: Priority.p0Critical),
        _task(2, priority: Priority.p1High),
        _task(3, priority: Priority.p2Medium),
        _task(4, priority: Priority.p3Low),
      ];
      expect(
        applyBoardQuickFilter(tasks, BoardQuickFilter.highPriority, now)
            .map((t) => t.id)
            .toSet(),
        {1, 2},
      );
    });
  });

  group('buildKanbanBoardData KPIs', () {
    final now = DateTime(2026, 9, 25, 15);
    final todayStart = DateTime(2026, 9, 25);

    test('today progress counts done vs due today', () {
      final data = buildKanbanBoardData(
        allTasks: [
          _task(1, due: DateTime(2026, 9, 25, 9), status: TaskStatus.completed),
          _task(2, due: DateTime(2026, 9, 25, 17)),
          _task(3, due: DateTime(2026, 9, 26)),
        ],
        filteredTasks: [
          _task(1, due: DateTime(2026, 9, 25, 9), status: TaskStatus.completed),
          _task(2, due: DateTime(2026, 9, 25, 17)),
          _task(3, due: DateTime(2026, 9, 26)),
        ],
        quickFilter: BoardQuickFilter.all,
        dimension: BoardDimension.status,
        now: now,
      );
      expect(data.dueTodayTotal, 2);
      expect(data.dueTodayDone, 1);
      expect(data.todayProgressPct, closeTo(0.5, 0.0001));
    });

    test('overdue counts past-due unfinished tasks but not blocked ones', () {
      final data = buildKanbanBoardData(
        allTasks: [
          _task(1, due: todayStart.subtract(const Duration(days: 1))),
          _task(2,
              due: todayStart.subtract(const Duration(days: 2)),
              status: TaskStatus.blocked),
          _task(3,
              due: todayStart.subtract(const Duration(days: 3)),
              status: TaskStatus.completed),
          _task(4),
        ],
        filteredTasks: const [],
        quickFilter: BoardQuickFilter.all,
        dimension: BoardDimension.status,
        now: now,
      );
      expect(data.overdueCount, 1);
    });

    test('in-progress / done / completion stats', () {
      final data = buildKanbanBoardData(
        allTasks: [
          _task(1, status: TaskStatus.inProgress, priority: Priority.p0Critical),
          _task(2, status: TaskStatus.inProgress, priority: Priority.p3Low),
          _task(3, status: TaskStatus.completed),
          _task(4, status: TaskStatus.archived),
          _task(5),
        ],
        filteredTasks: const [],
        quickFilter: BoardQuickFilter.all,
        dimension: BoardDimension.status,
        now: now,
      );
      expect(data.inProgressCount, 2);
      expect(data.highPriorityInProgress, 1);
      expect(data.doneCount, 2);
      expect(data.totalCount, 5);
      expect(data.completionPct, closeTo(0.4, 0.0001));
    });

    test('empty board divides by zero safely', () {
      final data = buildKanbanBoardData(
        allTasks: const [],
        filteredTasks: const [],
        quickFilter: BoardQuickFilter.all,
        dimension: BoardDimension.status,
        now: now,
      );
      expect(data.todayProgressPct, 0);
      expect(data.completionPct, 0);
      expect(data.columns.every((c) => c.tasks.isEmpty), isTrue);
    });
  });
}
