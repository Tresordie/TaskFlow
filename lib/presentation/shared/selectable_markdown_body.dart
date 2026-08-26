import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/markdown/gfm_extensions.dart';
import '../../core/markdown/latex_support.dart';
import '../../core/markdown/rich_markdown.dart';
import '../../core/theme/app_colors.dart';
import 'app_markdown_body.dart' show TaskCheckboxGlyph, alertLabel;

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
      GfmExtensions.prepare(data, hardenLineBreaks: hardenLineBreaks),
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
      blockSyntaxes: GfmExtensions.blockSyntaxes,
      inlineSyntaxes: [
        // v1.5.0: custom rich syntaxes MUST precede StrikethroughSyntax —
        // the package's strikethrough greedily consumes single-tilde runs
        // and would otherwise eat `~subscript~` before our syntax sees it.
        ...RichMarkdown.syntaxes(),
        ...LatexMarkdown.syntaxes(),
        ...GfmExtensions.inlineSyntaxes(),
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
        // v1.5.3: GFM alerts (`div.markdown-alert-*`) flatten to a colored
        // type label + gutter lines; everything else is still the v1.5.0
        // footnotes appendix (`div.footnotes`).
        final alertType = alertTypeOf(el);
        if (alertType != null) {
          return _alertSpans(el, alertType, style, context);
        }
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

  /// Renders a GFM alert (`> [!NOTE]` …) in its flattened, fully selectable
  /// form: the first line is an accent bar + colored TYPE label, then every
  /// content line keeps a matching `▎` gutter so the whole alert stays
  /// visually boxed while fitting the single-TextSpan architecture (no
  /// WidgetSpan containers). Known, accepted downgrade vs. the block
  /// renderer's tinted card.
  List<InlineSpan> _alertSpans(
    md.Element el,
    String type,
    TextStyle? style,
    BuildContext context,
  ) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.alertAccent(type, brightness);
    final labelStyle = (style ?? const TextStyle()).copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    final gutterStyle = (style ?? const TextStyle()).copyWith(
      color: accent.withOpacity(0.85),
    );
    final out = <InlineSpan>[
      TextSpan(text: '▎', style: labelStyle),
      TextSpan(text: alertLabel(type), style: labelStyle),
    ];
    for (final child in el.children ?? <md.Node>[]) {
      out.add(TextSpan(text: '\n', style: style));
      _appendGuttered(out, child, style, gutterStyle, context, '▎ ');
    }
    return out;
  }

  /// Appends one alert child block to [out], prefixing its first line and
  /// every following line (hard breaks, nested list items …) with the
  /// [gutter] so the whole alert body stays visually quoted.
  void _appendGuttered(
    List<InlineSpan> out,
    md.Node child,
    TextStyle? style,
    TextStyle gutterStyle,
    BuildContext context,
    String gutter,
  ) {
    if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
      // Lists handle per-line gutters themselves (every item line gets one).
      out.add(TextSpan(text: gutter, style: gutterStyle));
      out.addAll(_listSpans(child, style, context, 0, gutter: gutter));
      return;
    }
    out.add(TextSpan(text: gutter, style: gutterStyle));
    for (final s in _nodeSpan(child, style, context)) {
      out.add(s);
      // A hard break inside the alert starts a new quoted line.
      if (s is TextSpan && s.text != null && s.text!.endsWith('\n')) {
        out.add(TextSpan(text: gutter, style: gutterStyle));
      }
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
    int depth, {
    String gutter = '',
  }) {
    final out = <InlineSpan>[];
    final isOrdered = el.tag == 'ol';
    var idx = 0;
    for (final item in el.children ?? <md.Node>[]) {
      if (item is! md.Element) continue;
      idx++;
      if (out.isNotEmpty) {
        out.add(TextSpan(text: '\n$gutter', style: style));
      }
      // v1.5.4: task-list items carry a Material checkbox as the marker —
      // the icon WidgetSpan REPLACES the bullet instead of following it
      // (v1.5.3 used the faint ☐/☑ Unicode glyphs). Read-only; there is
      // deliberately no tap-to-toggle interaction. The trailing space span
      // keeps one text gap between icon and label.
      final taskState = _taskState(item);
      final markerSpans = taskState != null
          ? <InlineSpan>[
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: TaskCheckboxGlyph(checked: taskState),
              ),
              const TextSpan(text: ' '),
            ]
          : null;
      final marker = markerSpans ??
          [TextSpan(text: isOrdered ? '$idx. ' : '• ', style: style)];
      out.add(TextSpan(text: '${'    ' * depth}', style: style));
      out.addAll(marker);
      // A <li>'s children are its inline content plus, for nested lists,
      // further <ul>/<ol> blocks — render those on new lines, indented one
      // level deeper, rather than inline.
      for (final child in item.children ?? <md.Node>[]) {
        if (child is md.Element && child.tag == 'input') {
          continue; // already shown as the ☐ / ☑ marker
        }
        if (child is md.Element &&
            (child.tag == 'ul' || child.tag == 'ol')) {
          out.add(TextSpan(text: '\n$gutter', style: style));
          out.addAll(
            _listSpans(child, style, context, depth + 1, gutter: gutter),
          );
        } else {
          out.addAll(_nodeSpan(child, style, context));
        }
      }
    }
    return out;
  }

  /// The checkbox state of a task-list item (☑ true / ☐ false), or null for
  /// a regular item. The checkbox `<input>` sits either directly under the
  /// `<li>` (hoisted) or inside its first `<p>`.
  bool? _taskState(md.Element item) {
    bool? inputState(md.Element? input) {
      if (input == null || input.tag != 'input') return null;
      return input.attributes.containsKey('checked');
    }

    for (final child in item.children ?? <md.Node>[]) {
      if (child is md.Element) {
        final direct = inputState(child);
        if (direct != null) return direct;
        if (child.tag == 'p' && (child.children ?? const <md.Node>[]).isNotEmpty) {
          final first = child.children!.first;
          if (first is md.Element) {
            final nested = inputState(first);
            if (nested != null) return nested;
          }
        }
      }
    }
    return null;
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

  /// Renders a table as a REAL bordered `Table` widget embedded via a
  /// [WidgetSpan] (v1.5.4, user-approved route change). The v1.5.3
  /// monospace text grid silently misaligned on mixed CJK content — a CJK
  /// glyph's advance is not exactly twice the Latin monospace advance —
  /// and read as ASCII art rather than a table (pitfall 8.24).
  ///
  /// Styling mirrors the block chain's native tables (theme outline
  /// borders, bold header row, padded cells) so Preview and saved record
  /// stay WYSIWYG. Accepted downgrade — same tier as math formulas: the
  /// table's text takes no part in the drag selection and is absent from
  /// Ctrl+C copies; right-click "Copy as Markdown" still carries the full
  /// original source.
  List<InlineSpan> _tableSpans(
    md.Element el,
    TextStyle? style,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final s = style ?? const TextStyle();
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

    List<md.Element> rowCells(md.Element tr) => tr.children
            ?.whereType<md.Element>()
            .where((e) => e.tag == 'th' || e.tag == 'td')
            .toList() ??
        const [];

    final colCount = rows.fold<int>(
      0,
      (max, tr) => rowCells(tr).length > max ? rowCells(tr).length : max,
    );

    final tableRows = <TableRow>[
      for (var r = 0; r < rows.length; r++)
        TableRow(
          decoration: r == 0 && rows.length > 1
              ? BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.035),
                )
              : null,
          children: [
            for (var c = 0; c < colCount; c++)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(
                    children: _cellContent(rowCells(rows[r]), c, s, headStyle,
                        context),
                  )),
                ),
              ),
          ],
        ),
    ];

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Table(
            border: TableBorder.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              for (var c = 0; c < colCount; c++) c: const IntrinsicColumnWidth(),
            },
            children: tableRows,
          ),
        ),
      ),
    ];
  }

  /// The inline spans of cell [c] in [cells]: bold-styled when the cell is
  /// a header (`th`), plain body style otherwise. Empty text for missing
  /// cells keeps ragged AI tables rectangular.
  List<InlineSpan> _cellContent(
    List<md.Element> cells,
    int c,
    TextStyle s,
    TextStyle headStyle,
    BuildContext context,
  ) {
    if (c >= cells.length) return [TextSpan(text: '', style: s)];
    final cell = cells[c];
    final isHead = cell.tag == 'th';
    return _inlineSpans(cell, isHead ? headStyle : s, context);
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
        // Task-list checkbox (from the hoist syntaxes). Normally consumed
        // by _listSpans as the icon marker; this is the safety net for a
        // checkbox reached through another path (never literal brackets).
        final checked = el.attributes.containsKey('checked');
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: TaskCheckboxGlyph(checked: checked),
          ),
          const TextSpan(text: ' '),
        ];
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
        // v1.5.3: formulas render for real via flutter_math_fork, embedded
        // as a WidgetSpan. Known, accepted downgrade: a WidgetSpan takes no
        // part in the text selection — the formula cannot be drag-selected
        // and is absent from the copied text. Invalid TeX falls back to the
        // raw source (buildMathWidget), so nothing is ever lost. The
        // ambient text scaler is applied explicitly — flutter_math_fork
        // paints glyphs itself and would otherwise ignore the global font
        // scale (v1.5.5).
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: buildMathWidget(
              el.textContent,
              display: false,
              style: style,
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
        ];
      case 'latexBlock':
        // Display math (v1.5.3). Rendered display-style but embedded the
        // same way as inline math: the paragraph/block separators already
        // provide the blank lines, so no extra line breaks are added here
        // (v1.5.1 spacing contract).
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: buildMathWidget(
              el.textContent,
              display: true,
              style: style,
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
        ];
      case 'ul':
      case 'ol':
        // A list reached from an inline context: render it as an indented
        // block on its own lines rather than gluing it inline.
        return [
          TextSpan(text: '\n', style: style),
          ..._listSpans(el, style, context, 1),
        ];
      case 'th':
      case 'td':
        // Reached only via unusual nesting — keep the cell text.
        return _inlineSpans(el, style, context);
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
