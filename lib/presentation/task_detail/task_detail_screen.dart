import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../shared/edit_task_dialog.dart';
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
      // SelectionArea makes every read-only text below selectable &
      // copyable with the mouse: the task title / description / meta,
      // sub-step titles, and the Execution Log entries (MarkdownBody
      // content included — RenderParagraph registers its selectable
      // fragments with the surrounding SelectionContainer). Tappable
      // controls (status dropdown, sub-step toggles, edit/delete
      // buttons, the log input field) are unaffected: selection needs
      // a drag, a plain click still triggers them.
      body: SelectionArea(
        child: Column(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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
                    Text(
                      task.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
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
                            label:
                                'Due ${DateFormat('MMM d, yyyy').format(due)}',
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
                        ...task.tags.map((tag) => _MetaItem(
                              icon: Icons.label_outline,
                              label: tag,
                            )),
                      ],
                    );
                  }),
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
    final statusColors = {
      TaskStatus.planned: AppColors.lightTextSecondary,
      TaskStatus.inProgress: AppColors.info,
      TaskStatus.completed: AppColors.success,
      TaskStatus.archived: AppColors.p3Low,
    };

    return PopupMenuButton<TaskStatus>(
      initialValue: task.status,
      onSelected: (status) {
        ref.read(taskListProvider.notifier).updateStatus(task.id, status);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (statusColors[task.status] ?? AppColors.primary)
              .withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColors[task.status],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              task.status.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: statusColors[task.status],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: statusColors[task.status]),
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
                        color: statusColors[s],
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

class _SubStepsSection extends ConsumerWidget {
  final Task task;

  const _SubStepsSection({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completedCount =
        task.subSteps.where((s) => s.completed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Checklist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            Text(
              '$completedCount/${task.subSteps.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...task.subSteps.map((step) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => ref
                    .read(taskListProvider.notifier)
                    .toggleSubStep(task.id, step.uid),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        step.completed
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: step.completed
                            ? AppColors.success
                            : AppColors.lightTextSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
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
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }
}
