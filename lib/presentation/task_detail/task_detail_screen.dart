import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../../providers/color_settings_provider.dart';
import '../shared/app_markdown_body.dart';
import '../shared/color_picker_dialog.dart';
import '../shared/edit_task_dialog.dart';
import '../shared/tree_indent.dart';
import 'execution_log_widget.dart';

class TaskDetailScreen extends ConsumerWidget {
  final int taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);

    return tasksAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (tasks) {
        final task = tasks.where((t) => t.id == taskId).firstOrNull;
        if (task == null) {
          return Scaffold(
            body: Center(child: Text('Task not found')),
          );
        }
        return _TaskDetailContent(task: task);
      },
    );
  }
}

class _TaskDetailContent extends ConsumerWidget {
  final Task task;

  const _TaskDetailContent({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priorityColor = AppColors.priorityColor(task.priority.index);

    return Scaffold(
      // Text selection comes from the app-wide SelectionArea (AppShell):
      // every read-only text on this screen — task title / description /
      // meta, sub-step titles and the Execution Log entries — is mouse
      // drag-selectable and copyable. Do NOT add a screen-local
      // SelectionArea here: nesting one inside the app-level area
      // silently breaks drag selection (v1.4.25 fix).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 8),
                // Status selector
                _StatusDropdown(task: task),
                const Spacer(),
                // Priority badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    task.priority.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: priorityColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit task',
                  onPressed: () => _openEditDialog(context),
                ),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppColors.error,
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ),

          // Task title & meta
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AppMarkdownBody(
                    data: task.description!,
                    hardenLineBreaks: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                      p: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Meta info row: created / due / started / done / tags
                Builder(builder: (context) {
                  final now = DateTime.now();
                  final due = task.dueDate;
                  final isOverdue = due != null &&
                      due.isBefore(now) &&
                      task.status != TaskStatus.completed;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _MetaItem(
                        icon: Icons.access_time,
                        label: DateFormat('MMM d, yyyy · HH:mm')
                            .format(task.createdAt),
                      ),
                      if (due != null)
                        _MetaItem(
                          icon: Icons.event,
                          label: 'Due ${DateFormat('MMM d, yyyy').format(due)}',
                          color: isOverdue ? AppColors.error : null,
                        ),
                      if (task.startedAt != null)
                        _MetaItem(
                          icon: Icons.play_arrow,
                          label:
                              'Started ${DateFormat('MMM d, yyyy · HH:mm').format(task.startedAt!)}',
                        ),
                      if (task.completedAt != null)
                        _MetaItem(
                          icon: Icons.check_circle,
                          label:
                              'Done ${DateFormat('MMM d, yyyy · HH:mm').format(task.completedAt!)}',
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                // Editable tags
                _TagsEditor(task: task),
              ],
            ),
          ),

          const Divider(height: 32),

          // Sub-steps section
          if (task.subSteps.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SubStepsSection(task: task),
            ),
            const SizedBox(height: 16),
          ],

          // Execution Log section (main area)
          Expanded(
            child: ExecutionLogWidget(task: task),
          ),
        ],
      ),
    );
  }

  void _openEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => EditTaskDialog(task: task),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Delete "${task.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              ref.read(taskListProvider.notifier).deleteTask(task.id);
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _StatusDropdown extends ConsumerWidget {
  final Task task;

  const _StatusDropdown({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<TaskStatus>(
      initialValue: task.status,
      onSelected: (status) {
        ref.read(taskListProvider.notifier).updateStatus(task.id, status);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.statusColor(task.status).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.statusColor(task.status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              task.status.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.statusColor(task.status),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: AppColors.statusColor(task.status)),
          ],
        ),
      ),
      itemBuilder: (context) => TaskStatus.values
          .map((s) => PopupMenuItem(
                value: s,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.statusColor(s),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(s.label),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaItem({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? AppColors.lightTextSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                color: color,
                fontWeight: color != null ? FontWeight.w600 : null,
              ),
        ),
      ],
    );
  }
}

