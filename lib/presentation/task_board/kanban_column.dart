import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../../providers/theme_provider.dart';
import 'task_card_widget.dart';

/// v1.10.0 / v1.11.0: one kanban column of the Today board
/// (translate_tool-inspired): status-tinted header with a count badge and a
/// "+" quick-add button, a colored hairline along the top edge, a soft
/// accent gradient fading down the column, a breathing empty state, and
/// drop-anywhere semantics. The whole column is a [DragTarget]; the
/// per-card drop target (sub-step conversion) takes precedence when the
/// pointer is over a card. What a drop *means* is decided by the screen
/// via [onDropTask] (depends on the board dimension).
class KanbanColumn extends ConsumerStatefulWidget {
  final KanbanColumnData data;
  final String title;
  final IconData icon;
  final Color accent;
  final bool isAdding;
  final VoidCallback onStartAdd;
  final VoidCallback onCancelAdd;
  final ValueChanged<Task> onDropTask;
  final ValueChanged<String> onSubmitAdd;

  const KanbanColumn({
    super.key,
    required this.data,
    required this.title,
    required this.icon,
    required this.accent,
    required this.isAdding,
    required this.onStartAdd,
    required this.onCancelAdd,
    required this.onDropTask,
    required this.onSubmitAdd,
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

  void _submitAdd() {
    final title = _addController.text.trim();
    if (title.isEmpty) return;
    // What the new task inherits from this column depends on the board
    // dimension — the screen decides (status / priority / project).
    widget.onSubmitAdd(title);
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
      onAcceptWithDetails: (details) => widget.onDropTask(details.data),
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: appPalette.bg,
            // Soft accent wash fading down the column — gives each column a
            // quiet color identity without hurting card contrast.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.55],
              colors: [
                accent.withOpacity(0.05),
                accent.withOpacity(0.0),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isOver ? accent : palette.outline.withOpacity(0.4),
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
              // Accent hairline along the top edge (translate_tool's column
              // ::before).
              Positioned(
                top: 0,
                left: 20,
                right: 20,
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
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withOpacity(0.20),
                accent.withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: accent.withOpacity(0.30)),
          ),
          child: Icon(widget.icon, size: 15, color: accent),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
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
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
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

    return Scrollbar(
      thumbVisibility: false,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 2, bottom: 4, right: 2),
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
      ),
    );
  }
}
