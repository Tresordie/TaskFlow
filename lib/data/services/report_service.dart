import 'dart:io';

import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';
import '../repositories/task_repository.dart';
import 'ai_service.dart';

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
      case ReportPeriod.custom:
        return _zh ? '下期计划' : 'Plan for Next Period';
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
  String blockedDetail(String content) =>
      _zh ? '阻塞：$content' : 'blocked: $content';
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
      final entries = d.logActivity[t] ?? const <ExecutionEntry>[];
      if (entries.isNotEmpty) {
        b.writeln('Execution Log (${entries.length} entries in period):');
        for (final e in entries) {
          final content = e.content
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          b.writeln('  [${f.format(e.timestamp)}] ${e.type.name}: $content');
        }
      } else {
        b.writeln('Execution Log: (none in period)');
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
      '1. Read and comprehend every task\'s description AND every Execution '
      'Log Note across all tasks. Do not skim or skip entries. Both sources '
      'are equally important for generating accurate summaries.\n'
      '2. Classify each task under its Project.\n'
      '3. Synthesize — distill raw notes into concise, meaningful '
      'summaries. Preserve all technical terminology, part numbers, '
      'firmware versions, measurements, abbreviations, and proper nouns '
      'exactly as written in the original notes. NEVER rewrite, '
      'generalize, paraphrase, or substitute any technical identifier — '
      'copy it verbatim.\n'
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
      '## 1. Status Dashboard\n\n'
      '| Project | Status | Progress | Headline |\n'
      '|:-----:|:------:|:--------:|:---------|\n'
      '| {Project} | {emoji} {label} | {done}/{total} | {one-line headline '
      'of most significant task} |\n\n'
      '**Overall:** {emoji} {label} — {N} tasks touched · {M} completed '
      '({pct}%) · sub-steps {x}/{y}\n\n'
      '---\n\n'
      '## 2. Executive Summary\n\n'
      '### ✅ Achievements (Completed)\n'
      '- **{Task title}** (completed {MM-DD})\n'
      '  - {1–2 sentence incisive summary of what was accomplished and '
      'why it matters.}\n\n'
      '### 🚧 In Progress (Watch)\n'
      '- **{Task title}** — {x}/{y} sub-steps\n'
      '  - {1–2 sentence summary of current state and what remains.}\n\n'
      '### ⚠️ Risks / Blockers\n'
      '- **{Task title}** — overdue (due {MM-DD}, {Px}) or blocked since '
      '{MM-DD}\n'
      '  - {1–2 sentence summary including root cause and impact.}\n'
      '- (If none: "None this period")\n\n'
      '---\n\n'
      '## 3. Progress Details\n'
      '*(Grouped by project)*\n\n'
      '### {Project Name}\n\n'
      '| Item | Status | Details |\n'
      '|:-----|:------:|:--------|\n'
      '| {Task title} | {🟩/🟨/🟥/⬜} | • {bullet 1}<br>• {bullet 2} |\n\n'
      '---\n\n'
      '## 4. Plan for Next Period\n\n'
      '| Project | Task | Due | Priority |\n'
      '|:-----:|:-----|:---:|:--------:|\n'
      '| {Project} | {Task or decomposed sub-task} | {MM-DD or —} | '
      '{P0–P3} |\n\n'
      '---\n\n'
      '## 5. Asks / Decisions Needed\n'
      '- {Item requiring external input, escalation, or cross-team '
      'decision}\n'
      '- (If none: "None this period")\n\n'
      '---\n'
      '_Generated by TaskFlow · Log entries: Pass {n} / Fail {n} / '
      'Blocked {n} / Note {n}_\n\n'
      'SECTION-SPECIFIC RULES:\n\n'
      '1. Status Dashboard:\n'
      '- One row per project that has at least one task in the period.\n'
      '- Status emoji: 🟢 On Track (all progressing normally/completed); '
      '🟡 At Risk (delays, pending external dependencies, overdue, or '
      'approaching deadlines with incomplete work); 🔴 Blocked (one or '
      'more tasks explicitly blocked).\n'
      '- Progress = completed tasks / total tasks for that project.\n'
      '- Headline = the single most impactful task title or outcome.\n'
      '- The Overall line aggregates across all projects.\n\n'
      '2. Executive Summary:\n'
      '- Achievements: only Completed tasks (completion date in period). '
      'Present as a bullet list; each task gets exactly 1–2 sentences '
      'focusing on OUTCOME and significance, not process. Do NOT write '
      'paragraphs — keep it tight and scannable.\n'
      '- In Progress: include sub-step ratio; summarize what advanced '
      'this period and what remains.\n'
      '- Risks / Blockers: overdue tasks and tasks with blocked log '
      'entries. MUST include reason/root cause; state schedule impact '
      'if any.\n'
      '- Keep every bullet incisive — no filler, no restating the task '
      'title in the summary body.\n\n'
      '3. Progress Details:\n'
      '- Group tasks under their Project heading (H3).\n'
      '- Table alignment (STRICT): every project table MUST use identical '
      'fixed column widths — Item 25%, Status 8%, Details 67%. In HTML '
      'output enforce via <colgroup><col style="width:25%"><col '
      'style="width:8%"><col style="width:67%"></colgroup> inside each '
      '<table>; do NOT let content auto-size columns differently.\n'
      '- Status icons: 🟩 Completed, 🟨 In Progress, 🟥 Blocked/overdue, '
      '⬜ Planned.\n'
      '- Details column (MANDATORY for ALL tasks regardless of status): '
      'summarize from BOTH the task description AND the Execution Log '
      'Notes, combining both sources into a coherent summary — this '
      'applies equally to Completed, In Progress, Blocked, and Planned '
      'tasks. Maximum 5 bullets per task (use • separated by <br>). Each '
      'bullet = one distinct fact or milestone — do not merge unrelated '
      'facts. Preserve technical specifics: part numbers, firmware '
      'versions, voltage/current values, dates, vendor names, tracking '
      'numbers. Completed tasks are NOT exempt — their Details must '
      'contain a full summary of what was done, how, and the outcome. '
      'NEVER dismiss a task that has content: if a task has a description '
      'or ANY Execution Log entry (even slightly outside the period), you '
      'MUST summarize it. The fallback "No execution logs in the reporting '
      'period" is ONLY allowed when the task has literally NO description '
      'AND NO log entries at all.\n\n'
      '4. Plan for Next Period (MANDATORY — never omit):\n'
      '- This section is REQUIRED in every report. If there are no '
      'upcoming tasks, still include the section header with a note.\n'
      '- Include: Planned tasks, In Progress tasks (remaining work), and '
      'Blocked/overdue tasks (unblock steps).\n'
      '- Grouping (STRICT): rows MUST be grouped into contiguous blocks '
      'by Project — all tasks of one project appear together before '
      'moving to the next; NEVER interleave rows from different '
      'projects. Within each block, order by priority (P0 first). Task '
      'decomposition: if your understanding of the Execution Log '
      'suggests a task should be broken into smaller actionable steps, '
      'decompose it into multiple rows — each a concrete, completable '
      'action.\n'
      '- Due date: use the task\'s due date if set; otherwise "—".\n'
      '- Priority: P0 = critical path / blocks other work / imminent '
      'deadline; P1 = important, complete next period; P2 = planned but '
      'flexible; P3 = nice-to-have / backlog.\n\n'
      '5. Asks / Decisions Needed (MANDATORY — never omit):\n'
      '- This section is REQUIRED in every report. If nothing is needed, '
      'write "None this period" — but the section header must still '
      'appear.\n'
      '- Extract from blockers, pending confirmations, cross-team '
      'dependencies, or unresolved questions in Execution Log Notes.\n'
      '- Each item actionable: state WHO needs to decide/provide WHAT, '
      'and by WHEN if inferable.\n'
      '- If genuinely nothing is needed: "None this period".\n\n'
      'QUALITY CHECKLIST (self-verify before outputting):\n'
      '- ALL 5 sections are present: Status Dashboard, Executive Summary, '
      'Progress Details, Plan for Next Period, Asks / Decisions Needed.\n'
      '- Every task in the input appears in at least one section.\n'
      '- No Chinese characters in the output.\n'
      '- Technical terms, part numbers, abbreviations, measurements '
      'preserved verbatim — none rewritten or generalized.\n'
      '- Every bullet states exactly one fact — no merged multi-fact '
      'bullets.\n'
      '- All summaries use nested bullet hierarchy — zero flat '
      'paragraphs anywhere.\n'
      '- Executive Summary bullets ≤ 2 sentences each.\n'
      '- Progress Details bullets ≤ 5 per task.\n'
      '- All Progress Details project tables use identical column widths '
      '(25%/8%/67%) — visually aligned.\n'
      '- Status Dashboard progress fractions arithmetically correct.\n'
      '- Plan rows form contiguous per-project blocks (no interleaving), '
      'ordered by priority within each block.\n'
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
      '1. 通读并理解每个任务的描述（description）以及全部执行日志，'
      '不得跳过任何条目；两类来源对生成准确总结同等重要。\n'
      '2. 将每个任务归类到其项目下。\n'
      '3. 综合提炼——将原始日志提炼为简洁、有意义的总结。完整保留所有'
      '技术术语、物料编号、固件版本、测量值、缩写和专有名词，'
      '一律照抄原文，禁止改写、概括、转述或替换任何技术标识。\n'
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
      '## 1. 状态仪表盘\n\n'
      '| 项目 | 状态 | 进度 | 要点 |\n'
      '|:-----:|:------:|:--------:|:---------|\n'
      '| {项目} | {emoji} {标签} | {完成数}/{总数} | {最重要任务一行标题} |\n\n'
      '**总体:** {emoji} {标签} — 涉及 {N} 项任务 · 已完成 {M} 项'
      '（{pct}%）· 子步骤 {x}/{y}\n\n'
      '---\n\n'
      '## 2. 执行摘要\n\n'
      '### ✅ 已完成事项\n'
      '- **{任务标题}**（完成于 {MM-DD}）\n'
      '  - {1–2 句精炼总结：完成了什么、为何重要}\n\n'
      '### 🚧 进行中（关注）\n'
      '- **{任务标题}** — 子步骤 {x}/{y}\n'
      '  - {1–2 句总结：当前状态与剩余工作}\n\n'
      '### ⚠️ 风险与阻塞\n'
      '- **{任务标题}** — 逾期（截止 {MM-DD}，{Px}）或阻塞自 {MM-DD}\n'
      '  - {1–2 句总结：根因与影响}\n'
      '- （若无："本期无"）\n\n'
      '---\n\n'
      '## 3. 进度明细\n'
      '*（按项目分组）*\n\n'
      '### {项目名}\n\n'
      '| 事项 | 状态 | 详情 |\n'
      '|:-----|:------:|:--------|\n'
      '| {任务标题} | {🟩/🟨/🟥/⬜} | • {要点1}<br>• {要点2} |\n\n'
      '---\n\n'
      '## 4. 下期计划\n\n'
      '| 项目 | 任务 | 截止 | 优先级 |\n'
      '|:-----:|:-----|:---:|:--------:|\n'
      '| {项目} | {任务或分解后的子任务} | {MM-DD 或 —} | {P0–P3} |\n\n'
      '---\n\n'
      '## 5. 需决策事项\n'
      '- {需要外部输入、升级或跨团队决策的事项}\n'
      '- （若无："本期无"）\n\n'
      '---\n'
      '_由 TaskFlow 生成 · 日志条目: Pass {n} / Fail {n} / '
      'Blocked {n} / Note {n}_\n\n'
      '各节规则：\n\n'
      '1. 状态仪表盘：每个有任务的项目一行；状态 emoji：🟢 正常、'
      '🟡 有风险（延期/外部依赖/逾期/临近截止）、🔴 阻塞；'
      '进度=已完成/总数；要点=最有影响力的任务或成果。\n\n'
      '2. 执行摘要：成果仅含已完成任务，以列表呈现，每条聚焦结果与'
      '意义、不超 2 句，禁止写成段落，保持精炼可扫读；进行中含'
      '子步骤比例与剩余工作；风险含逾期任务和阻塞日志条目，'
      '必须说明根因与进度影响。\n\n'
      '3. 进度明细：按项目分组（H3）。表格对齐（严格）：每个项目表必须'
      '使用相同的固定列宽——事项 25%、状态 8%、详情 67%；HTML 输出中'
      '用 <colgroup><col style="width:25%"><col style="width:8%"><col '
      'style="width:67%"></colgroup> 强制，禁止内容自适应导致各表列宽'
      '不一。状态图标 🟩已完成 🟨进行中 🟥阻塞/逾期 ⬜计划中；详情列'
      '（对所有状态的任务都必填）综合任务描述与执行日志两类来源总结——'
      '已完成、进行中、阻塞、计划中任务一视同仁，每任务最多 5 个要点'
      '（• 用 <br> 分隔），每个要点=一个独立事实，保留技术细节；'
      '已完成任务不可豁免，其详情必须完整总结做了什么、如何做、结果如何；'
      '禁止轻易略过有内容的任务：只要任务有描述或任何执行日志（即使'
      '时间略超出报告期）就必须总结；仅当任务既无描述也无任何日志时，'
      '才写"报告期内无执行日志；{简要状态}"。\n\n'
      '4. 下期计划（必填，禁止省略）：每份报告都必须有此章节；'
      '即使没有后续任务，也要保留标题并加说明。含计划中、进行中'
      '（剩余工作）、阻塞（解除步骤）的任务。分组（严格）：行必须'
      '按项目连续成块——同一项目的任务全部排在一起再进入下一个'
      '项目，禁止不同项目的行交叉混排；每个项目块内按优先级排序'
      '（P0 在前）。可根据日志理解将任务分解为多个具体可完成的'
      '行动行。\n\n'
      '5. 需决策事项（必填，禁止省略）：每份报告都必须有此章节；'
      '若无需决策事项，写"本期无"，但章节标题必须保留。从阻塞、'
      '待确认、跨团队依赖或未解决问题中提取；每项须可执行：'
      '说明谁需要决策/提供什么。\n\n'
      '质量自检：5 个章节（状态仪表盘、执行摘要、进度明细、下期计划、'
      '需决策事项）全部齐备；每个任务至少出现在一个章节；技术术语、'
      '物料编号、缩写、测量值原样保留不得改写；每个要点只讲一个事实、'
      '不合并多事实；所有总结用嵌套列表层级、全报告零平铺段落；'
      '摘要不超 2 句；明细每任务不超 5 条；进度明细各项目表列宽一致'
      '（25%/8%/67%）视觉对齐；进度分数算术正确；'
      '下期计划按项目连续成块不交叉、块内按优先级排序；'
      '报告应连贯、可在 2 分钟内扫读完毕。'
      '仅输出 Markdown 报告本身，不要额外说明或代码围栏。';

  // ────────────────────────── Markdown ──────────────────────────

  String toMarkdown(
    ReportData d, {
    ReportLanguage lang = ReportLanguage.english,
    Map<Task, String>? aiSummaries,
    Map<Task, String>? aiTitles,
    Map<String, String>? aiTerms,
  }) {
    final l = _L(lang);
    final b = StringBuffer();
    final groups = _groupByProject(d.touchedTasks, l);

    b.writeln('# ${l.reportTitle(d.period)}${d.titlePrefix}');
    b.writeln(
        '**${l.period}:** ${d.rangeLabel} | **${l.prepared}:** ${DateFormat('yyyy-MM-dd').format(DateTime.now())}'
        '${d.filter.isActive ? ' | **${l.filters}:** ${d.filter.describe()}' : ''}');
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
          '| ${_term(g.key, aiTerms)} | ${rag.emoji} ${rag.label} | $done/${g.value.length} | ${_mdEscape(_groupHeadline(g.value, l, aiTitles))} |');
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
        b.writeln('- **${_mdEscape(_title(t, aiTitles))}**${_tagSuffix(t, aiTerms)} '
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
            '- **${_mdEscape(_title(t, aiTitles))}** — ${l.subStepsCount(done, t.subSteps.length)}${_tagSuffix(t, aiTerms)}');
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
      b.writeln('### ${_term(g.key, aiTerms)}');
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
            '| ${_term(group, aiTerms)} | ${_mdEscape(_title(t, aiTitles))} | $due | ${t.priority.shortLabel} |');
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
      final level = rag.emoji == '🔴' ? 2 : (rag.emoji == '🟡' ? 1 : 0);
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

  String _tagSuffix(Task t, [Map<String, String>? aiTerms]) =>
      t.tags.isEmpty
          ? ''
          : ' — ${t.tags.map((x) => '#${_term(x, aiTerms)}').join(' ')}';

  /// Translates a project name / tag via the AI-produced [aiTerms] map,
  /// falling back to the raw value when no translation is available. This
  /// is what keeps Chinese project names and tags out of English reports.
  String _term(String raw, Map<String, String>? aiTerms) {
    final tr = aiTerms?[raw];
    return (tr != null && tr.trim().isNotEmpty) ? tr : raw;
  }

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
      for (final e in entry.value.where((e) => e.type == EntryType.blocked)) {
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
    Map<String, String>? aiTerms,
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
    final headTrOpen =
        email ? '<tr style="background-color:#F1F5F9;">' : '<tr>';
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
<div class="meta" style="$metaS">${l.period}: ${d.rangeLabel} · ${l.prepared} ${DateFormat('yyyy-MM-dd').format(DateTime.now())}${d.filter.isActive ? ' · ${l.filters}: ${esc(d.filter.describe())}' : ''}</div>

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
      bodyOpen =
          '''<body style="margin:0; padding:0; background-color:#ffffff; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, 'Noto Sans SC', 'Microsoft YaHei', sans-serif; color:#1E293B;">
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
      bodyOpen =
          '''<body bgcolor="#F8FAFC" style="margin:0;padding:0;background:#F8FAFC;">
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
      b.write('<tr><td class="title" style="$tdT">${esc(_term(g.key, aiTerms))}</td>'
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
        b.write(
            '<li style="$sumLiS"><strong>${esc(_title(t, aiTitles))}</strong>${esc(_tagSuffix(t, aiTerms))} '
            '(${esc(l.doneOn(DateFormat('MM-dd').format(t.completedAt!)))})');
        final sub = _firstSummary(t, aiSummaries);
        if (sub != null) {
          b.write(
              '<ul class="sub" style="$subUlS"><li style="$subLiS">${esc(sub)}</li></ul>');
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
            '<li style="$sumLiS"><strong>${esc(_title(t, aiTitles))}</strong> — ${esc(l.subStepsCount(done, t.subSteps.length))}${esc(_tagSuffix(t, aiTerms))}');
        final sub = _firstSummary(t, aiSummaries);
        if (sub != null) {
          b.write(
              '<ul class="sub" style="$subUlS"><li style="$subLiS">${esc(sub)}</li></ul>');
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
        b.write(
            '<li style="$sumLiS"><strong>${esc(r.title)}</strong> — ${esc(r.detail)}</li>');
      }
      b.write('</ul>');
    }
    b.write('</div>');

    b.write('<h2 style="$h2S">3. ${l.progressDetails}</h2>');
    for (final g in groups.entries) {
      b.write(
          '<div class="group-head" style="$groupHeadS">${esc(_term(g.key, aiTerms))}</div>');
      b.write(
          '$tableOpen$headTrOpen<th style="$thL">${l.item}</th><th class="center" style="$thC">${l.status}</th><th style="$thL">${l.details}</th></tr>');
      for (final t in g.value) {
        b.write(
            '<tr><td class="title" style="$tdT">${esc(_title(t, aiTitles))}</td>'
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
        b.write(
            '<tr><td style="$tdL">${esc(_term(group, aiTerms))}</td><td class="title" style="$tdT">${esc(_title(t, aiTitles))}</td>'
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
        b.write(
            '<li style="$sumLiS"><strong>${esc(a.title)}</strong> — ${esc(a.detail)}</li>');
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
    var body = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    // Align the Progress Details tables (fixed 25%/8%/67% column widths) so
    // every project table lines up identically, per the report spec.
    body = _alignProgressTables(body);
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

  /// Converts the report Markdown (the SAME source as Export.md / Export.html)
  /// into a standalone Gmail-safe HTML document: table-based page layout and
  /// pure inline styles (mail clients strip <style> blocks), 6-digit hex
  /// colors. Content is identical to the other exports — only the styling is
  /// adapted for mail clients.
  String markdownToEmailHtml(String markdown, {String? title}) {
    var body = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    body = _alignProgressTables(body);
    body = _inlineEmailStyles(body);
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
<table width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width:1000px;padding:0 16px;text-align:left;">
<tr>
<td>
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

  /// Injects a fixed-width <colgroup> (Item 25% / Status 8% / Details 67%)
  /// into every 3-column table — these are the Progress Details tables, whose
  /// columns the report spec requires to align identically across projects.
  /// 4-column tables (Status Dashboard, Plan) are left to auto-size.
  static String _alignProgressTables(String html) {
    final tableRe =
        RegExp(r'<table(\s[^>]*)?>([\s\S]*?)</table>', caseSensitive: false);
    return html.replaceAllMapped(tableRe, (m) {
      final full = m.group(0)!;
      final openTag = full.substring(0, full.indexOf('>') + 1);
      final inner = m.group(2) ?? '';
      final firstRow = RegExp(r'<tr(\s[^>]*)?>([\s\S]*?)</tr>',
              caseSensitive: false)
          .firstMatch(inner);
      final cells = firstRow == null
          ? 0
          : RegExp(r'<t[hd](\s[^>]*)?>', caseSensitive: false)
              .allMatches(firstRow.group(2) ?? '')
              .length;
      if (cells != 3) return full;
      return '$openTag<colgroup><col style="width:25%"><col '
          'style="width:8%"><col style="width:67%"></colgroup>$inner</table>';
    });
  }

  /// Injects paste-proof inline styles into the block-level tags produced by
  /// [md.markdownToHtml] so the report renders correctly in Gmail / Outlook
  /// (which strip <style> blocks). Mirrors the visual language of the browser
  /// export. Existing style attributes (e.g. text-align from Markdown table
  /// alignment) are preserved and merged.
  static String _inlineEmailStyles(String html) {
    const styles = <String, String>{
      'h1': 'font-size:24px;font-weight:bold;margin:0 0 4px 0;color:#1E293B;',
      'h2': 'font-size:16px;font-weight:bold;margin:28px 0 10px 0;'
          'border-bottom:1px solid #E2E8F0;padding-bottom:6px;color:#1E293B;',
      'h3': 'font-size:13px;font-weight:bold;margin:16px 0 8px 0;'
          'color:#334155;',
      'p': 'font-size:13px;line-height:1.55;margin:0 0 8px 0;',
      'table': 'width:100%;border-collapse:collapse;border:1px solid #E2E8F0;'
          'margin:0 0 12px 0;',
      'th': 'text-align:left;font-size:11px;text-transform:uppercase;'
          'letter-spacing:.5px;color:#64748B;padding:10px 14px;'
          'background-color:#F1F5F9;border:1px solid #E2E8F0;',
      'td': 'padding:10px 14px;font-size:13px;border:1px solid #E2E8F0;'
          'vertical-align:top;line-height:1.5;',
      'ul': 'margin:6px 0;padding-left:20px;',
      'ol': 'margin:6px 0;padding-left:20px;',
      'li': 'font-size:13px;line-height:1.55;margin-bottom:4px;',
      'blockquote': 'border-left:3px solid #E2E8F0;margin:0 0 12px 0;'
          'padding:8px 14px;color:#475569;',
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
  static String alignProgressTablesForTest(String html) =>
      _alignProgressTables(html);

  @visibleForTesting
  static String inlineEmailStylesForTest(String html) =>
      _inlineEmailStyles(html);

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
