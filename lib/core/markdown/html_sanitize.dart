/// Normalises raw-HTML fragments that AI models sometimes mix into
/// Markdown output (most notably the Reports generator, whose prompt
/// mentions `<table>` / `<colgroup>` / `<br>` for the HTML export).
///
/// The in-app renderer (`flutter_markdown`, intentionally without
/// `InlineHtmlSyntax`) cannot display raw HTML — it would show the tags
/// as literal text ("messy" preview/edit screens). This sanitizer turns
/// the common HTML constructs into pure-Markdown equivalents so the same
/// source renders cleanly in-app while staying editable and exportable.
///
/// `<font color>` / `<font size>` are PRESERVED — they are first-class
/// rich-text extensions understood by [AppMarkdownBody] (RichMarkdown).
library;

final RegExp _tableRe =
    RegExp(r'<table(\s[^>]*)?>([\s\S]*?)</table>', caseSensitive: false);
final RegExp _rowRe =
    RegExp(r'<tr(\s[^>]*)?>([\s\S]*?)</tr>', caseSensitive: false);
final RegExp _cellRe =
    RegExp(r'<t[hd](\s[^>]*)?>([\s\S]*?)</t[hd]>', caseSensitive: false);
final RegExp _colgroupRe =
    RegExp(r'<colgroup[\s\S]*?</colgroup>', caseSensitive: false);
final RegExp _brRe = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _linkRe = RegExp(
    r'''<a\s[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
    caseSensitive: false);

/// Converts HTML constructs inside [input] into pure Markdown.
/// Idempotent: sanitizing an already-sanitized string is a no-op.
String sanitizeHtmlInMarkdown(String input) {
  if (!input.contains('<')) return input;
  var s = input;

  // 1. <colgroup> — HTML-export-only column-width hints.
  s = s.replaceAll(_colgroupRe, '');

  // 2. HTML tables → Markdown pipe tables.
  if (_tableRe.hasMatch(s)) {
    s = s.replaceAllMapped(
        _tableRe, (m) => '\n\n${_htmlTableToMarkdown(m.group(2)!)}\n\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  // 3. <a href> → [text](url) before generic tag stripping.
  s = s.replaceAllMapped(_linkRe, (m) {
    final text = _stripTags(m.group(2)!).trim();
    return '[${text.isEmpty ? m.group(1)! : text}](${m.group(1)})';
  });

  // 4. Inline emphasis → Markdown syntax.
  s = _wrapInline(s, ['b', 'strong'], '**');
  s = _wrapInline(s, ['i', 'em'], '*');
  s = _wrapInline(s, ['u'], '++');
  s = _wrapInline(s, ['s', 'del', 'strike'], '~~');

  // 5. Any remaining <br> → real newline.
  s = s.replaceAll(_brRe, '\n');

  // 6. Strip remaining block-level tags, KEEPING their text content and
  //    leaving <font ...> alone (renderer-native rich text).
  s = s.replaceAll(
      RegExp(
          r'</?(?:div|span|p|section|article|header|footer|main|ul|ol|li|'
          r'h[1-6]|pre|hr|center|sup|sub|small|mark|blockquote|table|'
          r'thead|tbody|tfoot|tr|td|th|caption|figure|figcaption)'
          r'(\s[^>]*)?>',
          caseSensitive: false),
      '');

  return s;
}

// ── Internals ──────────────────────────────────────────────────────────

String _htmlTableToMarkdown(String inner) {
  final rows = <List<String>>[];
  for (final rm in _rowRe.allMatches(inner)) {
    final cells = <String>[];
    for (final cm in _cellRe.allMatches(rm.group(2)!)) {
      cells.add(_cellText(cm.group(2)!));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return '';

  final colCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  // Pad short rows so every row has the same number of columns.
  for (final r in rows) {
    while (r.length < colCount) {
      r.add('');
    }
  }

  final buf = StringBuffer();
  buf.writeln('| ${rows.first.join(' | ')} |');
  buf.writeln('| ${List.filled(colCount, '---').join(' | ')} |');
  for (final r in rows.skip(1)) {
    buf.writeln('| ${r.join(' | ')} |');
  }
  return buf.toString().trimRight();
}

/// Cleans a single table cell: <br> becomes a bullet separator, nested
/// tags are dropped, entities decoded, pipes escaped.
String _cellText(String html) {
  var t = html.replaceAll(_brRe, ' • ');
  t = _stripTags(t);
  t = _unescapeEntities(t);
  t = t.replaceAll('|', r'\|');
  // Collapse internal whitespace runs (indentation inside HTML source).
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? ' ' : t;
}

String _stripTags(String html) =>
    html.replaceAll(RegExp(r'<[^>]+>'), '');

String _unescapeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// `<tag>x</tag>` → `{m}x{m}` for each tag name in [tags].
String _wrapInline(String s, List<String> tags, String m) {
  var out = s;
  for (final t in tags) {
    final re = RegExp('<$t(\\s[^>]*)?>([\\s\\S]*?)</$t>',
        caseSensitive: false);
    out = out.replaceAllMapped(re, (mt) => '$m${mt.group(2)!.trim()}$m');
  }
  return out;
}
