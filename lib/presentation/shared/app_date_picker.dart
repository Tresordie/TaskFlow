import 'package:flutter/material.dart';

/// Range selection for Timeline, Calendar and the Reports Custom range.
///
/// v1.6.5: the user asked for ONE page for the whole range — the v1.6.4
/// two-step flow was two dialogs. This is a custom single-page range
/// picker that reuses the SAME calendar grid as the approved Daily/Weekly
/// popup ([CalendarDatePicker] — identical visuals, inheriting the app
/// ColorScheme automatically):
///  - tap a day to set the START date;
///  - tap again to set the END date (a day before the start restarts the
///    range there; tapping once both ends exist starts a fresh selection);
///  - OK confirms once both ends exist (same-day ranges work by tapping
///    the day twice); Cancel aborts and returns null.
///
/// The public API is unchanged, so the three call sites need no changes.
/// All copy comes from [MaterialLocalizations].
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _RangePickerDialog(
      firstDate: firstDate,
      lastDate: lastDate,
      initialRange: initialDateRange,
    ),
  );
}

class _RangePickerDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;

  const _RangePickerDialog({
    required this.firstDate,
    required this.lastDate,
    this.initialRange,
  });

  @override
  State<_RangePickerDialog> createState() => _RangePickerDialogState();
}

class _RangePickerDialogState extends State<_RangePickerDialog> {
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialRange?.start;
    _end = widget.initialRange?.end;
  }

  /// The month the calendar opens on: the existing range start, clamped
  /// into [firstDate]..[lastDate].
  DateTime get _anchor {
    final today = DateUtils.dateOnly(DateTime.now());
    final candidate = _start ?? today;
    if (candidate.isBefore(widget.firstDate)) return widget.firstDate;
    if (candidate.isAfter(widget.lastDate)) return widget.lastDate;
    return candidate;
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      final d = DateUtils.dateOnly(day);
      if (_start == null) {
        _start = d;
      } else if (_end == null) {
        if (d.isBefore(_start!)) {
          // Tapping before the start restarts the range at that day.
          _start = d;
        } else {
          _end = d;
        }
      } else {
        // Both ends set — tapping starts a fresh selection.
        _start = d;
        _end = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    // Short numeric format keeps the state chips compact (the medium
    // format carries the weekday and overflows the 400px dialog).
    String fmt(DateTime d) => localizations.formatShortDate(d);

    final headline = _start == null
        ? localizations.dateRangePickerHelpText
        : _end == null
            ? '${fmt(_start!)} – …'
            : '${fmt(_start!)} – ${fmt(_end!)}';

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 8,
      shadowColor: scheme.primary.withOpacity(0.10),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 400,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outline.withOpacity(0.8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header: tinted, live range readout + which end is picked.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              color: scheme.primary.withOpacity(isDark ? 0.14 : 0.10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.dateRangePickerHelpText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // FittedBox keeps the headline on one line at any
                  // width / font metrics (scale-down, never overflow).
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      headline,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Wrap (not Row) so the state chips flow to a second line
                  // instead of overflowing on narrow layouts / wide fonts.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _EndChip(
                        label: _start == null
                            ? localizations.dateRangeStartLabel
                            : '${localizations.dateRangeStartLabel} · ${fmt(_start!)}',
                        active: _end == null,
                      ),
                      const SizedBox(width: 8),
                      _EndChip(
                        label: _end == null
                            ? localizations.dateRangeEndLabel
                            : '${localizations.dateRangeEndLabel} · ${fmt(_end!)}',
                        active: _end != null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── The same calendar grid as the Daily/Weekly popup.
            CalendarDatePicker(
              initialDate: _anchor,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              currentDate: DateUtils.dateOnly(DateTime.now()),
              onDateChanged: _onDaySelected,
            ),
            // ── Buttons: Cancel outlined + OK filled primary (app rule).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface.withOpacity(0.7),
                      side: BorderSide(color: scheme.outline.withOpacity(0.8)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(localizations.cancelButtonLabel),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _end == null
                        ? null
                        : () => Navigator.of(context)
                            .pop(DateTimeRange(start: _start!, end: _end!)),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(localizations.okButtonLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill showing which end of the range is currently being picked.
class _EndChip extends StatelessWidget {
  final String label;
  final bool active;

  const _EndChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? scheme.primary.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? scheme.primary.withOpacity(0.5)
              : scheme.primary.withOpacity(0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}
