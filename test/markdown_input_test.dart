import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/markdown_input.dart';

/// Regression contracts for Tab / Shift+Tab indentation (v1.6.1 user
/// request: "press Tab at the cursor position — the content AFTER the
/// cursor indents by two spaces, not the whole line"). With a collapsed
/// caret, Tab must insert TWO SPACES AT THE CARET, so only the text after
/// the cursor shifts right and everything before it stays put. A
/// multi-line selection still indents every touched line from its start
/// (block indent), and Shift+Tab removes the line's leading indentation.
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

  group('MarkdownInput.indent — caret-insert contract', () {
    test('caret at line start inserts two spaces there', () {
      final c = controllerWith('第一行', 0);
      MarkdownInput.indent(c);
      expect(c.text, '  第一行');
      expect(c.selection.baseOffset, 2);
    });

    test('caret MID-LINE inserts two spaces AT the caret (not the line)',
        () {
      final c = controllerWith('第一行', 2); // after "第一"
      MarkdownInput.indent(c);
      // The text BEFORE the caret ("第一") stays put.
      expect(c.text, '第一  行');
      // The caret moves past the inserted spaces.
      expect(c.selection.baseOffset, 4);
    });

    test('caret at line end appends two spaces there', () {
      final c = controllerWith('第一行', 3);
      MarkdownInput.indent(c);
      expect(c.text, '第一行  ');
      expect(c.selection.baseOffset, 5);
    });

    test('caret mid-line on line 2 inserts spaces on line 2 only', () {
      final c = controllerWith('第一行\n第二行', 6); // after "第二"
      MarkdownInput.indent(c);
      expect(c.text, '第一行\n第二  行');
      expect(c.selection.baseOffset, 8);
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
