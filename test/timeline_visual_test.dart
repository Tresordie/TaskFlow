import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/presentation/shared/emoji_glyphs.dart';
import 'package:taskflow/presentation/shared/timeline_rail.dart';
import 'package:taskflow/presentation/timeline/timeline_screen.dart';

/// v1.12.39: the Timeline page and the task Execution Log were re-skinned onto
/// ONE shared spine (TimelineRail + TimelineNode) with an emoji vocabulary, and
/// the Timeline list now groups by day in range mode. These tests lock the
/// contracts that the visual change depends on.
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

    test('first/last markers drive the rail caps', () {
      final tasks = [
        task(1, DateTime(2026, 9, 29, 10)),
        task(2, DateTime(2026, 9, 28, 10)),
      ];
      final rows = TimelineRows.build(tasks, showDayHeaders: true);
      // rows: day, task1, day, task2
      expect(TimelineRows.isFirstOfRun(rows, 0), isFalse);
      expect(TimelineRows.isFirstOfRun(rows, 1), isTrue);
      expect(TimelineRows.isFirstOfRun(rows, 3), isTrue);
      expect(TimelineRows.isLastEvent(rows, 1), isFalse);
      expect(TimelineRows.isLastEvent(rows, 3), isTrue);
    });
  });

  group('TimelineRail rendering', () {
    Widget harness({required Widget node, bool isLast = false, double h = 200}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: h,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TimelineRail(
                    accentColor: Colors.blue,
                    isLast: isLast,
                    node: node,
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 120, height: 60),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('glyph node renders without overflow errors',
        (tester) async {
      await tester.pumpWidget(harness(
        node: const TimelineNode(glyph: '🚧', accentColor: Colors.blue),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('🚧'), findsOneWidget);
      // The groove keeps its declared width whatever the content does.
      expect(tester.getSize(find.byType(TimelineRail)).width, 26);
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
      final nodes = tester.widgetList<TimelineNode>(find.byType(TimelineNode));
      final sizes = nodes
          .map((n) => n.emphasized ? 'big' : 'small')
          .toList();
      expect(sizes, ['small', 'big']);
      expect(
        tester.getSize(find.byType(TimelineNode).last).height,
        greaterThan(tester.getSize(find.byType(TimelineNode).first).height),
      );
    });

    testWidgets('last event ends the spine instead of continuing it',
        (tester) async {
      await tester.pumpWidget(harness(
        node: const TimelineNode(glyph: '📝', accentColor: Colors.blue),
        isLast: true,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineRail), findsOneWidget);
    });

    testWidgets('rail stays inside its slot at 140% text scale',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: harness(
            node: const TimelineNode(glyph: '⛔', accentColor: Colors.red),
            h: 90,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
