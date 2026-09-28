import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/presentation/calendar/calendar_screen.dart';

/// v1.12.31: the calendar day tile has a fixed height (grid childAspectRatio)
/// and the grid can't grow, so a busy day used to paint its 3rd due-task pill
/// (and the "+N more" line) OUTSIDE the tile. The fix shows only as many whole
/// pills as fit the space under the day-number row. calendarPillsThatFit is the
/// pure core of that logic — these lock its contract so a future tweak can't
/// silently reintroduce the overflow.
void main() {
  group('calendarPillsThatFit', () {
    test('never claims more pills than exist, and caps at 3', () {
      for (final total in [0, 1, 2, 3, 5, 12]) {
        for (final avail in [0.0, 8.0, 16.0, 40.0, 48.0, 80.0, 200.0]) {
          final shown = calendarPillsThatFit(avail, total);
          expect(shown, inInclusiveRange(0, 3),
              reason: 'shown must stay in 0..3 (avail=$avail total=$total)');
          expect(shown, lessThanOrEqualTo(total),
              reason: 'shown must not exceed total (avail=$avail total=$total)');
        }
      }
    });

    test('zero or negative height shows no pills', () {
      expect(calendarPillsThatFit(0, 5), 0);
      expect(calendarPillsThatFit(-10, 5), 0);
    });

    test('plenty of height shows the full 3-pill cap', () {
      expect(calendarPillsThatFit(200, 5), 3);
      expect(calendarPillsThatFit(200, 2), 2); // limited by total, not height
    });

    test('reserves a line for "+N more" when not everything fits', () {
      // A 3-pill-tall box that holds 5 tasks must drop one pill so the
      // "+2 more" line has room (3*16=48 > 40, but 2*16+13=45 > 40 too, so
      // only 1 pill + more fits at 40px).
      expect(calendarPillsThatFit(40, 5), 1);
      // At 61px: 3 pills = 48 fits, but 5 tasks don't, so reserve the more
      // line → 3*16+13=61 fits exactly → still 3.
      expect(calendarPillsThatFit(61, 5), 3);
    });

    test('all-tasks-fit case shows every pill with no "more" reservation',
        () {
      // 2 tasks in a 3-pill box: both shown, no indicator needed.
      expect(calendarPillsThatFit(48, 2), 2);
      expect(calendarPillsThatFit(48, 3), 3);
    });
  });
}
