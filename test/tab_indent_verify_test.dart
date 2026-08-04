// Verification tests for Tab-key behavior inside MarkdownEditorField:
// Tab on a list-item line nests the whole line (workreport.html "list
// indent" effect); Tab on plain text inserts two spaces at the caret;
// multi-line selection (de)indents the block and keeps it selected.
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

  testWidgets('Tab at list line start nests the line', (tester) async {
    final c = await pumpEditor(tester, '- a\n- b', 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- a\n  - b');
    expect(c.selection.baseOffset, 6);
  });

  testWidgets('Tab at list line middle nests the whole line', (tester) async {
    final c = await pumpEditor(tester, '- a\n- b', 6); // caret inside '- b'
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- a\n  - b');
    expect(c.selection.baseOffset, 8);
  });

  testWidgets('Tab at list line end nests the whole line', (tester) async {
    final c = await pumpEditor(tester, '- a\n- b', 7); // caret at end
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- a\n  - b');
    expect(c.selection.baseOffset, 9);
  });

  testWidgets('Tab on plain text indents the whole line at its start',
      (tester) async {
    final c = await pumpEditor(tester, 'abcd', 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '  abcd');
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
