import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/date_nav_providers.dart';
import '../../providers/task_providers.dart';
import '../shared/app_date_picker.dart';
import '../shared/hover_lift.dart';
import '../shared/task_date_meta.dart';
import '../shared/emoji_glyphs.dart';
import '../shared/task_list_card.dart';
import '../shared/timeline_rail.dart';
import '../shared/task_tag_project_meta.dart';
import '../shared/wheel_forward.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);
    final nav = ref.watch(timelineDateNavProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
              // v1.12.39: the accent bar is now lit the same way the spine
              // nodes are — gradient fill plus a soft accent glow.
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withOpacity(0.35),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Timeline',
                          style: theme.textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('🗓',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.3,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.55),
                                )),
                            const SizedBox(width: 5),
                            Text(
                              nav.rangeMode
                                  ? '${DateFormat('MMM d, yyyy').format(nav.dateRange!.start)} – '
                                      '${DateFormat('MMM d, yyyy').format(nav.dateRange!.end)}'
                                  : DateFormat('EEEE, MMM d, yyyy')
                                      .format(nav.selectedDate),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.colorScheme.surface,
                          theme.colorScheme.surfaceContainerHighest
                              .withOpacity(isDark ? 0.45 : 0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.28),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🗓️', style: TextStyle(fontSize: 30)),
                        const SizedBox(height: 10),
                        Text(
                          nav.rangeMode
                              ? 'No tasks in this range'
                              : 'No tasks on this day',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The timeline stays empty until a task is created here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return _TimelineList(
                tasks: dayTasks,
                showDayHeaders: nav.rangeMode,
              );
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
      // v1.9.2: newest first — the timeline reads top-down from the most
      // recent task down to the oldest.
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

/// Day-group marker in the Timeline row stream (range mode only).
class TimelineDayRow {
  final DateTime date;
  final int count;

  const TimelineDayRow(this.date, this.count);
}

/// v1.12.39: flattens the filtered tasks into the rows the list renders —
/// [TimelineDayRow] separators interleaved with [Task] events. Public and pure
/// so the day-grouping contract is testable without pumping the page.
class TimelineRows {
  static DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool sameDay(DateTime a, DateTime? b) =>
      b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  static List<Object> build(List<Task> tasks, {bool showDayHeaders = false}) {
    if (!showDayHeaders) return List<Object>.from(tasks);
    final rows = <Object>[];
    DateTime? runDay;
    for (var i = 0; i < tasks.length; i++) {
      final day = dayKey(tasks[i].createdAt);
      if (i == 0 || !sameDay(day, runDay)) {
        rows.add(TimelineDayRow(
          day,
          tasks.where((t) => sameDay(dayKey(t.createdAt), day)).length,
        ));
      }
      runDay = day;
      rows.add(tasks[i]);
    }
    return rows;
  }

  /// First event of the list (or right after a day separator) — the rail gets
  /// its soft top cap there. False for non-task rows.
  static bool isFirstOfRun(List<Object> rows, int index) =>
      rows[index] is Task && (index == 0 || rows[index - 1] is! Task);

  /// Last event overall — nothing task-shaped below it, so the rail ends in a
  /// fading tail.
  static bool isLastEvent(List<Object> rows, int index) =>
      !rows.skip(index + 1).any((r) => r is Task);
}

/// v1.12.39: the Timeline spine is drawn by the shared [TimelineRail] (the
/// same component the task Execution Log uses, so the two pages match).
/// Range mode groups by day with a `📅 Mon, Sep 29 · 3 tasks` header.
class _TimelineList extends StatelessWidget {
  final List<Task> tasks;
  final bool showDayHeaders;

  const _TimelineList({
    required this.tasks,
    this.showDayHeaders = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = TimelineRows.build(tasks, showDayHeaders: showDayHeaders);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is TimelineDayRow) {
          return _TimelineDayHeader(date: row.date, count: row.count);
        }
        final task = row as Task;
        return _TimelineItem(
          task: task,
          isLast: TimelineRows.isLastEvent(rows, index),
          capTop: TimelineRows.isFirstOfRun(rows, index),
          showDate: !showDayHeaders,
        );
      },
    );
  }
}

