import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import 'task_card_widget.dart';

class TaskBoardScreen extends ConsumerWidget {
  const TaskBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupedTasks = ref.watch(groupedTasksProvider);
    final tasksAsync = ref.watch(taskListProvider);
    final filter = ref.watch(taskFilterProvider);
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    final theme = Theme.of(context);

    return Column(
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
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: _QuickAddBar(),
        ),

        // Task list grouped by priority
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
                      _PrioritySectionHeader(priority: entry.key),
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
  Priority _priority = Priority.p2Medium;
  DateTime? _dueDate;
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _projectController.dispose();
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
                onPressed: () =>
                    setState(() => _expanded = !_expanded),
              ),
              // Submit button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  onPressed: _addTask,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
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
              child: Row(
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
                  // Project name input (sticky across quick-adds)
                  SizedBox(
                    width: 170,
                    height: 30,
                    child: TextField(
                      controller: _projectController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Project (e.g. Cosmo)',
                        prefixIcon: Icon(Icons.folder_outlined,
                            size: 14,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.5)),
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
    ref.read(taskListProvider.notifier).createTask(
          title: text,
          priority: _priority,
          dueDate: _dueDate,
          project: _projectController.text.trim(),
        );
    _controller.clear();
    setState(() {
      _priority = Priority.p2Medium;
      _dueDate = null;
      _expanded = false;
    });
  }
}

class _PrioritySectionHeader extends StatelessWidget {
  final Priority priority;

  const _PrioritySectionHeader({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.priorityColor(priority.index);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            priority.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
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
