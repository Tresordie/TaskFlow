import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/task.dart';

class TaskRepository {
  final _uuid = const Uuid();

  /// Stamps [t] with the current modification time. Called by every
  /// mutation so sync/restore can do last-write-wins merging.
  void _touch(Task t) {
    t.updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Future<List<Task>> getAllTasks() async {
    final isar = await AppDatabase.instance;
    return isar.tasks.where().sortBySortOrder().findAll();
  }

  Future<List<Task>> getTasksByDate(DateTime date) async {
    final isar = await AppDatabase.instance;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return isar.tasks
        .filter()
        .createdAtBetween(start, end)
        .sortBySortOrder()
        .findAll();
  }

  Future<List<Task>> getTasksByStatus(TaskStatus status) async {
    final isar = await AppDatabase.instance;
    return isar.tasks
        .filter()
        .statusEqualTo(status)
        .sortBySortOrder()
        .findAll();
  }

  Future<List<Task>> getTasksByDateRange(DateTime start, DateTime end) async {
    final isar = await AppDatabase.instance;
    return isar.tasks
        .filter()
        .createdAtBetween(start, end.add(const Duration(days: 1)))
        .sortBySortOrder()
        .findAll();
  }

  Future<Task?> getTaskById(int id) async {
    final isar = await AppDatabase.instance;
    return isar.tasks.get(id);
  }

  Future<int> createTask({
    required String title,
    String? description,
    Priority priority = Priority.p2Medium,
    List<String> tags = const [],
    List<String> subSteps = const [],
    DateTime? dueDate,
    String project = '',
  }) async {
    final isar = await AppDatabase.instance;

    // Get max sort order
    final allTasks = await isar.tasks.where().sortBySortOrderDesc().findFirst();
    final nextOrder = (allTasks?.sortOrder ?? 0) + 1;

    final task = Task()
      ..uid = _uuid.v4()
      ..title = title
      ..description = description
      ..priority = priority
      ..status = TaskStatus.planned
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now().millisecondsSinceEpoch
      ..dueDate = dueDate
      ..tags = tags
      ..project = project.trim()
      ..sortOrder = nextOrder
      ..subSteps = [
        for (final s in subSteps)
          if (s.trim().isNotEmpty)
            SubStep()
              ..uid = _uuid.v4()
              ..title = s.trim()
              ..completed = false,
      ];

    return isar.writeTxn(() => isar.tasks.put(task));
  }

  /// Bulk-imports [tasks] (restore / sync).
  ///
  /// [merge] = false → full restore: the whole table is cleared first.
  /// [merge] = true  → upsert by uid: incoming tasks overwrite existing
  ///                   ones with the same uid, other local tasks survive.
  Future<void> replaceAllTasks(List<Task> tasks, {required bool merge}) async {
    final isar = await AppDatabase.instance;

    for (final t in tasks) {
      if (t.uid.isEmpty) t.uid = _uuid.v4();
    }

    await isar.writeTxn(() async {
      if (!merge) {
        await isar.tasks.clear();
        await isar.tasks.putAll(tasks);
        return;
      }

      final existing = await isar.tasks.where().findAll();
      final byUid = {for (final e in existing) e.uid: e};
      for (final t in tasks) {
        final local = byUid[t.uid];
        if (local != null) {
          // Last-write-wins: a stale snapshot must never overwrite a
          // locally newer task. Ties keep the local copy (this also
          // protects upgrades where both sides still carry 0).
          if (t.updatedAt <= local.updatedAt) continue;
          t.id = local.id; // overwrite in place
        }
        await isar.tasks.put(t);
      }
    });
  }

  Future<void> updateTask(Task task) async {
    final isar = await AppDatabase.instance;
    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  Future<void> deleteTask(int id) async {
    final isar = await AppDatabase.instance;
    await isar.writeTxn(() => isar.tasks.delete(id));
  }

  Future<void> updateTaskStatus(int id, TaskStatus status) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(id);
    if (task == null) return;

    task.status = status;
    if (status == TaskStatus.inProgress && task.startedAt == null) {
      task.startedAt = DateTime.now();
    }
    if (status == TaskStatus.completed) {
      task.completedAt = DateTime.now();
    }

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  Future<void> addExecutionEntry(int taskId, ExecutionEntry entry) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    entry.uid = _uuid.v4();
    entry.timestamp = DateTime.now();
    // Isar deserializes embedded lists as fixed-length, so .add() would
    // throw. Reassign a new growable list instead.
    task.executionLog = [...task.executionLog, entry];

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  /// Replaces the execution-log entry identified by [entryUid] with
  /// [updated] (which must carry the same uid and original timestamp so
  /// the entry keeps its place in the timeline).
  Future<void> updateExecutionEntry(
    int taskId,
    String entryUid,
    ExecutionEntry updated,
  ) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    // Fixed-length list again: rebuild via collection-for instead of
    // mutating in place.
    task.executionLog = [
      for (final e in task.executionLog)
        if (e.uid == entryUid) updated else e,
    ];

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  /// Removes the execution-log entry identified by [entryUid].
  /// Attachment copies on disk are intentionally kept (only the DB
  /// reference is removed) so no user file is ever physically deleted.
  Future<void> deleteExecutionEntry(int taskId, String entryUid) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    // Fixed-length list: rebuild without the target entry.
    task.executionLog = [
      for (final e in task.executionLog)
        if (e.uid != entryUid) e,
    ];

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  /// Appends a sub-step. When [parentUid] is given the new sub-step is
  /// nested under that parent (depth = parent.depth + 1); adds are
  /// silently rejected once the parent is already at [SubStep.maxDepth]
  /// so nesting never exceeds 3 levels.
  Future<void> addSubStep(int taskId, String title,
      {String? parentUid}) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    SubStep? parent;
    if (parentUid != null) {
      parent =
          task.subSteps.where((s) => s.uid == parentUid).firstOrNull;
      if (parent == null || parent.depth >= SubStep.maxDepth) return;
    }

    // Same fixed-length list constraint as executionLog above.
    task.subSteps = [
      ...task.subSteps,
      SubStep()
        ..uid = _uuid.v4()
        ..title = title
        ..completed = false
        ..parentUid = parent?.uid
        ..depth = parent == null ? 0 : parent.depth + 1,
    ];

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  /// Renames an existing sub-step. Empty/whitespace titles are ignored.
  Future<void> renameSubStep(
      int taskId, String subStepUid, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;

    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    final step =
        task.subSteps.where((s) => s.uid == subStepUid).firstOrNull;
    if (step == null || step.title == trimmed) return;

    step.title = trimmed;
    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  Future<void> toggleSubStep(int taskId, String subStepUid) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    final step = task.subSteps.where((s) => s.uid == subStepUid).firstOrNull;
    if (step != null) {
      step.completed = !step.completed;
      step.completedAt = step.completed ? DateTime.now() : null;
      _touch(task);
      await isar.writeTxn(() => isar.tasks.put(task));
    }
  }

  /// Deletes a sub-step together with all of its descendants.
  Future<void> deleteSubStep(int taskId, String subStepUid) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    final step =
        task.subSteps.where((s) => s.uid == subStepUid).firstOrNull;
    if (step == null) return;

    final doomed = subStepDescendantUids(task.subSteps, step);
    task.subSteps = [
      for (final s in task.subSteps)
        if (!doomed.contains(s.uid)) s,
    ];

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  Future<void> reorderTasks(List<int> taskIds) async {
    final isar = await AppDatabase.instance;
    await isar.writeTxn(() async {
      for (var i = 0; i < taskIds.length; i++) {
        final task = await isar.tasks.get(taskIds[i]);
        if (task != null) {
          task.sortOrder = i;
          _touch(task);
          await isar.tasks.put(task);
        }
      }
    });
  }
}
