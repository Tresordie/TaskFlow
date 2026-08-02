/// Markdown line-break handling for user-entered log content.
///
/// CommonMark treats a single newline as a *soft* break and renders it as a
/// space, so a plain multi-line entry such as
///
///     Bollard
///     8/20 - Assembly
///     8/20 - Test
///
/// would collapse into one long line. Users expect Enter to produce a visible
/// break, so [hardenMarkdownLineBreaks] turns each single newline into a
/// Markdown *hard* break (two trailing spaces) before the text is handed to
/// `MarkdownBody`.
library;

/// Returns [markdown] with single newlines converted to hard breaks.
///
/// The transformation is deliberately conservative:
///  * lines inside fenced code blocks (``` or ~~~) are left untouched so code
///    is not padded with trailing spaces;
///  * blank lines are preserved so an intentional empty line still produces a
///    paragraph break rather than a hard break;
///  * lines that already end a hard break (two trailing spaces or a trailing
///    backslash) are not modified again;
///  * list-item lines (starting with `- `, `* `, `+ `, or `1. ` after optional
///    indentation) are left untouched so the Markdown parser can recognise
///    ordered / unordered list structures correctly.

/// Matches common Markdown list-item prefixes: unordered (`- `, `* `, `+ `)
/// and ordered (`1. `, `2) `, etc.) after optional leading whitespace.
final _listItemRe = RegExp(r'^\s*(?:[-*+]\s|\d+[.)]\s)');

String hardenMarkdownLineBreaks(String markdown) {
  // Normalise Windows / old-Mac line endings so the parser sees clean \n.
  // Also collapse exotic horizontal whitespace — non-breaking space (U+00A0),
  // ideographic/full-width space (U+3000) and other Unicode spaces commonly
  // introduced by browser copy/paste — into plain ASCII spaces, so the
  // CommonMark parser recognises list indentation. This mirrors the lenient
  // line-based renderer used by translate_tool.
  final normalised = markdown
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(
          RegExp('[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]'), ' ');
  final out = <String>[];
  var inFence = false;
  for (final line in normalised.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.add(line);
    } else if (inFence ||
        trimmed.isEmpty ||
        line.endsWith('  ') ||
        trimmed.endsWith(r'\') ||
        _listItemRe.hasMatch(line)) {
      out.add(line);
    } else {
      out.add('$line  ');
    }
  }
  return out.join('\n');
}
