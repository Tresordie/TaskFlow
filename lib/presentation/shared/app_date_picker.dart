import 'package:flutter/material.dart';

/// A polished wrapper around [showDateRangePicker] used by Timeline,
/// Calendar and the Reports Custom range (v1.6.0): rounded floating
/// dialog, tinted header, primary-accent selection and hover highlights —
/// replacing the stock flat Material look with the app's visual language.
///
/// Sizing history:
/// - v1.6.1: Material's range picker sizes its dialog to
///   `MediaQuery.sizeOf` — the FULL WINDOW — with zero insets (huge blank
///   side margins on desktop, user report). The builder feeds the picker a
///   compact MediaQuery size override instead.
/// - v1.6.2: 420×520 felt too small (user report) → FittedBox 1.5×
///   scale-up to a 660×690 visual popup.
/// - v1.6.3: 660×690 felt too big and the 1.5× scaling made strokes and
///   text chunky (user report) → the picker is laid out at the SDK's
///   portrait month-grid width cap **480×500** (ZERO side margins) and
///   scaled just **1.1×** into a **528×550** visual popup: near-native
///   rendering, no blank margins, and a full 6-row month (484 layout px)
///   fits without scrolling.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final scheme = theme.colorScheme;
  final localizations = MaterialLocalizations.of(context);

  // Layout size fed to the picker. Width = the SDK's portrait month-grid
  // cap (480) so the grid fills the dialog edge-to-edge with no side
  // gutter; height 500 covers header (120) + weekday row (42) + a 6-row
  // month (322) = 484. The aspect ratios match, so FittedBox.contain
  // scales exactly 1.1× and fills the outer box.
  const pickerSize = Size(480, 500);
  const pickerVisualSize = Size(528, 550);

  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    // v1.6.3: fully localized copy — no hardcoded strings. The app ships
    // DefaultMaterialLocalizations today (English, matching the app's UI);
    // the labels follow the locale automatically if flutter_localizations
    // is ever added.
    helpText: localizations.dateRangePickerHelpText,
    cancelText: localizations.cancelButtonLabel,
    confirmText: localizations.okButtonLabel,
    saveText: localizations.saveButtonLabel,
    fieldStartLabelText: localizations.dateRangeStartLabel,
    fieldEndLabelText: localizations.dateRangeEndLabel,
    builder: (context, child) {
      final pickerTheme = theme.copyWith(
        colorScheme: scheme.copyWith(
          onPrimary: isDark ? Color(0xFF10202A) : Colors.white,
        ),
        datePickerTheme: DatePickerThemeData(
          // Card-aligned chrome (v1.6.3): the shared card recipe from
          // app_theme.dart — palette card color, border 80% outline,
          // radius 18, soft primary-tinted shadow (flat in dark themes).
          backgroundColor: theme.cardTheme.color ?? scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: isDark ? 0 : 8,
          shadowColor: scheme.primary.withOpacity(0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outline.withOpacity(0.8)),
          ),
          // Range-picker specific slots — the calendar mode reads THESE
          // (not the plain fields above), so they must be set explicitly
          // for the themed look to actually apply.
          rangePickerShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outline.withOpacity(0.8)),
          ),
          rangePickerBackgroundColor: theme.cardTheme.color ?? scheme.surface,
          rangePickerSurfaceTintColor: Colors.transparent,
          rangePickerElevation: 0,
          rangePickerHeaderBackgroundColor:
              scheme.primary.withOpacity(isDark ? 0.14 : 0.10),
          rangePickerHeaderForegroundColor: scheme.primary,
          rangePickerHeaderHeadlineStyle: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
          rangePickerHeaderHelpStyle: theme.textTheme.bodySmall?.copyWith(
            color: scheme.primary.withOpacity(0.8),
          ),
          headerBackgroundColor:
              scheme.primary.withOpacity(isDark ? 0.14 : 0.10),
          headerForegroundColor: scheme.primary,
          headerHeadlineStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          headerHelpStyle: theme.textTheme.bodySmall?.copyWith(
            color: scheme.primary.withOpacity(0.8),
          ),
          dayStyle: theme.textTheme.bodyMedium,
          dayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? const Color(0xFF10202A) : Colors.white;
            }
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withOpacity(0.3);
            }
            return scheme.onSurface;
          }),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return null;
          }),
          todayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? const Color(0xFF10202A) : Colors.white;
            }
            return scheme.primary;
          }),
          todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return null;
          }),
          todayBorder: BorderSide(color: scheme.primary, width: 1.4),
          rangeSelectionBackgroundColor: scheme.primary.withOpacity(0.14),
          dayOverlayColor: WidgetStateProperty.all(
              scheme.primary.withOpacity(0.12)),
          yearOverlayColor:
              WidgetStateProperty.all(scheme.primary.withOpacity(0.12)),
          // v1.6.3: unified button pair — Cancel outlined + Confirm filled
          // primary (app convention: outline left, primary right, equal
          // height, rounded corners).
          cancelButtonStyle: ButtonStyle(
            foregroundColor:
                WidgetStateProperty.all(scheme.onSurface.withOpacity(0.7)),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.outline.withOpacity(0.8)),
            )),
          ),
          confirmButtonStyle: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(scheme.primary),
            foregroundColor: WidgetStateProperty.all(
                isDark ? const Color(0xFF10202A) : Colors.white),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            )),
          ),
          dividerColor: scheme.outlineVariant.withOpacity(0.5),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: scheme.primary),
        ),
      );
      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 8,
        shadowColor: scheme.primary.withOpacity(0.10),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Theme(
            data: pickerTheme,
            // v1.6.1: the range picker takes its dialog size from the
            // closest MediaQuery — override it to a calendar-hugging size
            // so no fullscreen blank margins appear on desktop.
            // v1.6.3: FittedBox scales the whole picker up 1.1× inside the
            // enlarged box — near-native rendering, zero margins.
            child: SizedBox(
              width: pickerVisualSize.width,
              height: pickerVisualSize.height,
              child: FittedBox(
                fit: BoxFit.contain,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: pickerSize),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
