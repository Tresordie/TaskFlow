import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import 'markdown_input.dart';
import 'suggestion_field.dart';
import 'tree_indent.dart';

/// A dialog for editing an existing task's title, description, priority
/// and due date.
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => EditTaskDialog(task: task),
/// );
/// ```
class EditTaskDialog extends ConsumerStatefulWidget {
  final Task task;

  const EditTaskDialog({super.key, required this.task});

  @override
  ConsumerState<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends ConsumerState<EditTaskDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final FocusNode _descriptionFocus;
  late final TextEditingController _projectController;
  final _subStepController = TextEditingController();
  late List<SubStep> _subSteps;
  late Priority _priority;
  DateTime? _dueDate;

  /// Per-step title editors, keyed by sub-step uid (created lazily).
  final Map<String, TextEditingController> _stepControllers = {};

  /// uid of the sub-step that an inline "add child" field is open for.
  String? _addingChildUid;
  final _addChildController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController =
        TextEditingController(text: widget.task.description ?? '');
    _descriptionFocus = markdownIndentFocusNode(_descriptionController);
    _projectController = TextEditingController(text: widget.task.project);
    // Deep copy: a shallow List.from would share SubStep instances with
    // the live task, leaking in-place edits even when Cancel is pressed.
    _subSteps = [
      for (final s in widget.task.subSteps)
        SubStep()
          ..uid = s.uid
          ..title = s.title
          ..completed = s.completed
          ..completedAt = s.completedAt
          ..parentUid = s.parentUid
          ..depth = s.depth,
    ];
    _priority = widget.task.priority;
    _dueDate = widget.task.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    _projectController.dispose();
    _subStepController.dispose();
    _addChildController.dispose();
    for (final c in _stepControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(SubStep step) {
    return _stepControllers.putIfAbsent(
        step.uid, () => TextEditingController(text: step.title));
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
                // Header
                Row(
                  children: [
                    Icon(Icons.edit_outlined,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Edit Task', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Title field
                Text('Title', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Task title',
                  ),
                ),
                const SizedBox(height: 16),

                // Project field (with history autocomplete)
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

                // Due date picker
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

                // Description field
                Text('Description', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                MarkdownToolbar(
                  controller: _descriptionController,
                  refocus: _descriptionFocus,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocus,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Add more details (optional, Markdown supported)',
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

                // Sub-tasks section (nested, max 3 levels)
                Text('Sub-tasks', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                if (_subSteps.isNotEmpty) ..._buildSubStepRows(theme),
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
                      onPressed: _save,
                      child: const Text('Save Changes'),
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

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    _syncTitles();

    final task = widget.task;
    task.title = title;
    task.description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    task.project = _projectController.text.trim();
    task.priority = _priority;
    task.dueDate = _dueDate;
    task.subSteps = _subSteps;

    ref.read(taskListProvider.notifier).updateTask(task);
    Navigator.pop(context);
  }

  /// Copies edited titles from the per-step controllers back into the
  /// sub-step objects. Empty edits keep the previous title.
  void _syncTitles() {
    for (final step in _subSteps) {
      final controller = _stepControllers[step.uid];
      if (controller == null) continue;
      final text = controller.text.trim();
      if (text.isNotEmpty) step.title = text;
    }
  }

  List<Widget> _buildSubStepRows(ThemeData theme) {
    final ordered = subStepsInDisplayOrder(_subSteps);
    // The inline add-child field goes AFTER the parent's whole subtree so
    // existing children render above it and a new child lands right above
    // the input instead of below the whole sibling group.
    final addingUid = _addingChildUid;
    final fieldAfter =
        addingUid == null ? -1 : subStepSubtreeEndIndex(ordered, addingUid);
    // The field must attach to the step the user tapped "+" on — NOT to
    // ordered[fieldAfter], which is the subtree's last descendant (using
    // it would indent the field one level too deep and nest new children
    // under the wrong parent).
    final parent = addingUid == null
        ? null
        : ordered.where((s) => s.uid == addingUid).firstOrNull;

    final rows = <Widget>[];
    for (var i = 0; i < ordered.length; i++) {
      rows.add(_buildSubStepRow(theme, ordered[i]));
      if (i == fieldAfter && parent != null) {
        rows.add(_buildAddChildField(theme, parent));
      }
    }
    return rows;
  }

  Widget _buildSubStepRow(ThemeData theme, SubStep step) {
    final canNest = step.depth < SubStep.maxDepth;

    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            step.completed ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: step.completed
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.35),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controllerFor(step),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.85),
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                border: InputBorder.none,
              ),
            ),
          ),
          if (canNest)
            IconButton(
              icon: Icon(
                Icons.add,
                size: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
              tooltip: 'Add nested sub-task',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: () => setState(() {
                _addingChildUid = _addingChildUid == step.uid ? null : step.uid;
                _addChildController.clear();
              }),
            ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            tooltip: 'Remove sub-task (and its children)',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => _removeStep(step),
          ),
        ],
      ),
    );

    return wrapWithTreeGuides(
      content,
      depth: step.depth,
      guideColor: treeGuideColor(theme),
    );
  }

  /// Inline "add child" input, indented one level below [parent] and
  /// wrapped in the same tree guide lines as its future siblings.
  Widget _buildAddChildField(ThemeData theme, SubStep parent) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 13, color: theme.colorScheme.primary.withOpacity(0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _addChildController,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Add nested sub-task…',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onSubmitted: (_) => _addChildStep(parent),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => setState(() => _addingChildUid = null),
          ),
        ],
      ),
    );

    return wrapWithTreeGuides(
      content,
      depth: parent.depth + 1,
      guideColor: treeGuideColor(theme),
    );
  }

  void _addChildStep(SubStep parent) {
    final text = _addChildController.text.trim();
    if (text.isEmpty || parent.depth >= SubStep.maxDepth) return;
    setState(() {
      _subSteps = [
        ..._subSteps,
        SubStep()
          ..uid = const Uuid().v4()
          ..title = text
          ..completed = false
          ..parentUid = parent.uid
          ..depth = parent.depth + 1,
      ];
    });
    _addChildController.clear();
  }

  /// Removes [step] together with all of its descendants.
  void _removeStep(SubStep step) {
    final doomed = subStepDescendantUids(_subSteps, step);
    setState(() {
      _subSteps = [
        for (final s in _subSteps)
          if (!doomed.contains(s.uid)) s,
      ];
      if (_addingChildUid != null && doomed.contains(_addingChildUid!)) {
        _addingChildUid = null;
      }
      for (final uid in doomed) {
        _stepControllers.remove(uid)?.dispose();
      }
    });
  }

  void _addSubStep() {
    final text = _subStepController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subSteps = [
        ..._subSteps,
        SubStep()
          ..uid = const Uuid().v4()
          ..title = text
          ..completed = false,
      ];
    });
    _subStepController.clear();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      // Allow past dates so overdue tasks can be re-scheduled.
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }
}
