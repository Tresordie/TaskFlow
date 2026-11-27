import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;

import '../../data/services/ai_service.dart';

/// Matches ```mermaid fenced blocks (v1.15.0 — AI Parse diagram export).
final RegExp _mermaidFencePattern =
    RegExp(r'```\s*mermaid\b', caseSensitive: false);

/// Converts the app's Markdown (including its rich-text extensions) into a
/// standalone HTML fragment for export.
///
/// Pipeline:
///  1. strip `"$1"`-style numbering placeholders (legacy saved summaries);
///  2. translate `==mark==`, `++underline++`, `<font color>` and
///     `<font size>` into raw HTML — package:markdown passes inline HTML
///     through untouched, while `==` / `++` are not syntax it recognises;
///  3. run the GitHub-flavored converter so headings, lists, task-list
///     checkboxes, fenced code blocks, tables, strikethrough, autolinks
///     and inline formatting inside headings all work;
///  4. v1.15.0: ` ```mermaid ` fences become `<pre class="mermaid">` blocks
///     (rendered to diagrams by the bundled mermaid.js when the wrapper
///     page includes it — see [wrapAiParseHtml]). Content without mermaid
///     fences is untouched.
String markdownToHtmlExport(String src) {
  var t = AiService.stripDollarPlaceholders(src);

  t = t.replaceAllMapped(
      RegExp(r"""<font\s+color\s*=\s*["']?([^"'\s>]+)["']?\s*>([^<]*)</font>""",
          caseSensitive: false),
      (m) => '<span style="color:${m[1]}">${m[2]}</span>');
  t = t.replaceAllMapped(
      RegExp(
          r"""<font\s+size\s*=\s*["']?(\d+(?:\.\d+)?)["']?\s*>([^<]*)</font>""",
          caseSensitive: false),
      (m) => '<span style="font-size:${m[1]}em">${m[2]}</span>');
  t = t.replaceAllMapped(
      RegExp(r'==([^=\n]+)=='), (m) => '<mark>${m[1]}</mark>');
  t = t.replaceAllMapped(RegExp(r'\+\+([^+\n]+)\+\+'), (m) => '<u>${m[1]}</u>');

  var html =
      md.markdownToHtml(t, extensionSet: md.ExtensionSet.gitHubWeb).trim();

  // package:markdown emits `<pre><code class="language-mermaid">…</code></pre>`;
  // re-tag so mermaid.js finds the blocks. The inner content stays HTML-
  // escaped — mermaid reads textContent, which decodes back to the source.
  html = html.replaceAllMapped(
      RegExp(r'<pre><code class="language-mermaid">([\s\S]*?)</code></pre>'),
      (m) => '<pre class="mermaid">${m[1]}</pre>');

  // v1.15.1: ```svg fences (G_SPEC cover blocks / figures) become INLINE
  // markup — browsers paint inline SVG natively, no script needed. Also
  // catches unlabeled fences whose content is an svg document.
  html = html.replaceAllMapped(
      RegExp(r'<pre><code(?: class="language-svg")?>([\s\S]*?)</code></pre>'),
      (m) {
    final content = _unescapeHtmlEntities(m[1]!).trim();
    if (!content.startsWith('<svg')) return m[0]!;
    return '<div class="md-figure">$content</div>';
  });
  return html;
}

/// Reverses package:markdown's entity escaping so raw markup (inline SVG)
/// can be embedded verbatim. `&amp;` is decoded LAST to avoid double
/// decoding (e.g. `&amp;lt;` → `&lt;` → `<`).
String _unescapeHtmlEntities(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Wraps an exported HTML [body] in the dark-themed standalone page used by
/// the Work Log "save as HTML" action. [extraHead] is injected before
/// `</head>` (default empty — byte-identical to the pre-mermaid output).
///
/// Content width follows the voice_transcription reference exporter
/// (`max-width: 1280px; padding: 32px 24px`) — the old 960px squeezed the
/// AI report's wide tables and SVG cover blocks.
String wrapHtmlExportPage(String body,
    {String title = 'Work Summary', String extraHead = ''}) {
  return '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="UTF-8"/>\n'
      '<title>$title</title>\n'
      '<style>\n'
      '  body{font-family:Inter,"Segoe UI",sans-serif;background:#0a0a0f;color:#e8eaf0;'
      'padding:32px 24px;max-width:1280px;margin:0 auto;line-height:1.85;font-size:15px;}\n'
      '  .md-figure{margin:14px 0;}\n'
      '  .md-figure svg{max-width:100%;height:auto;}\n'
      '  h2{color:#a78bfa;font-size:1.5rem;border-bottom:1px solid rgba(139,92,246,0.3);padding-bottom:10px;margin:32px 0 16px;}\n'
      '  h3{color:#22d3ee;font-size:1.15rem;margin:24px 0 10px;}\n'
      '  h4{color:#c4b5fd;font-size:1rem;margin:18px 0 8px;}\n'
      '  ul,ol{margin:8px 0 16px 20px;}\n'
      '  li{margin:6px 0;line-height:1.7;}\n'
      '  strong{color:#c4b5fd;}\n'
      '  hr{border:none;border-top:1px solid rgba(139,92,246,0.15);margin:24px 0;}\n'
      '  p{margin:8px 0;}\n'
      '  code{background:rgba(139,92,246,0.12);padding:2px 6px;border-radius:4px;font-size:0.9em;}\n'
      '  pre{background:rgba(139,92,246,0.08);border:1px solid rgba(139,92,246,0.2);border-radius:8px;padding:12px 14px;overflow-x:auto;}\n'
      '  pre code{background:none;padding:0;}\n'
      '  blockquote{border-left:3px solid rgba(139,92,246,0.4);margin:10px 0;padding:4px 14px;color:#b6bcd4;}\n'
      '  mark{background:rgba(250,204,21,0.22);color:#fde68a;padding:1px 5px;border-radius:3px;}\n'
      '  u{text-underline-offset:3px;text-decoration-color:rgba(167,139,250,0.65);}\n'
      '  input[type="checkbox"]{margin-right:8px;accent-color:#a78bfa;}\n'
      '  table{border-collapse:collapse;margin:12px 0;}\n'
      '  th,td{border:1px solid rgba(139,92,246,0.25);padding:6px 12px;}\n'
      '  a{color:#22d3ee;}\n'
      '</style>\n'
      '$extraHead'
      '</head>\n<body>\n$body\n</body>\n</html>';
}

/// AI Parse "Save .html": mermaid-aware export. Only when the source
/// markdown actually contains ```mermaid fences is the bundled mermaid.js
/// (~3.5 MB) inlined — diagram-free exports stay byte-identical to the
/// plain wrapper (zero impact on any other exporter).
Future<String> wrapAiParseHtml(String markdown,
    {String title = 'AI Parse Summary'}) async {
  final body = markdownToHtmlExport(markdown);
  if (!_mermaidFencePattern.hasMatch(markdown)) {
    return wrapHtmlExportPage(body, title: title);
  }
  final js = await rootBundle.loadString('assets/mermaid/mermaid.min.js');
  final extraHead = '<script>$js</script>\n'
      '<script>mermaid.initialize({ startOnLoad: true, theme: "dark" });</script>\n';
  return wrapHtmlExportPage(body, title: title, extraHead: extraHead);
}
