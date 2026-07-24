import 'package:isar/isar.dart';

part 'task.g.dart';

enum Priority {
  p0Critical,
  p1High,
  p2Medium,
  p3Low;

  String get label {
    switch (this) {
      case Priority.p0Critical:
        return 'P0 Critical';
      case Priority.p1High:
        return 'P1 High';
      case Priority.p2Medium:
        return 'P2 Medium';
      case Priority.p3Low:
        return 'P3 Low';
    }
  }

  String get shortLabel {
    switch (this) {
      case Priority.p0Critical:
        return 'P0';
      case Priority.p1High:
        return 'P1';
      case Priority.p2Medium:
        return 'P2';
      case Priority.p3Low:
        return 'P3';
    }
  }
}

enum TaskStatus {
  planned,
  inProgress,
  completed,
  archived,
  blocked;

  String get label {
    switch (this) {
      case TaskStatus.planned:
        return 'Planned';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.archived:
        return 'Archived';
      case TaskStatus.blocked:
        return 'Blocked';
    }
  }
}

@collection
class Task {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid; // UUID for sync

  late String title;

  String? description;

  @enumerated
  Priority priority = Priority.p2Medium;

  @enumerated
  TaskStatus status = TaskStatus.planned;

  late DateTime createdAt;

  DateTime? dueDate;

  DateTime? startedAt;

  DateTime? completedAt;

  List<String> tags = [];

  /// Project the task belongs to (e.g. "Cosmo", "Metro", "Monolith").
  /// Reports group tasks by this field; empty means "General".
  String project = '';

  /// Last modification timestamp (ms since epoch). Touched by every
  /// repository mutation and used for last-write-wins merging during
  /// sync/restore so a stale snapshot can never overwrite newer local
  /// data. Additive property — Isar auto-migrates existing rows to 0.
  int updatedAt = 0;

  int sortOrder = 0;

  // Execution log stored as embedded list
  List<ExecutionEntry> executionLog = [];

  // Sub-steps / checklist
  List<SubStep> subSteps = [];
}

@embedded
class ExecutionEntry {
  late String uid;
  late DateTime timestamp;
  late String content;

  @enumerated
  EntryType type = EntryType.note;

  @ignore
  EntryType get entryType => type;

  // Attached images / files
  List<Attachment> attachments = [];
}

/// Type of an attached file in an execution log entry.
enum AttachmentType {
  image,
  file;

  String get label {
    switch (this) {
      case AttachmentType.image:
        return 'Image';
      case AttachmentType.file:
        return 'File';
    }
  }
}

/// A file (image or generic file) attached to an execution log entry.
/// The file is copied into the app's attachments directory so the entry
/// stays valid even if the original file is moved or deleted.
@embedded
class Attachment {
  late String uid;
  late String name; // display name (original file name)
  late String path; // absolute path of the stored copy
  late int size; // size in bytes

  @enumerated
  AttachmentType type = AttachmentType.file;
}

enum EntryType {
  note,
  pass,
  fail,
  blocked;

  String get label {
    switch (this) {
      case EntryType.note:
        return 'Note';
      case EntryType.pass:
        return 'Pass';
      case EntryType.fail:
        return 'Fail';
      case EntryType.blocked:
        return 'Blocked';
    }
  }
}

@embedded
class SubStep {
  /// Maximum nesting depth (0-based). 0/1/2 => up to 3 levels of sub-tasks.
  /// Isar 3.1.0 cannot nest embedded objects inside embedded objects, so
  /// nesting is stored flat via [parentUid] adjacency + cached [depth].
  static const int maxDepth = 2;

  late String uid;
  late String title;
  bool completed = false;
  DateTime? completedAt;

  /// uid of the parent sub-step, or null for a top-level sub-step.
  String? parentUid;

  /// Cached nesting depth: 0 = top-level, 1 = child, 2 = grandchild.
  int depth = 0;
}

/// Returns [steps] in visual (DFS pre-order) order: each sub-step is
/// followed by its descendants, so the UI can render a flat list as an
/// indented tree. Orphans (parentUid pointing to a missing step) are
/// treated as top-level. The original list is not modified.
List<SubStep> subStepsInDisplayOrder(List<SubStep> steps) {
  final childrenOf = <String?, List<SubStep>>{};
  final uids = steps.map((s) => s.uid).toSet();
  for (final step in steps) {
    final parent =
        step.parentUid != null && uids.contains(step.parentUid)
            ? step.parentUid
            : null;
    childrenOf.putIfAbsent(parent, () => []).add(step);
  }

  final ordered = <SubStep>[];
  void visit(String? parentUid) {
    for (final step in childrenOf[parentUid] ?? const <SubStep>[]) {
      ordered.add(step);
      visit(step.uid);
    }
  }

  visit(null);
  return ordered;
}

/// Returns the uids of [step] plus all of its descendants within [steps].
/// Used so deleting a sub-step also removes its children.
Set<String> subStepDescendantUids(List<SubStep> steps, SubStep step) {
  final result = <String>{step.uid};
  var grew = true;
  while (grew) {
    grew = false;
    for (final s in steps) {
      if (s.parentUid != null &&
          result.contains(s.parentUid) &&
          result.add(s.uid)) {
        grew = true;
      }
    }
  }
  return result;
}
