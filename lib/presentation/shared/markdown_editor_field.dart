import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'markdown_input.dart';
import 'selectable_markdown_body.dart';

/// A Markdown editor with instant Write / Preview switching.
///
/// In **Write** mode a plain multiline [TextField] is shown (raw Markdown
/// source); in **Preview** mode the same content is rendered through
/// [AppMarkdownBody] so the user sees the formatted result immediately —
/// "input-as-preview" without leaving the field.
///
/// The toggle lives in a compact segmented control at the top-right of the
/// field border, keeping the whole widget drop-in replaceable with a bare
/// TextField.
class MarkdownEditorField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Fixed height (used by the Execution Log's resizable input area).
  /// When null the field sizes itself via [minLines]/[maxLines].
  final double? height;

  /// Fill ALL available space (used by the Reports full-screen editor).
  /// When true the Write field expands inside its parent and the Preview
  /// grows to match, so the toggle works in either mode.
  final bool expands;
  final int minLines;
  final int maxLines;
  final String? hintText;
  final TextStyle? style;

  /// Whether the Write field requests focus automatically.
  final bool autofocus;

  /// Custom [InputDecoration] for the Write field (defaults to an outlined
  /// border).
  final InputDecoration? decoration;

  /// Style sheet used to render the Preview. Callers should pass the SAME
  /// style sheet used to render the saved/recorded content so the preview is
  /// a true WYSIWYG of what will be stored ("input-as-preview").
  final MarkdownStyleSheet? styleSheet;

  /// Harden single line-breaks into visible breaks (user free-form input).
  final bool hardenLineBreaks;

  /// Called when the user submits (Enter with onSubmitted semantics).
  final ValueChanged<String>? onSubmitted;

  /// Called whenever the Write field's content changes.
  final ValueChanged<String>? onChanged;

  const MarkdownEditorField({
    super.key,
    required this.controller,
    this.focusNode,
    this.height,
    this.expands = false,
    this.minLines = 4,
    this.maxLines = 8,
    this.hintText,
    this.style,
    this.decoration,
    this.autofocus = false,
    this.styleSheet,
    this.hardenLineBreaks = true,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  State<MarkdownEditorField> createState() => _MarkdownEditorFieldState();
}

class _MarkdownEditorFieldState extends State<MarkdownEditorField> {
  bool _preview = false;

  /// Tab / Shift+Tab indent interception. When the caller supplies a
  /// [widget.focusNode] it is used as-is (callers add extra behavior, e.g.
  /// Ctrl+Enter submit); otherwise the field creates its own indent-only
  /// node so Tab always indents — never silently moves focus out of the
  /// editor.
  FocusNode? _internalFocus;
  late final FocusNode _focus = widget.focusNode ??
      (_internalFocus ??= markdownIndentFocusNode(widget.controller));

  @override
  void dispose() {
    _internalFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Listen to controller changes so switching to Preview always shows
    // the latest text (setState on listener).
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final hasText = widget.controller.text.trim().isNotEmpty;

        final field = _preview
            ? _buildPreview(theme, isDark)
            : _buildTextField(theme);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Write / Preview toggle ──────────────────────────────
            Row(
              children: [
                _ModeTab(
                  label: 'Write',
                  icon: Icons.edit_outlined,
                  active: !_preview,
                  onTap: () => setState(() => _preview = false),
                ),
                const SizedBox(width: 2),
                _ModeTab(
                  label: 'Preview',
                  icon: Icons.visibility_outlined,
                  active: _preview,
                  onTap: () => setState(() => _preview = true),
                ),
                const Spacer(),
                if (_preview && hasText)
                  Text(
                    'Markdown rendered',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // ── Editor / Preview body ───────────────────────────────
            field,
          ],
        );
      },
    );
  }

  Widget _buildTextField(ThemeData theme) {
    final fixed = widget.height != null;
    final grow = fixed || widget.expands;
    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      maxLines: grow ? null : widget.maxLines,
      minLines: grow ? null : widget.minLines,
      expands: grow,
      textAlignVertical: grow ? TextAlignVertical.top : null,
      style: widget.style ?? const TextStyle(fontSize: 13.5, height: 1.5),
      autofocus: widget.autofocus,
      decoration: widget.decoration ??
          InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(fontSize: 12.5),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
    );

    if (fixed) {
      return SizedBox(height: widget.height, child: field);
    }
    if (widget.expands) {
      return SizedBox.expand(child: field);
    }
    return field;
  }

  Widget _buildPreview(ThemeData theme, bool isDark) {
    final text = widget.controller.text;
    final empty = text.trim().isEmpty;

    final content = empty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Nothing to preview yet — write some Markdown first.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ),
          )
        : SingleChildScrollView(
            primary: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              // Whole-document SelectableText.rich: drag-select across all
              // lines, select-all, right-click Copy / "Copy as Markdown".
              child: SelectableMarkdownBody(
                data: text,
                hardenLineBreaks: widget.hardenLineBreaks,
                styleSheet: widget.styleSheet,
              ),
            ),
          );

    // In expands mode the preview fills its parent so Write / Preview toggle
    // keeps the same footprint.
    final constraints = widget.expands
        ? null
        : BoxConstraints(
            minHeight: widget.height ?? 96,
            maxHeight: widget.height ?? 260,
          );
    final container = Container(
      constraints: constraints,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface
            : theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.35),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: content,
    );

    return widget.expands ? SizedBox.expand(child: container) : container;
  }
}

/// One segment of the Write/Preview toggle.
class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.45),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
