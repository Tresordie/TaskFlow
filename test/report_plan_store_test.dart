import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/services/report_plan_store.dart';

/// Round-trip tests for the plan archive that feeds the "Last Period's Plan
/// vs. Actual" report section. The DB keeps no task history, so the archive
/// written at generation time is the only source for the comparison.
void main() {
  Task task(String uid, {DateTime? due}) => Task()
    ..uid = uid
    ..title = 'task $uid'
    ..project = 'Cosmo'
    ..priority = Priority.p1High
    ..dueDate = due;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('save + load round trip preserves every row field', () async {
    final store = ReportPlanStore();
    await store.savePlan(
      periodKey: 'weekly-2026-07-13',
      start: DateTime(2026, 7, 13),
      end: DateTime(2026, 7, 20),
      planTasks: [
        task('u1', due: DateTime(2026, 7, 14)),
        task('u2'),
      ],
    );

    final prev =
        await store.loadPreviousPlan(periodStart: DateTime(2026, 7, 20));
    expect(prev, isNotNull);
    expect(prev!.start, DateTime(2026, 7, 13));
    expect(prev.rows.length, 2);
    expect(prev.rows[0].uid, 'u1');
    expect(prev.rows[0].title, 'task u1');
    expect(prev.rows[0].project, 'Cosmo');
    expect(prev.rows[0].due, DateTime(2026, 7, 14));
    expect(prev.rows[0].priority, 'P1');
    expect(prev.rows[1].due, isNull);
  });

  test('the same period is never returned as its own previous plan',
      () async {
    final store = ReportPlanStore();
    await store.savePlan(
      periodKey: 'weekly-2026-07-13',
      start: DateTime(2026, 7, 13),
      end: DateTime(2026, 7, 20),
      planTasks: [task('u1')],
    );
    final same =
        await store.loadPreviousPlan(periodStart: DateTime(2026, 7, 13));
    expect(same, isNull);
  });

  test('the closest earlier plan wins when several are archived', () async {
    final store = ReportPlanStore();
    for (final d in [1, 8, 15]) {
      await store.savePlan(
        periodKey: 'weekly-2026-07-0$d',
        start: DateTime(2026, 7, d),
        end: DateTime(2026, 7, d + 7),
        planTasks: [task('u$d')],
      );
    }
    final prev =
        await store.loadPreviousPlan(periodStart: DateTime(2026, 7, 22));
    expect(prev!.start, DateTime(2026, 7, 15));
    expect(prev.rows.single.uid, 'u15');
  });

  test('archive is pruned to the newest 12 periods', () async {
    final store = ReportPlanStore();
    for (var i = 1; i <= 14; i++) {
      await store.savePlan(
        periodKey: 'weekly-2026-07-$i',
        start: DateTime(2026, 6, 1 + i),
        end: DateTime(2026, 6, 8 + i),
        planTasks: [task('u$i')],
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith('report.plan.')).length;
    expect(keys, 12);
    // The newest survives…
    final newest =
        await store.loadPreviousPlan(periodStart: DateTime(2026, 12, 1));
    expect(newest!.rows.single.uid, 'u14');
  });

  test('corrupt archive entries are skipped, not thrown', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('report.plan.broken', '{not json');
    final store = ReportPlanStore();
    final prev =
        await store.loadPreviousPlan(periodStart: DateTime(2026, 7, 20));
    expect(prev, isNull);
  });
}
