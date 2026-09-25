import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/color_settings_provider.dart';
import '../../providers/task_providers.dart';
import '../shared/suggestion_field.dart';
import 'kanban_column.dart';

/// v1.10.0 / v1.11.0: Today page redesigned as a translate_tool-inspired
/// kanban — four KPI stat cards, a toolbar with quick-filter pills and a
/// board dimension switcher (Status / Project / Priority), and a board
/// whose columns depend on the dimension. Dropping a card onto a column
/// applies that column's attribute; dropping it onto another card still
/// converts it into a sub-step. Archived tasks render in the Done column
/// (app-wide `completed || archived` convention).
class TaskBoardScreen extends ConsumerStatefulWidget {
  const TaskBoardScreen({super.key});

  @override
  ConsumerState<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends ConsumerState<TaskBoardScreen> {
  // Column (by bucket key) currently showing its inline quick-add field.
  String? _addingColumnKey;

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(kanbanBoardProvider);
    final tasksAsync = ref.watch(taskListProvider);
    final filter = ref.watch(taskFilterProvider);
    final quickFilter = ref.watch(boardQuickFilterProvider);
    final dimension = ref.watch(boardDimensionProvider);
    final colorSettings = ref.watch(colorSettingsProvider);
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    final theme = Theme.of(context);

    return Stack(
      children: [
        // Ambient decorative backdrop (soft color wash + drifting orbs),
        // behind all content and ignoring the pointer.
        Positioned.fill(
          child: IgnorePointer(child: _buildBackdrop(theme)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme, today),

            // Active filter banner (set e.g. by tapping an Activity stat card)
            if (filter.isActive) _buildFilterBanner(theme, filter),

            // Quick Add Bar (creates into the To Do column)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 4),
              child: _QuickAddBar(),
            ),

            Expanded(
              child: tasksAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (_) => _buildBody(
                    theme, board, filter, quickFilter, dimension, colorSettings),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Ambient backdrop ─────────────────────────────────────────────────────

  /// Soft page wash plus three slowly drifting color orbs — the quiet
  /// "texture" layer behind the board (translate_tool's ambient orbs).
  Widget _buildBackdrop(ThemeData theme) {
    final palette = theme.colorScheme;

    Widget orb(Color color, double size, double opacity) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0.0)],
          ),
        ),
      )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .moveX(
            begin: -18,
            end: 18,
            duration: 14000.ms,
            curve: Curves.easeInOut,
          );
    }

    return Stack(
      children: [
        // Whole-page wash: surface fading into a faint primary tint.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.surface,
                  Color.alphaBlend(
                      palette.primary.withOpacity(0.025), palette.surface),
                ],
              ),
            ),
          ),
        ),
        Positioned(top: -140, right: -100, child: orb(palette.primary, 460, 0.07)),
        Positioned(top: 300, left: -160, child: orb(palette.secondary, 420, 0.05)),
        Positioned(bottom: -160, right: 160, child: orb(AppColors.success, 380, 0.04)),
      ],
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, String today) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Text('Today', style: theme.textTheme.headlineLarge),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(today, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildFilterBanner(ThemeData theme, TaskFilter filter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_alt,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _describeFilter(filter),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            InkWell(
              onTap: () =>
                  ref.read(taskFilterProvider.notifier).state = TaskFilter(),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _describeFilter(TaskFilter f) {
    final parts = <String>[];
    if (f.status != null) parts.add('Status: ${f.status!.label}');
    if (f.date != null) {
      parts.add('Date: ${DateFormat('MMM d, yyyy').format(f.date!)}');
    }
    if (f.priority != null) parts.add('Priority: ${f.priority!.label}');
    if (f.tag != null && f.tag!.isNotEmpty) parts.add('Tag: ${f.tag}');
    return parts.isEmpty ? 'Filtered' : 'Filtered · ${parts.join(' · ')}';
  }

  // ─── Body: KPI cards + toolbar + board ────────────────────────────────────

  Widget _buildBody(
      ThemeData theme,
      KanbanBoardData board,
      TaskFilter filter,
      BoardQuickFilter quickFilter,
      BoardDimension dimension,
      ColorSettings colorSettings) {
    final boardVisible = board.columns.any((c) => c.tasks.isNotEmpty);
    final showEmptyState = !boardVisible &&
        !filter.isActive &&
        quickFilter == BoardQuickFilter.all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKpiRow(theme, board),
        _buildToolbar(theme, quickFilter, dimension),
        Expanded(
          child: showEmptyState
              ? _EmptyState()
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null)
                        Positioned.fill(child: currentChild),
                    ],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey('board-${dimension.name}'),
                    child:
                        _buildBoard(theme, board, dimension, colorSettings),
                  ),
                ),
        ),
      ],
    );
  }

  // ─── Toolbar: quick filter pills + dimension switcher ─────────────────────

  Widget _buildToolbar(ThemeData theme, BoardQuickFilter quickFilter,
      BoardDimension dimension) {
    final pills = _buildQuickFilterPills(theme, quickFilter);
    final dimensionControl = _buildDimensionControl(theme, dimension);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      // On narrow windows the two segmented controls stack instead of
      // overflowing (lesson 8.7).
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pills,
              const SizedBox(height: 8),
              dimensionControl,
            ],
          );
        }
        return Row(
          children: [pills, const Spacer(), dimensionControl],
        );
      }),
    );
  }

  /// Segmented quick-filter pills (All / Due Today / High Priority).
  Widget _buildQuickFilterPills(ThemeData theme, BoardQuickFilter current) {
    return _segmentedControl<BoardQuickFilter>(
      theme: theme,
      current: current,
      values: BoardQuickFilter.values,
      label: (f) => f.label,
      onSelect: (f) => ref.read(boardQuickFilterProvider.notifier).state = f,
    );
  }

  /// Segmented board dimension switcher (Status / Project / Priority).
  Widget _buildDimensionControl(ThemeData theme, BoardDimension current) {
    return _segmentedControl<BoardDimension>(
      theme: theme,
      current: current,
      values: BoardDimension.values,
      label: (d) => d.label,
      icon: (d) => switch (d) {
        BoardDimension.status => Icons.view_kanban_outlined,
        BoardDimension.project => Icons.folder_outlined,
        BoardDimension.priority => Icons.flag_rounded,
      },
      onSelect: (d) {
        ref.read(boardDimensionProvider.notifier).state = d;
        setState(() => _addingColumnKey = null);
      },
    );
  }

  Widget _segmentedControl<T>({
    required ThemeData theme,
    required T current,
    required List<T> values,
    required String Function(T) label,
    IconData Function(T)? icon,
    required ValueChanged<T> onSelect,
  }) {
    final palette = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            GestureDetector(
              onTap: () => onSelect(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      current == value ? palette.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon(value),
                        size: 13,
                        color: current == value
                            ? Colors.white
                            : palette.onSurface.withOpacity(0.55),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      label(value),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: current == value
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: current == value
                            ? Colors.white
                            : palette.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── KPI stat cards ───────────────────────────────────────────────────────

  Widget _buildKpiRow(ThemeData theme, KanbanBoardData board) {
    final palette = theme.colorScheme;
    final cards = [
      _KpiCardData(
        label: "TODAY'S PROGRESS",
        value: '${(board.todayProgressPct * 100).round()}%',
        sub: board.dueTodayTotal == 0
            ? 'Nothing due today'
            : '${board.dueTodayDone} of ${board.dueTodayTotal} due today done',
        accent: palette.primary,
        progress: board.todayProgressPct,
        icon: Icons.event_available_rounded,
      ),
      _KpiCardData(
        label: 'TO DO',
        value: '${board.plannedCount}',
        sub: board.overdueCount > 0
            ? '${board.overdueCount} overdue'
            : 'Nothing overdue',
        subColor: board.overdueCount > 0 ? AppColors.error : null,
        accent: AppColors.statusColor(TaskStatus.planned),
        icon: Icons.inbox_outlined,
      ),
      _KpiCardData(
        label: 'IN PROGRESS',
        value: '${board.inProgressCount}',
        sub: '${board.highPriorityInProgress} high priority',
        accent: AppColors.info,
        icon: Icons.play_arrow_rounded,
      ),
      _KpiCardData(
        label: 'DONE',
        value: '${board.doneCount}',
        sub: '${(board.completionPct * 100).round()}% completion',
        accent: AppColors.success,
        icon: Icons.check_circle_outline,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      child: Row(
        children: [
          for (final (i, data) in cards.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: _KpiCard(data: data, palette: palette)),
          ],
        ],
      ),
    );
  }

  // ─── Board ────────────────────────────────────────────────────────────────

  Widget _buildBoard(ThemeData theme, KanbanBoardData board,
      BoardDimension dimension, ColorSettings colorSettings) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 14.0;
      // Columns share the width equally once it fits; below 4×252px the
      // board scrolls horizontally instead of squeezing the cards.
      final colWidth = max(252.0, (constraints.maxWidth - gap * 3) / 4);
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, col) in board.columns.indexed) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: colWidth,
                    child: _buildColumn(col, dimension, colorSettings),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildColumn(KanbanColumnData col, BoardDimension dimension,
      ColorSettings colorSettings) {
    final (title, icon, accent) =
        _columnVisual(col, dimension, colorSettings);
    return KanbanColumn(
      key: ValueKey('kanban-col-${dimension.name}-${col.key}'),
      data: col,
      title: title,
      icon: icon,
      accent: accent,
      isAdding: _addingColumnKey == col.key,
      onStartAdd: () => setState(() => _addingColumnKey = col.key),
      onCancelAdd: () => setState(() => _addingColumnKey = null),
      onDropTask: (task) => _handleColumnDrop(col, task, dimension),
      onSubmitAdd: (title) =>
          _handleColumnSubmitAdd(col, title, dimension),
    );
  }

  /// Resolves title / icon / accent per dimension. Status accents follow
  /// [AppColors.statusColor] (single source of truth), priority accents the
  /// fixed priority colors, project accents the user-assigned color.
  (String, IconData, Color) _columnVisual(KanbanColumnData col,
      BoardDimension dimension, ColorSettings colorSettings) {
    switch (dimension) {
      case BoardDimension.status:
        return _statusColumnVisual(TaskStatus.values.byName(col.key));

      case BoardDimension.priority:
        final p = Priority.values[int.parse(col.key)];
        return (p.label, Icons.flag_rounded, AppColors.priorityColor(p.index));

      case BoardDimension.project:
        final accent = colorSettings.projectColor(col.key) ??
            AppColors.statusColor(TaskStatus.planned);
        return (
          col.key.isEmpty ? 'No Project' : col.key,
          Icons.folder_outlined,
          accent
        );
    }
  }

  (String, IconData, Color) _statusColumnVisual(TaskStatus status) {
    switch (status) {
      case TaskStatus.planned:
        return ('To Do', Icons.radio_button_unchecked,
            AppColors.statusColor(TaskStatus.planned));
      case TaskStatus.inProgress:
        return ('In Progress', Icons.play_arrow_rounded, AppColors.info);
      case TaskStatus.completed:
      case TaskStatus.archived:
        return ('Done', Icons.check_circle_outline, AppColors.success);
      case TaskStatus.blocked:
        return ('Blocked', Icons.block, AppColors.error);
    }
  }

  // ─── Drop / add semantics per dimension ───────────────────────────────────

  void _handleColumnDrop(
      KanbanColumnData col, Task task, BoardDimension dimension) {
    final notifier = ref.read(taskListProvider.notifier);
    switch (dimension) {
      case BoardDimension.status:
        if (statusColumnKeyOf(task) == col.key) return;
        notifier.updateStatus(task.id, TaskStatus.values.byName(col.key));

      case BoardDimension.priority:
        if (task.priority.index.toString() == col.key) return;
        final updated = task..priority = Priority.values[int.parse(col.key)];
        notifier.updateTask(updated);

      case BoardDimension.project:
        if (task.project == col.key) return;
        final updated = task..project = col.key;
        notifier.updateTask(updated);
    }
  }

  void _handleColumnSubmitAdd(
      KanbanColumnData col, String title, BoardDimension dimension) {
    final notifier = ref.read(taskListProvider.notifier);
    switch (dimension) {
      case BoardDimension.status:
        notifier.createTask(
            title: title, status: TaskStatus.values.byName(col.key));
      case BoardDimension.priority:
        notifier.createTask(
            title: title, priority: Priority.values[int.parse(col.key)]);
      case BoardDimension.project:
        notifier.createTask(title: title, project: col.key);
    }
  }
}

