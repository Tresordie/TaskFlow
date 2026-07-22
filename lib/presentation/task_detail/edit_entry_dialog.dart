import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../data/services/attachment_service.dart';
import '../../providers/task_providers.dart';

/// Dialog for editing an already-sent execution-log entry.
///
/// The edited entry keeps its original uid and timestamp so it stays in
/// the same place in the timeline; only content, type and attachments
/// can change.
class EditExecutionEntryDialog extends ConsumerStatefulWidget {
  final int taskId;
  final ExecutionEntry entry;

  const EditExecutionEntryDialog({
    super.key,
    required this.taskId,
    required this.entry,
  });

  @override
  ConsumerState<EditExecutionEntryDialog> createState() =>
      _EditExecutionEntryDialogState();
}

class _EditExecutionEntryDialogState
    extends ConsumerState<EditExecutionEntryDialog> {
  late final TextEditingController _contentController;
  late EntryType _selectedType;
  late final List<Attachment> _attachments;
  bool _isPicking = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.entry.content);
    _selectedType = widget.entry.type;
    _attachments = List<Attachment>.from(widget.entry.attachments);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Text('Edit Log Entry'),
          const Spacer(),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss')
                .format(widget.entry.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type selector
              Wrap(
                spacing: 8,
                children: EntryType.values.map((type) {
                  final selected = _selectedType == type;
                  return ChoiceChip(
                    label: Text(type.label),
                    selected: selected,
                    selectedColor: _typeColor(type).withOpacity(0.2),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? _typeColor(type)
                          : AppColors.lightTextSecondary,
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedType = type),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Attachments (existing + add/remove)
              Row(
                children: [
                  Text(
                    'Attachments',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  _AddButton(
                    icon: Icons.image_outlined,
                    label: 'Image',
                    busy: _isPicking,
                    onPressed: _pickImages,
                  ),
                  const SizedBox(width: 8),
                  _AddButton(
                    icon: Icons.attach_file,
                    label: 'File',
                    busy: _isPicking,
                    onPressed: _pickFiles,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_attachments.isEmpty)
                Text(
                  'No attachments.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.lightTextSecondary,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _attachments
                      .map((a) => _AttachmentChip(
                            attachment: a,
                            onRemove: () =>
                                setState(() => _attachments.remove(a)),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 14),

              // Content (Markdown source)
              TextField(
                controller: _contentController,
                minLines: 4,
                maxLines: 12,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Entry content (Markdown supported)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickImages() async {
    setState(() => _isPicking = true);
    final picked = await AttachmentService.pickImages();
    if (!mounted) return;
    setState(() {
      _attachments.addAll(picked);
      _isPicking = false;
    });
  }

  Future<void> _pickFiles() async {
    setState(() => _isPicking = true);
    final picked = await AttachmentService.pickFiles();
    if (!mounted) return;
    setState(() {
      _attachments.addAll(picked);
      _isPicking = false;
    });
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    // Same rule as creating an entry: needs text or at least one attachment.
    if (content.isEmpty && _attachments.isEmpty) return;

    // Keep the original uid + timestamp so the entry stays in place.
    final updated = ExecutionEntry()
      ..uid = widget.entry.uid
      ..timestamp = widget.entry.timestamp
      ..content = content
      ..type = _selectedType
      ..attachments = List<Attachment>.from(_attachments);

    // Capture before awaiting so we never use a stale context.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);
    try {
      await ref.read(taskListProvider.notifier).updateExecutionEntry(
            widget.taskId,
            widget.entry.uid,
            updated,
          );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update log entry: $e')),
      );
    }
  }

  Color _typeColor(EntryType type) {
    switch (type) {
      case EntryType.note:
        return AppColors.info;
      case EntryType.pass:
        return AppColors.success;
      case EntryType.fail:
        return AppColors.error;
      case EntryType.blocked:
        return AppColors.warning;
    }
  }
}

/// Small outlined button used to add an image or a file attachment.
class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  const _AddButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
        foregroundColor: theme.colorScheme.primary,
      ),
      onPressed: busy ? null : onPressed,
    );
  }
}

/// An attachment row inside the edit dialog with a remove button.
class _AttachmentChip extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onRemove;

  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = attachment.type == AttachmentType.image;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(attachment.path),
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.broken_image, size: 18),
                    ),
                  ),
                )
              : Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  AttachmentService.formatSize(attachment.size),
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
