import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/data/services/report_service.dart';
import 'package:taskflow/presentation/reports/reports_screen.dart';
import 'package:taskflow/providers/task_providers.dart';

/// In-memory [TaskRepository] so report aggregation (_build) can be
/// unit-tested without opening an Isar database (same pattern as
/// core_logic_test.dart).
class _FakeRepo extends TaskRepository {
  final List<Task> _tasks;
  _FakeRepo(this._tasks);

  @override
  Future<List<Task>> getAllTasks() async => _tasks;
}

/// Contract tests for the v1.13.2 raw task-notes export: the Reports page
/// exports every task the current controls would report on, together with
/// ALL of each task's notes, as structured Markdown / styled HTML — no AI.
void main() {
  late Directory tmp;
  late File smallImage;
  late File bigImage;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('taskflow_notes_export');
    // A tiny "PNG" — the exporter embeds bytes without validating them.
    smallImage = File('${tmp.path}/shot.png')
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // Over the 2MB per-image cap — must fall back to a name chip.
    bigImage = File('${tmp.path}/big.png')
      ..writeAsBytesSync(List.filled(3 * 1024 * 1024, 0));
  });

  tearDownAll(() {
    tmp.deleteSync(recursive: true);
  });

  ExecutionEntry entry(String uid, DateTime ts, EntryType type, String content,
          {List<Attachment> attachments = const []}) =>
      ExecutionEntry()
        ..uid = uid
        ..timestamp = ts
        ..type = type
        ..content = content
        ..attachments = attachments;

  /// Period 2026-11-16 → 2026-11-22 (end exclusive 11-23).
  /// t1: in progress, 4 notes (1 older than the period, 3 in period),
  ///     description + nested sub-steps + image/file attachments.
  /// t2: completed in period, no notes.
  /// t3: created long ago, overdue in period, no activity — must still be
  ///     exported (it appears in the report's Risks/Blockers).
  /// t4: entirely outside the period — must NOT be exported.
  List<Task> sampleTasks() => [
        Task()
          ..uid = 't1'
          ..title = 'Thermal validation'
          ..project = 'Cosmo'
          ..status = TaskStatus.inProgress
          ..priority = Priority.p1High
          ..tags = ['thermal']
          ..createdAt = DateTime(2026, 11, 10)
          ..startedAt = DateTime(2026, 11, 16)
          ..dueDate = DateTime(2026, 11, 25)
          ..description = 'Validate **pack** temps.\nSecond line.'
          ..subSteps = [
            SubStep()
              ..uid = 's1'
              ..title = 'Probe attach'
              ..completed = true,
            SubStep()
              ..uid = 's2'
              ..title = 'Chamber run',
            SubStep()
              ..uid = 's3'
              ..title = 'Log temps'
              ..parentUid = 's2'
              ..depth = 0, // stale cache — depth must be derived (=1)
          ]
          ..executionLog = [
            entry('e1', DateTime(2026, 11, 12, 9), EntryType.note,
                'Older context note'),
            entry('e2', DateTime(2026, 11, 18, 10, 30), EntryType.pass,
                'Vout ~ 5V stable'),
            entry(
                'e3',
                DateTime(2026, 11, 20, 14),
                EntryType.note,
                '**Bold** result\n- item A\n- item B',
                attachments: [
                  Attachment()
                    ..uid = 'a1'
                    ..name = 'shot.png'
                    ..path = smallImage.path
                    ..size = smallImage.lengthSync()
                    ..type = AttachmentType.image,
                  Attachment()
                    ..uid = 'a2'
                    ..name = 'report.pdf'
                    ..path = '${tmp.path}/report.pdf'
                    ..size = 12345
                    ..type = AttachmentType.file,
                ]),
            entry('e4', DateTime(2026, 11, 21, 8), EntryType.blocked,
                '<script>alert(1)</script> waiting on chamber'),
          ],
        Task()
          ..uid = 't2'
          ..title = 'Label redesign'
          ..project = 'Cosmo'
          ..status = TaskStatus.completed
          ..createdAt = DateTime(2026, 11, 17)
          ..completedAt = DateTime(2026, 11, 19),
        Task()
          ..uid = 't3'
          ..title = 'Old overdue chore'
          ..status = TaskStatus.planned
          ..createdAt = DateTime(2026, 10, 1)
          ..dueDate = DateTime(2026, 11, 18),
        Task()
          ..uid = 't4'
          ..title = 'Unrelated future task'
          ..status = TaskStatus.planned
          ..createdAt = DateTime(2026, 12, 1)
          ..dueDate = DateTime(2026, 12, 10),
      ];

  Future<ReportData> buildData({Set<String>? onlyUids}) =>
      ReportService(_FakeRepo(sampleTasks())).generateRange(
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 22),
        onlyUids: onlyUids,
      );

  group('tasksNotesToMarkdown', () {
    test('structured document: title, projects, task meta, full notes',
        () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final md = svc.tasksNotesToMarkdown(await buildData());

      expect(md, contains('# TaskFlow Task Notes — '));
      expect(md, contains('**Period:** 2026-11-16 → 2026-11-22'));
      expect(md, contains('## Cosmo'));
      expect(md, contains('## General')); // t3 has no project
      expect(md, contains('### 🚧 Thermal validation'));
      expect(md, contains('**Status:** In Progress'));
      expect(md, contains('**Priority:** P1'));
      expect(md, contains('#thermal'));
      expect(md, contains('**Due:** 2026-11-25'));
      // Description verbatim (lossless).
      expect(md, contains('Validate **pack** temps.\nSecond line.'));
      // Sub-steps as a checklist, child indented by derived depth.
      expect(md, contains('- [x] Probe attach'));
      expect(md, contains('- [ ] Chamber run'));
      expect(md, contains('  - [ ] Log temps'));
      // FULL log — the older-than-period note is included too.
      expect(md, contains('Older context note'));
      expect(md, contains('Vout ~ 5V stable'));
      expect(md, contains('**Bold** result\n- item A\n- item B'));
      // Empty-log task still gets its section.
      expect(md, contains('No notes yet.'));
    });

    test('entry headers carry type, timestamp and in-period mark', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final md = svc.tasksNotesToMarkdown(await buildData());
      // In-period entries are marked…
      expect(md, contains('**✅ 2026-11-18 10:30 · Pass** _(in period)_'));
      expect(md, contains('**⛔ 2026-11-21 08:00 · Blocked** _(in period)_'));
      // …the pre-period entry is NOT marked.
      expect(md, contains('**📝 2026-11-12 09:00 · Note**\n'));
      expect(md, isNot(contains('2026-11-12 09:00 · Note** _(in period)_')));
    });

    test('task set matches the report: overdue-only in, out-of-range out',
        () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final md = svc.tasksNotesToMarkdown(await buildData());
      expect(md, contains('Old overdue chore')); // overdue-only task
      expect(md, isNot(contains('Unrelated future task')));
    });

    test('checkbox selection (onlyUids) restricts the export', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final md = svc.tasksNotesToMarkdown(await buildData(onlyUids: {'t2'}));
      expect(md, contains('Label redesign'));
      expect(md, isNot(contains('Thermal validation')));
      expect(md, isNot(contains('Old overdue chore')));
    });

    test('attachments: image link + file name chip', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final md = svc.tasksNotesToMarkdown(await buildData());
      expect(md, contains('![shot.png](${smallImage.path})'));
      expect(md, contains('📎 report.pdf'));
    });

    test('Chinese localization', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final md = svc.tasksNotesToMarkdown(await buildData(),
          lang: ReportLanguage.chinese);
      expect(md, contains('TaskFlow 任务笔记 — '));
      expect(md, contains('执行日志'));
      expect(md, contains('（期内）'));
      expect(md, contains('**描述**'));
      expect(md, contains('**子步骤 (1/3)**'));
      expect(md, contains('## 通用'));
      // Note content stays verbatim — never translated.
      expect(md, contains('Vout ~ 5V stable'));
    });

    test('empty range produces a valid document', () async {
      final svc = ReportService(_FakeRepo([]));
      final d = await svc.generateRange(
          DateTime(2026, 11, 16), DateTime(2026, 11, 22));
      final md = svc.tasksNotesToMarkdown(d);
      expect(md, contains('# TaskFlow Task Notes — '));
      expect(md, contains('No tasks in the selected range.'));
    });

    test('notes file name is distinct from the report file name', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final d = await buildData();
      expect(svc.suggestNotesFileName(d, 'md'),
          'TaskFlow_Notes_2026-11-16_2026-11-22.md');
      expect(svc.suggestNotesFileName(d, 'html'),
          'TaskFlow_Notes_2026-11-16_2026-11-22.html');
    });
  });

  group('tasksNotesToHtml', () {
    test('standalone styled document with TOC anchors and task cards',
        () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final html = await svc.tasksNotesToHtml(await buildData());
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<style>'));
      expect(html, contains('TaskFlow Task Notes — '));
      // TOC links resolve to real task-card anchors.
      expect(html, contains('href="#task-t1"'));
      expect(html, contains('id="task-t1"'));
      expect(html, contains('href="#task-t3"'));
      expect(html, contains('id="task-t3"'));
      // Stat chips + project sections + status/priority pills.
      expect(html, contains('Tasks'));
      expect(html, contains('<h2>Cosmo</h2>'));
      expect(html, contains('In Progress'));
      expect(html, contains('>P1<'));
      expect(html, contains('⚠ Overdue')); // t3
    });

    test('note Markdown is rendered; raw HTML is escaped; tildes survive',
        () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final html = await svc.tasksNotesToHtml(await buildData());
      expect(html, contains('<strong>Bold</strong> result'));
      expect(html, contains('<li>item A</li>'));
      // Script injection in a note must never reach the document raw.
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<script>alert')));
      // Engineering "~" must not become strikethrough (v1.5.9 rule) — the
      // package decodes &#126; back to a literal ~ in the output.
      expect(html, contains('Vout ~ 5V stable'));
      expect(html, isNot(contains('<del>')));
    });

    test('in-period entries highlighted, older ones plain', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final html = await svc.tasksNotesToHtml(await buildData());
      // t1 has 4 entries, 3 inside the period.
      expect('class="entry in-period"'.allMatches(html).length, 3);
      expect('class="entry"'.allMatches(html).length, 1);
      expect(html, contains('Older context note'));
      // Type pills use the app emoji vocabulary.
      expect(html, contains('✅ Pass'));
      expect(html, contains('⛔ Blocked'));
      expect(html, contains('📝 Note'));
    });

    test('images embedded as base64; oversized images fall back to a chip',
        () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final html = await svc.tasksNotesToHtml(await buildData());
      expect(html, contains('data:image/png;base64,'));
      expect(html, contains('📎 report.pdf'));

      // A single >2MB image is NOT embedded.
      final bigTask = Task()
        ..uid = 'big'
        ..title = 'Big screenshot'
        ..createdAt = DateTime(2026, 11, 17)
        ..executionLog = [
          entry('be', DateTime(2026, 11, 18), EntryType.note, 'see capture',
              attachments: [
                Attachment()
                  ..uid = 'ba'
                  ..name = 'big.png'
                  ..path = bigImage.path
                  ..size = bigImage.lengthSync()
                  ..type = AttachmentType.image,
              ]),
        ];
      final d = await ReportService(_FakeRepo([bigTask])).generateRange(
          DateTime(2026, 11, 16), DateTime(2026, 11, 22));
      final bigHtml = await ReportService(_FakeRepo([bigTask]))
          .tasksNotesToHtml(d);
      expect(bigHtml, isNot(contains('data:image')));
      expect(bigHtml, contains('🖼 big.png'));
    });

    test('raw HTML in notes is escaped except the app rich-text vocabulary',
        () async {
      Future<String> renderNote(String content) async {
        final t = Task()
          ..uid = 'x'
          ..title = 'X'
          ..createdAt = DateTime(2026, 11, 17)
          ..executionLog = [
            entry('xe', DateTime(2026, 11, 18), EntryType.note, content),
          ];
        final svc = ReportService(_FakeRepo([t]));
        final d = await svc.generateRange(
            DateTime(2026, 11, 16), DateTime(2026, 11, 22));
        return svc.tasksNotesToHtml(d);
      }

      // Inline event handlers and block tags must never survive raw.
      final img = await renderNote('text <img src=x onerror=alert(1)> inline');
      expect(img, isNot(contains('<img src=x')));
      expect(img, contains('&lt;img'));
      final div = await renderNote('<div onclick="alert(1)">block</div>');
      expect(div, isNot(contains('<div onclick')));
      final iframe =
          await renderNote('<iframe src="https://evil.example"></iframe>');
      expect(iframe, isNot(contains('<iframe')));

      // The app's own rich text is preserved: <br> and <font color/size>.
      final br = await renderNote('line one<br>line two');
      expect(br, contains('line one<br>line two'));
      final font = await renderNote('<font color="#FF0000">red</font>');
      expect(font, contains('<font color="#FF0000">red</font>'));
      // …but a <font> smuggling an event handler is rebuilt with ONLY the
      // validated color/size attributes — the handler never survives.
      final badFont =
          await renderNote('<font color="red" onclick="alert(1)">x</font>');
      expect(badFont, isNot(contains('onclick')));
      expect(badFont, contains('<font color="red">x</font>'));

      // javascript: link destinations are neutralized.
      final jsLink = await renderNote('[click](javascript:alert(1))');
      expect(jsLink, isNot(contains('href="javascript:')));
      expect(jsLink, contains('href="#"'));
      // http links keep working.
      final okLink = await renderNote('[site](https://example.com)');
      expect(okLink, contains('href="https://example.com"'));

      // Code fences are escaped exactly once (by the markdown package) —
      // no double-escaping, and tildes inside code stay literal.
      final code =
          await renderNote('```\n<script>code sample</script>\nVout ~ 5V\n```');
      expect(code, contains('&lt;script&gt;code sample&lt;/script&gt;'));
      expect(code, isNot(contains('&amp;lt;')));
      expect(code, contains('Vout ~ 5V'));
    });

    test('Chinese localization', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final html = await svc.tasksNotesToHtml(await buildData(),
          lang: ReportLanguage.chinese);
      expect(html, contains('TaskFlow 任务笔记 — '));
      expect(html, contains('目录'));
      expect(html, contains('期内'));
      expect(html, contains('执行日志'));
      expect(html, contains('lang="zh-CN"'));
    });

    test('empty range produces a valid document', () async {
      final svc = ReportService(_FakeRepo([]));
      final d = await svc.generateRange(
          DateTime(2026, 11, 16), DateTime(2026, 11, 22));
      final html = await svc.tasksNotesToHtml(d);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('No tasks in the selected range.'));
    });
  });

  group('Reports page — Export notes entry point', () {
    Future<void> pumpReports(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(const Size(800, 600)));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWithValue(_FakeRepo(sampleTasks())),
          ],
          child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('available before any generation; menu offers both formats',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpReports(tester, const Size(1000, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('Export notes'), findsOneWidget);
      // No report generated yet — the summary exports are absent.
      expect(find.text('Export .md'), findsNothing);

      // The controls row scrolls horizontally below the fixed-row
      // threshold; bring the dropdown into view before tapping.
      await tester.scrollUntilVisible(
        find.text('Export notes'),
        150,
        scrollable: find.descendant(
          of: find.byKey(const Key('reportsControlsScroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Export notes'));
      await tester.pumpAndSettle();
      expect(find.text('Markdown (.md)'), findsOneWidget);
      expect(find.text('Styled HTML (.html)'), findsOneWidget);
    });

    testWidgets('full action cluster never overflows at the 900px minimum',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpReports(tester, const Size(900, 600));
      // Generate via the controller (the Generate button itself may sit
      // off-screen in the horizontally scrolling controls row at 900px).
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ReportsScreen)));
      await container.read(reportControllerProvider.notifier).generate();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Header actions fit without clipping; the Export notes dropdown
      // lives in the controls row (present even off-screen).
      expect(find.text('Export notes'), findsOneWidget);
      expect(find.text('Export .md'), findsOneWidget);
      expect(find.text('Export .html'), findsOneWidget);
      expect(find.text('Email .html'), findsOneWidget);
    });
  });
}