/// Day separator: an accent chip with the weekday/date and the number of
/// events, closed off by a hairline that fades out to the right.
class _TimelineDayHeader extends StatelessWidget {
  final DateTime date;
  final int count;

  const _TimelineDayHeader({required this.date, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withOpacity(0.16),
                  accent.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: accent.withOpacity(0.24)),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text('📅', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  DateFormat('EEE, MMM d').format(date),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: accent,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 7),
                  Text(
                    '$count ${count == 1 ? 'task' : 'tasks'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.60),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    accent.withOpacity(0.28),
                    theme.colorScheme.outline.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final Task task;
  final bool isLast;

  /// First event of the list (or of a day group) — the rail gets a soft
  /// fading stub above the node instead of starting at a hard cut.
  final bool capTop;

  /// Whether the left column repeats the date. Range mode already prints a
  /// `📅 Fri, Sep 11` header per group, so the row keeps only the time.
  final bool showDate;

  const _TimelineItem({
    required this.task,
    required this.isLast,
    this.capTop = false,
    this.showDate = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          // Date + time column. Width fits yyyy-MM-dd at the 140% font scale.
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDate) ...[
                  Text(
                    _dayLabel(task.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.72),
                        ),
                  ),
                  const SizedBox(height: 3),
                ] else
                  const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '🕐',
                      style: const TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          color: AppColors.lightTextSecondary),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      DateFormat('HH:mm').format(task.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.lightTextSecondary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Timeline spine: recessed groove + emoji status node + two-layer
          // (glow bed / crisp core) connector, ending in a fading tail.
          TimelineRail(
            accentColor: statusColor,
            isLast: isLast,
            capTop: capTop,
            node: TimelineNode(
              glyph: statusGlyph(task.status),
              accentColor: statusColor,
            ),
          ),
          const SizedBox(width: 14),

          // Task card — v1.12.13: hover lift + accent border highlight.
          Expanded(
            child: HoverLift(
              borderRadius: BorderRadius.circular(12),
              accentColor: statusColor,
              margin: const EdgeInsets.only(bottom: 20),
              builder: (context, hovered) => GestureDetector(
                onTap: () => context.push('/task/${task.id}'),
                child: TaskListCard(
                  accentColor: statusColor,
                  highlighted: hovered,
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.fromLTRB(0, 13, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Priority chip — the board's P0/P1/P2/P3 vocabulary
                          // instead of an unlabelled 6px dot.
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: priorityColor.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: priorityColor.withOpacity(0.34),
                              ),
                            ),
                            child: Text(
                              task.priority.shortLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: priorityColor,
                              ),
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
                          // Status badge: emoji + label, tinted and hair-lined.
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: statusColor.withOpacity(0.26),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(statusGlyph(task.status),
                                    style: const TextStyle(fontSize: 10)),
                                const SizedBox(width: 4),
                                Text(
                                  task.status.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ],
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary),
                          ),
                        ),
                      ],
                      // Execution log count
                      if (task.executionLog.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('🧾',
                                style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    color: AppColors.lightTextSecondary)),
                            const SizedBox(width: 5),
                            Text(
                              '${task.executionLog.length} log '
                              '${task.executionLog.length == 1 ? 'entry' : 'entries'}',
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
          ),
        ],
      ),
    );
  }

  Color _statusColor(TaskStatus status) {
    return AppColors.statusColor(status);
  }

  /// Absolute date, except today / yesterday which say so — "Today 14:05" is
  /// read faster than "2026-09-29 14:05".
  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    if (day == DateTime(now.year, now.month, now.day)) return 'Today';
    if (day.add(const Duration(days: 1)) ==
        DateTime(now.year, now.month, now.day)) {
      return 'Yesterday';
    }
    return DateFormat('yyyy-MM-dd').format(d);
  }
}
