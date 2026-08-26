import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Inline Markdown syntax that recognises LaTeX delimited by `$...$`
/// (inline math) and `$$...$$` (display math on a single line — use
/// [flattenDisplayMath] first so multi-line `$$` blocks are joined).
///
/// Boundary rules (v1.5.3) prevent money text from being misparsed:
///  * the opening `$` must not be followed by whitespace or another `$`;
///  * the closing `$` must not be preceded by whitespace and must not be
///    followed by another `$`;
///  * the content must be non-empty.
///
/// So `$100 and $5` stays literal, while `$E=mc^2$` renders. `\(...\)` /
/// `\[...\]` are deliberately NOT recognised.
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax()
      : super(
          r'\$\$([^$\n]+)\$\$|(?<!\$)\$(?!\$)'
          r'([^\s$](?:[^$\n]*[^\s$])?)'
          r'\$(?!\$)',
        );

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

/// Joins multi-line display-math blocks into single `$$ tex $$` lines so
/// the inline [LatexInlineSyntax] can match them. A block opens with a
/// line that is exactly `$$` (≤3 leading spaces) and closes at the next
/// `$$` line; everything in between is joined with single spaces. An
/// unclosed block is left untouched (renders as literal text).
///
/// Fenced code blocks and inline (single-line) `$$` are not touched.
String flattenDisplayMath(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  final bareRe = RegExp(r'^\s{0,3}\$\$\s*$');
  var inFence = false;
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.add(line);
      i++;
      continue;
    }
    if (!inFence && bareRe.hasMatch(line)) {
      // Opening `$$` — look for the closing `$$` line.
      final buf = StringBuffer();
      var j = i + 1;
      var closed = false;
      while (j < lines.length) {
        if (bareRe.hasMatch(lines[j])) {
          closed = true;
          break;
        }
        final content = lines[j].trim();
        if (content.isNotEmpty) {
          if (buf.isNotEmpty) buf.write(' ');
          buf.write(content);
        }
        j++;
      }
      if (closed) {
        out.add('\$\$${buf.toString().trim()}\$\$');
        i = j + 1;
        continue;
      }
      // Unclosed: fall through and emit the line unchanged.
    }
    out.add(line);
    i++;
  }
  return out.join('\n');
}

/// Builds the widget that renders one TeX expression. [Math.tex] parses
/// eagerly and throws on invalid TeX, so invalid input degrades to the raw
/// source (italic, dimmed) instead of crashing the view. During AI
/// streaming an incomplete formula simply does not match the syntax, and
/// once the stream finishes the re-parse renders it — no special handling
/// needed here.
///
/// flutter_math_fork paints glyphs itself and does NOT respond to the
/// ambient [TextScaler], so at font scales above 100% formulas would shrink
/// relative to the surrounding text. Callers pass the context's scaler
/// (`MediaQuery.textScalerOf(context)`) and the base font size is scaled
/// explicitly (v1.5.5).
Widget buildMathWidget(
  String tex, {
  required bool display,
  TextStyle? style,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final base = style ?? const TextStyle();
  final scaled = base.copyWith(
    fontSize:
        textScaler.scale(base.fontSize ?? 14.0),
  );
  try {
    return Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: scaled,
    );
  } catch (_) {
    return Text(
      tex,
      style: scaled.copyWith(
        color: Colors.redAccent,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// Builds a [Math] widget for the elements emitted by [LatexInlineSyntax].
/// Invalid TeX degrades to the raw source in an italic red style instead of
/// crashing the log view. Uses [visitElementAfterWithContext] so the formula
/// follows the ambient font scale (v1.5.5).
class LatexBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  LatexBuilder({this.baseStyle});

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    final isBlock = element.tag == 'latexBlock';
    final style = baseStyle ?? preferredStyle;
    final scaler = MediaQuery.textScalerOf(context);

    final math = buildMathWidget(
      tex,
      display: isBlock,
      style: style,
      textScaler: scaler,
    );
    if (isBlock) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
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
