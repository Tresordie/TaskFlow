import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/app_date_picker.dart';

/// v1.6.4 contract: the Custom range selection uses the SAME compact
/// single-date `showDatePicker` popup as the Reports Daily/Weekly mode
/// (the user rejected the Material range-picker dialog as ugly), driven as
/// a two-step flow: pick the START date, then the END date. Cancelling
/// either step aborts the whole selection.
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

  setUp(() => result = null);

  testWidgets('two-step flow picks start then end via the single-date dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(
      tester,
      initialDateRange: DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 10),
      ),
    );

    // Step 1: the compact single-date dialog, not the range picker.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Start Date'), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    // The M3 dialog selects the day and waits for OK to confirm.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Step 2: end date — same dialog, constrained from the start onward.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('End Date'), findsOneWidget);
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, DateTimeRange(
      start: DateTime(2026, 6, 15),
      end: DateTime(2026, 6, 20),
    ));
  });

  testWidgets('cancelling the START step aborts the whole selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, isNull);
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('cancelling the END step aborts the whole selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester);

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('End Date'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, isNull);
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('end step cannot select a date before the chosen start',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(
      tester,
      initialDateRange: DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 10),
      ),
    );

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The end step opened on the chosen start (June 20): dates before it
    // are disabled — selecting a later day must still produce the range
    // anchored at the 20th.
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, DateTimeRange(
      start: DateTime(2026, 6, 20),
      end: DateTime(2026, 6, 25),
    ));
  });
}
