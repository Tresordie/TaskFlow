import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/data/services/report_service.dart';

/// Regression tests for the email-HTML post-processing helpers that turn the
/// shared report Markdown into a Gmail-safe document. These guard the risky
/// regex manipulation: fixed-width colgroups for the 3-column Progress
/// Details tables, and paste-proof inline style injection.
void main() {
  group('alignProgressTables (colgroup injection)', () {
    test('3-column table gets fixed 25%/8%/67% colgroup', () {
      const html = '<table>\n<thead>\n'
          '<tr><th>Item</th><th>Status</th><th>Details</th></tr>\n'
          '</thead>\n<tbody>\n'
          '<tr><td>Task A</td><td>🟩</td><td>• did x</td></tr>\n'
          '</tbody>\n</table>';
      final out = ReportService.alignProgressTablesForTest(html);
      expect(out, contains('<colgroup>'));
      expect(out, contains('width:25%'));
      expect(out, contains('width:8%'));
      expect(out, contains('width:67%'));
      // Colgroup sits right after the opening <table> tag.
      expect(out.indexOf('<colgroup>'), lessThan(out.indexOf('<thead>')));
    });

    test('4-column table is left untouched (no colgroup)', () {
      const html = '<table>\n<thead>\n'
          '<tr><th>Project</th><th>Status</th><th>Progress</th>'
          '<th>Headline</th></tr>\n'
          '</thead>\n</table>';
      final out = ReportService.alignProgressTablesForTest(html);
      expect(out, isNot(contains('<colgroup>')));
    });

    test('each table is handled independently', () {
      const html = '<table><tr><th>A</th><th>B</th><th>C</th></tr></table>'
          '<table><tr><th>W</th><th>X</th><th>Y</th><th>Z</th></tr></table>';
      final out = ReportService.alignProgressTablesForTest(html);
      // Exactly one colgroup (only the 3-column table).
      expect('<colgroup>'.allMatches(out).length, 1);
    });
  });

  group('inlineEmailStyles (paste-proof inline styles)', () {
    test('block tags receive a style attribute', () {
      final out = ReportService.inlineEmailStylesForTest(
          '<h2>Section</h2><p>text</p><table><tr><td>cell</td></tr></table>');
      expect(out, contains('<h2 style="'));
      expect(out, contains('<p style="'));
      expect(out, contains('<table style="'));
      expect(out, contains('<td style="'));
    });

    test('existing style (table alignment) is preserved and merged', () {
      final out = ReportService.inlineEmailStylesForTest(
          '<td style="text-align:center">cell</td>');
      // Original alignment kept…
      expect(out, contains('text-align:center'));
      // …and the email padding added.
      expect(out, contains('padding:10px 14px'));
    });

    test('markdown <hr /> is restyled as a ruled line', () {
      final out = ReportService.inlineEmailStylesForTest('<hr />');
      expect(out, contains('<hr style="'));
      expect(out, contains('border-top:1px solid #E2E8F0'));
    });

    test('list items get font sizing for readability', () {
      final out =
          ReportService.inlineEmailStylesForTest('<ul><li>point</li></ul>');
      expect(out, contains('<ul style="'));
      expect(out, contains('<li style="'));
    });
  });
}
