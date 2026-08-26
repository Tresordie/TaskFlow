import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/app_date_picker.dart';

/// v1.6.1 contract: Material's range picker sizes its dialog to
/// `MediaQuery.sizeOf` (the FULL WINDOW) with zero insets — on desktop the
/// calendar floated in the middle of a fullscreen sheet with huge blank
/// side margins (user report). The wrapper must feed it a compact size so
/// the dialog hugs the calendar grid.
void main() {
  testWidgets('range picker dialog hugs a compact 420x520 content area',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppDateRangePicker(
                  context: context,
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The picker's internal AnimatedContainer is sized from the overridden
    // MediaQuery — 420x520, NOT the full 1600x1000 window.
    final sized = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(AnimatedContainer),
    );
    expect(sized, findsOneWidget);
    expect(tester.getSize(sized).width, 420);
    expect(tester.getSize(sized).height, 520);
  });
}
