// Verification tests for Tab-key behavior inside MarkdownEditorField
// (v1.6.1 contract): with a collapsed caret, Tab inserts TWO SPACES AT
// THE CARET — the content after the cursor shifts right, the content
// before it stays put (user request: not a whole-line indent). With a
// multi-line selection, Tab still (de)indents the whole block and keeps
// it selected.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/presentation/shared/markdown_editor_field.dart';

void main() {
  Future<TextEditingController> pumpEditor(
      WidgetTester tester, String text, int caret) async {
    final controller = TextEditingController(text: text);
    controller.selection = TextSelection.collapsed(offset: caret);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownEditorField(controller: controller),
        ),
      ),
    );
    // Focus the TextField so the Tab key event reaches the editor,
    // WITHOUT moving the caret (showKeyboard keeps the preset selection).
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    return controller;
  }

  testWidgets('Tab at list line start inserts spaces at the caret',
      (tester) async {
    final c = await pumpEditor(tester, '- a\n- b', 4); // start of '- b'
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- a\n  - b');
    expect(c.selection.baseOffset, 6);
  });

  testWidgets('Tab at list line middle inserts spaces AT the caret',
      (tester) async {
    final c = await pumpEditor(tester, '- a\n- b', 6); // before 'b' in '- b'
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- a\n-   b');
    expect(c.selection.baseOffset, 8);
  });

  testWidgets('Tab at list line end appends spaces at the caret',
      (tester) async {
    final c = await pumpEditor(tester, '- a\n- b', 7); // caret at end
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- a\n- b  ');
    expect(c.selection.baseOffset, 9);
  });

  testWidgets('Tab on plain text inserts two spaces at the caret',
      (tester) async {
    final c = await pumpEditor(tester, 'abcd', 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, 'ab  cd');
    expect(c.selection.baseOffset, 4);
  });

  testWidgets('Tab with multi-line selection indents block and keeps it',
      (tester) async {
    final controller = TextEditingController(text: '- a\n- b');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownEditorField(controller: controller),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, '  - a\n  - b');
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, controller.text.length);
  });
}
