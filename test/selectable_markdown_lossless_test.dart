import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/app_markdown_body.dart'
    show TaskCheckboxGlyph;
import 'package:taskflow/presentation/shared/selectable_markdown_body.dart';

/// Guards the whole-Note renderer ([SelectableMarkdownBody]) against the
/// "saved Note looks truncated / unlike the Preview" regression.
///
/// The Preview renders through a full `MarkdownBody`; the saved Note renders
/// through [SelectableMarkdownBody] (a single selectable [SelectableText.rich]
/// so cross-block drag-select works in Release/AOT). Because that renderer
/// flattens blocks to text, it must (a) never DROP any content and (b) keep
/// block structure legible — most importantly, nested list items must stay on
/// their own indented lines instead of being glued into one line (which made
/// Notes look dramatically shorter than the Preview).
void main() {
  testWidgets('saved-Note renderer is lossless and keeps list structure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));

    const md = '''# Heading One

Normal paragraph with **bold**, *italic*, ~~strike~~ and `inline code` here.

- bullet one
- bullet two
  - nested bullet 2a
  - nested bullet 2b
    - deep bullet 2b-i
- bullet three

1. first
2. second

- [ ] open task
- [x] done task

> a quoted line

```
void main() {
  print("hello code block");
}
```

| Col A | Col B |
|-------|-------|
| a1    | b1    |
| a2    | b2    |

A line with ++underline++ and ==highlight== and <font color="#FF0000">red</font>.

Vout < 5V and temp -> stable, A & B pass.

[link text](https://example.com) end of doc.''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectableMarkdownBody(data: md, hardenLineBreaks: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final st = tester.widget<SelectableText>(find.byType(SelectableText));
    final plain = st.textSpan?.toPlainText() ?? st.data ?? '';

    // ── Losslessness: every meaningful fragment must survive. ──
    for (final frag in const [
      'Heading One',
      'bold',
      'inline code',
      'bullet one',
      'nested bullet 2a',
      'nested bullet 2b',
      'deep bullet 2b-i',
      'bullet three',
      'first',
      'second',
      'open task',
      'done task',
      'a quoted line',
      'hello code block',
      '}',
      // 'Col A' and the other cells are asserted via finders below — since
      // v1.5.4 the table embeds as a WidgetSpan, so its text leaves the
      // plain-text selection flow (same tier as formulas).
      'underline',
      'highlight',
      'red',
      'Vout < 5V',
      'A & B',
      'link text',
      'end of doc',
    ]) {
      expect(plain, contains(frag), reason: 'content must not be dropped: $frag');
    }

    // ── Structure: nested list items on their own indented lines. ──
    expect(plain, contains('• bullet one'));
    expect(plain, contains('• bullet two'));
    expect(plain, contains('\n    • nested bullet 2a'));
    expect(plain, contains('\n    • nested bullet 2b'));
    expect(plain, contains('\n        • deep bullet 2b-i'));
    expect(plain, contains('1. first'));
    expect(plain, contains('2. second'));

    // ── Checkboxes render as Material icon markers (v1.5.4; previously
    //    literal [ ] / [x] brackets, then faint ☐/☑ glyphs). ──
    expect(plain, contains('\uFFFC open task'));
    expect(plain, contains('\uFFFC done task'));
    expect(plain, isNot(contains('[ ] open task')));
    expect(plain, isNot(contains('[x] done task')));
    final checkboxes = tester
        .widgetList<TaskCheckboxGlyph>(find.byType(TaskCheckboxGlyph))
        .toList();
    expect(checkboxes.map((c) => c.checked).toList(), [false, true]);

    // ── Table embeds as a REAL bordered table (v1.5.4; the v1.5.3 ASCII
    //    grid misaligned on CJK). Cell text lives in widgets now, so it no
    //    longer appears in plain text — assert via finders instead.
    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children.length, 3); // header + 2 data rows
    for (final frag in const ['Col A', 'a1', 'b1', 'a2', 'b2']) {
      expect(find.textContaining(frag), findsOneWidget,
          reason: 'table cell must render: $frag');
    }
    expect(find.byType(Table), findsOneWidget);

    // ── Blockquote gets a gutter. ──
    expect(plain, contains('│ a quoted line'));

    // ── Still exactly ONE SelectableText (whole-Note selection contract). ──
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
