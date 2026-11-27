// v1.15.2 headless figure-render smoke test — runs on a REAL Windows
// device (`flutter test integration_test/figure_render_test.dart -d windows`)
// because WebView2 does not exist in the widget-test environment.
// Verifies the reference-parity export path end to end:
//   * renderFigures pre-renders mermaid → static SVG headlessly,
//   * fitSvgText repairs model-SVG text overflow,
//   * wrapAiParseHtml emits a LIGHT self-contained document with inline
//     SVG and NO mermaid.js (the reference exports static figures).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:taskflow/core/markdown/html_export.dart';
import 'package:taskflow/data/services/figure_render_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('headless WebView2 renders mermaid and fits model SVG',
      (tester) async {
    final result = await tester.runAsync(() => renderFigures([
          const FigureBlock(
            id: 'm0',
            kind: 'mermaid',
            code: 'flowchart TD\n  A[开始] --> B{通过?}\n  B -->|是| C[放行]',
          ),
          // 74 CJK chars × 18px ≈ 1332px — well past the 906px available
          // inside the 960px cover, so fitSvgText MUST act (wrap path:
          // scale ≈ 0.68 < 0.75).
          const FigureBlock(
            id: 's0',
            kind: 'svg',
            code: '<svg xmlns="http://www.w3.org/2000/svg" width="960" '
                'height="420" viewBox="0 0 960 420">'
                '<rect width="960" height="420" fill="#0f2027"/>'
                '<text x="44" y="70" fill="#ffffff" font-size="18">'
                '这是一行故意写得非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常长的结论文字'
                '</text></svg>',
          ),
        ]));
    expect(result, isNotNull, reason: 'WebView2 headless render unavailable');
    final mermaidSvg = result!.svgById['m0'];
    expect(mermaidSvg, isNotNull, reason: 'mermaid block failed: ${result.errorById}');
    expect(mermaidSvg, contains('<svg'));
    expect(mermaidSvg, contains('开始'));
    final fittedSvg = result.svgById['s0'];
    expect(fittedSvg, isNotNull);
    expect(fittedSvg, contains('<svg'));
    // fitSvgText must have acted on the overlong line: the wrap path
    // clones <text> lines (≥2 text nodes) or compresses via textLength.
    expect(
        RegExp(r'<text').allMatches(fittedSvg!).length >= 2 ||
            fittedSvg.contains('textLength'),
        isTrue,
        reason: 'fitSvgText left the overlong text untouched');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('export is a light self-contained document (no mermaid.js)',
      (tester) async {
    const md = '# 【结论】测试会议：一项决策已定\n\n'
        '```mermaid\n'
        'timeline\n'
        '  title 关键节点\n'
        '  11/23 : PCB 到货\n'
        '  12/10 : Tester 就绪\n'
        '```\n\n'
        '```svg\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="960" height="200" '
        'viewBox="0 0 960 200"><rect width="960" height="200" fill="#eeeeee"/>'
        '<text x="40" y="100" font-size="20">封面结论</text></svg>\n'
        '```\n';
    final html = await tester.runAsync(() => wrapAiParseHtml(md,
        title: summaryFileTitle(md)));
    // Debug artifact for manual inspection (temp dir, harmless).
    await tester.runAsync(() async {
      final f = File('${Directory.systemTemp.path}/tf_export_smoke.html');
      await f.writeAsString(html ?? '');
    });
    expect(html, contains('<html lang="zh-CN">'));
    expect(html, contains('color: #1f2937'));
    expect(html, contains('@media print'));
    // Both figures became inline static SVG… (mermaid word-wrapping may
    // split a label across tspans, so assert the words separately)
    expect(html, contains('<div class="md-figure"><svg'));
    expect(html, contains('Tester'));
    expect(html, contains('就绪'));
    expect(html, contains('封面结论'));
    // …and the 5.5MB mermaid.js is NOT inlined (reference parity).
    expect(html, isNot(contains('__esbuild_esm_mermaid_nm')));
    expect(html, isNot(contains('<pre class="mermaid">')));
    expect(html!.length, lessThan(500000));
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('timeline table + emoji list upgrade to visual timelines',
      (tester) async {
    const md = '# 【结论】时间轴样式验证\n\n'
        '## 发言序时间轴\n\n'
        '| 时间 | 事件 | 说明 |\n|---|---|---|\n'
        '| 00:10 | 不良资料交付顺序 | 先分类给客户确认约一周 |\n'
        '| 02:30 | 接线路径比选 | 改越南自厂自行接线 |\n'
        '| 05:40 | 固化时长未决 | 8h/4h 待验证 |\n\n'
        '## 关键节点\n\n'
        '- 🔵 11/23 PCB 到货　30 piece 板\n'
        '- 🔵 11/26 开始上线　物料先到先建\n'
        '- 🟤 12/05 ATE plan 冲突　待 Jonathan 确认\n'
        '- 🔴 12/10 Tester 就绪　6 项卡点挡在 SAT/TP 前\n\n'
        '## 任务状态\n\n'
        '| 日期 | 任务 | 状态 |\n|---|---|---|\n'
        '| 11/26 | 30 piece 上线 | 完成 |\n'
        '| 11/28 | harness 调试 | 逾期 |\n';
    final html = await tester.runAsync(() => wrapAiParseHtml(md,
        title: summaryFileTitle(md)));
    await tester.runAsync(() async {
      final f = File('${Directory.systemTemp.path}/tf_timeline_smoke.html');
      await f.writeAsString(html ?? '');
    });
    // Three visual timelines: event table, emoji list, task table.
    expect('border-radius:999px'.allMatches(html!).length, greaterThanOrEqualTo(3));
    expect(html, contains('text-decoration:line-through'));
    expect(html, contains('已逾期'));
    expect(html, isNot(contains('<table>')));
    expect(html, isNot(contains('<ul>')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
