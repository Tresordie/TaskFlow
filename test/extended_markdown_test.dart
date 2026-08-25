import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/markdown/rich_markdown.dart';
import 'package:taskflow/presentation/shared/app_markdown_body.dart';
import 'package:taskflow/presentation/shared/markdown_input.dart';
import 'package:taskflow/presentation/shared/selectable_markdown_body.dart';

/// Contract tests for the v1.5.0 extended-Markdown capabilities:
///  - footnotes ([^1] reference + trailing definitions) in BOTH renderers;
///  - superscript ^x^ / subscript ~x~ (smaller inline text, selectable);
///  - rich styles (==highlight== / ++underline++ / <font>) no longer lost in
///    SelectableMarkdownBody;
///  - the lossless select/copy contract: every source character survives
///    flattening into the single TextSpan tree.
void main() {
  const base = TextStyle(fontSize: 14, color: Color(0xFF111111));

  /// Collects every TextSpan in [span]'s tree (depth-first).
  List<TextSpan> collect(InlineSpan span) {
    final out = <TextSpan>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        out.add(s);
        for (final c in s.children ?? const <InlineSpan>[]) {
          walk(c);
        }
      }
    }

    walk(span);
    return out;
  }

  Future<TextSpan> pumpSelectable(WidgetTester tester, String data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectableMarkdownBody(data: data, baseStyle: base),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final st = tester.widget<SelectableText>(find.byType(SelectableText));
    return st.textSpan ?? TextSpan(text: st.data ?? '');
  }

  Future<void> pumpApp(WidgetTester tester, String data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AppMarkdownBody(data: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SelectableMarkdownBody footnotes', () {
    testWidgets('reference renders as bracketed marker, definitions as notes',
        (tester) async {
      final span = await pumpSelectable(
          tester, 'Claim[^1] and more.\n\n[^1]: The note text.');
      final plain = span.toPlainText();
      expect(plain, contains('[1]'));
      expect(plain, contains('1. The note text.'));
      // Nothing of the source is silently dropped.
      expect(plain, contains('Claim'));
      expect(plain, contains('and more.'));
    });

    testWidgets('undefined reference stays visible as literal text',
        (tester) async {
      final span = await pumpSelectable(tester, 'Only a ref[^42] here.');
      // No definition exists: the parser leaves the marker untouched —
      // the lossless contract demands it remains visible.
      expect(span.toPlainText(), contains('[^42]'));
    });
  });

  group('SelectableMarkdownBody superscript / subscript', () {
    testWidgets('^x^ renders as smaller selectable text', (tester) async {
      final span =
          await pumpSelectable(tester, 'Area 100^m2^ measured.');
      final spans = collect(span);
      final sup = spans.where((s) => s.text == 'm2').toList();
      expect(sup, isNotEmpty, reason: 'superscript content must survive');
      expect(sup.first.style?.fontSize, 14 * 0.7);
    });

    testWidgets('~x~ renders as smaller text without breaking ~~strike~~',
        (tester) async {
      final span = await pumpSelectable(
          tester, 'H~2~O and ~~gone~~ kept.');
      final spans = collect(span);
      final sub = spans.where((s) => s.text == '2').toList();
      expect(sub, isNotEmpty);
      expect(sub.first.style?.fontSize, 14 * 0.7);
      // Strikethrough still wins for the double tilde.
      final del = spans.where((s) =>
          (s.style?.decoration == TextDecoration.lineThrough) ||
          (s.toPlainText() == 'gone'));
      expect(del, isNotEmpty);
      expect(span.toPlainText(), isNot(contains('~gone~')));
    });
  });

  group('SelectableMarkdownBody rich styles (v1.5.0 fix)', () {
    testWidgets('==highlight== keeps a background color', (tester) async {
      final span = await pumpSelectable(tester, 'A ==hot== item.');
      final hl = collect(span).where((s) => s.text == 'hot').toList();
      expect(hl, isNotEmpty);
      expect(hl.first.style?.backgroundColor, isNotNull);
    });

    testWidgets('++underline++ keeps the underline decoration',
        (tester) async {
      final span = await pumpSelectable(tester, 'An ++u++ word.');
      final u = collect(span).where((s) => s.text == 'u').toList();
      expect(u, isNotEmpty);
      expect(u.first.style?.decoration, TextDecoration.underline);
    });

    testWidgets('<font color> applies the tint instead of dropping it',
        (tester) async {
      final span = await pumpSelectable(
          tester, 'Tag: <font color="#FF0000">red</font>');
      final r = collect(span).where((s) => s.text == 'red').toList();
      expect(r, isNotEmpty);
      expect(r.first.style?.color, const Color(0xFFFF0000));
    });
  });

  group('AppMarkdownBody extended syntax', () {
    testWidgets('footnote definitions render as an appendix', (tester) async {
      await pumpApp(tester, 'Body[^1].\n\n[^1]: Appendix note.');
      expect(find.textContaining('Appendix note.'), findsOneWidget);
      // The raw definition prefix never leaks into the rendered output.
      expect(find.textContaining('[^1]:'), findsNothing);
    });

    testWidgets('^sup^ renders at reduced size', (tester) async {
      await pumpApp(tester, 'x^sup^ y');
      final t = tester.widget<Text>(find.text('sup'));
      expect(t.style?.fontSize, lessThan(14));
    });
  });

  group('MarkdownInput.insertFootnote', () {
    test('inserts [^1] at the caret and appends the definition', () {
      final c = TextEditingController(text: 'Start end');
      c.selection = const TextSelection.collapsed(offset: 5);
      MarkdownInput.insertFootnote(c);
      expect(c.text, startsWith('Start[^1] end'));
      expect(c.text, endsWith('[^1]: '));
      expect(c.text, contains('\n\n[^1]: '));
      // Caret lands inside the definition, ready for typing.
      expect(c.selection.baseOffset, c.text.length);
    });

    test('numbers up past already-used definitions', () {
      final c = TextEditingController(text: 'A[^1] b.\n\n[^1]: First.');
      c.selection = const TextSelection.collapsed(offset: 1);
      MarkdownInput.insertFootnote(c);
      expect(c.text, contains('[^2]'));
      expect(c.text, endsWith('[^2]: '));
    });
  });

  group('syntax non-collision guards', () {
    test('superscript/subscript regexes never eat math dollars or spaces',
        () {
      // The sup/sub patterns exclude whitespace, carets, tildes and $,
      // so LaTeX `$...$` and code-style text stay untouched.
      final sup = SuperscriptSyntax();
      final sub = SubscriptSyntax();
      expect(sup.pattern.hasMatch(r'$x$'), isFalse);
      expect(sub.pattern.hasMatch(r'$x$'), isFalse);
      expect(sup.pattern.hasMatch('a ^b c^ d'), isFalse);
    });
  });
}
