import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/markdown/html_export.dart';

/// v1.15.2 reference parity (voice_transcription exporters.ts /
/// richRender.ts): the AI Parse HTML export is a LIGHT standalone document
/// (zh-CN, viewport, DOC_CSS + PRINT_CSS, H1-derived title). mermaid
/// blocks are pre-rendered to static SVG by the headless WebView2 pass on
/// Windows; in the test environment (no plugin) the renderer degrades to
/// null and the export falls back to inlining mermaid.js initialized LIGHT.
/// Diagram-free exports carry no script at all.
void main() {
  group('summaryFileTitle (reference AiPage.resultTitle port)', () {
    test('first H1 becomes the title, illegal chars stripped', () {
      const md = '# 【结论】12/10 Tester 就绪倒排：接线改越南自厂自制\n\n正文';
      expect(summaryFileTitle(md), '【结论】1210 Tester 就绪倒排：接线改越南自厂自制');
    });

    test('caps at 30 chars and falls back to AI总结', () {
      expect(summaryFileTitle('# ${'长' * 50}'), '长' * 30);
      expect(summaryFileTitle('没有标题的正文'), 'AI总结');
      expect(summaryFileTitle('#    '), 'AI总结');
    });

    test('strips every filesystem-illegal character', () {
      expect(summaryFileTitle(r'# a\b/c:d*e?f"g<h>i|j'), 'abcdefghij');
    });
  });

  group('light document wrapper (reference DOC_CSS + PRINT_CSS)', () {
    test('content without figures bypasses mermaid entirely', () async {
      const src = '## 标题\n\n正文段落，无图表。';
      final html = await wrapAiParseHtml(src);
      expect(html, wrapAiParseDocument(markdownToHtmlExport(src)));
      expect(html, isNot(contains('mermaid.min')));
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('class="mermaid"')));
    });

    test('document shell matches the reference export', () {
      final html = wrapAiParseDocument('<p>x</p>', title: '测试标题');
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<html lang="zh-CN">'));
      expect(html,
          contains('<meta name="viewport" content="width=device-width, initial-scale=1">'));
      expect(html, contains('<title>测试标题</title>'));
      // Light theme (G_SPEC ② 浅底深字) — the reference ink/paper colors.
      expect(html, contains('color: #1f2937'));
      // Explicit paper white: dark-mode browsers must not paint the canvas
      // black under the light ink (the reference relies on viewer default).
      expect(html, contains('background: #ffffff'));
      expect(html, contains('max-width: 1280px'));
      expect(html, contains('body th { background: #eef2ff'));
      // Print styles reclaim A4 width and shrink wide figures.
      expect(html, contains('@media print'));
      expect(html, contains('max-width: 760px'));
      expect(html, contains('svg.md-fig-wide { width: auto !important'));
      // The old dark wrapper is NOT used for AI Parse anymore.
      expect(html, isNot(contains('background:#0a0a0f')));
    });

    test('title is HTML-escaped', () {
      final html = wrapAiParseDocument('<p>x</p>', title: 'A&B<C>');
      expect(html, contains('<title>A&amp;B&lt;C&gt;</title>'));
    });
  });

  group('mermaid fallback path (no WebView2 in the test environment)', () {
    testWidgets('mermaid fences keep <pre class="mermaid"> + inline LIGHT js',
        (tester) async {
      const src =
          '## 结论\n\n```mermaid\nflowchart TD\n  A[开始] --> B{通过?}\n```\n\n尾注。';
      // Asset loading uses real async IO — outside the fake-async zone.
      final html = await tester.runAsync(() => wrapAiParseHtml(src));
      expect(html, contains('<pre class="mermaid">'));
      expect(html, isNot(contains('language-mermaid')));
      // The bundled mermaid.min.js is inlined (no CDN) and initialized
      // LIGHT — v1.15.2 flipped the export theme from dark to default.
      expect(html, contains('__esbuild_esm_mermaid_nm'));
      expect(html, contains('mermaid.initialize'));
      expect(html, contains('startOnLoad: true'));
      expect(html, contains('theme: "default"'));
      expect(html, isNot(contains('theme: "dark"')));
      // Non-mermaid content still converts normally.
      expect(html, contains('<h2 id="">结论</h2>'));
      expect(html, contains('<p>尾注。</p>'));
    });

    test('plain fenced code blocks are NOT re-tagged', () {
      final html = markdownToHtmlExport('```python\nprint(1)\n```');
      expect(html, isNot(contains('class="mermaid"')));
      expect(html, contains('<code class="language-python">'));
    });

    test('content-first detection: unlabeled mermaid keyword fence', () {
      final html =
          markdownToHtmlExport('```\ntimeline\n  title 节点\n```');
      expect(html, contains('<pre class="mermaid">'));
    });
  });

  group('SVG figures (reference detectFigure + sanitize + wide marking)', () {
    test('```svg fences inline as native markup in .md-figure', () {
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

    test('unlabeled svg fences inline too; non-svg stay code', () {
      final svgHtml =
          markdownToHtmlExport('```\n<svg width="10" height="10"></svg>\n```');
      expect(svgHtml, contains('<div class="md-figure"><svg'));

      final codeHtml = markdownToHtmlExport('```\nprint(1)\n```');
      expect(codeHtml, isNot(contains('md-figure')));
    });

    test('xml-labeled svg fences inline (models tag SVG as xml/html)', () {
      final html = markdownToHtmlExport(
          '```xml\n<svg width="10" height="10"></svg>\n```');
      expect(html, contains('<div class="md-figure"><svg'));
    });

    test('script vectors are stripped from inline SVG', () {
      final html = markdownToHtmlExport('```svg\n<svg width="10" height="10">'
          '<script>alert(1)</script>'
          '<rect width="10" height="10" onclick="evil()"/>'
          '<a href="javascript:evil()"><text x="1" y="5">x</text></a>'
          '</svg>\n```');
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('onclick')));
      expect(html, isNot(contains('javascript:')));
      expect(html, contains('href="#"'));
      expect(html, contains('<rect width="10" height="10"'));
    });

    testWidgets('wide figures (>1100px) keep native size + md-fig-wide',
        (tester) async {
      const src = '```svg\n<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 3790 633" width="100%">'
          '<rect width="3790" height="633"/></svg>\n```';
      final html = await tester.runAsync(() => wrapAiParseHtml(src));
      expect(html, contains('class="md-fig-wide"'));
      expect(html, contains('width="3790"'));
      expect(html, contains('height="633"'));
      expect(html, contains('max-width: none;'));
    });

    testWidgets('narrow figures are NOT wide-marked', (tester) async {
      const src = '```svg\n<svg xmlns="http://www.w3.org/2000/svg" '
          'width="960" height="420" viewBox="0 0 960 420">'
          '<rect width="960" height="420"/></svg>\n```';
      final html = await tester.runAsync(() => wrapAiParseHtml(src));
      // (the CSS rule text mentions the class — assert on the SVG tag)
      expect(html, isNot(contains('class="md-fig-wide"')));
      expect(html, contains('width="960"'));
    });
  });

  test('Work Log dark wrapper is untouched (separate exporter)', () {
    final page = wrapHtmlExportPage('<p>x</p>');
    expect(page, contains('background:#0a0a0f'));
    expect(page, contains('max-width:1280px'));
  });
}
