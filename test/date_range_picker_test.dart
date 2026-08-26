import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/app_date_picker.dart';

/// Date-range picker sizing contracts:
/// - v1.6.1: Material's range picker sizes its dialog to
///   `MediaQuery.sizeOf` (the FULL WINDOW) with zero insets — on desktop
///   the calendar floated in the middle of a fullscreen sheet with huge
///   blank side margins (user report). The wrapper must feed it a compact
///   size so the dialog hugs the calendar grid.
/// - v1.6.2: that 420×520 dialog felt too small (user report) — the picker
///   is now laid out at 440×460 and scaled up 1.5× via FittedBox, so the
///   visible popup is 660×690 with zero blank margins.
void main() {
  testWidgets('range picker dialog is enlarged 1.5x to a 660x690 popup',
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
    // MediaQuery — 440x460 layout size, NOT the full 1600x1000 window.
    final sized = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(AnimatedContainer),
    );
    expect(sized, findsOneWidget);
    expect(tester.getSize(sized).width, 440);
    expect(tester.getSize(sized).height, 460);

    // The outer chrome carries the enlarged 660x690 visual size: the
    // FittedBox (our wrapper's child) is 660x690 and scales the picker up
    // 1.5x inside it.
    expect(tester.getSize(find.byType(FittedBox)).width, 660);
    expect(tester.getSize(find.byType(FittedBox)).height, 690);
  });
}
