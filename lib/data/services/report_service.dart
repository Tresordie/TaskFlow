import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/markdown/table_support.dart' as table_support;
import '../models/task.dart';
import '../repositories/task_repository.dart';
import 'ai_service.dart';
import 'attachment_service.dart';
import 'report_plan_store.dart';

enum ReportPeriod {
  daily,
  weekly,
  monthly,
  yearly,
  custom;

  String get label {
    switch (this) {
      case ReportPeriod.daily:
        return 'Daily';
      case ReportPeriod.weekly:
        return 'Weekly';
      case ReportPeriod.monthly:
        return 'Monthly';
      case ReportPeriod.yearly:
        return 'Yearly';
      case ReportPeriod.custom:
        return 'Custom';
    }
  }
}

/// Output language for generated reports.
enum ReportLanguage {
  english,
  chinese;

  String get label => this == ReportLanguage.english ? 'English' : '中文';
}

/// Optional task filter applied before report aggregation. A null field
/// means "all" for that dimension.
class ReportFilter {
  final String? project;
  final String? tag;
  final TaskStatus? status;
  final Priority? priority;

  const ReportFilter({this.project, this.tag, this.status, this.priority});

  bool get isActive =>
      project != null || tag != null || status != null || priority != null;

  bool matches(Task t) {
    if (project != null && t.project.trim() != project) return false;
    if (tag != null && !t.tags.contains(tag)) return false;
    if (status != null && t.status != status) return false;
    if (priority != null && t.priority != priority) return false;
    return true;
  }

  /// Compact human-readable summary, shown in the report meta line.
  String describe() {
    final parts = <String>[
      if (project != null) 'project: $project',
      if (tag != null) 'tag: #$tag',
      if (status != null) 'status: ${status!.label}',
      if (priority != null) 'priority: ${priority!.shortLabel}',
    ];
    return parts.join(' · ');
  }
}

/// Aggregated snapshot of everything that happened inside a period.
class ReportData {
  final ReportPeriod period;
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  final ReportFilter filter;
  final List<Task> completed;
  final List<Task> inProgress;
  final List<Task> planned; // created in period, still planned
  final List<Task> overdue; // due before end, not completed
  final Map<Task, List<ExecutionEntry>> logActivity;
  final int entryPass;
  final int entryFail;
  final int entryBlocked;
  final int entryNote;
  final int subStepsDone;
  final int subStepsTotal;

  ReportData({
    required this.period,
    required this.start,
    required this.end,
    this.filter = const ReportFilter(),
    required this.completed,
    required this.inProgress,
    required this.planned,
    required this.overdue,
    required this.logActivity,
    required this.entryPass,
    required this.entryFail,
    required this.entryBlocked,
    required this.entryNote,
    required this.subStepsDone,
    required this.subStepsTotal,
  });

  int get totalTouched => {
        ...completed,
        ...inProgress,
        ...planned,
        ...logActivity.keys,
      }.length;

  double get completionRate =>
      totalTouched == 0 ? 0 : completed.length / totalTouched;

  String get rangeLabel {
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(start)} → ${f.format(end.subtract(const Duration(days: 1)))}';
  }

  String get titlePrefix {
    final anchor = start;
    switch (period) {
      case ReportPeriod.daily:
        return DateFormat('yyyy-MM-dd').format(anchor);
      case ReportPeriod.weekly:
        final iso = _isoWeek(anchor);
        return '${anchor.year}-W${iso.toString().padLeft(2, '0')}';
      case ReportPeriod.monthly:
        return DateFormat('yyyy-MM').format(anchor);
      case ReportPeriod.yearly:
        return DateFormat('yyyy').format(anchor);
      case ReportPeriod.custom:
        final f = DateFormat('yyyy-MM-dd');
        return '${f.format(start)}_${f.format(end.subtract(const Duration(days: 1)))}';
    }
  }

  /// De-duplicated union of every task touched in the period, used for
  /// grouping (by project) in the dashboard / details sections. De-dupes by
  /// object identity: all lists are built from a single repository query,
  /// so each task appears as one instance.
  List<Task> get touchedTasks {
    final seen = <Task>{};
    final result = <Task>[];
    for (final t in [
      ...completed,
      ...inProgress,
      ...planned,
      ...logActivity.keys,
    ]) {
      if (seen.add(t)) result.add(t);
    }
    return result;
  }

  static int _isoWeek(DateTime d) {
    // ISO-8601 week number (approximate at year edges).
    final ordinal = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    var week = (ordinal - d.weekday + 10) ~/ 7;
    if (week < 1) week = 52;
    if (week > 52) week = 1;
    return week;
  }
}

/// All user-facing report strings, localized by [ReportLanguage].
class _L {
  final ReportLanguage lang;
  const _L(this.lang);
  bool get _zh => lang == ReportLanguage.chinese;

  String periodLabel(ReportPeriod p) {
    switch (p) {
      case ReportPeriod.daily:
        return _zh ? '日报' : 'Daily';
      case ReportPeriod.weekly:
        return _zh ? '周报' : 'Weekly';
      case ReportPeriod.monthly:
        return _zh ? '月报' : 'Monthly';
      case ReportPeriod.yearly:
        return _zh ? '年报' : 'Yearly';
      case ReportPeriod.custom:
        return _zh ? '自定义' : 'Custom';
    }
  }

  String reportTitle(ReportPeriod p) => _zh
      ? 'TaskFlow ${periodLabel(p)} — '
      : 'TaskFlow ${periodLabel(p)} Report — ';

  String get period => _zh ? '周期' : 'Period';
  String get prepared => _zh ? '生成于' : 'Prepared';
  String get filters => _zh ? '筛选' : 'Filters';

  String get statusDashboard => _zh ? '状态仪表盘' : 'Status Dashboard';
  String get project => _zh ? '项目' : 'Project';
  String get status => _zh ? '状态' : 'Status';
  String get headline => _zh ? '要点' : 'Headline';

  String get executiveSummary => _zh ? '执行摘要' : 'Executive Summary';
  String get noneThisPeriod => _zh ? '本期无' : 'None this period';

  String get progressDetails => _zh ? '进度明细' : 'Progress Details';
  String get groupedByProject => _zh ? '（按项目分组）' : '(Grouped by project)';
  String get item => _zh ? '事项' : 'Item';
  String get completedWord => _zh ? '已完成' : 'Completed';

  String planForNext(ReportPeriod p) {
    switch (p) {
      case ReportPeriod.daily:
        return _zh ? '明日计划' : 'Plan for Next Day';
      case ReportPeriod.weekly:
        return _zh ? '下周计划' : 'Plan for Next Week';
      case ReportPeriod.monthly:
        return _zh ? '下月计划' : 'Plan for Next Month';
      case ReportPeriod.yearly:
        return _zh ? '明年计划' : 'Plan for Next Year';
      case ReportPeriod.custom:
        return _zh ? '下期计划' : 'Plan for Next Period';
    }
  }

  String get task => _zh ? '任务' : 'Task';
  String get due => _zh ? '截止' : 'Due';
  String get priority => _zh ? '优先级' : 'Priority';
  String get noPendingTasks => _zh ? '暂无待办任务。' : 'No pending tasks.';

  String get generatedBy => _zh ? '由 TaskFlow 生成' : 'Generated by TaskFlow';
  String get logEntries => _zh ? '日志条目' : 'Log entries';

  // RAG labels.
  String get onTrack => _zh ? '正常' : 'On Track';
  String get atRisk => _zh ? '有风险' : 'At Risk';

  String get noActivity => _zh ? '暂无动态' : 'No activity';
  String get generalGroup => _zh ? '通用' : 'General';

  // Task-detail fragments.
  String subStepsCount(int done, int total) =>
      _zh ? '子步骤 $done/$total' : '$done/$total sub-steps';
  String doneOn(String date) => _zh ? '完成于 $date' : 'done $date';
  String dueOn(String date) => _zh ? '截止 $date' : 'due $date';
  String completedDated(String date) =>
      _zh ? '已完成 $date' : 'Completed $date';

  // Risk / ask fragments.
  String overdueDetail(String date, String pri) =>
      _zh ? '逾期（截止 $date，$pri）' : 'overdue (due $date, $pri)';
  String blockedDetail(String content) =>
      _zh ? '阻塞：$content' : 'blocked: $content';
  String needsDecision(String content) =>
      _zh ? '需决策：$content' : 'needs decision: $content';

  // ── TL;DR block (report v2 format) ──
  String get tldr => 'TL;DR';
  String get tldrClosed => _zh ? '已完成' : 'Closed';
  String get tldrNeedsAttention => _zh ? '需关注' : 'Needs attention';
  String get tldrNeedFromYou => _zh ? '需要您' : 'Need from you';

  // ── Dashboard (report v2 format) ──
  String get openClosed => _zh ? '未关闭 · 已完成' : 'Open · closed';
  String get statusLegend => _zh
      ? '按严重度排序。🔴 阻塞 = 等待外部方行动或高优先级逾期 · '
          '🟡 有风险 = 逾期或存在失败记录 · 🟢 正常 = 进行中且按计划推进 · '
          '🕐 计划中 = 尚未开始。🔴/🟡 决定项目状态，🕐 不影响。'
      : 'Sorted by severity. 🔴 Blocked = waiting on an external party or a '
          'high-priority overdue item · 🟡 At Risk = overdue or has fail '
          'entries · 🟢 On Track = in progress and on schedule · '
          '🕐 Planned = not started yet. A 🔴/🟡 item sets its project '
          'status; 🕐 does not.';

  // ── Executive Summary tables (report v2 format) ──
  String get openItemsBySeverity =>
      _zh ? '未关闭事项（按严重度）' : 'Open items (by severity)';
  String get changeThisPeriod => _zh ? '本期变化' : 'Change this period';
  String get nextStep => _zh ? '下一步' : 'Next step';
  String get owner => _zh ? '负责人' : 'Owner';
  String get eta => _zh ? '预计完成' : 'ETA';
  String get closedThisPeriod => _zh ? '本期关闭' : 'Closed this period';
  String get result => _zh ? '结果' : 'Result';
  String get followUp => _zh ? '遗留事项' : 'Follow-up';
  String get decisionsSignoffs =>
      _zh ? '决策 / 需要拍板' : 'Decisions / sign-offs';

  // ── Last Period's Plan vs. Actual (report v2 format) ──
  String get lastPeriodPlan =>
      _zh ? '上期计划对比' : "Last Period's Plan vs. Actual";
  String get plannedPrevious => _zh ? '上期计划' : 'Planned (previous period)';
  String doneInPeriod(String date) =>
      _zh ? '✅ 本期完成 $date' : '✅ Done in period $date';
  String stillOpen(String due) =>
      _zh ? '⏩ 仍在进行（当前截止 $due）' : '⏩ Still open (now due $due)';
  String get stillOpenNoDue =>
      _zh ? '⏩ 仍在进行（无截止日）' : '⏩ Still open (no due date)';
  String get noLongerTracked => _zh ? '❔ 已不在当前任务集' : '❔ No longer tracked';
  String get noRecordedPlan => _zh ? '无上期存档计划。' : 'No recorded plan for the previous period.';

  // ── Open-item cells (report v2 format) ──
  String get ragBlocked => _zh ? '阻塞' : 'Blocked';
  String get plannedWord => _zh ? '计划中' : 'Planned';
  String get noChange => _zh ? '无变化' : 'No change';
  String logEntryCount(int n) =>
      _zh ? '$n 条日志' : n == 1 ? '1 log entry' : '$n log entries';
  String unblockPrefix(String content) =>
      _zh ? '解除阻塞：$content' : 'Unblock: $content';
  String get ownerPlaceholder => '—';
  String get noNextStep => '—';
  String get noFollowUp => '—';

  // Task-notes export (v1.13.2) — raw tasks + full notes, no AI.
  String get notesTitle =>
      _zh ? 'TaskFlow 任务笔记 — ' : 'TaskFlow Task Notes — ';
  String get tasksWord => _zh ? '个任务' : 'tasks';
  String get notesWord => _zh ? '条笔记' : 'notes';
  String get entriesWord => _zh ? '条' : 'entries';
  String get inPeriod => _zh ? '期内' : 'in period';
  String get inPeriodMark => _zh ? '（期内）' : '(in period)';
  String get descriptionLabel => _zh ? '描述' : 'Description';
  String get subStepsLabel => _zh ? '子步骤' : 'Sub-steps';
  String get executionLogLabel => _zh ? '执行日志' : 'Execution log';
  String get createdOn => _zh ? '创建' : 'Created';
  String get startedOn => _zh ? '开始' : 'Started';
  String get completedOn => _zh ? '完成' : 'Completed';
  String get tagsLabel => _zh ? '标签' : 'Tags';
  String get contents => _zh ? '目录' : 'Contents';
  String get overdueWord => _zh ? '逾期' : 'Overdue';
  String get attachmentsLabel => _zh ? '附件' : 'Attachments';
  String get noTasksInRange =>
      _zh ? '当前范围内没有任务。' : 'No tasks in the selected range.';
  String get noNotes => _zh ? '暂无笔记。' : 'No notes yet.';
  String get tasksChip => _zh ? '任务' : 'Tasks';
  String get notesChip => _zh ? '笔记' : 'Notes';
  String get inPeriodChip => _zh ? '期内笔记' : 'In-period notes';
  String get doneChip => _zh ? '已完成' : 'Completed';

  String notesStats(int tasks, int notes, int inPeriodNotes, int done) => _zh
      ? '$tasks 个任务 · $notes 条笔记（$inPeriodNotes 条期内）· $done 个已完成'
      : '$tasks tasks · $notes notes ($inPeriodNotes in period) · $done completed';
  String logCount(int total, int inPeriodNotes) => _zh
      ? '$total 条（$inPeriodNotes 条期内）'
      : '$total entries ($inPeriodNotes in period)';

  String statusLabel(TaskStatus s) {
    if (!_zh) return s.label;
    switch (s) {
      case TaskStatus.planned:
        return '计划中';
      case TaskStatus.inProgress:
        return '进行中';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.archived:
        return '已归档';
      case TaskStatus.blocked:
        return '阻塞';
    }
  }

  String entryTypeLabel(EntryType t) {
    if (!_zh) return t.label;
    switch (t) {
      case EntryType.note:
        return '笔记';
      case EntryType.pass:
        return '通过';
      case EntryType.fail:
        return '失败';
      case EntryType.blocked:
        return '阻塞';
    }
  }
}

class ReportService {
  final TaskRepository _repo;
  final ReportPlanStore _planStore = ReportPlanStore();

  ReportService(this._repo);

  // ─────────────── Plan archive (Last Period's Plan vs. Actual) ───────────────

