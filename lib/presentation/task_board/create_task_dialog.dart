import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/task.dart';
import '../../providers/task_providers.dart';
import '../shared/markdown_editor_field.dart';
import '../shared/markdown_input.dart';
import '../shared/suggestion_field.dart';

class CreateTaskDialog extends ConsumerStatefulWidget {
  const CreateTaskDialog({super.key});

  @override
  ConsumerState<CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends ConsumerState<CreateTaskDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  late final FocusNode _descFocus;
  final _tagController = TextEditingController();
  final _subStepController = TextEditingController();
  Priority _priority = Priority.p2Medium;
  final List<String> _tags = [];
  final List<String> _subSteps = [];

  @override
  void initState() {
    super.initState();
    _descFocus = markdownIndentFocusNode(_descController);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _descFocus.dispose();
    _tagController.dispose();
    _subStepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Task'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title *',
                hintText: 'What needs to be done?',
              ),
            ),
            const SizedBox(height: 16),

            // Description — Markdown + rich-text with live Write/Preview
            MarkdownToolbar(
              controller: _descController,
              refocus: _descFocus,
            ),
            const SizedBox(height: 8),
            MarkdownEditorField(
              controller: _descController,
              focusNode: _descFocus,
              minLines: 3,
              maxLines: 6,
              hintText: 'Optional details... Markdown supported',
            ),
            const SizedBox(height: 16),

            // Priority selector
            Text('Priority', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<Priority>(
              segments: Priority.values
                  .map((p) => ButtonSegment(
                        value: p,
                        label: Text(p.shortLabel),
                      ))
                  .toList(),
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),

            // Tags
            Text('Tags', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SuggestionField(
                    controller: _tagController,
                    suggestions: ref.watch(distinctTagsProvider),
                    optionIcon: Icons.label_outline,
                    headerText: 'Recent tags',
                    decoration: const InputDecoration(
                      hintText: 'e.g. Metro, ATE, Firmware',
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addTag,
                ),
              ],
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _tags
                    .map((tag) => Chip(
                          label: Text(tag),
                          onDeleted: () => setState(() => _tags.remove(tag)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),

            // Sub-tasks
            Text('Sub-tasks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subStepController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Check torque spec, Run ATE',
                    ),
                    onSubmitted: (_) => _addSubStep(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addSubStep,
                ),
              ],
            ),
            if (_subSteps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _subSteps
                    .map((s) => Chip(
                          avatar: const Icon(Icons.checklist, size: 15),
                          label: Text(s),
                          onDeleted: () => setState(() => _subSteps.remove(s)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _createTask,
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  void _addSubStep() {
    final step = _subStepController.text.trim();
    if (step.isNotEmpty) {
      setState(() => _subSteps.add(step));
      _subStepController.clear();
    }
  }

  void _createTask() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    // Snapshot the live lists: createTask is async and not awaited;
    // guard against any future clear-before-read race.
    ref.read(taskListProvider.notifier).createTask(
          title: title,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          priority: _priority,
          tags: List<String>.of(_tags),
          subSteps: List<String>.of(_subSteps),
        );
    Navigator.of(context).pop();
  }
}
