import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../shared/suggestion_field.dart';
import 'kanban_column.dart';

/// v1.10.0: Today page redesigned as a translate_tool-inspired kanban —
/// four KPI stat cards, quick-filter pills in the header, and a fixed
/// four-column board (To Do / In Progress / Done / Blocked). Dragging a
/// card onto a column changes its status; dragging it onto another card
/// still converts it into a sub-step. Archived tasks render in the Done
/// column (app-wide `completed || archived` convention).
class TaskBoardScreen extends ConsumerStatefulWidget {
  const TaskBoardScreen({super.key});

  @override
  ConsumerState<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends ConsumerState<TaskBoardScreen> {
  // Column currently showing its inline quick-add field (null = none).
  TaskStatus? _addingColumnStatus;

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(kanbanBoardProvider);
    final tasksAsync = ref.watch(taskListProvider);
    final filter = ref.watch(taskFilterProvider);
    final quickFilter = ref.watch(boardQuickFilterProvider);
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme, today, quickFilter),

        // Active filter banner (set e.g. by tapping an Activity stat card)
        if (filter.isActive) _buildFilterBanner(theme, filter),

        // Quick Add Bar (creates into the To Do column)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 4),
          child: _QuickAddBar(),
        ),

        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (_) => _buildBody(theme, board, filter, quickFilter),
          ),
        ),
      ],
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(
      ThemeData theme, String today, BoardQuickFilter quickFilter) {
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
      child: Row(
        children: [
          Column(
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
          const Spacer(),
          _buildQuickFilterPills(theme, quickFilter),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  /// Segmented quick-filter pills (All / Due Today / High Priority),
  /// translate_tool-style inset segmented control.
  Widget _buildQuickFilterPills(ThemeData theme, BoardQuickFilter current) {
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
          for (final f in BoardQuickFilter.values)
            GestureDetector(
              onTap: () =>
                  ref.read(boardQuickFilterProvider.notifier).state = f,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: current == f ? palette.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: current == f ? FontWeight.w600 : FontWeight.w400,
                    color: current == f
                        ? Colors.white
                        : palette.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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

  // ─── Body: KPI cards + board ──────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, KanbanBoardData board, TaskFilter filter,
      BoardQuickFilter quickFilter) {
    final boardVisible = board.columns.any((c) => c.tasks.isNotEmpty);
    final showEmptyState = !boardVisible &&
        !filter.isActive &&
        quickFilter == BoardQuickFilter.all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKpiRow(theme, board),
        Expanded(
          child: showEmptyState
              ? _EmptyState()
              : _buildBoard(theme, board),
        ),
      ],
    );
  }

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
      ),
      _KpiCardData(
        label: 'TO DO',
        value: '${board.plannedCount}',
        sub: board.overdueCount > 0
            ? '${board.overdueCount} overdue'
            : 'Nothing overdue',
        subColor:
            board.overdueCount > 0 ? AppColors.error : null,
        accent: AppColors.statusColor(TaskStatus.planned),
      ),
      _KpiCardData(
        label: 'IN PROGRESS',
        value: '${board.inProgressCount}',
        sub: '${board.highPriorityInProgress} high priority',
        accent: AppColors.info,
      ),
      _KpiCardData(
        label: 'DONE',
        value: '${board.doneCount}',
        sub: '${(board.completionPct * 100).round()}% completion',
        accent: AppColors.success,
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

  Widget _buildBoard(ThemeData theme, KanbanBoardData board) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 14.0;
      // Columns share the width equally once it fits; below 4×252px the
      // board scrolls horizontally instead of squeezing the cards.
      final colWidth = max(252.0, (constraints.maxWidth - gap * 3) / 4);
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 6, 28, 14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, col) in board.columns.indexed) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(width: colWidth, child: _buildColumn(col)),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildColumn(KanbanColumnData col) {
    final (title, icon, accent) = kanbanColumnVisualFor(col.status);
    return KanbanColumn(
      key: ValueKey('kanban-col-${col.status.name}'),
      data: col,
      title: title,
      icon: icon,
      accent: accent,
      isAdding: _addingColumnStatus == col.status,
      onStartAdd: () => setState(() => _addingColumnStatus = col.status),
      onCancelAdd: () => setState(() => _addingColumnStatus = null),
    );
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

  const _KpiCardData({
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
    this.subColor,
    this.progress,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiCardData data;
  final ColorScheme palette;

  const _KpiCard({required this.data, required this.palette});

  @override
  Widget build(BuildContext context) {
    final muted = palette.onSurface.withOpacity(0.5);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.outline.withOpacity(0.5)),
        boxShadow: [
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
                color: data.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
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
            color: palette.outline.withOpacity(0.25),
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
