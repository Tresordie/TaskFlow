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
///    ordered / unordered list structures correctly;
///  * leading indentation (spaces) on ordinary paragraph lines is converted
///    to non-breaking spaces (U+00A0). CommonMark strips up to 3 leading
///    spaces from a paragraph and treats 4+ as a code block, so a Tab-indent
///    would otherwise be INVISIBLE in the preview ("no indent effect").
///    U+00A0 is not Markdown whitespace, so the visual indent survives
///    rendering — matching workreport.html, whose renderer keeps leading
///    spaces as-is.

/// Matches common Markdown list-item prefixes: unordered (`- `, `* `, `+ `)
/// and ordered (`1. `, `2) `, etc.) after optional leading whitespace.
final _listItemRe = RegExp(r'^\s*(?:[-*+]\s|\d+[.)]\s)');

/// Leading (1+) spaces followed by non-space content on a paragraph line.
final _leadSpaceRe = RegExp(r'^( +)(\S.*)$');

/// Full list-item line decomposition: leading spaces, marker (`-`, `*`,
/// `+`, `1.`, `2)`…), the space after the marker, and the item text.
final _listLineRe = RegExp(r'^( *)([-*+]|\d+[.)])( )(.*)$');

/// GFM alert opener (`> [!NOTE]` …) — case-sensitive, matching GitHub's
/// spec. Alert openers and table rows are exempt from hard-break padding
/// (v1.5.3): trailing spaces on a table row break TableSyntax's delimiter
/// detection, and alert lines carry their own structure.
final gfmAlertLineRe =
    RegExp(r'^\s{0,3}>\s{0,3}\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$');

/// Normalizes user-style "indent nesting" that strict CommonMark would
/// reject, so TaskFlow previews nested lists exactly like workreport.html.
///
/// CommonMark nests a sub-item only when its indent reaches the PARENT
/// item's marker width (e.g. `4. ` is 3 chars). A Tab-indented sub-item
/// (2 spaces) under a numbered item therefore becomes a TOP-LEVEL sibling
/// list — the bullet renders flush with the parent numbers instead of
/// nested beneath item 4 (the reported visual bug). workreport.html's
/// renderer nests on ANY positive indent, so here we pad an under-indented
/// line up to the enclosing parent's marker width, giving it the nested
/// rendering the user expects. Lines inside fenced code blocks are skipped.
String normalizeListNesting(String markdown) {
  final lines = markdown.split('\n');
  final out = <String>[];
  var inFence = false;
  // Open list levels: each entry is (indent, markerWidth). markerWidth is
  // the "content indent" a CHILD needs to nest under that item.
  final stack = <({int indent, int markerWidth})>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.add(line);
      stack.clear();
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    final m = _listLineRe.firstMatch(line);
    if (m == null) {
      out.add(line);
      // A blank line terminates the current list context.
      if (trimmed.isEmpty) stack.clear();
      continue;
    }
    var indent = m.group(1)!.length;
    // Close every level deeper than this item…
    while (stack.isNotEmpty && indent < stack.last.indent) {
      stack.removeLast();
    }
    // …and replace a same-level sibling on top.
    if (stack.isNotEmpty && stack.last.indent == indent) {
      stack.removeLast();
    }
    if (stack.isNotEmpty && indent < stack.last.markerWidth) {
      // Under-indented relative to the enclosing parent: pad up so
      // CommonMark parses it as a NESTED sub-item instead of a top-level
      // sibling (workreport.html's indent-based nesting semantics).
      indent = stack.last.markerWidth;
    }
    final markerWidth = indent + m.group(2)!.length + m.group(3)!.length;
    out.add('${' ' * indent}${m.group(2)}${m.group(3)}${m.group(4)}');
    stack.add((indent: indent, markerWidth: markerWidth));
  }
  return out.join('\n');
}

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
  final nested = normalizeListNesting(normalised);
  final out = <String>[];
  var inFence = false;
  for (final line in nested.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.add(line);
    } else if (inFence || trimmed.isEmpty || _listItemRe.hasMatch(line)) {
      out.add(line);
    } else if (trimmed.startsWith('|') ||
        trimmed.startsWith('\$\$') ||
        gfmAlertLineRe.hasMatch(line)) {
      // v1.5.3: structural lines keep their exact shape — a hard-break
      // suffix on a pipe-table row stops TableSyntax from matching (the
      // row collapses into literal `|` text), and alert openers / display
      // math carry their own block structure.
      out.add(line);
    } else {
      // Preserve user indentation (Tab): turn leading spaces into NBSP so
      // CommonMark keeps them visible in the rendered preview.
      final lead = _leadSpaceRe.firstMatch(line);
      final hardened = lead != null
          ? '\u00a0' * lead.group(1)!.length + lead.group(2)!
          : line;
      // Keep an existing hard break; otherwise add one.
      out.add(
          hardened.endsWith('  ') || hardened.endsWith(r'\')
              ? hardened
              : '$hardened  ');
    }
  }
  return out.join('\n');
}
