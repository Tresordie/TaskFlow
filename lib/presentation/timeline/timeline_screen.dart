import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/date_nav_providers.dart';
import '../../providers/task_providers.dart';
import '../shared/app_date_picker.dart';
import '../shared/task_date_meta.dart';
import '../shared/task_tag_project_meta.dart';
import '../shared/wheel_forward.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);
    final nav = ref.watch(timelineDateNavProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Forward mouse-wheel events over the fixed header to the timeline
        // list below, so the page scrolls wherever the pointer is.
        WheelForward(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with date picker / range controls
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Timeline',
                          style: theme.textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nav.rangeMode
                              ? '${DateFormat('MMM d, yyyy').format(nav.dateRange!.start)} – '
                                  '${DateFormat('MMM d, yyyy').format(nav.dateRange!.end)}'
                              : DateFormat('EEEE, MMM d, yyyy')
                                  .format(nav.selectedDate),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (nav.rangeMode) ...[
                      // Active range chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.date_range,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '${DateFormat('MMM d').format(nav.dateRange!.start)} – '
                              '${DateFormat('MMM d').format(nav.dateRange!.end)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Edit range',
                        onPressed: () => _pickRange(context, ref, nav),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Clear range',
                        onPressed: () =>
                            _setNav(ref, nav.copyWith(clearRange: true)),
                      ),
                    ] else ...[
                      // Single-day navigation
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _setNav(
                            ref,
                            nav.copyWith(
                                selectedDate: nav.selectedDate
                                    .subtract(const Duration(days: 1)))),
                      ),
                      TextButton(
                        onPressed: () => _pickDate(context, ref, nav),
                        child: const Text('Today'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _setNav(
                            ref,
                            nav.copyWith(
                                selectedDate: nav.selectedDate
                                    .add(const Duration(days: 1)))),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _pickRange(context, ref, nav),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: const Text('Range'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),

        // Timeline content
        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (tasks) {
              final dayTasks = _filterTasks(tasks, nav);

              if (dayTasks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy,
                          size: 48, color: AppColors.lightBorder),
                      const SizedBox(height: 12),
                      Text(
                        nav.rangeMode
                            ? 'No tasks in this range'
                            : 'No tasks on this day',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }

              return _TimelineList(tasks: dayTasks);
            },
          ),
        ),
      ],
    );
  }

  void _setNav(WidgetRef ref, DateNavState next) {
    ref.read(timelineDateNavProvider.notifier).state = next;
  }

  Future<void> _pickDate(
      BuildContext context, WidgetRef ref, DateNavState nav) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: nav.selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      _setNav(ref, nav.copyWith(selectedDate: picked));
    }
  }

  Future<void> _pickRange(
      BuildContext context, WidgetRef ref, DateNavState nav) async {
    final picked = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: nav.dateRange ??
          DateTimeRange(
            start: nav.selectedDate,
            end: nav.selectedDate.add(const Duration(days: 7)),
          ),
    );
    if (picked != null) {
      _setNav(ref, nav.copyWith(dateRange: picked));
    }
  }

  List<Task> _filterTasks(List<Task> tasks, DateNavState nav) {
    return tasks.where((t) {
      if (nav.rangeMode) {
        final start = DateTime(nav.dateRange!.start.year,
            nav.dateRange!.start.month, nav.dateRange!.start.day);
        final end = DateTime(nav.dateRange!.end.year, nav.dateRange!.end.month,
            nav.dateRange!.end.day, 23, 59, 59, 999);
        return !t.createdAt.isBefore(start) && !t.createdAt.isAfter(end);
      }
      final taskDay =
          DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
      final selected = DateTime(
          nav.selectedDate.year, nav.selectedDate.month, nav.selectedDate.day);
      return taskDay == selected;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}

class _TimelineList extends StatelessWidget {
  final List<Task> tasks;

  const _TimelineList({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isLast = index == tasks.length - 1;
        return _TimelineItem(task: task, isLast: isLast);
      },
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final Task task;
  final bool isLast;

  const _TimelineItem({required this.task, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
    final priorityColor = AppColors.priorityColor(task.priority.index);
    // v1.9.0: completed AND archived titles strike through + dim, matching
    // the Today board's TaskCard (archived previously showed as untouched).
    final isCompleted = task.status == TaskStatus.completed ||
        task.status == TaskStatus.archived;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          decoration: isCompleted ? TextDecoration.lineThrough : null,
          color: isCompleted
              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
              : null,
          decorationColor:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column
          SizedBox(
            width: 52,
            child: Text(
              DateFormat('HH:mm').format(task.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.lightTextSecondary,
                  ),
            ),
          ),
          const SizedBox(width: 12),

          // Timeline line + dot
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withOpacity(0.3),
                    width: 3,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),

          // Task card
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/task/${task.id}'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Priority dot
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: priorityColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.title,
                            style: titleStyle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            task.status.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (task.project.trim().isNotEmpty ||
                        task.tags.isNotEmpty) ...[
                      TaskTagProjectMeta(task: task),
                      const SizedBox(height: 4),
                    ],
                    TaskDateMeta(task: task),
                    // Sub-step progress
                    if (task.subSteps.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value:
                              task.subSteps.where((s) => s.completed).length /
                                  task.subSteps.length,
                          minHeight: 4,
                          backgroundColor: AppColors.lightBorder,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                    ],
                    // Execution log count
                    if (task.executionLog.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.edit_note,
                              size: 14, color: AppColors.lightTextSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${task.executionLog.length} log entries',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.lightTextSecondary,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(TaskStatus status) {
    return AppColors.statusColor(status);
  }
}
