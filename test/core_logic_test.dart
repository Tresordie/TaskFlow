import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/markdown/line_breaks.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/models/work_log.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/data/services/ai_service.dart';
import 'package:taskflow/data/services/report_service.dart';
import 'package:taskflow/presentation/reports/reports_screen.dart';
import 'package:taskflow/presentation/shared/markdown_input.dart';
import 'package:taskflow/presentation/shared/suggestion_field.dart';
import 'package:taskflow/providers/ai_provider.dart';
import 'package:taskflow/providers/task_providers.dart';

/// In-memory [TaskRepository] so report aggregation (_build) can be
/// unit-tested without opening an Isar database.
class _FakeRepo extends TaskRepository {
  final List<Task> _tasks;
  _FakeRepo(this._tasks);

  @override
  Future<List<Task>> getAllTasks() async => _tasks;
}

/// Pure-logic tests (no Isar / plugins required).
void main() {
  group('ReportService.rangeFor', () {
    test('daily range covers exactly one calendar day', () {
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.daily, DateTime(2026, 7, 21, 15, 30));
      expect(start, DateTime(2026, 7, 21));
      expect(end, DateTime(2026, 7, 22));
    });

    test('weekly range starts on Monday', () {
      // 2026-07-15 is a Wednesday.
      final (start, end) =
          ReportService.rangeFor(ReportPeriod.weekly, DateTime(2026, 7, 15));
      expect(start, DateTime(2026, 7, 13)); // Monday
      expect(end, DateTime(2026, 7, 20));
      expect(start.weekday, DateTime.monday);
    });

    test('weekly range handles a Monday anchor', () {
      final (start, end) =
          ReportService.rangeFor(ReportPeriod.weekly, DateTime(2026, 7, 13));
      expect(start, DateTime(2026, 7, 13));
      expect(end, DateTime(2026, 7, 20));
    });

    test('weekly range handles a Sunday anchor', () {
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.weekly, DateTime(2026, 7, 19)); // Sunday
      expect(start, DateTime(2026, 7, 13));
      expect(end, DateTime(2026, 7, 20));
    });

    test('monthly range covers the calendar month', () {
      final (start, end) =
          ReportService.rangeFor(ReportPeriod.monthly, DateTime(2026, 7, 21));
      expect(start, DateTime(2026, 7, 1));
      expect(end, DateTime(2026, 8, 1));
    });

    test('monthly range rolls over the year boundary', () {
      final (start, end) =
          ReportService.rangeFor(ReportPeriod.monthly, DateTime(2026, 12, 5));
      expect(start, DateTime(2026, 12, 1));
      expect(end, DateTime(2027, 1, 1));
    });

    test('yearly range covers the calendar year', () {
      final (start, end) =
          ReportService.rangeFor(ReportPeriod.yearly, DateTime(2026, 7, 21));
      expect(start, DateTime(2026, 1, 1));
      expect(end, DateTime(2027, 1, 1));
    });
  });

  group('ReportService.generate onlyUids task selection', () {
    List<Task> sampleTasks() => [
          Task()
            ..uid = 'a'
            ..title = 'done task'
            ..status = TaskStatus.completed
            ..createdAt = DateTime(2026, 7, 13)
            ..completedAt = DateTime(2026, 7, 15),
          Task()
            ..uid = 'b'
            ..title = 'wip task'
            ..status = TaskStatus.inProgress
            ..createdAt = DateTime(2026, 7, 13)
            ..startedAt = DateTime(2026, 7, 14),
          Task()
            ..uid = 'c'
            ..title = 'planned task'
            ..status = TaskStatus.planned
            ..createdAt = DateTime(2026, 7, 14),
        ];

    test('null onlyUids aggregates every task in range', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final d = await svc.generate(ReportPeriod.weekly, DateTime(2026, 7, 15));
      expect(d.touchedTasks.map((t) => t.uid).toSet(), {'a', 'b', 'c'});
    });

    test('onlyUids restricts aggregation to the checked tasks', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final d = await svc.generate(
        ReportPeriod.weekly,
        DateTime(2026, 7, 15),
        onlyUids: {'a', 'c'},
      );
      expect(d.touchedTasks.map((t) => t.uid).toSet(), {'a', 'c'});
      expect(d.completed.map((t) => t.uid), ['a']);
      expect(d.inProgress, isEmpty); // 'b' was deselected
      expect(d.planned.map((t) => t.uid), ['c']);
    });

    test('generateRange honours onlyUids too', () async {
      final svc = ReportService(_FakeRepo(sampleTasks()));
      final d = await svc.generateRange(
        DateTime(2026, 7, 13),
        DateTime(2026, 7, 19),
        onlyUids: {'b'},
      );
      expect(d.touchedTasks.map((t) => t.uid).toSet(), {'b'});
    });
  });

  group('ReportController persists report across widget rebuilds', () {
    test('report state survives a widget rebuild (navigation away & back)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(reportControllerProvider.notifier);

      // Simulate picker interactions plus a generated report + user edits.
      // Checkbox toggles only affect the next generation, so the report
      // set afterwards is not disturbed by them.
      notifier.setTaskPickerOpen(false);
      notifier.toggleTask('uid-1', false); // uncheck one task
      notifier.setMarkdown('# Weekly report');
      notifier.setEditing(true);

      // Navigating away disposes the widget; navigating back rebuilds it
      // and re-reads the same (non-autoDispose) provider — the state must
      // be exactly as left, NOT reset to defaults.
      final s = container.read(reportControllerProvider);
      expect(s.markdown, '# Weekly report');
      expect(s.editing, isTrue);
      expect(s.taskPickerOpen, isFalse);
      expect(s.excludedUids, {'uid-1'});
    });

    test('changing the period keeps the displayed report (next gen only)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(reportControllerProvider.notifier);

      notifier.setMarkdown('# report');
      notifier.setPeriod(ReportPeriod.monthly);
      final s = container.read(reportControllerProvider);
      expect(s.period, ReportPeriod.monthly);
      expect(s.markdown, '# report'); // report kept until Generate is pressed
    });

    test('changing filters keeps the displayed report (next gen only)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(reportControllerProvider.notifier);

      notifier.setMarkdown('# report');
      notifier.setFilterProject('Cosmo');
      notifier.clearFilters();
      final s = container.read(reportControllerProvider);
      expect(s.fProject, isNull);
      expect(s.markdown, '# report'); // report kept until Generate is pressed
    });

    test('toggling a task keeps the displayed report (affects next gen only)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(reportControllerProvider.notifier);

      notifier.setMarkdown('# report');
      notifier.toggleTask('uid-x', false);
      final s = container.read(reportControllerProvider);
      expect(s.excludedUids, {'uid-x'});
      expect(s.markdown, '# report'); // report kept until Generate is pressed
    });
  });

  group('ReportData', () {
    ReportData makeData(ReportPeriod period, DateTime start, DateTime end) =>
        ReportData(
          period: period,
          start: start,
          end: end,
          completed: [],
          inProgress: [],
          planned: [],
          overdue: [],
          logActivity: {},
          entryPass: 0,
          entryFail: 0,
          entryBlocked: 0,
          entryNote: 0,
          subStepsDone: 0,
          subStepsTotal: 0,
        );

    test('titlePrefix formats per period', () {
      expect(
        makeData(ReportPeriod.daily, DateTime(2026, 7, 21),
                DateTime(2026, 7, 22))
            .titlePrefix,
        '2026-07-21',
      );
      expect(
        makeData(ReportPeriod.weekly, DateTime(2026, 7, 13),
                DateTime(2026, 7, 20))
            .titlePrefix,
        '2026-W29',
      );
      expect(
        makeData(ReportPeriod.monthly, DateTime(2026, 7, 1),
                DateTime(2026, 8, 1))
            .titlePrefix,
        '2026-07',
      );
      expect(
        makeData(
                ReportPeriod.yearly, DateTime(2026, 1, 1), DateTime(2027, 1, 1))
            .titlePrefix,
        '2026',
      );
    });

    test('rangeLabel shows inclusive start and last day', () {
      final d = makeData(
          ReportPeriod.weekly, DateTime(2026, 7, 13), DateTime(2026, 7, 20));
      expect(d.rangeLabel, '2026-07-13 → 2026-07-19');
    });

    test('completionRate is 0 when nothing was touched', () {
      final d = makeData(
          ReportPeriod.daily, DateTime(2026, 7, 21), DateTime(2026, 7, 22));
      expect(d.completionRate, 0);
      expect(d.totalTouched, 0);
    });

    test('completionRate counts completed vs touched tasks', () {
      final done = Task()
        ..uid = 'a'
        ..title = 'done'
        ..createdAt = DateTime(2026, 7, 20);
      final wip = Task()
        ..uid = 'b'
        ..title = 'wip'
        ..createdAt = DateTime(2026, 7, 20);
      final d = ReportData(
        period: ReportPeriod.daily,
        start: DateTime(2026, 7, 21),
        end: DateTime(2026, 7, 22),
        completed: [done],
        inProgress: [wip],
        planned: [],
        overdue: [],
        logActivity: {},
        entryPass: 0,
        entryFail: 0,
        entryBlocked: 0,
        entryNote: 0,
        subStepsDone: 0,
        subStepsTotal: 0,
      );
      expect(d.totalTouched, 2);
      expect(d.completionRate, 0.5);
    });
  });

  group('Report templates (optimized 5-section format)', () {
    ReportData sampleWeekly() {
      final done = Task()
        ..uid = 'a'
        ..title = 'idbase64 fix deployed'
        ..tags = ['Cosmo']
        ..project = 'Cosmo'
        ..priority = Priority.p1High
        ..status = TaskStatus.completed
        ..createdAt = DateTime(2026, 7, 13)
        ..completedAt = DateTime(2026, 7, 15);

      final blockedTask = Task()
        ..uid = 'b'
        ..title = 'PDA data sync'
        ..tags = ['Cosmo']
        ..project = 'Cosmo'
        ..status = TaskStatus.inProgress
        ..createdAt = DateTime(2026, 7, 13)
        ..startedAt = DateTime(2026, 7, 14);

      final wip = Task()
        ..uid = 'c'
        ..title = 'brake sensor validation'
        ..tags = ['Metro']
        ..project = 'Metro'
        ..status = TaskStatus.inProgress
        ..createdAt = DateTime(2026, 7, 13)
        ..subSteps = [
          SubStep()
            ..uid = 's1'
            ..title = 'sample'
            ..completed = true,
          SubStep()
            ..uid = 's2'
            ..title = 'report'
            ..completed = false,
        ];

      final overdue = Task()
        ..uid = 'd'
        ..title = 'solar fixture ETA'
        ..tags = ['Metro']
        ..project = 'Metro'
        ..status = TaskStatus.planned
        ..createdAt = DateTime(2026, 7, 13)
        ..dueDate = DateTime(2026, 7, 16);

      final blockedEntry = ExecutionEntry()
        ..uid = 'e1'
        ..timestamp = DateTime(2026, 7, 15)
        ..content = 'waiting on vendor quote'
        ..type = EntryType.blocked;

      return ReportData(
        period: ReportPeriod.weekly,
        start: DateTime(2026, 7, 13),
        end: DateTime(2026, 7, 20),
        completed: [done],
        inProgress: [blockedTask, wip],
        planned: [overdue],
        overdue: [overdue],
        logActivity: {
          blockedTask: [blockedEntry],
        },
        entryPass: 0,
        entryFail: 0,
        entryBlocked: 1,
        entryNote: 0,
        subStepsDone: 1,
        subStepsTotal: 2,
      );
    }

    test('markdown has the 5 numbered sections in order', () {
      final md = ReportService(TaskRepository()).toMarkdown(sampleWeekly());
      final sections = [
        '## 1. Status Dashboard',
        '## 2. Executive Summary',
        '## 3. Progress Details',
        '## 4. Plan for Next Week',
        '## 5. Asks / Decisions Needed',
      ];
      var idx = -1;
      for (final s in sections) {
        final found = md.indexOf(s);
        expect(found, greaterThan(idx), reason: '$s missing or out of order');
        idx = found;
      }
    });

    test('markdown groups by project and computes RAG status', () {
      final md = ReportService(TaskRepository()).toMarkdown(sampleWeekly());
      // Cosmo has a blocked entry -> At Risk (red).
      expect(md, contains('| Cosmo | 🔴 At Risk |'));
      // Metro has an overdue task -> Watch (yellow).
      expect(md, contains('| Metro | 🟡 Watch |'));
      // Executive summary sub-headers.
      expect(md, contains('### ✅ Achievements (Done / Closed)'));
      expect(md, contains('### 🚧 In Progress (Watch)'));
      expect(md, contains('### ⚠️ Risks / Blockers'));
    });

    test('chinese markdown renders localized headers', () {
      final md = ReportService(TaskRepository())
          .toMarkdown(sampleWeekly(), lang: ReportLanguage.chinese);
      expect(md, contains('## 1. 状态仪表盘'));
      expect(md, contains('## 2. 执行摘要'));
      expect(md, contains('## 3. 进度明细'));
      expect(md, contains('## 4. 下周计划'));
      expect(md, contains('## 5. 需决策事项'));
      expect(md, contains('🔴 有风险'));
    });

    test('english report contains no Chinese characters anywhere', () {
      // Regression: the dashboard "progress" column header returned '进度'
      // in BOTH language branches, leaking Chinese into English reports.
      // Scan the whole output so any future hardcoded string fails here.
      final service = ReportService(TaskRepository());
      final md = service.toMarkdown(sampleWeekly());
      final html = service.toHtml(sampleWeekly());
      final cjk = RegExp(r'[\u4e00-\u9fff]');
      expect(
        cjk.hasMatch(md),
        isFalse,
        reason: 'English markdown leaked Chinese: '
            '${cjk.allMatches(md).map((m) => m.group(0)).toSet()}',
      );
      expect(
        cjk.hasMatch(html),
        isFalse,
        reason: 'English HTML leaked Chinese: '
            '${cjk.allMatches(html).map((m) => m.group(0)).toSet()}',
      );
      expect(md, contains('| Project | Status | Progress | Headline |'));
    });

    test('AI summaries override the details column', () {
      final data = sampleWeekly();
      final target = data.inProgress.first; // PDA data sync (Cosmo)
      final md = ReportService(TaskRepository()).toMarkdown(
        data,
        aiSummaries: {target: 'AI: vendor quote pending, ETA next Tue'},
      );
      expect(md, contains('AI: vendor quote pending, ETA next Tue'));
    });

    test('multi-line AI summaries render as a bullet list in Details', () {
      final data = sampleWeekly();
      final target = data.completed.first; // idbase64 fix deployed
      final md = ReportService(TaskRepository()).toMarkdown(
        data,
        aiSummaries: {
          target: 'Validated factory release\nClosed after PVT sign-off'
        },
      );
      // Details cell becomes a <br>-separated bullet list, replacing the
      // heuristic "done 07-15" text in that cell ...
      expect(
        md,
        contains(
            '| idbase64 fix deployed | 🟩 | • Validated factory release<br>• Closed after PVT sign-off |'),
      );
      // ... and the first bullet shows up under Achievements.
      expect(md, contains('  - Validated factory release'));
    });

    test('html renders multi-line AI summaries as a real list', () {
      final data = sampleWeekly();
      final target = data.completed.first;
      final html = ReportService(TaskRepository()).toHtml(
        data,
        aiSummaries: {
          target: 'Validated factory release\nClosed after PVT sign-off'
        },
      );
      expect(html, contains('<ul class="details" style="'));
      expect(html, contains('<li style="'));
      expect(html, contains('>Validated factory release</li>'));
      expect(html, contains('>Closed after PVT sign-off</li>'));
      // Executive summary callout boxes.
      expect(html, contains('class="sumbox achv"'));
      expect(html, contains('class="sumbox watch"'));
      expect(html, contains('class="sumbox risk"'));
    });

    test('html is paste-proof: inline styles survive Gmail sanitization', () {
      // Gmail strips <style> blocks and class attributes from pasted HTML
      // but keeps inline style attributes, so every visual property must be
      // duplicated inline while the classes stay for the browser view.
      final data = sampleWeekly();
      final target = data.completed.first;
      final html = ReportService(TaskRepository()).toHtml(
        data,
        aiSummaries: {
          target: 'Validated factory release\nClosed after PVT sign-off'
        },
      );
      // Tables keep borders/collapse/width.
      expect(
          html,
          contains(
              'style="width:100%;border-collapse:collapse;border-spacing:0;'));
      // Anti-stripe: if Gmail strips border-collapse, border-spacing:0 and
      // the cellspacing/cellpadding attributes still force zero cell gaps.
      expect(html, contains('<table cellspacing="0" cellpadding="0"'));
      // Every table in the document must carry the zero-spacing attribute.
      expect('cellspacing="0"'.allMatches(html).length,
          '<table'.allMatches(html).length);
      // Centered headers must not carry a duplicate text-align declaration
      // (a sanitizer that keeps the first occurrence would left-align them).
      expect(html, isNot(contains('background:#F1F5F9;text-align:center;')));
      // Header and body cells carry their own padding/alignment.
      expect(html, contains('text-transform:uppercase;'));
      expect(html, contains('vertical-align:top;'));
      expect(html, contains('text-align:center;'));
      expect(html, contains('font-weight:600;'));
      // RAG pills keep their shape and tint without the .rag class.
      expect(html, contains('display:inline-block;padding:2px 10px;'));
      expect(html, contains('border-radius:999px;'));
      expect(html, contains('background:#EF44441a;color:#EF4444')); // At Risk
      expect(html, contains('background:#F59E0B1a;color:#F59E0B')); // Watch
      // Callout boxes keep the colored left border + tinted background.
      expect(html, contains('border-left:3px solid #22C55E'));
      expect(html, contains('background:#F0FDF4'));
      expect(html, contains('border-left:3px solid #3B82F6'));
      expect(html, contains('background:#EFF6FF'));
      expect(html, contains('border-left:3px solid #F59E0B'));
      expect(html, contains('background:#FFFBEB'));
      // Lists keep indentation and spacing.
      expect(html, contains('style="margin:6px 0 0;padding-left:20px;"'));
      expect(html, contains('style="margin:0;padding-left:16px;"'));
      // Classes are retained so the standalone file looks identical.
      expect(html, contains('class="wrap"'));
      expect(html, contains('class="rag"'));
      expect(html, contains('class="details"'));
    });

    test('email html matches the reference Gmail-safe template', () {
      final data = sampleWeekly();
      final service = ReportService(TaskRepository());
      final html = service.toHtml(data, email: true);
      // Rule 3 — pure inline styles: no <style> block, no CSS variables.
      expect(html, isNot(contains('<style>')));
      expect(html, isNot(contains('var(')));
      // Rule 1 — table-based layout: 100% outer table with vertical
      // padding, centering a max-width:900px content table.
      expect(
          html,
          contains(
              'style="background-color:#ffffff; margin:0; padding:20px 0;"'));
      expect(html, contains('<td align="center">'));
      expect(
          html, contains('max-width:900px; padding:0 16px; text-align:left;'));
      // Rule 2 — white background everywhere, no full-width colored band.
      expect(
          html,
          contains(
              '<body style="margin:0; padding:0; background-color:#ffffff; font-family:'));
      expect(html, isNot(contains('#F8FAFC')));
      // Rule 4 — 6-digit hex only: Google-palette solid pills, never
      // 8-digit alpha hex or rgba().
      expect(html, contains('background-color:#FCE8E6;color:#C5221F')); // red
      expect(html, contains('background-color:#FEF7E0;color:#B06000')); // amber
      expect(html, isNot(contains('1a;'))); // no #RRGGBBAA tints
      expect(html, isNot(contains('rgba(')));
      // Rule 5 — the ONLY border-radius is the decorative 12px pill; no
      // radius on layout, no overflow:hidden / flexbox / grid.
      expect(html, contains('border-radius:12px;'));
      expect(html.replaceAll('border-radius:12px;', ''),
          isNot(contains('border-radius')));
      expect(html, isNot(contains('overflow:hidden')));
      expect(html, isNot(contains('display:flex')));
      expect(html, isNot(contains('display:grid')));
      // Reference details: header-row background on the <tr>, 4px sumbox
      // accent, data tables carry width/border attributes, footer is a div.
      expect(html, contains('<tr style="background-color:#F1F5F9;">'));
      expect(html, contains('border-left:4px solid'));
      expect(
          html,
          contains(
              '<table width="100%" border="0" cellspacing="0" cellpadding="0" style="border-collapse:collapse;'));
      expect(html, contains('<div style="margin-top:36px;'));
      expect(html, isNot(contains('<footer')));
      // Zero cell spacing on every table (anti-stripe), layout included.
      expect('cellspacing="0"'.allMatches(html).length,
          '<table'.allMatches(html).length);
      // Closes the nested layout tables before </body>.
      expect(html, contains('</table>\n</body>\n</html>'));
      // English email contains no Chinese characters anywhere.
      expect(RegExp(r'[一-鿿]').hasMatch(html), isFalse);
    });

    test('AI titles replace task titles across sections', () {
      final data = sampleWeekly();
      final target = data.completed.first; // idbase64 fix deployed (Cosmo)
      final md = ReportService(TaskRepository()).toMarkdown(
        data,
        aiTitles: {target: 'idbase64 修复已上线'},
      );
      // Translated title shows up ...
      expect(md, contains('idbase64 修复已上线'));
      // ... and the original English title for that task is gone.
      expect(md, isNot(contains('idbase64 fix deployed')));
      // A task without a translation keeps its original title.
      expect(md, contains('brake sensor validation'));
    });

    test('markdown surfaces blocked entries as asks', () {
      final md = ReportService(TaskRepository()).toMarkdown(sampleWeekly());
      expect(md, contains('needs decision: waiting on vendor quote'));
    });

    test('html renders dashboard and all five sections', () {
      final html = ReportService(TaskRepository()).toHtml(sampleWeekly());
      expect(html, contains('1. Status Dashboard'));
      expect(html, contains('2. Executive Summary'));
      expect(html, contains('3. Progress Details'));
      expect(html, contains('4. Plan for Next Week'));
      expect(html, contains('5. Asks / Decisions Needed'));
      expect(html, contains('🔴 At Risk'));
      expect(html, contains('🟡 Watch'));
    });

    test('markdownToStyledHtml renders edited markdown to a styled document',
        () {
      final service = ReportService(TaskRepository());
      const edited = '# My Custom Title\n\n'
          '| A | B |\n'
          '|---|---|\n'
          '| x<br>y | z |\n\n'
          '- edited bullet\n';
      final html = service.markdownToStyledHtml(edited, title: '2026-W22');
      // Reflects the user's edits rather than regenerating from ReportData.
      expect(html, contains('My Custom Title'));
      expect(html, contains('edited bullet'));
      // Tables and inline <br> survive the conversion.
      expect(html, contains('<table>'));
      expect(html, contains('x<br>y'));
      expect(html, isNot(contains('&lt;br&gt;')));
      // Standalone styled document shell.
      expect(html, contains('<title>2026-W22</title>'));
      expect(html, contains('<style>'));
      expect(html, contains('class="wrap"'));
    });
  });

  group('AiConfig', () {
    test('isConfigured requires all three fields', () {
      expect(const AiConfig().isConfigured, isFalse);
      // Model now defaults to deepseek-v4-pro, so baseUrl + apiKey alone
      // count as configured; an explicitly emptied model still blocks.
      expect(
        const AiConfig(baseUrl: 'https://api.deepseek.com', apiKey: 'sk-1')
            .isConfigured,
        isTrue,
      );
      expect(
        const AiConfig(
                baseUrl: 'https://api.deepseek.com', apiKey: 'sk-1', model: '')
            .isConfigured,
        isFalse,
      );
      expect(
        const AiConfig(
          baseUrl: 'https://api.deepseek.com',
          apiKey: 'sk-1',
          model: 'deepseek-v4-pro',
        ).isConfigured,
        isTrue,
      );
    });

    test('whitespace-only values count as unconfigured', () {
      expect(
        const AiConfig(baseUrl: '  ', apiKey: 'sk-1', model: 'm').isConfigured,
        isFalse,
      );
    });

    test('copyWith overrides selectively', () {
      const c = AiConfig(baseUrl: 'u', apiKey: 'k', model: 'm');
      final c2 = c.copyWith(model: 'm2');
      expect(c2.baseUrl, 'u');
      expect(c2.apiKey, 'k');
      expect(c2.model, 'm2');
    });

    test('model defaults to deepseek-v4-pro', () {
      expect(AiConfig.defaultModel, 'deepseek-v4-pro');
      expect(const AiConfig().model, 'deepseek-v4-pro');
    });
  });

  group('Model enums', () {
    test('priority short labels', () {
      expect(Priority.p0Critical.shortLabel, 'P0');
      expect(Priority.p1High.shortLabel, 'P1');
      expect(Priority.p2Medium.shortLabel, 'P2');
      expect(Priority.p3Low.shortLabel, 'P3');
    });

    test('status labels', () {
      expect(TaskStatus.planned.label, 'Planned');
      expect(TaskStatus.inProgress.label, 'In Progress');
      expect(TaskStatus.completed.label, 'Completed');
      expect(TaskStatus.archived.label, 'Archived');
    });
  });

  group('TaskDraft', () {
    test('defaults', () {
      const d = TaskDraft(title: 'x');
      expect(d.priority, Priority.p2Medium);
      expect(d.tags, isEmpty);
      expect(d.subSteps, isEmpty);
      expect(d.dueDate, isNull);
      expect(d.description, isNull);
    });
  });

  group('AiService (regression: "Invalid argument (string)")', () {
    test('enhanceTask sends a UTF-8 body containing Chinese task titles',
        () async {
      // Before the fix, HttpClientRequest.write() encoded the JSON body
      // as latin1 (the default) and threw ArgumentError "Invalid
      // argument (string): Contains invalid characters." for every task
      // whose title/digest contained Chinese — breaking AI summaries and
      // translation for the whole report.
      String? received;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        received = await utf8.decodeStream(req);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'TITLE: Draft Oak test plan\n'
                    'SUMMARY: PCBA BFT validated, 2 log entries reviewed.'
              }
            }
          ]
        }));
        await req.response.close();
      });

      final ai = AiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'sk-test',
        model: 'm',
      );
      final task = Task()
        ..uid = 'cn'
        ..title = 'Oak的test plan起草'
        ..status = TaskStatus.inProgress;

      final r = await ai.enhanceTask(task, chinese: false);

      // The Chinese title crossed the wire intact ...
      expect(received, contains('Oak的test plan起草'));
      // ... and the two-line reply was parsed.
      expect(r.title, 'Draft Oak test plan');
      expect(r.summary, contains('PCBA'));
      await server.close(force: true);
    });

    test('bare SUMMARY: line followed by bullets is fully captured', () async {
      // Models often emit the bullets on the lines AFTER a bare
      // "SUMMARY:" — the old parser only read same-line text, so the
      // summary came back empty and (typically completed) tasks silently
      // fell back to the heuristic "done MM-dd" Details.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decodeStream(req);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'TITLE: Monolith PVT release validation\n'
                    'SUMMARY:\n'
                    '- Validated V2 factory release\n'
                    '- Closed after PVT sign-off'
              }
            }
          ]
        }));
        await req.response.close();
      });

      final ai = AiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'sk-test',
        model: 'm',
      );
      final task = Task()
        ..uid = 'done'
        ..title = 'Monolith PVT 验证'
        ..status = TaskStatus.completed;

      final r = await ai.enhanceTask(task, chinese: false);
      expect(r.title, 'Monolith PVT release validation');
      expect(
          r.summary, 'Validated V2 factory release\nClosed after PVT sign-off');
      await server.close(force: true);
    });

    test('long bullets are kept in full and max_tokens leaves headroom',
        () async {
      // v1.2.7: max_tokens was 200 — a long TITLE line ate the budget and
      // replies were cut off before/inside SUMMARY (completed tasks fell
      // back to "done MM-dd", bullets ended in fragments like "BMS").
      // The parser also capped each bullet at 120 chars. Both are gone.
      final longBullet =
          'Validated the V2 factory release build across all three ATE '
          'stations and closed the task after PVT sign-off with the CM '
          'quality team (well over one hundred and twenty characters)';
      String? received;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        received = await utf8.decodeStream(req);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'TITLE: Monolith PVT release validation\n'
                    'SUMMARY:\n'
                    '- $longBullet'
              }
            }
          ]
        }));
        await req.response.close();
      });

      final ai = AiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'sk-test',
        model: 'm',
      );
      final task = Task()
        ..uid = 'long'
        ..title = 'Monolith-2025.7.112 V2 PVT factory release validation'
        ..status = TaskStatus.completed;

      final r = await ai.enhanceTask(task, chinese: false);
      expect(received, contains('"max_tokens":1000'));
      expect(r.summary, longBullet); // full length, no 120-char cut
      expect(r.summary, isNot(contains('…')));
      await server.close(force: true);
    });

    test('reply truncated to a bare SUMMARY: yields an empty summary',
        () async {
      // If a provider still cuts the reply right after "SUMMARY:", the
      // parser must return an empty summary (aiEnhance then drops it and
      // the Reports screen shows the failure banner) — never the literal
      // "SUMMARY:" marker as a Details bullet.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decodeStream(req);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'TITLE: Monolith PVT release validation\nSUMMARY:'
              }
            }
          ]
        }));
        await req.response.close();
      });

      final ai = AiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'sk-test',
        model: 'm',
      );
      final task = Task()
        ..uid = 'cut'
        ..title = 'Monolith PVT 验证'
        ..status = TaskStatus.completed;

      final r = await ai.enhanceTask(task, chinese: false);
      expect(r.summary, isEmpty);
      await server.close(force: true);
    });

    test('sloppy pasted endpoint settings are sanitized', () {
      final ai = AiService(
        baseUrl: ' https：//api.example.com／compatible-mode/v1\n',
        apiKey: ' sk-abc\n',
        model: 'm',
      );
      expect(ai.baseUrl, 'https://api.example.com/compatible-mode/v1');
      expect(ai.apiKey, 'sk-abc');
    });

    test('base URL without scheme fails with an actionable message', () {
      final ai = AiService(
        baseUrl: 'api.example.com/v1',
        apiKey: 'k',
        model: 'm',
      );
      final task = Task()
        ..uid = 'x'
        ..title = 't';
      expect(
        () => ai.enhanceTask(task, chinese: false),
        throwsA(isA<AiServiceException>()
            .having((e) => e.message, 'message', contains('Settings → AI'))),
      );
    });
  });

  group('AI enhance prompt language contract', () {
    test('English prompt demands English output and forbids Chinese', () {
      final p = AiService.enhancePromptForTest(false);
      // The English branch must explicitly tell the model to write in
      // English and never emit Chinese — the digest it receives is usually
      // Chinese, so without this rule the SUMMARY bullets leaked Chinese.
      expect(p, contains('English'));
      expect(p, contains('ZERO Chinese'));
      // The English prompt template itself must contain no CJK characters.
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(p), isFalse,
          reason: 'English prompt must not contain Chinese characters');
    });

    test('Chinese prompt is written in Chinese', () {
      final p = AiService.enhancePromptForTest(true);
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(p), isTrue);
    });
  });

  group('Reasoning-model detection (temperature handling)', () {
    // Reasoning models reject any temperature other than 1 (HTTP 400
    // "invalid temperature"); _chat omits the parameter for these.
    test('known reasoning models are detected', () {
      for (final m in [
        'kimi-k3',
        'kimi-k3-thinking',
        'deepseek-reasoner',
        'deepseek-v4-pro',
        'qwq-32b',
        'o1',
        'o3-mini',
        'o4-mini',
        'some-reasoning-model',
      ]) {
        expect(AiService.isReasoningModelForTest(m), isTrue, reason: m);
      }
    });

    test('regular chat models are NOT flagged', () {
      for (final m in [
        'deepseek-chat',
        'gpt-4o',
        'gpt-4o-mini',
        'qwen-plus',
        'gpt-4.1',
      ]) {
        expect(AiService.isReasoningModelForTest(m), isFalse, reason: m);
      }
    });
  });

  group('Nested sub-steps (max 3 levels)', () {
    SubStep step(String uid, {String? parent, int depth = 0}) => SubStep()
      ..uid = uid
      ..title = 'step $uid'
      ..parentUid = parent
      ..depth = depth;

    test('maxDepth allows exactly 3 levels (0, 1, 2)', () {
      expect(SubStep.maxDepth, 2);
    });

    test('display order is DFS: children follow their parent', () {
      // Flat storage order: children are appended at the end as they are
      // created, so visual order must be rebuilt via parentUid links.
      final steps = [
        step('a'),
        step('b'),
        step('a1', parent: 'a', depth: 1),
        step('a2', parent: 'a', depth: 1),
        step('a1x', parent: 'a1', depth: 2),
        step('b1', parent: 'b', depth: 1),
      ];
      final ordered = subStepsInDisplayOrder(steps).map((s) => s.uid).toList();
      expect(ordered, ['a', 'a1', 'a1x', 'a2', 'b', 'b1']);
    });

    test('orphans (missing parent) fall back to top level', () {
      final steps = [
        step('a'),
        step('x', parent: 'ghost', depth: 1),
      ];
      final ordered = subStepsInDisplayOrder(steps).map((s) => s.uid).toList();
      expect(ordered, ['a', 'x']);
    });

    test('descendant uids include the step and all nested children', () {
      final steps = [
        step('a'),
        step('b'),
        step('a1', parent: 'a', depth: 1),
        step('a1x', parent: 'a1', depth: 2),
        step('b1', parent: 'b', depth: 1),
      ];
      final a = steps.firstWhere((s) => s.uid == 'a');
      expect(subStepDescendantUids(steps, a), {'a', 'a1', 'a1x'});

      final a1 = steps.firstWhere((s) => s.uid == 'a1');
      expect(subStepDescendantUids(steps, a1), {'a1', 'a1x'});
    });

    test('subtree end index places the add-child field after all kids', () {
      final ordered = subStepsInDisplayOrder([
        step('a'),
        step('b'),
        step('a1', parent: 'a', depth: 1),
        step('a2', parent: 'a', depth: 1),
        step('a1x', parent: 'a1', depth: 2),
        step('b1', parent: 'b', depth: 1),
      ]);
      // DFS order: a, a1, a1x, a2, b, b1
      expect(subStepSubtreeEndIndex(ordered, 'a'), 3); // after a2
      expect(subStepSubtreeEndIndex(ordered, 'a1'), 2); // after a1x
      expect(subStepSubtreeEndIndex(ordered, 'b'), 5); // after b1
      expect(subStepSubtreeEndIndex(ordered, 'ghost'), -1);
    });

    test('normalize repairs sign-bit-corrupted depths (v1.4.9 migration)', () {
      // Regression (v1.4.12): the v1.4.9 Isar migration wrote the
      // sort-encoded default for the new depth field, flipping the sign
      // bit — roots read as (1 << 63) instead of 0, and the corruption
      // then propagated through `parent.depth + 1`. This is exactly what
      // was found in the live database (all checklist items rendered
      // flat). depth must be re-derived from the parentUid chain.
      final signBit = 1 << 63; // -9223372036854775808 (int64 min)
      final steps = [
        step('root', depth: signBit),
        step('child', parent: 'root', depth: signBit + 1),
        step('grand', parent: 'child', depth: signBit + 2),
        step('root2', depth: signBit),
      ];
      expect(normalizeSubStepDepths(steps), isTrue);
      final depthByUid = {for (final s in steps) s.uid: s.depth};
      expect(depthByUid['root'], 0);
      expect(depthByUid['child'], 1);
      expect(depthByUid['grand'], 2);
      expect(depthByUid['root2'], 0);
    });

    test('normalize is a no-op when depths already match the chain', () {
      final steps = [
        step('a'),
        step('a1', parent: 'a', depth: 1),
        step('a1x', parent: 'a1', depth: 2),
      ];
      expect(normalizeSubStepDepths(steps), isFalse);
      expect(steps.map((s) => s.depth).toList(), [0, 1, 2]);
    });

    test('normalize treats orphans (missing parent) as top level', () {
      final steps = [
        step('a'),
        step('x', parent: 'ghost', depth: 5),
      ];
      expect(normalizeSubStepDepths(steps), isTrue);
      expect(steps.firstWhere((s) => s.uid == 'x').depth, 0);
    });

    test('normalize survives a corrupted parent cycle without hanging', () {
      final steps = [
        step('a', parent: 'b', depth: 0),
        step('b', parent: 'a', depth: 0),
      ];
      normalizeSubStepDepths(steps); // must terminate
      for (final s in steps) {
        expect(s.depth, greaterThanOrEqualTo(0));
        expect(s.depth, lessThanOrEqualTo(SubStep.maxDepth));
      }
    });
  });

  group('hardenMarkdownLineBreaks (log entry newlines)', () {
    test('single newlines become hard breaks (two trailing spaces)', () {
      // Regression (v1.4.12): a multi-line log entry collapsed into one
      // line because Markdown renders a single newline as a space.
      expect(
        hardenMarkdownLineBreaks('Bollard\n8/20 - Assembly\n8/20 - Test'),
        'Bollard  \n8/20 - Assembly  \n8/20 - Test  ',
      );
    });

    test('blank lines stay paragraph breaks', () {
      expect(
        hardenMarkdownLineBreaks('para one\n\npara two'),
        'para one  \n\npara two  ',
      );
    });

    test('fenced code blocks are left untouched', () {
      expect(
        hardenMarkdownLineBreaks('before\n```\ncode line\n```\nafter'),
        'before  \n```\ncode line\n```\nafter  ',
      );
    });

    test('existing hard breaks are not doubled', () {
      // "a  " already ends a hard break; "b\" uses the backslash form.
      expect(
        hardenMarkdownLineBreaks('a  \nb\\\nc'),
        'a  \nb\\\nc  ',
      );
    });

    test('leading indentation on paragraph lines is preserved as NBSP', () {
      // CommonMark strips leading paragraph spaces (1-3) and treats 4+ as a
      // code block, so Tab-indented lines would lose their visible indent in
      // the preview. Converting them to U+00A0 keeps the indent rendered
      // (workreport.html parity).
      expect(
        hardenMarkdownLineBreaks('parent\n  \u2022 child line'),
        'parent  \n\u00a0\u00a0\u2022 child line  ',
      );
      // Deep indents (4+ spaces) must NOT become code blocks.
      expect(
        hardenMarkdownLineBreaks('    deep indent'),
        '\u00a0\u00a0\u00a0\u00a0deep indent  ',
      );
    });

    test('indented LIST lines keep plain spaces so nesting still parses',
        () {
      expect(
        hardenMarkdownLineBreaks('- a\n  - b'),
        '- a\n  - b',
      );
    });

    test('under-indented sub-item is padded to nest under a numbered item',
        () {
      // workreport.html parity: a Tab-indented (2 spaces) `- sub` under
      // `4. item` (marker width 3) must nest beneath item 4 instead of
      // becoming a top-level sibling list (the reported visual bug).
      expect(
        normalizeListNesting('4. item\n  - sub'),
        '4. item\n   - sub',
      );
      // Multiple sub-items align with the same parent context.
      expect(
        normalizeListNesting('4. item\n  - sub1\n  - sub2'),
        '4. item\n   - sub1\n   - sub2',
      );
      // Already-valid nesting is untouched.
      expect(
        normalizeListNesting('- a\n  - b'),
        '- a\n  - b',
      );
      // Top-level items (no indent) are untouched.
      expect(
        normalizeListNesting('1. a\n2. b\n- c'),
        '1. a\n2. b\n- c',
      );
      // Blank line resets the list context.
      expect(
        normalizeListNesting('1. a\n\n  - b'),
        '1. a\n\n  - b',
      );
    });
  });

  group('TaskRepository.buildNewTask snapshot (quick-add sub-task race)', () {
    // Regression (v1.4.18): the Today quick-add bar passed its live
    // _subSteps list into the unawaited createTask() future and cleared it
    // synchronously right after. The repository read the list only after
    // its first await — by then it was empty, so sub-tasks never reached
    // the database and the detail page showed nothing.

    test('sub-steps survive the caller clearing its list afterwards', () {
      final repo = TaskRepository();
      final live = ['torque check', 'brake bleed'];
      // Synchronous entry point, exactly as createTask() invokes it
      // before its first await.
      final task =
          repo.buildNewTask(title: 'Bike prep', subSteps: live, sortOrder: 1);
      live.clear(); // UI clears immediately (future not awaited)
      expect(task.subSteps.map((s) => s.title).toList(),
          ['torque check', 'brake bleed']);
      expect(task.subSteps.every((s) => !s.completed), isTrue);
      expect(task.subSteps.every((s) => s.uid.isNotEmpty), isTrue);
    });

    test('tags survive the caller clearing its list afterwards', () {
      final repo = TaskRepository();
      final liveTags = ['lyft', 'oak'];
      final task = repo.buildNewTask(title: 'T', tags: liveTags, sortOrder: 1);
      liveTags.clear();
      expect(task.tags, ['lyft', 'oak']);
    });

    test('blank sub-steps are dropped and titles trimmed', () {
      final repo = TaskRepository();
      final task = repo.buildNewTask(
          title: 'T', subSteps: [' step A ', '', '   '], sortOrder: 1);
      expect(task.subSteps.map((s) => s.title).toList(), ['step A']);
    });
  });

  group('filterSuggestions (Project/Tags autocomplete)', () {
    const options = ['Cosmo', 'Monolith', 'Oak'];

    test('empty query returns all options', () {
      expect(filterSuggestions(options, ''), options);
      expect(filterSuggestions(options, '   '), options);
    });

    test('case-insensitive substring match', () {
      expect(filterSuggestions(options, 'co'), ['Cosmo']);
      expect(filterSuggestions(options, 'O'), ['Cosmo', 'Monolith', 'Oak']);
    });

    test('exact match is excluded so the dropdown hides', () {
      expect(filterSuggestions(options, 'oak'), isEmpty);
    });

    test('caps the result list at 8 entries', () {
      final many = List.generate(20, (i) => 'tag$i');
      expect(filterSuggestions(many, 'tag').length, 8);
    });
  });

  group('MarkdownInput (Execution Log formatting)', () {
    TextEditingController ctl(String text, {int? base, int? extent}) {
      final c = TextEditingController(text: text);
      if (base != null) {
        c.selection =
            TextSelection(baseOffset: base, extentOffset: extent ?? base);
      }
      return c;
    }

    test('wrapSelection wraps the current selection', () {
      final c = ctl('hello world', base: 0, extent: 5);
      MarkdownInput.wrapSelection(c, '**', '**');
      expect(c.text, '**hello** world');
    });

    test('wrapSelection with no selection inserts the pair', () {
      final c = ctl('ab', base: 1);
      MarkdownInput.wrapSelection(c, '`', '`');
      expect(c.text, 'a``b');
      expect(c.selection.baseOffset, 2);
    });

    test('prefixLines prefixes the current line only', () {
      final c = ctl('line one\nline two', base: 2);
      MarkdownInput.prefixLines(c, '- ');
      expect(c.text, '- line one\nline two');
    });

    test('indent / outdent are inverse operations', () {
      final c = ctl('task\n  sub', base: 0, extent: 9);
      MarkdownInput.indent(c);
      expect(c.text, '  task\n    sub');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 14);
      MarkdownInput.outdent(c);
      expect(c.text, 'task\n  sub');
    });

    test('outdent removes a single leading space', () {
      final c = ctl(' x', base: 1);
      MarkdownInput.outdent(c);
      expect(c.text, 'x');
    });

    // ── md-editor parity (workreport.html): Tab always indents the current
    // line at its START so the effect is visible no matter where the caret
    // is; with an active selection it (de)indents every touched line and
    // keeps the whole block selected for repeated presses.

    test('indent with no selection indents the whole line at its start', () {
      final c = ctl('abcd', base: 2);
      MarkdownInput.indent(c);
      expect(c.text, '  abcd');
      expect(c.selection.baseOffset, 4);
      expect(c.selection.isCollapsed, isTrue);
    });

    test('indent with selection prefixes lines and keeps block selected', () {
      final c = ctl('a\nb\nc', base: 0, extent: 5);
      MarkdownInput.indent(c);
      expect(c.text, '  a\n  b\n  c');
      expect(c.selection.baseOffset, 0);
      expect(c.selection.extentOffset, c.text.length);
      // Repeated indent keeps working on the same block.
      MarkdownInput.indent(c);
      expect(c.text, '    a\n    b\n    c');
    });

    test('outdent keeps the block selected after removing indents', () {
      final c = ctl('  a\n  b', base: 0, extent: 7);
      MarkdownInput.outdent(c);
      expect(c.text, 'a\nb');
      expect(c.selection.baseOffset, 0);
      expect(c.selection.extentOffset, c.text.length);
    });
  });

  group('Work Log AI prompt + format helpers', () {
    test('formatWorkLogRecords numbers records and separates them', () {
      final out = AiService.formatWorkLogRecords([
        (
          timestamp: DateTime(2026, 7, 21, 9, 0).millisecondsSinceEpoch,
          content: 'first'
        ),
        (
          timestamp: DateTime(2026, 7, 21, 10, 30).millisecondsSinceEpoch,
          content: 'second'
        ),
      ]);
      expect(out, contains('[1]'));
      expect(out, contains('[2]'));
      expect(out, contains('first'));
      expect(out, contains('second'));
      expect(out, contains('\n\n---\n\n'));
    });

    test('Chinese system prompt asks for a Chinese summary', () {
      final p = AiService.workLogSystemPrompt(
          outputChinese: true, dateRange: '2026-07-21');
      expect(p, contains('工作总结'));
      expect(p, contains('2026-07-21'));
    });

    test('non-Chinese user prompt forbids leaking the input language', () {
      final p = AiService.workLogUserPrompt(
        recordsText: '记录',
        dateRange: '2026-07-21',
        inputLang: 'zh',
        outputLang: 'en',
      );
      expect(p, contains('ENTIRELY in English'));
      expect(p, contains('Do NOT write any Chinese'));
    });

    test('autoFormatResult collapses blank lines and trims edges', () {
      expect(AiService.autoFormatResult('\n\na  \n\n\n\nb\n\n'), 'a\n\nb');
    });

    test('system prompts prescribe "**N." bold breakdown topics', () {
      final zh = AiService.workLogSystemPrompt(
          outputChinese: true, dateRange: '2026-07-21');
      final en = AiService.workLogSystemPrompt(
          outputChinese: false, dateRange: '2026-07-21');
      expect(zh, contains('**1.'));
      expect(en, contains('**1.'));
      // Both variants explicitly ban placeholder numbering.
      expect(zh, contains('占位符'));
      expect(en.toLowerCase(), contains('placeholder'));
    });

    test('stripDollarPlaceholders converts "\$1" artifacts to plain digits',
        () {
      expect(AiService.stripDollarPlaceholders('#### \$1. Fix bug'),
          '#### 1. Fix bug');
      expect(AiService.stripDollarPlaceholders('\$1'), '1');
      expect(AiService.stripDollarPlaceholders('\$1\$'), '1');
      expect(AiService.stripDollarPlaceholders('\$2. 第二点'), '2. 第二点');
    });

    test('stripDollarPlaceholders leaves real LaTeX alone', () {
      expect(AiService.stripDollarPlaceholders(r'$x^2$ and $E=mc^2$'),
          r'$x^2$ and $E=mc^2$');
    });

    test('autoFormatResult strips "\$1" placeholders end-to-end', () {
      final out =
          AiService.autoFormatResult('### 📝 要点详述\n#### \$1. 修复bug\n\$2. 第二点');
      expect(out, contains('#### 1. 修复bug'));
      expect(out, contains('2. 第二点'));
      expect(out, isNot(contains('\$1')));
    });

    test('autoFormatResult tidies markers/punctuation via real group refs', () {
      // These rules silently inserted literal "\$1"/"\$2" before v1.4.21
      // (Dart replaceAll does not expand group references).
      expect(AiService.autoFormatResult('-  point'), '- point');
      expect(AiService.autoFormatResult('1.  point'), '1. point');
      expect(AiService.autoFormatResult('完成。下一步'), '完成。 下一步');
      expect(AiService.autoFormatResult('标题 ：内容'), '标题：内容');
    });
  });

  group('WorkLog models JSON round-trip', () {
    test('WorkLogRecord survives toJson/fromJson', () {
      final r = WorkLogRecord(id: 'r1', content: 'did X', timestamp: 123456);
      final back = WorkLogRecord.fromJson(r.toJson());
      expect(back.id, 'r1');
      expect(back.content, 'did X');
      expect(back.timestamp, 123456);
    });

    test('WorkLogSummary survives toJson/fromJson', () {
      final s = WorkLogSummary(
        id: 's1',
        dateRange: '2026-07-21',
        content: '## Summary',
        inputLang: 'zh',
        outputLang: 'en',
        timestamp: 999,
      );
      final back = WorkLogSummary.fromJson(s.toJson());
      expect(back.id, 's1');
      expect(back.dateRange, '2026-07-21');
      expect(back.content, '## Summary');
      expect(back.inputLang, 'zh');
      expect(back.outputLang, 'en');
      expect(back.timestamp, 999);
    });
  });

  group('distinct projects/tags providers (autocomplete source)', () {
    Task mk(String uid, {String project = '', List<String> tags = const []}) =>
        Task()
          ..uid = uid
          ..title = 't$uid'
          ..priority = Priority.p2Medium
          ..status = TaskStatus.planned
          ..createdAt = DateTime.now()
          ..project = project
          ..tags = List.of(tags);

    test('collects unique, sorted project/tag values', () async {
      final tasks = [
        mk('1', project: 'Metro', tags: ['lyft', 'ate']),
        mk('2', project: 'Cosmo', tags: ['firmware', 'lyft']),
        mk('3', project: '  ', tags: []),
      ];
      final container = ProviderContainer(overrides: [
        taskRepositoryProvider.overrideWithValue(_FakeRepo(tasks)),
      ]);
      addTearDown(container.dispose);
      await container.read(taskListProvider.notifier).loadTasks();

      expect(container.read(distinctProjectsProvider), ['Cosmo', 'Metro']);
      expect(container.read(distinctTagsProvider), ['ate', 'firmware', 'lyft']);
    });
  });
}
