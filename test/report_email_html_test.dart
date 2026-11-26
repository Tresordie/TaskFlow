import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/data/services/report_service.dart';

/// Regression tests for the email-HTML post-processing helpers that turn the
/// shared report Markdown into a Gmail-safe document. These guard the risky
/// regex manipulation: the per-column wrap policy (long-text columns may
/// break anywhere so narrow screens never overflow; short columns keep words
/// intact) and the paste-proof inline style injection.
void main() {
  group('applyTableColumnPolicy (per-column wrap policy)', () {
    test('long-text columns get overflow-wrap:anywhere on every cell', () {
      const long = 'a very long task title that clearly exceeds thirty '
          'characters in total';
      final html = '<table>\n<tr><th>Item</th><th>OK</th></tr>\n'
          '<tr><td>$long</td><td>yes</td></tr>\n</table>';
      final out = ReportService.applyTableColumnPolicyForTest(html);
      // Header + body cells of the long column (2 cells) carry the policy.
      expect('overflow-wrap:anywhere'.allMatches(out).length, 2);
    });

    test('short columns keep their words intact (no anywhere)', () {
      const html = '<table><tr><th>Project</th><th>Status</th></tr>'
          '<tr><td>Obelisk</td><td>OK</td></tr></table>';
      final out = ReportService.applyTableColumnPolicyForTest(html);
      expect(out, isNot(contains('overflow-wrap:anywhere')));
    });

    test('each table is handled independently', () {
      final html = '<table><tr><th>A</th><th>B</th></tr>'
          '<tr><td>short</td><td>ok</td></tr></table>'
          '<table><tr><th>L</th><th>x</th></tr>'
          '<tr><td>${'v' * 40}</td><td>y</td></tr></table>';
      final out = ReportService.applyTableColumnPolicyForTest(html);
      // The long column's header + body cells (2 cells) carry the policy.
      expect('overflow-wrap:anywhere'.allMatches(out).length, 2);
    });

    test('existing style attributes are merged, not replaced', () {
      final html = '<table><tr><th>H</th></tr>'
          '<tr><td style="padding:1px">${'w' * 40}</td></tr></table>';
      final out = ReportService.applyTableColumnPolicyForTest(html);
      expect(out, contains('style="padding:1px;overflow-wrap:anywhere;"'));
    });
  });

  group('inlineEmailStyles (paste-proof inline styles)', () {
    test('block tags receive a style attribute', () {
      final out = ReportService.inlineEmailStylesForTest(
          '<h2>Section</h2><h4>Task</h4><p>text</p>'
          '<blockquote><p>TL;DR</p></blockquote>'
          '<table><tr><td>cell</td></tr></table>');
      expect(out, contains('<h2 style="'));
      expect(out, contains('<h4 style="'));
      expect(out, contains('<p style="'));
      expect(out, contains('<blockquote style="'));
      expect(out, contains('<table style="'));
      expect(out, contains('<td style="'));
    });

    test('task-header h4 carries the gray bar style', () {
      final out = ReportService.inlineEmailStylesForTest('<h4>x</h4>');
      expect(out, contains('background-color:#F1F5F9'));
      expect(out, contains('border-left:3px solid #94A3B8'));
    });

    test('TL;DR blockquote carries the indigo callout style', () {
      final out =
          ReportService.inlineEmailStylesForTest('<blockquote>b</blockquote>');
      expect(out, contains('border-left:3px solid #6366F1'));
      expect(out, contains('background-color:#EEF2FF'));
    });

    test('table cells keep words intact by default (break-word)', () {
      final out = ReportService.inlineEmailStylesForTest(
          '<table><tr><td>c</td></tr></table>');
      expect(out, contains('overflow-wrap:break-word'));
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
