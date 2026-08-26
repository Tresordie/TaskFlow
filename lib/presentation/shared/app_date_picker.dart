import 'package:flutter/material.dart';

/// Range selection for Timeline, Calendar and the Reports Custom range.
///
/// v1.6.4: the Material range picker (`showDateRangePicker`) was rejected
/// by the user as ugly (its fullscreen-style calendar layout with a
/// start/end header bar; see HANDOFF pitfall 8.26 for the sizing saga).
/// The user asked for the SAME popup the Reports Daily/Weekly mode uses —
/// the compact single-date `showDatePicker` dialog, which inherits the
/// app's ColorScheme automatically.
///
/// This wrapper therefore implements the range as a two-step flow with
/// that exact popup: pick the START date, then the END date (constrained
/// to be on/after the start). Cancelling either step aborts the whole
/// selection and returns null. The public API is unchanged, so the three
/// call sites need no modifications.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  final localizations = MaterialLocalizations.of(context);

  // v1.6.4: fully localized copy (no hardcoded strings) — the app ships
  // DefaultMaterialLocalizations today (English, matching the app's UI);
  // the labels follow the locale automatically if flutter_localizations
  // is ever added.
  return _pickRangeWith(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialStart: initialDateRange?.start,
    initialEnd: initialDateRange?.end,
    startHelpText: localizations.dateRangeStartLabel,
    endHelpText: localizations.dateRangeEndLabel,
    cancelText: localizations.cancelButtonLabel,
    confirmText: localizations.okButtonLabel,
  );
}

/// The two-step start→end flow, kept separate so the logic is unit-testable
/// without mounting the full app theme.
Future<DateTimeRange?> _pickRangeWith({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  required String startHelpText,
  required String endHelpText,
  required String cancelText,
  required String confirmText,
  DateTime? initialStart,
  DateTime? initialEnd,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Step 1 — start date. Default to the previous selection's start, or a
  // 7-day-back window when none is given.
  final startInitial = initialStart ?? today.subtract(const Duration(days: 7));
  final start = await showDatePicker(
    context: context,
    initialDate: startInitial,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: startHelpText,
    cancelText: cancelText,
    confirmText: confirmText,
  );
  if (start == null) return null;

  // Step 2 — end date, constrained to be on/after the chosen start.
  final endInitial = (initialEnd != null && !initialEnd.isBefore(start))
      ? initialEnd
      : start;
  final end = await showDatePicker(
    context: context,
    initialDate: endInitial,
    firstDate: start,
    lastDate: lastDate,
    helpText: endHelpText,
    cancelText: cancelText,
    confirmText: confirmText,
  );
  if (end == null) return null;

  return DateTimeRange(start: start, end: end);
}
