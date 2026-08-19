import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/markdown/html_sanitize.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/open_folder.dart';
import '../../data/models/task.dart';
import '../../data/services/attachment_service.dart';
import '../../providers/task_providers.dart';
import '../../providers/typography_provider.dart';
import '../shared/selectable_markdown_body.dart';
import '../shared/markdown_editor_field.dart';
import '../shared/markdown_input.dart';

class ExecutionLogWidget extends ConsumerStatefulWidget {
  final Task task;

  const ExecutionLogWidget({super.key, required this.task});

  @override
  ConsumerState<ExecutionLogWidget> createState() => _ExecutionLogWidgetState();
}

class _ExecutionLogWidgetState extends ConsumerState<ExecutionLogWidget> {
  final _entryController = TextEditingController();
  late final FocusNode _entryFocus = FocusNode(onKeyEvent: (node, event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          MarkdownInput.outdent(_entryController);
        } else {
          MarkdownInput.indent(_entryController);
        }
        return KeyEventResult.handled;
      }
      // v1.4.83: Ctrl+V with an IMAGE on the clipboard (no text) attaches the
      // clipboard image; with text on the clipboard the normal paste runs.
      if (event.logicalKey == LogicalKeyboardKey.keyV &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        _maybePasteClipboardImage();
      }
    }
    return KeyEventResult.ignored;
  });
  EntryType _selectedType = EntryType.note;

  // Resizable text input area height (logical pixels).
  double _textAreaHeight = 74;
  static const double _minTextAreaHeight = 40;
  static const double _maxTextAreaHeight = 320;

  // Attachments staged for the next entry.
  final List<Attachment> _pendingAttachments = [];
  bool _isPicking = false;

  // v1.4.90: inline edit — pressing Edit on a record loads its content,
  // type and attachments into THIS input area; sending updates the record
  // in place instead of creating a new entry.
  ExecutionEntry? _editingEntry;

  @override
  void dispose() {
    _entryController.dispose();
    _entryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.task.executionLog.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                'Execution Log',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entries.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Entry list
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note,
                          size: 48, color: AppColors.lightBorder),
                      const SizedBox(height: 12),
                      Text(
                        'No entries yet.\nRecord your execution process below.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _LogEntryItem(
                      entry: entry,
                      isLatest: index == 0,
                      isLast: index == entries.length - 1,
                      isEditing: _editingEntry?.uid == entry.uid,
                      onEdit: () => _editEntry(entry),
                      onDelete: () => _deleteEntry(entry),
                    );
                  },
                ),
        ),

        // Input area (vertically resizable via the grip handle)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
            ),
          ),
          child: Column(
            children: [
              // Resize grip handle
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  setState(() {
                    // Dragging up (negative dy) grows the input area.
                    _textAreaHeight = (_textAreaHeight - details.delta.dy)
                        .clamp(_minTextAreaHeight, _maxTextAreaHeight);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: SizedBox(
                    height: 14,
                    width: double.infinity,
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Type selector + attach buttons
              Row(
                children: [
                  ...EntryType.values.map((type) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(type.label),
                          selected: _selectedType == type,
                          selectedColor: _typeColor(type).withOpacity(0.2),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _selectedType == type
                                ? _typeColor(type)
                                : AppColors.lightTextSecondary,
                          ),
                          onSelected: (_) =>
                              setState(() => _selectedType = type),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )),
                  const SizedBox(width: 12),
                  // Markdown formatting toolbar shares the same row as the type
                  // chips so the controls sit on one horizontal line; it fills
                  // the remaining width and scrolls internally when narrow.
                  Expanded(
                    child: MarkdownToolbar(
                      controller: _entryController,
                      refocus: _entryFocus,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Attach image
                  _AttachButton(
                    icon: Icons.image_outlined,
                    tooltip: 'Attach image',
                    busy: _isPicking,
                    onPressed: _pickImages,
                  ),
                  const SizedBox(width: 4),
                  // Attach file
                  _AttachButton(
                    icon: Icons.attach_file,
                    tooltip: 'Attach file',
                    busy: _isPicking,
                    onPressed: _pickFiles,
                  ),
                  const SizedBox(width: 4),
                  // Paste image from clipboard (v1.4.83)
                  _AttachButton(
                    icon: Icons.content_paste_go_rounded,
                    tooltip: 'Paste image from clipboard (Ctrl+V)',
                    busy: _isPicking,
                    onPressed: _pasteImage,
                  ),
                ],
              ),

              // Pending attachment previews
              if (_pendingAttachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _pendingAttachments
                        .map((a) => _PendingAttachmentChip(
                              attachment: a,
                              onRemove: () =>
                                  setState(() => _pendingAttachments.remove(a)),
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Text input with Write/Preview toggle (height controlled by
              // the grip handle above)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: MarkdownEditorField(
                      controller: _entryController,
                      focusNode: _entryFocus,
                      height: _textAreaHeight + 30,
                      hintText:
                          'Record what you did, observed, measured... (Markdown supported, Tab to indent)',
                      hardenLineBreaks: true,
                      // Preview with the SAME style sheet used to render the
                      // saved Note below, so what the user previews is exactly
                      // what gets recorded (WYSIWYG).
                      styleSheet: _markdownStyleSheet(context),
                      onSubmitted: (_) => _addEntry(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _editingEntry != null ? _cancelEdit : _addEntry,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      minimumSize: const Size(44, 44),
                      backgroundColor: _editingEntry != null
                          ? AppColors.error.withOpacity(0.12)
                          : null,
                      foregroundColor: _editingEntry != null
                          ? AppColors.error
                          : null,
                    ),
                    child: Icon(
                      _editingEntry != null ? Icons.close : Icons.send,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickImages() async {
    setState(() => _isPicking = true);
    final picked = await AttachmentService.pickImages();
    if (!mounted) return;
    setState(() {
      _pendingAttachments.addAll(picked);
      _isPicking = false;
    });
  }

  Future<void> _pickFiles() async {
    setState(() => _isPicking = true);
    final picked = await AttachmentService.pickFiles();
    if (!mounted) return;
    setState(() {
      _pendingAttachments.addAll(picked);
      _isPicking = false;
    });
  }

  /// v1.4.83: explicit "paste image from clipboard" action.
  Future<void> _pasteImage() async {
    setState(() => _isPicking = true);
    final pasted = await AttachmentService.pasteClipboardImage();
    if (!mounted) return;
    setState(() {
      if (pasted != null) _pendingAttachments.add(pasted);
      _isPicking = false;
    });
    if (pasted == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No image in clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Called on Ctrl+V: if the clipboard holds no text (i.e. the user copied
  /// a screenshot / image), attach it as a pending attachment.
  Future<void> _maybePasteClipboardImage() async {
    final clip = await Clipboard.getData('text/plain');
    if ((clip?.text ?? '').isNotEmpty) return; // normal text paste applies
    final pasted = await AttachmentService.pasteClipboardImage();
    if (pasted != null && mounted) {
      setState(() => _pendingAttachments.add(pasted));
    }
  }

  Future<void> _addEntry() async {
    // v1.4.90: while an existing record is loaded into the input area,
    // sending updates that record instead of creating a new one.
    if (_editingEntry != null) return _updateEntry();

    final content = _entryController.text.trim();
    // Allow sending when there is text OR at least one attachment.
    if (content.isEmpty && _pendingAttachments.isEmpty) return;

    final entry = ExecutionEntry()
      ..content = content
      ..type = _selectedType
      ..timestamp = DateTime.now()
      ..attachments = List<Attachment>.from(_pendingAttachments);

    // Clear the input immediately for a snappy feel.
    _entryController.clear();
    setState(() => _pendingAttachments.clear());

    try {
      await ref
          .read(taskListProvider.notifier)
          .addExecutionEntry(widget.task.id, entry);
    } catch (e) {
      // Never swallow save errors silently — tell the user.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save log entry: $e')),
      );
    }
  }

  /// v1.4.90: load the record into the input area for re-editing — its
  /// content, type and attachments all come along, so the user edits in
  /// the exact same environment used for new entries.
  void _editEntry(ExecutionEntry entry) {
    setState(() {
      _editingEntry = entry;
      _entryController.text = entry.content;
      _selectedType = entry.type;
      _pendingAttachments
        ..clear()
        ..addAll(entry.attachments);
    });
    _entryFocus.requestFocus();
  }

  /// Leaves edit mode, restoring the input area to "new entry" state.
  void _cancelEdit() {
    setState(() {
      _editingEntry = null;
      _entryController.clear();
      _pendingAttachments.clear();
      _selectedType = EntryType.note;
    });
  }

  /// Writes the edited content back to the record. The entry keeps its
  /// original uid + timestamp so it stays at the same timeline position;
  /// only content, type and attachments change.
  Future<void> _updateEntry() async {
    final original = _editingEntry;
    if (original == null) return;

    final content = _entryController.text.trim();
    // Same rule as the edit dialog: needs text or at least one attachment.
    if (content.isEmpty && _pendingAttachments.isEmpty) return;

    final updated = ExecutionEntry()
      ..uid = original.uid
      ..timestamp = original.timestamp
      ..content = content
      ..type = _selectedType
      ..attachments = List<Attachment>.from(_pendingAttachments);

    // Leave edit mode immediately for a snappy feel.
    setState(() {
      _editingEntry = null;
      _entryController.clear();
      _pendingAttachments.clear();
      _selectedType = EntryType.note;
    });

    try {
      await ref
          .read(taskListProvider.notifier)
          .updateExecutionEntry(widget.task.id, original.uid, updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log entry updated'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update log entry: $e')),
      );
    }
  }

  void _deleteEntry(ExecutionEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Log Entry'),
        content: Text(
          'Delete this entry from ${DateFormat('HH:mm:ss').format(entry.timestamp)}? '
          'This cannot be undone.\n\n'
          'Attached files will remain on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(taskListProvider.notifier)
                    .deleteExecutionEntry(widget.task.id, entry.uid);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete log entry: $e')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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

/// Small icon button used to attach an image or a file.
class _AttachButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool busy;
  final VoidCallback onPressed;

  const _AttachButton({
    required this.icon,
    required this.tooltip,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: busy ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.primary.withOpacity(0.8),
                ),
        ),
      ),
    );
  }
}

/// A staged (not yet sent) attachment with a remove button.
class _PendingAttachmentChip extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onRemove;

  const _PendingAttachmentChip({
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
          // Thumbnail / icon
          isImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(AttachmentService.resolvePathSync(attachment.path)),
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
            constraints: const BoxConstraints(maxWidth: 140),
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

class _LogEntryItem extends StatelessWidget {
  final ExecutionEntry entry;

  /// Newest entry (top of the reversed list) — rendered with the large
  /// emphasized marker, like the highlighted event in a delivery timeline.
  final bool isLatest;

  /// Oldest entry — no connector line below it.
  final bool isLast;

  /// v1.4.90: this record is currently loaded in the input area for
  /// re-editing — highlighted so the user sees which record they edit.
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LogEntryItem({
    required this.entry,
    required this.isLatest,
    required this.isLast,
    this.isEditing = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(entry.type);
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.outline.withOpacity(0.25);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail: marker + connector line down to the next event.
          SizedBox(
            width: 26,
            child: Column(
              children: [
                const SizedBox(height: 10),
                _TimelineMarker(type: entry.type, emphasized: isLatest),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 3, bottom: -12),
                      color: lineColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isEditing
                    ? AppColors.primary.withOpacity(0.07)
                    : color.withOpacity(isLatest ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isEditing
                      ? AppColors.primary
                      : color.withOpacity(isLatest ? 0.45 : 0.2),
                  width: isEditing ? 1.6 : (isLatest ? 1.2 : 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.type.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // v1.4.90: badge marking the record loaded into the
                      // input area for re-editing.
                      if (isEditing) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Editing',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        DateFormat('MMM d, yyyy · HH:mm:ss').format(entry.timestamp),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.lightTextSecondary,
                            ),
                      ),
                      const SizedBox(width: 2),
                      // Copy the raw Markdown source of this entry. The
                      // rendered Note shows formatted text, so drag-select
                      // copies the formatted version; this button is the
                      // one-tap way to get the original Markdown (same as
                      // copying inside edit mode).
                      Tooltip(
                        message: 'Copy as Markdown',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: entry.content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Markdown copied to clipboard'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.content_copy_outlined,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.45),
                            ),
                          ),
                        ),
                      ),
                      // Edit this entry
                      Tooltip(
                        message: 'Edit entry',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onEdit,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.45),
                            ),
                          ),
                        ),
                      ),
                      // Delete this entry
                      Tooltip(
                        message: 'Delete entry',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onDelete,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: AppColors.error.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (entry.content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // v1.4.75: whole-Note selectable renderer — the ENTIRE
                    // note is ONE SelectableText.rich: drag-select across
                    // lines/blocks, Select all, right-click Copy / Copy as
                    // Markdown (stable I-beam cursor, no per-block limits).
                    // HTML mixed into the note is sanitized first so nothing
                    // renders as raw tags.
                    SelectableMarkdownBody(
                      data: sanitizeHtmlInMarkdown(entry.content),
                      hardenLineBreaks: true,
                      styleSheet: _markdownStyleSheet(context),
                      onTapLink: (href) {
                        final uri = Uri.tryParse(href);
                        if (uri == null) return;
                        if (uri.scheme == 'file') {
                          // launchUrl on a file:// URI blocks the UI thread on
                          // Windows (ShellExecuteW); open the path out-of-band.
                          openPath(uri.toFilePath());
                        } else {
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                  if (entry.attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _AttachmentGallery(attachments: entry.attachments),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForType(EntryType type) {
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

/// Timeline event marker. The newest entry gets the large emphasized
/// circle with a white type icon (delivery-tracking style); older entries
/// use small solid dots with a soft halo.
class _TimelineMarker extends StatelessWidget {
  final EntryType type;
  final bool emphasized;

  const _TimelineMarker({required this.type, required this.emphasized});

  IconData get _icon {
    switch (type) {
      case EntryType.note:
        return Icons.edit_note;
      case EntryType.pass:
        return Icons.check;
      case EntryType.fail:
        return Icons.priority_high;
      case EntryType.blocked:
        return Icons.block;
    }
  }

  Color _colorFor(EntryType t) {
    switch (t) {
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

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(type);
    if (emphasized) {
      // Large filled circle with white icon + outer halo ring.
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3), width: 3),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(_icon, size: 14, color: Colors.white),
        ),
      );
    }
    // Small solid dot with a faint halo.
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.25), width: 3),
        ),
      ),
    );
  }
}

/// Theme-adaptive Markdown styling for log entries (light & dark). Shared by
/// the input Preview and the saved Note rows so the two render identically
/// (WYSIWYG "input-as-preview").
MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final base = MarkdownStyleSheet.fromTheme(theme);

  final sheet = base.copyWith(
    p: theme.textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.55),
    pPadding: const EdgeInsets.only(bottom: 6),
    h1: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
    h2: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
    h3: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
    h4: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
    h5: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
    h6: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
    a: TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
      backgroundColor: isDark
          ? Colors.white.withOpacity(0.08)
          : Colors.black.withOpacity(0.05),
    ),
    codeblockDecoration: BoxDecoration(
      color: isDark
          ? Colors.white.withOpacity(0.07)
          : Colors.black.withOpacity(0.04),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.08),
      ),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    blockquoteDecoration: BoxDecoration(
      color: isDark
          ? Colors.white.withOpacity(0.05)
          : Colors.black.withOpacity(0.03),
      borderRadius: BorderRadius.circular(6),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    // Nested lists need a visible indentation step (matches
    // workreport.html's ~1.6em list padding).
    listIndent: 26,
  );
  // v1.4.85: user-configurable content font family / size.
  return applyContentTypography(context, sheet);
}

/// Renders the attachments of a saved log entry: image thumbnails (tap to
/// view full size) and file chips (tap to open with the system).
class _AttachmentGallery extends StatelessWidget {
  final List<Attachment> attachments;

  const _AttachmentGallery({required this.attachments});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map((a) => a.type == AttachmentType.image
              ? _ImageAttachment(attachment: a)
              : _FileAttachment(attachment: a))
          .toList(),
    );
  }
}

class _ImageAttachment extends StatelessWidget {
  final Attachment attachment;

  const _ImageAttachment({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(AttachmentService.resolvePathSync(attachment.path)),
          width: 132,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 132,
            height: 96,
            color: Colors.black.withOpacity(0.05),
            child: const Icon(Icons.broken_image, size: 28),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ResizableImageDialog(
        file: File(AttachmentService.resolvePathSync(attachment.path)),
      ),
    );
  }
}

/// v1.4.85: full-size image preview whose frame the user can resize by
/// dragging the bottom-right corner grip. The chosen size is persisted and
/// restored on the next open. Pinch / scroll zoom inside the frame still
/// works via InteractiveViewer.
class _ResizableImageDialog extends StatefulWidget {
  final File file;

  const _ResizableImageDialog({required this.file});

  @override
  State<_ResizableImageDialog> createState() => _ResizableImageDialogState();
}

class _ResizableImageDialogState extends State<_ResizableImageDialog> {
  static const _kPref = 'settings.imagePreviewSize';
  static const _minW = 380.0;
  static const _minH = 260.0;
  double _w = 900;
  double _h = 640;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kPref);
      if (v == null) return;
      final parts = v.split('x');
      final w = double.tryParse(parts[0]);
      final h = parts.length > 1 ? double.tryParse(parts[1]) : null;
      if (w != null && h != null && mounted) {
        setState(() {
          _w = w;
          _h = h;
        });
      }
    } catch (_) {}
  }

  void _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPref, '${_w.round()}x${_h.round()}');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final maxW = screen.width - 80;
    final maxH = screen.height - 120;
    final w = _w.clamp(_minW, maxW);
    final h = _h.clamp(_minH, maxH);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InteractiveViewer(
                    child: Center(
                      child: Image.file(
                        widget.file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image,
                              size: 48, color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            // Resize grip — drag to adjust the preview frame; the size is
            // remembered for the next time.
            Positioned(
              right: 2,
              bottom: 2,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      _w = (_w + d.delta.dx).clamp(_minW, maxW);
                      _h = (_h + d.delta.dy).clamp(_minH, maxH);
                    });
                  },
                  onPanEnd: (_) => _persist(),
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    child: const Icon(Icons.open_in_full,
                        size: 15, color: Colors.white70),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileAttachment extends StatelessWidget {
  final Attachment attachment;

  const _FileAttachment({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Open ${attachment.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => AttachmentService.openAttachment(attachment),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  attachment.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                AttachmentService.formatSize(attachment.size),
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
