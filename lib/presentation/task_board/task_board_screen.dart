import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/color_settings_provider.dart';
import '../../providers/task_providers.dart';
import '../shared/suggestion_field.dart';
import '../shared/wheel_forward.dart';
import 'task_card_widget.dart';

class TaskBoardScreen extends ConsumerWidget {
  const TaskBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupedTasks = ref.watch(groupedTasksByModeProvider);
    final tasksAsync = ref.watch(taskListProvider);
    final filter = ref.watch(taskFilterProvider);
    final groupMode = ref.watch(taskGroupModeProvider);
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Forward mouse-wheel events over the fixed header / quick-add area
        // to the task list below, so the page scrolls even when the pointer
        // isn't directly over the list.
        WheelForward(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with themed accent bar
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
                        Text(
                          'Today',
                          style: theme.textTheme.headlineLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        today,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

              // Active filter banner (set e.g. by tapping an Activity stat card)
              if (filter.isActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          onTap: () => ref
                              .read(taskFilterProvider.notifier)
                              .state = TaskFilter(),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                ),

              // Quick Add Bar (enhanced with priority + due date)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                child: _QuickAddBar(),
              ),

              // Group-by selector
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
                child: Row(
                  children: [
                    Icon(Icons.group_work_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.45)),
                    const SizedBox(width: 6),
                    Text(
                      'Group by:',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...TaskGroupMode.values.map((mode) {
                      final isActive = groupMode == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: GestureDetector(
                          onTap: () => ref
                              .read(taskGroupModeProvider.notifier)
                              .state = mode,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? theme.colorScheme.primary.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isActive
                                    ? theme.colorScheme.primary.withOpacity(0.5)
                                    : theme.colorScheme.outline
                                        .withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              mode.label,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Task list grouped by selected mode
        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (_) {
              final hasTasks =
                  groupedTasks.values.any((list) => list.isNotEmpty);
              if (!hasTasks) {
                return _EmptyState();
              }
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                children: [
                  for (final entry in groupedTasks.entries)
                    if (entry.value.isNotEmpty) ...[
                      _GroupSectionHeader(
                        label: entry.key,
                        color: _groupColor(groupMode, entry.key, ref, theme),
                      ),
                      const SizedBox(height: 8),
                      ...entry.value.asMap().entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TaskCard(task: e.value),
                            )
                                .animate()
                                .fadeIn(
                                  duration: 260.ms,
                                  delay: (80 + e.key * 40).ms,
                                )
                                .slideY(
                                  begin: 0.06,
                                  end: 0,
                                  duration: 260.ms,
                                  delay: (80 + e.key * 40).ms,
                                  curve: Curves.easeOut,
                                ),
                          ),
                      const SizedBox(height: 16),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Resolves the color for a group header so it matches how the same
  /// attribute is colored on the task detail page (priority / status use
  /// their fixed colors; project / tag use the user-assigned color, or a
  /// muted tone when none is set).
  Color _groupColor(
      TaskGroupMode mode, String label, WidgetRef ref, ThemeData theme) {
    final fallback = theme.colorScheme.primary;
    final muted = theme.brightness == Brightness.dark
        ? AppColors.darkBorder
        : AppColors.lightTextSecondary;

    switch (mode) {
      case TaskGroupMode.priority:
        final p = Priority.values.where((p) => p.label == label).firstOrNull;
        return p == null ? fallback : AppColors.priorityColor(p.index);

      case TaskGroupMode.status:
        final s = TaskStatus.values.where((s) => s.label == label).firstOrNull;
        return s == null ? fallback : AppColors.statusColor(s);

      case TaskGroupMode.project:
        if (label == 'No Project') return muted;
        return ref.read(colorSettingsProvider).projectColor(label) ?? muted;

      case TaskGroupMode.tag:
        if (label == 'No Tag') return muted;
        return ref.read(colorSettingsProvider).tagColor(label) ?? muted;

      case TaskGroupMode.none:
        return fallback;
    }
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
}

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

class _GroupSectionHeader extends StatelessWidget {
  final String label;
  final Color? color;

  const _GroupSectionHeader({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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
            'Add a task above to get started',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
