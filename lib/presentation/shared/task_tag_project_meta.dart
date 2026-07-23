import 'package:flutter/material.dart';
import '../../data/models/task.dart';
import '../../core/theme/app_colors.dart';

/// Compact "project + tags" metadata row shown below the task title on
/// task cards across the Timeline / Calendar / Activity views.
///
/// Renders nothing when the task has neither a project nor tags, so
/// callers can place it unconditionally.
class TaskTagProjectMeta extends StatelessWidget {
  final Task task;

  /// When true, uses a tighter layout suitable for single-line list rows.
  final bool compact;

  const TaskTagProjectMeta({
    super.key,
    required this.task,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppColors.darkBorder
        : AppColors.lightTextSecondary;

    final project = task.project.trim();
    if (project.isEmpty && task.tags.isEmpty) {
      return const SizedBox.shrink();
    }

    final iconSize = compact ? 12.0 : 13.0;
    final fontSize = compact ? 10.5 : 11.0;
    final gap = compact ? 8.0 : 12.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (project.isNotEmpty) ...[
          Icon(Icons.folder_outlined, size: iconSize, color: muted),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              project,
              style: TextStyle(fontSize: fontSize, color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (project.isNotEmpty && task.tags.isNotEmpty)
          SizedBox(width: gap),
        if (task.tags.isNotEmpty) ...[
          Icon(Icons.label_outline, size: iconSize, color: muted),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              task.tags.map((t) => '#$t').join('  '),
              style: TextStyle(fontSize: fontSize, color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
