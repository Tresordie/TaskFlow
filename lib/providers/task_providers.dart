import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';

// Repository provider
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository();
});

// All tasks stream
final taskListProvider =
    StateNotifierProvider<TaskListNotifier, AsyncValue<List<Task>>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return TaskListNotifier(repo);
});

// Selected task
final selectedTaskProvider = StateProvider<Task?>((ref) => null);

// Filter providers
final taskFilterProvider = StateProvider<TaskFilter>((ref) => TaskFilter());

// Filtered tasks (derived)
final filteredTaskListProvider = Provider<List<Task>>((ref) {
  final tasksAsync = ref.watch(taskListProvider);
  final filter = ref.watch(taskFilterProvider);

  return tasksAsync.when(
    data: (tasks) {
      var filtered = tasks;
      if (filter.status != null) {
        filtered = filtered.where((t) => t.status == filter.status).toList();
      }
      if (filter.priority != null) {
        filtered =
            filtered.where((t) => t.priority == filter.priority).toList();
      }
      if (filter.tag != null && filter.tag!.isNotEmpty) {
        filtered = filtered.where((t) => t.tags.contains(filter.tag)).toList();
      }
      if (filter.date != null) {
        final dayStart =
            DateTime(filter.date!.year, filter.date!.month, filter.date!.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        filtered = filtered
            .where((t) =>
                t.createdAt.isAfter(dayStart) && t.createdAt.isBefore(dayEnd))
            .toList();
      }
      return filtered;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// Tasks grouped by priority
final groupedTasksProvider = Provider<Map<Priority, List<Task>>>((ref) {
  final tasks = ref.watch(filteredTaskListProvider);
  final grouped = <Priority, List<Task>>{
    Priority.p0Critical: [],
    Priority.p1High: [],
    Priority.p2Medium: [],
    Priority.p3Low: [],
  };
  for (final task in tasks) {
    grouped[task.priority]!.add(task);
  }
  return grouped;
});

// ─── Kanban board (v1.10.0: Today page redesign) ────────────────────────────

/// Quick filter pills shown in the Today board header.
enum BoardQuickFilter {
  all('All'),
  dueToday('Due Today'),
  highPriority('High Priority');

  final String label;
  const BoardQuickFilter(this.label);
}

final boardQuickFilterProvider =
    StateProvider<BoardQuickFilter>((ref) => BoardQuickFilter.all);

/// Board dimension (v1.11.0): what the Today kanban columns represent.
/// Dropping a card onto a column applies that column's attribute (status /
/// project / priority).
enum BoardDimension {
  status('Status'),
  project('Project'),
  priority('Priority');

  final String label;
  const BoardDimension(this.label);
}

final boardDimensionProvider =
    StateProvider<BoardDimension>((ref) => BoardDimension.status);

/// One kanban column: a stable [key] identifying the bucket (a status name,
/// a priority index as string, or a project name with '' = No Project) plus
/// the tasks bucketed into it. Title / icon / accent are resolved in the UI
/// layer per [BoardDimension].
class KanbanColumnData {
  final String key;
  final List<Task> tasks;

  const KanbanColumnData({required this.key, required this.tasks});
}

/// Everything the Today kanban needs: the four columns plus the global
/// KPI numbers for the stat cards (computed over ALL tasks, ignoring
/// filters — mirroring translate_tool's stat panel behaviour).
class KanbanBoardData {
  final List<KanbanColumnData> columns;
  final int dueTodayTotal;
  final int dueTodayDone;
  final int overdueCount;
  final int plannedCount;
  final int inProgressCount;
  final int highPriorityInProgress;
  final int doneCount;
  final int totalCount;

  const KanbanBoardData({
    required this.columns,
    required this.dueTodayTotal,
    required this.dueTodayDone,
    required this.overdueCount,
    required this.plannedCount,
    required this.inProgressCount,
    required this.highPriorityInProgress,
    required this.doneCount,
    required this.totalCount,
  });

  double get todayProgressPct =>
      dueTodayTotal == 0 ? 0 : dueTodayDone / dueTodayTotal;

  double get completionPct => totalCount == 0 ? 0 : doneCount / totalCount;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isDone(Task t) =>
    t.status == TaskStatus.completed || t.status == TaskStatus.archived;

/// The status-mode column key a task belongs to (the Done column holds both
/// completed and archived — the app-wide `completed || archived` convention).
String statusColumnKeyOf(Task t) =>
    _isDone(t) ? TaskStatus.completed.name : t.status.name;

/// Column-internal order: earliest due date first (no due date sinks to the
/// bottom), then priority P0→P3, then newest created first.
List<Task> sortKanbanTasks(List<Task> tasks) {
  final sorted = List<Task>.of(tasks);
  sorted.sort((a, b) {
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue == null && bDue != null) return 1;
    if (aDue != null && bDue == null) return -1;
    if (aDue != null && bDue != null) {
      final cmp = aDue.compareTo(bDue);
      if (cmp != 0) return cmp;
    }
    final pri = a.priority.index.compareTo(b.priority.index);
    if (pri != 0) return pri;
    return b.createdAt.compareTo(a.createdAt);
  });
  return sorted;
}

/// Applies the quick filter pills on top of the externally-set TaskFilter.
List<Task> applyBoardQuickFilter(
    List<Task> tasks, BoardQuickFilter filter, DateTime now) {
  switch (filter) {
    case BoardQuickFilter.all:
      return tasks;
    case BoardQuickFilter.dueToday:
      return tasks.where((t) => t.dueDate != null && _isSameDay(t.dueDate!, now)).toList();
    case BoardQuickFilter.highPriority:
      return tasks
          .where((t) =>
              t.priority == Priority.p0Critical ||
              t.priority == Priority.p1High)
          .toList();
  }
}

/// Buckets [tasks] into columns for [dimension] and sorts each column.
/// Status and Priority always show their fixed columns (even when empty);
/// Project shows one column per project in use (alphabetical, '' = No
/// Project last), so the board never goes blank.
List<KanbanColumnData> buildKanbanColumns(
    List<Task> tasks, BoardDimension dimension) {
  switch (dimension) {
    case BoardDimension.status:
      final byKey = {
        for (final s in const [
          TaskStatus.planned,
          TaskStatus.inProgress,
          TaskStatus.completed,
          TaskStatus.blocked,
        ])
          s.name: <Task>[],
      };
      for (final t in tasks) {
        byKey[statusColumnKeyOf(t)]!.add(t);
      }
      return [
        for (final entry in byKey.entries)
          KanbanColumnData(
              key: entry.key, tasks: sortKanbanTasks(entry.value)),
      ];

    case BoardDimension.priority:
      final byKey = {
        for (final p in Priority.values) p.index.toString(): <Task>[],
      };
      for (final t in tasks) {
        byKey[t.priority.index.toString()]!.add(t);
      }
      return [
        for (final entry in byKey.entries)
          KanbanColumnData(
              key: entry.key, tasks: sortKanbanTasks(entry.value)),
      ];

    case BoardDimension.project:
      final names = {for (final t in tasks) t.project};
      final sorted = names.toList()
        ..sort((a, b) {
          if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
      if (sorted.isEmpty) sorted.add('');
      return [
        for (final name in sorted)
          KanbanColumnData(
              key: name,
              tasks: sortKanbanTasks(
                  tasks.where((t) => t.project == name).toList())),
      ];
  }
}

/// Pure computation of the whole board payload so it is unit-testable
/// without Isar. [filteredTasks] already went through [TaskFilter];
/// [allTasks] is the unfiltered set used for the KPI cards.
KanbanBoardData buildKanbanBoardData({
  required List<Task> allTasks,
  required List<Task> filteredTasks,
  required BoardQuickFilter quickFilter,
  required BoardDimension dimension,
  required DateTime now,
}) {
  final todayStart =
      DateTime(now.year, now.month, now.day);

  var dueTodayTotal = 0;
  var dueTodayDone = 0;
  var overdueCount = 0;
  for (final t in allTasks) {
    final due = t.dueDate;
    if (due != null && _isSameDay(due, now)) {
      dueTodayTotal++;
      if (_isDone(t)) dueTodayDone++;
    }
    if (due != null &&
        due.isBefore(todayStart) &&
        !_isDone(t) &&
        t.status != TaskStatus.blocked) {
      overdueCount++;
    }
  }

  var highPriorityInProgress = 0;
  for (final t in allTasks) {
    if (t.status == TaskStatus.inProgress &&
        (t.priority == Priority.p0Critical || t.priority == Priority.p1High)) {
      highPriorityInProgress++;
    }
  }

  final plannedCount =
      allTasks.where((t) => t.status == TaskStatus.planned).length;
  final inProgressCount =
      allTasks.where((t) => t.status == TaskStatus.inProgress).length;
  final doneCount = allTasks.where(_isDone).length;

  return KanbanBoardData(
    columns: buildKanbanColumns(
        applyBoardQuickFilter(filteredTasks, quickFilter, now), dimension),
    dueTodayTotal: dueTodayTotal,
    dueTodayDone: dueTodayDone,
    overdueCount: overdueCount,
    plannedCount: plannedCount,
    inProgressCount: inProgressCount,
    highPriorityInProgress: highPriorityInProgress,
    doneCount: doneCount,
    totalCount: allTasks.length,
  );
}

final kanbanBoardProvider = Provider<KanbanBoardData>((ref) {
  final tasksAsync = ref.watch(taskListProvider);
  final all = tasksAsync.valueOrNull ?? const <Task>[];
  final filtered = ref.watch(filteredTaskListProvider);
  final quick = ref.watch(boardQuickFilterProvider);
  final dimension = ref.watch(boardDimensionProvider);
  return buildKanbanBoardData(
    allTasks: all,
    filteredTasks: filtered,
    quickFilter: quick,
    dimension: dimension,
    now: DateTime.now(),
  );
});

// ─── Autocomplete suggestions ────────────────────────────────────────────────

/// Distinct, sorted project names currently in use (empty values excluded).
/// Powers the Project autocomplete in the quick-add bar and edit dialog.
final distinctProjectsProvider = Provider<List<String>>((ref) {
  final tasksAsync = ref.watch(taskListProvider);
  final tasks = tasksAsync.valueOrNull ?? const <Task>[];
  final set = <String>{};
  for (final t in tasks) {
    final p = t.project.trim();
    if (p.isNotEmpty) set.add(p);
  }
  final list = set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
});

/// Distinct, sorted tags currently in use. Powers the Tags autocomplete.
final distinctTagsProvider = Provider<List<String>>((ref) {
  final tasksAsync = ref.watch(taskListProvider);
  final tasks = tasksAsync.valueOrNull ?? const <Task>[];
  final set = <String>{};
  for (final t in tasks) {
    for (final tag in t.tags) {
      final s = tag.trim();
      if (s.isNotEmpty) set.add(s);
    }
  }
  final list = set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
});

class TaskFilter {
  final TaskStatus? status;
  final Priority? priority;
  final String? tag;
  final DateTime? date;

  TaskFilter({this.status, this.priority, this.tag, this.date});

  bool get isActive =>
      status != null ||
      priority != null ||
      (tag != null && tag!.isNotEmpty) ||
      date != null;

  TaskFilter copyWith({
    TaskStatus? status,
    Priority? priority,
    String? tag,
    DateTime? date,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearTag = false,
    bool clearDate = false,
  }) {
    return TaskFilter(
      status: clearStatus ? null : (status ?? this.status),
      priority: clearPriority ? null : (priority ?? this.priority),
      tag: clearTag ? null : (tag ?? this.tag),
      date: clearDate ? null : (date ?? this.date),
    );
  }
}

class TaskListNotifier extends StateNotifier<AsyncValue<List<Task>>> {
  final TaskRepository _repo;

  TaskListNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadTasks();
  }

  Future<void> loadTasks() async {
    try {
      final tasks = await _repo.getAllTasks();
      state = AsyncValue.data(tasks);
    } catch (e, st) {
      // Keep showing the previous data (if any) instead of flashing a
      // spinner or an error screen on every background refresh.
      final previous = state.valueOrNull;
      state = previous != null
          ? AsyncValue.data(previous)
          : AsyncValue.error(e, st);
    }
  }

  Future<void> createTask({
    required String title,
    String? description,
    Priority priority = Priority.p2Medium,
    List<String> tags = const [],
    List<String> subSteps = const [],
    DateTime? dueDate,
    String project = '',
    // v1.10.0: kanban column "+" creates the task in that column's status.
    TaskStatus status = TaskStatus.planned,
  }) async {
    await _repo.createTask(
      title: title,
      description: description,
      priority: priority,
      tags: tags,
      subSteps: subSteps,
      dueDate: dueDate,
      project: project,
      status: status,
    );
    await loadTasks();
  }

  /// Creates several tasks in one batch (AI parse flow) and refreshes once.
  Future<int> createTasks(List<TaskDraft> drafts) async {
    var created = 0;
    for (final d in drafts) {
      await _repo.createTask(
        title: d.title,
        description: d.description,
        priority: d.priority,
        tags: d.tags,
        subSteps: d.subSteps,
        dueDate: d.dueDate,
        project: d.project,
      );
      created++;
    }
    await loadTasks();
    return created;
  }

  Future<void> updateTask(Task task) async {
    await _repo.updateTask(task);
    await loadTasks();
  }

  Future<void> deleteTask(int id) async {
    await _repo.deleteTask(id);
    await loadTasks();
  }

  /// Drag-and-drop conversion: [draggedId] becomes a sub-step of
  /// [targetId]; its sub-step tree and Execution Log notes are merged into
  /// the target. Returns how many notes / sub-steps were merged.
  Future<({int notes, int subSteps})> convertTaskToSubStep(
      int draggedId, int targetId) async {
    final merged = await _repo.convertTaskToSubStep(draggedId, targetId);
    await loadTasks();
    return merged;
  }

  /// Reverse drag operation: extracts sub-step [subStepUid] (with its
  /// subtree) from task [taskId] into a standalone task.
  Future<String?> extractSubStepToTask(int taskId, String subStepUid) async {
    final title = await _repo.extractSubStepToTask(taskId, subStepUid);
    await loadTasks();
    return title;
  }

  Future<void> updateStatus(int id, TaskStatus status) async {
    await _repo.updateTaskStatus(id, status);
    await loadTasks();
  }

  Future<void> addExecutionEntry(int taskId, ExecutionEntry entry) async {
    await _repo.addExecutionEntry(taskId, entry);
    await loadTasks();
  }

  Future<void> updateExecutionEntry(
    int taskId,
    String entryUid,
    ExecutionEntry updated,
  ) async {
    await _repo.updateExecutionEntry(taskId, entryUid, updated);
    await loadTasks();
  }

  Future<void> deleteExecutionEntry(int taskId, String entryUid) async {
    await _repo.deleteExecutionEntry(taskId, entryUid);
    await loadTasks();
  }

  Future<void> addSubStep(int taskId, String title, {String? parentUid}) async {
    await _repo.addSubStep(taskId, title, parentUid: parentUid);
    await loadTasks();
  }

  Future<void> renameSubStep(
      int taskId, String subStepUid, String newTitle) async {
    await _repo.renameSubStep(taskId, subStepUid, newTitle);
    await loadTasks();
  }

  Future<void> toggleSubStep(int taskId, String subStepUid) async {
    await _repo.toggleSubStep(taskId, subStepUid);
    await loadTasks();
  }

  Future<void> setSubStepDueDate(
      int taskId, String subStepUid, DateTime? dueDate) async {
    await _repo.setSubStepDueDate(taskId, subStepUid, dueDate);
    await loadTasks();
  }

  Future<void> deleteSubStep(int taskId, String subStepUid) async {
    await _repo.deleteSubStep(taskId, subStepUid);
    await loadTasks();
  }

  Future<void> reorder(List<int> taskIds) async {
    await _repo.reorderTasks(taskIds);
    await loadTasks();
  }
}

/// Plain description of a task to be created (batch / AI parse flow).
class TaskDraft {
  final String title;
  final String? description;
  final Priority priority;
  final List<String> tags;
  final List<String> subSteps;
  final DateTime? dueDate;
  final String project;

  const TaskDraft({
    required this.title,
    this.description,
    this.priority = Priority.p2Medium,
    this.tags = const [],
    this.subSteps = const [],
    this.dueDate,
    this.project = '',
  });
}
