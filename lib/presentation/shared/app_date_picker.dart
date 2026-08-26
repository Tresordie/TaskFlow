import 'package:flutter/material.dart';

/// A polished wrapper around [showDateRangePicker] used by Timeline,
/// Calendar and the Reports Custom range (v1.6.0): rounded floating
/// dialog, tinted header, primary-accent selection and hover highlights —
/// replacing the stock flat Material look with the app's visual language.
///
/// v1.6.1: Material's range picker sizes its dialog to
/// `MediaQuery.sizeOf` — the FULL WINDOW — with zero insets, so on desktop
/// the calendar floated in the middle of a fullscreen sheet with huge
/// blank margins on both sides (user report). The builder feeds the picker
/// a compact size override instead.
///
/// v1.6.2: the 420×520 dialog felt too small (user report) — the picker is
/// now rendered at a 440×460 layout size and scaled up 1.5× via
/// [FittedBox], so the WHOLE popup (calendar cells, fonts, header) is
/// visually 660×690 with zero blank side margins.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final scheme = theme.colorScheme;

  // Layout size fed to the picker (portrait month layout: a single month
  // grid is at most 480 logical px wide, so 440 fits it with no side
  // gutter) and the visual scale-up factor — the aspect ratios match so
  // FittedBox.contain scales exactly 1.5× and fills the outer box.
  const pickerSize = Size(440, 460);
  const pickerScale = 1.5;
  const pickerVisualSize = Size(660, 690);

  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    helpText: '选择日期范围 · Select range',
    cancelText: '取消',
    confirmText: '确定',
    saveText: '确定',
    fieldStartLabelText: '开始',
    fieldEndLabelText: '结束',
    builder: (context, child) {
      final pickerTheme = theme.copyWith(
        colorScheme: scheme.copyWith(
          onPrimary: isDark ? Color(0xFF10202A) : Colors.white,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: isDark ? 0 : 8,
          shadowColor: scheme.primary.withOpacity(0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
          ),
          // Range-picker specific slots — the calendar mode reads THESE
          // (not the plain fields above), so they must be set explicitly
          // for the themed look to actually apply.
          rangePickerShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
          ),
          rangePickerBackgroundColor: theme.colorScheme.surface,
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
          headerBackgroundColor: scheme.primary.withOpacity(isDark ? 0.14 : 0.10),
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
          cancelButtonStyle: ButtonStyle(
            foregroundColor:
                WidgetStateProperty.all(scheme.onSurface.withOpacity(0.7)),
          ),
          confirmButtonStyle: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(scheme.primary),
            foregroundColor: WidgetStateProperty.all(
                isDark ? const Color(0xFF10202A) : Colors.white),
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
        elevation: isDark ? 0 : 10,
        shadowColor: scheme.primary.withOpacity(0.18),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Theme(
            data: pickerTheme,
            // v1.6.1: the range picker takes its dialog size from the
            // closest MediaQuery — override it to a calendar-hugging size
            // so no fullscreen blank margins appear on desktop.
            // v1.6.2: FittedBox scales the whole picker up 1.5× inside the
            // enlarged box — bigger calendar cells and text, zero margins.
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
