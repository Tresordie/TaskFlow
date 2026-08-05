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

// ─── Group-by mode ───────────────────────────────────────────────────────────

enum TaskGroupMode {
  priority('Priority'),
  status('Status'),
  project('Project'),
  tag('Tag'),
  none('None');

  final String label;
  const TaskGroupMode(this.label);
}

final taskGroupModeProvider =
    StateProvider<TaskGroupMode>((ref) => TaskGroupMode.priority);

/// Generic grouping: returns an ordered map of group-label → tasks.
final groupedTasksByModeProvider = Provider<Map<String, List<Task>>>((ref) {
  final tasks = ref.watch(filteredTaskListProvider);
  final mode = ref.watch(taskGroupModeProvider);

  switch (mode) {
    case TaskGroupMode.none:
      return {'All Tasks': tasks};

    case TaskGroupMode.priority:
      final grouped = <String, List<Task>>{};
      for (final p in Priority.values) {
        final list = tasks.where((t) => t.priority == p).toList();
        if (list.isNotEmpty) grouped[p.label] = list;
      }
      return grouped;

    case TaskGroupMode.status:
      final grouped = <String, List<Task>>{};
      for (final s in TaskStatus.values) {
        final list = tasks.where((t) => t.status == s).toList();
        if (list.isNotEmpty) grouped[s.label] = list;
      }
      return grouped;

    case TaskGroupMode.project:
      final grouped = <String, List<Task>>{};
      for (final task in tasks) {
        final key = (task.project.isEmpty) ? 'No Project' : task.project;
        (grouped[key] ??= []).add(task);
      }
      return grouped;

    case TaskGroupMode.tag:
      final grouped = <String, List<Task>>{};
      for (final task in tasks) {
        if (task.tags.isEmpty) {
          (grouped['No Tag'] ??= []).add(task);
        } else {
          for (final tag in task.tags) {
            (grouped[tag] ??= []).add(task);
          }
        }
      }
      return grouped;
  }
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
  }) async {
    await _repo.createTask(
      title: title,
      description: description,
      priority: priority,
      tags: tags,
      subSteps: subSteps,
      dueDate: dueDate,
      project: project,
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
