import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/markdown/rich_markdown.dart';
import 'package:taskflow/presentation/shared/app_markdown_body.dart';

/// Widget tests for the v1.4.21 rich-text Markdown extensions rendered by
/// [AppMarkdownBody]: underline (`++`), highlight (`==`), `<font color>`
/// and `<font size>`.
void main() {
  Future<void> pumpMd(WidgetTester tester, String data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AppMarkdownBody(data: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('parseRichTextColor', () {
    test('parses #RGB, #RRGGBB and named colors', () {
      expect(parseRichTextColor('#F00'), const Color(0xFFFF0000));
      expect(parseRichTextColor('#ff0000'), const Color(0xFFFF0000));
      expect(parseRichTextColor('red'), const Color(0xFFEF4444));
      expect(parseRichTextColor('TEAL'), const Color(0xFF14B8A6));
      expect(parseRichTextColor('not-a-color'), isNull);
    });
  });

  group('AppMarkdownBody rich extensions', () {
    testWidgets('++text++ renders underlined', (tester) async {
      await pumpMd(tester, 'Some ++under++ text');
      final t = tester.widget<Text>(find.text('under'));
      expect(t.style?.decoration, TextDecoration.underline);
    });

    testWidgets('==text== renders on a highlight background', (tester) async {
      await pumpMd(tester, 'A ==hl== word');
      final textFinder = find.text('hl');
      expect(textFinder, findsOneWidget);
      final container = tester.widget<Container>(
        find.ancestor(of: textFinder, matching: find.byType(Container)).first,
      );
      final deco = container.decoration;
      expect(deco, isA<BoxDecoration>());
      expect((deco as BoxDecoration).color, isNotNull);
    });

    testWidgets('<font color> tints the text and tags stay hidden',
        (tester) async {
      await pumpMd(tester, 'Status: <font color="#FF0000">blocked</font>');
      final t = tester.widget<Text>(find.text('blocked'));
      expect(t.style?.color, const Color(0xFFFF0000));
      expect(find.textContaining('<font'), findsNothing);
    });

    testWidgets('<font size> scales the font size', (tester) async {
      await pumpMd(tester, 'Look <font size="2">big</font> text');
      final t = tester.widget<Text>(find.text('big'));
      // Base body text is 15–16px; a 2× factor must clearly exceed it.
      expect(t.style?.fontSize, greaterThanOrEqualTo(24));
    });

    testWidgets('strikethrough still works without InlineHtmlSyntax',
        (tester) async {
      await pumpMd(tester, '~~gone~~');

      bool hasLineThrough(InlineSpan span) {
        if (span is TextSpan) {
          if (span.style?.decoration == TextDecoration.lineThrough &&
              (span.text?.contains('gone') ?? false)) {
            return true;
          }
          for (final child in span.children ?? const <InlineSpan>[]) {
            if (hasLineThrough(child)) return true;
          }
        }
        return false;
      }

      // Selectable paragraphs render as SelectableText, not Text.
      final found = find.byType(SelectableText).evaluate().any((e) {
        final span = (e.widget as SelectableText).textSpan;
        return span != null && hasLineThrough(span);
      });
      expect(found, isTrue,
          reason: '~~gone~~ must render with a line-through decoration');
    });
  });
}
