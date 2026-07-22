import 'dart:io';

import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';
import '../repositories/task_repository.dart';
import 'ai_service.dart';

enum ReportPeriod {
  daily,
  weekly,
  monthly,
  yearly;

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
    }
  }
}

/// Output language for generated reports.
enum ReportLanguage {
  english,
  chinese;

  String get label => this == ReportLanguage.english ? 'English' : '中文';
}

/// Aggregated snapshot of everything that happened inside a period.
class ReportData {
  final ReportPeriod period;
  final DateTime start; // inclusive
  final DateTime end; // exclusive
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

  int get totalTouched =>
      {
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
    }
  }

  String reportTitle(ReportPeriod p) =>
      _zh ? 'TaskFlow ${periodLabel(p)} — ' : 'TaskFlow ${periodLabel(p)} Report — ';

  String get period => _zh ? '周期' : 'Period';
  String get prepared => _zh ? '生成于' : 'Prepared';

  String get statusDashboard => _zh ? '状态仪表盘' : 'Status Dashboard';
  String get project => _zh ? '项目' : 'Project';
  String get status => _zh ? '状态' : 'Status';
  String get progress => _zh ? '进度' : 'Progress';
  String get headline => _zh ? '要点' : 'Headline';
  String get overall => _zh ? '总体' : 'Overall';
  String get tasksTouched => _zh ? '涉及任务' : 'tasks touched';
  String get completedWord => _zh ? '已完成' : 'completed';
  String get subStepsWord => _zh ? '子步骤' : 'sub-steps';

  String get executiveSummary => _zh ? '执行摘要' : 'Executive Summary';
  String get achievements => _zh ? '已完成事项' : 'Achievements (Done / Closed)';
  String get inProgressWatch => _zh ? '进行中（关注）' : 'In Progress (Watch)';
  String get risksBlockers => _zh ? '风险与阻塞' : 'Risks / Blockers';
  String get noneThisPeriod => _zh ? '本期无' : 'None this period';

  String get progressDetails => _zh ? '进度明细' : 'Progress Details';
  String get groupedByProject => _zh ? '（按项目分组）' : '(Grouped by project)';
  String get item => _zh ? '事项' : 'Item';
  String get details => _zh ? '详情' : 'Details';

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
    }
  }

  String get task => _zh ? '任务' : 'Task';
  String get due => _zh ? '截止' : 'Due';
  String get priority => _zh ? '优先级' : 'Priority';
  String get noPendingTasks => _zh ? '暂无待办任务。' : 'No pending tasks.';

  String get asksDecisions => _zh ? '需决策事项' : 'Asks / Decisions Needed';

  String get generatedBy => _zh ? '由 TaskFlow 生成' : 'Generated by TaskFlow';
  String get logEntries => _zh ? '日志条目' : 'Log entries';

  // RAG labels.
  String get onTrack => _zh ? '正常' : 'On Track';
  String get watch => _zh ? '关注' : 'Watch';
  String get atRisk => _zh ? '有风险' : 'At Risk';

  String get noActivity => _zh ? '暂无动态' : 'No activity';
  String get generalGroup => _zh ? '通用' : 'General';

  // Task-detail fragments.
  String subStepsCount(int done, int total) =>
      _zh ? '子步骤 $done/$total' : '$done/$total sub-steps';
  String doneOn(String date) => _zh ? '完成于 $date' : 'done $date';
  String dueOn(String date) => _zh ? '截止 $date' : 'due $date';

  // Risk / ask fragments.
  String overdueDetail(String date, String pri) =>
      _zh ? '逾期（截止 $date，$pri）' : 'overdue (due $date, $pri)';
  String blockedDetail(String content) => _zh ? '阻塞：$content' : 'blocked: $content';
  String needsDecision(String content) =>
      _zh ? '需决策：$content' : 'needs decision: $content';
}

class ReportService {
  final TaskRepository _repo;

