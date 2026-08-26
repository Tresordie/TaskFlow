import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:taskflow/core/markdown/gfm_extensions.dart';
import 'package:taskflow/core/markdown/latex_support.dart';
import 'package:taskflow/core/markdown/line_breaks.dart';
import 'package:taskflow/core/markdown/table_support.dart' as table_support;
import 'package:taskflow/presentation/shared/app_markdown_body.dart';
import 'package:taskflow/presentation/shared/selectable_markdown_body.dart';

/// v1.5.3 contracts for the four GFM additions — tables, task lists,
/// alerts, LaTeX — across BOTH rendering chains:
///   * [AppMarkdownBody]  — block-level widgets (AI content, reports);
///   * [SelectableMarkdownBody] — the whole-Note selectable renderer that
///     also backs the editor Preview (WYSIWYG contract).
void main() {
  // ────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────

  Widget appBody(String data, {bool harden = false}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppMarkdownBody(data: data, hardenLineBreaks: harden),
          ),
        ),
      );

  Widget selectableBody(String data, {bool harden = false}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectableMarkdownBody(data: data, hardenLineBreaks: harden),
          ),
        ),
      );

  Future<String> selectablePlain(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final st = tester.widget<SelectableText>(find.byType(SelectableText));
    return (st.textSpan ?? const TextSpan(text: '')).toPlainText();
  }

  /// Every visible string painted by the block renderer (Text + RichText).
  String blockText(WidgetTester tester) {
    final buf = StringBuffer();
    for (final el in find.byType(Text).evaluate()) {
      final t = el.widget as Text;
      if (t.data != null) buf.writeln(t.data);
    }
    for (final el in find.byType(RichText).evaluate()) {
      buf.writeln((el.widget as RichText).text.toPlainText());
    }
    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────
  // 1. GFM tables
  // ────────────────────────────────────────────────────────────────────
  group('GFM tables', () {
    const tableSrc = '''| # | 优先级 | 事项 | 依赖 |
|---|---|---|---|
| A1 | P0 | 整理并分享采购清单给 Foxlink | 无 |
| A2 | P1 | 跟进软件更新 | 等待回复 |''';

    testWidgets('block chain renders a real Table (no literal pipes)',
        (tester) async {
      await tester.pumpWidget(appBody(tableSrc, harden: true));
      await tester.pumpAndSettle();

      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children.length, 3); // header + 2 data rows

      final text = blockText(tester);
      expect(text, contains('整理并分享采购清单给 Foxlink'));
      expect(text, contains('跟进软件更新'));
      // No literal pipe row may survive as plain text.
      expect(text, isNot(contains('| A1 | P0')));
    });

    testWidgets('selectable chain embeds a real bordered table (CJK safe)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(selectableBody(tableSrc, harden: true));
      await tester.pumpAndSettle();

      // v1.5.4: the flattened renderer embeds a REAL Table via WidgetSpan —
      // no ASCII pipes, and CJK cells render in their natural font so
      // columns cannot misalign.
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children.length, 3); // header + 2 data rows
      expect(find.textContaining('整理并分享采购清单给 Foxlink'), findsOneWidget);
      expect(find.textContaining('跟进软件更新'), findsOneWidget);

      final plain = await selectablePlain(tester);
      expect(plain, isNot(contains('| A1 | P0'))); // no literal pipes

      // Whole-document selection contract still holds.
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('multi-line table rows are merged back (pitfall 8.10)',
        (tester) async {
      const broken = '''| 项目 | 详情 |
|---|---|
| 电源 | 第一行内容
第二行内容 |''';
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(selectableBody(broken));
      await tester.pumpAndSettle();

      // The merge must restore ONE data row containing both fragments.
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children.length, 2); // header + merged row
      expect(find.textContaining('第一行内容'), findsOneWidget);
      expect(find.textContaining('第二行内容'), findsOneWidget);
    });

    testWidgets('<br> inside a cell renders a line break, not literal text',
        (tester) async {
      const src = '''| 项 | 值 |
|---|---|
| a | 行一<br>行二 |''';
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(selectableBody(src));
      await tester.pumpAndSettle();

      final richTexts = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText());
      final joined = richTexts.join('\n');
      expect(joined, contains('行一\n行二'));
      expect(joined, isNot(contains('<br>')));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 2. Task lists
  // ────────────────────────────────────────────────────────────────────
  group('task lists', () {
    const taskSrc = '''- [ ] 验证 Power distribution 方案是否符合指导
- [x] 已确认 splice harness 是否需要''';

    testWidgets('block chain shows Material checkboxes, never literal '
        'brackets', (tester) async {
      await tester.pumpWidget(appBody(taskSrc, harden: true));
      await tester.pumpAndSettle();

      // v1.5.4: real checkbox icons (open + checked), not faint glyphs.
      final glyphs =
          tester.widgetList<TaskCheckboxGlyph>(find.byType(TaskCheckboxGlyph));
      expect(glyphs.map((g) => g.checked).toList(), [false, true]);
      final text = blockText(tester);
      expect(text, contains('验证 Power distribution 方案是否符合指导'));
      expect(text, isNot(contains('[ ]')));
      expect(text, isNot(contains('[x]')));
    });

    testWidgets('selectable chain: icon marker REPLACES the bullet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(selectableBody(taskSrc, harden: true));
      final plain = await selectablePlain(tester);

      // The WidgetSpan icon shows up as \uFFFC in plain text; the item
      // label follows after one space. No bullet, no literal brackets.
      expect(plain, contains('\uFFFC 验证 Power distribution'));
      expect(plain, contains('\uFFFC 已确认 splice harness'));
      expect(plain, isNot(contains('• \uFFFC')));
      expect(plain, isNot(contains('[ ]')));
      expect(plain, isNot(contains('[x]')));

      final glyphs =
          tester.widgetList<TaskCheckboxGlyph>(find.byType(TaskCheckboxGlyph));
      expect(glyphs.map((g) => g.checked).toList(), [false, true]);
    });

    testWidgets('mixing with nested + ordered lists keeps indentation',
        (tester) async {
      const src = '''- [ ] 父任务
  - [ ] 子任务一
- 普通项

1. 有序一''';
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(selectableBody(src, harden: true));
      final plain = await selectablePlain(tester);

      expect(plain, contains('\uFFFC 父任务'));
      expect(plain, contains('\n    \uFFFC 子任务一'));
      expect(plain, contains('• 普通项'));
      expect(plain, contains('1. 有序一'));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 3. GFM alerts
  // ────────────────────────────────────────────────────────────────────
  group('GFM alerts', () {
    testWidgets('all five types render a themed label in the block chain',
        (tester) async {
      for (final type in const [
        'NOTE',
        'TIP',
        'IMPORTANT',
        'WARNING',
        'CAUTION',
      ]) {
        await tester.pumpWidget(appBody('> [!$type]\n> 内容行'));
        await tester.pumpAndSettle();
        expect(find.text(type), findsOneWidget,
            reason: 'alert label for $type');
        expect(blockText(tester), contains('内容行'),
            reason: 'alert content for $type');
      }
    });

    testWidgets('multi-line alert keeps inline styles and inline math',
        (tester) async {
      const src = '''> [!NOTE]
> 注意事项，支持 **加粗** 与 \$E = mc^2\$ 行内公式。

> [!WARNING]
> 警告内容第一行
> 警告内容第二行''';
      await tester.pumpWidget(appBody(src, harden: true));
      await tester.pumpAndSettle();

      final text = blockText(tester);
      expect(text, contains('注意事项'));
      expect(text, contains('警告内容第一行'));
      expect(text, contains('警告内容第二行'));
      // Inline math inside the alert renders through the SAME extensions.
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('alert content may contain lists', (tester) async {
      const src = '''> [!TIP]
> - 第一项
> - 第二项''';
      await tester.pumpWidget(appBody(src));
      await tester.pumpAndSettle();
      final text = blockText(tester);
      expect(text, contains('第一项'));
      expect(text, contains('第二项'));
    });

    testWidgets('plain blockquotes are untouched (regression)',
        (tester) async {
      const src = '> 普通引用必须保持原样渲染';
      await tester.pumpWidget(appBody(src, harden: true));
      await tester.pumpAndSettle();

      final text = blockText(tester);
      expect(text, contains('普通引用必须保持原样渲染'));
      for (final label in const [
        'NOTE',
        'TIP',
        'IMPORTANT',
        'WARNING',
        'CAUTION',
      ]) {
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets('lowercase [!note] is NOT an alert (case-sensitive)',
        (tester) async {
      await tester.pumpWidget(appBody('> [!note]\n> 小写不算'));
      await tester.pumpAndSettle();
      expect(find.text('NOTE'), findsNothing);
      expect(blockText(tester), contains('[!note]'));
    });

    testWidgets('selectable chain: colored bar label + guttered content '
        'lines', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      const src = '''> [!WARNING]
> 警告第一行
> 警告第二行''';
      await tester.pumpWidget(selectableBody(src, harden: true));
      final plain = await selectablePlain(tester);

      // v1.5.4: accent ▎ bar before the label and on every content line.
      expect(plain, contains('▎WARNING'));
      expect(plain, contains('▎ 警告第一行'));
      expect(plain, contains('▎ 警告第二行'));
      expect(plain, isNot(contains('[!WARNING]')));
    });

    testWidgets('selectable chain: plain blockquote regression',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester
          .pumpWidget(selectableBody('> 普通引用必须保持原样渲染', harden: true));
      final plain = await selectablePlain(tester);

      expect(plain, contains('│ 普通引用必须保持原样渲染'));
      expect(plain, isNot(contains('NOTE')));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 4. LaTeX
  // ────────────────────────────────────────────────────────────────────
  group('LaTeX', () {
    testWidgets('block chain renders inline and block math', (tester) async {
      const src = r'''行内公式 $E = mc^2$ 与货币 $100 混排。

$$\int_{0}^{\infty} e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$''';
      await tester.pumpWidget(appBody(src));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNWidgets(2));
      // The currency stays literal.
      expect(blockText(tester), contains(r'$100'));
    });

    testWidgets('multi-line \$\$ blocks are flattened and rendered',
        (tester) async {
      const src = '前置说明。\n\n\$\$\nx = \\frac{a}{b}\n\$\$\n\n后置说明。';
      await tester.pumpWidget(appBody(src));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('invalid TeX falls back to the raw source, never crashes',
        (tester) async {
      await tester.pumpWidget(appBody(r'$$\unknowncmd{x}$$'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final mathRendered = find.byType(Math).evaluate().isNotEmpty;
      final fallbackShown =
          find.textContaining('unknowncmd').evaluate().isNotEmpty;
      expect(mathRendered || fallbackShown, isTrue);
    });

    testWidgets('money text is never misparsed as math (both chains)',
        (tester) async {
      const src = r'预算 $100 and $5 都是钱。';
      await tester.pumpWidget(appBody(src));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNothing);
      expect(blockText(tester), contains(r'$100 and $5'));

      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(selectableBody(src));
      final plain = await selectablePlain(tester);
      expect(plain, contains(r'$100 and $5'));
    });

    testWidgets('selectable chain renders math via WidgetSpan and keeps '
        'the spacing contract', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      const src = '前文段落。\n\n\$\$E = mc^2\$\$\n\n后文段落。';
      await tester.pumpWidget(selectableBody(src));
      final plain = await selectablePlain(tester);

      // The formula widget is embedded in the single SelectableText.
      expect(find.byType(Math), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(plain, contains('前文段落。'));
      expect(plain, contains('后文段落。'));
      // v1.5.1 spacing contract: no triple newlines around the formula.
      expect(plain, isNot(contains('\n\n\n')));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 5. Preparation pipeline (pure unit tests)
  // ────────────────────────────────────────────────────────────────────
  group('prep pipeline', () {
    test('flattenDisplayMath joins multi-line \$\$ blocks', () {
      expect(
        flattenDisplayMath('a\n\$\$\nx + y\n= z\n\$\$\nb'),
        'a\n\$\$x + y = z\$\$\nb',
      );
      // Unclosed blocks stay untouched.
      expect(flattenDisplayMath('a\n\$\$\nx + y'), 'a\n\$\$\nx + y');
      // Single-line $$ is not touched.
      expect(flattenDisplayMath(r'$$x$$'), r'$$x$$');
    });

    test('normalizeMultilineTableRows merges broken rows with <br>', () {
      const broken = '| a | b |\n|---|---|\n| c | 第一行\n第二行 |';
      final merged = table_support.normalizeMultilineTableRows(broken);
      expect(merged, contains('| c | 第一行<br>第二行 |'));
    });

    test('harden leaves table rows, alert openers and \$\$ lines intact', () {
      const src = '| a | b |\n> [!NOTE]\n\$\$E=mc^2\$\$\n普通行';
      final out = hardenMarkdownLineBreaks(src);
      expect(out, contains('| a | b |'));
      expect(out, contains('> [!NOTE]'));
      expect(out, contains('\$\$E=mc^2\$\$'));
      expect(out, endsWith('普通行  '));
      expect(out, isNot(contains('| a | b |  ')));
    });

    test('prepare is idempotent enough for nested alert re-rendering', () {
      const src = '> [!NOTE]\n> 内容行';
      final once = GfmExtensions.prepare(src, hardenLineBreaks: true);
      final twice = GfmExtensions.prepare(once, hardenLineBreaks: true);
      expect(twice, once);
    });
  });
}
