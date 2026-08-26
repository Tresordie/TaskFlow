import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/app_date_picker.dart';

/// Date-range picker sizing contracts:
/// - v1.6.1: Material's range picker sizes its dialog to
///   `MediaQuery.sizeOf` (the FULL WINDOW) with zero insets — on desktop
///   the calendar floated in the middle of a fullscreen sheet with huge
///   blank side margins (user report). The wrapper must feed it a compact
///   size so the dialog hugs the calendar grid.
/// - v1.6.2: that 420×520 dialog felt too small (user report) — FittedBox
///   1.5× scale-up to a 660×690 visual popup.
/// - v1.6.3: 660×690 felt too big and the 1.5× strokes/text chunky (user
///   report) — layout 480×500 (the SDK portrait grid width cap → zero
///   margins) scaled just 1.1× into a 528×550 visual popup.
void main() {
  Future<void> openPicker(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: textScaler), child: child!),
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
  }

  void expectSizes(WidgetTester tester) {
    // The picker's internal AnimatedContainer is sized from the overridden
    // MediaQuery — 480x500 layout size, NOT the full window.
    final sized = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(AnimatedContainer),
    );
    expect(sized, findsOneWidget);
    expect(tester.getSize(sized).width, 480);
    expect(tester.getSize(sized).height, 500);

    // The FittedBox carries the enlarged 528x550 visual size (1.1x scale).
    expect(tester.getSize(find.byType(FittedBox)).width, 528);
    expect(tester.getSize(find.byType(FittedBox)).height, 550);
  }

  testWidgets('range picker dialog is a 1.1x-scaled 528x550 popup',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openPicker(tester);
    expectSizes(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker layout holds across 3 text scales x 2 DPIs (v1.6.3)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final scale in const [1.0, 1.25, 1.4]) {
      for (final dpr in const [1.0, 2.0]) {
        tester.view.devicePixelRatio = dpr;
        addTearDown(() => tester.view.resetDevicePixelRatio());
        await openPicker(tester, textScaler: TextScaler.linear(scale));
        expectSizes(tester);
        expect(tester.takeException(), isNull,
            reason: 'scale=$scale dpr=$dpr');
        // Close the dialog (calendar mode uses an X CloseButton, not a
        // Cancel text button) before the next combination.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
      }
    }
  });
}
