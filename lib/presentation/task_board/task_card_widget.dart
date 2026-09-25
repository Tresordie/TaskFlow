import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/color_settings_provider.dart';
import '../../providers/task_providers.dart';
import '../../providers/theme_provider.dart';
import '../shared/edit_task_dialog.dart';

/// v1.10.0: kanban-style task card for the Today board (translate_tool-
/// inspired): a 3px priority bar on the left edge, title with hover actions
/// (done-toggle / edit / delete), a two-line truncated description and a
/// row of pill-shaped meta chips. Dropping another task onto this card
/// still converts it into a sub-step (pre-existing board interaction).
class TaskCard extends ConsumerStatefulWidget {
  final Task task;

  const TaskCard({super.key, required this.task});

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _isHovered = false;
  bool _isDragOver = false;
  // v1.4.29: brief press-down state so the card gives a subtle "dips then
  // springs back" tactile feedback on tap, in addition to the hover lift.
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isDone =
        task.status == TaskStatus.completed || task.status == TaskStatus.archived;
    final priorityColor = AppColors.priorityColor(task.priority.index);
    // Completed cards switch their accent bar to green, like translate_tool's
    // `.is-done` cards.
    final barColor = isDone ? AppColors.success : priorityColor;
    final theme = Theme.of(context);
    final palette = theme.colorScheme;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        final accept = details.data.id != task.id;
        if (accept && !_isDragOver) setState(() => _isDragOver = true);
        return accept;
      },
      onLeave: (_) => setState(() => _isDragOver = false),
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        _convertToSubStep(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return Draggable<Task>(
          data: task,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 260,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.primary.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.subdirectory_arrow_right,
                      size: 14, color: palette.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.outline.withOpacity(0.4),
                  style: BorderStyle.solid,
                ),
              ),
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: _isDragOver
                  ? Border.all(
                      color: palette.primary,
                      width: 2,
                    )
                  : null,
              boxShadow: _isDragOver
                  ? [
                      BoxShadow(
                        color: palette.primary.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: _buildCard(theme, palette, task, barColor, isDone),
          ),
        );
      },
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme palette, Task task,
      Color barColor, bool isDone) {
    final colorSettings = ref.watch(colorSettingsProvider);
    final muted = palette.onSurface.withOpacity(0.5);
    // v1.11.1: pure white in light themes so cards pop off the bg canvas;
    // dark themes keep the palette card color.
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? ref.watch(themeModeProvider).palette.card
        : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/task/${task.id}'),
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isDone ? 0.78 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: _isPressed
                ? (Matrix4.identity()..scale(0.985))
                : _isHovered
                    ? (Matrix4.identity()..translate(0.0, -2.0))
                    : Matrix4.identity(),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDone
                    ? AppColors.success.withOpacity(0.3)
                    : _isHovered
                        ? barColor.withOpacity(0.45)
                        : palette.outline.withOpacity(0.7),
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: barColor.withOpacity(0.10),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.05 : 0.07),
                        blurRadius: isDark ? 7 : 9,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                // Content (bottom of the stack).
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 13.5,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                          color: isDone
                              ? palette.onSurface.withOpacity(0.4)
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.description != null &&
                          task.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          task.description!,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (_hasMetaChips(task)) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            if (task.dueDate != null)
                              _dueChip(theme, palette, task, muted),
                            _chip(
                              icon: null,
                              label: task.priority.shortLabel,
                              color: AppColors.priorityColor(
                                  task.priority.index),
                              background: AppColors
                                  .priorityColor(task.priority.index)
                                  .withOpacity(0.10),
                            ),
                            if (task.subSteps.isNotEmpty)
                              _chip(
                                icon: Icons.checklist,
                                label:
                                    '${task.subSteps.where((s) => s.completed).length}/${task.subSteps.length}',
                                color: muted,
                                background:
                                    palette.outline.withOpacity(0.10),
                              ),
                            if (task.project.trim().isNotEmpty)
                              _chip(
                                icon: Icons.folder_outlined,
                                label: task.project.trim(),
                                color: colorSettings
                                        .projectColor(task.project.trim()) ??
                                    muted,
                                background:
                                    palette.outline.withOpacity(0.10),
                              ),
                            for (final tag in task.tags)
                              _chip(
                                icon: null,
                                dotColor:
                                    colorSettings.tagColor(tag) ?? muted,
                                label: tag,
                                color: muted,
                                background:
                                    palette.outline.withOpacity(0.10),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Hover actions (top-right, overlaying the title tail like
                // translate_tool's kb-actions).
                Positioned(
                  right: 6,
                  top: 5,
                  child: AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _actionIcon(
                          icon: isDone ? Icons.undo : Icons.check,
                          tooltip: isDone ? 'Move to To Do' : 'Mark done',
                          color: isDone
                              ? muted
                              : AppColors.success.withOpacity(0.9),
                          onTap: _toggleStatus,
                        ),
                        const SizedBox(width: 8),
                        _actionIcon(
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit',
                          color: muted,
                          onTap: _openEditDialog,
                        ),
                        const SizedBox(width: 8),
                        _actionIcon(
                          icon: Icons.delete_outline,
                          tooltip: 'Delete',
                          color: AppColors.error.withOpacity(0.8),
                          onTap: _confirmDelete,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasMetaChips(Task task) =>
      task.dueDate != null ||
      task.subSteps.isNotEmpty ||
      task.project.trim().isNotEmpty ||
      task.tags.isNotEmpty;

  /// Due-date chip: red when overdue, theme-primary when due today.
  Widget _dueChip(
      ThemeData theme, ColorScheme palette, Task task, Color muted) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final due = task.dueDate!;
    final isOverdue = due.isBefore(todayStart) && !_isDoneTask(task);
    final isToday = _isSameDay(due, now);

    final color = isOverdue
        ? AppColors.error
        : isToday
            ? palette.primary
            : muted;
    final background = isOverdue
        ? AppColors.error.withOpacity(0.12)
        : isToday
            ? palette.primary.withOpacity(0.12)
            : palette.outline.withOpacity(0.10);

    final differsFromCurrentYear = due.year != now.year;
    final label = DateFormat('MMM d').format(due) +
        (differsFromCurrentYear ? ', ${due.year}' : '');

    return _chip(
      icon: Icons.event,
      label: isOverdue ? '$label · Overdue' : label,
      color: color,
      background: background,
      bold: isOverdue,
    );
  }

  bool _isDoneTask(Task t) =>
      t.status == TaskStatus.completed || t.status == TaskStatus.archived;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _chip({
    required String label,
    required Color color,
    required Color background,
    IconData? icon,
    Color? dotColor,
    bool bold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  void _convertToSubStep(Task dragged) async {
    final target = widget.task;
    final notifier = ref.read(taskListProvider.notifier);
    // v1.4.79: atomic conversion — the dragged task's sub-step tree AND
    // its Execution Log notes are merged into the target before deletion.
    final merged =
        await notifier.convertTaskToSubStep(dragged.id, target.id);
    if (!mounted) return;
    final parts = <String>[
      if (merged.notes > 0)
        '${merged.notes} note${merged.notes == 1 ? '' : 's'}',
      if (merged.subSteps > 0)
        '${merged.subSteps} sub-task${merged.subSteps == 1 ? '' : 's'}',
    ];
    final suffix = parts.isEmpty ? '' : ' (${parts.join(', ')} merged)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('"${dragged.title}" → sub-step of "${target.title}"$suffix'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openEditDialog() {
    showDialog(
      context: context,
      builder: (_) => EditTaskDialog(task: widget.task),
    );
  }

  Future<void> _confirmDelete() async {
    final task = widget.task;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task'),
        content: Text(
          'Delete "${task.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(taskListProvider.notifier).deleteTask(task.id);
    }
  }

  void _toggleStatus() {
    final task = widget.task;
    final isDone =
        task.status == TaskStatus.completed || task.status == TaskStatus.archived;
    final newStatus = isDone ? TaskStatus.planned : TaskStatus.completed;
    ref.read(taskListProvider.notifier).updateStatus(task.id, newStatus);
  }
}
