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

  test('G_SPEC contract present; adapter line REMOVED (v1.15.2 parity)', () {
    expect(gSpec, contains('【输出契约】'));
    // Per user decision, mermaid/SVG visual directives stay.
    expect(gSpec, contains('mermaid flowchart'));
    expect(gSpec, contains('SVG'));
    // v1.15.2: prompts travel byte-identical to the reference — no
    // TaskFlow adapter extra line anywhere in the dataset.
    for (final t in summaryTemplates) {
      expect(t.prompt, isNot(contains('【输出格式补充】')),
          reason: '${t.id} still carries the removed adapter line');
    }
  });

  test('M1 prompt is the reference prompt verbatim (parity anchor)', () {
    final m1 = findSummaryTemplate('M1')!;
    expect(m1.prompt, startsWith('你是会议纪要专家。输入：{{会议录音转写稿或笔记}}'));
    expect(m1.prompt, contains('9 证据附录(关键摘录原话±2句+时间戳+转写链接)'));
    expect(
        m1.prompt,
        endsWith(
            '禁止臆造人名/数字/承诺；缺失写【待确认】；分歧保留，不写「大家一致同意」除非真的投票了。'));
  });
}

const expectedScenarioIds = {'MTG', 'RPT', 'TASK', 'SUM', 'WRT'};
