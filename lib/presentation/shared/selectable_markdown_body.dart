import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
  final void Function(String href)? onTapLink;

  const SelectableMarkdownBody({
    super.key,
    required this.data,
    this.hardenLineBreaks = false,
    this.baseStyle,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final style = baseStyle ?? Theme.of(context).textTheme.bodyLarge;
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
        buttonItems: editableTextState.contextMenuButtonItems,
      ),
    );
  }

  TextSpan _buildSpan(BuildContext context, String markdown, TextStyle? style) {
    final document = md.Document(
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: const [
        md.FencedCodeBlockSyntax(),
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
        final s = (style ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
          fontSize: (style?.fontSize ?? 14) + (el.tag == 'h1' ? 6 : el.tag == 'h2' ? 4 : 2),
        );
        return [TextSpan(style: s, children: _inlineSpans(el, s, context))];
      case 'ul':
      case 'ol':
        final out = <InlineSpan>[];
        var idx = 0;
        for (final item in el.children ?? <md.Node>[]) {
          idx++;
          if (out.isNotEmpty) out.add(TextSpan(text: '\n', style: style));
          final marker = el.tag == 'ol'
              ? '$idx. '
              : '${'  ' * listDepth}• ';
          out.add(TextSpan(text: marker, style: style));
          if (item is md.Element) {
            out.addAll(_inlineSpans(item, style, context));
          }
        }
        return out;
      case 'li':
        return _inlineSpans(el, style, context);
      case 'blockquote':
        final inner = _inlineSpans(el, style, context);
        final s = (style ?? const TextStyle()).copyWith(
          fontStyle: FontStyle.italic,
          color: Colors.grey,
        );
        return [TextSpan(text: '│ ', style: s), TextSpan(style: s, children: inner)];
      case 'pre':
        final code = el.textContent;
        final s = (style ?? const TextStyle()).copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.black.withOpacity(0.05),
        );
        return [TextSpan(text: code, style: s)];
      case 'hr':
        return [TextSpan(text: '──────────', style: style)];
      default:
        return _inlineSpans(el, style, context);
    }
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
        final s = (style ?? const TextStyle()).copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.black.withOpacity(0.05),
        );
        return [TextSpan(text: el.textContent, style: s)];
      case 'a':
        final href = el.attributes['href'];
        final s = (style ?? const TextStyle()).copyWith(
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
      default:
        // Unknown inline/block tag: recurse into children to keep text.
        return _inlineSpans(el, style, context);
    }
  }

  Color? _parseColor(String value) {
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final intVal = int.tryParse(hex, radix: 16);
    return intVal != null ? Color(intVal) : null;
  }
}
