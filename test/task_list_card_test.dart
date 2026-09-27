import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/task_list_card.dart';

/// v1.12.24 regression: TaskListCard must render inside UNBOUNDED-height
/// containers (the Calendar day panel ListView, the Activity column) — the
/// stretch Row used to collapse to nothing there, making the task list
/// appear empty.
void main() {
  testWidgets('renders inside an unbounded-height ListView', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            TaskListCard(
              accentColor: Colors.blue,
              highlighted: false,
              borderRadius: BorderRadius.circular(10),
              padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
              child: const Text('Visible task'),
            ),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Visible task'), findsOneWidget);
  });

  testWidgets('the accent bar stretches to the card content height',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            TaskListCard(
              accentColor: Colors.blue,
              highlighted: false,
              borderRadius: BorderRadius.circular(10),
              padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
              child: const Text('Visible task'),
            ),
          ],
        ),
      ),
    ));

    // The bar is the 3px-wide decorated Container inside the IntrinsicHeight
    // row; it must have real height (stretched to the content) — if the
    // stretch collapsed it would be just its 3+3 vertical margins (6px).
    final bars = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 3.0);
    expect(bars, findsOneWidget);
    final height = tester.getSize(bars).height;
    expect(height, greaterThan(10));
  });
}
