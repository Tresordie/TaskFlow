import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markdown/html_sanitize.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../data/services/ai_service.dart';
import '../../providers/ai_provider.dart';
import '../../providers/color_settings_provider.dart';
import '../../providers/task_providers.dart';
import '../shared/markdown_input.dart';
import '../shared/selectable_markdown_body.dart';

/// Phase 2 — AI note parsing.
/// Paste raw notes → LLM extracts structured tasks → one-click create.
class AiParseScreen extends ConsumerStatefulWidget {
  const AiParseScreen({super.key});

  @override
  ConsumerState<AiParseScreen> createState() => _AiParseScreenState();
}

class _AiParseScreenState extends ConsumerState<AiParseScreen> {
  final _notesController = TextEditingController();
  final _scrollController = ScrollController();
  late final FocusNode _notesFocus;

  bool _parsing = false;
  bool _creating = false;
  bool _previewMode = false;
  String? _error;
  List<ParsedTask> _results = [];

  // Resizable notes input area height (logical pixels) — drag the grip
  // handle below the field, mirroring the Work Log input behavior.
  double _notesHeight = 200;
  static const double _minNotesHeight = 100;
  static const double _maxNotesHeight = 500;

  @override
  void initState() {
    super.initState();
    _notesFocus = markdownIndentFocusNode(_notesController);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _notesFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final notes = _notesController.text.trim();
    if (notes.isEmpty) return;

    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      setState(() => _error =
          'AI is not configured yet. Open Settings → AI Assistant to set your API endpoint first.');
      return;
    }

    setState(() {
      _parsing = true;
      _error = null;
    });

