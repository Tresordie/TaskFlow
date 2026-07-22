import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/task.dart';
import '../../core/theme/app_colors.dart';

/// Compact "created + due" metadata row shown on task cards across the
/// Today / Timeline / Calendar / Activity views.
///
/// Shows the creation date-time always, and the due date when present
/// (highlighted in the error color when overdue and not completed).
class TaskDateMeta extends StatelessWidget {
  final Task task;

  /// When true, uses a tighter layout suitable for single-line list rows.
  final bool compact;

  const TaskDateMeta({super.key, required this.task, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppColors.darkBorder
        : AppColors.lightTextSecondary;

    final created = DateFormat('MMM d, yyyy · HH:mm').format(task.createdAt);
    final due = task.dueDate;
    final now = DateTime.now();
    final isOverdue = due != null &&
        due.isBefore(now) &&
        task.status != TaskStatus.completed;

    final iconSize = compact ? 12.0 : 13.0;
    final fontSize = compact ? 10.5 : 11.0;
    final gap = compact ? 8.0 : 12.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: iconSize, color: muted),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            created,
            style: TextStyle(fontSize: fontSize, color: muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (due != null) ...[
          SizedBox(width: gap),
          Icon(
            Icons.event,
            size: iconSize,
            color: isOverdue ? AppColors.error : muted,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              'Due ${DateFormat('MMM d, yyyy').format(due)}',
              style: TextStyle(
                fontSize: fontSize,
                color: isOverdue ? AppColors.error : muted,
                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
