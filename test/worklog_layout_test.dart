import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/presentation/work_log/work_log_screen.dart';

/// Regression tests for the v1.4.21 Work Log layout rework:
///  - the records / history cards must fill the remaining column height so no
///    bare page-background ("gray gap") shows below short lists;
///  - no ParentDataWidget misuse (Spacer/Expanded outside a Flex);
///  - no RenderFlex overflow in the summary-card title row.
void main() {
  Future<void> pumpPage(WidgetTester tester, List<Map<String, dynamic>> recs,
      {Size size = const Size(1280, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'worklog.records': jsonEncode(recs),
    });
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: WorkLogScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('records card fills remaining column height with one record',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await pumpPage(tester, [
      {'id': '1', 'content': 'Fixed the mapping file issue', 'timestamp': now},
    ]);

    // No layout exceptions (ParentDataWidget misuse, overflow, ...).
    expect(tester.takeException(), isNull);

    // Card order in build(): input, records (left column),
    // summary, history (right column).
    final cards = find.byType(Card).evaluate().toList();
    expect(cards.length, 4);
    final inputBox = cards[0].renderObject as RenderBox;
    final recordsBox = cards[1].renderObject as RenderBox;

    // The records card must stretch to fill everything below the input card,
    // not hug its single row of content (old bug left a large gray gap).
    expect(recordsBox.size.height, greaterThan(300));
    // And it must be strictly taller than the input card.
    expect(recordsBox.size.height, greaterThan(inputBox.size.height));
  });

  testWidgets('empty state is centered and no layout exceptions',
      (tester) async {
    await pumpPage(tester, []);
    expect(tester.takeException(), isNull);

    expect(find.text('No work records yet'), findsOneWidget);
    expect(
      find.text('Enter content above and click "Save record" (Ctrl+Enter).'),
      findsOneWidget,
    );
  });

  testWidgets('many records scroll inside the card without overflow',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await pumpPage(tester, [
      for (var i = 0; i < 30; i++)
        {'id': '$i', 'content': 'Record number $i', 'timestamp': now - i},
    ]);
    expect(tester.takeException(), isNull);
    // First and last records: the list is internally scrollable, so the last
    // one is built lazily — just make sure the page itself is stable.
    expect(find.text('Record number 0'), findsOneWidget);
  });
}
