import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';

/// A dialog for editing an existing task's title, description, priority
/// and due date.
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => EditTaskDialog(task: task),
/// );
/// ```
class EditTaskDialog extends ConsumerStatefulWidget {
  final Task task;

  const EditTaskDialog({super.key, required this.task});

  @override
  ConsumerState<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends ConsumerState<EditTaskDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _projectController;
  final _subStepController = TextEditingController();
  late List<SubStep> _subSteps;
  late Priority _priority;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController =
        TextEditingController(text: widget.task.description ?? '');
    _projectController = TextEditingController(text: widget.task.project);
    _subSteps = List<SubStep>.from(widget.task.subSteps);
    _priority = widget.task.priority;
    _dueDate = widget.task.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _projectController.dispose();
    _subStepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.edit_outlined,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Edit Task', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Title field
              Text('Title', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Task title',
                ),
              ),
              const SizedBox(height: 16),

              // Project field
              Text('Project', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _projectController,
                decoration: const InputDecoration(
                  hintText: 'Project name (e.g. Cosmo, Metro)',
                  prefixIcon: Icon(Icons.folder_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 16),

              // Due date picker
              Text('Due Date', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(
                children: [
                  InkWell(
                    onTap: _pickDueDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: _dueDate != null
                            ? theme.colorScheme.primary.withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _dueDate != null
                              ? theme.colorScheme.primary.withOpacity(0.4)
                              : theme.colorScheme.outline.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: _dueDate != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface
                                    .withOpacity(0.5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _dueDate != null
                                ? DateFormat('yyyy-MM-dd (EEE)')
                                    .format(_dueDate!)
                                : 'No due date',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
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
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                      tooltip: 'Clear due date',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _dueDate = null),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Description field
              Text('Description', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Add more details (optional)',
                ),
              ),
              const SizedBox(height: 16),

              // Priority selector
              Text('Priority', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: Priority.values.map((p) {
                  final color = AppColors.priorityColor(p.index);
                  final isSelected = _priority == p;
                  return ChoiceChip(
                    label: Text(p.label),
                    selected: isSelected,
                    selectedColor: color.withOpacity(0.18),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? color
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? color.withOpacity(0.5)
                          : theme.colorScheme.outline.withOpacity(0.4),
                    ),
                    onSelected: (_) => setState(() => _priority = p),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Sub-tasks section
              Text('Sub-tasks', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (_subSteps.isNotEmpty)
                ..._subSteps.map((step) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            step.completed
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: step.completed
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface
                                    .withOpacity(0.35),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.85),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 14,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.4),
                            ),
                            tooltip: 'Remove sub-task',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                setState(() => _subSteps.remove(step)),
                          ),
                        ],
                      ),
                    )),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subStepController,
                      decoration: const InputDecoration(
                        hintText: 'Add a sub-task and press Enter',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addSubStep(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: _addSubStep,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final task = widget.task;
    task.title = title;
    task.description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    task.project = _projectController.text.trim();
    task.priority = _priority;
    task.dueDate = _dueDate;
    task.subSteps = _subSteps;

    ref.read(taskListProvider.notifier).updateTask(task);
    Navigator.pop(context);
  }

  void _addSubStep() {
    final text = _subStepController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subSteps = [
        ..._subSteps,
        SubStep()
          ..uid = const Uuid().v4()
          ..title = text
          ..completed = false,
      ];
    });
    _subStepController.clear();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      // Allow past dates so overdue tasks can be re-scheduled.
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }
}
