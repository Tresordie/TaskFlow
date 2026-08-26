import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Helpers for editing Markdown inside a plain multiline [TextField]:
/// selection wrapping (bold/italic/code/underline/highlight/color/size),
/// line prefixing (headings, lists, quotes, task lists) and Tab /
/// Shift+Tab multi-level indentation.
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
    final lineStart =
        s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = text.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    final prefixed = block.split('\n').map((l) => '$prefix$l').join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, prefixed),
      selection: TextSelection.collapsed(offset: lineStart + prefixed.length),
    );
  }

  /// Sets the heading level (1–6) on the selected line(s), replacing any
  /// existing heading prefix so repeated clicks never stack `#` marks.
  static void setHeading(TextEditingController c, int level) {
    final text = c.text;
    final s = _sel(c);
    final lineStart =
        s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = text.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    final prefix = level <= 0 ? '' : '${'#' * level} ';
    final changed = block
        .split('\n')
        .map((l) => '$prefix${l.replaceFirst(RegExp(r'^#{1,6}\s+'), '')}')
        .join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, changed),
      selection: TextSelection.collapsed(offset: lineStart + changed.length),
    );
  }

  /// Wraps the selection in a fenced code block (``` on its own lines).
  static void codeBlock(TextEditingController c) {
    final text = c.text;
    final s = _sel(c);
    final selected = text.substring(s.start, s.end);
    final replacement = '```\n$selected\n```';
    c.value = TextEditingValue(
      text: text.replaceRange(s.start, s.end, replacement),
      selection: TextSelection.collapsed(offset: s.start + 4 + selected.length),
    );
  }

  /// Replaces the selection with a `[text](url)` link.
  static void insertLink(TextEditingController c, String text, String url) {
    final t = c.text;
    final s = _sel(c);
    final replacement = '[$text]($url)';
    c.value = TextEditingValue(
      text: t.replaceRange(s.start, s.end, replacement),
      selection: TextSelection.collapsed(offset: s.start + replacement.length),
    );
  }

  /// Indents (Tab):
  /// - no selection → insert TWO SPACES AT THE CARET (v1.6.1 user request):
  ///   only the content AFTER the cursor shifts right; the text before it
  ///   stays put — this is a plain caret insertion, NOT a whole-line indent;
  /// - active selection → prefix every line the selection touches and keep
  ///   the whole block selected, so repeated Tabs keep indenting the same
  ///   lines one level at a time.
  static void indent(TextEditingController c) {
    final text = c.text;
    final s = _sel(c);
    if (s.start == s.end) {
      c.value = TextEditingValue(
        text: text.replaceRange(s.start, s.start, '  '),
        selection: TextSelection.collapsed(offset: s.start + 2),
      );
      return;
    }
    _indentBlock(c, '  ');
  }

  /// Removes up to two leading spaces from every line the selection touches
  /// (or the caret's line when collapsed). The whole block stays selected,
  /// mirroring workreport.html's md-editor Shift+Tab.
  static void outdent(TextEditingController c) => _indentBlock(c, null);

  /// Inserts a footnote reference `[^n]` at the caret and appends the
  /// matching definition `[^n]: ` at the end of the document (v1.5.0).
  /// The number is the next unused positive integer, and the caret lands
  /// inside the definition ready for typing.
  static void insertFootnote(TextEditingController c) {
    final text = c.text;
    final s = _sel(c);
    // Find the next unused footnote number.
    final used = RegExp(r'^\[\^(\d+)\]:', multiLine: true)
        .allMatches(text)
        .map((m) => int.parse(m.group(1)!))
        .toSet();
    var n = 1;
    while (used.contains(n)) {
      n++;
    }
    final ref = '[^$n]';
    final withRef = text.replaceRange(s.start, s.end, ref);
    final separator = withRef.endsWith('\n\n') || withRef.isEmpty
        ? ''
        : (withRef.endsWith('\n') ? '\n' : '\n\n');
    final def = '[^$n]: ';
    final full = '$withRef$separator$def';
    c.value = TextEditingValue(
      text: full,
      selection: TextSelection.collapsed(offset: full.length),
    );
  }

  /// Shared multi-line (de)indent: with [prefix] != null adds two spaces to
  /// every line; with null removes up to two leading spaces per line. The
  /// resulting block is re-selected ([TextSelection.baseOffset] → extent)
  /// so repeated presses keep operating on the same lines.
  static void _indentBlock(TextEditingController c, String? prefix) {
    final text = c.text;
    final s = _sel(c);
    final lineStart =
        s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = text.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    final changed = block.split('\n').map((l) {
      if (prefix != null) return '$prefix$l';
      if (l.startsWith('  ')) return l.substring(2);
      if (l.startsWith(' ')) return l.substring(1);
      return l;
    }).join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, changed),
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + changed.length,
      ),
    );
  }
}

