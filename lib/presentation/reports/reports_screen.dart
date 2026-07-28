import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/open_folder.dart';
import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/services/ai_service.dart';
import '../../data/services/report_service.dart';
import '../../providers/ai_provider.dart';
import '../../providers/color_settings_provider.dart';
import '../../providers/task_providers.dart';

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(ref.watch(taskRepositoryProvider));
});

/// Sentinel for [ReportsState.copyWith] so passing an explicit `null`
/// clears a nullable field while omitting it keeps the current value.
const Object _unset = Object();

/// Immutable state for the Reports screen. Held in a (non-autoDispose)
/// [StateNotifierProvider] so it survives route changes: navigating to the
/// task list and back must NOT discard a generated report — it stays until
/// the user presses Generate Report again.
class ReportsState {
  final ReportPeriod period;
  final DateTime anchor;
  final DateTimeRange? customRange;
  final ReportLanguage lang;

  // Task filters applied before aggregation (null = all).
  final String? fProject;
  final String? fTag;
  final TaskStatus? fStatus;
  final Priority? fPriority;

  // Per-task selection: uids of tasks the user UNCHECKED in the picker.
  // Empty = every task in range is included. Keyed by stable Task.uid.
  final Set<String> excludedUids;
  final bool taskPickerOpen;
  final bool useAiSummary;

  // Transient + generated output.
  final bool generating;
  final bool editing;
  final ReportData? data;
  final String? markdown;
  final String? error;
  final String? aiWarning;
  final bool aiWarningNeedsConfig;
  final Map<Task, String>? aiSummaries;
  final Map<Task, String>? aiTitles;
  final Map<String, String>? aiTerms;

  ReportsState({
    this.period = ReportPeriod.weekly,
    DateTime? anchor,
    this.customRange,
    this.lang = ReportLanguage.english,
    this.fProject,
    this.fTag,
    this.fStatus,
    this.fPriority,
    this.excludedUids = const {},
    this.taskPickerOpen = true,
    this.useAiSummary = true,
    this.generating = false,
    this.editing = false,
    this.data,
    this.markdown,
    this.error,
    this.aiWarning,
    this.aiWarningNeedsConfig = false,
    this.aiSummaries,
    this.aiTitles,
    this.aiTerms,
  }) : anchor = anchor ?? DateTime.now();

  ReportsState copyWith({
    ReportPeriod? period,
    DateTime? anchor,
    Object? customRange = _unset,
    ReportLanguage? lang,
    Object? fProject = _unset,
    Object? fTag = _unset,
    Object? fStatus = _unset,
    Object? fPriority = _unset,
    Set<String>? excludedUids,
    bool? taskPickerOpen,
    bool? useAiSummary,
    bool? generating,
    bool? editing,
    Object? data = _unset,
    Object? markdown = _unset,
    Object? error = _unset,
    Object? aiWarning = _unset,
    bool? aiWarningNeedsConfig,
    Object? aiSummaries = _unset,
    Object? aiTitles = _unset,
    Object? aiTerms = _unset,
  }) {
    return ReportsState(
      period: period ?? this.period,
      anchor: anchor ?? this.anchor,
      customRange: identical(customRange, _unset)
          ? this.customRange
          : customRange as DateTimeRange?,
      lang: lang ?? this.lang,
      fProject:
          identical(fProject, _unset) ? this.fProject : fProject as String?,
      fTag: identical(fTag, _unset) ? this.fTag : fTag as String?,
      fStatus:
          identical(fStatus, _unset) ? this.fStatus : fStatus as TaskStatus?,
      fPriority: identical(fPriority, _unset)
          ? this.fPriority
          : fPriority as Priority?,
      excludedUids: excludedUids ?? this.excludedUids,
      taskPickerOpen: taskPickerOpen ?? this.taskPickerOpen,
      useAiSummary: useAiSummary ?? this.useAiSummary,
      generating: generating ?? this.generating,
      editing: editing ?? this.editing,
      data: identical(data, _unset) ? this.data : data as ReportData?,
      markdown:
          identical(markdown, _unset) ? this.markdown : markdown as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      aiWarning:
          identical(aiWarning, _unset) ? this.aiWarning : aiWarning as String?,
      aiWarningNeedsConfig: aiWarningNeedsConfig ?? this.aiWarningNeedsConfig,
      aiSummaries: identical(aiSummaries, _unset)
          ? this.aiSummaries
          : aiSummaries as Map<Task, String>?,
      aiTitles: identical(aiTitles, _unset)
          ? this.aiTitles
          : aiTitles as Map<Task, String>?,
      aiTerms: identical(aiTerms, _unset)
          ? this.aiTerms
          : aiTerms as Map<String, String>?,
    );
  }
}

