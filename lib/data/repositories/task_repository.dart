import 'package:isar/isar.dart';
import 'package:meta/meta.dart';
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
    final tasks = await isar.tasks.where().sortBySortOrder().findAll();

    // Self-heal: SubStep.depth is a derived cache over parentUid and the
    // v1.4.9 migration corrupted the persisted values (sign-bit flipped).
    // Recompute from the parentUid chain and persist any repair so the
    // database is fixed on first load and stays correct thereafter.
    final repaired = <Task>[
      for (final t in tasks)
        if (normalizeSubStepDepths(t.subSteps)) t,
    ];
    if (repaired.isNotEmpty) {
      await isar.writeTxn(() => isar.tasks.putAll(repaired));
    }
    return tasks;
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

  /// Synchronously builds the [Task] entity for a new task.
  ///
  /// [tags] and [subSteps] are snapshot-copied immediately, so a caller
  /// may clear its own lists the moment the async [createTask] future is
  /// fired (unawaited) without racing the persistence layer.
  @visibleForTesting
  Task buildNewTask({
    required String title,
    String? description,
    Priority priority = Priority.p2Medium,
    List<String> tags = const [],
    List<String> subSteps = const [],
    DateTime? dueDate,
    String project = '',
    required int sortOrder,
  }) {
    // Defensive copies: snapshot before any async gap can interleave
    // with caller-side mutation (see [createTask]).
    final safeTags = List<String>.of(tags);
    final safeSubSteps = List<String>.of(subSteps);

    return Task()
      ..uid = _uuid.v4()
      ..title = title
      ..description = description
      ..priority = priority
      ..status = TaskStatus.planned
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now().millisecondsSinceEpoch
      ..dueDate = dueDate
      ..tags = safeTags
      ..project = project.trim()
      ..sortOrder = sortOrder
      ..subSteps = [
        for (final s in safeSubSteps)
          if (s.trim().isNotEmpty)
            SubStep()
              ..uid = _uuid.v4()
              ..title = s.trim()
              ..completed = false,
      ];
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
    // Build synchronously at the entry point — BEFORE the first await —
    // so the defensive copies inside [buildNewTask] are taken while the
    // caller's lists are still intact. (Callers such as the quick-add bar
    // clear their lists right after firing this future without awaiting.)
    final task = buildNewTask(
      title: title,
      description: description,
      priority: priority,
      tags: tags,
      subSteps: subSteps,
      dueDate: dueDate,
      project: project,
      sortOrder: 0, // placeholder, patched below
    );

    final isar = await AppDatabase.instance;

    // Get max sort order
    final allTasks = await isar.tasks.where().sortBySortOrderDesc().findFirst();
    task.sortOrder = (allTasks?.sortOrder ?? 0) + 1;

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

  /// Converts [draggedId] into a sub-step of [targetId] (drag-and-drop on
  /// the board), merging the dragged task's sub-step tree AND its Execution
  /// Log NOTE entries — with attachments, due dates and original timestamps
  /// — into the target BEFORE deleting it, so nothing is ever lost by the
  /// conversion. Returns how many notes and sub-steps were merged.
  Future<({int notes, int subSteps})> convertTaskToSubStep(
      int draggedId, int targetId) async {
    if (draggedId == targetId) return (notes: 0, subSteps: 0);
    final isar = await AppDatabase.instance;
    final dragged = await isar.tasks.get(draggedId);
    final target = await isar.tasks.get(targetId);
    if (dragged == null || target == null) return (notes: 0, subSteps: 0);

    // Sub-step append mirrors addSubStep(): normalize depths first, then
    // add with a fresh uid and record createdAt at the Task level
    // (SubStep's schema is frozen — SCHEMA FREEZE in task.dart).
    normalizeSubStepDepths(target.subSteps);
    final newUid = _uuid.v4();
    target.subSteps = [
      ...target.subSteps,
      SubStep()
        ..uid = newUid
        ..title = dragged.title
        ..completed = false
        ..depth = 0,
    ];
    target.subStepDates = [
      ...target.subStepDates,
      SubStepDates()
        ..uid = newUid
        ..createdAt = DateTime.now(),
    ];

    // v1.4.79: migrate the dragged task's sub-step tree under the new
    // sub-step. uids are preserved (date metadata keys off them); every
    // level sinks one deeper, and nodes that would overflow maxDepth are
    // re-parented to their nearest ancestor sitting at maxDepth-1 so the
    // tree stays valid without dropping any sub-step.
    final origParent = <String, String?>{
      for (final s in dragged.subSteps) s.uid: s.parentUid,
    };
    final newDepthByUid = <String, int>{newUid: 0};
    final migratedSteps = <SubStep>[];
    final pending = List<SubStep>.from(dragged.subSteps);
    var guard = 0;
    while (pending.isNotEmpty && guard++ < 10000) {
      final s = pending.removeAt(0);
      String newParentUid;
      int newDepth;
      if (s.parentUid == null) {
        newParentUid = newUid;
        newDepth = 1;
      } else {
        final parentNewDepth = newDepthByUid[s.parentUid];
        if (parentNewDepth == null) {
          pending.add(s); // parent not migrated yet — retry later
          continue;
        }
        if (parentNewDepth + 1 <= SubStep.maxDepth) {
          newParentUid = s.parentUid!;
          newDepth = parentNewDepth + 1;
        } else {
          // Overflow: climb the original ancestor chain to the nearest one
          // whose NEW depth leaves room (maxDepth - 1).
          var ancestor = s.parentUid;
          while (ancestor != null &&
              (newDepthByUid[ancestor] ?? 0) > SubStep.maxDepth - 1) {
            ancestor = origParent[ancestor];
          }
          newParentUid = ancestor ?? newUid;
          newDepth = (newDepthByUid[newParentUid] ?? 0) + 1;
        }
      }
      newDepthByUid[s.uid] = newDepth;
      migratedSteps.add(SubStep()
        ..uid = s.uid
        ..title = s.title
        ..completed = s.completed
        ..completedAt = s.completedAt
        ..parentUid = newParentUid
        ..depth = newDepth);
    }
    target.subSteps = [...target.subSteps, ...migratedSteps];

    // Carry over the date metadata (createdAt / dueDate) of every migrated
    // sub-step. Fixed-length lists: rebuild via spread.
    final migratedUids = {for (final s in migratedSteps) s.uid};
    target.subStepDates = [
      ...target.subStepDates,
      for (final d in dragged.subStepDates)
        if (migratedUids.contains(d.uid))
          SubStepDates()
            ..uid = d.uid
            ..createdAt = d.createdAt
            ..dueDate = d.dueDate,
    ];

    // Merge NOTE entries only (user-requested scope): keep original uid /
    // timestamp / attachments, rebuild as a growable list (Isar hands back
    // fixed-length lists), then sort chronologically.
    final mergedNotes = [
      for (final e in dragged.executionLog)
        if (e.type == EntryType.note) e,
    ];
    target.executionLog = [
      ...target.executionLog,
      ...mergedNotes,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    _touch(target);
    await isar.writeTxn(() async {
      await isar.tasks.put(target);
      await isar.tasks.delete(draggedId);
    });
    return (notes: mergedNotes.length, subSteps: migratedSteps.length);
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
  Future<void> addSubStep(int taskId, String title, {String? parentUid}) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    // depth is derived from parentUid — recompute it first so a corrupted
    // stored value can neither propagate into the new child nor break the
    // maxDepth guard below.
    normalizeSubStepDepths(task.subSteps);

    SubStep? parent;
    if (parentUid != null) {
      parent = task.subSteps.where((s) => s.uid == parentUid).firstOrNull;
      if (parent == null || parent.depth >= SubStep.maxDepth) return;
    }

    // Same fixed-length list constraint as executionLog above.
    final newUid = _uuid.v4();
    task.subSteps = [
      ...task.subSteps,
      SubStep()
        ..uid = newUid
        ..title = title
        ..completed = false
        ..parentUid = parent?.uid
        ..depth = parent == null ? 0 : parent.depth + 1,
    ];
    // Record the creation date at the Task level (SubStep's schema is
    // frozen — see SCHEMA FREEZE in task.dart).
    task.subStepDates = [
      ...task.subStepDates,
      SubStepDates()
        ..uid = newUid
        ..createdAt = DateTime.now(),
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

    final step = task.subSteps.where((s) => s.uid == subStepUid).firstOrNull;
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

  /// Sets (or clears, when [dueDate] is null) the due date for a sub-step.
  /// The date lives in [Task.subStepDates] because SubStep's schema is frozen
  /// (SCHEMA FREEZE in task.dart).
  Future<void> setSubStepDueDate(
      int taskId, String subStepUid, DateTime? dueDate) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    final dates =
        task.subStepDates.where((d) => d.uid == subStepUid).firstOrNull;
    if (dates != null) {
      dates.dueDate = dueDate;
    } else {
      // No metadata row yet (sub-step predates this feature) — create one.
      task.subStepDates = [
        ...task.subStepDates,
        SubStepDates()
          ..uid = subStepUid
          ..dueDate = dueDate,
      ];
    }

    _touch(task);
    await isar.writeTxn(() => isar.tasks.put(task));
  }

  /// Deletes a sub-step together with all of its descendants.
  Future<void> deleteSubStep(int taskId, String subStepUid) async {
    final isar = await AppDatabase.instance;
    final task = await isar.tasks.get(taskId);
    if (task == null) return;

    final step = task.subSteps.where((s) => s.uid == subStepUid).firstOrNull;
    if (step == null) return;

    final doomed = subStepDescendantUids(task.subSteps, step);
    task.subSteps = [
      for (final s in task.subSteps)
        if (!doomed.contains(s.uid)) s,
    ];
    // Drop the date metadata for the removed sub-steps as well.
    task.subStepDates = [
      for (final d in task.subStepDates)
        if (!doomed.contains(d.uid)) d,
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
