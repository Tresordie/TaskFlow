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

/// Phase 3 — report generation: aggregate tasks & execution logs over a
/// day / week / month / year and export as Markdown or styled HTML.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.weekly;
  DateTime _anchor = DateTime.now();
  DateTimeRange? _customRange;
  ReportLanguage _lang = ReportLanguage.english;

  // Task filters applied before aggregation (null = all).
  String? _fProject;
  String? _fTag;
  TaskStatus? _fStatus;
  Priority? _fPriority;

  // AI enhancement (log summaries for the Details column + title
  // translation into the report language) is ON by default — it only
  // actually runs when an AI endpoint is configured in Settings.
  bool _useAiSummary = true;

  bool _generating = false;
  bool _exporting = false;
  bool _editing = false;
  ReportData? _data;
  String? _markdown;
  String? _error;
  String? _aiWarning;
  bool _aiWarningNeedsConfig = false;
  Map<Task, String>? _aiSummaries;
  Map<Task, String>? _aiTitles;

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final service = ref.read(reportServiceProvider);
      final filter = ReportFilter(
        project: _fProject,
        tag: _fTag,
        status: _fStatus,
        priority: _fPriority,
      );
      final ReportData data;
      if (_period == ReportPeriod.custom) {
        final range = _customRange;
        if (range == null) {
          setState(() {
            _generating = false;
            _error = 'Pick a custom date range first.';
          });
          return;
        }
        data = await service.generateRange(range.start, range.end,
            filter: filter);
      } else {
        data = await service.generate(_period, _anchor, filter: filter);
      }

      // Optional AI pass: summarize each task's in-period execution logs
      // (Details column) and translate titles into the report language.
      Map<Task, String>? summaries;
      Map<Task, String>? titles;
      String? aiWarning;
      var aiWarningNeedsConfig = false;
      final aiCfg = ref.read(aiConfigProvider);
      if (_useAiSummary) {
        if (aiCfg.isConfigured) {
          final ai = AiService(
            baseUrl: aiCfg.baseUrl,
            apiKey: aiCfg.apiKey,
            model: aiCfg.model,
          );
          final r = await service.aiEnhance(data, ai, _lang);
          summaries = r.summaries;
          titles = r.titles;
          if (r.failed > 0) {
            final total = data.touchedTasks.length;
            aiWarning = r.failed >= total
                ? 'AI enhancement failed for all $total tasks — '
                    '${r.firstError}. Titles and Details fell back to raw '
                    'task content.'
                : 'AI enhancement failed for ${r.failed}/$total tasks — '
                    '${r.firstError}. Those rows use raw task content.';
          }
        } else {
          aiWarning = 'AI summary is enabled but no AI endpoint is '
              'configured — task titles stay in their original language '
              'and Details shows plain log counts. Configure the endpoint '
              'in Settings → AI.';
          aiWarningNeedsConfig = true;
        }
      }

      if (!mounted) return;
      setState(() {
        _data = data;
        _aiSummaries = summaries;
        _aiTitles = titles;
        _aiWarning = aiWarning;
        _aiWarningNeedsConfig = aiWarningNeedsConfig;
        _markdown = service.toMarkdown(
          data,
          lang: _lang,
          aiSummaries: summaries,
          aiTitles: titles,
        );
        _editing = false;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e.toString();
        _aiWarning = null;
      });
    }
  }

  Future<void> _export(String ext) async {
    final data = _data;
    if (data == null) return;
    setState(() => _exporting = true);
    try {
      final service = ref.read(reportServiceProvider);
      final String content;
      final String fileName;
      if (ext == 'md') {
        // Export the current (possibly user-edited) Markdown verbatim.
        content = _markdown ??
            service.toMarkdown(data,
                lang: _lang, aiSummaries: _aiSummaries, aiTitles: _aiTitles);
        fileName = service.suggestFileName(data, ext);
      } else if (ext == 'email') {
        // Dedicated email-client HTML (table layout, no <style> block).
        // Rendered from ReportData — the Gmail-safe template is not derived
        // from the editable Markdown source.
        content = service.toHtml(data,
            lang: _lang,
            aiSummaries: _aiSummaries,
            aiTitles: _aiTitles,
            email: true);
        fileName = service
            .suggestFileName(data, 'html')
            .replaceFirst('.html', '-email.html');
      } else {
        // Convert the current (possibly user-edited) Markdown to styled
        // HTML so the exported file reflects the user's edits.
        final source = _markdown ??
            service.toMarkdown(data,
                lang: _lang, aiSummaries: _aiSummaries, aiTitles: _aiTitles);
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

  void _shiftAnchor(int direction) {
    if (_period == ReportPeriod.custom) return;
    setState(() {
      switch (_period) {
        case ReportPeriod.daily:
          _anchor = _anchor.add(Duration(days: direction));
        case ReportPeriod.weekly:
          _anchor = _anchor.add(Duration(days: 7 * direction));
        case ReportPeriod.monthly:
          _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
        case ReportPeriod.yearly:
          _anchor = DateTime(_anchor.year + direction, 1, 1);
        case ReportPeriod.custom:
          break;
      }
      _data = null;
      _markdown = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _anchor = picked;
        _data = null;
        _markdown = null;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _data = null;
        _markdown = null;
      });
    }
  }

  String get _anchorLabel {
    if (_period == ReportPeriod.custom) {
      final range = _customRange;
      if (range == null) return 'Select range…';
      final f = DateFormat('yyyy-MM-dd');
      return '${f.format(range.start)} → ${f.format(range.end)}';
    }
    final (start, end) = ReportService.rangeFor(_period, _anchor);
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(start)} → ${f.format(end.subtract(const Duration(days: 1)))}';
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
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.6))),
              ),
              for (final o in options)
                DropdownMenuItem<T?>(
                  value: o,
                  child: Text(
                    optionLabel(o),
                    style:
                        TextStyle(fontSize: 12, color: optionColor?.call(o)),
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      );
    }

    void clearReport() => setState(() {
          _data = null;
          _markdown = null;
        });

    final active =
        _fProject != null || _fTag != null || _fStatus != null || _fPriority != null;

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
          value: _fProject,
          options: projects,
          optionLabel: (p) => p,
          optionColor: (p) => colors.projectColor(p),
          onChanged: (v) {
            setState(() => _fProject = v);
            clearReport();
          },
        ),
        const SizedBox(width: 8),
        dropdown<String>(
          label: 'Tag',
          icon: Icons.label_outline,
          value: _fTag,
          options: tags,
          optionLabel: (t) => '#$t',
          optionColor: (t) => colors.tagColor(t),
          onChanged: (v) {
            setState(() => _fTag = v);
            clearReport();
          },
        ),
        const SizedBox(width: 8),
        dropdown<TaskStatus>(
          label: 'Status',
          icon: Icons.track_changes,
          value: _fStatus,
          options: TaskStatus.values,
          optionLabel: (s) => s.label,
          onChanged: (v) {
            setState(() => _fStatus = v);
            clearReport();
          },
        ),
        const SizedBox(width: 8),
        dropdown<Priority>(
          label: 'Priority',
          icon: Icons.flag_outlined,
          value: _fPriority,
          options: Priority.values,
          optionLabel: (p) => p.label,
          onChanged: (v) {
            setState(() => _fPriority = v);
            clearReport();
          },
        ),
        if (active) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _fProject = null;
                _fTag = null;
                _fStatus = null;
                _fPriority = null;
              });
              clearReport();
            },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, fontSize: 18)),
              const Spacer(),
              if (_data != null) ...[
                _editing
                    ? FilledButton.icon(
                        onPressed: () => setState(() => _editing = false),
                        icon: const Icon(Icons.check, size: 15),
                        label: const Text('Done'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => setState(() => _editing = true),
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
                    selected: {_period},
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onSelectionChanged: (s) => setState(() {
                      _period = s.first;
                      _data = null;
                      _markdown = null;
                    }),
                  ),
                  const SizedBox(width: 16),
                  // Date navigation (prev/next hidden in custom mode)
                  if (_period != ReportPeriod.custom)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Previous',
                      onPressed: () => _shiftAnchor(-1),
                      icon: const Icon(Icons.chevron_left, size: 20),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _period == ReportPeriod.custom
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
                              _period == ReportPeriod.custom
                                  ? Icons.date_range
                                  : Icons.calendar_month,
                              size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            _anchorLabel,
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
                  if (_period != ReportPeriod.custom)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Next',
                      onPressed: () => _shiftAnchor(1),
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
                          color: theme.colorScheme.outline.withOpacity(0.35)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReportLanguage>(
                        value: _lang,
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
                          if (l == null || l == _lang) return;
                          setState(() => _lang = l);
                          if (_data != null) _generate();
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
                        color: _useAiSummary
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      label: const Text('AI summary',
                          style: TextStyle(fontSize: 12)),
                      selected: _useAiSummary,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) {
                        setState(() => _useAiSummary = v);
                        if (_data != null) _generate();
                      },
                    ),
                  ),
                ];

                final generateButton = FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded, size: 17),
                  label:
                      Text(_generating ? 'Generating…' : 'Generate Report'),
                );

                // Everything stays on ONE row. When there is room, a Spacer
                // pushes Generate to the right edge; when the window is too
                // narrow, the row scrolls horizontally instead of clipping.
                // The controls + Generate button need ~980px, so only use
                // the fixed single row once there is clearly enough room —
                // below that, scroll so the button is never clipped.
                final fits = constraints.maxWidth >= 1040;
                return fits
                    ? Row(children: [...controls, const Spacer(), generateButton])
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
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Text(_error!,
                  style:
                      const TextStyle(fontSize: 12.5, color: AppColors.error)),
            ),
          ],

          // AI fallback warning — never let silent heuristic fallbacks hide
          // why titles are untranslated or Details lacks AI summaries.
          if (_aiWarning != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.09),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.warning.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _aiWarning!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF92600A),
                          height: 1.45),
                    ),
                  ),
                  if (_aiWarningNeedsConfig)
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
            child: _markdown != null && _data != null
                ? _ReportPreview(
                    data: _data!,
                    markdown: _markdown!,
                    editing: _editing,
                    onMarkdownChanged: (v) => setState(() => _markdown = v),
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
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.35),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Exports land in Documents/TaskFlow/reports/',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.28),
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
                      h1: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 17, fontWeight: FontWeight.w700),
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
