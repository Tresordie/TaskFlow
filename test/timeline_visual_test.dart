import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/presentation/shared/emoji_glyphs.dart';
import 'package:taskflow/presentation/shared/timeline_rail.dart';
import 'package:taskflow/presentation/timeline/timeline_screen.dart';

/// v1.12.39: the Timeline page and the task Execution Log were re-skinned onto
/// ONE shared spine (TimelineRail + TimelineNode) with an emoji vocabulary, and
/// the Timeline list now groups by day. v1.12.39 follow-up: the alignment pass
/// — the node sits at a fixed offset, the time label centres on it, the day
/// header lines up with the cards, and every group ends its own spine.
/// These tests lock those contracts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Task task(int id, DateTime at, {TaskStatus status = TaskStatus.planned}) =>
      Task()
        ..id = id
        ..uid = 'uid-$id'
        ..title = 'Task $id'
        ..status = status
        ..priority = Priority.p2Medium
        ..createdAt = at;

  group('emoji vocabulary', () {
    test('every TaskStatus has a glyph', () {
      for (final s in TaskStatus.values) {
        expect(statusGlyph(s), isNotEmpty, reason: '$s needs a glyph');
      }
    });

    test('every EntryType has a glyph', () {
      for (final t in EntryType.values) {
        expect(entryGlyph(t), isNotEmpty, reason: '$t needs a glyph');
      }
    });

    test('the pairs match the AI report vocabulary', () {
      expect(statusGlyph(TaskStatus.completed), '✅');
      expect(statusGlyph(TaskStatus.inProgress), '🚧');
      expect(statusGlyph(TaskStatus.blocked), '⛔');
      expect(statusGlyph(TaskStatus.archived), '📦');
      expect(entryGlyph(EntryType.pass), '✅');
      expect(entryGlyph(EntryType.fail), '❌');
      expect(entryGlyph(EntryType.note), '📝');
      expect(entryGlyph(EntryType.blocked), '⛔');
    });
  });

  group('TimelineRows flattening', () {
    test('single-day mode emits tasks only', () {
      final tasks = [
        task(1, DateTime(2026, 9, 29, 10)),
        task(2, DateTime(2026, 9, 29, 9)),
      ];
      final rows = TimelineRows.build(tasks);
      expect(rows, hasLength(2));
      expect(rows.every((r) => r is Task), isTrue);
    });

    test('range mode interleaves a counted day header per run of days', () {
      final tasks = [
        task(1, DateTime(2026, 9, 29, 10)),
        task(2, DateTime(2026, 9, 29, 8)),
        task(3, DateTime(2026, 9, 27, 20)),
      ];
      final rows = TimelineRows.build(tasks, showDayHeaders: true);
      expect(rows.map((r) => r.runtimeType.toString()).toList(),
          ['TimelineDayRow', 'Task', 'Task', 'TimelineDayRow', 'Task']);
      final first = rows.first as TimelineDayRow;
      expect(first.date, DateTime(2026, 9, 29));
      expect(first.count, 2);
      expect((rows[3] as TimelineDayRow).count, 1);
    });

    test('a day split inside the same week still starts a new group', () {
      final tasks = [
        task(1, DateTime(2026, 10, 1, 0, 5)),
        task(2, DateTime(2026, 9, 30, 23, 55)),
      ];
      final rows = TimelineRows.build(tasks, showDayHeaders: true);
      expect(rows.whereType<TimelineDayRow>().length, 2);
    });

    test('each day group ends its own spine', () {
      final tasks = [
        task(1, DateTime(2026, 9, 29, 10)),
        task(2, DateTime(2026, 9, 29, 8)),
        task(3, DateTime(2026, 9, 27, 20)),
      ];
      final rows = TimelineRows.build(tasks, showDayHeaders: true);
      // rows: day, t1, t2, day, t3
      expect(TimelineRows.isLastOfGroup(rows, 1), isFalse);
      expect(TimelineRows.isLastOfGroup(rows, 2), isTrue,
          reason: 't2 is the last event of Sep 29 — the connector must stop');
      expect(TimelineRows.isLastOfGroup(rows, 4), isTrue);
    });
  });

  group('alignment budget', () {
    test('the day header indent equals the columns left of the card', () {
      expect(
        TimelineRows.cardIndent,
        TimelineRows.timeColumnWidth +
            TimelineRows.timeGap +
            TimelineRows.railWidth +
            TimelineRows.railGap,
      );
    });

    test('the node centre is a fixed distance from the row top', () {
      expect(TimelineRail.nodeCenterY(),
          TimelineRail.nodeInset + TimelineRail.nodeDiameter / 2);
      expect(
        TimelineRail.nodeCenterY(emphasized: true),
        greaterThan(TimelineRail.nodeCenterY()),
      );
    });
  });

  group('TimelineRail rendering', () {
    Widget row({required List<Widget> children, double h = 220}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: h,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      );
    }

    Widget rail({bool isLast = false, Widget? node}) => TimelineRail(
          accentColor: Colors.blue,
          isLast: isLast,
          node:
              node ?? const TimelineNode(glyph: '🚧', accentColor: Colors.blue),
        );

    testWidgets('glyph node renders without overflow errors', (tester) async {
      await tester.pumpWidget(row(children: [rail()]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('🚧'), findsOneWidget);
      expect(tester.getSize(find.byType(TimelineRail)).width, 26);
    });

    testWidgets('the time label sits level with the node', (tester) async {
      await tester.pumpWidget(row(children: [
        SizedBox(
          width: TimelineRows.timeColumnWidth,
          height: TimelineRail.nodeCenterY() * 2,
          child: const Align(
            alignment: Alignment.centerRight,
            child: Text('17:52'),
          ),
        ),
        const SizedBox(width: TimelineRows.timeGap),
        rail(),
      ]));
      await tester.pumpAndSettle();
      final node = tester.getCenter(find.byType(TimelineNode));
      final label = tester.getCenter(find.text('17:52'));
      expect((node.dy - label.dy).abs(), lessThan(1.0),
          reason: 'a label boxed to 2x nodeCenterY must centre on the node');
      // ...and it hugs the spine instead of floating at the page margin.
      expect(
        tester.getRect(find.text('17:52')).right,
        closeTo(
            tester.getRect(find.byType(TimelineRail)).left -
                TimelineRows.timeGap,
            1.0),
      );
    });

    testWidgets('every row centres its label on the same line', (tester) async {
      await tester.pumpWidget(row(children: [
        rail(),
        const SizedBox(width: 8),
        rail(isLast: true),
      ]));
      await tester.pumpAndSettle();
      final centers = [
        tester.getCenter(find.byType(TimelineNode).first).dy,
        tester.getCenter(find.byType(TimelineNode).last).dy,
      ];
      expect(centers[0], closeTo(centers[1], 0.01),
          reason: 'no row may push its node down — that is what made the '
              'spine and the labels read as misaligned');
    });

    testWidgets('emphasized node is the larger chip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: const [
            TimelineNode(glyph: '✅', accentColor: Colors.green),
            TimelineNode(
                glyph: '✅', accentColor: Colors.green, emphasized: true),
          ]),
        ),
      ));
      expect(
        tester.getSize(find.byType(TimelineNode).last).height,
        greaterThan(tester.getSize(find.byType(TimelineNode).first).height),
      );
    });

    testWidgets('last event ends the spine instead of continuing it',
        (tester) async {
      await tester.pumpWidget(row(children: [rail(isLast: true)]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineRail), findsOneWidget);
    });

    testWidgets('rail stays inside its slot at 140% text scale',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: row(
            h: 90,
            children: [
              rail(
                  node:
                      const TimelineNode(glyph: '⛔', accentColor: Colors.red)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