/// Owns the Reports screen state + the generate pipeline so the widget can
/// be torn down by navigation without losing the current report.
class ReportController extends StateNotifier<ReportsState> {
  ReportController(this.ref) : super(ReportsState());

  final Ref ref;

  // ------------------------------------------------------------------
  // Derived helpers (pure functions of [state]).

  /// The active [start, end) range, mirroring how generate()/generateRange()
  /// resolve it (the custom end day is extended to cover its full 24h).
  (DateTime, DateTime) get currentRange {
    if (state.period == ReportPeriod.custom) {
      final r = state.customRange;
      if (r == null) {
        final now = DateTime.now();
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day)
        );
      }
      final s = DateTime(r.start.year, r.start.month, r.start.day);
      final e = DateTime(r.end.year, r.end.month, r.end.day)
          .add(const Duration(days: 1));
      return (s, e);
    }
    return ReportService.rangeFor(state.period, state.anchor);
  }

  /// Tasks created inside the current range — the checkbox picker's list.
  List<Task> tasksInRange(List<Task> allTasks) {
    final (start, end) = currentRange;
    return allTasks
        .where((t) => !t.createdAt.isBefore(start) && t.createdAt.isBefore(end))
        .toList();
  }

  String get anchorLabel {
    if (state.period == ReportPeriod.custom) {
      final range = state.customRange;
      if (range == null) return 'Select range…';
      final f = DateFormat('yyyy-MM-dd');
      return '${f.format(range.start)} → ${f.format(range.end)}';
    }
    final (start, end) = ReportService.rangeFor(state.period, state.anchor);
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(start)} → ${f.format(end.subtract(const Duration(days: 1)))}';
  }

  // ------------------------------------------------------------------
  // Control mutations. Contract: every control (period, date, filters,
  // selection, language, AI toggle) only configures the NEXT generation.
  // The displayed report is replaced SOLELY by pressing Generate Report —
  // no control change clears or regenerates it.

  void setPeriod(ReportPeriod p) => state = state.copyWith(period: p);

  void shiftAnchor(int direction) {
    if (state.period == ReportPeriod.custom) return;
    final a = state.anchor;
    final DateTime next;
    switch (state.period) {
      case ReportPeriod.daily:
        next = a.add(Duration(days: direction));
      case ReportPeriod.weekly:
        next = a.add(Duration(days: 7 * direction));
      case ReportPeriod.monthly:
        next = DateTime(a.year, a.month + direction, 1);
      case ReportPeriod.yearly:
        next = DateTime(a.year + direction, 1, 1);
      case ReportPeriod.custom:
        return;
    }
    state = state.copyWith(anchor: next);
  }

  void setAnchor(DateTime d) => state = state.copyWith(anchor: d);

  void setCustomRange(DateTimeRange r) =>
      state = state.copyWith(customRange: r);

  void setLang(ReportLanguage l) => state = state.copyWith(lang: l);

  void setFilterProject(String? v) => state = state.copyWith(fProject: v);
  void setFilterTag(String? v) => state = state.copyWith(fTag: v);
  void setFilterStatus(TaskStatus? v) => state = state.copyWith(fStatus: v);
  void setFilterPriority(Priority? v) => state = state.copyWith(fPriority: v);
  void clearFilters() => state = state.copyWith(
      fProject: null, fTag: null, fStatus: null, fPriority: null);

  /// Checkbox changes only affect the NEXT generation — the currently
  /// displayed report is kept until the user presses Generate Report again.
  void toggleTask(String uid, bool checked) {
    final set = Set<String>.from(state.excludedUids);
    if (checked) {
      set.remove(uid);
    } else {
      set.add(uid);
    }
    state = state.copyWith(excludedUids: set);
  }

  void setAllSelected(bool selected) {
    final all = ref.read(taskListProvider).valueOrNull ?? const <Task>[];
    final set =
        selected ? <String>{} : tasksInRange(all).map((t) => t.uid).toSet();
    state = state.copyWith(excludedUids: set);
  }

  void setTaskPickerOpen(bool v) => state = state.copyWith(taskPickerOpen: v);
  void setUseAiSummary(bool v) => state = state.copyWith(useAiSummary: v);
  void setEditing(bool v) => state = state.copyWith(editing: v);
  void setMarkdown(String v) => state = state.copyWith(markdown: v);

  // ------------------------------------------------------------------
  // Generate pipeline (moved verbatim from the old widget `_generate`).

  Future<void> generate() async {
    state = state.copyWith(generating: true, error: null);
    try {
      final service = ref.read(reportServiceProvider);
      final filter = ReportFilter(
        project: state.fProject,
        tag: state.fTag,
        status: state.fStatus,
        priority: state.fPriority,
      );
      // Checkbox selection: null = every task in range; otherwise only the
      // checked ones (tasks in range minus the excluded uids).
      final Set<String>? onlyUids = state.excludedUids.isEmpty
          ? null
          : tasksInRange(
                  ref.read(taskListProvider).valueOrNull ?? const <Task>[])
              .where((t) => !state.excludedUids.contains(t.uid))
              .map((t) => t.uid)
              .toSet();
      final ReportData data;
      if (state.period == ReportPeriod.custom) {
        final range = state.customRange;
        if (range == null) {
          state = state.copyWith(
              generating: false, error: 'Pick a custom date range first.');
          return;
        }
        data = await service.generateRange(range.start, range.end,
            filter: filter, onlyUids: onlyUids);
      } else {
        data = await service.generate(state.period, state.anchor,
            filter: filter, onlyUids: onlyUids);
      }

      // AI pass. Two tiers:
      //  1. FULL generation — one LLM call produces the entire report
      //     following the spec rules (weekly_report_ai_summary_prompts.md):
      //     deep log comprehension, synthesis, task decomposition, etc.
      //  2. FALLBACK — if the full call fails (timeout, API error, empty
      //     reply), fall back to the deterministic template with per-task
      //     AI enhancement (title translation + short summaries).
      Map<Task, String>? summaries;
      Map<Task, String>? titles;
      Map<String, String>? terms;
      String? aiWarning;
      var aiWarningNeedsConfig = false;
      String? markdown;
      final aiCfg = ref.read(aiConfigProvider);
      if (state.useAiSummary) {
        if (aiCfg.isConfigured) {
          final ai = AiService(
            baseUrl: aiCfg.baseUrl,
            apiKey: aiCfg.apiKey,
            model: aiCfg.model,
          );
          // Tier 1: full spec-driven report generation.
          try {
            markdown = await ai.generateFullReport(
              systemPrompt: ReportService.fullReportPrompt(state.lang),
              taskData: service.formatTaskData(data),
            );
          } catch (e) {
            // Tier 2: template + per-task enhancement.
            aiWarning = 'Full AI report generation failed (${e.toString()}). '
                'Fell back to the template with per-task AI summaries.';
          }
          if (markdown == null) {
            final r = await service.aiEnhance(data, ai, state.lang);
            summaries = r.summaries;
            titles = r.titles;
            terms = r.terms;
            if (r.failed > 0) {
              final total = data.touchedTasks.length;
              aiWarning = '$aiWarning\n'
                  'AI enhancement failed for ${r.failed}/$total tasks — '
                  '${r.firstError}. Those rows use raw task content.';
            }
          }
        } else {
          aiWarning = 'AI summary is enabled but no AI endpoint is '
              'configured — task titles stay in their original language '
              'and Details shows plain log counts. Configure the endpoint '
              'in Settings → AI.';
          aiWarningNeedsConfig = true;
        }
      }

      state = state.copyWith(
        data: data,
        aiSummaries: summaries,
        aiTitles: titles,
        aiTerms: terms,
        aiWarning: aiWarning,
        aiWarningNeedsConfig: aiWarningNeedsConfig,
        markdown: markdown ??
            service.toMarkdown(
              data,
              lang: state.lang,
              aiSummaries: summaries,
              aiTitles: titles,
              aiTerms: terms,
            ),
        editing: false,
        generating: false,
      );
    } catch (e) {
      state = state.copyWith(
        generating: false,
        error: e.toString(),
        aiWarning: null,
      );
    }
  }
}

