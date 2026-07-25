import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/markdown/html_export.dart';

/// Regression tests for the Work Log "save as HTML" export pipeline
/// (v1.4.21): the old hand-rolled converter dropped inline formatting
/// inside headings and leaked `"$1"` placeholder artifacts into the
/// exported file.
void main() {
  group('markdownToHtmlExport', () {
    test('inline formatting survives inside headings', () {
      final html = markdownToHtmlExport('## **Bold** title');
      expect(html, contains('<strong>Bold</strong> title'));
      expect(html, contains('<h2'));
    });

    test('"\$1" placeholder artifacts are cleaned from headings', () {
      final html = markdownToHtmlExport('#### \$1. Fix bug\n\n\$2. second');
      expect(html, contains('1. Fix bug'));
      expect(html, isNot(contains('\$1')));
      expect(html, isNot(contains('\$2')));
    });

    test('fenced code blocks become <pre><code>', () {
      final html = markdownToHtmlExport('```\ncode here\n```');
      expect(html, contains('<pre><code>'));
      expect(html, contains('code here'));
    });

    test('task lists render checkboxes', () {
      final html = markdownToHtmlExport('- [ ] todo\n- [x] done');
      expect(html, contains('type="checkbox"'));
      expect(html, contains('todo'));
      expect(html, contains('done'));
    });

    test('strikethrough becomes <del>', () {
      expect(markdownToHtmlExport('~~gone~~'), contains('<del>gone</del>'));
    });

    test('rich-text extensions convert to styled HTML', () {
      final html = markdownToHtmlExport(
          '==mark== ++under++ <font color="#FF0000">red</font> '
          '<font size="1.5">big</font>');
      expect(html, contains('<mark>mark</mark>'));
      expect(html, contains('<u>under</u>'));
      expect(html, contains('<span style="color:#FF0000">red</span>'));
      expect(html, contains('<span style="font-size:1.5em">big</span>'));
    });

    test('numbered lists and horizontal rules still work', () {
      final html = markdownToHtmlExport('1. one\n2. two\n\n---\n\ntail');
      expect(html, contains('<ol>'));
      expect(html, contains('<li>one</li>'));
      expect(html, contains('<hr />'));
    });
  });

  group('wrapHtmlExportPage', () {
    test('produces a standalone dark-themed page with rich-text CSS', () {
      final page = wrapHtmlExportPage('<p>x</p>');
      expect(page, startsWith('<!DOCTYPE html>'));
      expect(page, contains('<p>x</p>'));
      // Styles for every newly supported element are present.
      expect(page, contains('mark{'));
      expect(page, contains('u{'));
      expect(page, contains('pre{'));
      expect(page, contains('blockquote{'));
      expect(page, contains('input[type="checkbox"]'));
    });
  });
}
