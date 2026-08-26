import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/app_date_picker.dart';

/// v1.6.5 contract: the Custom range selection is ONE dialog using the
/// same calendar grid as the Daily/Weekly popup ([CalendarDatePicker]):
/// tap a day → START, tap again → END (tapping a day before the start
/// restarts the range there; tapping after both ends exist starts over),
/// OK confirms only once both ends exist, Cancel returns null.
void main() {
  late DateTimeRange? result;

  Future<void> openPicker(
    WidgetTester tester, {
    DateTimeRange? initialDateRange,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showAppDateRangePicker(
                    context: context,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                    initialDateRange: initialDateRange,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  final initialRange = DateTimeRange(
    start: DateTime(2026, 6, 1),
    end: DateTime(2026, 6, 10),
  );

  FilledButton okButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK'));

  setUp(() => result = null);

  testWidgets('one dialog: tap start, tap end, OK returns the range',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester, initialDateRange: initialRange);

    // A single dialog with the Daily/Weekly-style calendar grid. The
    // June 1–10 range is pre-filled, so OK starts enabled.
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.text('Select range'), findsOneWidget);
    expect(okButton(tester).onPressed, isNotNull);

    // Tapping with both ends set starts a FRESH selection at that day.
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    // Start chip reflects the picked day; OK still disabled (no end).
    expect(find.textContaining('Start Date · Jun 15, 2026'), findsOneWidget);
    expect(okButton(tester).onPressed, isNull);

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(find.textContaining('End Date · Jun 20, 2026'), findsOneWidget);
    expect(okButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, DateTimeRange(
      start: DateTime(2026, 6, 15),
      end: DateTime(2026, 6, 20),
    ));
  });

  testWidgets('tapping a day BEFORE the start restarts the range there',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester, initialDateRange: initialRange);

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    // The range restarted at the 10th, end cleared, OK disabled again.
    expect(find.textContaining('Start Date · Jun 10, 2026'), findsOneWidget);
    expect(find.text('End Date'), findsOneWidget);
    expect(okButton(tester).onPressed, isNull);

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, DateTimeRange(
      start: DateTime(2026, 6, 10),
      end: DateTime(2026, 6, 12),
    ));
  });

  testWidgets('tapping the same day twice yields a single-day range',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester, initialDateRange: initialRange);

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(okButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, DateTimeRange(
      start: DateTime(2026, 6, 15),
      end: DateTime(2026, 6, 15),
    ));
  });

  testWidgets('Cancel aborts and returns null', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester, initialDateRange: initialRange);

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, isNull);
    expect(find.byType(CalendarDatePicker), findsNothing);
  });

  testWidgets('the existing range is pre-filled and immediately confirmable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester, initialDateRange: initialRange);

    // June 1–10 pre-filled → chips show it and OK is already enabled.
    expect(find.textContaining('Start Date · Jun 1, 2026'), findsOneWidget);
    expect(find.textContaining('End Date · Jun 10, 2026'), findsOneWidget);
    expect(okButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(result, initialRange);
  });
}
