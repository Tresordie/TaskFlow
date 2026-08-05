import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/markdown/latex_support.dart';
import '../../core/markdown/line_breaks.dart';
import '../../core/markdown/rich_markdown.dart';

/// A whole-Note selectable Markdown renderer.
///
/// Unlike `MarkdownBody(selectable: true)` — which emits one independent
/// `SelectableText` PER BLOCK (paragraph / list item), so a drag can only
/// select inside a single block — this renderer merges the ENTIRE document
/// into ONE [TextSpan] tree and shows it with a single [SelectableText.rich].
/// The result: the user can drag-select across lines and paragraphs of the
/// whole Note, and the highlight is painted by SelectableText itself (which
/// is unaffected by the AOT detached-repaint-boundary issue that broke the
/// app-wide SelectionArea). (v1.4.28 fix)
///
/// Supported inline formatting: bold, italic, strikethrough, inline code,
/// links (tap), and the app's custom `++underline++` / `==highlight==` /
/// `<font color/size>` tags via [RichMarkdown]. Block structure (paragraphs,
/// headings, list items, blockquotes, code blocks) is flattened to text with
/// newlines, which is exactly what an execution-log Note needs.
class SelectableMarkdownBody extends StatelessWidget {
  final String data;
  final bool hardenLineBreaks;
  final TextStyle? baseStyle;

  /// Optional style sheet (the SAME one used by the input Preview via
  /// [AppMarkdownBody]) so the recorded Note's typography — paragraph,
  /// headings, code, quote, link — matches what the user previewed
  /// (WYSIWYG), while still rendering the whole document as ONE selectable
  /// [SelectableText.rich]. Falls back to sensible defaults when null.
  final MarkdownStyleSheet? styleSheet;
  final void Function(String href)? onTapLink;

  const SelectableMarkdownBody({
    super.key,
    required this.data,
    this.hardenLineBreaks = false,
    this.baseStyle,
    this.styleSheet,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final style = baseStyle ??
        styleSheet?.p ??
        Theme.of(context).textTheme.bodyLarge;
    final span = _buildSpan(
      context,
      hardenLineBreaks ? hardenMarkdownLineBreaks(data) : data,
      style,
    );
    return SelectableText.rich(
      span,
      style: style,
      contextMenuBuilder: (context, editableTextState) =>
          AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: [
          ...editableTextState.contextMenuButtonItems,
          // The rendered Note shows FORMATTED text, so the stock Copy gives
          // the formatted version (bullets as •, no ** etc.). Add an explicit
          // "Copy as Markdown" that copies the ORIGINAL Markdown source —
          // what the user pastes into a .md file. Right-click after
          // drag-selecting to reach it.
          ContextMenuButtonItem(
            label: 'Copy as Markdown',
            onPressed: () {
              ContextMenuController.removeAny();
              Clipboard.setData(ClipboardData(text: data));
            },
          ),
        ],
      ),
    );
  }

