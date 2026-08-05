import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/presentation/shared/markdown_editor_field.dart';

/// Verifies the Write / Preview Markdown editor introduced for the
/// "input-as-preview" requirement: the user types raw Markdown in Write mode
/// and switches to Preview mode to see it rendered. Since v1.4.77 the
/// preview renders through SelectableMarkdownBody — ONE whole-document
/// SelectableText (multi-line drag-select, Select all, right-click
/// Copy / Copy as Markdown) — with the source text preserved across toggles.
void main() {
  Future<void> pumpEditor(WidgetTester tester, String text) async {
    final controller = TextEditingController(text: text);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownEditorField(controller: controller),
          ),
        ),
      ),
    );
  }

  testWidgets('defaults to Write mode with a TextField', (tester) async {
    await pumpEditor(tester, '# Title');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.text('Write'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('Preview mode renders Markdown instead of raw source',
      (tester) async {
    await pumpEditor(tester, '# Title\n\n**bold** text');

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    // TextField is replaced by ONE whole-document SelectableText
    // (SelectableMarkdownBody contract).
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(MarkdownBody), findsNothing);
    final stFinder = find.byType(SelectableText);
    expect(stFinder, findsOneWidget);

    // The parsed content is present, but the raw Markdown source is NOT
    // shown literally (no '# ' prefix, no '**' markers).
    final st = tester.widget<SelectableText>(stFinder);
    final plain = st.textSpan?.toPlainText() ?? st.data ?? '';
    expect(plain, contains('Title'));
    expect(plain, contains('bold'));
    expect(plain, isNot(contains('**')));
    expect(plain, isNot(contains('# ')));
  });

  testWidgets('empty preview shows a placeholder, not a blank box',
      (tester) async {
    await pumpEditor(tester, '   ');

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsNothing);
    expect(
      find.text('Nothing to preview yet — write some Markdown first.'),
      findsOneWidget,
    );
  });

  testWidgets('source text is preserved when toggling back to Write',
      (tester) async {
    const source = '- item one\n- item two';
    final controller = TextEditingController(text: source);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownEditorField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(controller.text, source);
  });
}
