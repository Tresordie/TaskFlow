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

/// Timeline page date navigation (persists across page switches).
final timelineDateNavProvider = StateProvider<DateNavState>(
  (ref) => DateNavState(selectedDate: DateTime.now()),
);

/// Calendar page date navigation (persists across page switches).
final calendarDateNavProvider = StateProvider<DateNavState>(
  (ref) => DateNavState(selectedDate: DateTime.now()),
);
