/// AI Parse summarize pipeline — ported from the voice_transcription
/// reference project (`summarize.ts`): full material → (map-reduce chunked
/// comprehension when too long) → streaming final summary that follows the
/// selected template / user prompt / output language.
///
/// The template prompt (incl. the G_SPEC output contract) applies to the
/// FINAL stage only — the model first understands the whole material, then
/// formats. The map phase is deliberately template-agnostic (bare key-point
/// extraction) so contract details never dilute into the digests.
library;

import 'ai_service.dart';
import 'summary_templates.dart';

/// Map-stage target characters per chunk.
const int kChunkChars = 8000;

/// Material length above which map-reduce kicks in.
const int kMapThreshold = 12000;

/// Max map chunks (≈1M characters cap; beyond that the tail is cut and
/// flagged in the output).
const int kMaxChunks = 120;

const String kMapSystem =
    '你是资料整理专家。以下是大文档的一个片段，请提取关键信息要点：'
    '事实、数字、结论、决策、待办、人名/日期/专有名词等，条目化输出（Markdown 列表），'
    '保留数字与专有名词原样，不臆造、不评价，≤400 字。';

/// Output-language options (verbatim port of OUTPUT_LANGUAGES; '' = follow
/// the source material, no language directive injected).
class OutputLanguage {
  final String value;
  final String label;

  const OutputLanguage(this.value, this.label);
}

const List<OutputLanguage> kOutputLanguages = [
  OutputLanguage('', '跟随原文'),
  OutputLanguage('简体中文', '简体中文'),
  OutputLanguage('繁體中文', '繁體中文'),
  OutputLanguage('English（英语）', 'English（英语）'),
  OutputLanguage('日本語（日语）', '日本語（日语）'),
  OutputLanguage('한국어（韩语）', '한국어（韩语）'),
  OutputLanguage('Français（法语）', 'Français（法语）'),
  OutputLanguage('Deutsch（德语）', 'Deutsch（德语）'),
  OutputLanguage('Español（西班牙语）', 'Español（西班牙语）'),
  OutputLanguage('Português（葡萄牙语）', 'Português（葡萄牙语）'),
  OutputLanguage('Italiano（意大利语）', 'Italiano（意大利语）'),
  OutputLanguage('Русский（俄语）', 'Русский（俄语）'),
  OutputLanguage('العربية（阿拉伯语）', 'العربية（阿拉伯语）'),
  OutputLanguage('हिन्दी（印地语）', 'हिन्दी（印地语）'),
  OutputLanguage('ไทย（泰语）', 'ไทย（泰语）'),
  OutputLanguage('Tiếng Việt（越南语）', 'Tiếng Việt（越南语）'),
  OutputLanguage('Bahasa Indonesia（印尼语）', 'Bahasa Indonesia（印尼语）'),
];

/// Splits [text] on line boundaries (never mid-sentence unless a single line
/// exceeds [maxChars], which is hard-cut as a fallback). Verbatim port of
/// `splitByParagraphs`.
List<String> splitByParagraphs(String text, {int maxChars = kChunkChars}) {
  final chunks = <String>[];
  var buf = '';
  for (final line in text.split('\n')) {
    if (buf.isNotEmpty && buf.length + line.length + 1 > maxChars) {
      chunks.add(buf);
      buf = '';
    }
    buf += (buf.isEmpty ? '' : '\n') + line;
    while (buf.length >= maxChars) {
      chunks.add(buf.substring(0, maxChars));
      buf = buf.substring(maxChars);
    }
  }
  if (buf.trim().isNotEmpty) chunks.add(buf);
  return chunks;
}

