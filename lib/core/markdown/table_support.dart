/// GFM pipe-table source helpers shared by the in-app renderers and the
/// report export (v1.5.3).
///
/// AI models sometimes place real newlines inside a pipe-table cell
/// (e.g. multi-bullet Details columns). A markdown table row must be a
/// single line, otherwise every continuation line becomes a broken row
/// with empty cells — or the whole table collapses into literal `|` text
/// when no valid delimiter row survives. [normalizeMultilineTableRows]
/// merges those continuation lines back into the previous row (pitfall
/// 8.10), separated by `<br>` (rendered as a real line break by the app's
/// narrow `BrSyntax`, and as HTML in the report export).
library;

/// Merges continuation lines of a broken pipe-table row into the row.
///
/// A row "starts" a merge when it (after ≤3 leading spaces) begins with
/// `|` but does not end with `|`; following lines are appended — joined by
/// [separator] — until a blank line, a fresh `|` row, or a line ending in
/// `|` closes the merge. Fenced code blocks are never touched.
String normalizeMultilineTableRows(String markdown,
    {String separator = '<br>'}) {
  final lines = markdown.split('\n');
  final out = <String>[];
  var inFence = false;
  var i = 0;
  while (i < lines.length) {
    final raw = lines[i];
    final fenceTrim = raw.trim();
    if (fenceTrim.startsWith('```') || fenceTrim.startsWith('~~~')) {
      inFence = !inFence;
      out.add(raw);
      i++;
      continue;
    }
    final t = raw.trimRight();
    final tl = t.trimLeft();
    final lead = t.length - tl.length;
    if (!inFence &&
        lead <= 3 &&
        tl.startsWith('|') &&
        !tl.endsWith('|')) {
      final buf = StringBuffer(t);
      i++;
      while (i < lines.length) {
        final next = lines[i].trimRight();
        final nextTrimmed = next.trimLeft();
        // Blank line or a fresh row ends the merge.
        if (nextTrimmed.isEmpty || nextTrimmed.startsWith('|')) break;
        buf.write(separator);
        buf.write(nextTrimmed);
        i++;
        if (nextTrimmed.endsWith('|')) break;
      }
      out.add(buf.toString());
      continue;
    }
    out.add(raw);
    i++;
  }
  return out.join('\n');
}

/// Display-width helpers were removed in v1.5.4: the flattened renderer
/// now embeds a REAL bordered `Table` (WidgetSpan) instead of the old
/// monospace text grid — whose column alignment silently broke whenever a
/// CJK glyph's advance was not exactly twice the Latin monospace advance
/// (MiSans ≈ 1em vs Courier ≈ 0.6em). See pitfall 8.24.
