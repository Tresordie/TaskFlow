import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/markdown/html_export.dart';
import 'package:taskflow/core/markdown/timeline_upgrade.dart';

/// v1.15.3 reference parity (voice_transcription timeline.ts): tables with
/// a time column and "phase emoji + date" lists upgrade to the visual
/// timeline (inline styles, vertical line + colored nodes + date capsules;
/// task style with strikethrough/overdue). Guards mirror the reference
/// thresholds so ordinary tables/lists are never mangled.
void main() {
  group('detectTimeline (reference port)', () {
    test('time + event + desc columns → event timeline', () {
      final data = detectTimeline(
        ['时间', '事件', '说明'],
        [
          ['11/23', 'PCB 到货', '30 piece 板'],
          ['12/10', 'Tester 就绪', '接线改越南自厂'],
        ],
      );
      expect(data, isNotNull);
      expect(data!.style, 'event');
      expect(data.entries, hasLength(2));
      expect(data.entries[0].time, '11/23');
      expect(data.entries[0].title, 'PCB 到货');
      expect(data.entries[1].desc, '接线改越南自厂');
    });

    test('status column switches to task style', () {
      final data = detectTimeline(
        ['日期', '任务', '状态'],
        [
          ['11/26', '上线 30 piece', '完成'],
          ['11/28', 'harness 调试', '逾期'],
        ],
      );
      expect(data!.style, 'task');
    });

    test('mm:ss value fallback without header keyword', () {
      final data = detectTimeline(
        ['mm:ss', '发言人', '要点'],
        [
          ['00:10', '李斌', '不良分类'],
          ['02:30', 'Jonathan', 'ATE plan'],
        ],
      );
      expect(data, isNotNull);
      expect(data!.entries[0].time, '00:10');
    });

    test('guards: single column / one row / no time column → null', () {
      expect(detectTimeline(['时间轴（mm:ss ｜ 发言人 ｜ 事件）'], [
        ['a'],
        ['b'],
      ]), isNull);
      expect(detectTimeline(['时间', '事件'], [
        ['11/23', 'PCB'],
      ]), isNull);
      expect(detectTimeline(['项目', '数值'], [
        ['良率', '98%'],
        ['投入', '30'],
      ]), isNull);
    });

    test('entries capped at 40', () {
      final data = detectTimeline(
        ['时间', '事件'],
        List.generate(50, (i) => ['11/$i', '事件 $i']),
      );
      expect(data!.entries, hasLength(40));
    });
  });

  group('parseTimelineListItems (reference port)', () {
    test('phase emoji + date list → event timeline with emoji colors', () {
      final data = parseTimelineListItems([
        const TimelineListItem(text: '🔵 11/23 PCB 到货　30 piece 板'),
        const TimelineListItem(text: '🔴 12/05 ATE plan 冲突　待 Jonathan 确认'),
      ]);
      expect(data, isNotNull);
      expect(data!.style, 'event');
      expect(data.entries[0].color, '#0b6bcb');
      expect(data.entries[1].color, '#b42318');
      expect(data.entries[0].time, '11/23');
      expect(data.entries[0].title, 'PCB 到货');
      expect(data.entries[0].desc, '30 piece 板');
    });

    test('task emoji majority → task style', () {
      final data = parseTimelineListItems([
        const TimelineListItem(text: '✅ 11/26 上线完成'),
        const TimelineListItem(text: '🚧 11/28 调试进行中'),
      ]);
      expect(data!.style, 'task');
    });

    test('strong fragment becomes the title', () {
      final data = parseTimelineListItems([
        const TimelineListItem(
            text: '🔵 11/23 PCB 到货 30 piece', strong: '11/23 PCB 到货'),
        const TimelineListItem(text: '🔵 12/10 Tester 就绪 接线自制', strong: '12/10 Tester 就绪'),
      ]);
      expect(data!.entries[0].title, 'PCB 到货');
      expect(data.entries[0].desc, '30 piece');
    });

    test('ordinary lists are NOT upgraded (thresholds)', () {
      expect(parseTimelineListItems([
        const TimelineListItem(text: '第一条普通要点'),
        const TimelineListItem(text: '第二条普通要点'),
      ]), isNull);
      // Only one dated item out of three → below the 50% time threshold.
      expect(parseTimelineListItems([
        const TimelineListItem(text: '🔵 11/23 到货'),
        const TimelineListItem(text: '普通要点甲'),
        const TimelineListItem(text: '普通要点乙'),
      ]), isNull);
    });
  });

  group('renderTimelineHtml (inline styles, self-contained)', () {
    test('event style carries line + capsule + hex colors, escapes text', () {
      final html = renderTimelineHtml(const TimelineData(
        style: 'event',
        entries: [
          TimelineEntry(time: '11/23', title: 'PCB <到货>', desc: 'A&B', status: ''),
        ],
      ));
      expect(html, contains('background:#d1d5db')); // vertical line
      expect(html, contains('border-radius:999px')); // date capsule
      expect(html, contains('PCB &lt;到货&gt;'));
      expect(html, contains('A&amp;B'));
      expect(html, isNot(contains('class='))); // inline styles only
    });

    test('task style strikes through done and reds overdue', () {
      final html = renderTimelineHtml(const TimelineData(
        style: 'task',
        entries: [
          TimelineEntry(time: '11/26', title: '上线', desc: '', status: '完成'),
          TimelineEntry(time: '11/28', title: '调试', desc: '', status: '逾期'),
        ],
      ));
      expect(html, contains('text-decoration:line-through'));
      expect(html, contains('已逾期'));
      expect(html, contains('color:#b42318'));
    });
  });

  group('export integration (wrapAiParseHtml)', () {
    test('timeline table becomes visual timeline, not <table>', () async {
      const md = '# 标题\n\n'
          '| 时间 | 事件 | 说明 |\n|---|---|---|\n'
          '| 11/23 | PCB 到货 | 30 piece |\n'
          '| 12/10 | Tester 就绪 | 接线自制 |\n';
      final html = await wrapAiParseHtml(md);
      expect(html, contains('border-radius:999px'));
      expect(html, contains('PCB 到货'));
      expect(html, isNot(contains('<table>')));
    });

    test('emoji+date list becomes visual timeline, not <ul>', () async {
      const md = '# 标题\n\n'
          '- 🔵 11/23 PCB 到货　30 piece\n'
          '- 🔴 12/05 ATE plan 冲突　待确认\n';
      final html = await wrapAiParseHtml(md);
      expect(html, contains('background:#0b6bcb'));
      expect(html, contains('background:#b42318'));
      expect(html, isNot(contains('<ul>')));
    });

    test('ordinary table and list survive untouched', () async {
      const md = '# 标题\n\n'
          '| 项目 | 数值 |\n|---|---|\n| 良率 | 98% |\n| 投入 | 30 |\n\n'
          '- 普通要点甲\n- 普通要点乙\n';
      final html = await wrapAiParseHtml(md);
      expect(html, contains('<table>'));
      expect(html, contains('<ul>'));
      expect(html, isNot(contains('border-radius:999px')));
    });

    test('nested non-timeline list is preserved whole', () async {
      const md = '# 标题\n\n'
          '- 父项甲\n  - 子项一\n  - 子项二\n- 父项乙\n';
      final html = await wrapAiParseHtml(md);
      expect(html, contains('<ul>'));
      expect(html, contains('子项一'));
      expect(html, isNot(contains('border-radius:999px')));
    });
  });
}
