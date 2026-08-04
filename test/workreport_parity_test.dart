// End-to-end verification of the user-reported scenario:
// numbered list 1-4 followed by a Tab-indented `- sub` under item 4 must
// render NESTED (visibly indented beneath item 4) — matching
// workreport.html — in BOTH render paths:
//   1. AppMarkdownBody  (input Preview)
//   2. SelectableMarkdownBody (saved records / notes list)
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/presentation/shared/app_markdown_body.dart';
import 'package:taskflow/presentation/shared/selectable_markdown_body.dart';

/// The user's exact content shape: numbered items, item 4 ends with a
/// colon, and a Tab-indented (2 spaces) bullet follows it.
const String _kUserMd =
    '1. Voc: A点电流\n'
    '2. Isc: B点电流\n'
    '3. Voc x Isc: C点\n'
    '4. 我们已经要求Foxlink IQC需要搭建EL测试，我比较担心的问题是:\n'
    '  - 来料EL如果存在Cell Crack, 供应商是否会吸收或者做RMA';

/// x of the first VISIBLE glyph (skipping spaces/NBSP) inside a
/// RenderParagraph found under [f].
double glyphX(WidgetTester tester, Finder f) {
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

void main() {
  testWidgets('Preview (AppMarkdownBody): sub-item nests under item 4',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppMarkdownBody(data: _kUserMd, hardenLineBreaks: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final item1X = glyphX(tester, find.textContaining('Voc'));
    final item4X = glyphX(tester, find.textContaining('Foxlink'));
    final subX = glyphX(tester, find.textContaining('Cell Crack'));
    debugPrint('PREVIEW: item1=$item1X item4=$item4X sub=$subX');

    // Item texts align in the number column…
    expect((item4X - item1X).abs(), lessThan(4));
    // …and the Tab-indented bullet sits clearly to their right (nested).
    expect(subX - item1X, greaterThan(20),
        reason: 'sub-item must be visibly nested under item 4');
  });

  testWidgets('Saved record (SelectableMarkdownBody): sub-item nests',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child:
                SelectableMarkdownBody(data: _kUserMd, hardenLineBreaks: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // SelectableMarkdownBody flattens blocks into ONE SelectableText; the
    // nested sub-item must live on its own line, indented with spaces
    // relative to the parent item text.
    final st = tester.widget<SelectableText>(find.byType(SelectableText));
    final plain = st.textSpan?.toPlainText() ?? st.data ?? '';

    expect(plain, contains('1. Voc'));
    expect(plain, contains('4. '));
    // The sub-item keeps its nesting indent on its own line (lossless +
    // structure preserved, matching the Preview hierarchy).
    expect(RegExp(r'\n +• 来料EL').hasMatch(plain), isTrue,
        reason: 'sub-item must be on its own indented line: $plain');
    debugPrint('RECORD plain excerpt around sub-item: '
        '${plain.substring(plain.indexOf('4. '))}');
  });
}