  /// The tasks that should appear in a "plan" archive for [d]: every
  /// uncompleted task the report covers (in progress, planned, overdue,
  /// blocked). Also the row source of the Plan for Next Period table.
  List<Task> openTasksForPlan(ReportData d) {
    final seen = <Task>{};
    final open = <Task>[];
    for (final t in [...d.inProgress, ...d.planned, ...d.overdue]) {
      if (seen.add(t)) open.add(t);
    }
    int rank(Task t) => _severityRank(
        _taskSeverity(t, d, const _L(ReportLanguage.english)));
    int cmp(Task a, Task b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final p = a.priority.index.compareTo(b.priority.index);
      if (p != 0) return p;
      final ad = a.dueDate, bd = b.dueDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }
    return open..sort(cmp);
  }

  /// Archives the current period's plan so a future report can compare
  /// against it (see [loadPreviousPlan]).
  Future<void> savePlan(ReportData d) => _planStore.savePlan(
        periodKey: _planKey(d),
        start: d.start,
        end: d.end,
        planTasks: openTasksForPlan(d),
      );

  /// The plan archived for the period immediately before [d]'s, or null.
  Future<List<ReportPlanRow>?> loadPreviousPlan(ReportData d) async =>
      (await _planStore.loadPreviousPlan(periodStart: d.start))?.rows;

  static String _planKey(ReportData d) {
    final f = DateFormat('yyyy-MM-dd');
    return '${d.period.label.toLowerCase()}-${f.format(d.start)}';
  }

  /// Plain-text PREVIOUS PERIOD PLAN block for the full-report AI prompt:
  /// each archived row annotated with its actual outcome (computed from
  /// [d]), so the LLM can render the §3 comparison table from real data.
  String formatPreviousPlan(ReportData d, List<ReportPlanRow> rows) {
    final f = DateFormat('MM-dd');
    final completedByUid = {for (final t in d.completed) t.uid: t};
    final openByUid = {for (final t in openTasksForPlan(d)) t.uid: t};
    final b = StringBuffer();
    b.writeln('PREVIOUS PERIOD PLAN (archive — compare in section 3 '
        '"Last Period\'s Plan vs. Actual"; one line per planned task):');
    for (final r in rows) {
      final plannedDue = r.due != null ? f.format(r.due!) : '—';
      String actual;
      final c = completedByUid[r.uid];
      if (c != null && c.completedAt != null) {
        actual = 'DONE in this period on ${f.format(c.completedAt!)}';
      } else if (openByUid.containsKey(r.uid)) {
        final due = openByUid[r.uid]!.dueDate;
        actual = due != null
            ? 'STILL OPEN (current due ${f.format(due)})'
            : 'STILL OPEN (no due date)';
      } else {
        actual = 'NO LONGER TRACKED (completed earlier, archived or removed)';
      }
      b.writeln('- ${r.title} (planned due $plannedDue) → $actual');
    }
    return b.toString();
  }