class _SubStepsSection extends ConsumerStatefulWidget {
  final Task task;

  const _SubStepsSection({required this.task});

  @override
  ConsumerState<_SubStepsSection> createState() => _SubStepsSectionState();
}

class _SubStepsSectionState extends ConsumerState<_SubStepsSection> {
  final _addController = TextEditingController();

  /// uid of the sub-step whose title is being edited inline.
  String? _editingUid;
  final _editController = TextEditingController();

  /// uid of the sub-step that an inline "add child" field is open for.
  String? _addingChildUid;
  final _addChildController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    _editController.dispose();
    _addChildController.dispose();
    super.dispose();
  }

  void _addSubStep() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    ref.read(taskListProvider.notifier).addSubStep(widget.task.id, text);
    _addController.clear();
  }

  void _startEdit(SubStep step) {
    setState(() {
      _editingUid = step.uid;
      _editController.text = step.title;
    });
  }

  void _commitEdit() {
    final uid = _editingUid;
    final text = _editController.text.trim();
    if (uid != null && text.isNotEmpty) {
      ref
          .read(taskListProvider.notifier)
          .renameSubStep(widget.task.id, uid, text);
    }
    setState(() => _editingUid = null);
  }

  void _addChild(SubStep parent) {
    final text = _addChildController.text.trim();
    if (text.isEmpty) return;
    ref
        .read(taskListProvider.notifier)
        .addSubStep(widget.task.id, text, parentUid: parent.uid);
    _addChildController.clear();
  }

  void _deleteStep(SubStep step) {
    final doomed = subStepDescendantUids(widget.task.subSteps, step);
    setState(() {
      if (_addingChildUid != null && doomed.contains(_addingChildUid!)) {
        _addingChildUid = null;
      }
      if (_editingUid != null && doomed.contains(_editingUid!)) {
        _editingUid = null;
      }
    });
    ref.read(taskListProvider.notifier).deleteSubStep(widget.task.id, step.uid);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final completedCount = task.subSteps.where((s) => s.completed).length;
    final theme = Theme.of(context);
    final ordered = subStepsInDisplayOrder(task.subSteps);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Checklist',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            Text(
              '$completedCount/${task.subSteps.length}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._buildStepRows(theme, task, ordered),
        // Inline add sub-step input (top level)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 18, color: theme.colorScheme.primary.withOpacity(0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _addController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add sub-step…',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.35),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onSubmitted: (_) => _addSubStep(),
                ),
              ),
              IconButton(
                icon:
                    Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
                tooltip: 'Add sub-step',
                onPressed: _addSubStep,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStepRows(
      ThemeData theme, Task task, List<SubStep> ordered) {
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
      rows.add(_buildStepRow(theme, task, ordered[i]));
      if (i == fieldAfter && parent != null) {
        rows.add(_buildAddChildField(theme, parent));
      }
    }
    return rows;
  }

  Widget _buildStepRow(ThemeData theme, Task task, SubStep step) {
    final isEditing = _editingUid == step.uid;
    final canNest = step.depth < SubStep.maxDepth;
    final isEmpty = step.title.trim().isEmpty;
    final subtle = theme.colorScheme.onSurface.withOpacity(0.3);

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          // Checkbox — tap to toggle completion
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => ref
                .read(taskListProvider.notifier)
                .toggleSubStep(task.id, step.uid),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                step.completed
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 18,
                color: step.completed
                    ? AppColors.success
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEditing
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _editController,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitEdit(),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.check,
                            size: 16, color: theme.colorScheme.primary),
                        tooltip: 'Save',
                        onPressed: _commitEdit,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Cancel',
                        onPressed: () => setState(() => _editingUid = null),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  )
                : InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _startEdit(step),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 4),
                      child: isEmpty
                          ? Text(
                              '(untitled sub-step)',
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.35),
                              ),
                            )
                          : Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 14,
                                decoration: step.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: step.completed
                                    ? AppColors.lightTextSecondary
                                    : null,
                              ),
                            ),
                    ),
                  ),
          ),
          // Add nested sub-step (max 3 levels)
          if (canNest && !isEditing)
            IconButton(
              icon: Icon(Icons.add, size: 15, color: subtle),
              tooltip: 'Add nested sub-step',
              onPressed: () => setState(() {
                _addingChildUid = _addingChildUid == step.uid ? null : step.uid;
                _addChildController.clear();
              }),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
          // Delete sub-step (with its children)
          if (!isEditing)
            IconButton(
              icon: Icon(Icons.close, size: 15, color: subtle),
              tooltip: 'Remove sub-step',
              onPressed: () => _deleteStep(step),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 14, color: theme.colorScheme.primary.withOpacity(0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _addChildController,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add nested sub-step…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _addChild(parent),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            tooltip: 'Close',
            onPressed: () => setState(() => _addingChildUid = null),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
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
}

/// Inline tag editor on the task detail page: removable chips plus a
/// comma-separated input (Enter to add). Every change is persisted
/// immediately via [TaskListNotifier.updateTask].
class _TagsEditor extends ConsumerStatefulWidget {
  final Task task;

  const _TagsEditor({required this.task});

  @override
  ConsumerState<_TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends ConsumerState<_TagsEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(List<String> tags) {
    widget.task.tags = tags;
    ref.read(taskListProvider.notifier).updateTask(widget.task);
  }

  void _add() {
    final raw = _controller.text.trim();
    _controller.clear();
    if (raw.isEmpty) return;
    final additions = raw
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !widget.task.tags.contains(t))
        .toList();
    if (additions.isEmpty) return;
    _commit([...widget.task.tags, ...additions]);
  }

  Future<void> _pickTagColor(String tag, Color? current) async {
    final picked = await showColorPickerDialog(
      context,
      title: 'Tag color · #$tag',
      current: current,
    );
    if (!mounted) return;
    ref.read(colorSettingsProvider.notifier).setTagColor(tag, picked);
  }

  Future<void> _pickProjectColor(String project, Color? current) async {
    final picked = await showColorPickerDialog(
      context,
      title: 'Project color · $project',
      current: current,
    );
    if (!mounted) return;
    ref.read(colorSettingsProvider.notifier).setProjectColor(project, picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ref.watch(colorSettingsProvider);
    final project = widget.task.project.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.label_outline,
            size: 15, color: theme.colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 6),
        Text('Tags', style: theme.textTheme.labelLarge),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (project.isNotEmpty)
                _colorChip(
                  icon: Icons.folder_outlined,
                  label: project,
                  color: colors.projectColor(project),
                  theme: theme,
                  onTap: () =>
                      _pickProjectColor(project, colors.projectColor(project)),
                ),
              ...widget.task.tags.map((tag) => _colorChip(
                    icon: Icons.label,
                    label: tag,
                    color: colors.tagColor(tag),
                    theme: theme,
                    onTap: () => _pickTagColor(tag, colors.tagColor(tag)),
                    onDeleted: () => _commit(
                        widget.task.tags.where((t) => t != tag).toList()),
                  )),
              SizedBox(
                width: 170,
                height: 30,
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 12),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: 'Add tag, press Enter',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.4)),
                    ),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a compact chip whose tint follows the user-assigned [color]
  /// (or the theme default when none). Tapping opens the color picker;
  /// [onDeleted] (when provided) shows the delete affordance.
  Widget _colorChip({
    required IconData icon,
    required String label,
    required Color? color,
    required ThemeData theme,
    required VoidCallback onTap,
    VoidCallback? onDeleted,
  }) {
    final accent = color ?? theme.colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Chip(
        avatar: Icon(icon, size: 13, color: accent),
        label: Text(label, style: TextStyle(fontSize: 11.5, color: accent)),
        backgroundColor: accent.withOpacity(0.12),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        deleteIcon: const Icon(Icons.close, size: 13),
        onDeleted: onDeleted,
      ),
    );
  }
}
