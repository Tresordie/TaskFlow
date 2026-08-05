import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../shared/edit_task_dialog.dart';
import '../shared/task_date_meta.dart';
import '../shared/task_tag_project_meta.dart';

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
    final priorityColor = AppColors.priorityColor(task.priority.index);
    final isCompleted =
        task.status == TaskStatus.completed || task.status == TaskStatus.archived;
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
              height: 56,
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
            child: _buildCard(theme, palette, task, priorityColor, isCompleted),
          ),
        );
      },
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme palette, Task task,
      Color priorityColor, bool isCompleted) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/task/${task.id}'),
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          transform: _isPressed
              ? (Matrix4.identity()..scale(0.985))
              : _isHovered
                  ? (Matrix4.identity()..translate(0.0, -2.0))
                  : Matrix4.identity(),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCompleted
                  ? AppColors.success.withOpacity(0.3)
                  : _isHovered
                      ? priorityColor.withOpacity(0.45)
                      : palette.outline.withOpacity(0.6),
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: priorityColor.withOpacity(0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Status checkbox with animation
              GestureDetector(
                onTap: () => _toggleStatus(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCompleted ? AppColors.success : priorityColor,
                      width: 2,
                    ),
                    color: isCompleted ? AppColors.success : Colors.transparent,
                  ),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 14),

              // Task content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted
                            ? palette.onSurface.withOpacity(0.4)
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.status.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.statusColor(task.status),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (task.project.trim().isNotEmpty ||
                        task.tags.isNotEmpty) ...[
                      TaskTagProjectMeta(task: task),
                      const SizedBox(height: 4),
                    ],
                    TaskDateMeta(task: task),
                  ],
                ),
              ),

              // Right column: actions + priority + progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Quick actions (revealed on hover): edit + delete
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openEditDialog,
                            child: Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: palette.onSurface.withOpacity(0.55),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _confirmDelete,
                            child: Icon(
                              Icons.delete_outline,
                              size: 15,
                              color: AppColors.error.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      task.priority.shortLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: priorityColor,
                      ),
                    ),
                  ),
                  if (task.subSteps.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${task.subSteps.where((s) => s.completed).length}/${task.subSteps.length}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
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
