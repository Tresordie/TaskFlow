import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../../providers/theme_provider.dart';
import 'task_card_widget.dart';

/// Display triple for a kanban column: name, header icon and accent color.
/// Accent colors follow [AppColors.statusColor] (the app-wide single source
/// of truth for status colors).
(String, IconData, Color) kanbanColumnVisualFor(TaskStatus status) {
  switch (status) {
    case TaskStatus.planned:
      return ('To Do', Icons.radio_button_unchecked,
          AppColors.statusColor(TaskStatus.planned));
    case TaskStatus.inProgress:
      return ('In Progress', Icons.play_arrow_rounded, AppColors.info);
    case TaskStatus.completed:
      return ('Done', Icons.check_circle_outline, AppColors.success);
    case TaskStatus.blocked:
      return ('Blocked', Icons.block, AppColors.error);
    case TaskStatus.archived:
      // Archived tasks live in the Done column; never a column of its own.
      return ('Done', Icons.check_circle_outline, AppColors.success);
  }
}

/// v1.10.0: one kanban column of the Today board (translate_tool-inspired):
/// status-tinted header with a count badge and a "+" quick-add button, a
/// status-colored hairline along the top edge, a breathing empty state, and
/// drop-anywhere status change. The whole column is a [DragTarget]; the
/// per-card drop target (sub-step conversion) takes precedence when the
/// pointer is over a card.
class KanbanColumn extends ConsumerStatefulWidget {
  final KanbanColumnData data;
  final String title;
  final IconData icon;
  final Color accent;
  final bool isAdding;
  final VoidCallback onStartAdd;
  final VoidCallback onCancelAdd;

  const KanbanColumn({
    super.key,
    required this.data,
    required this.title,
    required this.icon,
    required this.accent,
    required this.isAdding,
    required this.onStartAdd,
    required this.onCancelAdd,
  });

  @override
  ConsumerState<KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends ConsumerState<KanbanColumn> {
  final _addController = TextEditingController();
  final _addFocusNode = FocusNode();

  @override
  void dispose() {
    _addController.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  void _changeStatus(Task task) {
    final isDone = task.status == TaskStatus.completed ||
        task.status == TaskStatus.archived;
    final currentKey = isDone ? TaskStatus.completed : task.status;
    // Dropping a card onto the column it already belongs to (e.g. an
    // archived task dropped on Done) must not rewrite its status.
    if (currentKey == widget.data.status) return;
    ref.read(taskListProvider.notifier).updateStatus(task.id, widget.data.status);
  }

  void _submitAdd() {
    final title = _addController.text.trim();
    if (title.isEmpty) return;
    ref.read(taskListProvider.notifier).createTask(
          title: title,
          status: widget.data.status,
        );
    _addController.clear();
    _addFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.colorScheme;
    final appPalette = ref.watch(themeModeProvider).palette;
    final accent = widget.accent;
    final muted = palette.onSurface.withOpacity(0.5);

    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _changeStatus(details.data),
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: appPalette.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOver ? accent : palette.outline.withOpacity(0.45),
              width: isOver ? 1.5 : 1,
            ),
            boxShadow: isOver
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Stack(
            children: [
              // Status-colored hairline along the top edge (translate_tool's
              // column ::before).
              Positioned(
                top: 0,
                left: 18,
                right: 18,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      accent.withOpacity(0.0),
                      accent.withOpacity(0.85),
                      accent.withOpacity(0.0),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(theme, palette, accent, muted),
                    if (widget.isAdding) ...[
                      const SizedBox(height: 10),
                      _buildAddField(theme, palette),
                    ],
                    const SizedBox(height: 10),
                    Expanded(child: _buildContent(theme, palette, muted)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      ThemeData theme, ColorScheme palette, Color accent, Color muted) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: Icon(widget.icon, size: 14, color: accent),
        ),
        const SizedBox(width: 8),
        Text(
          widget.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: palette.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${widget.data.tasks.length}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        const Spacer(),
        // "+" opens the inline quick-add field; while adding it becomes ✕.
        IconButton(
          onPressed: widget.isAdding ? widget.onCancelAdd : widget.onStartAdd,
          tooltip: widget.isAdding ? 'Close' : 'Add task',
          icon: Icon(widget.isAdding ? Icons.close : Icons.add, size: 16),
          color: muted,
          hoverColor: accent.withOpacity(0.15),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints:
              const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ],
    );
  }

  Widget _buildAddField(ThemeData theme, ColorScheme palette) {
    return Row(
      children: [
        Expanded(
          child: Focus(
            focusNode: _addFocusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                widget.onCancelAdd();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _addController,
              focusNode: _addFocusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'New task...',
                isDense: true,
                filled: true,
                fillColor: palette.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: palette.outline.withOpacity(0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: palette.outline.withOpacity(0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: palette.primary.withOpacity(0.6), width: 1.2),
                ),
              ),
              onSubmitted: (_) => _submitAdd(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Explicit add button (never rely on Enter alone).
        IconButton(
          onPressed: _submitAdd,
          tooltip: 'Add',
          icon: Icon(Icons.add_circle, size: 18, color: palette.primary),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme palette, Color muted) {
    if (widget.data.tasks.isEmpty) {
      // Breathing dashed-style empty box, inviting a drag.
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: palette.outline.withOpacity(0.45)),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 26, color: muted),
            const SizedBox(height: 8),
            Text(
              'Drag tasks here',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
      )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fade(begin: 0.55, end: 1.0, duration: 1800.ms);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      itemCount: widget.data.tasks.length,
      separatorBuilder: (context, separatorIndex) =>
          const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = widget.data.tasks[index];
        return TaskCard(key: ValueKey(task.id), task: task)
            .animate()
            .fadeIn(
              duration: 260.ms,
              delay: (40 * (index < 8 ? index : 8)).ms,
            )
            .slideY(
              begin: 0.06,
              end: 0,
              duration: 260.ms,
              delay: (40 * (index < 8 ? index : 8)).ms,
              curve: Curves.easeOut,
            );
      },
    );
  }
}
