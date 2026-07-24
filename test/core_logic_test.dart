import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models/task.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/data/services/ai_service.dart';
import 'package:taskflow/data/services/report_service.dart';
import 'package:taskflow/providers/ai_provider.dart';
import 'package:taskflow/providers/task_providers.dart';

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
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.weekly, DateTime(2026, 7, 15));
      expect(start, DateTime(2026, 7, 13)); // Monday
      expect(end, DateTime(2026, 7, 20));
      expect(start.weekday, DateTime.monday);
    });

    test('weekly range handles a Monday anchor', () {
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.weekly, DateTime(2026, 7, 13));
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
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.monthly, DateTime(2026, 7, 21));
      expect(start, DateTime(2026, 7, 1));
      expect(end, DateTime(2026, 8, 1));
    });

    test('monthly range rolls over the year boundary', () {
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.monthly, DateTime(2026, 12, 5));
      expect(start, DateTime(2026, 12, 1));
      expect(end, DateTime(2027, 1, 1));
    });

    test('yearly range covers the calendar year', () {
      final (start, end) = ReportService.rangeFor(
          ReportPeriod.yearly, DateTime(2026, 7, 21));
      expect(start, DateTime(2026, 1, 1));
      expect(end, DateTime(2027, 1, 1));
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
        makeData(ReportPeriod.yearly, DateTime(2026, 1, 1),
                DateTime(2027, 1, 1))
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
      expect(html, contains(
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
      expect(html,
          contains('style="background-color:#ffffff; margin:0; padding:20px 0;"'));
      expect(html, contains('<td align="center">'));
      expect(html, contains('max-width:900px; padding:0 16px; text-align:left;'));
      // Rule 2 — white background everywhere, no full-width colored band.
      expect(html, contains(
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
      expect(html, contains(
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
        const AiConfig(
                baseUrl: 'https://api.deepseek.com', apiKey: 'sk-1')
            .isConfigured,
        isTrue,
      );
      expect(
        const AiConfig(
                baseUrl: 'https://api.deepseek.com',
                apiKey: 'sk-1',
                model: '')
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
        const AiConfig(baseUrl: '  ', apiKey: 'sk-1', model: 'm')
            .isConfigured,
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

    test('bare SUMMARY: line followed by bullets is fully captured',
        () async {
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
      expect(r.summary,
          'Validated V2 factory release\nClosed after PVT sign-off');
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
                'content':
                    'TITLE: Monolith PVT release validation\nSUMMARY:'
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
        throwsA(isA<AiServiceException>().having(
            (e) => e.message, 'message', contains('Settings → AI'))),
      );
    });
  });

  group('Nested sub-steps (max 3 levels)', () {
    SubStep step(String uid, {String? parent, int depth = 0}) =>
        SubStep()
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
      final ordered =
          subStepsInDisplayOrder(steps).map((s) => s.uid).toList();
      expect(ordered, ['a', 'a1', 'a1x', 'a2', 'b', 'b1']);
    });

    test('orphans (missing parent) fall back to top level', () {
      final steps = [
        step('a'),
        step('x', parent: 'ghost', depth: 1),
      ];
      final ordered =
          subStepsInDisplayOrder(steps).map((s) => s.uid).toList();
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

    test('normalize repairs sign-bit-corrupted depths (v1.4.9 migration)',
        () {
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
}
