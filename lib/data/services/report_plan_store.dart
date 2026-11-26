import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';

/// One planned row of a generated report's "Plan for Next Period" table —
/// persisted at generation time so the NEXT period's report can render the
/// "Last Period's Plan vs. Actual" comparison from real data. The Isar DB
/// keeps no task history, so the previous plan must be archived by us.
class ReportPlanRow {
  final String uid;
  final String title;
  final String project;
  final DateTime? due;
  final String priority; // short label, e.g. "P1"

  ReportPlanRow({
    required this.uid,
    required this.title,
    required this.project,
    required this.due,
    required this.priority,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': title,
        'project': project,
        if (due != null) 'due': due!.millisecondsSinceEpoch,
        'priority': priority,
      };

  static ReportPlanRow fromJson(Map<String, dynamic> j) => ReportPlanRow(
        uid: j['uid'] as String,
        title: j['title'] as String,
        project: j['project'] as String? ?? '',
        due: j['due'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['due'] as int),
        priority: j['priority'] as String? ?? '',
      );
}

/// A stored period plan: the tasks that were open when a report over
/// [start, end) was generated.
class ReportPlanEntry {
  final DateTime start;
  final DateTime end;
  final List<ReportPlanRow> rows;

  ReportPlanEntry({required this.start, required this.end, required this.rows});

  Map<String, dynamic> toJson() => {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'rows': [for (final r in rows) r.toJson()],
      };

  static ReportPlanEntry fromJson(Map<String, dynamic> j) => ReportPlanEntry(
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        rows: [
          for (final r in (j['rows'] as List? ?? []))
            ReportPlanRow.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

/// Archives each generated report's plan in shared_preferences (JSON, one
/// key per period) and serves the previous period's plan back to the report
/// renderer. Keeps only the newest [_keepEntries] periods.
class ReportPlanStore {
  static const _keyPrefix = 'report.plan.';
  static const _keepEntries = 12;

  /// Persists [planTasks] as the plan of the period identified by
  /// [periodKey] (e.g. "weekly-2026-11-09"), overwriting any earlier save
  /// of the same period.
  Future<void> savePlan({
    required String periodKey,
    required DateTime start,
    required DateTime end,
    required List<Task> planTasks,
  }) async {
    final entry = ReportPlanEntry(
      start: start,
      end: end,
      rows: [
        for (final t in planTasks)
          ReportPlanRow(
            uid: t.uid,
            title: t.title,
            project: t.project.trim(),
            due: t.dueDate,
            priority: t.priority.shortLabel,
          ),
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$periodKey', jsonEncode(entry.toJson()));
    await _prune(prefs);
  }

  /// The stored plan whose period starts most recently BEFORE [periodStart]
  /// — the plan this report's "Last Period's Plan vs. Actual" section
  /// compares against. Corrupt entries are skipped, not thrown.
  Future<ReportPlanEntry?> loadPreviousPlan({
    required DateTime periodStart,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    ReportPlanEntry? best;
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      try {
        final e = ReportPlanEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        if (!e.start.isBefore(periodStart)) continue;
        if (best == null || e.start.isAfter(best.start)) best = e;
      } catch (_) {
        // Corrupt entry — skip it rather than breaking report generation.
      }
    }
    return best;
  }

  Future<void> _prune(SharedPreferences prefs) async {
    final stored = <String, ReportPlanEntry>{};
    for (final k in prefs.getKeys().where((k) => k.startsWith(_keyPrefix))) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      try {
        stored[k] = ReportPlanEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    if (stored.length <= _keepEntries) return;
    final keysByAge = stored.keys.toList()
      ..sort((a, b) => stored[b]!.start.compareTo(stored[a]!.start));
    for (final k in keysByAge.skip(_keepEntries)) {
      await prefs.remove(k);
    }
  }
}