// ─── KPI stat cards ──────────────────────────────────────────────────────────

class _KpiCardData {
  final String label;
  final String value;
  final String sub;
  final Color accent;
  final Color? subColor;
  final double? progress;
  final IconData icon;

  const _KpiCardData({
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
    required this.icon,
    this.subColor,
    this.progress,
  });
}

class _KpiCard extends StatefulWidget {
  final _KpiCardData data;
  final ColorScheme palette;

  const _KpiCard({required this.data, required this.palette});

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = widget.palette;
    final muted = palette.onSurface.withOpacity(0.5);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -2.0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          // Subtle accent-tinted wash toward the bottom-right corner — the
          // "texture" layer on top of the flat surface color.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface,
              Color.alphaBlend(
                  data.accent.withOpacity(0.07), palette.surface),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: palette.outline.withOpacity(_hovered ? 0.7 : 0.5),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: data.accent.withOpacity(0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Stack(
          children: [
            // Left accent bar (translate_tool's KPI ::before).
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      data.accent,
                      data.accent.withOpacity(0.35),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Accent icon chip (top-right).
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: data.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, size: 15, color: data.accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    data.value,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.sub,
                    style: TextStyle(
                        fontSize: 11, color: data.subColor ?? muted),
                  ),
                  if (data.progress != null) ...[
                    const SizedBox(height: 8),
                    _progressBar(data.progress!, palette),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(double progress, ColorScheme palette) {
    final clamped = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(
            height: 6,
            color: widget.palette.outline.withOpacity(0.25),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: clamped),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => FractionallySizedBox(
              widthFactor: value,
              alignment: Alignment.centerLeft,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [palette.primary, palette.secondary],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick add bar (unchanged behaviour, creates planned tasks) ─────────────

class _QuickAddBar extends ConsumerStatefulWidget {
  @override
  ConsumerState<_QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<_QuickAddBar> {
  final _controller = TextEditingController();
  final _projectController = TextEditingController();
  final _tagController = TextEditingController();
  final _subStepController = TextEditingController();
  final List<String> _subSteps = [];
  Priority _priority = Priority.p2Medium;
  DateTime? _dueDate;
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _projectController.dispose();
    _tagController.dispose();
    _subStepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded
              ? theme.colorScheme.primary.withOpacity(0.4)
              : theme.colorScheme.outline.withOpacity(0.5),
        ),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        children: [
          // Main input row
          Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.add_circle_outline,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Add a task...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onTap: () => setState(() => _expanded = true),
                  onSubmitted: (_) => _addTask(),
                ),
              ),
              // Expand/collapse options
              IconButton(
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              // Submit button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  onPressed: _addTask,
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Add', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),

          // Expanded options: priority + due date
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Priority selector
                      Text('Priority:',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 12)),
                      const SizedBox(width: 8),
                      ...Priority.values.map((p) {
                        final color = AppColors.priorityColor(p.index);
                        final isSelected = _priority == p;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _priority = p),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : color.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                p.shortLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 20),
                      // Due date picker
                      GestureDetector(
                        onTap: _pickDueDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _dueDate != null
                                ? theme.colorScheme.primary.withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _dueDate != null
                                  ? theme.colorScheme.primary.withOpacity(0.4)
                                  : theme.colorScheme.outline.withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 13,
                                  color: _dueDate != null
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.5)),
                              const SizedBox(width: 6),
                              Text(
                                _dueDate != null
                                    ? DateFormat('MMM d').format(_dueDate!)
                                    : 'Due date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _dueDate != null
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_dueDate != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _dueDate = null),
                          child: Icon(Icons.close,
                              size: 14,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.4)),
                        ),
                      ],
                      const Spacer(),
                      // Tags input (comma-separated, with history autocomplete)
                      SizedBox(
                        width: 150,
                        height: 30,
                        child: SuggestionField(
                          controller: _tagController,
                          commaSeparated: true,
                          suggestions: ref.watch(distinctTagsProvider),
                          optionIcon: Icons.label_outline,
                          headerText: 'Recent tags',
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Tags (a, b)',
                            prefixIcon: Icon(Icons.label_outline,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5)),
                            prefixIconConstraints: const BoxConstraints(
                                minWidth: 30, minHeight: 0),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.4)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.4)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Project name input (sticky across quick-adds, with history autocomplete)
                      SizedBox(
                        width: 170,
                        height: 30,
                        child: SuggestionField(
                          controller: _projectController,
                          suggestions: ref.watch(distinctProjectsProvider),
                          optionIcon: Icons.folder_outlined,
                          headerText: 'Recent projects',
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Project (e.g. Cosmo)',
                            prefixIcon: Icon(Icons.folder_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5)),
                            prefixIconConstraints: const BoxConstraints(
                                minWidth: 30, minHeight: 0),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.4)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.4)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Sub-tasks row
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.checklist,
                            size: 15,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 30,
                            child: TextField(
                              controller: _subStepController,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText:
                                    'Sub-task, press Enter to add (repeatable)',
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withOpacity(0.4)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withOpacity(0.4)),
                                ),
                              ),
                              onSubmitted: (_) => _addSubStep(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: _addSubStep,
                        ),
                      ],
                    ),
                  ),
                  if (_subSteps.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _subSteps
                            .map((s) => Chip(
                                  avatar: const Icon(Icons.checklist, size: 13),
                                  label: Text(s,
                                      style: const TextStyle(fontSize: 11)),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onDeleted: () =>
                                      setState(() => _subSteps.remove(s)),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  void _addTask() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final tags = _tagController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // Snapshot the live list: createTask is async and not awaited here,
    // while _subSteps is cleared synchronously below. Passing the live
    // list would let the repository read an already-empty list.
    ref.read(taskListProvider.notifier).createTask(
          title: text,
          priority: _priority,
          dueDate: _dueDate,
          tags: tags,
          subSteps: List<String>.of(_subSteps),
          project: _projectController.text.trim(),
        );
    _controller.clear();
    _tagController.clear();
    setState(() {
      _subSteps.clear();
      _priority = Priority.p2Medium;
      _dueDate = null;
      _expanded = false;
    });
  }

  void _addSubStep() {
    final text = _subStepController.text.trim();
    if (text.isEmpty) return;
    setState(() => _subSteps.add(text));
    _subStepController.clear();
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline,
              size: 36,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1.0, end: 1.06, duration: 1400.ms),
          const SizedBox(height: 16),
          Text(
            'No tasks yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a task above or press + on a column to get started',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