  ReportService(this._repo);

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
    }
  }

  Future<ReportData> generate(ReportPeriod period, DateTime anchor) async {
    final (start, end) = rangeFor(period, anchor);
    final all = await _repo.getAllTasks();

    bool inRange(DateTime? t) =>
        t != null && !t.isBefore(start) && t.isBefore(end);

    final completed = all
        .where((t) => inRange(t.completedAt))
        .toList()
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
  Future<({
    Map<Task, String> summaries,
    Map<Task, String> titles,
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
    for (final t in d.touchedTasks) {
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
    return (
      summaries: summaries,
      titles: titles,
      failed: failed,
      firstError: firstError,
    );
  }

  // ────────────────────────── Markdown ──────────────────────────

  String toMarkdown(
    ReportData d, {
    ReportLanguage lang = ReportLanguage.english,
    Map<Task, String>? aiSummaries,
    Map<Task, String>? aiTitles,
  }) {
    final l = _L(lang);
    final b = StringBuffer();
    final groups = _groupByProject(d.touchedTasks, l);

    b.writeln('# ${l.reportTitle(d.period)}${d.titlePrefix}');
    b.writeln(
        '**${l.period}:** ${d.rangeLabel} | **${l.prepared}:** ${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 1. Status Dashboard
    b.writeln('## 1. ${l.statusDashboard}');
    b.writeln();
    b.writeln('| ${l.project} | ${l.status} | ${l.progress} | ${l.headline} |');
    b.writeln('|:-----:|:------:|:--------:|:---------|');
    for (final g in groups.entries) {
      final rag = _ragForGroup(g.value, d, l);
      final done =
          g.value.where((t) => t.status == TaskStatus.completed).length;
      b.writeln(
          '| ${g.key} | ${rag.emoji} ${rag.label} | $done/${g.value.length} | ${_mdEscape(_groupHeadline(g.value, l, aiTitles))} |');
    }
    b.writeln();
    final overall = _overallRag(groups, d, l);
    b.writeln(
        '**${l.overall}:** ${overall.emoji} ${overall.label} — ${d.totalTouched} ${l.tasksTouched} · '
        '${d.completed.length} ${l.completedWord} (${(d.completionRate * 100).toStringAsFixed(0)}%) · '
        '${l.subStepsWord} ${d.subStepsDone}/${d.subStepsTotal}');
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 2. Executive Summary
    b.writeln('## 2. ${l.executiveSummary}');
    b.writeln();
    b.writeln('### ✅ ${l.achievements}');
    if (d.completed.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      for (final t in d.completed) {
        b.writeln('- **${_mdEscape(_title(t, aiTitles))}**${_tagSuffix(t)} '
            '(${l.doneOn(DateFormat('MM-dd').format(t.completedAt!))})');
        final sub = _firstSummary(t, aiSummaries);
        if (sub != null) b.writeln('  - ${_mdEscape(sub)}');
      }
    }
    b.writeln();
    b.writeln('### 🚧 ${l.inProgressWatch}');
    if (d.inProgress.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      for (final t in d.inProgress) {
        final done = t.subSteps.where((s) => s.completed).length;
        b.writeln(
            '- **${_mdEscape(_title(t, aiTitles))}** — ${l.subStepsCount(done, t.subSteps.length)}${_tagSuffix(t)}');
        final sub = _firstSummary(t, aiSummaries);
        if (sub != null) b.writeln('  - ${_mdEscape(sub)}');
      }
    }
    b.writeln();
    b.writeln('### ⚠️ ${l.risksBlockers}');
    final risks = _risks(d, l, aiTitles);
    if (risks.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      for (final r in risks) {
        b.writeln('- **${_mdEscape(r.title)}** — ${r.detail}');
      }
    }
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 3. Progress Details
    b.writeln('## 3. ${l.progressDetails}');
    b.writeln('*${l.groupedByProject}*');
    b.writeln();
    for (final g in groups.entries) {
      b.writeln('### ${g.key}');
      b.writeln();
      b.writeln('| ${l.item} | ${l.status} | ${l.details} |');
      b.writeln('|:-----|:------:|:--------|');
      for (final t in g.value) {
        b.writeln(
            '| ${_mdEscape(_title(t, aiTitles))} | ${_taskStatusEmoji(t, d)} | ${_detailsCellMd(_taskDetailsLines(t, l, aiSummaries))} |');
      }
      b.writeln();
    }
    b.writeln('---');
    b.writeln();

    // 4. Plan for Next Period
    b.writeln('## 4. ${l.planForNext(d.period)}');
    b.writeln();
    final plan = _planTasks(d);
    if (plan.isEmpty) {
      b.writeln('_${l.noPendingTasks}_');
    } else {
      b.writeln('| ${l.project} | ${l.task} | ${l.due} | ${l.priority} |');
      b.writeln('|:-----:|:-----|:---:|:--------:|');
      for (final t in plan) {
        final group = _projectOf(t, l);
        final due =
            t.dueDate != null ? DateFormat('MM-dd').format(t.dueDate!) : '—';
        b.writeln(
            '| $group | ${_mdEscape(_title(t, aiTitles))} | $due | ${t.priority.shortLabel} |');
      }
    }
    b.writeln();
    b.writeln('---');
    b.writeln();

    // 5. Asks / Decisions Needed
    b.writeln('## 5. ${l.asksDecisions}');
    final asks = _asks(d, l, aiTitles);
    if (asks.isEmpty) {
      b.writeln('- ${l.noneThisPeriod}');
    } else {
      for (final a in asks) {
        b.writeln('- **${_mdEscape(a.title)}** — ${a.detail}');
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

  ({String emoji, String label}) _ragForGroup(
      List<Task> group, ReportData d, _L l) {
    final blocked = group.any((t) => _hasEntryType(t, d, EntryType.blocked));
    final overdueHigh = group.any((t) =>
        _isOverdue(t, d) &&
        (t.priority == Priority.p0Critical || t.priority == Priority.p1High));
    final overdue = group.any((t) => _isOverdue(t, d));
    final fail = group.any((t) => _hasEntryType(t, d, EntryType.fail));
    if (blocked || overdueHigh) return (emoji: '🔴', label: l.atRisk);
    if (overdue || fail) return (emoji: '🟡', label: l.watch);
    return (emoji: '🟢', label: l.onTrack);
  }

  ({String emoji, String label}) _overallRag(
      Map<String, List<Task>> groups, ReportData d, _L l) {
    var worst = 0; // 0 green · 1 yellow · 2 red
    for (final g in groups.values) {
      final rag = _ragForGroup(g, d, l);
      final level =
          rag.emoji == '🔴' ? 2 : (rag.emoji == '🟡' ? 1 : 0);
      if (level > worst) worst = level;
    }
    if (worst == 2) return (emoji: '🔴', label: l.atRisk);
    if (worst == 1) return (emoji: '🟡', label: l.watch);
    return (emoji: '🟢', label: l.onTrack);
  }

  /// Display name for a task: the AI-translated title when available,
  /// otherwise the original title.
  String _title(Task t, Map<Task, String>? aiTitles) {
    final tr = aiTitles?[t];
    return (tr != null && tr.trim().isNotEmpty) ? tr : t.title;
  }

  /// One-line headline for a group: the top completed task, else the top
  /// in-progress task, else a quiet placeholder.
  String _groupHeadline(List<Task> group, _L l, Map<Task, String>? aiTitles) {
    final done = group.where((t) => t.status == TaskStatus.completed).toList();
    if (done.isNotEmpty) return _title(done.first, aiTitles);
    final active =
        group.where((t) => t.status == TaskStatus.inProgress).toList();
    if (active.isNotEmpty) return _title(active.first, aiTitles);
    return l.noActivity;
  }

  String _tagSuffix(Task t) =>
      t.tags.isEmpty ? '' : ' — ${t.tags.map((x) => '#$x').join(' ')}';

  String _taskStatusEmoji(Task t, ReportData d) {
    if (t.status == TaskStatus.completed) return '🟩';
    if (_isOverdue(t, d) || _hasEntryType(t, d, EntryType.blocked)) return '🟥';
    if (t.status == TaskStatus.inProgress) return '🟨';
    return '⬜';
  }

  /// DETAILS cell content as a list of lines: the AI summary bullets
  /// when available (applies to completed tasks too — their summaries
  /// describe what was accomplished), otherwise a single compact
  /// heuristic line (sub-step progress / completion / due date).
  List<String> _taskDetailsLines(
      Task t, _L l, Map<Task, String>? aiSummaries) {
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

  /// DETAILS cell for Markdown tables: a single line stays plain;
  /// multiple AI bullets become "• a<br>• b" — `<br>` renders as a real
  /// line break both in the in-app flutter_markdown preview and in
  /// GitHub / VS Code / browser viewers of the exported file.
  String _detailsCellMd(List<String> lines) {
    if (lines.length <= 1) {
      return _mdEscape(lines.isEmpty ? '—' : lines.first);
    }
    return lines.map((s) => '• ${_mdEscape(s)}').join('<br>');
  }

  /// First AI summary bullet for a task, shown as context under the
  /// Executive Summary entries; null when there is none.
  String? _firstSummary(Task t, Map<Task, String>? aiSummaries) {
    final s = aiSummaries?[t];
    if (s == null) return null;
    for (final line in s.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return _oneLine(trimmed);
    }
    return null;
  }

  /// Upcoming work: in-progress carry-over plus newly planned tasks,
  /// highest priority first.
  List<Task> _planTasks(ReportData d) => [...d.inProgress, ...d.planned]
    ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

  List<({String title, String detail})> _risks(
      ReportData d, _L l, Map<Task, String>? aiTitles) {
    final out = <({String title, String detail})>[];
    for (final t in d.overdue) {
      out.add((
        title: _title(t, aiTitles),
        detail: l.overdueDetail(
            DateFormat('MM-dd').format(t.dueDate!), t.priority.shortLabel),
      ));
    }
    for (final entry in d.logActivity.entries) {
      for (final e
          in entry.value.where((e) => e.type == EntryType.blocked)) {
        out.add((
          title: _title(entry.key, aiTitles),
          detail: l.blockedDetail(_oneLine(e.content)),
        ));
      }
    }
    return out;
  }

  List<({String title, String detail})> _asks(
      ReportData d, _L l, Map<Task, String>? aiTitles) {
    final out = <({String title, String detail})>[];
    for (final entry in d.logActivity.entries) {
      for (final e
          in entry.value.where((e) => e.type == EntryType.blocked)) {
        out.add((
          title: _title(entry.key, aiTitles),
          detail: l.needsDecision(_oneLine(e.content)),
        ));
      }
    }
    return out;
  }

  String _mdEscape(String s) =>
      s.replaceAll('|', '\\|').replaceAll('\n', ' ');

  String _oneLine(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Generous cap: full AI summary bullets must reach the Details cell
    // uncut; 300 only guards against pathological model output.
    if (t.length > 300) t = '${t.substring(0, 300)}…';
    return t;
  }

  // ──────────────────────────── HTML ────────────────────────────

  /// Renders the report as HTML.
  ///
  /// With [email] false (default) this produces the browser-oriented
  /// document: a `<style>` block plus paste-proof inline styles, a 900px
  /// centered column on a soft-gray page, rounded corners and translucent
  /// RAG pills. Optimized for opening the file directly in a browser.
  ///
  /// With [email] true this produces a strict Gmail-compatible document
  /// modeled on the reference email template, following classic email-HTML
  /// conventions:
  ///  - table-based page layout (100% outer table, max-width:900px centered
  ///    content table, font/color on <body>),
  ///  - white background everywhere (a colored body background renders as a
  ///    full-width band in Gmail),
  ///  - pure inline styles — no `<style>` block, no CSS variables,
  ///  - 6-digit hex colors only (no 8-digit alpha hex, no rgba),
  ///  - no border-radius / overflow:hidden / flexbox / grid on layout — the
  ///    only exception is the small decorative border-radius on RAG pills.
  /// It therefore intentionally looks plainer than the browser export —
  /// that is the price of rendering identically across mail clients.
  String toHtml(
    ReportData d, {
    ReportLanguage lang = ReportLanguage.english,
    Map<Task, String>? aiSummaries,
    Map<Task, String>? aiTitles,
    bool email = false,
  }) {
    final l = _L(lang);

    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    // ── Paste-proof inline styles ──────────────────────────────────
    // Gmail / Outlook strip <style> blocks AND class attributes from
    // pasted HTML, but keep (most) inline style attributes. Every visual
    // property is therefore duplicated onto the element itself. Values
    // mirror the stylesheet below exactly, so the standalone browser
    // view is pixel-identical while the copy-paste-into-email path keeps
    // tables, pills, colored callouts and list styling.
    const bd = '#E2E8F0'; // border
    const mut = '#64748B'; // muted text
    const wrapS = "max-width:1000px;margin:0 auto;padding:32px 24px 64px;"
        "font-family:-apple-system,'Segoe UI',Roboto,'Noto Sans SC',"
        "'Microsoft YaHei',sans-serif;color:#1E293B;";
    final h1S = email
        ? 'font-size:24px;font-weight:bold;margin:0 0 4px 0;color:#1E293B;'
        : 'font-size:24px;margin:0 0 4px;color:#1E293B;';
    const metaS = 'color:$mut;font-size:13px;margin-bottom:24px;';
    final h2S = email
        ? 'font-size:16px;font-weight:bold;margin:28px 0 10px 0;'
            'border-bottom:1px solid $bd;padding-bottom:6px;color:#1E293B;'
        : 'font-size:16px;margin:28px 0 10px;border-bottom:1px solid '
            '$bd;padding-bottom:6px;color:#1E293B;';
    final h3S = email
        ? 'font-size:13px;font-weight:bold;margin:16px 0 8px 0;color:#334155;'
        : 'font-size:13px;margin:18px 0 8px;color:#334155;';
    final tableS = email
        ? 'border-collapse:collapse;border:1px solid $bd;margin-bottom:12px;'
        : 'width:100%;border-collapse:collapse;border-spacing:0;'
            'background:#ffffff;border:1px solid $bd;'
            'border-radius:12px;margin-bottom:8px;';
    // In the email variant the header-row background lives on the <tr>
    // (matching the reference example), not on each <th>.
    final thBg = email ? '' : 'background:#F1F5F9;';
    final headTrOpen = email ? '<tr style="background-color:#F1F5F9;">' : '<tr>';
    final thL = 'text-align:left;font-size:11px;text-transform:uppercase;'
        'letter-spacing:.5px;color:$mut;padding:10px 14px;$thBg';
    final thC = 'text-align:center;font-size:11px;text-transform:uppercase;'
        'letter-spacing:.5px;color:$mut;padding:10px 14px;$thBg';
    const tdL = 'padding:10px 14px;font-size:13px;border-top:1px solid $bd;'
        'vertical-align:top;';
    const tdC = '${tdL}text-align:center;';
    const tdT = '${tdL}font-weight:600;';
    final overallS = email
        ? 'border:1px solid $bd;padding:12px 16px;font-size:13px;'
            'margin-top:8px;margin-bottom:20px;background-color:#FFFFFF;'
        : 'background:#ffffff;border:1px solid $bd;'
            'border-radius:12px;padding:14px 16px;'
            'font-size:13px;margin-top:8px;';
    const sumUlS = 'margin:6px 0 0;padding-left:20px;';
    const sumLiS = 'font-size:13px;margin-bottom:6px;line-height:1.5;';
    const subUlS = 'margin:4px 0 2px;padding-left:18px;color:#475569;';
    const subLiS = 'font-size:12.5px;margin-bottom:2px;';
    const detUlS = 'margin:0;padding-left:16px;';
    const detLiS = 'font-size:12.5px;margin-bottom:3px;line-height:1.45;';
    const noneS = 'color:$mut;font-style:italic;font-size:13px;margin:6px 0;';
    const groupHeadS = 'font-weight:700;font-size:13px;margin:16px 0 6px;'
        'color:#6366F1;';
    const footerS = 'margin-top:36px;color:$mut;font-size:12px;'
        'border-top:1px solid $bd;padding-top:12px;';
    String sumboxS(String color, String bg) => email
        ? 'border-left:4px solid $color;padding:10px 14px;'
            'margin:0 0 16px 0;background-color:$bg;'
        : 'border-left:3px solid $color;'
            'border-radius:0 10px 10px 0;'
            'padding:8px 14px 6px;margin:0 0 12px;background:$bg;';

    final groups = _groupByProject(d.touchedTasks, l);
    final overall = _overallRag(groups, d, l);

    String ragPill(({String emoji, String label}) rag) {
      if (email) {
        // Google-style solid 6-digit pastels, matching the reference email.
        // The pill keeps a small decorative border-radius:12px — the
        // "fixed decoration" exception in the no-rounded-corners rule.
        final String bg, fg;
        switch (rag.emoji) {
          case '🔴':
            bg = '#FCE8E6';
            fg = '#C5221F';
          case '🟡':
            bg = '#FEF7E0';
            fg = '#B06000';
          default:
            bg = '#E6F4EA';
            fg = '#137333';
        }
        return '<span style="display:inline-block;padding:2px 8px;'
            'border-radius:12px;font-size:11px;font-weight:bold;'
            'white-space:nowrap;background-color:$bg;color:$fg;">'
            '${rag.emoji} ${rag.label}</span>';
      }
      final color = rag.emoji == '🔴'
          ? '#EF4444'
          : (rag.emoji == '🟡' ? '#F59E0B' : '#22C55E');
      return '<span class="rag" style="display:inline-block;padding:2px 10px;'
          'border-radius:999px;font-size:11px;font-weight:700;'
          'white-space:nowrap;background:${color}1a;color:$color;">'
          '${rag.emoji} ${rag.label}</span>';
    }

    // DETAILS cell: a single line stays plain text; multiple AI bullets
    // become a compact real list inside the table cell.
    String detailsCell(List<String> lines) {
      if (lines.length <= 1) return esc(lines.isEmpty ? '—' : lines.first);
      return '<ul class="details" style="$detUlS">'
          '${lines.map((s) => '<li style="$detLiS">${esc(s)}</li>').join()}'
          '</ul>';
    }

    final htmlLang = lang == ReportLanguage.chinese ? 'zh-CN' : 'en';
    final title = '${esc(l.reportTitle(d.period))}${esc(d.titlePrefix)}';
    final b = StringBuffer();

    // Opening tag for data tables. The email variant carries width="100%"
    // and border="0" as HTML attributes (more reliable than CSS in mail
    // clients) to match the reference source; the browser variant keeps
    // relying on its stylesheet / inline CSS.
    final tableOpen = email
        ? '<table width="100%" border="0" cellspacing="0" cellpadding="0" style="$tableS">'
        : '<table cellspacing="0" cellpadding="0" style="$tableS">';

    // Shared opening: title, meta line and the Status Dashboard table
    // header. Identical for both documents — only the wrapper differs.
    final innerHead = '''<h1 style="$h1S">$title</h1>
<div class="meta" style="$metaS">${l.period}: ${d.rangeLabel} · ${l.prepared} ${DateFormat('yyyy-MM-dd').format(DateTime.now())}</div>

<h2 style="$h2S">1. ${l.statusDashboard}</h2>
$tableOpen
$headTrOpen<th style="$thL">${l.project}</th><th class="center" style="$thC">${l.status}</th><th class="center" style="$thC">${l.progress}</th><th style="$thL">${l.headline}</th></tr>
''';

    // Page wrapper — deliberately different per variant, matching the
    // reference email example. The browser doc uses a div-based 1000px
    // centered column on a soft-gray page. The email doc uses the classic
    // Gmail-safe recipe: font/color on <body>, a 100% outer table with
    // vertical padding centering a width=100%/max-width:900px content
    // table, all-white background (a colored body/page background renders
    // as a full-width band in Gmail).
    final String bodyOpen;
    final String bodyClose;
    if (email) {
      bodyOpen = '''<body style="margin:0; padding:0; background-color:#ffffff; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, 'Noto Sans SC', 'Microsoft YaHei', sans-serif; color:#1E293B;">
<table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color:#ffffff; margin:0; padding:20px 0;">
<tr>
<td align="center">
<table width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width:900px; padding:0 16px; text-align:left;">
<tr>
<td>
''';
      bodyClose =
          '</td>\n</tr>\n</table>\n</td>\n</tr>\n</table>\n</body>\n</html>';
    } else {
      bodyOpen = '''<body bgcolor="#F8FAFC" style="margin:0;padding:0;background:#F8FAFC;">
<div class="wrap" style="$wrapS">
''';
      bodyClose = '</div>\n</body>\n</html>';
    }

    if (email) {
      // Email-client document: no <style> block (mail clients strip it;
      // every style is already inline) and the table-based white page
      // wrapper defined in bodyOpen above.
      b.write('''<!DOCTYPE html>
<html lang="$htmlLang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
</head>
$bodyOpen$innerHead''');
    } else {
      b.write('''<!DOCTYPE html>
<html lang="$htmlLang">
<head>
<meta charset="utf-8">
<title>$title</title>
<style>
  :root { --primary:#6366F1; --border:#E2E8F0; --muted:#64748B; }
  * { box-sizing:border-box; }
  body { font-family:-apple-system,"Segoe UI",Roboto,"Noto Sans SC","Microsoft YaHei",sans-serif;
         margin:0; background:#F8FAFC; color:#1E293B; }
  .wrap { max-width:1000px; margin:0 auto; padding:32px 24px 64px; }
  h1 { font-size:24px; margin:0 0 4px; }
  .meta { color:var(--muted); font-size:13px; margin-bottom:24px; }
  h2 { font-size:16px; margin:28px 0 10px; border-bottom:1px solid var(--border);
       padding-bottom:6px; }
  h3 { font-size:13px; margin:18px 0 8px; color:#334155; }
  table { width:100%; border-collapse:collapse; background:#fff;
          border:1px solid var(--border); border-radius:12px; overflow:hidden;
          margin-bottom:8px; }
  th { text-align:left; font-size:11px; text-transform:uppercase;
       letter-spacing:.5px; color:var(--muted); padding:10px 14px;
       background:#F1F5F9; }
  td { padding:10px 14px; font-size:13px; border-top:1px solid var(--border);
       vertical-align:top; }
  td.title { font-weight:600; }
  .center { text-align:center; }
  .rag { display:inline-block; padding:2px 10px; border-radius:999px;
         font-size:11px; font-weight:700; white-space:nowrap; }
  .overall { background:#fff; border:1px solid var(--border); border-radius:12px;
             padding:14px 16px; font-size:13px; margin-top:8px; }
  ul.sum { margin:6px 0 0; padding-left:20px; }
  ul.sum li { font-size:13px; margin-bottom:6px; line-height:1.5; }
  ul.sum li ul.sub { margin:4px 0 2px; padding-left:18px; color:#475569; }
  ul.sum li ul.sub li { font-size:12.5px; margin-bottom:2px; }
  .sumbox { border-left:3px solid var(--border); border-radius:0 10px 10px 0;
            padding:8px 14px 6px; margin:0 0 12px; }
  .sumbox.achv { border-color:#22C55E; background:#F0FDF4; }
  .sumbox.watch { border-color:#3B82F6; background:#EFF6FF; }
  .sumbox.risk { border-color:#F59E0B; background:#FFFBEB; }
  ul.details { margin:0; padding-left:16px; }
  ul.details li { font-size:12.5px; margin-bottom:3px; line-height:1.45; }
  .none { color:var(--muted); font-style:italic; font-size:13px; }
  .group-head { font-weight:700; font-size:13px; margin:16px 0 6px;
                color:var(--primary); }
  footer { margin-top:36px; color:var(--muted); font-size:12px;
           border-top:1px solid var(--border); padding-top:12px; }
</style>
</head>
$bodyOpen$innerHead''');
    }

    for (final g in groups.entries) {
      final rag = _ragForGroup(g.value, d, l);
      final done =
          g.value.where((t) => t.status == TaskStatus.completed).length;
      b.write('<tr><td class="title" style="$tdT">${esc(g.key)}</td>'
          '<td class="center" style="$tdC">${ragPill(rag)}</td>'
          '<td class="center" style="$tdC">$done/${g.value.length}</td>'
          '<td style="$tdL">${esc(_groupHeadline(g.value, l, aiTitles))}</td></tr>\n');
    }

    b.write('''</table>
<div class="overall" style="$overallS"><strong>${l.overall}:</strong> ${ragPill(overall)} — ${d.totalTouched} ${l.tasksTouched} · ${d.completed.length} ${l.completedWord} (${(d.completionRate * 100).toStringAsFixed(0)}%) · ${l.subStepsWord} ${d.subStepsDone}/${d.subStepsTotal}</div>

<h2 style="$h2S">2. ${l.executiveSummary}</h2>
<h3 style="$h3S">✅ ${l.achievements}</h3>
<div class="sumbox achv" style="${sumboxS('#22C55E', '#F0FDF4')}">
''');

    if (d.completed.isEmpty) {
      b.write('<p class="none" style="$noneS">${l.noneThisPeriod}</p>');
    } else {
      b.write('<ul class="sum" style="$sumUlS">');
      for (final t in d.completed) {
        b.write('<li style="$sumLiS"><strong>${esc(_title(t, aiTitles))}</strong>${esc(_tagSuffix(t))} '
            '(${esc(l.doneOn(DateFormat('MM-dd').format(t.completedAt!)))})');
        final sub = _firstSummary(t, aiSummaries);
        if (sub != null) {
          b.write('<ul class="sub" style="$subUlS"><li style="$subLiS">${esc(sub)}</li></ul>');
        }
        b.write('</li>');
      }
      b.write('</ul>');
    }
    b.write('</div>');

    b.write('<h3 style="$h3S">🚧 ${l.inProgressWatch}</h3>'
        '<div class="sumbox watch" style="${sumboxS('#3B82F6', '#EFF6FF')}">');
    if (d.inProgress.isEmpty) {
      b.write('<p class="none" style="$noneS">${l.noneThisPeriod}</p>');
    } else {
      b.write('<ul class="sum" style="$sumUlS">');
      for (final t in d.inProgress) {
        final done = t.subSteps.where((s) => s.completed).length;
        b.write(
            '<li style="$sumLiS"><strong>${esc(_title(t, aiTitles))}</strong> — ${esc(l.subStepsCount(done, t.subSteps.length))}${esc(_tagSuffix(t))}');
        final sub = _firstSummary(t, aiSummaries);
        if (sub != null) {
          b.write('<ul class="sub" style="$subUlS"><li style="$subLiS">${esc(sub)}</li></ul>');
        }
        b.write('</li>');
      }
      b.write('</ul>');
    }
    b.write('</div>');

    b.write('<h3 style="$h3S">⚠️ ${l.risksBlockers}</h3>'
        '<div class="sumbox risk" style="${sumboxS('#F59E0B', '#FFFBEB')}">');
    final risks = _risks(d, l, aiTitles);
    if (risks.isEmpty) {
      b.write('<p class="none" style="$noneS">${l.noneThisPeriod}</p>');
    } else {
      b.write('<ul class="sum" style="$sumUlS">');
      for (final r in risks) {
        b.write('<li style="$sumLiS"><strong>${esc(r.title)}</strong> — ${esc(r.detail)}</li>');
      }
      b.write('</ul>');
    }
    b.write('</div>');

    b.write('<h2 style="$h2S">3. ${l.progressDetails}</h2>');
    for (final g in groups.entries) {
      b.write('<div class="group-head" style="$groupHeadS">${esc(g.key)}</div>');
      b.write(
          '$tableOpen$headTrOpen<th style="$thL">${l.item}</th><th class="center" style="$thC">${l.status}</th><th style="$thL">${l.details}</th></tr>');
      for (final t in g.value) {
        b.write('<tr><td class="title" style="$tdT">${esc(_title(t, aiTitles))}</td>'
            '<td class="center" style="$tdC">${_taskStatusEmoji(t, d)}</td>'
            '<td style="$tdL">${detailsCell(_taskDetailsLines(t, l, aiSummaries))}</td></tr>');
      }
      b.write('</table>');
    }

    b.write('<h2 style="$h2S">4. ${l.planForNext(d.period)}</h2>');
    final plan = _planTasks(d);
    if (plan.isEmpty) {
      b.write('<p class="none" style="$noneS">${l.noPendingTasks}</p>');
    } else {
      b.write(
          '$tableOpen$headTrOpen<th style="$thL">${l.project}</th><th style="$thL">${l.task}</th><th class="center" style="$thC">${l.due}</th><th class="center" style="$thC">${l.priority}</th></tr>');
      for (final t in plan) {
        final group = _projectOf(t, l);
        final due =
            t.dueDate != null ? DateFormat('MM-dd').format(t.dueDate!) : '—';
        b.write('<tr><td style="$tdL">${esc(group)}</td><td class="title" style="$tdT">${esc(_title(t, aiTitles))}</td>'
            '<td class="center" style="$tdC">$due</td><td class="center" style="$tdC">${t.priority.shortLabel}</td></tr>');
      }
      b.write('</table>');
    }

    b.write('<h2 style="$h2S">5. ${l.asksDecisions}</h2>');
    final asks = _asks(d, l, aiTitles);
    if (asks.isEmpty) {
      b.write('<p class="none" style="$noneS">${l.noneThisPeriod}</p>');
    } else {
      b.write('<ul class="sum" style="$sumUlS">');
      for (final a in asks) {
        b.write('<li style="$sumLiS"><strong>${esc(a.title)}</strong> — ${esc(a.detail)}</li>');
      }
      b.write('</ul>');
    }

    final footerTag = email ? 'div' : 'footer';
    b.write('''
<$footerTag style="$footerS">${l.generatedBy} · ${l.logEntries}: Pass ${d.entryPass} / Fail ${d.entryFail} / Blocked ${d.entryBlocked} / Note ${d.entryNote}</$footerTag>
''');
    b.write(bodyClose);
    return b.toString();
  }

  /// Converts a Markdown string (typically the user-edited report source)
  /// into a standalone, styled HTML document.
  ///
  /// Unlike [toHtml] — which renders a [ReportData] into the fixed report
  /// template — this renders whatever Markdown it is given, so user edits
  /// made in the Reports preview are faithfully preserved on export. Tables
  /// and inline `<br>` produced by [toMarkdown] are handled via the GitHub
  /// extension set.
  String markdownToStyledHtml(String markdown, {String? title}) {
    final body = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    final docTitle = (title == null || title.isEmpty) ? 'TaskFlow Report' : title;
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
  p, li { font-size:13px; line-height:1.55; }
  table { width:100%; border-collapse:collapse; background:#fff;
          border:1px solid var(--border); border-radius:12px; overflow:hidden;
          margin-bottom:8px; }
  th { text-align:left; font-size:11px; text-transform:uppercase;
       letter-spacing:.5px; color:var(--muted); padding:10px 14px;
       background:#F1F5F9; }
  td { padding:10px 14px; font-size:13px; border-top:1px solid var(--border);
       vertical-align:top; }
  blockquote { border-left:3px solid var(--border); margin:0 0 12px;
               padding:8px 14px; color:#475569; background:#fff;
               border-radius:0 10px 10px 0; }
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

  String suggestFileName(ReportData d, String ext) =>
      'TaskFlow_${d.period.label}_${d.titlePrefix}.$ext';
}
