import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/markdown_input.dart';

/// Regression contracts for Tab / Shift+Tab indentation (v1.5.10 user
/// report: "Tab only indents the content after the cursor"). The indent
/// must ALWAYS apply at the LINE START — i.e. the whole line shifts no
/// matter where the caret sits inside it — and a multi-line selection
/// indents every touched line from its start.
void main() {
  TextEditingController controllerWith(
      String text, int caret, [int? extent]) {
    final c = TextEditingController(text: text);
    c.value = TextEditingValue(
      text: text,
      selection: extent == null
          ? TextSelection.collapsed(offset: caret)
          : TextSelection(baseOffset: caret, extentOffset: extent),
    );
    return c;
  }

  group('MarkdownInput.indent — whole-line contract', () {
    test('caret at line start indents the whole line', () {
      final c = controllerWith('第一行', 0);
      MarkdownInput.indent(c);
      expect(c.text, '  第一行');
    });

    test('caret MID-LINE still indents from the line start (whole line)',
        () {
      final c = controllerWith('第一行', 2); // after "第一"
      MarkdownInput.indent(c);
      expect(c.text, '  第一行');
      // The caret follows its text (+2 inserted before it).
      expect(c.selection.baseOffset, 4);
    });

    test('caret at line end indents the whole line', () {
      final c = controllerWith('第一行', 3);
      MarkdownInput.indent(c);
      expect(c.text, '  第一行');
    });

    test('caret mid-line on line 2 indents ONLY line 2, from its start', () {
      final c = controllerWith('第一行\n第二行', 6); // after "第二"
      MarkdownInput.indent(c);
      expect(c.text, '第一行\n  第二行');
    });

    test('multi-line selection indents EVERY touched line from its start',
        () {
      // 'aaa\nbbb\nccc' — offsets: a=0..2, \n=3, b=4..6, \n=7, c=8..10.
      // Selection from mid line1 (1) into mid line3 (9) touches all three.
      final c = controllerWith('aaa\nbbb\nccc', 1, 9);
      MarkdownInput.indent(c);
      expect(c.text, '  aaa\n  bbb\n  ccc');
    });

    test('shift+tab (outdent) removes leading spaces from the caret line',
        () {
      final c = controllerWith('  缩进行', 4);
      MarkdownInput.outdent(c);
      expect(c.text, '缩进行');
    });
  });
}
