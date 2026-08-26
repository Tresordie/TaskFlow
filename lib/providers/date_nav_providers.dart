import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Date-navigation view state for a page (selected day + optional range).
///
/// Lifted into a Riverpod provider so the selection survives route
/// changes: navigating to another page and back no longer resets the
/// chosen date / range — it persists until the user changes it.
class DateNavState {
  final DateTime selectedDate;
  final DateTimeRange? dateRange;

  const DateNavState({required this.selectedDate, this.dateRange});

  bool get rangeMode => dateRange != null;

  DateNavState copyWith({
    DateTime? selectedDate,
    DateTimeRange? dateRange,
    bool clearRange = false,
  }) {
    return DateNavState(
      selectedDate: selectedDate ?? this.selectedDate,
      dateRange: clearRange ? null : (dateRange ?? this.dateRange),
    );
  }
}

/// The default view range: the LAST 30 DAYS ending today (v1.6.1 —
/// Timeline and Calendar open on the recent month instead of a week).
DateTimeRange defaultMonthRange() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTimeRange(
    start: today.subtract(const Duration(days: 29)),
    end: today,
  );
}

/// Timeline page date navigation (persists across page switches).
final timelineDateNavProvider = StateProvider<DateNavState>(
  (ref) => DateNavState(
    selectedDate: DateTime.now(),
    dateRange: defaultMonthRange(),
  ),
);

/// Calendar page date navigation (persists across page switches).
final calendarDateNavProvider = StateProvider<DateNavState>(
  (ref) => DateNavState(
    selectedDate: DateTime.now(),
    dateRange: defaultMonthRange(),
  ),
);
