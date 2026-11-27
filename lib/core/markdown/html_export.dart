import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;

import '../../data/services/ai_service.dart';
import '../../data/services/figure_render_service.dart';

/// Export filename prefix / document title — verbatim port of the
/// reference `AiPage.resultTitle`: the first H1 of the summary, stripped
/// of filesystem-illegal characters, capped at 30 chars, 'AI总结' fallback
/// (v1.15.2 reference parity).
String summaryFileTitle(String markdown) {
  final h1 =
      RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(markdown)?.group(1);
  final raw = (h1 == null || h1.trim().isEmpty) ? 'AI总结' : h1.trim();
  final clean = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  return clean.length > 30 ? clean.substring(0, 30) : clean;
}

/// Mermaid diagram-type keywords — content-first detection for fences
/// without a `mermaid` label (verbatim port of the reference MERMAID_START).
final RegExp _mermaidStartPattern = RegExp(
    r'^(flowchart|graph|mindmap|gantt|sequenceDiagram|classDiagram|stateDiagram(-v2)?|erDiagram|journey|pie|gitGraph|quadDiagram|requirementDiagram|sankey-beta|xychart-beta|timeline|block-beta)\b');

final RegExp _svgStartPattern =
    RegExp(r'^<svg[\s>]', caseSensitive: false);

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
///  4. v1.15.0: ` ```mermaid ` fences become `<pre class="mermaid">` blocks;
///  5. v1.15.2 reference parity (detectFigure): CONTENT-FIRST figure
///     detection — any fence whose content starts with `<svg` becomes an
///     inline (sanitized) SVG figure, any fence starting with a mermaid
///     diagram keyword becomes a mermaid block, regardless of the label
///     (models often tag SVG as ```xml/```html or leave it unlabeled).
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

  // Content-first figure dispatch for every remaining fenced block (the
  // reference detectFigure order: <svg content → SVG, mermaid keyword →
  // mermaid, else keep the code block). Inline SVG is sanitized first —
  // script vectors never reach the exported document.
  html = html.replaceAllMapped(
      RegExp(r'<pre><code(?: class="language-[\w-]+")?>([\s\S]*?)</code></pre>'),
      (m) {
    final content = _unescapeHtmlEntities(m[1]!).trim();
    if (_svgStartPattern.hasMatch(content)) {
      return '<div class="md-figure">${_sanitizeSvgString(content)}</div>';
    }
    if (_mermaidStartPattern.hasMatch(content)) {
      return '<pre class="mermaid">${m[1]}</pre>';
    }
    return m[0]!;
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

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// String-level SVG sanitization — Dart port of the reference
/// `sanitizeSvgString`: strip script vectors, keep every visual structure
/// (DOMPurify would eat foreignObject text, so the reference uses exactly
/// these three replacements).
String _sanitizeSvgString(String svg) => svg
    .replaceAll(
        RegExp(r'<script[\s\S]*?</script\s*>', caseSensitive: false), '')
    .replaceAll(
        RegExp(r"""\son\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)""",
            caseSensitive: false),
        '')
    .replaceAllMapped(
        RegExp(
            r"""(href|xlink:href)\s*=\s*(?:"\s*javascript:[^"]*"|'\s*javascript:[^']*'|javascript:[^\s>]+)""",
            caseSensitive: false),
        (m) => '${m[1]}="#"');

/// Wide-figure threshold (reference WIDE_FIG_PX): figures whose intrinsic
/// width exceeds this keep their native size and scroll horizontally
/// instead of shrinking to the container (a 3790px timeline squeezed to
/// 1280px has unreadable text — user-verified in the reference).
const double _wideFigPx = 1100;

/// Marks every inline SVG wider than [_wideFigPx] with explicit pixel
/// width/height + `class="md-fig-wide"` + `max-width:none` — the reference
/// renderRichMarkdown wide-figure pass (string-level equivalent).
String _markWideFigures(String body) {
  return body.replaceAllMapped(RegExp(r'<svg[^>]*>'), (m) {
    final tag = m[0]!;
    final vbMatch = RegExp(r'viewBox\s*=\s*"([^"]*)"').firstMatch(tag);
    if (vbMatch == null) return tag;
    final vb = vbMatch
        .group(1)!
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (vb.length != 4 || vb.any((n) => n == null || !n.isFinite)) return tag;
    if (!(vb[2]! > _wideFigPx)) return tag;
    final w = vb[2]!.round().toString();
    final h = vb[3]!.round().toString();
    var out = _setAttr(tag, 'width', w);
    out = _setAttr(out, 'height', h);
    // class: append md-fig-wide (mermaid SVGs may already carry a class).
    final classMatch = RegExp(r'class\s*=\s*"([^"]*)"').firstMatch(out);
    if (classMatch != null) {
      if (!classMatch.group(1)!.split(' ').contains('md-fig-wide')) {
        out = out.replaceRange(classMatch.start, classMatch.end,
            'class="${classMatch.group(1)} md-fig-wide"');
      }
    } else {
      out = out.replaceFirst('>', ' class="md-fig-wide">');
    }
    // style: force max-width:none (replace an existing max-width decl).
    final styleMatch = RegExp(r'style\s*=\s*"([^"]*)"').firstMatch(out);
    if (styleMatch != null) {
      var style = styleMatch.group(1)!;
      if (RegExp(r'max-width\s*:', caseSensitive: false).hasMatch(style)) {
        style = style.replaceAll(
            RegExp(r'max-width\s*:\s*[^;"]*;?', caseSensitive: false),
            'max-width: none;');
      } else {
        style = '${style.isEmpty ? '' : '$style;'}max-width: none;';
      }
      out = out.replaceRange(
          styleMatch.start, styleMatch.end, 'style="$style"');
    } else {
      out = out.replaceFirst('>', ' style="max-width: none;">');
    }
    return out;
  });
}

/// Sets (or inserts) an attribute on an SVG opening tag string. The
/// leading-whitespace anchor keeps `width` from matching `stroke-width`.
String _setAttr(String tag, String name, String value) {
  final match = RegExp('\\s$name\\s*=\\s*"[^"]*"').firstMatch(tag);
  if (match != null) {
    return tag.replaceRange(match.start, match.end, ' $name="$value"');
  }
  return tag.replaceFirst('>', ' $name="$value">');
}

/// Light document CSS — verbatim port of the reference exporters.ts
/// DOC_CSS + PRINT_CSS (G_SPEC ②: 浅底深字 + print styles → printable PDF).
/// Screen width matches the app container (1280px); print reclaims A4
/// width (~760px) and wide figures fall back to proportional scaling.
const String _aiParseDocCss = '''
  body { font-family: "PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif; color: #1f2937;
         line-height: 1.75; max-width: 1280px; margin: 0 auto; padding: 32px 24px; }
  body img { max-width: 100%; }
  body .md-figure { margin: 1.2em 0; overflow-x: auto; }
  body .md-figure svg { max-width: 100%; height: auto; }
  body .md-figure svg.md-fig-wide { width: auto; max-width: none; }
  body h1 { font-size: 1.7em; border-bottom: 3px solid #6366f1; padding-bottom: 10px; margin: 1.2em 0 0.8em; }
  body h2 { font-size: 1.3em; border-left: 4px solid #6366f1; padding-left: 10px; margin: 1.4em 0 0.6em; }
  body h3 { font-size: 1.1em; margin: 1.1em 0 0.5em; color: #4338ca; }
  body table { border-collapse: collapse; width: 100%; margin: 0.8em 0; font-size: 0.92em; }
  body th { background: #eef2ff; color: #3730a3; }
  body th, body td { border: 1px solid #d1d5db; padding: 6px 10px; text-align: left; }
  body tr:nth-child(even) td { background: #f9fafb; }
  body code { background: #f3f4f6; border-radius: 4px; padding: 1px 5px; font-size: 0.9em; }
  body pre { background: #111827; color: #e5e7eb; border-radius: 8px; padding: 12px 14px; overflow-x: auto; }
  body pre code { background: none; color: inherit; }
  body blockquote { border-left: 4px solid #a5b4fc; background: #f5f6ff; margin: 0.8em 0; padding: 8px 14px; color: #4b5563; }
  body ul, body ol { padding-left: 1.6em; }
  body hr { border: none; border-top: 1px solid #e5e7eb; margin: 1.4em 0; }
  @media print {
    body { padding: 0; max-width: 760px; }
    body .md-figure svg.md-fig-wide { width: auto !important; max-width: 100% !important; }
  }
''';

/// AI Parse standalone document — reference `wrapHtmlDocument` port:
/// zh-CN, viewport meta, light DOC_CSS + PRINT_CSS, H1-derived title.
String wrapAiParseDocument(String body,
    {String title = 'AI总结', String extraHead = ''}) {
  return '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
      '<title>${_escapeHtml(title)}</title>\n'
      '<style>\n$_aiParseDocCss</style>\n'
      '$extraHead</head>\n<body>\n$body\n</body>\n</html>';
}

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

/// AI Parse "Save .html" — v1.15.2 reference parity:
///  * light document (DOC_CSS + PRINT_CSS, zh-CN, H1-derived title);
///  * ```mermaid blocks PRE-RENDERED to static light-theme SVG and model
///    SVG covers text-fitted via a headless WebView2 pass
///    ([renderFigures]) — the exported file needs no JavaScript and stays
///    small (the reference exports static SVG, not a 3.5 MB mermaid.js);
///  * wide figures (>1100px) keep native size + horizontal scroll;
///  * degradation: no WebView2 / non-Windows / render timeout → mermaid.js
///    is inlined and initialized LIGHT (startOnLoad), SVG figures inline
///    as before. Diagram-free exports carry no script at all.
Future<String> wrapAiParseHtml(String markdown,
    {String title = 'AI总结'}) async {
  var body = markdownToHtmlExport(markdown);

  // Collect figure blocks in document order (ids are positional).
  final prePattern = RegExp(r'<pre class="mermaid">([\s\S]*?)</pre>');
  final svgPattern =
      RegExp(r'<div class="md-figure">(<svg[\s\S]*?</svg>)</div>');
  final blocks = <FigureBlock>[];
  var mi = 0;
  for (final m in prePattern.allMatches(body)) {
    blocks.add(FigureBlock(
        id: 'm${mi++}',
        kind: 'mermaid',
        code: _unescapeHtmlEntities(m[1]!)));
  }
  var si = 0;
  for (final m in svgPattern.allMatches(body)) {
    blocks.add(FigureBlock(id: 's${si++}', kind: 'svg', code: m[1]!));
  }

  var extraHead = '';
  final rendered = blocks.isEmpty ? null : await renderFigures(blocks);
  if (rendered != null) {
    // SVG figures first (fitSvgText results)…
    var sIdx = 0;
    body = body.replaceAllMapped(svgPattern, (m) {
      final fitted = rendered.svgById['s${sIdx++}'];
      return fitted != null
          ? '<div class="md-figure">${_sanitizeSvgString(fitted)}</div>'
          : m[0]!;
    });
    // …then mermaid blocks (rendered SVG, or source + error note on a
    // per-block failure — the reference keeps the source visible).
    var mIdx = 0;
    body = body.replaceAllMapped(prePattern, (m) {
      final id = 'm${mIdx++}';
      final svg = rendered.svgById[id];
      if (svg != null) {
        return '<div class="md-figure">${_sanitizeSvgString(svg)}</div>';
      }
      final error = rendered.errorById[id];
      if (error != null) {
        return '<div class="md-figure-error">⚠️ 图表渲染失败'
            '（${_escapeHtml(error)}），已保留源码</div>'
            '<pre class="mermaid">${m[1]}</pre>';
      }
      return m[0]!;
    });
  } else if (mi > 0) {
    // Fallback: client-side mermaid, LIGHT theme (was dark pre-v1.15.2).
    final js = await rootBundle.loadString('assets/mermaid/mermaid.min.js');
    extraHead = '<script>$js</script>\n'
        '<script>mermaid.initialize({ startOnLoad: true, theme: "default", '
        'fontFamily: \'"PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif\' '
        '});</script>\n';
  }

  body = _markWideFigures(body);
  return wrapAiParseDocument(body, title: title, extraHead: extraHead);
}
