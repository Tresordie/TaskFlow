// Renders nested lists through AppMarkdownBody and measures the actual
// on-screen x-offset of the bullet glyphs, to verify that Tab-indented
// (`  - item`) list items really render with a visible nested indentation
// (same visual language as workreport.html's 1.6em padding).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:taskflow/presentation/shared/app_markdown_body.dart';

void main() {
  Future<Map<String, double>> bulletX(WidgetTester tester, String md,
      {MarkdownStyleSheet? styleSheet}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMarkdownBody(data: md, styleSheet: styleSheet),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Every bullet is a RichText whose plain text is '•'.
    final finds = find.text('•');
    final xs = <double>[];
    for (var i = 0; i < finds.evaluate().length; i++) {
      final box = tester.renderObject<RenderBox>(
          find.descendant(of: finds.at(i), matching: find.byType(RichText)).first);
      xs.add(box.localToGlobal(Offset.zero).dx);
    }
    return {for (var i = 0; i < xs.length; i++) 'bullet$i': xs[i]};
  }

  testWidgets('flat list: all bullets share the same x', (tester) async {
    final xs = await bulletX(tester, '- a\n- b');
    debugPrint('FLAT bullets: $xs');
    expect(xs.length, 2);
    expect((xs['bullet1']! - xs['bullet0']!).abs(), lessThan(1.0));
  });

  testWidgets('nested list: second bullet is visibly indented', (tester) async {
    final xs = await bulletX(tester, '- a\n  - b');
    debugPrint('NESTED bullets: $xs');
    expect(xs.length, 2);
    final dx = xs['bullet1']! - xs['bullet0']!;
    debugPrint('NESTED dx = $dx');
    expect(dx, greaterThan(10), reason: 'nested item must indent visibly');
  });

  testWidgets('nested list with app listIndent=26 indents further',
      (tester) async {
    final sheet = MarkdownStyleSheet(listIndent: 26);
    final xs = await bulletX(tester, '- a\n  - b', styleSheet: sheet);
    debugPrint('NESTED26 bullets: $xs');
    expect(xs.length, 2);
    final dx = xs['bullet1']! - xs['bullet0']!;
    debugPrint('NESTED26 dx = $dx');
    expect(dx, greaterThan(20));
  });

  testWidgets(
      'indented paragraph line (Tab) keeps its indent in the preview',
      (tester) async {
    // User scenario: a Tab-indented bullet line (literal U+2022). Without
    // NBSP preservation CommonMark strips the leading spaces and the
    // preview shows NO indent.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMarkdownBody(
            data: 'parent line\n\n  \u2022 child line',
            hardenLineBreaks: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double firstVisibleGlyphX(Finder f) {
      final para = tester.renderObject<RenderParagraph>(
          find.descendant(of: f, matching: find.byType(RichText)).first);
      final text = para.text.toPlainText();
      // Skip leading NBSP/space so we measure the first VISIBLE char, whose
      // x reflects the indentation (the NBSP boxes themselves start at x=0).
      var i = 0;
      while (i < text.length && (text[i] == '\u00a0' || text[i] == ' ')) {
        i++;
      }
      final boxes = para.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1));
      final origin = para.localToGlobal(Offset.zero).dx;
      return origin + (boxes.isEmpty ? 0 : boxes.first.left);
    }

    final parentX = firstVisibleGlyphX(find.textContaining('parent line'));
    final childX = firstVisibleGlyphX(find.textContaining('child line'));
    final dx = childX - parentX;
    debugPrint('INDENTED-PARA glyph dx = $dx');
    expect(dx, greaterThan(8),
        reason: 'Tab-indented line must visibly indent in preview');
  });

  testWidgets(
      'Tab-indented sub-item under a numbered item renders NESTED '
      '(workreport parity)', (tester) async {
    // User scenario: numbered items 1-4, then a Tab-indented `- sub` under
    // item 4. It must render nested beneath item 4's text — NOT flush with
    // the numbers like a top-level sibling list.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMarkdownBody(
            data: '1. alpha\n2. beta\n4. parent\n  - sub item',
            hardenLineBreaks: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double glyphX(Finder f) {
      final para = tester.renderObject<RenderParagraph>(
          find.descendant(of: f, matching: find.byType(RichText)).first);
      final text = para.text.toPlainText();
      var i = 0;
      while (i < text.length && (text[i] == '\u00a0' || text[i] == ' ')) {
        i++;
      }
      final boxes = para.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1));
      return para.localToGlobal(Offset.zero).dx +
          (boxes.isEmpty ? 0 : boxes.first.left);
    }

    // The number '1.' text and the nested bullet '•' are separate spans in
    // flutter_markdown's ordered/unordered rows.
    final numberX = glyphX(find.textContaining('alpha'));
    final parentX = glyphX(find.textContaining('parent'));
    final subX = glyphX(find.textContaining('sub item'));
    debugPrint('NUMBERED-NEST: parent=$parentX sub=$subX anchor=$numberX');
    // The sub-item text starts clearly to the right of the parent number
    // column (it is nested inside item 4).
    expect(subX, greaterThan(numberX + 20),
        reason: 'sub-item must be visibly nested under item 4');
    expect(subX, greaterThan(parentX),
        reason: 'sub-item must sit right of the parent item content start');
  });
}