/// Builds a [FocusNode] that intercepts Tab / Shift+Tab inside a multiline
/// field and turns them into indent / outdent instead of moving focus.
/// Attach the returned node to the target [TextField].
FocusNode markdownIndentFocusNode(TextEditingController controller) {
  return FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
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

/// Palette offered by the font-color picker. Kept in sync with
/// [parseRichTextColor] in core/markdown/rich_markdown.dart.
const List<Color> _kToolbarColors = [
  Color(0xFFEF4444), // red
  Color(0xFFF97316), // orange
  Color(0xFFF59E0B), // amber
  Color(0xFFEAB308), // yellow
  Color(0xFF22C55E), // green
  Color(0xFF14B8A6), // teal
  Color(0xFF06B6D4), // cyan
  Color(0xFF3B82F6), // blue
  Color(0xFF6366F1), // indigo
  Color(0xFF8B5CF6), // purple
  Color(0xFFEC4899), // pink
  Color(0xFF92400E), // brown
  Color(0xFF6B7280), // gray
  Color(0xFF111827), // black
];

/// Font-size multipliers offered by the size picker (em-like factors
/// understood by `<font size="N">`).
const List<({String label, double factor})> _kToolbarSizes = [
  (label: 'Small · 0.8×', factor: 0.8),
  (label: 'Normal · 1.0×', factor: 1.0),
  (label: 'Large · 1.25×', factor: 1.25),
  (label: 'X-Large · 1.5×', factor: 1.5),
  (label: 'Huge · 2.0×', factor: 2.0),
];

/// A compact, single-row (horizontally scrollable when space is tight)
/// Markdown + rich-text formatting bar that operates on [controller].
///
/// Supported formats: H1–H3 headings, bold, italic, strikethrough,
/// underline (`++`), highlight (`==`), font color / font size
/// (`<font …>`), quote, hyperlink, task list, bullet list, numbered list,
/// inline code, fenced code block, indent / outdent.
///
/// After each action the optional [refocus] node is re-requested so the
/// user can keep typing without clicking back into the field.
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

  Future<void> _runAsync(Future<void> Function() action) async {
    await action();
    refocus?.requestFocus();
  }

  // ── Pickers ───────────────────────────────────────────────────────────

  Future<void> _pickColor(BuildContext context) {
    return _runAsync(() async {
      final color = await showDialog<Color>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Font color'),
          content: SizedBox(
            width: 260,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _kToolbarColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(ctx).pop(c),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.black.withOpacity(0.12)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (color == null) return;
      final hex =
          '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      MarkdownInput.wrapSelection(controller, '<font color="$hex">', '</font>');
    });
  }

  Future<void> _pickSize(BuildContext context) {
    return _runAsync(() async {
      final size = await showDialog<double>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Font size'),
          children: [
            for (final s in _kToolbarSizes)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(s.factor),
                child: Text(s.label, style: TextStyle(fontSize: 14 * s.factor)),
              ),
          ],
        ),
      );
      if (size == null) return;
      final label = size == size.truncateToDouble()
          ? size.toStringAsFixed(0)
          : size.toString();
      MarkdownInput.wrapSelection(
          controller, '<font size="$label">', '</font>');
    });
  }

  Future<void> _insertLink(BuildContext context) {
    return _runAsync(() async {
      final s = controller.selection;
      final selected = (s.isValid && !s.isCollapsed)
          ? controller.text.substring(s.start, s.end)
          : '';
      final textCtl = TextEditingController(text: selected);
      final urlCtl = TextEditingController(text: 'https://');
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insert link'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textCtl,
                  autofocus: selected.isEmpty,
                  decoration: const InputDecoration(labelText: 'Link text'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtl,
                  autofocus: selected.isNotEmpty,
                  decoration: const InputDecoration(labelText: 'URL'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Insert'),
            ),
          ],
        ),
      );
      final text = textCtl.text.trim();
      final url = urlCtl.text.trim();
      if (result == true && url.isNotEmpty && url != 'https://') {
        MarkdownInput.insertLink(controller, text.isEmpty ? url : text, url);
      }
    });
  }

  // ── Bar ───────────────────────────────────────────────────────────────

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

    Widget textBtn(String label, String tooltip, VoidCallback onPressed) {
      return SizedBox(
        width: 26,
        height: 26,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: tooltip,
          onPressed: () => _run(onPressed),
          icon: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: iconColor,
            ),
          ),
        ),
      );
    }

    // Group separator: a thin vertical rule so related buttons read as
    // clusters instead of one long undifferentiated run.
    final gap = Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: theme.colorScheme.outline.withOpacity(0.22),
    );

    // A single row wrapped in a subtle pill container so the bar reads as
    // one cohesive formatting toolbar; it scrolls horizontally when the
    // window is too narrow instead of wrapping or truncating buttons.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.045),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.14)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            textBtn('H1', 'Heading 1 (# )',
                () => MarkdownInput.setHeading(controller, 1)),
            textBtn('H2', 'Heading 2 (## )',
                () => MarkdownInput.setHeading(controller, 2)),
            textBtn('H3', 'Heading 3 (### )',
                () => MarkdownInput.setHeading(controller, 3)),
            gap,
            btn(Icons.format_bold, 'Bold (**text**)',
                () => MarkdownInput.wrapSelection(controller, '**', '**')),
            btn(Icons.format_italic, 'Italic (*text*)',
                () => MarkdownInput.wrapSelection(controller, '*', '*')),
            btn(Icons.strikethrough_s, 'Strikethrough (~~text~~)',
                () => MarkdownInput.wrapSelection(controller, '~~', '~~')),
            btn(Icons.format_underlined, 'Underline (++text++)',
                () => MarkdownInput.wrapSelection(controller, '++', '++')),
            btn(Icons.highlight, 'Highlight (==text==)',
                () => MarkdownInput.wrapSelection(controller, '==', '==')),
            gap,
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 15,
                tooltip: 'Font color (<font color>)',
                onPressed: () => _pickColor(context),
                icon: Icon(Icons.format_color_text, color: iconColor),
              ),
            ),
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 15,
                tooltip: 'Font size (<font size>)',
                onPressed: () => _pickSize(context),
                icon: Icon(Icons.format_size, color: iconColor),
              ),
            ),
            gap,
            btn(Icons.format_quote, 'Quote (> )',
                () => MarkdownInput.prefixLines(controller, '> ')),
            btn(Icons.link, 'Hyperlink ([text](url))',
                () => _insertLink(context)),
            btn(Icons.fact_check_outlined, 'Task list (- [ ] )',
                () => MarkdownInput.prefixLines(controller, '- [ ] ')),
            btn(Icons.format_list_bulleted, 'Bullet list (- )',
                () => MarkdownInput.prefixLines(controller, '- ')),
            btn(Icons.format_list_numbered, 'Numbered list (1. )',
                () => MarkdownInput.prefixLines(controller, '1. ')),
            gap,
            btn(Icons.code, 'Inline code (`code`)',
                () => MarkdownInput.wrapSelection(controller, '`', '`')),
            btn(Icons.terminal, 'Code block (```)',
                () => MarkdownInput.codeBlock(controller)),
            gap,
            // v1.5.0: footnote / superscript / subscript extensions.
            btn(Icons.note_add_outlined, 'Footnote ([^1] + definition)',
                () => MarkdownInput.insertFootnote(controller)),
            textBtn('x²', 'Superscript (^text^)',
                () => MarkdownInput.wrapSelection(controller, '^', '^')),
            textBtn('x₂', 'Subscript (~text~)',
                () => MarkdownInput.wrapSelection(controller, '~', '~')),
            gap,
            btn(Icons.format_indent_increase, 'Indent (Tab)',
                () => MarkdownInput.indent(controller)),
            btn(Icons.format_indent_decrease, 'Outdent (Shift+Tab)',
                () => MarkdownInput.outdent(controller)),
          ],
        ),
      ),
    );
  }
}
