import 'package:flutter/material.dart';

/// A polished wrapper around [showDateRangePicker] used by Timeline,
/// Calendar and the Reports Custom range (v1.6.0): rounded floating
/// dialog, tinted header, primary-accent selection and hover highlights —
/// replacing the stock flat Material look with the app's visual language.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final scheme = theme.colorScheme;

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
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Theme(data: pickerTheme, child: child ?? const SizedBox.shrink()),
        ),
      );
    },
  );
}
