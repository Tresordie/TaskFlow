import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      'Col A',
      'a1',
      'b2',
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

    // ── Checkboxes render as [ ] / [x]. ──
    expect(plain, contains('[ ] open task'));
    expect(plain, contains('[x] done task'));

    // ── Table renders as an aligned, boxed monospace grid. ──
    expect(plain, contains('| Col A'));
    expect(plain, contains('a1'));
    expect(plain, contains('b1'));
    expect(plain, contains('a2'));
    expect(plain, contains('b2'));
    expect(plain, contains('+-')); // header rule

    // ── Blockquote gets a gutter. ──
    expect(plain, contains('│ a quoted line'));

    // ── Still exactly ONE SelectableText (whole-Note selection contract). ──
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
