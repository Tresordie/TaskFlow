import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Helpers for editing Markdown inside a plain multiline [TextField]:
/// selection wrapping (bold/italic/code), line prefixing (headings, lists,
/// quotes) and Tab / Shift+Tab multi-level indentation.
///
/// All operations mutate the supplied [TextEditingController] in place and
/// reposition the caret sensibly, so they work with any existing field.
class MarkdownInput {
  MarkdownInput._();

  static ({int start, int end}) _sel(TextEditingController c) {
    final len = c.text.length;
    var start = c.selection.start;
    var end = c.selection.end;
    if (start < 0 || start > len) start = len;
    if (end < 0 || end > len) end = start;
    if (end < start) end = start;
    return (start: start, end: end);
  }

  /// Wraps the current selection with [prefix]/[suffix] (e.g. `**` bold).
  /// With no selection, inserts the pair and parks the caret between them.
  static void wrapSelection(
      TextEditingController c, String prefix, String suffix) {
    final text = c.text;
    final s = _sel(c);
    final selected = text.substring(s.start, s.end);
    final replacement = '$prefix$selected$suffix';
    c.value = TextEditingValue(
      text: text.replaceRange(s.start, s.end, replacement),
      selection: TextSelection.collapsed(
          offset: s.start + prefix.length + selected.length),
    );
  }

  /// Prefixes every line touched by the selection with [prefix]
  /// (e.g. `- `, `> `, `## `).
  static void prefixLines(TextEditingController c, String prefix) {
    final text = c.text;
    final s = _sel(c);
    final lineStart = s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = text.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    final prefixed =
        block.split('\n').map((l) => '$prefix$l').join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, prefixed),
      selection:
          TextSelection.collapsed(offset: lineStart + prefixed.length),
    );
  }

  /// Indents the selected line(s) by two spaces (one nesting level).
  static void indent(TextEditingController c) => prefixLines(c, '  ');

  /// Removes up to two leading spaces from the selected line(s).
  static void outdent(TextEditingController c) {
    final text = c.text;
    final s = _sel(c);
    final lineStart = s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = text.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    final outdented = block.split('\n').map((l) {
      if (l.startsWith('  ')) return l.substring(2);
      if (l.startsWith(' ')) return l.substring(1);
      return l;
    }).join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, outdented),
      selection:
          TextSelection.collapsed(offset: lineStart + outdented.length),
    );
  }
}

/// Builds a [FocusNode] that intercepts Tab / Shift+Tab inside a multiline
/// field and turns them into indent / outdent instead of moving focus.
/// Attach the returned node to the target [TextField].
FocusNode markdownIndentFocusNode(TextEditingController controller) {
  return FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.tab) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          MarkdownInput.outdent(controller);
        } else {
          MarkdownInput.indent(controller);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
}

/// A compact row of Markdown formatting buttons that operate on [controller].
/// After each action the optional [refocus] node is re-requested so the user
/// can keep typing without clicking back into the field.
class MarkdownToolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? refocus;

  const MarkdownToolbar({
    super.key,
    required this.controller,
    this.refocus,
  });

  void _run(VoidCallback action) {
    action();
    refocus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface.withOpacity(0.55);

    Widget btn(IconData icon, String tooltip, VoidCallback onPressed) {
      return SizedBox(
        width: 26,
        height: 26,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 15,
          color: iconColor,
          tooltip: tooltip,
          icon: Icon(icon),
          onPressed: () => _run(onPressed),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.format_bold, 'Bold (**text**)',
            () => MarkdownInput.wrapSelection(controller, '**', '**')),
        btn(Icons.format_italic, 'Italic (*text*)',
            () => MarkdownInput.wrapSelection(controller, '*', '*')),
        btn(Icons.code, 'Inline code (`code`)',
            () => MarkdownInput.wrapSelection(controller, '`', '`')),
        const SizedBox(width: 4),
        btn(Icons.title, 'Heading (## )',
            () => MarkdownInput.prefixLines(controller, '## ')),
        btn(Icons.format_list_bulleted, 'Bullet list (- )',
            () => MarkdownInput.prefixLines(controller, '- ')),
        btn(Icons.format_list_numbered, 'Numbered list (1. )',
            () => MarkdownInput.prefixLines(controller, '1. ')),
        btn(Icons.format_quote, 'Quote (> )',
            () => MarkdownInput.prefixLines(controller, '> ')),
        const SizedBox(width: 4),
        btn(Icons.format_indent_increase, 'Indent (Tab)',
            () => MarkdownInput.indent(controller)),
        btn(Icons.format_indent_decrease, 'Outdent (Shift+Tab)',
            () => MarkdownInput.outdent(controller)),
      ],
    );
  }
}
