import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/models/work_log.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/data/repositories/work_log_repository.dart';
import 'package:taskflow/data/services/backup_service.dart';

/// In-memory [TaskRepository] so snapshot round-trips can be unit-tested
/// without opening an Isar database.
class _FakeTasks extends TaskRepository {
  List<Task> tasks;
  _FakeTasks(this.tasks);

  @override
  Future<List<Task>> getAllTasks() async => tasks;

  @override
  Future<void> replaceAllTasks(List<Task> t, {required bool merge}) async {
    tasks = merge ? [...tasks, ...t] : t;
  }
}

Task _task(String uid, int updatedAt) => Task()
  ..uid = uid
  ..title = 'T $uid'
  ..createdAt = DateTime(2026, 10, 1)
  ..updatedAt = updatedAt;

/// A snapshot with the given work log entries and no tasks (version 1 if
/// [withWorkLogs] is false, mimicking pre-v2 files).
String _snapshotJson({
  List<WorkLogRecord> records = const [],
  List<WorkLogSummary> summaries = const [],
  bool withWorkLogs = true,
}) {
  final root = {
    'app': 'TaskFlow',
    'version': withWorkLogs ? 2 : 1,
    'exportedAt': DateTime(2026, 10, 30).toIso8601String(),
    'tasks': <Object>[],
  };
  if (withWorkLogs) {
    root['workLogs'] = {
      'records': [for (final r in records) r.toJson()],
      'summaries': [for (final s in summaries) s.toJson()],
    };
  }
  return jsonEncode(root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkLogRepository wl;
  late BackupService backup;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    wl = WorkLogRepository();
    backup = BackupService(_FakeTasks([]), wl);
  });

  group('buildSnapshot v2', () {
    test('embeds work log records and summaries', () async {
      await wl.saveRecords([
        WorkLogRecord(id: 'r1', content: 'a', timestamp: 10)
      ]);
      await wl.saveSummaries([
        WorkLogSummary(
            id: 's1',
            dateRange: 'week',
            content: 'c',
            inputLang: 'zh',
            outputLang: 'en',
            timestamp: 11)
      ]);
      final root =
          jsonDecode(await BackupService(_FakeTasks([_task('u1', 5)]), wl)
              .buildSnapshot()) as Map<String, dynamic>;
      expect(root['version'], 2);
      expect(root['tasks'], hasLength(1));
      final wlJson = root['workLogs'] as Map<String, dynamic>;
      expect(wlJson['records'], hasLength(1));
      expect(wlJson['summaries'], hasLength(1));
    });

    test('omits the section when no work log repo is wired', () async {
      final root = jsonDecode(
          await BackupService(_FakeTasks([_task('u1', 5)]))
              .buildSnapshot()) as Map<String, dynamic>;
      expect(root['workLogs'], isNull);
    });
  });

  group('restoreSnapshot work logs · merge', () {
    test('unions by id, newest timestamp wins', () async {
      await wl.saveRecords([
        WorkLogRecord(id: 'r1', content: 'local-wins', timestamp: 500),
        WorkLogRecord(id: 'r2', content: 'only-local', timestamp: 300),
      ]);
      await backup.restoreSnapshot(
        _snapshotJson(records: [
          WorkLogRecord(id: 'r1', content: 'stale-remote', timestamp: 100),
          WorkLogRecord(id: 'r3', content: 'only-remote', timestamp: 400),
        ]),
        merge: true,
      );
      final merged = {for (final r in await wl.loadRecords()) r.id: r};
      expect(merged.keys, unorderedEquals(['r1', 'r2', 'r3']));
      expect(merged['r1']!.content, 'local-wins'); // newer local kept
      expect(merged['r3']!.content, 'only-remote'); // new from remote
      // Newest-first order.
      expect((await wl.loadRecords()).map((r) => r.timestamp), [500, 400, 300]);
    });

    test('incoming entry with newer timestamp overwrites local', () async {
      await wl.saveRecords([
        WorkLogRecord(id: 'r1', content: 'old', timestamp: 100)
      ]);
      await backup.restoreSnapshot(
        _snapshotJson(records: [
          WorkLogRecord(id: 'r1', content: 'new', timestamp: 200)
        ]),
        merge: true,
      );
      final r = (await wl.loadRecords()).single;
      expect(r.content, 'new');
      expect(r.timestamp, 200);
    });

    test('merge stays bounded to the repository cap', () async {
      await wl.saveRecords([
        for (var i = 0; i < 200; i++)
          WorkLogRecord(id: 'l$i', content: 'local', timestamp: i),
      ]);
      await backup.restoreSnapshot(
        _snapshotJson(records: [
          for (var i = 0; i < 200; i++)
            WorkLogRecord(id: 'r$i', content: 'remote', timestamp: 1000 + i),
        ]),
        merge: true,
      );
      final merged = await wl.loadRecords();
      expect(merged.length, WorkLogRepository.maxRecords);
      // All 200 remote entries (timestamps ≥ 1000) outrank local ones.
      expect(merged.every((r) => r.id.startsWith('r')), isTrue);
    });

    test('summaries merge and cap independently', () async {
      await wl.saveSummaries([
        for (var i = 0; i < 50; i++)
          WorkLogSummary(
              id: 's$i',
              dateRange: 'd',
              content: 'local',
              inputLang: 'zh',
              outputLang: 'zh',
              timestamp: i),
      ]);
      await backup.restoreSnapshot(
        _snapshotJson(summaries: [
          WorkLogSummary(
              id: 'new1',
              dateRange: 'd',
              content: 'remote',
              inputLang: 'zh',
              outputLang: 'zh',
              timestamp: 9999),
        ]),
        merge: true,
      );
      final merged = await wl.loadSummaries();
      expect(merged.length, WorkLogRepository.maxSummaries);
      expect(merged.first.id, 'new1');
    });

    test('pre-v2 snapshot without workLogs leaves local lists untouched',
        () async {
      await wl.saveRecords([
        WorkLogRecord(id: 'r1', content: 'keep me', timestamp: 10)
      ]);
      await backup.restoreSnapshot(_snapshotJson(withWorkLogs: false),
          merge: true);
      expect((await wl.loadRecords()).single.content, 'keep me');
    });

    test('full restore replaces the lists outright', () async {
      await wl.saveRecords([
        WorkLogRecord(id: 'r2', content: 'only-local', timestamp: 900)
      ]);
      await backup.restoreSnapshot(
        _snapshotJson(records: [
          WorkLogRecord(id: 'r1', content: 'from-file', timestamp: 10)
        ]),
        merge: false,
      );
      final merged = await wl.loadRecords();
      expect(merged, hasLength(1));
      expect(merged.single.id, 'r1');
    });
  });

  test('newer-than-app snapshot is still rejected', () async {
    final future = jsonEncode({
      'app': 'TaskFlow',
      'version': BackupService.formatVersion + 1,
      'tasks': <Object>[],
    });
    expect(() => backup.restoreSnapshot(future, merge: true),
        throwsA(isA<FormatException>()));
  });
}
