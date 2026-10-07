import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../shared/markdown_editor_field.dart';
import '../shared/markdown_input.dart';
import '../shared/suggestion_field.dart';

/// v1.12.46: the full-field New Task form — the kanban column inline-add and
/// the top quick-add bar both keep their fast "type + Enter" path, and this
/// dialog is the "more options" escape hatch: title, project, due date,
/// description (Markdown), priority, tags and sub-tasks in one place.
///
/// The shell follows [EditTaskDialog] (Dialog + 520 max width + scroll) so
/// the two task forms read as one family. Opened via a plain
/// `showDialog<String>`; pops the created title on success, null on cancel.
///
/// The `initial*` values carry the caller's context: a column "+" in the
/// Status dimension pre-fills that status, the Priority dimension the
/// priority, the Project dimension the project — the user can still change
/// any of them here.
class CreateTaskDialog extends ConsumerStatefulWidget {
  final String initialTitle;
  final TaskStatus initialStatus;
  final Priority initialPriority;
  final String initialProject;
  final DateTime? initialDueDate;

  const CreateTaskDialog({
    super.key,
    this.initialTitle = '',
    this.initialStatus = TaskStatus.planned,
    this.initialPriority = Priority.p2Medium,
    this.initialProject = '',
    this.initialDueDate,
  });

  @override
  ConsumerState<CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends ConsumerState<CreateTaskDialog> {
  late final TextEditingController _titleController;
  final _descController = TextEditingController();
  late final FocusNode _descFocus;
  final _projectController = TextEditingController();
  final _tagController = TextEditingController();
  final _subStepController = TextEditingController();
  late Priority _priority;
  DateTime? _dueDate;
  final List<String> _subSteps = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    // Keep Create enabled/disabled in sync with the title.
    _titleController.addListener(_onTitleChanged);
    _descFocus = markdownIndentFocusNode(_descController);
    _projectController.text = widget.initialProject;
    _priority = widget.initialPriority;
    _dueDate = widget.initialDueDate;
  }

  void _onTitleChanged() => setState(() {});

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _descController.dispose();
    _descFocus.dispose();
    _projectController.dispose();
    _tagController.dispose();
    _subStepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (same language as EditTaskDialog).
                Row(
                  children: [
                    Icon(Icons.add_task,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('New Task', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Title
                Text('Title', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'What needs to be done?',
                  ),
                  onSubmitted: (_) => _create(),
                ),
                const SizedBox(height: 16),

                // Project (history autocomplete, same field as the edit dialog)
                Text('Project', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                SuggestionField(
                  controller: _projectController,
                  suggestions: ref.watch(distinctProjectsProvider),
                  optionIcon: Icons.folder_outlined,
                  headerText: 'Recent projects',
                  decoration: const InputDecoration(
                    hintText: 'Project name (e.g. Cosmo, Metro)',
                    prefixIcon: Icon(Icons.folder_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 16),

                // Due date picker (past dates allowed — a new task can be
                // back-filled; same affordance as EditTaskDialog).
                Text('Due Date', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Row(
                  children: [
                    InkWell(
                      onTap: _pickDueDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: _dueDate != null
                              ? theme.colorScheme.primary.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _dueDate != null
                                ? theme.colorScheme.primary.withOpacity(0.4)
                                : theme.colorScheme.outline.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: _dueDate != null
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _dueDate != null
                                  ? DateFormat('yyyy-MM-dd (EEE)')
                                      .format(_dueDate!)
                                  : 'No due date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _dueDate != null
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_dueDate != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.45),
                        ),
                        tooltip: 'Clear due date',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _dueDate = null),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Description — Markdown + rich-text with live Write/Preview
                Text('Description', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                MarkdownToolbar(
                  controller: _descController,
                  refocus: _descFocus,
                ),
                const SizedBox(height: 8),
                MarkdownEditorField(
                  controller: _descController,
                  focusNode: _descFocus,
                  maxLines: 4,
                  minLines: 2,
                  hintText: 'Add more details (optional, Markdown supported)',
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),

                // Priority selector
                Text('Priority', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: Priority.values.map((p) {
                    final color = AppColors.priorityColor(p.index);
                    final isSelected = _priority == p;
                    return ChoiceChip(
                      label: Text(p.label),
                      selected: isSelected,
                      selectedColor: color.withOpacity(0.18),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? color
                            : theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? color.withOpacity(0.5)
                            : theme.colorScheme.outline.withOpacity(0.4),
                      ),
                      onSelected: (_) => setState(() => _priority = p),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Tags (comma-separated, history autocomplete — same field
                // as the quick-add bar).
                Text('Tags', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                SuggestionField(
                  controller: _tagController,
                  commaSeparated: true,
                  suggestions: ref.watch(distinctTagsProvider),
                  optionIcon: Icons.label_outline,
                  headerText: 'Recent tags',
                  decoration: const InputDecoration(
                    hintText: 'Tags (a, b)',
                    prefixIcon: Icon(Icons.label_outline, size: 18),
                  ),
                ),
                const SizedBox(height: 16),

                // Sub-tasks
                Text('Sub-tasks', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subStepController,
                        decoration: const InputDecoration(
                          hintText: 'Add a sub-task and press Enter',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addSubStep(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _addSubStep,
                    ),
                  ],
                ),
                if (_subSteps.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _subSteps
                          .map((s) => Chip(
                                avatar: const Icon(Icons.checklist, size: 15),
                                label: Text(s),
                                onDeleted: () =>
                                    setState(() => _subSteps.remove(s)),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed:
                          _titleController.text.trim().isEmpty ? null : _create,
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      // Allow past dates so a task can be back-filled.
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _addSubStep() {
    final text = _subStepController.text.trim();
    if (text.isEmpty) return;
    setState(() => _subSteps.add(text));
    _subStepController.clear();
  }

  void _create() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final tags = _tagController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // Snapshot the live list: createTask is async and not awaited here,
    // while the dialog pops immediately below (same race guard as the
    // quick-add bar).
    ref.read(taskListProvider.notifier).createTask(
          title: title,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          priority: _priority,
          tags: tags,
          subSteps: List<String>.of(_subSteps),
          dueDate: _dueDate,
          project: _projectController.text.trim(),
          status: widget.initialStatus,
        );
    Navigator.of(context).pop(title);
  }
}