    try {
      final service = AiService(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      );
      final tasks = await service.parseNotes(notes);
      setState(() {
        _results = tasks;
        _parsing = false;
        if (tasks.isEmpty) {
          _error = 'No actionable tasks found in the notes.';
        }
      });
    } catch (e) {
      setState(() {
        _parsing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createSelected() async {
    final selected = _results.where((t) => t.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _creating = true);
    try {
      final notifier = ref.read(taskListProvider.notifier);
      final count = await notifier.createTasks([
        for (final t in selected)
          TaskDraft(
            title: t.title,
            description: t.description.isEmpty ? null : t.description,
            priority: t.priority,
            tags: t.tags,
            subSteps: t.subSteps,
          ),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Created $count task${count == 1 ? '' : 's'} from notes'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _creating = false;
        _results = [];
        _notesController.clear();
      });
      context.go('/today');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create tasks: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  int get _selectedCount => _results.where((t) => t.selected).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(aiConfigProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text('AI Parse',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700, fontSize: 18)),
              const Spacer(),
              if (!config.isConfigured)
                TextButton.icon(
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Configure AI'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Paste raw notes — meeting minutes, test logs, chat excerpts — and let AI turn them into structured tasks.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 16),

          // Notes input with Write / Preview tabs
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tab bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
                  child: Row(
                    children: [
                      _InputTab(
                        label: 'Write',
                        icon: Icons.edit_note,
                        active: !_previewMode,
                        onTap: () => setState(() => _previewMode = false),
                      ),
                      const SizedBox(width: 4),
                      _InputTab(
                        label: 'Preview',
                        icon: Icons.visibility_outlined,
                        active: _previewMode,
                        onTap: () => setState(() => _previewMode = true),
                      ),
                      const Spacer(),
                      Text(
                        'Markdown supported',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                ),
                // Formatting toolbar (Write mode only)
                if (!_previewMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 10, 0),
                    child: MarkdownToolbar(
                      controller: _notesController,
                      refocus: _notesFocus,
                    ),
                  ),
                // Content area
                if (_previewMode)
                  Container(
                    height: _notesHeight,
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    child: _notesController.text.trim().isEmpty
                        ? Text(
                            'Nothing to preview yet…',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.35),
                            ),
                          )
                        : SingleChildScrollView(
                            primary: false,
                            // v1.4.79: whole-document SelectableText preview —
                            // multi-line drag-select, Select all, right-click
                            // Copy / Select all / Copy as Markdown.
                            child: SelectableMarkdownBody(
                              data: sanitizeHtmlInMarkdown(
                                  _notesController.text),
                              hardenLineBreaks: true,
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(theme).copyWith(
                                p: const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ),
                          ),
                  )
                else
                  SizedBox(
                    height: _notesHeight,
                    child: TextField(
                      controller: _notesController,
                      focusNode: _notesFocus,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        fontFamily: 'Consolas',
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Today\'s PVT line review: 1) Metro battery connector torque spec needs re-check (2.5 N·m), station 3 failed 2 units...\n\nMarkdown / plain text / mixed languages all fine.',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Consolas',
                          color: theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                // Resize grip handle — drag up/down to resize the notes
                // input area (same pattern as the Work Log input).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _notesHeight = (_notesHeight + details.delta.dy)
                          .clamp(_minNotesHeight, _maxNotesHeight);
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: SizedBox(
                      height: 10,
                      width: double.infinity,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 3,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outline.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action row
          Row(
            children: [
              FilledButton.icon(
                onPressed: (_parsing || _creating) ? null : _parse,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: _parsing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_parsing ? 'Parsing…' : 'Parse with AI'),
              ),
              const SizedBox(width: 12),
              if (_results.isNotEmpty) ...[
                TextButton(
                  onPressed: () => setState(() {
                    final all = _selectedCount == _results.length;
                    for (final t in _results) {
                      t.selected = !all;
                    }
                  }),
                  child: Text(_selectedCount == _results.length
                      ? 'Deselect all'
                      : 'Select all'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: (_creating || _selectedCount == 0)
                      ? null
                      : _createSelected,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  icon: _creating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_task, size: 16),
                  label: Text(_creating
                      ? 'Creating…'
                      : 'Create $_selectedCount task${_selectedCount == 1 ? '' : 's'}'),
                ),
              ],
            ],
          ),

          // Error
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Results
          if (_results.isNotEmpty) ...[
            Text(
              'Extracted ${_results.length} task${_results.length == 1 ? '' : 's'} — review and uncheck what you don\'t need:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _ParsedTaskCard(task: _results[i]),
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notes_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurface.withOpacity(0.15)),
                    const SizedBox(height: 12),
                    Text(
                      _parsing ? 'Thinking…' : 'Parsed tasks will appear here',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.35),
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

class _ParsedTaskCard extends ConsumerWidget {
  final ParsedTask task;

  const _ParsedTaskCard({required this.task});

  Color _priorityColor(Priority p) {
    switch (p) {
      case Priority.p0Critical:
        return AppColors.p0Critical;
      case Priority.p1High:
        return AppColors.p1High;
      case Priority.p2Medium:
        return AppColors.p2Medium;
      case Priority.p3Low:
        return AppColors.p3Low;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = ref.watch(colorSettingsProvider);
    final pColor = _priorityColor(task.priority);

    return StatefulBuilder(
      builder: (context, setLocal) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: task.selected ? 1.0 : 0.45,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: task.selected
                    ? theme.colorScheme.primary.withOpacity(0.35)
                    : theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: task.selected,
                        onChanged: (v) {
                          task.selected = v ?? true;
                          setLocal(() {});
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            // v1.4.75: whole-description SelectableText —
                            // multi-line drag-select, Select all, right-click
                            // Copy / Copy as Markdown. HTML sanitized first.
                            SelectableMarkdownBody(
                              data: sanitizeHtmlInMarkdown(task.description),
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(theme).copyWith(
                                p: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  height: 1.45,
                                ),
                                pPadding: const EdgeInsets.only(bottom: 4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Priority chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        task.priority.shortLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: pColor,
                        ),
                      ),
                    ),
                  ],
                ),

                // Tags
                if (task.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in task.tags)
                        Builder(builder: (context) {
                          final tagColor =
                              colors.tagColor(tag) ?? theme.colorScheme.primary;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: tagColor,
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ],

                // Sub-steps preview
                if (task.subSteps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.checklist,
                                size: 13,
                                color:
                                    theme.colorScheme.primary.withOpacity(0.7)),
                            const SizedBox(width: 6),
                            Text(
                              '${task.subSteps.length} sub-step${task.subSteps.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    theme.colorScheme.primary.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final s in task.subSteps)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('•  ',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.4),
                                    )),
                                Expanded(
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.65),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InputTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _InputTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.45)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
