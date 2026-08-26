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

/// Display width of [text] in terminal-style columns: East-Asian-Wide /
/// Fullwidth characters (CJK ideographs, Hangul, fullwidth forms …) count
/// as 2, everything else as 1. Used to align the flattened renderer's
/// text tables so Chinese and Latin cells line up.
int displayWidth(String text) {
  var w = 0;
  for (final r in text.runes) {
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

/// Pads [text] with spaces to [width] display columns (see [displayWidth]).
String padCell(String text, int width) =>
    text + ' ' * (width - displayWidth(text)).clamp(0, 60);