  TextSpan _buildSpan(BuildContext context, String markdown, TextStyle? style) {
    final document = md.Document(
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: const [
        md.FencedCodeBlockSyntax(),
        md.TableSyntax(),
        md.UnorderedListWithCheckboxSyntax(),
        md.OrderedListWithCheckboxSyntax(),
      ],
      inlineSyntaxes: [
        md.StrikethroughSyntax(),
        md.AutolinkExtensionSyntax(),
        ...LatexMarkdown.syntaxes(),
        ...RichMarkdown.syntaxes(),
      ],
      encodeHtml: false,
    );
    final nodes = document.parse(markdown);
    final children = <InlineSpan>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0) children.add(TextSpan(text: '\n\n', style: style));
      children.addAll(_blockSpans(nodes[i], style, context, listDepth: 0));
    }
    return TextSpan(style: style, children: children);
  }

  /// Flattens a block-level node into inline spans (with newlines between
  /// sub-blocks). Returns a list so lists/blockquotes can insert line breaks.
  List<InlineSpan> _blockSpans(
    md.Node node,
    TextStyle? style,
    BuildContext context, {
    required int listDepth,
  }) {
    if (node is md.Text) return [TextSpan(text: node.text, style: style)];
    if (node is! md.Element) return const [];
    final el = node;
    switch (el.tag) {
      case 'p':
        return _inlineSpans(el, style, context);
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final s = _headingStyle(el.tag, style);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'ul':
      case 'ol':
        return _listSpans(el, style, context, listDepth);
      case 'li':
        return _inlineSpans(el, style, context);
      case 'blockquote':
        return _blockquoteSpans(el, style, context);
      case 'pre':
        final code = el.textContent;
        final s = styleSheet?.code ??
            (style ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.black.withOpacity(0.05),
            );
        return [TextSpan(text: code, style: s)];
      case 'table':
        return _tableSpans(el, style, context);
      case 'hr':
        return [
          TextSpan(
            text: '─' * 48,
            style: (style ?? const TextStyle())
                .copyWith(color: Colors.grey.withOpacity(0.5)),
          )
        ];
      default:
        return _inlineSpans(el, style, context);
    }
  }

  /// Renders a list (`ul`/`ol`) with every item on its own line, indented by
  /// [depth] and prefixed with a bullet / ordinal marker. Nested lists are
  /// rendered recursively one level deeper instead of being glued inline —
  /// this is what stops multi-level lists from collapsing into a single line
  /// (the "content looks truncated" symptom).
  List<InlineSpan> _listSpans(
    md.Element el,
    TextStyle? style,
    BuildContext context,
    int depth,
  ) {
    final out = <InlineSpan>[];
    final isOrdered = el.tag == 'ol';
    var idx = 0;
    for (final item in el.children ?? <md.Node>[]) {
      if (item is! md.Element) continue;
      idx++;
      if (out.isNotEmpty) out.add(TextSpan(text: '\n', style: style));
      final marker = isOrdered ? '$idx. ' : '• ';
      out.add(TextSpan(text: '${'    ' * depth}$marker', style: style));
      // A <li>'s children are its inline content plus, for nested lists,
      // further <ul>/<ol> blocks — render those on new lines, indented one
      // level deeper, rather than inline.
      for (final child in item.children ?? <md.Node>[]) {
        if (child is md.Element &&
            (child.tag == 'ul' || child.tag == 'ol')) {
          out.add(TextSpan(text: '\n', style: style));
          out.addAll(_listSpans(child, style, context, depth + 1));
        } else {
          out.addAll(_nodeSpan(child, style, context));
        }
      }
    }
    return out;
  }

  /// Renders a blockquote, prefixing each of its child blocks with a `│ `
  /// gutter and separating them with newlines.
  List<InlineSpan> _blockquoteSpans(
    md.Element el,
    TextStyle? style,
    BuildContext context,
  ) {
    final s = styleSheet?.blockquote ??
        (style ?? const TextStyle()).copyWith(
          fontStyle: FontStyle.italic,
          color: Colors.grey,
        );
    final out = <InlineSpan>[];
    final kids = el.children ?? <md.Node>[];
    for (var i = 0; i < kids.length; i++) {
      if (i > 0) out.add(TextSpan(text: '\n', style: s));
      out.add(TextSpan(text: '│ ', style: s));
      out.addAll(_nodeSpan(kids[i], s, context));
    }
    return out;
  }

  /// Renders a table as monospace rows of `cell | cell` with a rule under the
  /// header row. Not a full grid like the Preview's MarkdownBody, but keeps
  /// every cell's text intact and each row on its own line.
  List<InlineSpan> _tableSpans(
    md.Element el,
    TextStyle? style,
    BuildContext context,
  ) {
    final s = styleSheet?.code ??
        (style ?? const TextStyle()).copyWith(fontFamily: 'monospace');
    final rows = <md.Element>[];
    void collect(md.Element e) {
      for (final c in e.children ?? <md.Node>[]) {
        if (c is! md.Element) continue;
        if (c.tag == 'tr') {
          rows.add(c);
        } else if (c.tag == 'thead' || c.tag == 'tbody') {
          collect(c);
        }
      }
    }

    collect(el);

    List<String> cellTexts(md.Element tr) {
      final texts = <String>[];
      for (final cell in tr.children ?? <md.Node>[]) {
        if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
          texts.add(
            TextSpan(children: _inlineSpans(cell, s, context)).toPlainText(),
          );
        }
      }
      return texts;
    }

    final out = <InlineSpan>[];
    for (var r = 0; r < rows.length; r++) {
      final texts = cellTexts(rows[r]);
      if (r > 0) out.add(TextSpan(text: '\n', style: s));
      out.add(TextSpan(text: texts.join(' | '), style: s));
      if (r == 0 && rows.length > 1) {
        final rule = texts
            .map((t) => '─' * (t.length < 3 ? 3 : t.length))
            .join('─┼─');
        out.add(TextSpan(text: '\n$rule', style: s));
      }
    }
    return out;
  }

  /// Converts an element's inline children into styled spans.
  List<InlineSpan> _inlineSpans(md.Element el, TextStyle? style, BuildContext context) {
    final out = <InlineSpan>[];
    for (final child in el.children ?? <md.Node>[]) {
      out.addAll(_nodeSpan(child, style, context));
    }
    return out;
  }

  List<InlineSpan> _nodeSpan(md.Node node, TextStyle? style, BuildContext context) {
    if (node is md.Text) return [TextSpan(text: node.text, style: style)];
    if (node is! md.Element) return const [];
    final el = node;
    switch (el.tag) {
      case 'strong':
      case 'b':
        final s = (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'em':
      case 'i':
        final s = (style ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'del':
        final s = (style ?? const TextStyle()).copyWith(decoration: TextDecoration.lineThrough);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'code':
        final s = styleSheet?.code ??
            (style ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.black.withOpacity(0.05),
            );
        return [TextSpan(text: el.textContent, style: s)];
      case 'a':
        final href = el.attributes['href'];
        final s = styleSheet?.a ??
            (style ?? const TextStyle()).copyWith(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            );
        return [
          TextSpan(
            style: s,
            children: _inlineSpans(el, s, context),
            recognizer: (href != null && onTapLink != null)
                ? (TapGestureRecognizer()..onTap = () => onTapLink!(href))
                : null,
          )
        ];
      case 'br':
        return [TextSpan(text: '\n', style: style)];
      case 'u':
        final s = (style ?? const TextStyle()).copyWith(decoration: TextDecoration.underline);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'mark':
        final s = (style ?? const TextStyle()).copyWith(backgroundColor: Colors.yellow.withOpacity(0.4));
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'font':
        var s = style ?? const TextStyle();
        final colorAttr = el.attributes['color'];
        final sizeAttr = el.attributes['size'];
        final color = colorAttr != null ? _parseColor(colorAttr) : null;
        final size = sizeAttr != null ? double.tryParse(sizeAttr) : null;
        s = s.copyWith(color: color, fontSize: size);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'input':
        // Task-list checkbox (from UnorderedListWithCheckboxSyntax): show a
        // textual [ ] / [x] so the state is not silently dropped.
        final checked = el.attributes.containsKey('checked');
        return [TextSpan(text: checked ? '[x] ' : '[ ] ', style: style)];
      case 'ul':
      case 'ol':
        // A list reached from an inline context: render it as an indented
        // block on its own lines rather than gluing it inline.
        return [
          TextSpan(text: '\n', style: style),
          ..._listSpans(el, style, context, 1),
        ];
      default:
        // Unknown inline/block tag: recurse into children to keep text.
        return _inlineSpans(el, style, context);
    }
  }

  /// Resolves a heading style for [tag] ('h1'..'h6'): the style sheet's
  /// heading style when available (matching the Preview exactly), else a
  /// bold, size-stepped fallback derived from the base style.
  TextStyle _headingStyle(String tag, TextStyle? base) {
    if (styleSheet != null) {
      final s = switch (tag) {
        'h1' => styleSheet!.h1,
        'h2' => styleSheet!.h2,
        'h3' => styleSheet!.h3,
        'h4' => styleSheet!.h4,
        'h5' => styleSheet!.h5,
        _ => styleSheet!.h6,
      };
      if (s != null) return s;
    }
    return (base ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      fontSize: (base?.fontSize ?? 14) +
          (tag == 'h1' ? 6 : tag == 'h2' ? 4 : 2),
    );
  }

  Color? _parseColor(String value) {
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final intVal = int.tryParse(hex, radix: 16);
    return intVal != null ? Color(intVal) : null;
  }
}
