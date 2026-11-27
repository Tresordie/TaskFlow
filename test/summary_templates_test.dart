import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/services/summary_templates.dart';

/// Template data integrity — the 25 prompts are ported verbatim from the
/// voice_transcription reference project; these guards keep the dataset
/// consistent (unique ids, valid scenarios, non-empty prompts).
void main() {
  test('exactly 25 templates in 5 scenarios', () {
    expect(summaryTemplates, hasLength(25));
    expect(summaryScenarios, hasLength(5));
    const expectedScenarioIds = {'MTG', 'RPT', 'TASK', 'SUM', 'WRT'};
    expect(summaryScenarios.map((s) => s.id).toSet(), expectedScenarioIds);
  });

  test('template ids are unique and scenario ids valid', () {
    final ids = summaryTemplates.map((t) => t.id).toSet();
    expect(ids, hasLength(25));
    for (final t in summaryTemplates) {
      expect(expectedScenarioIds.contains(t.scenario), isTrue,
          reason: '${t.id} has invalid scenario ${t.scenario}');
      expect(t.name, isNotEmpty);
      expect(t.desc, isNotEmpty);
      expect(t.modules, isNotEmpty);
    }
  });

  test('every prompt is non-empty, contains G_SPEC context markers', () {
    for (final t in summaryTemplates) {
      expect(t.prompt.trim(), isNotEmpty, reason: '${t.id} prompt empty');
      // All templates declare their inputs with {{...}} placeholders.
      expect(t.prompt, contains('{{'),
          reason: '${t.id} prompt missing input placeholders');
    }
  });

  test('expected headline templates exist', () {
    final ids = summaryTemplates.map((t) => t.id).toSet();
    // 会议 5 + 日报周报 5 + 任务 5 + 邮件总结 5 + 邮件撰写 5.
    for (final id in ['M1', 'M2', 'M3', 'M4', 'M5', 'D1', 'D2', 'D3', 'D4',
        'D5', 'T1', 'T2', 'T3', 'T4', 'T5', 'E1', 'E2', 'E3', 'E4', 'E5',
        'W1', 'W2', 'W3', 'W4', 'W5']) {
      expect(ids, contains(id));
    }
  });

  test('findSummaryTemplate falls back to free mode on unknown ids', () {
    expect(findSummaryTemplate(null), isNull);
    expect(findSummaryTemplate('free'), isNull);
    expect(findSummaryTemplate(''), isNull);
    expect(findSummaryTemplate('NOPE'), isNull);
    expect(findSummaryTemplate('M1')!.name, '通用会议纪要 · 全功能版');
  });

  test('G_SPEC contract and TaskFlow adapter are present', () {
    expect(gSpec, contains('【输出契约】'));
    // Per user decision, mermaid/SVG visual directives stay.
    expect(gSpec, contains('mermaid flowchart'));
    expect(gSpec, contains('SVG'));
    expect(templateOutputAdapter, contains('Markdown 正文'));
    expect(templateOutputAdapter, contains('mermaid/SVG 代码块'));
  });
}

const expectedScenarioIds = {'MTG', 'RPT', 'TASK', 'SUM', 'WRT'};
