import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../shared/task_date_meta.dart';

/// GitHub-style contribution heatmap showing daily task volume for the year.
class HeatmapScreen extends ConsumerWidget {
  const HeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(taskListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withOpacity(0.06),
                theme.colorScheme.surface,
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text('Activity', style: theme.textTheme.headlineLarge),
            ],
          ),
        ),

        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (tasks) => SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary stats
                  _buildStats(context, ref, theme, tasks),
                  const SizedBox(height: 28),
                  // Heatmap
                  Text(
                    '${DateTime.now().year} Task Activity',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _HeatmapGrid(tasks: tasks),
                  const SizedBox(height: 12),
                  // Legend
                  _buildLegend(theme),
                  const SizedBox(height: 28),
                  // Task list with created / due dates
                  Text(
                    'Tasks',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildTaskList(context, theme, tasks),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats(
      BuildContext context, WidgetRef ref, ThemeData theme, List<Task> tasks) {
    final now = DateTime.now();
    final todayCount = tasks
        .where((t) =>
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month &&
            t.createdAt.day == now.day)
        .length;
    final completedCount =
        tasks.where((t) => t.status == TaskStatus.completed).length;
    final totalCount = tasks.length;

    // Set the shared task filter, then jump to the task list — the board
    // screen consumes taskFilterProvider, so it shows the filtered result.
    void jumpWith(TaskFilter filter) {
      ref.read(taskFilterProvider.notifier).state = filter;
      context.go('/today');
    }

    return Row(
      children: [
        _StatCard(
          label: 'Today',
          value: '$todayCount',
          icon: Icons.today,
          theme: theme,
          onTap: () =>
              jumpWith(TaskFilter(date: DateTime(now.year, now.month, now.day))),
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Completed',
          value: '$completedCount',
          icon: Icons.check_circle_outline,
          theme: theme,
          onTap: () => jumpWith(TaskFilter(status: TaskStatus.completed)),
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Total',
          value: '$totalCount',
          icon: Icons.list_alt,
          theme: theme,
          onTap: () => jumpWith(TaskFilter()),
        ),
      ],
    );
  }

  Widget _buildLegend(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: theme.textTheme.labelSmall),
        const SizedBox(width: 6),
        ...[0.0, 0.2, 0.4, 0.7, 1.0].map((opacity) => Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: opacity == 0.0
                    ? theme.colorScheme.outline.withOpacity(0.15)
                    : primary.withOpacity(opacity),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
        const SizedBox(width: 6),
        Text('More', style: theme.textTheme.labelSmall),
      ],
    );
  }

  Widget _buildTaskList(
      BuildContext context, ThemeData theme, List<Task> tasks) {
    final sorted = [...tasks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No tasks yet', style: theme.textTheme.bodyMedium),
      );
    }
    return Column(
      children: sorted
          .map((task) => _ActivityTaskItem(task: task))
          .toList(),
    );
  }
}

class _ActivityTaskItem extends StatelessWidget {
  final Task task;

  const _ActivityTaskItem({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priorityColor = AppColors.priorityColor(task.priority.index);
    final isCompleted = task.status == TaskStatus.completed;

    return GestureDetector(
      onTap: () => context.push('/task/${task.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isCompleted ? AppColors.success : priorityColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 13,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      color: isCompleted
                          ? theme.colorScheme.onSurface.withOpacity(0.4)
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isCompleted ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: isCompleted ? AppColors.success : priorityColor,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: TaskDateMeta(task: task, compact: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const Spacer(),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurface.withOpacity(0.35),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  final List<Task> tasks;

  const _HeatmapGrid({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final now = DateTime.now();
    final year = now.year;

    // Build task count map for the year
    final countMap = <String, int>{};
    for (final task in tasks) {
      if (task.createdAt.year == year) {
        final key =
            '${task.createdAt.month}-${task.createdAt.day}';
        countMap[key] = (countMap[key] ?? 0) + 1;
      }
    }

    final maxCount =
        countMap.values.isEmpty ? 1 : countMap.values.reduce((a, b) => a > b ? a : b);

    // Calculate weeks (columns) for the year
    final jan1 = DateTime(year, 1, 1);
    final dec31 = DateTime(year, 12, 31);
    final startOffset = jan1.weekday - 1; // 0=Mon
    final totalDays = dec31.difference(jan1).inDays + 1;
    final totalWeeks = ((startOffset + totalDays) / 7).ceil();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels
          Column(
            children: [
              const SizedBox(height: 20), // space for weekday labels
              ...['Mon', 'Wed', 'Fri'].map((d) => SizedBox(
                    height: 42,
                    child: Text(
                      d,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontSize: 9),
                    ),
                  )),
            ],
          ),
          const SizedBox(width: 6),
          // Grid
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month labels row
              SizedBox(
                height: 18,
                child: _MonthLabels(year: year, totalWeeks: totalWeeks),
              ),
              const SizedBox(height: 4),
              // Weeks
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(totalWeeks, (weekIndex) {
                  return Column(
                    children: List.generate(7, (dayIndex) {
                      final dayOfYear =
                          weekIndex * 7 + dayIndex - startOffset + 1;
                      if (dayOfYear < 1 || dayOfYear > totalDays) {
                        return Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(1.5),
                        );
                      }
                      final date =
                          jan1.add(Duration(days: dayOfYear - 1));
                      final key = '${date.month}-${date.day}';
                      final count = countMap[key] ?? 0;
                      final intensity =
                          count == 0 ? 0.0 : (count / maxCount).clamp(0.15, 1.0);

                      return Tooltip(
                        message:
                            '${DateFormat('MMM d').format(date)}: $count task${count == 1 ? '' : 's'}',
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: count == 0
                                ? theme.colorScheme.outline
                                    .withOpacity(0.12)
                                : primary.withOpacity(intensity),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthLabels extends StatelessWidget {
  final int year;
  final int totalWeeks;

  const _MonthLabels({required this.year, required this.totalWeeks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = <Widget>[];
    int lastMonth = -1;

    for (int w = 0; w < totalWeeks; w++) {
      final jan1 = DateTime(year, 1, 1);
      final startOffset = jan1.weekday - 1;
      final dayOfYear = w * 7 - startOffset + 1;
      final date = dayOfYear < 1
          ? DateTime(year, 1, 1)
          : jan1.add(Duration(days: dayOfYear - 1));

      if (date.month != lastMonth && date.day <= 7) {
        labels.add(SizedBox(
          width: 17 * (w == 0 ? 1 : 1),
          child: Text(
            DateFormat('MMM').format(date),
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
          ),
        ));
        lastMonth = date.month;
      } else {
        labels.add(const SizedBox(width: 17));
      }
    }

    return Row(children: labels);
  }
}
