import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/markdown/latex_support.dart';
import '../../core/markdown/line_breaks.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/open_folder.dart';
import '../../data/models/task.dart';
import '../../data/services/attachment_service.dart';
import '../../providers/task_providers.dart';
import '../shared/markdown_input.dart';
import 'edit_entry_dialog.dart';

class ExecutionLogWidget extends ConsumerStatefulWidget {
  final Task task;

  const ExecutionLogWidget({super.key, required this.task});

  @override
  ConsumerState<ExecutionLogWidget> createState() => _ExecutionLogWidgetState();
}

class _ExecutionLogWidgetState extends ConsumerState<ExecutionLogWidget> {
  final _entryController = TextEditingController();
  late final FocusNode _entryFocus = markdownIndentFocusNode(_entryController);
  EntryType _selectedType = EntryType.note;

  // Resizable text input area height (logical pixels).
  double _textAreaHeight = 74;
  static const double _minTextAreaHeight = 40;
  static const double _maxTextAreaHeight = 320;

  // Attachments staged for the next entry.
  final List<Attachment> _pendingAttachments = [];
  bool _isPicking = false;

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
                  const Spacer(),
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

              // Markdown formatting toolbar (bold/italic/code/headings/lists/
              // quote + indent/outdent). Tab & Shift+Tab also indent inline.
              MarkdownToolbar(
                controller: _entryController,
                refocus: _entryFocus,
              ),
              const SizedBox(height: 6),

              // Text input (height controlled by the grip handle above)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _textAreaHeight,
                      child: TextField(
                        controller: _entryController,
                        focusNode: _entryFocus,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText:
                              'Record what you did, observed, measured... (Markdown supported, Tab to indent)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onSubmitted: (_) => _addEntry(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addEntry,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Icon(Icons.send, size: 18),
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

  Future<void> _addEntry() async {
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

  void _editEntry(ExecutionEntry entry) {
    showDialog(
      context: context,
      builder: (_) => EditExecutionEntryDialog(
        taskId: widget.task.id,
        entry: entry,
      ),
    );
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LogEntryItem({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(entry.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + line
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.2)),
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
                      Text(
                        DateFormat('HH:mm:ss').format(entry.timestamp),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.lightTextSecondary,
                            ),
                      ),
                      const SizedBox(width: 2),
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
                    MarkdownBody(
                      data: hardenMarkdownLineBreaks(entry.content),
                      styleSheet: _markdownStyleSheet(context),
                      inlineSyntaxes: LatexMarkdown.syntaxes(),
                      builders: LatexMarkdown.builders(
                        Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontSize: 14),
                      ),
                      onTapLink: (text, href, title) {
                        if (href == null) return;
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

  /// Theme-adaptive Markdown styling for log entries (light & dark).
  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = MarkdownStyleSheet.fromTheme(theme);

    return base.copyWith(
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
      listIndent: 20,
    );
  }
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
          File(attachment.path),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.file(
                  File(attachment.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image, size: 48),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
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
