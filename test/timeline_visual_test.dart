import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/presentation/shared/emoji_glyphs.dart';
import 'package:taskflow/presentation/shared/task_list_card.dart';
import 'package:taskflow/presentation/shared/timeline_rail.dart';
import 'package:taskflow/presentation/timeline/timeline_screen.dart';
import 'package:taskflow/providers/date_nav_providers.dart';
import 'package:taskflow/providers/task_providers.dart';

/// v1.12.39: the Timeline page and the task Execution Log were re-skinned onto
/// ONE shared spine (TimelineRail + TimelineNode) with an emoji vocabulary.
/// v1.12.40 locked the alignment (fixed node offset, label centred on it).
/// v1.12.41: the date + time live on the LEFT of every task again — one
/// aligned two-line column, no day headers — so these tests now check the real
/// page end to end.
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

  group('alignment budget', () {
    test('the label box is centred on the node centre line', () {
      expect(TimelineLayout.labelBoxHeight(), TimelineRail.nodeCenterY() * 2);
      expect(TimelineRail.nodeCenterY(),
          TimelineRail.nodeInset + TimelineRail.nodeDiameter / 2);
      expect(
        TimelineRail.nodeCenterY(emphasized: true),
        greaterThan(TimelineRail.nodeCenterY()),
      );
    });

    test('the label format is fixed width, every row identical', () {
      final d = DateTime(2026, 9, 5, 7, 8);
      expect(TimelineLayout.dateLabel(d), '2026-09-05');
      expect(TimelineLayout.timeLabel(d), '07:08');
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

    testWidgets('every row puts its node on the same line', (tester) async {
      await tester.pumpWidget(row(children: [
        rail(),
        const SizedBox(width: 8),
        rail(isLast: true),
      ]));
      await tester.pumpAndSettle();
      final first = tester.getCenter(find.byType(TimelineNode).first);
      final last = tester.getCenter(find.byType(TimelineNode).last);
      expect(first.dy, closeTo(last.dy, 0.01),
          reason: 'a top cap or per-row offset would desync the spine');
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

  test('v1.12.43: the spine is a recess, not a drawn capsule', () {
    // The hairline outline around the groove read as an ugly stroked tube on
    // both the Timeline and the task Event Log (user: 时间线加外框难看 /
    // Notes 时间线外框难看). The recess now comes from the fill alone, and
    // the 1px inset that keeps the node centred is padding, not a border.
    const rail = TimelineRail(
      node: SizedBox.shrink(),
      accentColor: Color(0xFF3F6C99),
    );
    for (final brightness in Brightness.values) {
      final decoration = rail.grooveDecoration(brightness);
      expect(decoration.border, isNull,
          reason: 'no outline on ${brightness.name}');
      expect(decoration.gradient, isNotNull,
          reason: 'the channel still needs its recessed fill');
    }

    expect(rail.grooveInset, TimelineRail.grooveBorderWidth);
  });

  group('Timeline page — date + time on the left of every task', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayA = today.subtract(const Duration(days: 1));
    final dayB = today.subtract(const Duration(days: 3));
    final atA = dayA.add(const Duration(hours: 10, minutes: 15));
    final atB = dayB.add(const Duration(hours: 18, minutes: 40));

    Future<void> pumpTimeline(WidgetTester tester, List<Task> tasks) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWithValue(_FakeRepo(tasks)),
            timelineDateNavProvider.overrideWith(
              (ref) => DateNavState(
                selectedDate: today,
                dateRange: DateTimeRange(
                  start: today.subtract(const Duration(days: 10)),
                  end: today,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TimelineScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('each row shows its own date and time, no day headers',
        (tester) async {
      await pumpTimeline(tester, [task(1, atA), task(2, atB)]);
      expect(tester.takeException(), isNull);

      final dateA = DateFormat('yyyy-MM-dd').format(atA);
      final dateB = DateFormat('yyyy-MM-dd').format(atB);
      expect(find.text(dateA), findsOneWidget);
      expect(find.text(dateB), findsOneWidget);
      expect(find.text('10:15'), findsOneWidget);
      expect(find.text('18:40'), findsOneWidget);
      // The day-group headers are gone — nothing counts tasks per day.
      expect(find.textContaining(' tasks'), findsNothing);
    });

    testWidgets('the label column sits left of the spine, the card right',
        (tester) async {
      await pumpTimeline(tester, [task(1, atA), task(2, atB)]);
      final dateA = DateFormat('yyyy-MM-dd').format(atA);

      final labelRight = tester.getRect(find.text(dateA)).right;
      final railLeft = tester.getRect(find.byType(TimelineRail).first).left;
      final cardLeft = tester.getRect(find.byType(TaskListCard).first).left;
      expect(labelRight, lessThan(railLeft),
          reason: 'the date/time column must be left of the spine');
      expect(cardLeft, greaterThan(railLeft),
          reason: 'the card must sit right of the spine');

      // ...and both rows share one spine x and one label right edge.
      final rails = find.byType(TimelineRail);
      expect(tester.getCenter(rails.first).dx,
          closeTo(tester.getCenter(rails.last).dx, 0.01));
      expect(
        tester.getRect(find.text(dateA)).right,
        closeTo(
            tester
                .getRect(find.text(DateFormat('yyyy-MM-dd').format(atB)))
                .right,
            0.01),
      );
    });

    testWidgets('the node sits between the date and the time', (tester) async {
      await pumpTimeline(tester, [task(1, atA)]);
      final date = DateFormat('yyyy-MM-dd').format(atA);
      final nodeDy = tester.getCenter(find.byType(TimelineNode).first).dy;
      final mid = (tester.getCenter(find.text(date)).dy +
              tester.getCenter(find.text('10:15')).dy) /
          2;
      expect(mid, closeTo(nodeDy, 3.0),
          reason: 'date above / time below, straddling the node');
    });

    testWidgets('single-day mode carries the date too', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWithValue(_FakeRepo([task(1, atA)])),
            timelineDateNavProvider.overrideWith(
              (ref) => DateNavState(selectedDate: dayA),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TimelineScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(DateFormat('yyyy-MM-dd').format(atA)), findsOneWidget);
      expect(find.text('10:15'), findsOneWidget);
    });
  });
}

/// In-memory repo so the page renders real rows without touching Hive.
class _FakeRepo extends TaskRepository {
  final List<Task> tasks;

  _FakeRepo(this.tasks);

  @override
  Future<List<Task>> getAllTasks() async => tasks;
}
