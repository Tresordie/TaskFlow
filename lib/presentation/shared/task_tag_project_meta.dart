import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/task.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/color_settings_provider.dart';

/// Compact "project + tags" metadata row shown below the task title on
/// task cards across the Timeline / Calendar / Activity views.
///
/// Renders nothing when the task has neither a project nor tags, so
/// callers can place it unconditionally. Project and tag colors follow
/// the user's assignments in [colorSettingsProvider] (falling back to a
/// muted default when none is set).
class TaskTagProjectMeta extends ConsumerWidget {
  final Task task;

  /// When true, uses a tighter layout suitable for single-line list rows.
  final bool compact;

  const TaskTagProjectMeta({
    super.key,
    required this.task,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = ref.watch(colorSettingsProvider);
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

    final projectColor = colors.projectColor(project) ?? muted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (project.isNotEmpty) ...[
          Icon(Icons.folder_outlined, size: iconSize, color: projectColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              project,
              style: TextStyle(fontSize: fontSize, color: projectColor),
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
            child: Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < task.tags.length; i++) ...[
                    if (i > 0) TextSpan(text: '  ', style: TextStyle(fontSize: fontSize, color: muted)),
                    TextSpan(
                      text: '#${task.tags[i]}',
                      style: TextStyle(
                        fontSize: fontSize,
                        color: colors.tagColor(task.tags[i]) ?? muted,
                      ),
                    ),
                  ],
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
