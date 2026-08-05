import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

Future<void> _mouseDrag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from,
      kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
  await tester.pump(const Duration(milliseconds: 30));
  await g.moveTo(to);
  await tester.pump(const Duration(milliseconds: 30));
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> _mouseRightClick(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at,
      kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await tester.pump(const Duration(milliseconds: 30));
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  // Documents a Flutter SDK bug (verified on Flutter 3.44.7): SelectionArea
  // (SelectableRegion._handleRightClickDown) collapses the active selection
  // on right-click because its selection-rect hit test is glyph-tight while
  // the visible highlight covers whole lines. TaskFlow therefore does NOT
  // use SelectionArea for content areas — SelectableText-based widgets
  // (see the passing tests below) keep the selection on right-click.
  testWidgets(
      'SelectionArea+Text: right-click inside selection',
      skip: true,
      (tester) async {
    SelectedContent? lastContent;
    int changeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (c) {
              lastContent = c;
              changeCount++;
              // ignore: avoid_print
              print('SELECTION CHANGED #$changeCount: '
                  '${c == null ? "null" : "\"${c.plainText}\""}');
            },
            child: const Padding(
              padding: EdgeInsets.all(40),
              child: Text('line one of text\nline two of text\nline three'),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(Text));
    await _mouseDrag(tester, rect.topLeft + const Offset(4, 6),
        rect.topLeft + const Offset(60, 40));
    // ignore: avoid_print
    print('AFTER drag: content=${lastContent?.plainText}');
    expect(lastContent != null && lastContent!.plainText.isNotEmpty, isTrue,
        reason: 'drag should select text');

    await _mouseRightClick(tester, rect.topLeft + const Offset(20, 20));
    // ignore: avoid_print
    print('After right-click: content=${lastContent?.plainText}');
    expect(lastContent != null && lastContent!.plainText.isNotEmpty, isTrue,
        reason: 'selection must survive right-click inside it');
  });

  testWidgets(
      'SelectionArea + Listener intercept keeps selection on right-click',
      skip: true,
      (tester) async {
    SelectedContent? lastContent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Listener(
            onPointerDown: (e) {
              if (e.buttons == kSecondaryMouseButton &&
                  (lastContent?.plainText.isNotEmpty ?? false)) {
                // Swallow the right-click so SelectableRegion's
                // _handleRightClickDown never collapses the selection.
                // ignore: avoid_print
                print('INTERCEPTED right-click');
              }
            },
            behavior: HitTestBehavior.translucent,
            child: SelectionArea(
              onSelectionChanged: (c) {
                lastContent = c;
                // ignore: avoid_print
                print('SA2 SELECTION CHANGED: '
                    '${c == null ? "null" : "\"${c.plainText}\""}');
              },
              child: const Padding(
                padding: EdgeInsets.all(40),
                child: Text('line one of text\nline two of text\nline three'),
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(Text));
    await _mouseDrag(tester, rect.topLeft + const Offset(4, 6),
        rect.topLeft + const Offset(60, 40));
    expect(lastContent != null && lastContent!.plainText.isNotEmpty, isTrue,
        reason: 'drag should select text');

    await _mouseRightClick(tester, rect.topLeft + const Offset(20, 20));
    // ignore: avoid_print
    print('SA2 after right-click: content=${lastContent?.plainText}');
    expect(lastContent != null && lastContent!.plainText.isNotEmpty, isTrue,
        reason: 'selection must survive an intercepted right-click');
  });

  testWidgets('SelectableText: right-click inside selection', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(40),
            child:
                SelectableText('line one of text\nline two of text\nline three'),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(SelectableText));
    await _mouseDrag(tester, rect.topLeft + const Offset(4, 6),
        rect.topLeft + const Offset(60, 40));

    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final sel1 = state.textEditingValue.selection;
    // ignore: avoid_print
    print('ST after drag: $sel1');
    expect(sel1.isCollapsed, isFalse);

    await _mouseRightClick(tester, rect.topLeft + const Offset(20, 20));
    final sel2 = state.textEditingValue.selection;
    // ignore: avoid_print
    print('ST after right-click: $sel2');
    expect(sel2.isCollapsed, isFalse,
        reason: 'SelectableText selection must survive right-click');
  });
}
