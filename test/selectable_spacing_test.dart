import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/presentation/shared/selectable_markdown_body.dart';

/// v1.5.1 contract: the flattened renderer must match standard Markdown
/// preview spacing — no uniform blank line between every block.
///  - a heading hugs the block that follows it (single \n);
///  - a list directly continuing a paragraph gets no blank line;
///  - genuine paragraph breaks keep one blank line;
///  - nothing of the source text is dropped (lossless contract).
void main() {
  const src = '''## 📋 工作总结 (2026-08-25)

### 🔑 要点总结
- **优化采购流程**：通过更新图纸并在Arena系统中创建新物料号，避免基础线缆采购后的二次返工，简化美国项目的定制线缆采购流程。
- **梳理线缆现状**：完成6款K口线的现状分类，明确共用、返工及系统缺漏物料号的具体情况。

### 📝 要点详述
**1. 采购流程优化与系统建档方案**
针对发往美国的测试项目，从而简化供应链操作。

**2. K口线现状分类与梳理**
目前项目共涉及6款K口线，具体分类如下：
- **1款**：可直接与车载CB线共用，无需额外处理。
- **3款**：需要在原Q线基础上进行返工（rework）。''';

  Future<String> render(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectableMarkdownBody(
              data: src,
              hardenLineBreaks: true,
              baseStyle: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final st = tester.widget<SelectableText>(find.byType(SelectableText));
    return (st.textSpan ?? const TextSpan(text: '')).toPlainText();
  }

  testWidgets('heading hugs the following block (no blank line)',
      (tester) async {
    final plain = await render(tester);
    expect(plain, contains('🔑 要点总结\n• '));
    expect(plain, contains('📝 要点详述\n1. '));
    // No blank line directly after any heading.
    expect(plain, isNot(contains('要点总结\n\n')));
    expect(plain, isNot(contains('要点详述\n\n')));
    expect(plain, isNot(contains('工作总结 (2026-08-25)\n\n')));
  });

  testWidgets('list continuing a paragraph gets no blank line',
      (tester) async {
    final plain = await render(tester);
    expect(plain, contains('具体分类如下：\n• 1款'));
    expect(plain, isNot(contains('具体分类如下：\n\n')));
  });

  testWidgets('genuine paragraph breaks keep one blank line',
      (tester) async {
    final plain = await render(tester);
    // Two real paragraphs stay visually separated.
    expect(plain, contains('从而简化供应链操作。\n\n2. K口线现状分类与梳理'));
    // …but never a double blank line.
    expect(plain, isNot(contains('\n\n\n')));
  });

  testWidgets('lossless: every content fragment survives', (tester) async {
    final plain = await render(tester);
    for (final fragment in [
      '📋 工作总结 (2026-08-25)',
      '优化采购流程',
      '梳理线缆现状',
      '采购流程优化与系统建档方案',
      '针对发往美国的测试项目',
      'K口线现状分类与梳理',
      '可直接与车载CB线共用',
      '需要在原Q线基础上进行返工',
    ]) {
      expect(plain, contains(fragment), reason: 'missing: $fragment');
    }
  });
}
