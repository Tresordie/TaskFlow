import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/markdown/html_sanitize.dart';

void main() {
  group('sanitizeHtmlInMarkdown', () {
    test('plain markdown passes through untouched', () {
      const md = '## Title\n\n- item 1\n- **bold** item 2';
      expect(sanitizeHtmlInMarkdown(md), md);
    });

    test('strips colgroup blocks', () {
      final out = sanitizeHtmlInMarkdown(
          'before\n<colgroup><col style="width:25%"></colgroup>\nafter');
      expect(out.contains('colgroup'), isFalse);
      expect(out.contains('before'), isTrue);
      expect(out.contains('after'), isTrue);
    });

    test('converts HTML table to markdown pipe table', () {
      const html = '''
<table>
<tr><th>Item</th><th>Status</th><th>Details</th></tr>
<tr><td>Task A</td><td>🟩</td><td>Done<br>Shipped</td></tr>
</table>''';
      final out = sanitizeHtmlInMarkdown(html);
      expect(out, contains('| Item | Status | Details |'));
      expect(out, contains('| --- | --- | --- |'));
      expect(out, contains('| Task A | 🟩 | Done • Shipped |'));
      expect(out.contains('<table>'), isFalse);
    });

    test('converts inline emphasis tags', () {
      final out = sanitizeHtmlInMarkdown('a <b>bold</b> <i>it</i> <u>u</u>');
      expect(out, 'a **bold** *it* ++u++');
    });

    test('br outside tables becomes newline', () {
      expect(sanitizeHtmlInMarkdown('a<br>b'), 'a\nb');
      expect(sanitizeHtmlInMarkdown('a<br/>b'), 'a\nb');
    });

    test('preserves <font> rich-text tags', () {
      const md = '<font color="#E53935">red</font> text';
      expect(sanitizeHtmlInMarkdown(md), md);
    });

    test('converts <a href> links', () {
      final out = sanitizeHtmlInMarkdown('<a href="http://x.com">site</a>');
      expect(out, '[site](http://x.com)');
    });

    test('idempotent', () {
      const html =
          '<table><tr><td>a<br>b</td></tr></table>\n<b>x</b><br>y';
      final once = sanitizeHtmlInMarkdown(html);
      final twice = sanitizeHtmlInMarkdown(once);
      expect(twice, once);
    });
  });
}
