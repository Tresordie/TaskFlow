import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Inline Markdown syntax that recognises LaTeX delimited by `$...$`
/// (inline math) and `$$...$$` (single-line display math).
///
/// Multi-line display math is not matched — keep `$$...$$` on one line.
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax() : super(r'\$\$([^$]+)\$\$|\$([^$\n]+)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match.group(1); // $$...$$
    final inline = match.group(2); // $...$
    final tex = (display ?? inline ?? '').trim();
    final tag = display != null ? 'latexBlock' : 'latexInline';
    parser.addNode(md.Element.text(tag, tex));
    return true;
  }
}

/// Builds a [Math] widget for the elements emitted by [LatexInlineSyntax].
/// Invalid TeX degrades to the raw source in an italic red style instead of
/// crashing the log view.
class LatexBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  LatexBuilder({this.baseStyle});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    final isBlock = element.tag == 'latexBlock';
    final style = baseStyle ?? preferredStyle;

    // Math.tex parses eagerly and throws on invalid TeX, so guard it and
    // fall back to the raw source instead of crashing the log view.
    Widget math;
    try {
      math = Math.tex(
        tex,
        mathStyle: isBlock ? MathStyle.display : MathStyle.text,
        textStyle: style,
      );
    } catch (_) {
      math = Text(
        tex,
        style: style?.copyWith(
          color: Colors.redAccent,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (isBlock) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        child: math,
      );
    }
    return math;
  }
}

/// Convenience wiring for a [MarkdownBody]: the syntaxes + builders needed
/// to render LaTeX inside Markdown content.
class LatexMarkdown {
  LatexMarkdown._();

  static List<md.InlineSyntax> syntaxes() => [LatexInlineSyntax()];

  static Map<String, MarkdownElementBuilder> builders(TextStyle? baseStyle) => {
        'latexBlock': LatexBuilder(baseStyle: baseStyle),
        'latexInline': LatexBuilder(baseStyle: baseStyle),
      };
}
