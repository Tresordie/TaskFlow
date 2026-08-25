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
        // v1.5.0: footnotes (definitions appendix; references become sup
        // markers via the link syntax automatically).
        md.FootnoteDefSyntax(),
      ],
      inlineSyntaxes: [
        // v1.5.0: custom rich syntaxes MUST precede StrikethroughSyntax —
        // the package's strikethrough greedily consumes single-tilde runs
        // and would otherwise eat `~subscript~` before our syntax sees it.
        ...RichMarkdown.syntaxes(),
        ...LatexMarkdown.syntaxes(),
        md.StrikethroughSyntax(),
        md.AutolinkExtensionSyntax(),
      ],
      encodeHtml: false,
    );
    final nodes = document.parse(markdown);
    final children = <InlineSpan>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0) {
        // v1.5.1: compact separators matching standard Markdown previews —
        // a heading hugs the block that follows it, and a list that
        // directly continues a paragraph ("如下：\n- …") gets no blank
        // line. Only true paragraph breaks keep a full blank line, which
        // removes the "too many empty lines" look of the old uniform \n\n.
        final prev = nodes[i - 1];
        final cur = nodes[i];
        final prevTag = prev is md.Element ? prev.tag : '';
        final curTag = cur is md.Element ? cur.tag : '';
        final prevIsHeading =
            prevTag.length == 2 && prevTag.startsWith('h');
        final paraIntoList = prevTag == 'p' &&
            (curTag == 'ul' || curTag == 'ol');
        children.add(TextSpan(
          text: (prevIsHeading || paraIntoList) ? '\n' : '\n\n',
          style: style,
        ));
      }
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
      case 'div':
        // v1.5.0: the footnotes appendix emitted by FootnoteDefSyntax —
        // flatten it to numbered note lines so the definitions stay
        // selectable instead of being dropped.
        return _footnoteDivSpans(el, style);
      default:
        return _inlineSpans(el, style, context);
    }
  }

  /// Flattens the trailing footnote appendix (`div.footnotes`) into one
  /// numbered line per note. Back-link glyphs (↩) are navigation aids with
  /// no meaning in a static view, so they are stripped.
  List<InlineSpan> _footnoteDivSpans(md.Element el, TextStyle? style) {
    final s = (style ?? const TextStyle()).copyWith(
      fontSize: 12,
      color: (style ?? const TextStyle()).color?.withOpacity(0.7) ??
          Colors.grey.withOpacity(0.8),
    );
    final notes = <String>[];
    void walk(md.Element e) {
      for (final c in e.children ?? <md.Node>[]) {
        if (c is! md.Element) continue;
        if (c.tag == 'li') {
          final t = c.textContent.replaceAll('↩', '').trim();
          if (t.isNotEmpty) notes.add(t);
        } else {
          walk(c);
        }
      }
    }

    walk(el);
    if (notes.isEmpty) return const [];
    final out = <InlineSpan>[];
    for (var i = 0; i < notes.length; i++) {
      if (i > 0) out.add(TextSpan(text: '\n', style: s));
      out.add(TextSpan(text: '${i + 1}. ${notes[i]}', style: s));
    }
    return out;
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

  /// Renders a table as an aligned monospace grid: every column is padded
  /// to the widest cell so the rows line up visually (CJK characters count
  /// double-width), with a boxed header row. Keeps every cell's text intact
  /// and each row on its own line while still fitting a single TextSpan tree.
  List<InlineSpan> _tableSpans(
    md.Element el,
    TextStyle? style,
    BuildContext context,
  ) {
    final s = styleSheet?.code ??
        (style ?? const TextStyle()).copyWith(fontFamily: 'monospace');
    final headStyle = s.copyWith(fontWeight: FontWeight.w700);
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

    final rowTexts = rows.map(cellTexts).toList();
    if (rowTexts.isEmpty) return const [];

    // Column widths in display units (CJK ≈ 2 columns).
    int displayWidth(String t) {
      var w = 0;
      for (final r in t.runes) {
        w += (r >= 0x1100 &&
                (r <= 0x115F ||
                    (r >= 0x2E80 && r <= 0xA4CF) ||
                    (r >= 0xAC00 && r <= 0xD7A3) ||
                    (r >= 0xF900 && r <= 0xFAFF) ||
                    (r >= 0xFE30 && r <= 0xFE4F) ||
                    (r >= 0xFF00 && r <= 0xFF60) ||
                    (r >= 0xFFE0 && r <= 0xFFE6)))
            ? 2
            : 1;
      }
      return w;
    }

    String pad(String t, int width) =>
        t + ' ' * (width - displayWidth(t)).clamp(0, 60);

    final colCount =
        rowTexts.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final widths = List<int>.generate(
      colCount,
      (c) => rowTexts
          .map((r) => c < r.length ? displayWidth(r[c]) : 0)
          .reduce((a, b) => a > b ? a : b),
    );

    String fmtRow(List<String> cells) =>
        '| ${List.generate(colCount, (c) => pad(c < cells.length ? cells[c] : '', widths[c])).join(' | ')} |';
    final rule =
        '+-${widths.map((w) => '-' * w).join('-+-')}-+';

    final out = <InlineSpan>[];
    for (var r = 0; r < rowTexts.length; r++) {
      if (r > 0) out.add(TextSpan(text: '\n', style: s));
      final isHeader = r == 0 && rowTexts.length > 1;
      out.add(TextSpan(
        text: fmtRow(rowTexts[r]),
        style: isHeader ? headStyle : s,
      ));
      if (isHeader) {
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
      case 'sup':
        // v1.5.0: footnote reference — keep the marker visible and
        // selectable as a bracketed, slightly smaller number.
        final s = (style ?? const TextStyle())
            .copyWith(fontSize: (style?.fontSize ?? 14) * 0.75);
        return [TextSpan(text: '[${el.textContent}]', style: s)];
      case 'richUnderline':
        // v1.5.0: style the custom rich tags instead of dropping their
        // formatting (previously fell through to the plain-text default).
        final s = (style ?? const TextStyle())
            .copyWith(decoration: TextDecoration.underline);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'richHighlight':
        final s = (style ?? const TextStyle())
            .copyWith(backgroundColor: Colors.yellow.withOpacity(0.4));
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'richFontColor':
        final color = parseRichTextColor(el.attributes['color'] ?? '');
        final s = color == null
            ? (style ?? const TextStyle())
            : (style ?? const TextStyle()).copyWith(color: color);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'richFontSize':
        final raw = double.tryParse(el.attributes['size'] ?? '1') ?? 1.0;
        final factor = raw.clamp(0.5, 3.0);
        final s = (style ?? const TextStyle())
            .copyWith(fontSize: (style?.fontSize ?? 14.0) * factor);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'richSup':
      case 'richSub':
        // Superscript / subscript as smaller inline text — a WidgetSpan
        // with real baseline shifting would NOT be selectable, so size is
        // the TextSpan-friendly cue (lossless select/copy contract wins).
        final s = (style ?? const TextStyle())
            .copyWith(fontSize: (style?.fontSize ?? 14.0) * 0.7);
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'latexInline':
      case 'latexBlock':
        // The flattened renderer cannot draw math glyphs; keep the TeX
        // source visible in a monospace tint so nothing is silently
        // dropped (lossless contract). True math rendering happens in
        // AppMarkdownBody (flutter_math_fork).
        final s = styleSheet?.code ??
            (style ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.black.withOpacity(0.05),
            );
        return [TextSpan(text: el.textContent, style: s)];
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
