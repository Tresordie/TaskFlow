// Verification tests for the two Work Log selection bugs:
//  - Issue 2: record content cannot be selected left-to-right (date/time are
//    two separate Text selectables creating a geometric dead-zone).
//  - Issue 1: selecting inside the right (AI summary) column also selects the
//    left (records) column, because both columns share one selection scope.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/app/app.dart';
import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/presentation/shared/app_markdown_body.dart';

const String _kText =
    'Foxlink提供了FATP组装线上来料有SN的物料清单2.对比当前的mapping file format, left brake lever, right brake lever, caliper没有加入到mapping file';

const String _kMd = '📄 **Work Summary**\n'
    '- The current mapping file does not include the left brake lever, right brake lever, and caliper.\n'
    '- The SNs for these three items are already stored in the SFC database.';

MaterialApp _themed(Widget child) => MaterialApp(
      scrollBehavior: AppScrollBehavior(),
      theme: AppTheme.buildTheme(AppThemeMode.indigoLight),
      debugShowCheckedModeBanner: false,
      home: child,
    );

// ── Row builders ─────────────────────────────────────────────────────────

/// Original production row: date and time are TWO separate Text widgets.
Widget _rowTwoText() => _rowShell(
      dateChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('2026-07-25', style: TextStyle(fontSize: 11)),
          Text('15:01', style: TextStyle(fontSize: 10.5)),
        ],
      ),
    );

/// Fixed row: date and time merged into a SINGLE Text.rich (one selectable).
Widget _rowMerged() => _rowShell(
      dateChild: Text.rich(
        TextSpan(
          children: [
            TextSpan(
                text: '2026-07-25\n',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            TextSpan(
                text: '15:01',
                style: TextStyle(
                    fontSize: 10.5, color: Colors.black.withOpacity(0.5))),
          ],
        ),
      ),
    );

Widget _rowShell({required Widget dateChild}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 24, child: Checkbox(value: false, onChanged: (_) {})),
          const SizedBox(width: 8),
          SizedBox(width: 74, child: dateChild),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_kText,
                  style: const TextStyle(fontSize: 13, height: 1.45))),
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {},
              icon: const Icon(Icons.edit, size: 15)),
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {},
              icon: const Icon(Icons.delete_outline, size: 15)),
        ],
      ),
    );

// ── Probe helpers ────────────────────────────────────────────────────────

RenderParagraph _paraOf(WidgetTester tester, Finder textFinder) =>
    tester.renderObject<RenderParagraph>(find
        .descendant(of: textFinder, matching: find.byType(RichText))
        .first);

bool _anySelected(WidgetTester tester, Finder textFinder) {
  final n = textFinder.evaluate().length;
  for (var i = 0; i < n; i++) {
    final p = _paraOf(tester, textFinder.at(i));
    if (p.selections.any((s) => !s.isCollapsed)) return true;
  }
  return false;
}

String _selDump(WidgetTester tester, Finder textFinder) {
  final n = textFinder.evaluate().length;
  final parts = <String>[];
  for (var i = 0; i < n; i++) {
    final p = _paraOf(tester, textFinder.at(i));
    final l = p.selections.map((s) => '(${s.start},${s.end})').join(',');
    parts.add(l.isEmpty ? '-' : l);
  }
  return parts.join(' | ');
}

/// Drag left-to-right across the FIRST content paragraph; return whether it
/// ended up with a non-collapsed selection.
Future<bool> _probeContentLtr(WidgetTester tester) async {
  final finder =
      find.descendant(of: find.text(_kText), matching: find.byType(RichText)).first;
  final rect = tester.getRect(finder);
  final from = rect.topLeft + const Offset(2, 2);
  final to = Offset(rect.right - 2, rect.top + 8);
  final gesture =
      await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  for (var i = 1; i <= 5; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 5)!);
    await tester.pump();
  }
  final selected = _paraOf(tester, find.text(_kText).first)
      .selections
      .any((s) => !s.isCollapsed);
  await gesture.up();
  await tester.pump();
  return selected;
}

// ── Tests ────────────────────────────────────────────────────────────────

