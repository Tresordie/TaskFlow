import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';
import '../repositories/task_repository.dart';

/// Serializes the whole task database to a portable JSON snapshot and
/// restores it. The same snapshot format powers the manual backup/restore
/// feature and the Google Drive folder sync (Phase 4).
class BackupService {
  static const int formatVersion = 1;

  final TaskRepository _repo;

  BackupService(this._repo);

  // ────────────────────────── Serialization ──────────────────────────

  Future<String> buildSnapshot() async {
    final tasks = await _repo.getAllTasks();
    final payload = {
      'app': 'TaskFlow',
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tasks': [for (final t in tasks) _taskToJson(t)],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, dynamic> _taskToJson(Task t) => {
        'uid': t.uid,
        'title': t.title,
        'description': t.description,
        'priority': t.priority.name,
        'status': t.status.name,
        'createdAt': t.createdAt.toIso8601String(),
        'dueDate': t.dueDate?.toIso8601String(),
        'startedAt': t.startedAt?.toIso8601String(),
        'completedAt': t.completedAt?.toIso8601String(),
        'tags': t.tags,
        'project': t.project,
        'updatedAt': t.updatedAt,
        'sortOrder': t.sortOrder,
        'executionLog': [
          for (final e in t.executionLog)
            {
              'uid': e.uid,
              'timestamp': e.timestamp.toIso8601String(),
              'content': e.content,
              'type': e.type.name,
              'attachments': [
                for (final a in e.attachments)
                  {
                    'uid': a.uid,
                    'name': a.name,
                    'path': a.path,
                    'size': a.size,
                    'type': a.type.name,
                  },
              ],
            },
        ],
        'subSteps': [
          for (final s in t.subSteps)
            {
              'uid': s.uid,
              'title': s.title,
              'completed': s.completed,
              'completedAt': s.completedAt?.toIso8601String(),
              'parentUid': s.parentUid,
              'depth': s.depth,
            },
        ],
      };

  /// Parses a snapshot and returns the task count it contains.
  int countTasksInSnapshot(String jsonText) {
    final root = jsonDecode(jsonText) as Map<String, dynamic>;
    final list = root['tasks'];
    return list is List ? list.length : 0;
  }

  /// Restores a snapshot. [merge]=false wipes the current database first
  /// (full restore); [merge]=true upserts by task uid, keeping any local
  /// task that is not present in the snapshot.
  Future<int> restoreSnapshot(String jsonText, {required bool merge}) async {
    final root = jsonDecode(jsonText) as Map<String, dynamic>;
    final version = root['version'] ?? 1;
    if (version is int && version > formatVersion) {
      throw const FormatException(
          'Snapshot was created by a newer TaskFlow version.');
    }
    final list = root['tasks'];
    if (list is! List) throw const FormatException('Invalid snapshot file.');

    final tasks = [
      for (final raw in list)
        if (raw is Map<String, dynamic>) _taskFromJson(raw),
    ];

    await _repo.replaceAllTasks(tasks, merge: merge);
    return tasks.length;
  }

  Task _taskFromJson(Map<String, dynamic> j) {
    final t = Task()
      ..uid = (j['uid'] as String?) ?? ''
      ..title = (j['title'] as String?) ?? 'Untitled'
      ..description = j['description'] as String?
      ..priority = _enumByName(
          Priority.values, j['priority'] as String?, Priority.p2Medium)
      ..status = _enumByName(
          TaskStatus.values, j['status'] as String?, TaskStatus.planned)
      ..createdAt =
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now()
      ..dueDate = _parseDate(j['dueDate'])
      ..startedAt = _parseDate(j['startedAt'])
      ..completedAt = _parseDate(j['completedAt'])
      ..tags = _stringList(j['tags'])
      ..project = (j['project'] as String?) ?? ''
      ..updatedAt = (j['updatedAt'] as num?)?.toInt() ?? 0
      ..sortOrder = (j['sortOrder'] as num?)?.toInt() ?? 0;

    t.executionLog = [
      for (final raw in (j['executionLog'] as List? ?? []))
        if (raw is Map<String, dynamic>)
          ExecutionEntry()
            ..uid = (raw['uid'] as String?) ?? ''
            ..timestamp =
                DateTime.tryParse(raw['timestamp'] as String? ?? '') ??
                    DateTime.now()
            ..content = (raw['content'] as String?) ?? ''
            ..type = _enumByName(
                EntryType.values, raw['type'] as String?, EntryType.note)
            ..attachments = [
              for (final a in (raw['attachments'] as List? ?? []))
                if (a is Map<String, dynamic>)
                  Attachment()
                    ..uid = (a['uid'] as String?) ?? ''
                    ..name = (a['name'] as String?) ?? ''
                    ..path = (a['path'] as String?) ?? ''
                    ..size = (a['size'] as num?)?.toInt() ?? 0
                    ..type = _enumByName(AttachmentType.values,
                        a['type'] as String?, AttachmentType.file),
            ],
    ];

    t.subSteps = [
      for (final raw in (j['subSteps'] as List? ?? []))
        if (raw is Map<String, dynamic>)
          SubStep()
            ..uid = (raw['uid'] as String?) ?? ''
            ..title = (raw['title'] as String?) ?? ''
            ..completed = (raw['completed'] as bool?) ?? false
            ..completedAt = _parseDate(raw['completedAt'])
            ..parentUid = raw['parentUid'] as String?
            ..depth = ((raw['depth'] as num?)?.toInt() ?? 0)
                .clamp(0, SubStep.maxDepth),
    ];

    return t;
  }

  T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  List<String> _stringList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : [];

  // ──────────────────────────── Files ────────────────────────────

  /// Writes a snapshot into `<Documents>/TaskFlow/backups/` and returns
  /// the file. Used as the default target for manual backups.
  Future<File> exportToBackupsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'TaskFlow', 'backups'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name =
        'TaskFlow_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(await buildSnapshot());
    return file;
  }
}
