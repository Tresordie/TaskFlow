import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/markdown/html_export.dart';

/// v1.15.0: mermaid-aware HTML export — diagram-free markdown must produce
/// byte-identical output to the plain wrapper (zero impact on other
/// exporters), while ```mermaid fences become `<pre class="mermaid">` blocks
/// with the bundled mermaid.js inlined.
void main() {
  test('content without mermaid fences bypasses mermaid entirely', () async {
    const src = '## 标题\n\n正文段落，无图表。';
    final html = await wrapAiParseHtml(src);
    expect(html,
        wrapHtmlExportPage(markdownToHtmlExport(src), title: 'AI Parse Summary'));
    expect(html, isNot(contains('mermaid.min')));
    expect(html, isNot(contains('class="mermaid"')));
  });

  testWidgets('mermaid fences re-tag to <pre class="mermaid"> + inline js',
      (tester) async {
    const src = '## 结论\n\n```mermaid\nflowchart TD\n  A[开始] --> B{通过?}\n```\n\n尾注。';
    // Asset loading uses real async IO — outside the fake-async zone, or
    // loadString would never complete.
    final html = await tester.runAsync(() => wrapAiParseHtml(src));
    expect(html, contains('<pre class="mermaid">'));
    expect(html, isNot(contains('language-mermaid')));
    // The bundled mermaid.min.js is inlined (no CDN) + initialized dark
    // (the export page is dark-themed).
    expect(html, contains('__esbuild_esm_mermaid_nm'));
    expect(html, contains('mermaid.initialize'));
    expect(html, contains('startOnLoad: true'));
    // Non-mermaid content still converts normally (gitHubWeb adds id="").
    expect(html, contains('<h2 id="">结论</h2>'));
    expect(html, contains('<p>尾注。</p>'));
  });

  test('plain fenced code blocks are NOT re-tagged', () {
    final html = markdownToHtmlExport('```python\nprint(1)\n```');
    expect(html, isNot(contains('class="mermaid"')));
    expect(html, contains('<code class="language-python">'));
  });

  test('v1.15.1: ```svg fences inline as native markup in .md-figure', () {
    const src = '```svg\n<svg xmlns="http://www.w3.org/2000/svg" '
        'width="960" height="420"><rect width="960" height="420" '
        'fill="#0f2027"/><text x="46" y="70">标题 A&amp;B</text></svg>\n```';
    final html = markdownToHtmlExport(src);
    expect(html, contains('<div class="md-figure"><svg'));
    expect(html, isNot(contains('<pre><code')));
    // Entities decoded so the browser paints the SVG (and &amp; survives).
    expect(html, contains('fill="#0f2027"'));
    expect(html, contains('标题 A&amp;B'));
  });

  test('v1.15.1: unlabeled svg fences inline too; non-svg stay code', () {
    final svgHtml = markdownToHtmlExport(
        '```\n<svg width="10" height="10"></svg>\n```');
    expect(svgHtml, contains('<div class="md-figure"><svg'));

    final codeHtml = markdownToHtmlExport('```\nprint(1)\n```');
    expect(codeHtml, isNot(contains('md-figure')));
  });

  test('v1.15.1: export page width follows the reference (1280px)', () {
    final html = wrapHtmlExportPage('<p>x</p>');
    expect(html, contains('max-width:1280px'));
    expect(html, contains('.md-figure svg{max-width:100%;height:auto;}'));
    expect(html, isNot(contains('max-width:960px')));
  });
}
