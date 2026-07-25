import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// `++underlined text++` — underline is not part of CommonMark.
class UnderlineSyntax extends md.InlineSyntax {
  UnderlineSyntax() : super(r'\+\+([^+\n]+)\+\+');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('richUnderline', match.group(1) ?? ''));
    return true;
  }
}

/// `==highlighted text==` — background highlight (mark).
class HighlightSyntax extends md.InlineSyntax {
  HighlightSyntax() : super(r'==([^=\n]+)==');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('richHighlight', match.group(1) ?? ''));
    return true;
  }
}

/// `<font color="#RRGGBB">text</font>` (also accepts `#RGB` and a small set
/// of named colors). The color is carried on the element as an attribute so
/// the builder can style the text.
class FontColorSyntax extends md.InlineSyntax {
  FontColorSyntax()
      : super(
          r'<font\s+color\s*=\s*["'
          "'"
          r']?([^"'
          "'"
          r'\s>]+)["'
          "'"
          r']?\s*>([^<]*)</font>',
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('richFontColor', match.group(2) ?? '');
    el.attributes['color'] = match.group(1) ?? '';
    parser.addNode(el);
    return true;
  }
}

/// `<font size="1.4">text</font>` — the value is an em multiplier
/// (1.0 = surrounding text size).
class FontSizeSyntax extends md.InlineSyntax {
  FontSizeSyntax()
      : super(
          r'<font\s+size\s*=\s*["'
          "'"
          r']?(\d+(?:\.\d+)?)["'
          "'"
          r']?\s*>([^<]*)</font>',
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('richFontSize', match.group(2) ?? '');
    el.attributes['size'] = match.group(1) ?? '1';
    parser.addNode(el);
    return true;
  }
}

/// Parses `#RGB` / `#RRGGBB` / `#RRGGBBAA` hex strings and a small palette
/// of CSS-style color names. Returns null when unparseable.
Color? parseRichTextColor(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(v);
    }
    return null;
  }
  const named = <String, Color>{
    'red': Color(0xFFEF4444),
    'orange': Color(0xFFF97316),
    'amber': Color(0xFFF59E0B),
    'yellow': Color(0xFFEAB308),
    'green': Color(0xFF22C55E),
    'teal': Color(0xFF14B8A6),
    'cyan': Color(0xFF06B6D4),
    'blue': Color(0xFF3B82F6),
    'indigo': Color(0xFF6366F1),
    'purple': Color(0xFF8B5CF6),
    'pink': Color(0xFFEC4899),
    'brown': Color(0xFF92400E),
    'gray': Color(0xFF6B7280),
    'grey': Color(0xFF6B7280),
    'black': Color(0xFF111827),
    'white': Color(0xFFFFFFFF),
  };
  return named[s];
}

/// Renders the elements emitted by [UnderlineSyntax].
class UnderlineBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  UnderlineBuilder({this.baseStyle});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final style = (preferredStyle ?? baseStyle ?? const TextStyle())
        .copyWith(decoration: TextDecoration.underline);
    return Text(element.textContent, style: style);
  }
}

/// Renders the elements emitted by [HighlightSyntax] as text on a soft
/// yellow background, like a marker pen.
class HighlightBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  HighlightBuilder({this.baseStyle});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final style = preferredStyle ?? baseStyle ?? const TextStyle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFEAB308).withOpacity(0.28),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(element.textContent, style: style),
    );
  }
}

/// Renders `<font color="...">` spans. Unknown colors fall back to the
/// surrounding text color instead of crashing.
class FontColorBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  FontColorBuilder({this.baseStyle});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final style = preferredStyle ?? baseStyle ?? const TextStyle();
    final color = parseRichTextColor(element.attributes['color'] ?? '');
    return Text(
      element.textContent,
      style: color == null ? style : style.copyWith(color: color),
    );
  }
}

/// Renders `<font size="N">` spans, where N scales the surrounding font
/// size (em-like multiplier, clamped to a sane 0.5–3.0 range).
class FontSizeBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  FontSizeBuilder({this.baseStyle});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final style = preferredStyle ?? baseStyle ?? const TextStyle();
    final raw = double.tryParse(element.attributes['size'] ?? '1') ?? 1.0;
    final factor = raw.clamp(0.5, 3.0);
    final base = style.fontSize ?? 14.0;
    return Text(
      element.textContent,
      style: style.copyWith(fontSize: base * factor),
    );
  }
}

/// Convenience wiring for a [MarkdownBody]: the syntaxes + builders needed
/// to render the rich-text extensions (underline, highlight, font color,
/// font size) inside Markdown content.
class RichMarkdown {
  RichMarkdown._();

  static List<md.InlineSyntax> syntaxes() => [
        UnderlineSyntax(),
        HighlightSyntax(),
        FontColorSyntax(),
        FontSizeSyntax(),
      ];

  static Map<String, MarkdownElementBuilder> builders(TextStyle? baseStyle) => {
        'richUnderline': UnderlineBuilder(baseStyle: baseStyle),
        'richHighlight': HighlightBuilder(baseStyle: baseStyle),
        'richFontColor': FontColorBuilder(baseStyle: baseStyle),
        'richFontSize': FontSizeBuilder(baseStyle: baseStyle),
      };
}