final reportControllerProvider =
    StateNotifierProvider<ReportController, ReportsState>(
        (ref) => ReportController(ref));

/// Phase 3 — report generation: aggregate tasks & execution logs over a
/// day / week / month / year and export as Markdown or styled HTML.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  // All durable state (controls, selection, generated report) lives in
  // [reportControllerProvider] so it survives route changes. Only the
  // transient export-in-progress flag stays widget-local.
  bool _exporting = false;

  Future<void> _export(String ext) async {
    final s = ref.read(reportControllerProvider);
    final data = s.data;
    if (data == null) return;
    setState(() => _exporting = true);
    try {
      final service = ref.read(reportServiceProvider);
      final String content;
      final String fileName;
      if (ext == 'md') {
        // Export the current (possibly user-edited) Markdown verbatim.
        content = s.markdown ??
            service.toMarkdown(data,
                lang: s.lang,
                aiSummaries: s.aiSummaries,
                aiTitles: s.aiTitles,
                aiTerms: s.aiTerms);
        fileName = service.suggestFileName(data, ext);
      } else if (ext == 'email') {
        // Dedicated email-client HTML (table layout, no <style> block).
        // Rendered from ReportData — the Gmail-safe template is not derived
        // from the editable Markdown source.
        content = service.toHtml(data,
            lang: s.lang,
            aiSummaries: s.aiSummaries,
            aiTitles: s.aiTitles,
            aiTerms: s.aiTerms,
            email: true);
        fileName = service
            .suggestFileName(data, 'html')
            .replaceFirst('.html', '-email.html');
      } else {
        // Convert the current (possibly user-edited) Markdown to styled
        // HTML so the exported file reflects the user's edits.
        final source = s.markdown ??
            service.toMarkdown(data,
                lang: s.lang,
                aiSummaries: s.aiSummaries,
                aiTitles: s.aiTitles,
                aiTerms: s.aiTerms);
        content = service.markdownToStyledHtml(source, title: data.titlePrefix);
        fileName = service.suggestFileName(data, ext);
      }
      final file = await service.export(fileName, content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved: ${file.path}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Open folder',
            // launchUrl(Uri.file(...)) blocks the UI thread on Windows
            // ("Not responding"); openFolder spawns explorer fire-and-forget.
            onPressed: () => openFolder(file.parent.path),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickDate() async {
    final notifier = ref.read(reportControllerProvider.notifier);
    final picked = await showDatePicker(
      context: context,
      initialDate: ref.read(reportControllerProvider).anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) notifier.setAnchor(picked);
  }

  Future<void> _pickRange() async {
    final notifier = ref.read(reportControllerProvider.notifier);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: ref.read(reportControllerProvider).customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) notifier.setCustomRange(picked);
  }

  /// Filter row under the main controls: narrow the report down to one
  /// project / tag / status / priority before aggregation (null = all).
  Widget _buildFilterRow(ThemeData theme) {
    final tasks = ref.watch(taskListProvider).valueOrNull ?? const <Task>[];
    final colors = ref.watch(colorSettingsProvider);
    final projects = tasks
        .map((t) => t.project.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final tags = tasks.expand((t) => t.tags).toSet().toList()..sort();

    Widget dropdown<T>({
      required String label,
      required IconData icon,
      required T? value,
      required List<T> options,
      required String Function(T) optionLabel,
      required ValueChanged<T?> onChanged,
      Color? Function(T)? optionColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value != null
                ? theme.colorScheme.primary.withOpacity(0.5)
                : theme.colorScheme.outline.withOpacity(0.35),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T?>(
            value: value,
            isDense: true,
            icon: const Icon(Icons.arrow_drop_down, size: 16),
            hint: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
            items: [
              DropdownMenuItem<T?>(
                value: null,
                child: Text('All',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.6))),
              ),
              for (final o in options)
                DropdownMenuItem<T?>(
                  value: o,
                  child: Text(
                    optionLabel(o),
                    style: TextStyle(fontSize: 12, color: optionColor?.call(o)),
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      );
    }

    final s = ref.watch(reportControllerProvider);
    final notifier = ref.read(reportControllerProvider.notifier);

    final active = s.fProject != null ||
        s.fTag != null ||
        s.fStatus != null ||
        s.fPriority != null;

    return Row(
      children: [
        Icon(Icons.filter_list,
            size: 15, color: theme.colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 8),
        Text('Filter:',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
        const SizedBox(width: 8),
        dropdown<String>(
          label: 'Project',
          icon: Icons.folder_outlined,
          value: s.fProject,
          options: projects,
          optionLabel: (p) => p,
          optionColor: (p) => colors.projectColor(p),
          onChanged: notifier.setFilterProject,
        ),
        const SizedBox(width: 8),
        dropdown<String>(
          label: 'Tag',
          icon: Icons.label_outline,
          value: s.fTag,
          options: tags,
          optionLabel: (t) => '#$t',
          optionColor: (t) => colors.tagColor(t),
          onChanged: notifier.setFilterTag,
        ),
        const SizedBox(width: 8),
        dropdown<TaskStatus>(
          label: 'Status',
          icon: Icons.track_changes,
          value: s.fStatus,
          options: TaskStatus.values,
          optionLabel: (st) => st.label,
          onChanged: notifier.setFilterStatus,
        ),
        const SizedBox(width: 8),
        dropdown<Priority>(
          label: 'Priority',
          icon: Icons.flag_outlined,
          value: s.fPriority,
          options: Priority.values,
          optionLabel: (p) => p.label,
          onChanged: notifier.setFilterPriority,
        ),
        if (active) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: notifier.clearFilters,
            icon: const Icon(Icons.clear, size: 13),
            label: const Text('Clear', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }

  /// Per-task picker: lists the tasks created inside the current date range
  /// with a checkbox each, so the user chooses which tasks Generate Report
  /// summarizes. Everything is selected by default (empty exclusion set).
  Widget _buildTaskSelection(ThemeData theme) {
    final s = ref.watch(reportControllerProvider);
    final notifier = ref.read(reportControllerProvider.notifier);
    final allTasks = ref.watch(taskListProvider).valueOrNull ?? const <Task>[];
    final inRange = notifier.tasksInRange(allTasks);
    final selectedCount =
        inRange.where((t) => !s.excludedUids.contains(t.uid)).length;
    final allSelected = inRange.isNotEmpty && selectedCount == inRange.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fact_check_outlined,
                size: 15, color: theme.colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              inRange.isEmpty
                  ? 'Tasks: none created in this range'
                  : 'Tasks: $selectedCount of ${inRange.length} selected',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            const Spacer(),
            if (inRange.isNotEmpty) ...[
              TextButton(
                onPressed: () => notifier.setAllSelected(!allSelected),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(allSelected ? 'Deselect all' : 'Select all',
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 2),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => notifier.setTaskPickerOpen(!s.taskPickerOpen),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    s.taskPickerOpen ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (s.taskPickerOpen && inRange.isNotEmpty) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: Scrollbar(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final t in inRange) _taskSelectionRow(theme, t),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _taskSelectionRow(ThemeData theme, Task t) {
    final s = ref.watch(reportControllerProvider);
    final notifier = ref.read(reportControllerProvider.notifier);
    final checked = !s.excludedUids.contains(t.uid);
    return InkWell(
      onTap: () => notifier.toggleTask(t.uid, !checked),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => notifier.toggleTask(t.uid, v ?? true),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: checked
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.45),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              t.status.label,
              style: TextStyle(
                fontSize: 10.5,
                color: theme.colorScheme.onSurface.withOpacity(0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(reportControllerProvider);
    final notifier = ref.read(reportControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.summarize_outlined,
                  size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text('Reports',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700, fontSize: 18)),
              const Spacer(),
              if (s.data != null) ...[
                s.editing
                    ? FilledButton.icon(
                        onPressed: () => notifier.setEditing(false),
                        icon: const Icon(Icons.check, size: 15),
                        label: const Text('Done'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => notifier.setEditing(true),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('Edit'),
                      ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export('md'),
                  icon: _exporting
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.description_outlined, size: 15),
                  label: const Text('Export .md'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _exporting ? null : () => _export('html'),
                  icon: const Icon(Icons.html_outlined, size: 15),
                  label: const Text('Export .html'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export('email'),
                  icon: const Icon(Icons.mail_outline, size: 15),
                  label: const Text('Email .html'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Controls
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final controls = <Widget>[
                      // Period selector
                      SegmentedButton<ReportPeriod>(
                        segments: [
                          for (final p in ReportPeriod.values)
                            ButtonSegment(
                              value: p,
                              label: Text(p.label,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                        selected: {s.period},
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onSelectionChanged: (sel) =>
                            notifier.setPeriod(sel.first),
                      ),
                      const SizedBox(width: 16),
                      // Date navigation (prev/next hidden in custom mode)
                      if (s.period != ReportPeriod.custom)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Previous',
                          onPressed: () => notifier.shiftAnchor(-1),
                          icon: const Icon(Icons.chevron_left, size: 20),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: s.period == ReportPeriod.custom
                            ? _pickRange
                            : _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  s.period == ReportPeriod.custom
                                      ? Icons.date_range
                                      : Icons.calendar_month,
                                  size: 14,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                notifier.anchorLabel,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (s.period != ReportPeriod.custom)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Next',
                          onPressed: () => notifier.shiftAnchor(1),
                          icon: const Icon(Icons.chevron_right, size: 20),
                        ),
                      const SizedBox(width: 12),
                      // Report language
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  theme.colorScheme.outline.withOpacity(0.35)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ReportLanguage>(
                            value: s.lang,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            items: [
                              for (final l in ReportLanguage.values)
                                DropdownMenuItem(
                                  value: l,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.language,
                                          size: 13,
                                          color: theme.colorScheme.primary),
                                      const SizedBox(width: 6),
                                      Text(l.label,
                                          style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (l) {
                              if (l == null || l == s.lang) return;
                              notifier.setLang(l);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // AI summary toggle
                      Tooltip(
                        message: ref.watch(aiConfigProvider).isConfigured
                            ? 'On by default: AI summarizes each task\'s '
                                'in-period execution logs (Details column) and '
                                'translates titles into the report language'
                            : 'Configure the AI endpoint in Settings first — '
                                'without it, titles stay in their original '
                                'language and Details shows plain log counts',
                        child: FilterChip(
                          avatar: Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: s.useAiSummary
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          label: const Text('AI summary',
                              style: TextStyle(fontSize: 12)),
                          selected: s.useAiSummary,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: notifier.setUseAiSummary,
                        ),
                      ),
                    ];

                    final generateButton = FilledButton.icon(
                      onPressed: s.generating ? null : notifier.generate,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      icon: s.generating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow_rounded, size: 17),
                      label: Text(
                          s.generating ? 'Generating…' : 'Generate Report'),
                    );

                    // Everything stays on ONE row. When there is room, a Spacer
                    // pushes Generate to the right edge; when the window is too
                    // narrow, the row scrolls horizontally instead of clipping.
                    // The controls + Generate button need ~980px, so only use
                    // the fixed single row once there is clearly enough room —
                    // below that, scroll so the button is never clipped.
                    final fits = constraints.maxWidth >= 1040;
                    return fits
                        ? Row(children: [
                            ...controls,
                            const Spacer(),
                            generateButton
                          ])
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ...controls,
                                const SizedBox(width: 16),
                                generateButton,
                              ],
                            ),
                          );
                  },
                ),
                const SizedBox(height: 10),
                _buildFilterRow(theme),
                const SizedBox(height: 10),
                _buildTaskSelection(theme),
              ],
            ),
          ),

          if (s.error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Text(s.error!,
                  style:
                      const TextStyle(fontSize: 12.5, color: AppColors.error)),
            ),
          ],

          // AI fallback warning — never let silent heuristic fallbacks hide
          // why titles are untranslated or Details lacks AI summaries.
          if (s.aiWarning != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.aiWarning!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF92600A),
                          height: 1.45),
                    ),
                  ),
                  if (s.aiWarningNeedsConfig)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => context.go('/settings'),
                      child: const Text('Open Settings',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Preview / empty state
          Expanded(
            child: s.markdown != null && s.data != null
                ? _ReportPreview(
                    data: s.data!,
                    markdown: s.markdown!,
                    editing: s.editing,
                    onMarkdownChanged: notifier.setMarkdown,
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insights_outlined,
                            size: 48,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.15)),
                        const SizedBox(height: 12),
                        Text(
                          'Pick a period and press Generate Report',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.35),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Exports land in Documents/TaskFlow/reports/',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.28),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReportPreview extends StatefulWidget {
  final ReportData data;
  final String markdown;
  final bool editing;
  final ValueChanged<String> onMarkdownChanged;

  const _ReportPreview({
    required this.data,
    required this.markdown,
    required this.editing,
    required this.onMarkdownChanged,
  });

  @override
  State<_ReportPreview> createState() => _ReportPreviewState();
}

class _ReportPreviewState extends State<_ReportPreview> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.markdown;
  }

  @override
  void didUpdateWidget(covariant _ReportPreview old) {
    super.didUpdateWidget(old);
    if (widget.editing && !old.editing) {
      // Just entered edit mode → load the latest markdown into the editor.
      _controller.text = widget.markdown;
    } else if (!widget.editing && widget.markdown != _controller.text) {
      // In view mode keep the editor buffer in sync so the next edit
      // session starts from the latest content (e.g. after regeneration).
      _controller.text = widget.markdown;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick stat chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(
                label: 'Touched',
                value: '${widget.data.totalTouched}',
                color: theme.colorScheme.primary),
            _StatChip(
                label: 'Done',
                value: '${widget.data.completed.length}',
                color: AppColors.success),
            _StatChip(
                label: 'In progress',
                value: '${widget.data.inProgress.length}',
                color: AppColors.info),
            _StatChip(
                label: 'Overdue',
                value: '${widget.data.overdue.length}',
                color: widget.data.overdue.isEmpty
                    ? theme.colorScheme.onSurface.withOpacity(0.4)
                    : AppColors.error),
            _StatChip(
                label: 'Rate',
                value:
                    '${(widget.data.completionRate * 100).toStringAsFixed(0)}%',
                color: theme.colorScheme.primary),
          ],
        ),
        const SizedBox(height: 12),
        // Markdown preview / editor
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: widget.editing
                      ? theme.colorScheme.primary.withOpacity(0.4)
                      : theme.colorScheme.outline.withOpacity(0.25)),
            ),
            child: widget.editing
                ? TextField(
                    controller: _controller,
                    onChanged: widget.onMarkdownChanged,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontFamily: 'Consolas, Menlo, Courier New, monospace',
                      fontSize: 12.5,
                      height: 1.5,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  )
                : Markdown(
                    data: widget.markdown,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                      tableHead: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                      tableBody:
                          theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      h1: theme.textTheme.titleLarge
                          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                      h2: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                      h3: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
                      blockquote: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              )),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.85),
              )),
        ],
      ),
    );
  }
}