/// Assembles the FINAL stage system prompt (template / email / free mode) —
/// verbatim port of `buildSystemPrompt`, plus the email playbook branch and
/// the TaskFlow output-format adapter line for template mode.
String buildSystemPrompt({
  SummaryTemplate? template,
  bool email = false,
  String userPrompt = '',
  String? language,
}) {
  // The language directive goes LAST (after template & G_SPEC) so it wins
  // priority; the G-SPEC structure requirements are restated as a checklist
  // the model can tick off position by position.
  final langNote = (language == null || language.isEmpty)
      ? ''
      : '''

【输出语言】请将总结的全部内容一律用「$language」书写；这只是语言切换，结构与格式必须和中文输出完全一致，逐项对照以下清单（与上文 G-SPEC 契约对应，一项不得省略）：
① 结论式标题（含数字/对比）＋ 30秒 TL;DR（≤3条）；
② 模块化正文（小标题＋表格），每个模块末尾固定三行小结——用「$language」等义标记（英文如 Key points / Conclusion / Next actions）；
③ 全局待办表：事项/唯一负责人/截止日/验收标准/出处 五列齐全；
④ 按内容自动配图：占比→饼图（≤5类）/堆叠条形（>5类）、排名→横向条形、趋势→折线（标异常点）、流程/依赖→mermaid flowchart、结构/聚类→mermaid mindmap、对比/参数→表格、时间/里程碑→时间轴/甘特、风险→概率×影响矩阵、状态→徽章/看板/进度条；每模块配 1 个图标，关键概念配 SVG 示意图；
⑤ 会议/线程/项目输出「时间戳|发言人/来源|事件」时间轴，关键摘录保留原话±2句＋时间戳（原话保留原语言）；
⑥ 封面块（SVG 封面：标题/日期/参与人/一句话结论/状态徽章）；
⑦ 保真：数字/人名/日期/标识符（版本号/SN/字段名/错误码）原文保留，缺失信息用「$language」等义占位标记（英文如 [TBC]），推断必须标注，不新增事实。
若使用模板，模板定义的全部模块（如决策日志、证据附录、风险矩阵）一个不少，仅将文字换成「$language」；上文契约中的中文固定措辞（【重点】【结论】【待办】【待确认】【待补】等）一律改为「$language」等义标记；除原文直接引用与专有名词外不得出现中文；若上文契约与语言要求冲突，以本要求为准。''';

  final extra =
      userPrompt.trim().isEmpty ? '' : '\n\n【用户额外要求】${userPrompt.trim()}';

  if (template != null) {
    // The template prompt (with its own {{...}} input declaration and
    // G-SPEC contract) travels VERBATIM — same as the reference. G_SPEC ②
    // already defaults the output medium to Markdown; the former TaskFlow
    // adapter line is gone (v1.15.2: it also told the model to replace the
    // SVG cover with text badges, diverging from the reference output).
    return template.prompt +
        '\n\n【本任务说明】上文「输入：{{...}}」所指的主输入材料在用户消息中以「===== 全文内容 =====」分隔完整给出；'
            '其余占位符上下文若用户消息未提供，请按全文内容合理推断，无法推断的' +
        (language != null && language.isNotEmpty ? '用输出语言的等义占位标记标注' : '写【待确认】') +
        '。' +
        extra +
        langNote;
  }
  if (email) {
    // Email threads keep their dedicated playbook (fixed section format,
    // timeline table, per-party to-dos); no G_SPEC on top.
    return AiService.emailThreadSystemPrompt +
        extra +
        (userPrompt.trim().isEmpty
            ? '\n\n【用户额外要求】请给出全面而精炼的总结：核心结论、关键要点、重要数据与待办事项。'
            : '') +
        langNote;
  }
  return '你是专业的内容总结助手。请理解用户消息中「===== 全文内容 =====」之后的完整材料，'
      '输出一份结构清晰的 Markdown 总结（结论先行、要点条目化、善用小标题与表格），保留数字与专有名词原样，'
      '不新增事实；' +
      (language != null && language.isNotEmpty
          ? '缺失信息用输出语言的等义占位标记标注（如英文写 [TBC]）。'
          : '缺失信息写【待确认】。') +
      (userPrompt.trim().isEmpty
          ? '\n【用户额外要求】请给出全面而精炼的总结：核心结论、关键要点、重要数据与待办事项。'
          : extra) +
      '\n\n$gSpec' +
      langNote;
}

