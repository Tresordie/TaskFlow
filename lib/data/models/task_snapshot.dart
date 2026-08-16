import 'package:uuid/uuid.dart';

import 'task.dart';

/// v1.4.83 reversibility support: manual JSON (de)serialization of a [Task]
/// so a task converted into a sub-step can later be restored EXACTLY
/// (Isar's generated code does not emit toJson/fromJson for collections).
///
/// The snapshot is stored inside [SubStepOrigin.snapshot] on the target task.

Map<String, dynamic> taskToSnapshot(Task t) => {
      'id': t.id,
      'uid': t.uid,
      'title': t.title,
      'description': t.description,
      'priority': t.priority.index,
      'status': t.status.index,
      'createdAt': t.createdAt.toIso8601String(),
      'dueDate': t.dueDate?.toIso8601String(),
      'startedAt': t.startedAt?.toIso8601String(),
      'completedAt': t.completedAt?.toIso8601String(),
      'tags': List<String>.of(t.tags),
      'project': t.project,
      'sortOrder': t.sortOrder,
      'updatedAt': t.updatedAt,
      'executionLog': [
        for (final e in t.executionLog)
          {
            'uid': e.uid,
            'timestamp': e.timestamp.toIso8601String(),
            'content': e.content,
            'type': e.type.index,
            'attachments': [
              for (final a in e.attachments)
                {
                  'uid': a.uid,
                  'name': a.name,
                  'path': a.path,
                  'size': a.size,
                  'type': a.type.index,
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
      'subStepDates': [
        for (final d in t.subStepDates)
          {
            'uid': d.uid,
            'createdAt': d.createdAt?.toIso8601String(),
            'dueDate': d.dueDate?.toIso8601String(),
          },
      ],
    };

DateTime? _dt(dynamic v) =>
    v is String ? DateTime.tryParse(v) : null;

Task taskFromSnapshot(Map<String, dynamic> m) {
  final t = Task()
    ..uid = (m['uid'] as String?) ?? const Uuid().v4()
    ..title = (m['title'] as String?) ?? ''
    ..description = m['description'] as String?
    ..priority = Priority.values.elementAt(
        (m['priority'] is int) ? m['priority'] as int : 2)
    ..status = TaskStatus.values
        .elementAt((m['status'] is int) ? m['status'] as int : 0)
    ..createdAt = _dt(m['createdAt']) ?? DateTime.now()
    ..dueDate = _dt(m['dueDate'])
    ..startedAt = _dt(m['startedAt'])
    ..completedAt = _dt(m['completedAt'])
    ..project = (m['project'] as String?) ?? ''
    ..sortOrder = (m['sortOrder'] is int) ? m['sortOrder'] as int : 0
    ..updatedAt = (m['updatedAt'] is int) ? m['updatedAt'] as int : 0;
  // Restore the original id when present (the row was deleted, so the id
  // is free again); otherwise keep Isar.autoIncrement.
  if (m['id'] is int) {
    t.id = m['id'] as int;
  }
  t.tags = [for (final x in (m['tags'] as List? ?? const [])) '$x'];

  t.executionLog = [
    for (final e in (m['executionLog'] as List? ?? const []))
      ExecutionEntry()
        ..uid = (e['uid'] as String?) ?? ''
        ..timestamp = _dt(e['timestamp']) ?? DateTime.now()
        ..content = (e['content'] as String?) ?? ''
        ..type = EntryType.values
            .elementAt((e['type'] is int) ? e['type'] as int : 0)
        ..attachments = [
          for (final a in (e['attachments'] as List? ?? const []))
            Attachment()
              ..uid = (a['uid'] as String?) ?? ''
              ..name = (a['name'] as String?) ?? ''
              ..path = (a['path'] as String?) ?? ''
              ..size = (a['size'] is int) ? a['size'] as int : 0
              ..type = AttachmentType.values
                  .elementAt((a['type'] is int) ? a['type'] as int : 1),
        ],
  ];

  t.subSteps = [
    for (final s in (m['subSteps'] as List? ?? const []))
      SubStep()
        ..uid = (s['uid'] as String?) ?? ''
        ..title = (s['title'] as String?) ?? ''
        ..completed = (s['completed'] as bool?) ?? false
        ..completedAt = _dt(s['completedAt'])
        ..parentUid = s['parentUid'] as String?
        ..depth = (s['depth'] is int) ? s['depth'] as int : 0,
  ];

  t.subStepDates = [
    for (final d in (m['subStepDates'] as List? ?? const []))
      SubStepDates()
        ..uid = (d['uid'] as String?) ?? ''
        ..createdAt = _dt(d['createdAt'])
        ..dueDate = _dt(d['dueDate']),
  ];

  return t;
}
