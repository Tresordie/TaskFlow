import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../data/services/ai_service.dart';
import '../../providers/ai_provider.dart';
import '../../providers/task_providers.dart';

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

  bool _parsing = false;
  bool _creating = false;
  String? _error;
  List<ParsedTask> _results = [];

  @override
  void dispose() {
    _notesController.dispose();
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
          content: Text('Created $count task${count == 1 ? '' : 's'} from notes'),
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
              Icon(Icons.auto_awesome, size: 22, color: theme.colorScheme.primary),
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

          // Notes input
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.25),
              ),
            ),
            child: TextField(
              controller: _notesController,
              maxLines: 8,
              minLines: 5,
              style: const TextStyle(fontSize: 13, height: 1.5),
              decoration: InputDecoration(
                hintText:
                    'e.g. Today\'s PVT line review: 1) Metro battery connector torque spec needs re-check (2.5 N·m), station 3 failed 2 units...\n\nMarkdown / plain text / mixed languages all fine.',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
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
                itemBuilder: (context, i) =>
                    _ParsedTaskCard(task: _results[i]),
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

class _ParsedTaskCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
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
                            Text(
                              task.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.6),
                                height: 1.45,
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
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
                                color: theme.colorScheme.primary
                                    .withOpacity(0.7)),
                            const SizedBox(width: 6),
                            Text(
                              '${task.subSteps.length} sub-step${task.subSteps.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary
                                    .withOpacity(0.8),
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