/// Summarize [content] with the given options. Long material (>12k chars) is
/// first compressed chunk-by-chunk (concurrency 2, order preserved) into a
/// key-point digest; the final stage streams the formatted summary.
///
/// [isCancelled] is polled between stages/chunks — when it returns true a
/// [SummarizeCancelled] is thrown (the caller owns the cancel flag).
Future<String> runSummarize(
  AiService ai, {
  required String content,
  String? templateId,
  String userPrompt = '',
  String? outputLanguage,
  bool email = false,
  void Function(String stage, int done, int total)? onProgress,
  void Function(String delta, String full)? onDelta,
  bool Function()? isCancelled,
}) async {
  final template = findSummaryTemplate(templateId);
  var material = content;
  var truncatedNote = '';

  if (content.length > kMapThreshold) {
    var chunks = splitByParagraphs(content);
    if (chunks.length > kMaxChunks) {
      chunks = chunks.sublist(0, kMaxChunks);
      truncatedNote =
          '\n\n> ⚠️ 原文约 ${(content.length / 10000).ceil()} 万字符，超出单次分析上限，'
          '本次仅分析前 $kMaxChunks 个片段（约 ${(kMaxChunks * kChunkChars / 10000).ceil()} 万字符）。';
    }
    onProgress?.call('理解全文（分块提取要点）', 0, chunks.length);
    final bullets = await _mapWithConcurrency(
      chunks,
      2,
      (chunk, i) async {
        _throwIfCancelled(isCancelled);
        // Reference parity: the map call sends maxTokens only (no
        // temperature — the server default applies, same as summarize.ts).
        final out = await ai.chat(
          maxTokens: 800,
          responseTimeout: const Duration(seconds: 150),
          messages: [
            {'role': 'system', 'content': kMapSystem},
            {'role': 'user', 'content': '【片段 ${i + 1}/${chunks.length}】\n$chunk'},
          ],
        );
        onProgress?.call('理解全文（分块提取要点）', i + 1, chunks.length);
        return out;
      },
      isCancelled: isCancelled,
    );
    material = '以下是对全文各片段依次提取的要点合集（已按原文顺序拼接），'
            '请在此基础上结合整体脉络进行总结：\n\n' +
        bullets
            .asMap()
            .entries
            .map((e) => '【片段 ${e.key + 1} 要点】\n${e.value}')
            .join('\n\n') +
        truncatedNote;
  }

  final messages = <Map<String, String>>[
    {
      'role': 'system',
      'content': buildSystemPrompt(
        template: template,
        email: email && template == null,
        userPrompt: userPrompt,
        language: outputLanguage,
      ),
    },
    {'role': 'user', 'content': '===== 全文内容 =====\n$material'},
  ];
  onProgress?.call('生成总结', 0, 0);
  // Reference parity: the final pass sends NO max_tokens (the reference
  // chatLLM omits the field unless asked) — the provider default applies
  // and streamChat's finish_reason continuation still guards truncation.
  return ai.streamChat(
    temperature: 0.3,
    messages: messages,
    onDelta: onDelta,
    isCancelled: isCancelled,
  );
}

void _throwIfCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) throw const AiCancelledException();
}

/// Order-preserving bounded-concurrency map (verbatim port of
/// `mapWithConcurrency`).
Future<List<T>> _mapWithConcurrency<T>(
  List<String> items,
  int limit,
  Future<T> Function(String item, int index) worker, {
  bool Function()? isCancelled,
}) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> runner() async {
    while (true) {
      _throwIfCancelled(isCancelled);
      final i = next++;
      if (i >= items.length) return;
      results[i] = await worker(items[i], i);
    }
  }

  await Future.wait(
      List.generate(limit.clamp(1, items.length), (_) => runner()));
  return results.cast<T>();
}