  /// Computes the [start, end) range for [period] containing [anchor].
  static (DateTime, DateTime) rangeFor(ReportPeriod period, DateTime anchor) {
    switch (period) {
      case ReportPeriod.daily:
        final s = DateTime(anchor.year, anchor.month, anchor.day);
        return (s, s.add(const Duration(days: 1)));
      case ReportPeriod.weekly:
        final day = DateTime(anchor.year, anchor.month, anchor.day);
        final monday = day.subtract(Duration(days: day.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
      case ReportPeriod.monthly:
        final s = DateTime(anchor.year, anchor.month, 1);
        return (s, DateTime(anchor.year, anchor.month + 1, 1));
      case ReportPeriod.yearly:
        final s = DateTime(anchor.year, 1, 1);
        return (s, DateTime(anchor.year + 1, 1, 1));
      case ReportPeriod.custom:
        // Custom ranges are passed explicitly to generateRange(); this
        // fallback (the anchor's single day) is never used in practice.
        final s = DateTime(anchor.year, anchor.month, anchor.day);
        return (s, s.add(const Duration(days: 1)));
    }
  }

  Future<ReportData> generate(
    ReportPeriod period,
    DateTime anchor, {
    ReportFilter filter = const ReportFilter(),
    Set<String>? onlyUids,
  }) {
    final (start, end) = rangeFor(period, anchor);
    return _build(period, start, end, filter, onlyUids);
  }

  /// Generates a report over an explicit [start, end] date range (the
  /// "Custom" period). Both bounds are inclusive calendar days — the end
  /// day is extended to cover its full 24h before aggregation.
  Future<ReportData> generateRange(
    DateTime start,
    DateTime end, {
    ReportFilter filter = const ReportFilter(),
    Set<String>? onlyUids,
  }) {
    final s = DateTime(start.year, start.month, start.day);
    final e =
        DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
    return _build(ReportPeriod.custom, s, e, filter, onlyUids);
  }

  /// [onlyUids] restricts aggregation to the tasks whose uid is in the set
  /// (the Reports screen's per-task checkbox selection); null = every task.
  /// Archived tasks are ALWAYS excluded from report aggregation.
  Future<ReportData> _build(ReportPeriod period, DateTime start, DateTime end,
      ReportFilter filter, Set<String>? onlyUids) async {
    final all = (await _repo.getAllTasks())
        .where((t) => t.status != TaskStatus.archived)
        .where(filter.matches)
        .where((t) => onlyUids == null || onlyUids.contains(t.uid))
        .toList();

    bool inRange(DateTime? t) =>
        t != null && !t.isBefore(start) && t.isBefore(end);

    final completed = all.where((t) => inRange(t.completedAt)).toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

    final inProgress = all
        .where((t) =>
            t.status == TaskStatus.inProgress &&
            (inRange(t.startedAt) ||
                (t.startedAt != null && t.startedAt!.isBefore(end))))
        .toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

    final planned = all
        .where((t) => t.status == TaskStatus.planned && inRange(t.createdAt))
        .toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

    final overdue = all
        .where((t) =>
            t.status != TaskStatus.completed &&
            t.dueDate != null &&
            t.dueDate!.isBefore(end))
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    // Execution-log entries inside the period, grouped per task.
    final logActivity = <Task, List<ExecutionEntry>>{};
    var pass = 0, fail = 0, blocked = 0, note = 0;
    for (final t in all) {
      final entries = t.executionLog.where((e) => inRange(e.timestamp)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (entries.isNotEmpty) logActivity[t] = entries;
      for (final e in entries) {
        switch (e.type) {
          case EntryType.pass:
            pass++;
          case EntryType.fail:
            fail++;
          case EntryType.blocked:
            blocked++;
          case EntryType.note:
            note++;
        }
      }
    }

    // Sub-step progress across tasks touched in the period.
    var ssDone = 0, ssTotal = 0;
    for (final t in all) {
      if (inRange(t.createdAt) ||
          inRange(t.completedAt) ||
          logActivity.containsKey(t)) {
        ssTotal += t.subSteps.length;
        ssDone += t.subSteps.where((s) => s.completed).length;
      }
    }

    return ReportData(
      period: period,
      start: start,
      end: end,
      filter: filter,
      completed: completed,
      inProgress: inProgress,
      planned: planned,
      overdue: overdue,
      logActivity: logActivity,
      entryPass: pass,
      entryFail: fail,
      entryBlocked: blocked,
      entryNote: note,
      subStepsDone: ssDone,
      subStepsTotal: ssTotal,
    );
  }

  /// Runs one [AiService.enhanceTask] call per touched task, feeding it
  /// ALL execution-log entries inside the report period. Returns:
  ///  - `summaries`: one-line log summaries for the Details column,
  ///  - `titles`: task titles translated into the report language,
  ///  - `failed`: how many tasks' AI calls threw (0 = full success), and
  ///  - `firstError`: the message of the first failure, if any.
  /// Failed tasks are omitted from both maps (the renderer falls back to
  /// the original title + heuristic details); the UI should surface
  /// [failed]/[firstError] so silent fallbacks never go unnoticed. Maps
  /// are keyed by task identity, matching [ReportData.touchedTasks].
  Future<
      ({
        Map<Task, String> summaries,
        Map<Task, String> titles,
        Map<String, String> terms,
        int failed,
        String? firstError,
      })> aiEnhance(
    ReportData d,
    AiService ai,
    ReportLanguage lang,
  ) async {
    final summaries = <Task, String>{};
    final titles = <Task, String>{};
    final chinese = lang == ReportLanguage.chinese;
    var failed = 0;
    String? firstError;
    // Process every task that may appear in ANY report section — not just
    // touchedTasks (dashboard/details) but also overdue tasks that show up
    // in Risks/Blockers and Asks. Without this, an overdue task that was
    // never started and has no in-period log entries would keep its raw
    // (Chinese) title in an English report.
    final allReportTasks = <Task>{...d.touchedTasks, ...d.overdue};
    for (final t in allReportTasks) {
      try {
        final r = await ai.enhanceTask(
          t,
          chinese: chinese,
          periodEntries: d.logActivity[t] ?? const [],
        );
        if (r.summary.trim().isNotEmpty) summaries[t] = r.summary.trim();
        if (r.title.trim().isNotEmpty) titles[t] = r.title.trim();
      } catch (e) {
        failed++;
        firstError ??= e.toString();
      }
    }
    // Translate project names + tags in ONE batch call so an English report
    // contains no Chinese group headers or tag text. Failure here is
    // non-fatal: the renderer falls back to the raw values.
    var terms = <String, String>{};
    try {
      final allTerms = <String>[
        for (final t in allReportTasks) t.project.trim(),
        for (final t in allReportTasks) ...t.tags,
      ];
      terms = await ai.translateTerms(allTerms, toChinese: chinese);
    } catch (_) {
      // Keep terms empty -> raw project/tag text is shown.
    }
    return (
      summaries: summaries,
      titles: titles,
      terms: terms,
      failed: failed,
      firstError: firstError,
    );
  }

  // ─────────────── Full AI report generation (spec-driven) ───────────────

  /// Formats every task in [d] into the plain-text TASK DATA block that the
  /// full-report system prompt ([fullReportPrompt]) expects: title, project,
  /// status, priority, due date, sub-steps and ALL in-period execution-log
  /// entries. Archived tasks are already excluded by [_build].
  String formatTaskData(ReportData d) {
    final f = DateFormat('MM-dd');
    final fr = DateFormat('yyyy-MM-dd');
    final b = StringBuffer();
    b.writeln('TASK DATA (${fr.format(d.start)} → '
        '${fr.format(d.end.subtract(const Duration(days: 1)))}):');
    b.writeln();
    for (final t in d.touchedTasks) {
      b.writeln('Task: ${t.title}');
      final proj = t.project.trim();
      if (proj.isNotEmpty) b.writeln('Project: $proj');
      var status = t.status.label;
      if (t.status == TaskStatus.completed && t.completedAt != null) {
        status += ' (${f.format(t.completedAt!)})';
      }
      b.writeln('Status: $status');
      b.writeln('Priority: ${t.priority.shortLabel}');
      if (t.dueDate != null) b.writeln('Due: ${f.format(t.dueDate!)}');
      if (t.subSteps.isNotEmpty) {
        final done = t.subSteps.where((s) => s.completed).length;
        b.writeln('Sub-steps ($done/${t.subSteps.length}):');
        for (final s in t.subSteps) {
          b.writeln('  [${s.completed ? 'x' : ' '}] ${s.title}');
        }
      }
      // Task description (free-text detail on the task page). The spec
      // requires summaries to draw from BOTH the description and the
      // execution log, so include it (whitespace-collapsed, generously
      // capped to keep the prompt bounded).
      final desc = t.description?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (desc != null && desc.isNotEmpty) {
        var dd = desc;
        if (dd.length > 2000) dd = '${dd.substring(0, 2000)}…';
        b.writeln('Description: $dd');
      }
      // v1.4.88: the AI reads EVERY log entry of the task — not only the
      // ones inside the reporting period. v1.9.3 refines the split: entries
      // from the LAST 7 DAYS / one week (relative to the period end) are the
      // summary's focus and are fed in full; entries older than one week are
      // explicitly labeled "context only" so the model condenses them into a
      // single history sentence instead of detailing them (user request).
      // The older-context text is still capped (12000 chars per task) only
      // to keep pathological histories from blowing up the prompt.
      final entries = [...t.executionLog]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (entries.isNotEmpty) {
        final recentCut = d.end.subtract(const Duration(days: 7));
        final inPeriodCount = entries
            .where((e) =>
                !e.timestamp.isBefore(d.start) &&
                e.timestamp.isBefore(d.end))
            .length;
        final recentCount = entries.where((e) => !e.timestamp.isBefore(recentCut)).length;
        b.writeln('Execution Log (${entries.length} entries total, '
            '$inPeriodCount in period, $recentCount within the last '
            '7 days):');
        var earlierChars = 0;
        var earlierTruncated = false;
        for (final e in entries) {
          final content =
              e.content.replaceAll(RegExp(r'\s+'), ' ').trim();
          final inPeriod = !e.timestamp.isBefore(d.start) &&
              e.timestamp.isBefore(d.end);
          if (inPeriod) {
            b.writeln('  [${f.format(e.timestamp)}] ${e.type.name}: $content');
          } else if (!e.timestamp.isBefore(recentCut)) {
            // Recent (last 7 days) but outside the period — still focus
            // material, fed in full.
            b.writeln('  [${fr.format(e.timestamp)}] ${e.type.name}: $content');
          } else {
            if (earlierTruncated) continue;
            if (earlierChars + content.length > 12000) {
              earlierTruncated = true;
              b.writeln('  … (remaining earlier entries omitted for length)');
              continue;
            }
            earlierChars += content.length;
            b.writeln('  [${fr.format(e.timestamp)}] ${e.type.name} '
                '(older than 7 days — context only): $content');
          }
        }
      } else {
        b.writeln('Execution Log: (no entries)');
      }
      b.writeln();
    }
    return b.toString();
  }

  /// System prompt for full AI report generation — implements the rules
  /// from weekly_report_ai_summary_prompts.md: deep comprehension of all
  /// execution logs, per-project classification, synthesis with technical
  /// fidelity, NPI context inference, archived-task exclusion, and the exact
  /// 5-section output format. Language of the output follows [lang].
  static String fullReportPrompt(ReportLanguage lang) =>
      lang == ReportLanguage.chinese ? _fullReportPromptZh : _fullReportPromptEn;

  static const _fullReportPromptEn =
      'You are a senior technical program manager assistant. Your job is to '
      'analyze a set of work tasks recorded in TaskFlow over a specified '
      'date range, deeply understand the content, and produce a structured '
      'report in English.\n'
      'The user is an NPI (New Product Introduction) hardware/test engineer '
      'working on e-bike programs. Tasks are organized by project. Each '
      'task has an Execution Log — a chronological series of Notes '
      'documenting progress, decisions, blockers, and outcomes.\n\n'
      'PROCESSING RULES — before generating output you MUST:\n'
      '1. FIRST, read through EVERY task\'s notes — its description AND '
      'its ENTIRE Execution Log — and understand the background of each '
      'task as well as the content of its notes BEFORE writing '
      'anything: every entry, including the ones labeled "(older than '
      '7 days — context only)" from before the recent window. Do not '
      'skim or skip entries. Summaries must be based on a genuine '
      'UNDERSTANDING of the logs (what was done, why, what was '
      'decided, what the results were) — not on surface copying. Entries '
      'from the last 7 days (one week) drive the summary; older '
      'context-only entries provide background that explains them.\n'
      '2. Classify each task under its Project.\n'
      '3. Synthesize — distill raw notes into concise, meaningful '
      'summaries, but NEVER over-compress technical content. Technical '
      'key points — part numbers, firmware versions, parameters, '
      'measurements, test conditions, thresholds, model numbers, vendor '
      'names, results, root causes — must stay COMPLETE and specific in '
      'the summary. When in doubt between shortening and keeping a '
      'technical detail, KEEP it. Copy every technical identifier '
      'verbatim; never rewrite, generalize, paraphrase, or substitute '
      'it.\n'
      '4. One fact per line — each bullet states exactly ONE fact, event, '
      'or decision. Never merge multiple facts into a single bullet or '
      'sentence. If a note contains three facts, that becomes three '
      'bullets.\n'
      '5. Hierarchical structure — NEVER write flat, run-on paragraphs. '
      'All summaries must use a clear nested bullet hierarchy with exact '
      'Markdown indentation: level 1 "- " (no indent) for key points, '
      'level 2 "  - " (2 spaces) for supporting details, level 3 "    - " '
      '(4 spaces) for finer specifics. The reader must be able to scan '
      'the structure at a glance.\n'
      '6. Infer context — use your understanding of NPI workflows '
      '(EVT → DVT → PVT → MP), hardware validation, factory coordination, '
      'and cross-team communication to fill logical gaps and produce '
      'coherent narratives.\n'
      '7. Archived tasks are already excluded from the input data — '
      'never mention or summarize archived tasks.\n'
      '8. Output language: English only. NEVER output Chinese characters '
      'in the final report (any Chinese character in the output is a '
      'failure). Task data may be in Chinese — translate ALL of it.\n\n'
      'CRITICAL — the report MUST contain ALL 5 sections below, in order, '
      'without exception. Never omit, truncate, or skip any section — even '
      'if a section has no relevant data, include its header with "None '
      'this period." A report missing any section is INVALID.\n\n'
      'OUTPUT FORMAT — generate the report using EXACTLY this structure '
      '(Markdown):\n'
      '# TaskFlow Report — {PERIOD_LABEL}\n'
      '**Period:** {START} → {END} | **Prepared:** {TODAY}\n\n'
      '---\n\n'
      '> **TL;DR**\n'
      '>\n'
      '> - **Closed**\n'
      '>   - {completed task title} (done {MM-DD})   ← ONE sub-bullet per '
      'completed task, or "None this period"\n'
      '> - **Needs attention**\n'
      '>   - {task title} — {root cause / impact, ONE line}   ← the 1–3 '
      'most severe risks (blocked first, then overdue), or "None this '
      'period"\n'
      '> - **Need from you:** {the single most important decision/input '
      'needed from the reader, or "None this period"}\n\n'
      '---\n\n'
      '## 1. Status Dashboard\n\n'
      '*Sorted by severity. 🔴 Blocked = waiting on an external party · '
      '🟡 At Risk = overdue or has fail entries · 🟢 On Track = '
      'progressing and on schedule · 🕐 Planned = not started yet.*\n\n'
      '| Project | Status | Open · closed | Headline |\n'
      '|:-----|:------:|:--------:|:---------|\n'
      '| {Project} | {emoji} {label} | {open} · {closed} | {per-task '
      'headlines — ONE line per task of the project: **{task title}** '
      '— {ONE-sentence summary of its most recent updates}, lines '
      'joined by <br>} |\n\n'
      '(rows sorted worst severity first: 🔴 projects, then 🟡, then the '
      'rest)\n\n'
      '---\n\n'
      '## 2. Executive Summary\n\n'
      '### Open items (by severity)\n\n'
      '| Item | Status | Change this period | Next step | Owner | ETA |\n'
      '|:-----|:------:|:------|:------|:------|:---:|\n'
      '| **{Project}** · {Task title} | {emoji} {label} | {what the '
      'in-period log entries moved, ONE line; "No change" only when the '
      'period has zero log entries for the task; prefix "New: " when the '
      'task started in the period} | {the concrete next action, naming '
      'WHO must act when external} | {party we wait on (vendor / '
      'customer / another team) or "—"} | {MM-DD or —, ⚠️-marked when '
      'overdue} |\n\n'
      '(ONE row per open task, sorted 🔴 → 🟡 → 🟢 → 🕐, ties by priority '
      'P0 first; completed tasks NEVER listed here)\n\n'
      '### Closed this period\n\n'
      '| Item | Result | Follow-up |\n'
      '|:-----|:-----|:-----|\n'
      '| **{Project}** · {Task title} | {completed {MM-DD} + 1–2 '
      'sentences on the OUTCOME} | {what remains (tickets, pending '
      'confirmations) or "—"} |\n\n'
      '### Decisions / sign-offs\n\n'
      '- {Item requiring external input, escalation, or cross-team '
      'decision}\n'
      '- (If none: "None this period")\n\n'
      '---\n\n'
      '## 3. Last Period\'s Plan vs. Actual\n\n'
      'The input contains a "PREVIOUS PERIOD PLAN" block (present when '
      'the previous period\'s plan was archived). Render ONE row per '
      'planned task, copying the annotated outcome VERBATIM:\n\n'
      '| Planned (previous period) | Due | Result |\n'
      '|:-----|:---:|:-----|\n'
      '| {planned task title} | {planned due MM-DD or —} | {✅ Done in '
      'period {MM-DD} / ⏩ Still open (now due {MM-DD}) / ❔ No longer '
      'tracked — as annotated in the block} |\n\n'
      'If NO "PREVIOUS PERIOD PLAN" block is present in the input, write '
      'exactly one line: _No recorded plan for the previous period._\n\n'
      '---\n\n'
      '## 4. Progress Details\n'
      '*(Grouped by project, SAME project order as section 1)*\n\n'
      '### {Project Name}\n\n'
      '#### {🟩/🔴/🟡/🟢/🕐} {Task title} — {Completed {MM-DD} / '
      'Blocked / At Risk / On Track / Planned} · due {MM-DD or —}\n'
      '- {detail item 1}\n'
      '- {detail item 2}\n\n'
      '(repeat the block for each task, blank line between blocks)\n\n'
      '---\n\n'
      '## 5. Plan for Next Period\n\n'
      '| Project | Task | Due | Priority |\n'
      '|:-----:|:-----|:---:|:--------:|\n'
      '| {Project} | {Task} | {MM-DD or —} | '
      '{P0–P3} |\n\n'
      '(ONE row per open task — blocked and overdue INCLUDED, completed '
      'tasks EXCLUDED; sorted 🔴 → 🟡 → 🟢 → 🕐, ties by priority)\n\n'
      '---\n'
      '_Generated by TaskFlow · Log entries: Pass {n} / Fail {n} / '
      'Blocked {n} / Note {n}_\n\n'
      'SECTION-SPECIFIC RULES:\n\n'
      '1. TL;DR:\n'
      '- A Markdown BLOCKQUOTE (every line prefixed "> "). Exactly 3 top '
      'bullets — Closed, Needs attention, Need from you — each with its '
      'sub-bullets exactly as in the skeleton. One line per item, no '
      'paragraphs.\n'
      '- Need from you must be ONE concrete, actionable request (a '
      'decision, an approval, an escalation, input from another team) '
      'drawn from the most severe blocker; "None this period" when '
      'nothing is needed. Never hedge.\n\n'
      '2. Status Dashboard:\n'
      '- One row per project that has at least one task in the period, '
      'rows sorted by severity: projects containing a 🔴 task first, '
      'then 🟡, then the rest.\n'
      '- Per-task status: 🔴 Blocked (status Blocked or a blocked log '
      'entry — waiting on an external party); 🟡 At Risk (overdue or a '
      'fail log entry); 🟢 On Track (in progress, on schedule); '
      '🕐 Planned (not started). The project status = its worst open '
      'task.\n'
      '- Open · closed = number of uncompleted tasks · number of tasks '
      'completed in the period.\n'
      '- Headline = a LIST, ONE line per task of the project (EVERY task '
      'in the row must appear): each task is summarized in exactly ONE '
      'sentence centered on its MOST RECENT updates — the last-7-days '
      'log entries are the core, older entries only provide background. '
      'Line format: "**{task title}** — {one-sentence summary of the '
      'task\'s current state and latest progress}". Order lines by '
      'recency (task with the newest log activity first). Never output '
      'a bare task title without its sentence, never merge two tasks '
      'into one line, never write it as a paragraph. Lines are '
      'separated by <br>.\n\n'
      '3. Executive Summary:\n'
      '- Open items table: EVERY uncompleted task appears EXACTLY once — '
      'no omissions, no duplicates; completed tasks NEVER listed here. '
      'Status per the per-task rules above.\n'
      '- "Change this period" = what the in-period log entries moved '
      '(tests run, decisions made, replies received); write "No change" '
      'only when the period has zero log entries for the task; prefix '
      '"New: " when the task started in the period.\n'
      '- "Next step" must be concrete and actionable (e.g. "Foxlink to '
      'return the ATE SW schedule"), naming WHO acts next when it is an '
      'external party. "Owner" = the party we are waiting on (vendor, '
      'customer, another team) inferred from the task text and logs, '
      '"—" when nothing is awaited. "ETA" = the task due date, ⚠️-marked '
      'when overdue, "—" when none.\n'
      '- Closed this period: Result = what was accomplished (the '
      'OUTCOME, not the process), 1–2 sentences; Follow-up = what '
      'remains after the close (tickets, pending confirmations) or '
      '"—".\n'
      '- Decisions / sign-offs: extract from blockers, pending '
      'confirmations and cross-team dependencies; each item states WHO '
      'needs to decide/provide WHAT, and by WHEN if inferable; "None '
      'this period" when nothing is needed.\n\n'
      '4. Last Period\'s Plan vs. Actual:\n'
      '- Use ONLY the "PREVIOUS PERIOD PLAN" block — never invent plan '
      'rows, never recompute outcomes; copy each row\'s annotated '
      'outcome verbatim into the Result column.\n'
      '- When no block is present, write exactly the one-line italic '
      'note; NEVER fabricate a comparison.\n\n'
      '5. Progress Details:\n'
      '- Group tasks under their Project heading (H3); the project order '
      'MUST match section 1 (worst severity first). Within a project, '
      'tasks sorted 🔴 → 🟡 → 🟢 → 🕐, ties by priority (P0 first).\n'
      '- Layout (STRICT): each task is a CONTENT LIST, NOT a table. One '
      'H4 header line "#### {status emoji} {Task title} — {status '
      'label} · due {MM-DD}", followed immediately by its detail items '
      'as plain "- " bullets — EXACTLY ONE item per line, each item on '
      'its own line with a line break between items. NEVER put multiple '
      'items on one line; NEVER use <br> or a table for details. Leave '
      'one blank line between two task blocks.\n'
      '- Header status emoji: 🟩 Completed (+ completion date), '
      '🔴 Blocked, 🟡 At Risk, 🟢 On Track, 🕐 Planned.\n'
      '- RECENCY FOCUS (v1.9.3): detail items give a DETAILED description '
      'of the task and MUST center on the Execution Log entries from the '
      'LAST 7 DAYS / one week (in-period entries and recent entries are '
      'the core). Entries labeled "(older than 7 days — context only)" '
      'must be condensed into AT MOST ONE history sentence, placed as '
      'the LAST bullet of the task, prefixed "Earlier context: ". Never '
      'detail old entries bullet-by-bullet.\n'
      '- Detail items (MANDATORY for ALL tasks regardless of status): '
      'summarize from your understanding of the task description AND '
      'its Execution Log (recent entries in full, older ones as the '
      'single context sentence), combining both sources into a coherent '
      'summary — this applies equally to Completed, In Progress, '
      'Blocked, and Planned tasks. Maximum 5 items per task (the '
      'earlier-context sentence counts toward the 5). Each item = one '
      'distinct fact or milestone — do not merge unrelated facts. '
      'Technical key points must NOT be compressed away: keep part '
      'numbers, firmware versions, parameters, measurements, test '
      'conditions, dates, vendor names, tracking numbers, results and '
      'root causes complete and specific. Completed tasks are NOT '
      'exempt — their items must contain a full summary of what was '
      'done, how, and the outcome. NEVER dismiss a task that has '
      'content: if a task has a description or ANY Execution Log entry '
      '(even one older than 7 days), you MUST summarize it. The '
      'fallback "No execution logs in the reporting period" is ONLY '
      'allowed when the task has literally NO description AND NO log '
      'entries at all.\n\n'
      '6. Plan for Next Period (MANDATORY — never omit):\n'
      '- This section is REQUIRED in every report. If there are no open '
      'tasks, still include the section header with a note.\n'
      '- Include ONLY uncompleted tasks: In Progress, Planned, and '
      'Blocked/overdue tasks (unblock steps). NEVER include completed '
      'tasks.\n'
      '- ONE row per task (v1.9.3) — NEVER decompose a task into '
      'multiple rows or sub-task steps; the Task column carries the '
      'task title as-is.\n'
      '- Rows sorted 🔴 → 🟡 → 🟢 → 🕐, ties by priority (P0 first).\n'
      '- Due date: use the task\'s due date if set; otherwise "—".\n'
      '- Priority: P0 = critical path / blocks other work / imminent '
      'deadline; P1 = important, complete next period; P2 = planned but '
      'flexible; P3 = nice-to-have / backlog.\n\n'
      'QUALITY CHECKLIST (self-verify before outputting):\n'
      '- The TL;DR blockquote + ALL 5 sections are present, in order: '
      'TL;DR, Status Dashboard, Executive Summary (Open items / Closed '
      'this period / Decisions), Last Period\'s Plan vs. Actual, '
      'Progress Details, Plan for Next Period.\n'
      '- Every task in the input appears in at least one section.\n'
      '- No Chinese characters in the output.\n'
      '- Technical terms, part numbers, abbreviations, measurements '
      'preserved verbatim — none rewritten or generalized.\n'
      '- Every bullet states exactly one fact — no merged multi-fact '
      'bullets.\n'
      '- All summaries use nested bullet hierarchy — zero flat '
      'paragraphs anywhere.\n'
      '- TL;DR is a blockquote with exactly 3 top bullets; "Need from '
      'you" is one concrete request or "None this period".\n'
      '- Open items table lists EVERY uncompleted task exactly once, '
      'sorted 🔴 → 🟡 → 🟢 → 🕐; closed tasks only in the Closed table.\n'
      '- Status Dashboard Headline cells are <br>-separated lists — one '
      'line per task (bold title — one-sentence summary from its most '
      'recent updates), never bare titles and never one long line.\n'
      '- Progress Details: every task is an H4 header line + "- " bullet '
      'list, exactly one item per line, max 5 items per task; no tables '
      'and no <br> in this section; entries older than 7 days appear '
      'only as the single "Earlier context:" sentence.\n'
      '- Technical key points are complete and specific — nothing '
      'over-compressed.\n'
      '- Plan rows: uncompleted tasks only, one row per task (no '
      'decomposition), sorted by severity then priority.\n'
      '- The report reads as a coherent narrative a director can scan '
      'in under 2 minutes.\n'
      '- Output ONLY the Markdown report — no extra prose, no code '
      'fences around the document.';

  static const _fullReportPromptZh =
      '你是一位资深技术项目管理助手。你的任务是分析 TaskFlow 中指定日期范围内的'
      '一组工作任务，深入理解内容，并生成结构化的中文报告。\n'
      '用户是一名 NPI（新产品导入）硬件/测试工程师，负责电动自行车项目。'
      '任务按项目组织，每个任务包含执行日志——按时间顺序记录进展、决策、'
      '阻塞和结果的 Note 条目。\n\n'
      '处理规则——生成输出前必须：\n'
      '1. 先通读每个任务的 notes——其描述（description）以及全部执行日志'
      '——包括标注为"(older than 7 days — context only)"的超出近一周'
      '（7 天）窗口的条目——在动笔前理解每个任务的背景与 notes 的内容，'
      '不得跳过任何条目。总结必须建立在对日志的真正理解'
      '之上（做了什么、为什么、决策是什么、结果如何），而非表面摘抄；'
      '近一周（7 天）内的条目是总结的主体，更早的仅作背景（context only）'
      '帮助解释近期进展。\n'
      '2. 将每个任务归类到其项目下。\n'
      '3. 综合提炼——将原始日志提炼为简洁、有意义的总结，但技术'
      '要点绝不过度缩减：料号、固件版本、参数、测量值、测试条件、'
      '阈值、型号、供应商、结果、根因等技术关键内容必须完整、具体'
      '地保留在总结中；在"缩短"与"保留技术细节"之间犹豫时，一律'
      '保留。所有技术标识一律照抄原文，禁止改写、概括、转述或替换。\n'
      '4. 一条一个事实——每个要点只陈述一个事实、事件或决策，'
      '禁止把多个事实合并进同一个要点或句子；一条日志含三个事实'
      '就拆成三个要点。\n'
      '5. 层级结构——禁止写平铺的流水段落。所有总结必须使用清晰的'
      '嵌套列表层级，缩进严格：一级 "- "（无缩进）表要点，'
      '二级 "  - "（两空格）表支撑细节，三级 "    - "（四空格）'
      '表更细信息，让读者一眼扫清结构。\n'
      '6. 推断上下文——利用你对 NPI 流程（EVT → DVT → PVT → MP）、'
      '硬件验证、工厂协调和跨团队沟通的理解，填补逻辑空白，'
      '生成连贯的叙述。\n'
      '7. 归档任务已从输入数据中排除——禁止提及或总结归档任务。\n'
      '8. 输出语言：仅中文。\n\n'
      '【关键】报告必须包含下面全部 5 个章节，按顺序，无一例外。'
      '禁止省略、截断或跳过任何章节——即使某章节没有相关数据，'
      '也要保留其标题并写"本期无"。缺少任何章节的报告视为无效。\n\n'
      '输出格式——严格按以下结构生成 Markdown 报告：\n'
      '# TaskFlow 报告 — {周期标签}\n'
      '**周期:** {起} → {止} | **生成于:** {今天}\n\n'
      '---\n\n'
      '> **TL;DR**\n'
      '>\n'
      '> - **已完成**\n'
      '>   - {已完成任务标题}（完成于 {MM-DD}）   ← 每个已完成任务一条，'
      '无则写"本期无"\n'
      '> - **需关注**\n'
      '>   - {任务标题} — {根因/影响，一句话}   ← 最严重的 1–3 条风险'
      '（阻塞优先，其次逾期），无则写"本期无"\n'
      '> - **需要您：** {需要读者拍板/提供的最重要的一件事，'
      '无则写"本期无"}\n\n'
      '---\n\n'
      '## 1. 状态仪表盘\n\n'
      '*按严重度排序。🔴 阻塞 = 等待外部方行动 · 🟡 有风险 = 逾期或存在'
      '失败记录 · 🟢 正常 = 进行中且按计划推进 · 🕐 计划中 = 尚未开始。'
      '*\n\n'
      '| 项目 | 状态 | 未关闭 · 已完成 | 要点 |\n'
      '|:-----|:------:|:--------:|:---------|\n'
      '| {项目} | {emoji} {标签} | {未关闭数} · {已完成数} | {要点——该项目每个'
      '任务一行：**{任务标题}** — {一句话总结其最近的更新}，行间用 '
      '<br> 分隔} |\n\n'
      '（行按严重度排序：含 🔴 任务的项目在前，其次 🟡，其余在后）\n\n'
      '---\n\n'
      '## 2. 执行摘要\n\n'
      '### 未关闭事项（按严重度）\n\n'
      '| 事项 | 状态 | 本期变化 | 下一步 | 负责人 | 预计完成 |\n'
      '|:-----|:------:|:------|:------|:------|:---:|\n'
      '| **{项目}** · {任务标题} | {emoji} {标签} | {本期日志推动的变化，'
      '一行；期内零日志才写"无变化"；期内新开始的任务加"新任务："前缀} | '
      '{具体下一步行动，外部方行动时写明谁} | {等待对象（供应商/客户/'
      '其他团队），无则"—"} | {MM-DD 或 —，逾期加 ⚠️} |\n\n'
      '（每个未关闭任务恰好一行，按 🔴 → 🟡 → 🟢 → 🕐 排序，同档按优先级 '
      'P0 在前；已完成任务禁止列入）\n\n'
      '### 本期关闭\n\n'
      '| 事项 | 结果 | 遗留事项 |\n'
      '|:-----|:-----|:-----|\n'
      '| **{项目}** · {任务标题} | {完成于 {MM-DD} + 1–2 句结果（讲结果'
      '而非过程）} | {遗留（工单、待确认事项）或"—"} |\n\n'
      '### 决策 / 需要拍板\n\n'
      '- {需要外部输入、升级或跨团队决策的事项}\n'
      '- （若无："本期无"）\n\n'
      '---\n\n'
      '## 3. 上期计划对比\n\n'
      '输入中包含"PREVIOUS PERIOD PLAN"块（上期计划已存档时）。'
      '每个计划任务渲染一行，逐字照抄块中标注的实际结果：\n\n'
      '| 上期计划 | 截止 | 结果 |\n'
      '|:-----|:---:|:-----|\n'
      '| {上期任务标题} | {上期截止 MM-DD 或 —} | {✅ 本期完成 {MM-DD} / '
      '⏩ 仍在进行（当前截止 {MM-DD}） / ❔ 已不在当前任务集——照块中标注} |\n\n'
      '若输入中没有"PREVIOUS PERIOD PLAN"块，原样输出一行：'
      '_无上期存档计划。_\n\n'
      '---\n\n'
      '## 4. 进度明细\n'
      '*（按项目分组，项目顺序与第 1 节一致）*\n\n'
      '### {项目名}\n\n'
      '#### {🟩/🔴/🟡/🟢/🕐} {任务标题} — {已完成 {MM-DD} / 阻塞 / '
      '有风险 / 正常 / 计划中} · 截止 {MM-DD 或 —}\n'
      '- {详情条目1}\n'
      '- {详情条目2}\n\n'
      '（每个任务重复上述块，块之间空一行）\n\n'
      '---\n\n'
      '## 5. 下期计划\n\n'
      '| 项目 | 任务 | 截止 | 优先级 |\n'
      '|:-----:|:-----|:---:|:--------:|\n'
      '| {项目} | {任务} | {MM-DD 或 —} | {P0–P3} |\n\n'
      '（每个未关闭任务一行——阻塞与逾期任务一并列入，已完成任务禁止列入；'
      '按 🔴 → 🟡 → 🟢 → 🕐 排序，同档按优先级）\n\n'
      '---\n'
      '_由 TaskFlow 生成 · 日志条目: Pass {n} / Fail {n} / '
      'Blocked {n} / Note {n}_\n\n'
      '各节规则：\n\n'
      '1. TL;DR：\n'
      '- Markdown 引用块（每行以 ">" 开头）。恰好 3 个顶层要点：已完成、'
      '需关注、需要您——每条按骨架挂子要点，一行一条，禁止写段落。\n'
      '- "需要您"必须是一条具体、可行动的请求（决策、批准、升级、'
      '其他团队输入），取自最严重的阻塞事项；无则写"本期无"，'
      '禁止含糊表述。\n\n'
      '2. 状态仪表盘：每个有任务的项目一行；行按严重度排序——含 🔴 任务的'
      '项目在前，其次 🟡，其余在后。单任务状态：🔴 阻塞（状态为阻塞或有'
      '阻塞日志条目——等待外部方）、🟡 有风险（逾期或存在失败记录）、'
      '🟢 正常（进行中且按计划推进）、🕐 计划中（尚未开始）；'
      '项目状态 = 其最严重的未关闭任务；未关闭 · 已完成 = 未完成任务数 · '
      '本期完成任务数；要点=列表格式——该项目行中的每个任务各占一行'
      '（每个任务都必须出现）：每行"**{任务标题}** — {一句话总结}"，'
      '该句以该任务最近的更新为主体（近 7 天日志为核心，更早日志仅作'
      '背景），概括任务当前状态与最新进展；按最近更新时间排序（最近有'
      '日志动态的任务在前）；禁止只写任务标题不带句子，禁止把两个任务'
      '并成一行，禁止写成长段；行间用 <br> 分隔。\n\n'
      '3. 执行摘要：未关闭事项表——每个未关闭任务恰好出现一次，禁止遗漏、'
      '禁止重复，已完成任务禁止列入；状态按单任务状态规则；'
      '"本期变化"=期内日志推动的变化（执行的测试、做出的决策、'
      '收到的回复），期内零日志才写"无变化"，期内新开始的任务加'
      '"新任务："前缀；"下一步"必须具体可行动（如"等待 Foxlink 返回 '
      'ATE SW 排期"），外部方行动时写明谁；"负责人"=从任务文本与日志'
      '推断的等待对象（供应商、客户、其他团队），无则"—"；"预计完成"'
      '=任务截止日，逾期加 ⚠️ 前缀，无截止日写"—"。'
      '本期关闭表：结果=完成的结果（讲结果而非过程），1–2 句；'
      '遗留事项=关闭后仍待处理的内容（工单、待确认）或"—"。'
      '决策/需要拍板：从阻塞、待确认、跨团队依赖中提取；每项写明'
      '谁需要决策/提供什么、何时前（可推断时）；无则"本期无"。\n\n'
      '4. 上期计划对比：只依据"PREVIOUS PERIOD PLAN"块——禁止编造计划行、'
      '禁止重算结果，逐行照抄块中标注的实际结果到"结果"列；无块时'
      '原样输出一行斜体说明，禁止虚构对比。\n\n'
      '5. 进度明细：按项目分组（H3），项目顺序必须与第 1 节一致'
      '（最严重在前）；项目内任务按 🔴 → 🟡 → 🟢 → 🕐 排序，同档按优先级'
      '（P0 在前）。版式（严格）：每个任务是一段内容清单而非表格——'
      '一行 H4 标题"#### {状态图标} {任务标题} — {状态} · 截止 {MM-DD}"，'
      '紧跟其详情条目，每条用 "- " 列表项呈现，严格一条一行、逐条换行，'
      '禁止多条挤在一行、禁止使用 <br> 或表格，任务块之间空一行。'
      '标题状态图标 🟩已完成（附完成日期）🔴阻塞 🟡有风险 🟢正常 🕐计划中；'
      '近因聚焦（v1.9.3）：详情条目须对任务做详细描述，'
      '且必须以近一周（7 天）内的执行日志为主体（期内条目与近期条目'
      '是核心）；标注为"(older than 7 days — context only)"的更早'
      '条目必须压缩为至多一句历史总结，置于该任务要点列表的'
      '最后一条，以"早期背景："开头，禁止把旧日志逐条展开；'
      '详情条目（对所有状态的任务都必填）基于对任务描述与执行日志'
      '（近 7 天条目完整展开、更早条目并入那句背景）的理解综合总结'
      '——已完成、进行中、阻塞、计划中任务一视同仁，每任务最多 5 条'
      '（早期背景句计入 5 条），每条=一个独立事实；技术要点不得被'
      '压缩掉：料号、固件版本、参数、测量值、测试条件、日期、供应商、'
      '结果、根因必须完整具体；已完成任务不可豁免，其条目必须完整'
      '总结做了什么、如何做、结果如何；禁止轻易略过有内容的任务：'
      '只要任务有描述或任何执行日志（即使超过一周）就必须总结；'
      '仅当任务既无描述也无任何日志时，才写"报告期内无执行日志；'
      '{简要状态}"。\n\n'
      '6. 下期计划（必填，禁止省略）：每份报告都必须有此章节；'
      '即使没有未关闭任务，也要保留标题并加说明。只包含未完成任务：'
      '进行中、计划中、阻塞/逾期（解除步骤）的任务，禁止把已完成任务'
      '列入计划。每个任务只占一行（v1.9.3）——禁止把任务分解为多个'
      '子任务行，任务列保持任务标题原样；按 🔴 → 🟡 → 🟢 → 🕐 排序，'
      '同档按优先级（P0 在前）。\n\n'
      '质量自检：TL;DR 引用块与 5 个章节（状态仪表盘、执行摘要'
      '【未关闭事项/本期关闭/决策 / 需要拍板】、上期计划对比、进度明细、'
      '下期计划）全部齐备且顺序正确；每个任务至少出现在一个章节；'
      '技术术语、物料编号、缩写、测量值原样保留不得改写；每个要点只讲'
      '一个事实、不合并多事实；全报告零平铺段落；TL;DR 恰好 3 个顶层'
      '要点，"需要您"是一条具体请求或"本期无"；未关闭事项表每个'
      '未关闭任务恰好一行、按 🔴 → 🟡 → 🟢 → 🕐 排序，已完成任务只出现在'
      '本期关闭表；状态仪表盘要点格为 <br> 分隔的列表——每任务一行'
      '（加粗标题 — 一句话总结其最近的更新），行数与该项目任务数一致、'
      '禁止只写标题；进度明细每个任务=H4 标题行+"- "清单，严格一条一行，'
      '最多 5 条，本节禁止表格与 <br>，超过一周（7 天）的旧日志只以'
      '"早期背景："一句出现；技术要点完整具体、不过度压缩；'
      '下期计划只含未完成任务、每任务一行不分解、按严重度与优先级排序；'
      '报告应连贯、可在 2 分钟内扫读完毕。'
      '仅输出 Markdown 报告本身，不要额外说明或代码围栏。';

  // ────────────────────────── Markdown ──────────────────────────

  String toMarkdown(
    ReportData d, {
    ReportLanguage lang = ReportLanguage.english,
    Map<Task, String>? aiSummaries,
    Map<Task, String>? aiTitles,
    Map<String, String>? aiTerms,
    List<ReportPlanRow>? previousPlan,
  }) {
    final l = _L(lang);
    final b = StringBuffer();
    final f = DateFormat('MM-dd');
    final groups = _groupByProject(d.touchedTasks, l);
    final sorted = _sortedGroups(groups, d, l);
    final open = openTasksForPlan(d);
    final asks = _asks(d, l, aiTitles);
    final risks = _risks(d, l, aiTitles);

    b.writeln('# ${l.reportTitle(d.period)}${d.titlePrefix}');
    b.writeln(
        '**${l.period}:** ${d.rangeLabel} | **${l.prepared}:** ${DateFormat('yyyy-MM-dd').format(DateTime.now())}'
        '${d.filter.isActive ? ' | **${l.filters}:** ${d.filter.describe()}' : ''}');
    b.writeln();
    b.writeln('---');
    b.writeln();

    // TL;DR — the 30-second view for a director: what closed, what needs
    // attention, what is needed from them. Nested list: 3 top bullets only.
    b.writeln('> **${l.tldr}**');
    b.writeln('>');
    b.writeln('> - **${l.tldrClosed}**');
    if (d.completed.isEmpty) {
      b.writeln('>   - ${l.noneThisPeriod}');
    } else {
      for (final t in d.completed) {
        b.writeln(
            '>   - ${_mdEscape(_title(t, aiTitles))} (${l.doneOn(f.format(t.completedAt!))})');
      }
    }
    b.writeln('> - **${l.tldrNeedsAttention}**');
    if (risks.isEmpty) {
      b.writeln('>   - ${l.noneThisPeriod}');
    } else {
      for (final r in risks.take(3)) {
        b.writeln('>   - ${_mdEscape(r.title)} — ${_mdEscape(r.detail)}');
      }
    }
    b.writeln(
        '> - **${l.tldrNeedFromYou}:** ${asks.isEmpty ? l.noneThisPeriod : _mdEscape(asks.first.title)}');
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 1. Status Dashboard — one row per project, worst severity first,
    // open/closed counts instead of a done/total fraction.
    b.writeln('## 1. ${l.statusDashboard}');
    b.writeln();
    b.writeln('*${l.statusLegend}*');
    b.writeln();
    b.writeln(
        '| ${l.project} | ${l.status} | ${l.openClosed} | ${l.headline} |');
    b.writeln('|:-----|:------:|:--------:|:---------|');
    for (final g in sorted) {
      final rag = _ragForGroup(g.value, d, l);
      final openCount =
          g.value.where((t) => t.status != TaskStatus.completed).length;
      final done = g.value.length - openCount;
      // The Headline cell is a LIST — up to 3 task headlines, one per line
      // via <br> (rendered as a real break by the app's BrSyntax in-app and
      // as raw HTML in the exported files).
      final headlines =
          _groupHeadlines(g.value, l, aiTitles).map(_mdEscape).join('<br>');
      b.writeln(
          '| ${_term(g.key, aiTerms)} | ${rag.emoji} ${rag.label} | $openCount · $done | $headlines |');
    }
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 2. Executive Summary — three tables: open items by severity, closed
    // this period, decisions / sign-offs. Details live in §4 only.
    b.writeln('## 2. ${l.executiveSummary}');
    b.writeln();
    b.writeln('### ${l.openItemsBySeverity}');
    b.writeln();
    if (open.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      b.writeln(
          '| ${l.item} | ${l.status} | ${l.changeThisPeriod} | ${l.nextStep} | ${l.owner} | ${l.eta} |');
      b.writeln('|:-----|:------:|:------|:------|:------|:---:|');
      for (final t in open) {
        final sev = _taskSeverity(t, d, l);
        final proj = _term(_projectOf(t, l), aiTerms);
        b.writeln('| **$proj** · ${_mdEscape(_title(t, aiTitles))}'
            ' | ${sev.emoji} ${sev.label}'
            ' | ${_mdEscape(_changeCell(t, d, l))}'
            ' | ${_mdEscape(_nextStepCell(t, d, l))}'
            ' | ${l.ownerPlaceholder}'
            ' | ${_etaCell(t, d)} |');
      }
    }
    b.writeln();
    b.writeln('### ${l.closedThisPeriod}');
    b.writeln();
    if (d.completed.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      b.writeln('| ${l.item} | ${l.result} | ${l.followUp} |');
      b.writeln('|:-----|:-----|:-----|');
      for (final t in d.completed) {
        final proj = _term(_projectOf(t, l), aiTerms);
        b.writeln('| **$proj** · ${_mdEscape(_title(t, aiTitles))}'
            ' | ${_mdEscape(_closedResult(t, l))} | ${l.noFollowUp} |');
      }
    }
    b.writeln();
    b.writeln('### ${l.decisionsSignoffs}');
    if (asks.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      for (final a in asks) {
        b.writeln('- **${_mdEscape(a.title)}** — ${_mdEscape(a.detail)}');
      }
    }
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 3. Last Period's Plan vs. Actual — from the plan archived when the
    // previous period's report was generated (the DB keeps no history).
    b.writeln('## 3. ${l.lastPeriodPlan}');
    b.writeln();
    if (previousPlan == null || previousPlan.isEmpty) {
      b.writeln('_${l.noRecordedPlan}_');
    } else {
      final completedByUid = {for (final t in d.completed) t.uid: t};
      final openByUid = {for (final t in open) t.uid: t};
      b.writeln('| ${l.plannedPrevious} | ${l.due} | ${l.result} |');
      b.writeln('|:-----|:---:|:-----|');
      for (final row in previousPlan) {
        final plannedDue = row.due != null ? f.format(row.due!) : '—';
        String result;
        final c = completedByUid[row.uid];
        if (c != null && c.completedAt != null) {
          result = l.doneInPeriod(f.format(c.completedAt!));
        } else if (openByUid.containsKey(row.uid)) {
          final due = openByUid[row.uid]!.dueDate;
          result =
              due != null ? l.stillOpen(f.format(due)) : l.stillOpenNoDue;
        } else {
          result = l.noLongerTracked;
        }
        b.writeln('| ${_mdEscape(row.title)} | $plannedDue | $result |');
      }
    }
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 4. Progress Details — content-list layout; each task is an h4 header
    // bar (emoji + status + due) with one "- " item per line; project
    // groups render in the SAME order as §1, tasks worst severity first.
    b.writeln('## 4. ${l.progressDetails}');
    b.writeln('*${l.groupedByProject}*');
    b.writeln();
    for (final g in sorted) {
      b.writeln('### ${_term(g.key, aiTerms)}');
      b.writeln();
      final tasks = [...g.value]
        ..sort((x, y) {
          final r = _severityRank(_taskSeverity(x, d, l))
              .compareTo(_severityRank(_taskSeverity(y, d, l)));
          if (r != 0) return r;
          return x.priority.index.compareTo(y.priority.index);
        });
      for (final t in tasks) {
        final st = _taskStatus(t, d, l);
        final duePart =
            t.dueDate != null ? ' · ${l.dueOn(f.format(t.dueDate!))}' : '';
        b.writeln('#### ${st.emoji} ${_mdEscape(_title(t, aiTitles))}'
            ' — ${st.label}$duePart');
        for (final line in _taskDetailsLines(t, l, aiSummaries)) {
          // Strip any leading bullet glyph the AI summary may carry so the
          // list never renders doubled markers ("- • text").
          final item =
              _oneLine(line).replaceFirst(RegExp(r'^[•\-\*]\s*'), '');
          b.writeln('- $item');
        }
        b.writeln();
      }
    }
    b.writeln('---');
    b.writeln();

    // 5. Plan for Next Period — every open task (blocked/overdue included),
    // worst severity first.
    b.writeln('## 5. ${l.planForNext(d.period)}');
    b.writeln();
    if (open.isEmpty) {
      b.writeln('_${l.noPendingTasks}_');
    } else {
      b.writeln('| ${l.project} | ${l.task} | ${l.due} | ${l.priority} |');
      b.writeln('|:-----:|:-----|:---:|:--------:|');
      for (final t in open) {
        final group = _term(_projectOf(t, l), aiTerms);
        final due = t.dueDate != null ? f.format(t.dueDate!) : '—';
        b.writeln(
            '| $group | ${_mdEscape(_title(t, aiTitles))} | $due | ${t.priority.shortLabel} |');
      }
    }
    b.writeln();
    b.writeln('---');
    b.writeln(
        '_${l.generatedBy} · ${l.logEntries}: Pass ${d.entryPass} / Fail ${d.entryFail} / '
        'Blocked ${d.entryBlocked} / Note ${d.entryNote}_');
    return b.toString();
  }

  // ─────────────── Grouping & status helpers (MD + HTML) ───────────────

  /// The project a task belongs to, or the localized "General" bucket.
  String _projectOf(Task t, _L l) {
    final proj = t.project.trim();
    return proj.isEmpty ? l.generalGroup : proj;
  }

  /// Groups tasks by their [Task.project] field; tasks without a project
  /// fall into the localized "General" group.
  Map<String, List<Task>> _groupByProject(List<Task> tasks, _L l) {
    final groups = <String, List<Task>>{};
    for (final t in tasks) {
      (_groups_key(groups, _projectOf(t, l))).add(t);
    }
    return groups;
  }

  List<Task> _groups_key(Map<String, List<Task>> m, String k) => m[k] ??= [];

  bool _isOverdue(Task t, ReportData d) =>
      t.status != TaskStatus.completed &&
      t.dueDate != null &&
      t.dueDate!.isBefore(d.end);

  bool _hasEntryType(Task t, ReportData d, EntryType type) =>
      (d.logActivity[t] ?? const []).any((e) => e.type == type);

  /// Severity of a single open task — the per-row status of the Open items
  /// table, the Progress Details headers and the plan ordering:
  /// 🔴 Blocked → 🟡 At Risk → 🟢 On Track → 🕐 Planned.
  ({String emoji, String label}) _taskSeverity(
      Task t, ReportData d, _L l) {
    if (t.status == TaskStatus.blocked ||
        _hasEntryType(t, d, EntryType.blocked)) {
      return (emoji: '🔴', label: l.ragBlocked);
    }
    if (_isOverdue(t, d) || _hasEntryType(t, d, EntryType.fail)) {
      return (emoji: '🟡', label: l.atRisk);
    }
    if (t.status == TaskStatus.inProgress) {
      return (emoji: '🟢', label: l.onTrack);
    }
    return (emoji: '🕐', label: l.plannedWord);
  }

  int _severityRank(({String emoji, String label}) s) => switch (s.emoji) {
        '🔴' => 0,
        '🟡' => 1,
        '🟢' => 2,
        _ => 3,
      };

  /// Status of a task for the Progress Details header: completed tasks get
  /// 🟩 + completion date, open tasks their severity.
  ({String emoji, String label}) _taskStatus(Task t, ReportData d, _L l) {
    if (t.status == TaskStatus.completed && t.completedAt != null) {
      return (
        emoji: '🟩',
        label: l.completedDated(DateFormat('MM-dd').format(t.completedAt!)),
      );
    }
    if (t.status == TaskStatus.completed) {
      return (emoji: '🟩', label: l.completedWord);
    }
    return _taskSeverity(t, d, l);
  }

  /// RAG status of a project group = the severity of its worst open task
  /// (🔴 Blocked → 🟡 At Risk → 🟢 On Track). A group with no open tasks is
  /// 🟢 On Track.
  ({String emoji, String label}) _ragForGroup(
      List<Task> group, ReportData d, _L l) {
    var best = (emoji: '🟢', label: l.onTrack);
    var bestRank = 3;
    for (final t in group) {
      if (t.status == TaskStatus.completed) continue;
      final s = _taskSeverity(t, d, l);
      final r = _severityRank(s);
      if (r < bestRank) {
        bestRank = r;
        best = s;
      }
      if (bestRank == 0) break;
    }
    return best;
  }

  /// Display name for a task: the AI-translated title when available,
  /// otherwise the original title.
  String _title(Task t, Map<Task, String>? aiTitles) {
    final tr = aiTitles?[t];
    return (tr != null && tr.trim().isNotEmpty) ? tr : t.title;
  }

  /// Headline LIST for a dashboard cell (v1.5.6): up to 3 of the group's
  /// most significant tasks — completed first, then in-progress — one per
  /// line; a quiet placeholder when the group has neither.
  List<String> _groupHeadlines(
      List<Task> group, _L l, Map<Task, String>? aiTitles) {
    final out = <String>[];
    for (final t in group.where((t) => t.status == TaskStatus.completed)) {
      out.add(_title(t, aiTitles));
    }
    for (final t in group.where((t) => t.status == TaskStatus.inProgress)) {
      out.add(_title(t, aiTitles));
    }
    if (out.isEmpty) return [l.noActivity];
    return out.take(3).toList();
  }

  /// Translates a project name / tag via the AI-produced [aiTerms] map,
  /// falling back to the raw value when no translation is available. This
  /// is what keeps Chinese project names and tags out of English reports.
  String _term(String raw, Map<String, String>? aiTerms) {
    final tr = aiTerms?[raw];
    return (tr != null && tr.trim().isNotEmpty) ? tr : raw;
  }

  /// "Change this period" cell of the Open items table: the in-period log
  /// entry count plus a one-line latest entry; "New:" when the task started
  /// inside the period; "No change" when nothing was logged.
  String _changeCell(Task t, ReportData d, _L l) {
    final entries = d.logActivity[t] ?? const <ExecutionEntry>[];
    String change = l.noChange;
    if (entries.isNotEmpty) {
      final last = entries.last;
      final short = _short(last.content);
      change = '${l.logEntryCount(entries.length)} · '
          '${l.entryTypeLabel(last.type)}: $short';
    }
    final started =
        t.startedAt != null && !t.startedAt!.isBefore(d.start) && t.startedAt!.isBefore(d.end);
    if (started) change = 'New: $change';
    return change;
  }

  /// "Next step" cell: the latest blocked entry's content as the unblock
  /// action; deterministically "—" otherwise (the AI path fills this from
  /// the logs).
  String _nextStepCell(Task t, ReportData d, _L l) {
    final entries = d.logActivity[t] ?? const <ExecutionEntry>[];
    final blocked =
        entries.where((e) => e.type == EntryType.blocked).toList();
    if (blocked.isNotEmpty) return l.unblockPrefix(_short(blocked.last.content));
    return l.noNextStep;
  }

  /// ETA cell: the due date, ⚠️-marked when already overdue at period end.
  String _etaCell(Task t, ReportData d) {
    if (t.dueDate == null) return '—';
    final f = DateFormat('MM-dd').format(t.dueDate!);
    return _isOverdue(t, d) ? '$f ⚠️' : f;
  }

  /// Result cell of the Closed-this-period table: completion date plus the
  /// sub-step ratio when the task has sub-steps.
  String _closedResult(Task t, _L l) {
    final parts = <String>[
      if (t.completedAt != null)
        l.doneOn(DateFormat('MM-dd').format(t.completedAt!)),
    ];
    if (t.subSteps.isNotEmpty) {
      parts.add(l.subStepsCount(
          t.subSteps.where((s) => s.completed).length, t.subSteps.length));
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  String _short(String s) {
    var t = _oneLine(s);
    if (t.length > 100) t = '${t.substring(0, 100)}…';
    return t;
  }

  /// Dashboard / details group ordering: worst severity first, then by
  /// project name. Details groups render in the SAME order as §1.
  List<MapEntry<String, List<Task>>> _sortedGroups(
      Map<String, List<Task>> groups, ReportData d, _L l) {
    int rank(List<Task> ts) =>
        _severityRank(_ragForGroup(ts, d, l));
    return groups.entries.toList()
      ..sort((a, b) {
        final r = rank(a.value).compareTo(rank(b.value));
        if (r != 0) return r;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
  }

  /// DETAILS cell content as a list of lines: the AI summary bullets
  /// when available (applies to completed tasks too — their summaries
  /// describe what was accomplished), otherwise a single compact
  /// heuristic line (sub-step progress / completion / due date).
  List<String> _taskDetailsLines(Task t, _L l, Map<Task, String>? aiSummaries) {
    final ai = aiSummaries?[t];
    if (ai != null && ai.trim().isNotEmpty) {
      final lines = ai
          .split('\n')
          .map((s) => _oneLine(s))
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines;
    }
    final parts = <String>[];
    final done = t.subSteps.where((s) => s.completed).length;
    if (t.subSteps.isNotEmpty) {
      parts.add(l.subStepsCount(done, t.subSteps.length));
    }
    if (t.status == TaskStatus.completed && t.completedAt != null) {
      parts.add(l.doneOn(DateFormat('MM-dd').format(t.completedAt!)));
    }
    if (t.dueDate != null) {
      parts.add(l.dueOn(DateFormat('MM-dd').format(t.dueDate!)));
    }
    return [parts.isEmpty ? '—' : parts.join(' · ')];
  }

  /// Risks for the TL;DR "Needs attention" bullets: blocked tasks FIRST
  /// (🔴 waiting on an external party), then overdue ones (🟡) — matching
  /// the AI prompt's "blocked first, then overdue" ordering.
  List<({String title, String detail})> _risks(
      ReportData d, _L l, Map<Task, String>? aiTitles) {
    final out = <({String title, String detail})>[];
    for (final entry in d.logActivity.entries) {
      for (final e in entry.value.where((e) => e.type == EntryType.blocked)) {
        out.add((
          title: _title(entry.key, aiTitles),
          detail: l.blockedDetail(_oneLine(e.content)),
        ));
      }
    }
    for (final t in d.overdue) {
      out.add((
        title: _title(t, aiTitles),
        detail: l.overdueDetail(
            DateFormat('MM-dd').format(t.dueDate!), t.priority.shortLabel),
      ));
    }
    return out;
  }

  List<({String title, String detail})> _asks(
      ReportData d, _L l, Map<Task, String>? aiTitles) {
    final out = <({String title, String detail})>[];
    for (final entry in d.logActivity.entries) {
      for (final e in entry.value.where((e) => e.type == EntryType.blocked)) {
        out.add((
          title: _title(entry.key, aiTitles),
          detail: l.needsDecision(_oneLine(e.content)),
        ));
      }
    }
    return out;
  }

  String _mdEscape(String s) => s.replaceAll('|', '\\|').replaceAll('\n', ' ');

  String _oneLine(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Generous cap: full AI summary bullets must reach the Details cell
    // uncut; 300 only guards against pathological model output.
    if (t.length > 300) t = '${t.substring(0, 300)}…';
    return t;
  }

  /// Escapes every literal `~` before the markdown→HTML conversion. The
  /// markdown package's strikethrough syntax matches SINGLE tildes too
  /// (`~text~`), so engineering text like "Vout ~ 5V … temp ~ stable"
  /// turned everything between two tildes into a strikethrough run
  /// (v1.5.9 user report). Reports never legitimately use ~~strikethrough~~
  /// — the approx sign is what tildes mean here — so the escape is safe.
  /// `&#126;` renders as a plain `~` in every browser and mail client.
  static String _escapeTildesForHtml(String markdown) =>
      markdown.replaceAll('~', '&#126;');

  /// Prepares user note/description Markdown for safe HTML export
  /// (v1.13.2). The markdown package passes raw HTML through verbatim —
  /// `<script>`, `<img onerror=…>`, `<div onclick=…>` would all execute in
  /// the exported document. Every tag is therefore entity-escaped EXCEPT
  /// the app's own rich-text vocabulary: `<br>` and `<font color/size>`
  /// (attributes strictly validated and rebuilt). Code fences and inline
  /// code spans are left untouched — the package escapes their content
  /// itself, and pre-escaping would double-escape it. Tildes are escaped
  /// only OUTSIDE code for the same reason (v1.5.9 strikethrough rule).
  static String _sanitizeNoteMarkdown(String source) {
    var s = _normalizeMultilineTableRows(source);
    final re = RegExp(
        r'(```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`)|(</?[a-zA-Z][^>]*>)');
    final b = StringBuffer();
    var last = 0;
    for (final m in re.allMatches(s)) {
      b.write(_escapeTildesForHtml(s.substring(last, m.start)));
      if (m.group(1) != null) {
        b.write(m.group(1)); // code span/fence — the package escapes it
      } else {
        b.write(_escapeRawTag(m.group(2)!));
      }
      last = m.end;
    }
    b.write(_escapeTildesForHtml(s.substring(last)));
    return b.toString();
  }

  /// Entity-escapes a raw HTML tag unless it is `<br>` or a `<font>` carrying
  /// only valid color/size attributes (the only raw HTML the app renders).
  static String _escapeRawTag(String tag) {
    if (RegExp(r'^<br\s*/?>$', caseSensitive: false).hasMatch(tag)) return tag;
    if (RegExp(r'^</font\s*>$', caseSensitive: false).hasMatch(tag)) {
      return '</font>';
    }
    final open =
        RegExp(r'^<font\s+([^>]*?)\s*>$', caseSensitive: false).firstMatch(tag);
    if (open != null) {
      final attrs = <String>[];
      final attrRe = RegExp(
          r'''([a-zA-Z]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''');
      for (final a in attrRe.allMatches(open.group(1)!)) {
        final name = a.group(1)!.toLowerCase();
        final value = a.group(3) ?? a.group(4) ?? a.group(5) ?? '';
        if (name == 'color' &&
            RegExp(r'^(#[0-9a-fA-F]{3,8}|[a-zA-Z]{3,20})$').hasMatch(value)) {
          attrs.add('color="$value"');
        } else if (name == 'size' && RegExp(r'^[0-9]{1,2}$').hasMatch(value)) {
          attrs.add('size="$value"');
        }
      }
      if (attrs.isNotEmpty) return '<font ${attrs.join(' ')}>';
    }
    return tag
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Neutralizes dangerous URL schemes in markdown-generated links/images
  /// (the package passes `[x](javascript:…)` through untouched). Relative
  /// URLs and anchors stay; `data:` is allowed for images only.
  static String _sanitizeUrls(String html) {
    final re = RegExp(r'<(a|img)(\s[^>]*?)?\s(href|src)="([^"]*)"',
        caseSensitive: false);
    return html.replaceAllMapped(re, (m) {
      final tag = m.group(1)!.toLowerCase();
      final attr = m.group(3)!.toLowerCase();
      // Browsers strip tab/LF/CR inside URLs — normalize before checking.
      final url = m.group(4)!.replaceAll(RegExp(r'[\s\x00-\x1F]'), '');
      final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):')
          .firstMatch(url)
          ?.group(1)
          ?.toLowerCase();
      final allowed = tag == 'a'
          ? const {'http', 'https', 'mailto', 'file', 'ftp'}
          : const {'http', 'https', 'file'};
      final ok = scheme == null ||
          allowed.contains(scheme) ||
          (tag == 'img' && url.startsWith('data:image/'));
      if (ok) return m.group(0)!;
      return '<${m.group(1)}${m.group(2) ?? ''} $attr="#"';
    });
  }

  /// Converts a Markdown string (typically the user-edited report source)
  /// into a standalone, styled HTML document.
  /// Unlike [toMarkdown]-based exports — which share the SAME Markdown —
  /// this renders whatever Markdown it is given, so user edits made in the
  /// Reports preview are faithfully preserved on export. Tables and inline
  /// `<br>` produced by [toMarkdown] are handled via the GitHub extension
  /// set.
  String markdownToStyledHtml(String markdown, {String? title}) {
    var body = md.markdownToHtml(
      _escapeTildesForHtml(_normalizeMultilineTableRows(markdown)),
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    // Per-column wrap policy: long-text columns may break anywhere on
    // narrow screens, short columns keep words intact.
    body = _applyTableColumnPolicy(body);
    body = _wrapTablesInScrollDivs(body);
    final docTitle =
        (title == null || title.isEmpty) ? 'TaskFlow Report' : title;
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$docTitle</title>
<style>
  :root { --primary:#6366F1; --border:#E2E8F0; --muted:#64748B; }
  * { box-sizing:border-box; }
  body { font-family:-apple-system,"Segoe UI",Roboto,"Noto Sans SC","Microsoft YaHei",sans-serif;
         margin:0; background:#F8FAFC; color:#1E293B; }
  .wrap { max-width:1000px; margin:0 auto; padding:32px 24px 64px; }
  h1 { font-size:24px; margin:0 0 4px; }
  h2 { font-size:16px; margin:28px 0 10px; border-bottom:1px solid var(--border);
       padding-bottom:6px; }
  h3 { font-size:13px; margin:18px 0 8px; color:#334155; }
  h4 { font-size:13px; margin:20px 0 8px; padding:6px 10px;
       background:#F1F5F9; border-left:3px solid #94A3B8; color:#1E293B;
       line-height:1.5; }
  p, li { font-size:13px; line-height:1.55; }
  .table-scroll { overflow-x:auto; }
  table { width:100%; border-collapse:collapse; background:#fff;
          border:1px solid var(--border); border-radius:12px; overflow:hidden;
          margin-bottom:8px; }
  th { font-size:11px; text-transform:uppercase; letter-spacing:.5px;
       color:var(--muted); padding:10px 14px; background:#F1F5F9;
       vertical-align:bottom; overflow-wrap:break-word; }
  td { padding:10px 14px; font-size:13px; border-top:1px solid var(--border);
       vertical-align:top; overflow-wrap:break-word; }
  blockquote { border-left:3px solid var(--primary); margin:0 0 12px;
               padding:10px 14px; color:#1E293B; background:#EEF2FF;
               border-radius:0 8px 8px 0; }
  code { background:#F1F5F9; border-radius:4px; padding:1px 5px;
         font-size:12px; }
  pre { background:#F1F5F9; border-radius:8px; padding:12px; overflow:auto; }
  hr { border:none; border-top:1px solid var(--border); margin:24px 0; }
</style>
</head>
<body>
<div class="wrap">
$body
</div>
</body>
</html>''';
  }

  /// Converts the report Markdown (the SAME source as Export.md / Export.html)
  /// into a standalone Gmail-safe HTML document: table-based page layout and
  /// pure inline styles (mail clients strip <style> blocks), 6-digit hex
  /// colors. Content is identical to the other exports — only the styling is
  /// adapted for mail clients.
  String markdownToEmailHtml(String markdown, {String? title}) {
    var body = md.markdownToHtml(
      _escapeTildesForHtml(_normalizeMultilineTableRows(markdown)),
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    body = _inlineEmailStyles(body);
    // Runs AFTER the base styles so `overflow-wrap:anywhere` is appended to
    // the existing inline style attributes of long-text columns.
    body = _applyTableColumnPolicy(body);
    final docTitle =
        (title == null || title.isEmpty) ? 'TaskFlow Report' : title;
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$docTitle</title>
</head>
<body style="margin:0;padding:0;background-color:#ffffff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,'Noto Sans SC','Microsoft YaHei',sans-serif;color:#1E293B;">
<table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color:#ffffff;margin:0;padding:20px 0;">
<tr>
<td align="center">
<table width="100%" border="0" cellspacing="0" cellpadding="0" style="width:100%;max-width:1000px;padding:0 16px;text-align:left;border-collapse:collapse;">
<tr>
<td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,'Noto Sans SC','Microsoft YaHei',sans-serif;">
$body
</td>
</tr>
</table>
</td>
</tr>
</table>
</body>
</html>''';
  }

  /// AI models sometimes place real newlines inside a pipe-table cell
  /// (e.g. multi-bullet Details columns). A markdown table row must be a
  /// single line, otherwise every continuation line becomes a broken row
  /// with empty cells in the exported HTML. Merge those continuation lines
  /// into the previous cell separated by `<br>` — restoring the classic
  /// single-row-per-task export layout.
  ///
  /// v1.5.3: delegates to the shared implementation in table_support.dart
  /// that the in-app renderers use too (single source of truth, pitfall
  /// 8.10).
  static String _normalizeMultilineTableRows(String markdown) =>
      table_support.normalizeMultilineTableRows(markdown, separator: '<br>');

  /// Columns whose longest cell exceeds this many characters may be
  /// squeezed hard on narrow screens (`overflow-wrap:anywhere`); shorter
  /// columns keep `break-word` so words like "Foxlink" or "Obelisk" stay
  /// intact and prop up the column's min-content width.
  static const _anywhereMinChars = 30;

  /// Applies the per-column wrap policy to every table: long-text columns
  /// get `overflow-wrap:anywhere` (they can absorb any compression, which
  /// keeps the page free of horizontal overflow down to ~375px), short
  /// columns keep the `break-word` set by the base styles. Column alignment
  /// itself is carried by the markdown `align` attributes — no CSS override.
  static String _applyTableColumnPolicy(String html) {
    final tableRe =
        RegExp(r'<table(\s[^>]*)?>([\s\S]*?)</table>', caseSensitive: false);
    final rowRe =
        RegExp(r'<tr(\s[^>]*)?>[\s\S]*?</tr>', caseSensitive: false);
    final cellRe = RegExp(r'<(t[hd])(\s[^>]*)?>', caseSensitive: false);
    final cellTextRe =
        RegExp(r'<t[hd](\s[^>]*)?>([\s\S]*?)</t[hd]>', caseSensitive: false);
    return html.replaceAllMapped(tableRe, (m) {
      final table = m.group(0)!;
      final rows = rowRe.allMatches(table).toList();
      if (rows.isEmpty) return table;
      final ncols = rows
          .map((r) => cellRe.allMatches(r.group(0)!).length)
          .reduce((a, b) => a > b ? a : b);
      // Longest cell text per column.
      final longest = List.filled(ncols, 0);
      for (final r in rows) {
        var i = 0;
        for (final cm in cellTextRe.allMatches(r.group(0)!)) {
          if (i >= ncols) break;
          final text =
              (cm.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
          if (text.length > longest[i]) longest[i] = text.length;
          i++;
        }
      }
      // Rewrite every row, appending `overflow-wrap:anywhere` to squeezed
      // columns' cells.
      return table.replaceAllMapped(rowRe, (rm) {
        var i = 0;
        return rm.group(0)!.replaceAllMapped(cellRe, (cm) {
          final idx = i++;
          if (idx >= ncols || longest[idx] <= _anywhereMinChars) {
            return cm.group(0)!;
          }
          return '<${cm.group(1)}${_appendStyleAttr(cm.group(2) ?? '', 'overflow-wrap:anywhere;')}>';
        });
      });
    });
  }

  /// Wraps each table in a horizontal-scroll container so a pathological
  /// user-edited table can never push the page wider than the viewport.
  static String _wrapTablesInScrollDivs(String html) => html
      .replaceAll('<table', '<div class="table-scroll">\n<table')
      .replaceAll('</table>', '</table>\n</div>');

  /// Appends [style] to the cells' existing `style` attribute (or adds one).
  static String _appendStyleAttr(String attrs, String style) {
    final existing = RegExp('style="([^"]*)"').firstMatch(attrs);
    if (existing != null) {
      final current = existing.group(1)!;
      final sep = current.endsWith(';') ? '' : ';';
      return attrs.replaceFirst(
          'style="$current"', 'style="$current$sep$style"');
    }
    return '$attrs style="$style"';
  }

  /// Injects paste-proof inline styles into the block-level tags produced by
  /// [md.markdownToHtml] so the report renders correctly in Gmail / Outlook
  /// (which strip <style> blocks). Mirrors the visual language of the browser
  /// export. Existing style attributes are preserved and merged. Column
  /// alignment is NOT overridden — the markdown `align` attributes govern.
  static String _inlineEmailStyles(String html) {
    const styles = <String, String>{
      'h1': 'font-size:24px;font-weight:bold;margin:0 0 4px 0;color:#1E293B;',
      'h2': 'font-size:16px;font-weight:bold;margin:28px 0 10px 0;'
          'border-bottom:1px solid #E2E8F0;padding-bottom:6px;color:#1E293B;',
      'h3': 'font-size:13px;font-weight:bold;margin:16px 0 8px 0;'
          'color:#334155;',
      'h4': 'font-size:13px;font-weight:bold;margin:20px 0 8px 0;'
          'padding:6px 10px;background-color:#F1F5F9;'
          'border-left:3px solid #94A3B8;color:#1E293B;line-height:1.5;',
      'p': 'font-size:13px;line-height:1.55;margin:0 0 8px 0;',
      'table': 'width:100%;border-collapse:collapse;border:1px solid #E2E8F0;'
          'margin:0 0 12px 0;',
      'th': 'font-size:11px;text-transform:uppercase;letter-spacing:.5px;'
          'color:#64748B;padding:10px 14px;background-color:#F1F5F9;'
          'border:1px solid #E2E8F0;vertical-align:bottom;'
          'overflow-wrap:break-word;',
      'td': 'padding:10px 14px;font-size:13px;border:1px solid #E2E8F0;'
          'vertical-align:top;line-height:1.5;overflow-wrap:break-word;',
      'ul': 'margin:6px 0;padding-left:20px;',
      'ol': 'margin:6px 0;padding-left:20px;',
      'li': 'font-size:13px;line-height:1.55;margin-bottom:4px;',
      'blockquote': 'border-left:3px solid #6366F1;margin:0 0 12px 0;'
          'padding:10px 14px;color:#1E293B;background-color:#EEF2FF;'
          'border-radius:0 8px 8px 0;',
      'code': 'background-color:#F1F5F9;padding:1px 5px;font-size:12px;',
      'pre': 'background-color:#F1F5F9;padding:12px;font-size:12px;'
          'margin:0 0 12px 0;',
    };
    var out = html;
    styles.forEach((tag, style) {
      out = _injectTagStyle(out, tag, style);
    });
    // Markdown <hr /> — restyle as a thin ruled line.
    out = out.replaceAllMapped(
        RegExp(r'<hr\s*/?>', caseSensitive: false),
        (_) =>
            '<hr style="border:none;border-top:1px solid #E2E8F0;margin:24px 0;">');
    return out;
  }

  /// Adds (or merges) a `style` attribute on every occurrence of `<tag …>`.
  static String _injectTagStyle(String html, String tag, String style) {
    final re = RegExp('<$tag(\\s[^>]*)?>', caseSensitive: false);
    return html.replaceAllMapped(re, (m) {
      final full = m.group(0)!;
      final attrs = m.group(1) ?? '';
      final existing = RegExp('style="([^"]*)"').firstMatch(attrs);
      if (existing != null) {
        return full.replaceFirst('style="${existing.group(1)}"',
            'style="$style;${existing.group(1)}"');
      }
      return '<$tag$attrs style="$style">';
    });
  }

  /// Test accessors for the email-HTML post-processing helpers (the risky
  /// regex manipulation), so they can be asserted without a repository.
  @visibleForTesting
  static String applyTableColumnPolicyForTest(String html) =>
      _applyTableColumnPolicy(html);

  @visibleForTesting
  static String inlineEmailStylesForTest(String html) =>
      _inlineEmailStyles(html);

  // ───────────────── Task notes export (raw, no AI) ─────────────────

  /// Every task that appears in the report — touched tasks plus overdue
  /// tasks that only show up in Risks/Blockers — de-duplicated by identity.
  /// Exactly the set Generate Report summarizes, so the notes export and
  /// the report always cover the same tasks.
  List<Task> _notesTasks(ReportData d) {
    final seen = <Task>{};
    final out = <Task>[];
    for (final t in [...d.touchedTasks, ...d.overdue]) {
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  bool _entryInPeriod(ExecutionEntry e, ReportData d) =>
      !e.timestamp.isBefore(d.start) && e.timestamp.isBefore(d.end);

  /// Task-status glyph for the notes export — mirrors the app-wide
  /// vocabulary in emoji_glyphs.dart (the data layer must not import
  /// presentation, so the mapping is duplicated here).
  String _notesStatusGlyph(Task t) {
    switch (t.status) {
      case TaskStatus.planned:
        return '🗓';
      case TaskStatus.inProgress:
        return '🚧';
      case TaskStatus.completed:
        return '✅';
      case TaskStatus.archived:
        return '📦';
      case TaskStatus.blocked:
        return '⛔';
    }
  }

  /// Entry-type glyph — same vocabulary as emoji_glyphs.dart.
  String _notesEntryGlyph(EntryType type) {
    switch (type) {
      case EntryType.note:
        return '📝';
      case EntryType.pass:
        return '✅';
      case EntryType.fail:
        return '❌';
      case EntryType.blocked:
        return '⛔';
    }
  }

  /// Nesting depth of a sub-step derived from its parentUid chain — the
  /// stored [SubStep.depth] is an untrusted cache (normalizeSubStepDepths).
  int _subStepDepth(List<SubStep> steps, SubStep s) {
    final byUid = {for (final x in steps) x.uid: x};
    final visiting = <String>{s.uid};
    var depth = 0;
    var cur = s;
    while (cur.parentUid != null &&
        byUid.containsKey(cur.parentUid) &&
        visiting.add(cur.parentUid!)) {
      depth++;
      cur = byUid[cur.parentUid]!;
    }
    return depth;
  }

  /// Structured, lossless Markdown export of the report's tasks and ALL
  /// their notes (v1.13.2): grouped by project, each task carries its
  /// metadata, description, sub-steps and its FULL execution log in
  /// chronological order; entries inside the report period are marked.
  /// No AI is involved — note content is copied verbatim.
  String tasksNotesToMarkdown(
    ReportData d, {
    ReportLanguage lang = ReportLanguage.english,
  }) {
    final l = _L(lang);
    final tasks = _notesTasks(d);
    final groups = _groupByProject(tasks, l);
    final f = DateFormat('yyyy-MM-dd');
    final ft = DateFormat('yyyy-MM-dd HH:mm');
    final b = StringBuffer();

    var totalNotes = 0, inPeriodNotes = 0;
    for (final t in tasks) {
      for (final e in t.executionLog) {
        totalNotes++;
        if (_entryInPeriod(e, d)) inPeriodNotes++;
      }
    }
    final done = tasks.where((t) => t.status == TaskStatus.completed).length;

    b.writeln('# ${l.notesTitle}${d.titlePrefix}');
    b.writeln(
        '**${l.period}:** ${d.rangeLabel} | **${l.prepared}:** ${f.format(DateTime.now())}'
        '${d.filter.isActive ? ' | **${l.filters}:** ${d.filter.describe()}' : ''}');
    b.writeln();
    b.writeln('> ${l.notesStats(tasks.length, totalNotes, inPeriodNotes, done)}');
    b.writeln();
    b.writeln('---');
    b.writeln();

    if (tasks.isEmpty) {
      b.writeln('_${l.noTasksInRange}_');
      return b.toString();
    }

    for (final g in groups.entries) {
      b.writeln('## ${g.key}');
      b.writeln();
      for (final t in g.value) {
        b.writeln('### ${_notesStatusGlyph(t)} ${t.title}');
        b.writeln();
        b.writeln([
          '**${l.status}:** ${l.statusLabel(t.status)}',
          '**${l.priority}:** ${t.priority.shortLabel}',
          if (t.tags.isNotEmpty)
            '**${l.tagsLabel}:** ${t.tags.map((x) => '#$x').join(' ')}',
        ].join(' · '));
        b.writeln([
          '**${l.createdOn}:** ${f.format(t.createdAt)}',
          if (t.dueDate != null) '**${l.due}:** ${f.format(t.dueDate!)}',
          if (t.startedAt != null) '**${l.startedOn}:** ${f.format(t.startedAt!)}',
          if (t.completedAt != null)
            '**${l.completedOn}:** ${f.format(t.completedAt!)}',
        ].join(' · '));
        b.writeln();

        final desc = t.description?.trim();
        if (desc != null && desc.isNotEmpty) {
          b.writeln('**${l.descriptionLabel}**');
          b.writeln();
          b.writeln(desc);
          b.writeln();
        }

        if (t.subSteps.isNotEmpty) {
          final ordered = subStepsInDisplayOrder(t.subSteps);
          final ssDone = ordered.where((s) => s.completed).length;
          b.writeln('**${l.subStepsLabel} ($ssDone/${ordered.length})**');
          b.writeln();
          for (final s in ordered) {
            final indent = '  ' * _subStepDepth(t.subSteps, s);
            b.writeln('$indent- [${s.completed ? 'x' : ' '}] ${s.title}');
          }
          b.writeln();
        }

        final entries = [...t.executionLog]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final inPeriod = entries.where((e) => _entryInPeriod(e, d)).length;
        b.writeln(
            '**${l.executionLogLabel} — ${l.logCount(entries.length, inPeriod)}**');
        b.writeln();
        if (entries.isEmpty) {
          b.writeln('_${l.noNotes}_');
          b.writeln();
        }
        for (final e in entries) {
          b.writeln(
              '**${_notesEntryGlyph(e.type)} ${ft.format(e.timestamp)} · ${l.entryTypeLabel(e.type)}**'
              '${_entryInPeriod(e, d) ? ' _${l.inPeriodMark}_' : ''}');
          b.writeln();
          final content = e.content.trim();
          if (content.isNotEmpty) {
            b.writeln(content);
            b.writeln();
          }
          for (final a in e.attachments) {
            if (a.type == AttachmentType.image) {
              b.writeln('![${a.name}](${AttachmentService.resolvePathSync(a.path)})');
            } else {
              b.writeln('📎 ${a.name} (${AttachmentService.formatSize(a.size)})');
            }
          }
          if (e.attachments.isNotEmpty) b.writeln();
        }
        b.writeln('---');
        b.writeln();
      }
    }
    b.writeln(
        '_${l.generatedBy} · ${l.notesStats(tasks.length, totalNotes, inPeriodNotes, done)}_');
    return b.toString();
  }

  /// MIME type for an embedded attachment image, by file extension.
  static String _imageMime(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      case '.webp':
        return 'image/webp';
      case '.ico':
        return 'image/x-icon';
      case '.tif':
      case '.tiff':
        return 'image/tiff';
      default:
        return 'image/png';
    }
  }

  /// Beautiful standalone HTML export of the report's tasks and ALL their
  /// notes (v1.13.2) — the raw-data counterpart of [toHtml]: a table of
  /// contents, per-project sections, one card per task (metadata pills,
  /// description, sub-step checklist) and a chronological note timeline
  /// with type pills; in-period entries are highlighted. Note content is
  /// rendered as Markdown; images are embedded as base64 data URIs (each
  /// ≤2MB, ≤20MB per document) so the file is fully self-contained.
  Future<String> tasksNotesToHtml(
    ReportData d, {
    ReportLanguage lang = ReportLanguage.english,
  }) async {
    final l = _L(lang);
    final tasks = _notesTasks(d);
    final groups = _groupByProject(tasks, l);
    final f = DateFormat('yyyy-MM-dd');
    final ft = DateFormat('yyyy-MM-dd HH:mm');

    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    // Note/description Markdown → HTML. Same pipeline as the report
    // exports: multiline table cells normalized (8.10), tildes escaped so
    // engineering "~" text never becomes strikethrough (v1.5.9). Unlike
    // the AI report source, notes are arbitrary user content — the
    // markdown package passes raw HTML through VERBATIM (block AND
    // inline), so [_sanitizeNoteMarkdown] escapes every tag outside the
    // app's own rich-text vocabulary before conversion, and
    // [_sanitizeUrls] neutralizes javascript: link destinations after it.
    String renderMd(String source) => _sanitizeUrls(md.markdownToHtml(
          _sanitizeNoteMarkdown(source),
          extensionSet: md.ExtensionSet.gitHubWeb,
        ));

    // Pre-read embeddable images (bounded so a huge attachment history
    // cannot blow up the document): ≤2MB each, ≤20MB total. Anything
    // skipped falls back to a name chip.
    const maxImageBytes = 2 * 1024 * 1024;
    const maxTotalBytes = 20 * 1024 * 1024;
    final images = <String, String>{}; // attachment uid -> data URI
    var embeddedBytes = 0;
    for (final t in tasks) {
      for (final e in t.executionLog) {
        for (final a in e.attachments) {
          if (a.type != AttachmentType.image) continue;
          final file = File(AttachmentService.resolvePathSync(a.path));
          if (!file.existsSync()) continue;
          final len = file.lengthSync();
          if (len > maxImageBytes || embeddedBytes + len > maxTotalBytes) {
            continue;
          }
          try {
            final bytes = await file.readAsBytes();
            images[a.uid] =
                'data:${_imageMime(a.name)};base64,${base64Encode(bytes)}';
            embeddedBytes += bytes.length;
          } catch (_) {
            // Unreadable file — the name chip fallback covers it.
          }
        }
      }
    }

    var totalNotes = 0, inPeriodNotes = 0;
    for (final t in tasks) {
      for (final e in t.executionLog) {
        totalNotes++;
        if (_entryInPeriod(e, d)) inPeriodNotes++;
      }
    }
    final done = tasks.where((t) => t.status == TaskStatus.completed).length;

    String pill(String text, String bg, String fg) =>
        '<span class="pill" style="background:$bg;color:$fg;">$text</span>';

    ({String bg, String fg}) statusColors(TaskStatus s) {
      switch (s) {
        case TaskStatus.completed:
          return (bg: '#F0FDF4', fg: '#16A34A');
        case TaskStatus.inProgress:
          return (bg: '#EFF6FF', fg: '#2563EB');
        case TaskStatus.blocked:
          return (bg: '#FEF2F2', fg: '#DC2626');
        case TaskStatus.planned:
        case TaskStatus.archived:
          return (bg: '#EEF2FF', fg: '#4F46E5');
      }
    }

    ({String bg, String fg}) priorityColors(Priority pr) {
      switch (pr) {
        case Priority.p0Critical:
          return (bg: '#FEF2F2', fg: '#DC2626');
        case Priority.p1High:
          return (bg: '#FFFBEB', fg: '#D97706');
        case Priority.p2Medium:
          return (bg: '#EFF6FF', fg: '#2563EB');
        case Priority.p3Low:
          return (bg: '#F1F5F9', fg: '#64748B');
      }
    }

    ({String bg, String fg}) entryColors(EntryType ty) {
      switch (ty) {
        case EntryType.pass:
          return (bg: '#F0FDF4', fg: '#16A34A');
        case EntryType.fail:
          return (bg: '#FEF2F2', fg: '#DC2626');
        case EntryType.blocked:
          return (bg: '#FFFBEB', fg: '#D97706');
        case EntryType.note:
          return (bg: '#F1F5F9', fg: '#475569');
      }
    }

    String attachmentsHtml(ExecutionEntry e) {
      if (e.attachments.isEmpty) return '';
      final out = StringBuffer();
      for (final a in e.attachments) {
        final uri = images[a.uid];
        if (uri != null) {
          out.write('<img src="$uri" alt="${esc(a.name)}" style="max-width:100%;'
              'border-radius:8px;margin:6px 0;display:block;">');
        } else {
          final icon = a.type == AttachmentType.image ? '🖼' : '📎';
          out.write('<span class="att">$icon ${esc(a.name)} '
              '(${AttachmentService.formatSize(a.size)})</span>');
        }
      }
      return out.toString();
    }

    final htmlLang = lang == ReportLanguage.chinese ? 'zh-CN' : 'en';
    final title = '${esc(l.notesTitle)}${esc(d.titlePrefix)}';
    final b = StringBuffer();
    b.write('''<!DOCTYPE html>
<html lang="$htmlLang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  :root { --primary:#6366F1; --border:#E2E8F0; --muted:#64748B; }
  * { box-sizing:border-box; }
  body { font-family:-apple-system,"Segoe UI",Roboto,"Noto Sans SC","Microsoft YaHei",sans-serif;
         margin:0; background:#F8FAFC; color:#1E293B; }
  .wrap { max-width:1000px; margin:0 auto; padding:32px 24px 64px; }
  h1 { font-size:24px; margin:0 0 4px; }
  .meta { color:var(--muted); font-size:13px; margin-bottom:16px; }
  .stats { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:24px; }
  .stat { background:#fff; border:1px solid var(--border); border-radius:10px;
          padding:8px 16px; font-size:11.5px; color:var(--muted); }
  .stat b { display:block; font-size:18px; color:#1E293B; margin-bottom:2px; }
  h2 { font-size:16px; margin:28px 0 12px; border-bottom:1px solid var(--border);
       padding-bottom:6px; }
  .toc { background:#fff; border:1px solid var(--border); border-radius:12px;
         padding:14px 18px; margin-bottom:8px; }
  .toc-title { font-size:11px; text-transform:uppercase; letter-spacing:.5px;
               color:var(--muted); font-weight:700; margin-bottom:6px; }
  .toc-project { font-weight:700; font-size:12.5px; color:var(--primary);
                 margin:8px 0 4px; }
  .toc ul { margin:0; padding-left:18px; }
  .toc li { margin:2px 0; font-size:12.5px; }
  .toc a { color:#334155; text-decoration:none; }
  .toc a:hover { color:var(--primary); text-decoration:underline; }
  .toc-count { color:var(--muted); font-size:11.5px; }
  .task { background:#fff; border:1px solid var(--border); border-radius:12px;
          padding:18px 20px; margin-bottom:14px; }
  .task-head { display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
  .task-title { font-size:15px; font-weight:700; margin:0; }
  .pill { display:inline-block; padding:2px 10px; border-radius:999px;
          font-size:11px; font-weight:700; white-space:nowrap; }
  .task-meta { color:var(--muted); font-size:12px; margin-top:8px; }
  .section-label { font-size:11px; text-transform:uppercase; letter-spacing:.5px;
                   color:var(--muted); font-weight:700; margin:14px 0 6px; }
  .desc { font-size:13px; line-height:1.55; background:#F8FAFC;
          border-radius:8px; padding:10px 14px; }
  .desc p { margin:0 0 6px; }
  .steps { margin:0; padding-left:4px; list-style:none; font-size:13px; }
  .steps li { margin:3px 0; }
  .steps .done { color:var(--muted); text-decoration:line-through; }
  .entry { padding:10px 12px; border-radius:8px; margin-bottom:6px;
           background:#F8FAFC; }
  .entry.in-period { background:#EEF2FF; border-left:3px solid var(--primary); }
  .entry-head { display:flex; align-items:center; gap:8px; flex-wrap:wrap;
                margin-bottom:6px; }
  .entry-time { font-size:12px; color:var(--muted);
                font-variant-numeric:tabular-nums; }
  .entry-body { font-size:13px; line-height:1.55; }
  .entry-body p { margin:0 0 6px; }
  .entry-body ul, .entry-body ol { margin:4px 0; padding-left:20px; }
  .entry-body code { background:#E2E8F0; border-radius:4px; padding:1px 5px;
                     font-size:12px; }
  .entry-body pre { background:#E2E8F0; border-radius:6px; padding:10px;
                    overflow:auto; }
  .entry-body blockquote { border-left:3px solid var(--border); margin:6px 0;
                           padding:4px 12px; color:#475569; }
  .entry-body table { border-collapse:collapse; margin:6px 0; }
  .entry-body th, .entry-body td { border:1px solid var(--border);
                                   padding:4px 8px; font-size:12px; }
  .att { display:inline-block; font-size:11.5px; color:var(--muted);
         background:#fff; border:1px solid var(--border); border-radius:6px;
         padding:2px 8px; margin:4px 6px 0 0; }
  .none { color:var(--muted); font-style:italic; font-size:13px; margin:6px 0; }
  footer { margin-top:36px; color:var(--muted); font-size:12px;
           border-top:1px solid var(--border); padding-top:12px; }
</style>
</head>
<body>
<div class="wrap">
<h1>$title</h1>
<div class="meta">${l.period}: ${d.rangeLabel} · ${l.prepared} ${f.format(DateTime.now())}${d.filter.isActive ? ' · ${l.filters}: ${esc(d.filter.describe())}' : ''}</div>
<div class="stats">
<div class="stat"><b>${tasks.length}</b>${l.tasksChip}</div>
<div class="stat"><b>$totalNotes</b>${l.notesChip}</div>
<div class="stat"><b>$inPeriodNotes</b>${l.inPeriodChip}</div>
<div class="stat"><b>$done</b>${l.doneChip}</div>
</div>
''');

    if (tasks.isEmpty) {
      b.write('<p class="none">${l.noTasksInRange}</p>\n');
    } else {
      // Table of contents — anchor links into the task cards below.
      b.write('<div class="toc">\n<div class="toc-title">${l.contents}</div>\n');
      for (final g in groups.entries) {
        b.write('<div class="toc-project">${esc(g.key)} '
            '<span class="toc-count">(${g.value.length})</span></div>\n<ul>\n');
        for (final t in g.value) {
          b.write('<li><a href="#task-${t.uid}">${_notesStatusGlyph(t)} '
              '${esc(t.title)}</a> <span class="toc-count">· '
              '${t.executionLog.length} ${l.notesWord}</span></li>\n');
        }
        b.write('</ul>\n');
      }
      b.write('</div>\n');

      for (final g in groups.entries) {
        b.write('<h2>${esc(g.key)}</h2>\n');
        for (final t in g.value) {
          final sc = statusColors(t.status);
          final pc = priorityColors(t.priority);
          b.write('<div class="task" id="task-${t.uid}">\n'
              '<div class="task-head"><span>${_notesStatusGlyph(t)}</span>'
              '<h3 class="task-title">${esc(t.title)}</h3>'
              '${pill(esc(l.statusLabel(t.status)), sc.bg, sc.fg)}'
              '${pill(t.priority.shortLabel, pc.bg, pc.fg)}');
          if (_isOverdue(t, d)) {
            b.write(pill('⚠ ${l.overdueWord}', '#FEF2F2', '#DC2626'));
          }
          b.write('</div>\n<div class="task-meta">'
              '${l.createdOn} ${f.format(t.createdAt)}');
          if (t.dueDate != null) b.write(' · ${l.due} ${f.format(t.dueDate!)}');
          if (t.startedAt != null) {
            b.write(' · ${l.startedOn} ${f.format(t.startedAt!)}');
          }
          if (t.completedAt != null) {
            b.write(' · ${l.completedOn} ${f.format(t.completedAt!)}');
          }
          if (t.tags.isNotEmpty) {
            b.write(' · ${t.tags.map((x) => '#${esc(x)}').join(' ')}');
          }
          b.write('</div>\n');

          final desc = t.description?.trim();
          if (desc != null && desc.isNotEmpty) {
            b.write('<div class="section-label">${l.descriptionLabel}</div>'
                '<div class="desc">${renderMd(desc)}</div>\n');
          }

          if (t.subSteps.isNotEmpty) {
            final ordered = subStepsInDisplayOrder(t.subSteps);
            final ssDone = ordered.where((s) => s.completed).length;
            b.write('<div class="section-label">${l.subStepsLabel} '
                '($ssDone/${ordered.length})</div><ul class="steps">\n');
            for (final s in ordered) {
              final indent = 18 * _subStepDepth(t.subSteps, s);
              final glyph = s.completed ? '☑' : '☐';
              final cls = s.completed ? ' class="done"' : '';
              b.write('<li$cls style="margin-left:${indent}px;">'
                  '$glyph ${esc(s.title)}</li>\n');
            }
            b.write('</ul>\n');
          }

          final entries = [...t.executionLog]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final inPeriod = entries.where((e) => _entryInPeriod(e, d)).length;
          b.write('<div class="section-label">${l.executionLogLabel} — '
              '${l.logCount(entries.length, inPeriod)}</div>\n');
          if (entries.isEmpty) {
            b.write('<p class="none">${l.noNotes}</p>\n');
          }
          for (final e in entries) {
            final ec = entryColors(e.type);
            final isIn = _entryInPeriod(e, d);
            b.write('<div class="entry${isIn ? ' in-period' : ''}">\n'
                '<div class="entry-head">'
                '${pill('${_notesEntryGlyph(e.type)} ${l.entryTypeLabel(e.type)}', ec.bg, ec.fg)}'
                '<span class="entry-time">${ft.format(e.timestamp)}</span>');
            if (isIn) b.write(pill(l.inPeriod, '#E0E7FF', '#4F46E5'));
            b.write('</div>\n');
            final content = e.content.trim();
            if (content.isNotEmpty) {
              b.write('<div class="entry-body">${renderMd(content)}</div>\n');
            }
            b.write('${attachmentsHtml(e)}</div>\n');
          }
          b.write('</div>\n');
        }
      }
    }

    b.write('<footer>${l.generatedBy} · '
        '${l.notesStats(tasks.length, totalNotes, inPeriodNotes, done)}'
        '</footer>\n</div>\n</body>\n</html>');
    return b.toString();
  }

  // ─────────────────────────── Export ───────────────────────────

  /// Writes [content] to `<Documents>/TaskFlow/reports/<fileName>` and
  /// returns the created file.
  Future<File> export(String fileName, String content) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'TaskFlow', 'reports'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content);
    return file;
  }

  /// File name carries the FULL period range so exports sort chronologically
  /// by name: TaskFlow_Weekly_2026-11-09_2026-11-15.md.
  String suggestFileName(ReportData d, String ext) {
    final f = DateFormat('yyyy-MM-dd');
    final lastDay = f.format(d.end.subtract(const Duration(days: 1)));
    return 'TaskFlow_${d.period.label}_${f.format(d.start)}_${lastDay}.$ext';
  }

  /// File name for the raw task-notes export (v1.13.2) — distinct from the
  /// summarized report so both can coexist in the reports folder.
  String suggestNotesFileName(ReportData d, String ext) =>
      'TaskFlow_Notes_${d.titlePrefix}.$ext';
}
