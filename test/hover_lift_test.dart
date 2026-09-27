import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/shared/hover_lift.dart';

/// v1.12.13: the shared hover micro-interaction for Timeline / Calendar /
/// Activity task items — hovering lifts the card and adds an accent shadow.
void main() {
  List<BoxShadow>? shadowOf(AnimatedContainer container) {
    final decoration = container.decoration as BoxDecoration?;
    return decoration?.boxShadow;
  }

  testWidgets('hover adds shadow and lift, unhover removes them',
      (tester) async {
    const key = Key('target');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoverLift(
            borderRadius: BorderRadius.circular(10),
            accentColor: Colors.blue,
            builder: (context, hovered) => Container(
              key: key,
              width: 100,
              height: 40,
              color: hovered ? Colors.blue.withOpacity(0.2) : Colors.grey,
            ),
          ),
        ),
      ),
    ));

    // Resting: two layered shadows (v1.12.22 material elevation).
    final resting = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first);
    expect(shadowOf(resting)!.length, 2);
    expect(find.byKey(key), findsOneWidget);

    // Hover with a real mouse pointer.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(key)));
    await tester.pumpAndSettle();

    final hovered = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first);
    expect(shadowOf(hovered)!.length, 3);

    // Unhover restores the resting look.
    await gesture.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    final after = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first);
    expect(shadowOf(after)!.length, 2);
  });
}
