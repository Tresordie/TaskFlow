import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/services/ai_service.dart';
import 'package:taskflow/data/services/summary_templates.dart';
import 'package:taskflow/data/services/summarize_pipeline.dart';

void main() {
  group('splitByParagraphs (ported from summarize.ts)', () {
    test('keeps short text as one chunk', () {
      final chunks = splitByParagraphs('第一段\n第二段\n第三段');
      expect(chunks, hasLength(1));
    });

    test('splits on line boundaries without cutting a line', () {
      final line = 'x' * 100;
      final text = List.filled(50, line).join('\n'); // 5099 chars
      final chunks = splitByParagraphs(text, maxChars: 1200);
      expect(chunks.length, greaterThanOrEqualTo(4));
      for (final c in chunks) {
        expect(c.length, lessThan(1200 + 100)); // a line may overflow once
      }
      // Rejoining (with the '\n' separators consumed at boundaries) must
      // preserve the total content.
      final rejoined = chunks.join('\n');
      expect(rejoined.length, text.length);
    });

    test('hard-cuts a single overlong line', () {
      final text = 'y' * 5000;
      final chunks = splitByParagraphs(text, maxChars: 800);
      expect(chunks.length, 7); // 6×800 + 200
      expect(chunks.join('').length, 5000);
    });
  });

  group('buildSystemPrompt composition', () {
    test('free mode embeds G_SPEC and the default extra request', () {
      final prompt = buildSystemPrompt(template: null, email: false);
      expect(prompt, contains('===== 全文内容 ====='));
      expect(prompt, contains(gSpec));
      expect(prompt, contains('核心结论、关键要点、重要数据与待办事项'));
      expect(prompt, isNot(contains('【输出语言】')));
    });

    test('free mode + user prompt uses it verbatim', () {
      final prompt = buildSystemPrompt(
          template: null, email: false, userPrompt: '输出成周报');
      expect(prompt, contains('【用户额外要求】输出成周报'));
      expect(prompt, isNot(contains('【用户额外要求】请给出全面而精炼的总结')));
    });

    test('template mode appends adapter + main-input note', () {
      final template = findSummaryTemplate('M1')!;
      final prompt = buildSystemPrompt(template: template);
      expect(prompt, startsWith('你是会议纪要专家'));
      expect(prompt, contains(templateOutputAdapter));
      expect(prompt, contains('【本任务说明】'));
      expect(prompt, contains('【输出格式补充】'));
      expect(prompt, contains('Markdown 正文'));
    });

    test('email mode uses the email playbook without G_SPEC', () {
      final prompt = buildSystemPrompt(template: null, email: true);
      expect(prompt, contains(AiService.emailThreadSystemPrompt));
      expect(prompt, isNot(contains(gSpec)));
    });

    test('language directive lands LAST and wins priority', () {
      final prompt = buildSystemPrompt(
          template: null, email: false, language: 'English（英语）');
      // The directive must appear AFTER the G_SPEC contract...
      final gSpecIndex = prompt.indexOf(gSpec);
      final langIndex = prompt.indexOf('【输出语言】');
      expect(gSpecIndex, greaterThanOrEqualTo(0));
      expect(langIndex, greaterThan(gSpecIndex));
      expect(prompt, contains('Key points / Conclusion / Next actions'));
      // ...and its checklist closes the prompt.
      expect(prompt.trimRight(), endsWith('以本要求为准。'));
    });
  });

  group('output languages (17 entries, verbatim port)', () {
    test('first entry is follow-source and the list is global', () {
      expect(kOutputLanguages.first.value, '');
      expect(kOutputLanguages.first.label, '跟随原文');
      expect(kOutputLanguages, hasLength(17));
      final labels = kOutputLanguages.map((l) => l.label).toSet();
      expect(labels, hasLength(17));
      for (final expected in [
        '简体中文', 'English（英语）', '日本語（日语）', 'Français（法语）',
        'العربية（阿拉伯语）', 'Bahasa Indonesia（印尼语）',
      ]) {
        expect(labels, contains(expected));
      }
    });
  });

  group('runSummarize with a fake AiService', () {
    test('short content skips map-reduce and streams the final call',
        () async {
      final ai = _FakeAiService();
      final result = await runSummarize(
        ai,
        content: '短内容',
        templateId: 'free',
        onProgress: (stage, done, total) => stages.add('$stage/$done/$total'),
      );
      expect(result, '-streamed-');
      expect(ai.streamCalls.length, 1);
      expect(ai.chatCalls, isEmpty); // no map phase below the threshold
      // The user message carries the full material behind the delimiter.
      expect(ai.lastStreamMessages!.last['content'],
          startsWith('===== 全文内容 ====='));
      // "生成总结" progress fires for the final stage.
      expect(stages.join('|'), contains('生成总结'));
    });

    test('long content map-reduces with concurrency and preserved order',
        () async {
      final ai = _FakeAiService();
      // 3 chunks above the 12k threshold: 3 × ~5k-char lines.
      final content =
          List.filled(3, 'z' * 5000).join('\n\n\n'); // ~15k chars
      await runSummarize(ai, content: content, templateId: 'free');
      expect(ai.chatCalls, hasLength(3));
      // Map prompts are numbered 片段 1/3 .. 3/3.
      final fragments = ai.chatCalls
          .map((m) => m.last['content'] as String)
          .map((c) => RegExp(r'【片段 (\d)/3】').firstMatch(c)!.group(1)!)
          .toList();
      expect(fragments, ['1', '2', '3']);
      // The digest travels into the final call's material.
      final material =
          ai.lastStreamMessages!.last['content'] as String;
      expect(material, contains('【片段 1 要点】'));
      expect(material, contains('【片段 3 要点】'));
    });

    test('cancellation between chunks throws AiCancelledException',
        () async {
      final ai = _FakeAiService();
      final content = List.filled(3, 'z' * 5000).join('\n');
      var calls = 0;
      await expectLater(
        runSummarize(
          ai,
          content: content,
          templateId: 'free',
          isCancelled: () => ++calls > 1, // cancel after first chunk
        ),
        throwsA(isA<AiCancelledException>()),
      );
      expect(ai.streamCalls.length, 0); // never reached the final stage
    });
  });
}

// The pipeline test's shared stage recorder.
List<String> stages = <String>[];

/// Minimal AiService test double: records calls, returns canned responses.
/// (AiService is constructed via its public constructor in production code;
/// the pipeline only calls [chat] / [streamChat], so a noSuchMethod-backed
/// implementation is the least invasive seam.)
class _FakeAiService implements AiService {
  final chatCalls = <List<Map<String, String>>>[];
  final streamCalls = <int>[];
  List<Map<String, String>>? lastStreamMessages;
  int _counter = 0;

  @override
  Future<String> chat({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    dynamic responseTimeout,
  }) async {
    chatCalls.add(messages);
    return '要点${++_counter}';
  }

  @override
  Future<String> streamChat({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    void Function(String delta, String full)? onDelta,
    bool Function()? isCancelled,
  }) async {
    streamCalls.add(++_counter);
    lastStreamMessages = messages;
    return '-streamed-';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
