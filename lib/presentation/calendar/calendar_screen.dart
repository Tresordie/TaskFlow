import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/date_nav_providers.dart';
import '../../providers/task_providers.dart';
import '../shared/task_date_meta.dart';
import '../shared/task_tag_project_meta.dart';
import '../shared/wheel_forward.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// The month currently shown in the grid. Local view state — the
  /// selected day / range live in [calendarDateNavProvider] so they
  /// persist across page switches.
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final nav = ref.read(calendarDateNavProvider);
    _currentMonth = DateTime(nav.selectedDate.year, nav.selectedDate.month);
  }

  void _setNav(DateNavState next) {
    ref.read(calendarDateNavProvider.notifier).state = next;
  }

  Future<void> _pickRange(DateNavState nav) async {
    final picked = await showDateRangePicker(
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
      _setNav(nav.copyWith(dateRange: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(taskListProvider);
    final nav = ref.watch(calendarDateNavProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Forward mouse-wheel events over the fixed header to the day task
        // list, so the page scrolls wherever the pointer is.
        WheelForward(
          child: Column(
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
                    Text('Calendar', style: theme.textTheme.headlineLarge),
                    const Spacer(),
                    if (nav.rangeMode) ...[
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
                        onPressed: () => _pickRange(nav),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Clear range',
                        onPressed: () =>
                            _setNav(nav.copyWith(clearRange: true)),
                      ),
                    ] else
                      OutlinedButton.icon(
                        onPressed: () => _pickRange(nav),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: const Text('Range'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (tasks) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Calendar grid
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildCalendar(theme, tasks, nav),
                  ),
                ),
                // Selected day tasks
                Expanded(
                  flex: 2,
                  child: _buildDayPanel(theme, tasks, nav),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar(ThemeData theme, List<Task> tasks, DateNavState nav) {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final firstWeekday = firstDay.weekday; // 1=Mon, 7=Sun
    final daysInMonth = lastDay.day;

    // Count tasks per day
    final taskCounts = <int, int>{};
    for (final task in tasks) {
      if (task.createdAt.year == year && task.createdAt.month == month) {
        final day = task.createdAt.day;
        taskCounts[day] = (taskCounts[day] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() {
                _currentMonth = DateTime(year, month - 1);
              }),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_currentMonth),
              style: theme.textTheme.titleLarge,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() {
                _currentMonth = DateTime(year, month + 1);
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Weekday headers
        Row(
          children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),

        // Day grid
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.2,
            ),
            itemCount: (firstWeekday - 1) + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) {
                return const SizedBox.shrink();
              }
              final day = index - (firstWeekday - 1) + 1;
              final date = DateTime(year, month, day);
              final isToday = _isSameDay(date, DateTime.now());
              final isSelected =
                  !nav.rangeMode && _isSameDay(date, nav.selectedDate);
              final inRange = nav.rangeMode && _isInRange(date, nav);
              final count = taskCounts[day] ?? 0;

              return GestureDetector(
                onTap: () =>
                    _setNav(nav.copyWith(selectedDate: date, clearRange: true)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : inRange
                            ? theme.colorScheme.primary.withOpacity(0.15)
                            : isToday
                                ? theme.colorScheme.primary.withOpacity(0.1)
                                : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !isSelected
                        ? Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.4))
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isToday || isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            count > 3 ? 3 : count,
                            (_) => Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.8)
                                    : theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayPanel(ThemeData theme, List<Task> tasks, DateNavState nav) {
    final String title;
    final List<Task> dayTasks;
    final String emptyLabel;

    if (nav.rangeMode) {
      title = '${DateFormat('MMM d').format(nav.dateRange!.start)} – '
          '${DateFormat('MMM d, yyyy').format(nav.dateRange!.end)}';
      dayTasks = tasks.where((t) => _isInRange(t.createdAt, nav)).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      emptyLabel = 'No tasks in this range';
    } else {
      title = DateFormat('EEE, MMM d').format(nav.selectedDate);
      dayTasks = tasks
          .where((t) => _isSameDay(t.createdAt, nav.selectedDate))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      emptyLabel = 'No tasks on this day';
    }

    return Container(
      margin: const EdgeInsets.only(top: 24, right: 24, bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${dayTasks.length} task${dayTasks.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (dayTasks.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  emptyLabel,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children:
                    dayTasks.map((task) => _DayTaskItem(task: task)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isInRange(DateTime date, DateNavState nav) {
    if (nav.dateRange == null) return false;
    final d = DateTime(date.year, date.month, date.day);
    final start = DateTime(nav.dateRange!.start.year,
        nav.dateRange!.start.month, nav.dateRange!.start.day);
    final end = DateTime(nav.dateRange!.end.year, nav.dateRange!.end.month,
        nav.dateRange!.end.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

class _DayTaskItem extends StatelessWidget {
  final Task task;

  const _DayTaskItem({required this.task});

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
                      fontSize: 14.5,
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
            if (task.project.trim().isNotEmpty || task.tags.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: TaskTagProjectMeta(task: task, compact: true),
              ),
              const SizedBox(height: 4),
            ],
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