void main() {
  testWidgets('F1: merged date/time row → content selects left-to-right',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 880));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_themed(SelectionArea(
        child: Scaffold(
            body: Padding(
      padding: const EdgeInsets.all(28),
      child: ListView(
        primary: false,
        children: [_rowMerged(), _rowMerged(), _rowMerged()],
      ),
    )))));
    await tester.pumpAndSettle();
    final ok = await _probeContentLtr(tester);
    debugPrint('F1 merged-row LTR drag → ${ok ? "PASS" : "FAIL"} '
        '(content=${_selDump(tester, find.text(_kText).first)})');
    expect(ok, isTrue);
  });

  testWidgets('F1b: ORIGINAL two-text row → content LTR drag (expect broken)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 880));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_themed(SelectionArea(
        child: Scaffold(
            body: Padding(
      padding: const EdgeInsets.all(28),
      child: ListView(
        primary: false,
        children: [_rowTwoText(), _rowTwoText(), _rowTwoText()],
      ),
    )))));
    await tester.pumpAndSettle();
    final ok = await _probeContentLtr(tester);
    debugPrint('F1b two-text-row LTR drag → ${ok ? "PASS" : "FAIL"} '
        '(content=${_selDump(tester, find.text(_kText).first)})');
    // Informational: documents the pre-fix broken behavior.
  });

  testWidgets('F2: REPRO cross-column — drag in summary selects records',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 880));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_themed(SelectionArea(
        child: Scaffold(
            body: Padding(
      padding: const EdgeInsets.all(28),
      child: _twoColumns(isolate: false),
    )))));
    await tester.pumpAndSettle();
    final r = await _probeSummary(tester);
    debugPrint('F2 single-scope: summarySelected=${r.right} '
        'leftSelected=${r.left} '
        'leftDump=${_selDump(tester, find.text(_kText))}');
  });

  testWidgets('F3: FIXED isolated columns — summary drag stays in column',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 880));
    addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_themed(SelectionArea(
        child: Scaffold(
            body: Padding(
      padding: const EdgeInsets.all(28),
      child: _twoColumns(isolate: true, mergedRows: true),
    )))));
    await tester.pumpAndSettle();
    final r = await _probeSummary(tester);
    debugPrint('F3 isolated: summarySelected=${r.right} '
        'leftSelected=${r.left} '
        'leftDump=${_selDump(tester, find.text(_kText))}');
    expect(r.right, isTrue, reason: 'summary must be selectable');
    expect(r.left, isFalse, reason: 'records column must NOT be selected');

    // Also verify the left column still selects its own content.
    final leftOk = await _probeContentLtr(tester);
    debugPrint('F3 isolated left-column LTR drag → ${leftOk ? "PASS" : "FAIL"} '
        '(content=${_selDump(tester, find.text(_kText).first)})');
    expect(leftOk, isTrue, reason: 'records column must stay selectable');
  });
}

// ── Two-column page (records | summary) ──────────────────────────────────

Widget _twoColumns({required bool isolate, bool mergedRows = false}) {
  Widget mkRow() => mergedRows ? _rowMerged() : _rowTwoText();
  Widget leftCol = Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        primary: false,
        padding: EdgeInsets.zero,
        children: [mkRow(), mkRow(), mkRow()],
      ),
    ),
  );
  Widget rightCol = Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        primary: false,
        child: KeyedSubtree(
          key: const ValueKey('md'),
          child: AppMarkdownBody(data: _kMd),
        ),
      ),
    ),
  );
  if (isolate) {
    leftCol = SelectionArea(child: leftCol);
    rightCol = SelectionArea(child: rightCol);
  }
  final row = Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 3, child: leftCol),
      const SizedBox(width: 14),
      Expanded(flex: 2, child: rightCol),
    ],
  );
  return isolate ? SelectionContainer.disabled(child: row) : row;
}

/// Drag diagonally across the AI summary markdown; report whether the summary
/// (right column) and the records (left column) ended up selected.
Future<({bool left, bool right})> _probeSummary(WidgetTester tester) async {
  final mdRect = tester.getRect(find.byKey(const ValueKey('md')));
  final from = mdRect.topLeft + const Offset(4, 4);
  final to = mdRect.bottomRight - const Offset(4, 4);
  final gesture =
      await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  for (var i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
    await tester.pump();
  }
  final right = _anySelected(tester, find.textContaining('brake lever'));
  final left = _anySelected(tester, find.text(_kText));
  await gesture.up();
  await tester.pump();
  return (left: left, right: right);
}
