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
///    backslash) are not modified again.
String hardenMarkdownLineBreaks(String markdown) {
  final out = <String>[];
  var inFence = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.add(line);
    } else if (inFence ||
        trimmed.isEmpty ||
        line.endsWith('  ') ||
        trimmed.endsWith(r'\')) {
      out.add(line);
    } else {
      out.add('$line  ');
    }
  }
  return out.join('\n');
}
