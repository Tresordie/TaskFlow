import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

import '../models/task.dart';

/// A task extracted from free-form notes by the LLM.
class ParsedTask {
  String title;
  String description;
  Priority priority;
  List<String> tags;
  List<String> subSteps;
  bool selected;

  ParsedTask({
    required this.title,
    this.description = '',
    this.priority = Priority.p2Medium,
    List<String>? tags,
    List<String>? subSteps,
    this.selected = true,
  })  : tags = tags ?? [],
        subSteps = subSteps ?? [];
}

/// Minimal OpenAI-compatible chat client (works with OpenAI, DeepSeek,
/// Qwen DashScope-compatible endpoints, Ollama, LM Studio, vLLM, ...).
///
/// Uses dart:io HttpClient directly to avoid extra dependencies.
class AiService {
  final String baseUrl;
  final String apiKey;
  final String model;

  AiService({
    required String baseUrl,
    required String apiKey,
    required this.model,
  })  : baseUrl = _sanitizeBaseUrl(baseUrl),
        apiKey = _sanitizeApiKey(apiKey);

  /// Endpoint strings are often pasted from chat messages or docs: strip
  /// whitespace/control chars and map full-width punctuation (： ／) to
  /// ASCII so a sloppy paste doesn't become an inscrutable dart:io
  /// "Invalid argument" error later.
  static String _sanitizeBaseUrl(String raw) => raw
      .replaceAll(RegExp(r'[\u0000-\u0020\u007f\u3000]+'), '')
      .replaceAll('：', ':')
      .replaceAll('／', '/');

  /// API keys never contain whitespace; pasted ones frequently carry a
  /// trailing newline that would corrupt the Authorization header.
  static String _sanitizeApiKey(String raw) =>
      raw.replaceAll(RegExp(r'[\u0000-\u0020\u007f\u3000]+'), '');

  /// Sends one chat-completions request and returns the raw response body.
  ///
  /// Centralizes sampling-parameter handling so EVERY feature copes with
  /// reasoning models: kimi-k3, deepseek-reasoner, OpenAI o-series, QwQ and
  /// similar models reject any `temperature` other than 1 (HTTP 400
  /// "invalid temperature: only 1 is allowed"). For those
  /// ([_isReasoningModel]) the parameter is omitted outright; and as a safety
  /// net for any model we did not anticipate, a 400 whose body mentions
  /// "temperature" triggers exactly one automatic retry without it.
  /// [extraBody] carries request-specific fields such as `response_format`.
  Future<String> _chat({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration requestTimeout = const Duration(seconds: 15),
    Duration responseTimeout = const Duration(seconds: 60),
  }) async {
    // Reasoning models "think" before answering and are markedly slower than
    // chat models — a full report over many tasks can take several minutes on
    // kimi-k3. Give them a generous multiple of the caller's response timeout
    // so a long-but-valid generation is not aborted prematurely (this was the
    // "Full-report generation timed out" failure on kimi-k3).
    final effectiveResponseTimeout =
        _isReasoningModel(model) ? responseTimeout * 3 : responseTimeout;
    Future<String> send({required bool includeTemperature}) async {
      final uri = _buildUri();
      final client = HttpClient()..connectionTimeout = connectTimeout;
      try {
        final request = await client.postUrl(uri).timeout(requestTimeout);
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.headers.set('Authorization', 'Bearer $apiKey');
        final body = <String, dynamic>{
          'model': model,
          'messages': messages,
          // Reasoning models spend part of the token budget on internal
          // "thinking"; a restrictive max_tokens can be exhausted by the
          // reasoning alone, leaving the final content EMPTY (this caused
          // "AI returned an empty report" on kimi-k3 full reports, while
          // short per-task calls still fit). Omit max_tokens for those so
          // the model uses its own generous default and always leaves room
          // for the answer.
          if (maxTokens != null && !_isReasoningModel(model))
            'max_tokens': maxTokens,
          if (includeTemperature &&
              temperature != null &&
              !_isReasoningModel(model))
            'temperature': temperature,
          if (extraBody != null) ...extraBody,
        };
        // add() writes raw UTF-8 bytes; write() would default to latin1 and
        // throw on Chinese content ("Invalid argument (string)").
        request.add(utf8.encode(jsonEncode(body)));
        final response =
            await request.close().timeout(effectiveResponseTimeout);
        final text = await response.transform(utf8.decoder).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw AiServiceException(
              'API error ${response.statusCode}: ${_shorten(text)}');
        }
        return text;
      } finally {
        client.close(force: true);
      }
    }

    try {
      return await send(includeTemperature: true);
    } on AiServiceException catch (e) {
      // Reactive safety net: a model we did not recognise as reasoning-only
      // still rejected the sampling parameter — retry once without it.
      if (temperature != null &&
          e.message.toLowerCase().contains('temperature')) {
        return await send(includeTemperature: false);
      }
      rethrow;
    }
  }

  /// Streaming variant of [_chat], used by [generateFullReport]. A
  /// non-streaming request must wait for the WHOLE document before the
  /// response completes, so it trips the response timeout on long reports.
  /// Streaming receives tokens continuously — we only guard the gap BETWEEN
  /// chunks ([chunkTimeout]) — so the total generation may run as long as the
  /// model needs. Returns the accumulated assistant content plus whether the
  /// model stopped because it hit its output token limit (`finish_reason:
  /// length`), i.e. the report is truncated and needs a continuation.
  /// Reasoning/thinking deltas (`reasoning_content`) are ignored.
  Future<({String content, bool truncated})> _chatStream({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration requestTimeout = const Duration(seconds: 15),
    Duration chunkTimeout = const Duration(seconds: 180),
  }) async {
    final uri = _buildUri();
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final request = await client.postUrl(uri).timeout(requestTimeout);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Accept', 'text/event-stream');
      final body = <String, dynamic>{
        'model': model,
        'stream': true,
        'messages': messages,
        if (maxTokens != null) 'max_tokens': maxTokens,
        // Reasoning models only accept temperature=1 — omit it for those.
        if (temperature != null && !_isReasoningModel(model))
          'temperature': temperature,
        if (extraBody != null) ...extraBody,
      };
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(chunkTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.transform(utf8.decoder).join();
        throw AiServiceException(
            'API error ${response.statusCode}: ${_shorten(text)}');
      }
      final content = StringBuffer();
      String? finishReason;
      // Server-Sent Events: one `data: {json}` line per chunk, terminated by
      // `data: [DONE]`. `.timeout` guards the gap between chunks so a stalled
      // stream still fails instead of hanging forever.
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(chunkTimeout);
      await for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith(':')) continue; // comment/keep-alive
        if (!line.startsWith('data:')) continue;
        final data = line.substring('data:'.length).trim();
        if (data == '[DONE]') break;
        try {
          final decoded = jsonDecode(data);
          final choices = decoded is Map ? decoded['choices'] : null;
          if (choices is List && choices.isNotEmpty) {
            final choice = choices.first;
            final delta = choice is Map ? choice['delta'] : null;
            final c = delta is Map ? delta['content'] : null;
            if (c is String) content.write(c);
            final fr = choice is Map ? choice['finish_reason'] : null;
            if (fr is String && fr.isNotEmpty) finishReason = fr;
          }
        } catch (_) {
          // Ignore malformed/partial keep-alive chunks.
        }
      }
      return (
        content: content.toString(),
        truncated: finishReason == 'length',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Heuristic: reasoning / "thinking" models spend part of the token budget
  /// on internal reasoning (they return `reasoning_content`) and most only
  /// accept their default temperature. Match the well-known families by name
  /// so they get a larger output budget and omit temperature. Anything this
  /// misses is still caught by [_chat]'s reactive temperature retry and by
  /// the truncation-continuation loop in [generateFullReport].
  static bool _isReasoningModel(String model) {
    final m = model.toLowerCase();
    if (m.contains('reasoner') ||
        m.contains('reasoning') ||
        m.contains('thinking') ||
        m.contains('qwq') ||
        m.contains('kimi-k3') ||
        // deepseek-v4-* (e.g. deepseek-v4-pro) are thinking models — their
        // responses carry reasoning_content and share the token budget with
        // the answer, so they need the larger budget too.
        m.contains('deepseek-v4')) {
      return true;
    }
    // OpenAI o-series: o1 / o3 / o4 and their -mini / -pro variants, without
    // matching e.g. "gpt-4o" (the 'o' there follows a digit).
    return RegExp(r'(^|[^a-z0-9])o[134]($|[^0-9])').hasMatch(m);
  }

  static const _systemPrompt = '''
You are a task-extraction assistant for a hardware test engineer.
The user pastes raw work notes (meeting notes, test logs, to-do scribbles,
chat excerpts, etc.). Your job: extract every actionable TASK from the notes.

Rules:
1. Reply with ONLY a JSON object, no prose, no markdown fences.
2. JSON schema:
{"tasks":[{"title":"short imperative title","description":"context, details, measurements, links","priority":"P0|P1|P2|P3","tags":["tag1"],"subSteps":["step 1","step 2"]}]}
3. priority: P0 = critical / blocking line-down, P1 = high / this week,
   P2 = medium / normal, P3 = low / nice-to-have. Default P2.
4. title: imperative, <= 60 chars, in the SAME language as the notes.
5. description: keep concrete facts (values, part numbers, station names).
6. subSteps: only when the notes clearly enumerate steps; else [].
7. tags: 0-3 short lowercase keywords (e.g. "ate", "harness", "pvt").
8. If there is no actionable task, return {"tasks":[]}.
''';

  /// Sends [notes] to the LLM and returns the parsed task list.
  Future<List<ParsedTask>> parseNotes(String notes) async {
    try {
      final text = await _chat(
        temperature: 0.2,
        extraBody: {
          'response_format': {'type': 'json_object'}
        },
        requestTimeout: const Duration(seconds: 20),
        responseTimeout: const Duration(seconds: 90),
        messages: [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': notes},
        ],
      );
      return _parseResponse(text);
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw AiServiceException('Request timed out. Check base URL / network.');
    }
  }

  /// Quick connectivity + auth check. Returns a short status string.
  Future<String> testConnection() async {
    final uri = _buildUri();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.add(utf8.encode(jsonEncode({
        'model': model,
        'max_tokens': 8,
        'messages': [
          {'role': 'user', 'content': 'ping'}
        ],
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return 'OK (${response.statusCode})';
      }
      throw AiServiceException(
          'API error ${response.statusCode}: ${_shorten(text)}');
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Connection timed out.');
    } finally {
      client.close(force: true);
    }
  }

  /// One LLM call per task for the report pipeline. Returns:
  ///  - [title]: the task title translated into the report language
  ///    (technical terms / part numbers kept as-is), and
  ///  - [summary]: 1-3 short bullet lines (joined by '\n', markers
  ///    stripped) summarizing ALL execution-log entries that fall inside
  ///    the report period ([periodEntries]); when there are none, the
  ///    task's current state. Rendered as a list in the Details column.
  ///
  /// [chinese] selects the output language. Failures are thrown as
  /// [AiServiceException]; callers typically catch and fall back to the
  /// original title + heuristic details.
  Future<({String title, String summary})> enhanceTask(
    Task t, {
    required bool chinese,
    List<ExecutionEntry> periodEntries = const [],
  }) async {
    try {
      // The digest carries the raw (usually Chinese) task title; _chat
      // writes raw UTF-8 bytes so dart:io's latin1 "Invalid argument"
      // never fires.
      final text = await _chat(
        temperature: 0.3,
        // 200 was too tight: a long task title ate most of the completion
        // budget, so replies got cut off BEFORE the SUMMARY section
        // (completed tasks silently fell back to the "done MM-dd"
        // heuristic) or mid-bullet ("…BMS"). 1000 leaves ample room for
        // the TITLE line plus three full bullets in either language.
        maxTokens: 1000,
        responseTimeout: const Duration(seconds: 60),
        messages: [
          {'role': 'system', 'content': _enhancePrompt(chinese)},
          {'role': 'user', 'content': _taskDigest(t, periodEntries)},
        ],
      );
      return _parseEnhance(_extractContentMultiLine(text), t.title);
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Summary request timed out.');
    }
  }

  /// Translates a batch of short terms (project names, tags) into the report
  /// language in ONE call. Returns a map from original term to translation;
  /// terms that fail to translate are omitted so the caller falls back to the
  /// raw value. Used to keep English reports free of Chinese project/tag text.
  Future<Map<String, String>> translateTerms(
    List<String> terms, {
    required bool toChinese,
  }) async {
    final unique = terms.where((t) => t.trim().isNotEmpty).toSet().toList();
    if (unique.isEmpty) return const {};
    final target = toChinese ? 'Chinese' : 'English';
    try {
      final prompt = 'Translate the following ${unique.length} short work '
          'terms into $target. Output EXACTLY ${unique.length} lines, one '
          'translation per line, in the SAME ORDER as given. Output ONLY the '
          'translations — no numbering, no bullets, no explanations. Keep '
          'model numbers / acronyms unchanged. If a term is already in '
          '$target, output it unchanged.\n\n${unique.join('\n')}';
      final text = await _chat(
        temperature: 0.1,
        responseTimeout: const Duration(seconds: 60),
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      final content = _extractContentMultiLine(text);
      // Parse tolerantly: prefer "original => translation" lines, else zip
      // bare translation lines with the input by order.
      final result = <String, String>{};
      final arrowLines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.contains('=>'))
          .toList();
      if (arrowLines.length >= unique.length) {
        for (final line in arrowLines) {
          final idx = line.indexOf('=>');
          final orig = line
              .substring(0, idx)
              .trim()
              .replaceFirst(RegExp(r'^[-*\d.\s]+'), '');
          final trans = line.substring(idx + 2).trim();
          if (orig.isNotEmpty && trans.isNotEmpty) result[orig] = trans;
        }
      } else {
        final lines = content
            .split('\n')
            .map((l) => l.trim().replaceFirst(RegExp(r'^[-*\d.\s]+'), ''))
            .where((l) => l.isNotEmpty)
            .toList();
        for (var i = 0; i < unique.length && i < lines.length; i++) {
          result[unique[i]] = lines[i];
        }
      }
      return result;
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Translation request timed out.');
    }
  }

  /// Generates a COMPLETE structured report in one LLM call, following the
  /// report-generation spec (see [ReportService.fullReportPrompt]). The
  /// model receives every task with its full in-period execution log and
  /// produces the entire Markdown document — unlike [enhanceTask] which
  /// only yields a per-task title translation + short summary.
  ///
  /// [systemPrompt] carries the spec rules; [taskData] is the formatted
  /// input block (date range + all tasks). Throws [AiServiceException] on
  /// any failure — callers fall back to the deterministic template.
  Future<String> generateFullReport({
    required String systemPrompt,
    required String taskData,
  }) async {
    try {
      final baseMessages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': taskData},
      ];
      // A full report over many tasks routinely exceeds a single 8192-token
      // completion (it was being cut off mid-section, e.g. stopping at
      // "4. Plan for Next Period"), so use a generous budget. If the model
      // STILL hits its own output cap (finish_reason: length) we ask it to
      // continue where it left off, repeating until the report is complete —
      // the result always contains all 5 sections. Streaming is used for
      // every model so long generations are bounded only by the gap between
      // chunks, not a whole-response timeout.
      var result = await _chatStream(
        temperature: 0.3,
        maxTokens: _isReasoningModel(model) ? 32768 : 16384,
        messages: baseMessages,
      );
      var content = result.content;
      var continuations = 0;
      while (result.truncated && continuations < 3) {
        continuations++;
        result = await _chatStream(
          temperature: 0.3,
          maxTokens: _isReasoningModel(model) ? 32768 : 16384,
          messages: [
            ...baseMessages,
            {'role': 'assistant', 'content': content},
            {
              'role': 'user',
              'content': 'The report above was cut off mid-way. Continue '
                  'EXACTLY where you stopped and finish the remaining '
                  'sections. Do NOT repeat anything already written. Output '
                  'ONLY the continuation, with no preamble.',
            },
          ],
        );
        content += result.content;
      }
      // Strip wrapping code fences some models emit around the document.
      content = _stripFences(content);
      if (content.trim().isEmpty) {
        throw AiServiceException('AI returned an empty report.');
      }
      return content.trim();
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Full-report generation timed out.');
    }
  }

  /// Generates a structured work summary from free-form work-log records
  /// (ported from the LinguaFlow Chrome extension's workreport page).
  ///
  /// [recordsText] is the already-formatted block of records (see
  /// [formatWorkLogRecords]); [dateRange] labels the covered period.
  /// [inputLang]/[outputLang] are language codes (e.g. 'zh', 'en'); the
  /// prompt instructs the model to read the input language but write the
  /// summary entirely in the output language.
  Future<String> summarizeWorkLog({
    required String recordsText,
    required String dateRange,
    required String inputLang,
    required String outputLang,
  }) async {
    try {
      final text = await _chat(
        temperature: 0.1,
        requestTimeout: const Duration(seconds: 20),
        responseTimeout: const Duration(seconds: 120),
        messages: [
          {
            'role': 'system',
            'content': workLogSystemPrompt(
                outputChinese: outputLang == 'zh', dateRange: dateRange),
          },
          {
            'role': 'user',
            'content': workLogUserPrompt(
              recordsText: recordsText,
              dateRange: dateRange,
              inputLang: inputLang,
              outputLang: outputLang,
            ),
          },
        ],
      );
      final result = _extractContentMultiLine(text).trim();
      if (result.isEmpty) {
        throw AiServiceException('Empty summary returned by the model.');
      }
      return autoFormatResult(result);
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Summary request timed out.');
    }
  }

  /// AI Parse page (v1.6.0): parses / summarizes arbitrary content (pasted
  /// notes, attached documents, email threads) according to the user's
  /// free-form instructions. [email] selects the email-thread playbook
  /// (condensed from the app's email-thread-summarizer skill): timeline in
  /// chronological order, technical fidelity, risks and a per-party to-do
  /// list. The raw markdown output is returned untouched.
  Future<String> analyzeContent({
    required String content,
    required String instructions,
    bool email = false,
  }) async {
    final user = instructions.trim().isEmpty
        ? content
        : '【解析要求】\n${instructions.trim()}\n\n———\n\n【内容】\n$content';
    try {
      final text = await _chat(
        temperature: 0.3,
        maxTokens: 3000,
        responseTimeout: const Duration(seconds: 150),
        messages: [
          {
            'role': 'system',
            'content': email ? emailThreadSystemPrompt : contentAnalyzeSystemPrompt,
          },
          {'role': 'user', 'content': user},
        ],
      );
      final result = _extractContentMultiLine(text).trim();
      if (result.isEmpty) {
        throw AiServiceException('Empty analysis returned by the model.');
      }
      return result;
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Analysis request timed out.');
    }
  }

  /// Generic playbook for the AI Parse analyze mode: structured markdown,
  /// verbatim technical fidelity, one fact per line, no fabrication.
  @visibleForTesting
  static const String contentAnalyzeSystemPrompt = r'''
# 角色
你是资深技术分析助理，面向硬件/项目工程师（NPI 电动自行车项目）。

# 任务
按用户给出的【解析要求】对【内容】进行解析与总结；未给出要求时，输出一份结构化要点总结。

# 铁律
1. 绝不编造：内容中没有的信息禁止生成；信息不足时明确指出缺什么。
2. 数字保真：数值、型号、料号、寄存器名、命令名、日期与原文逐字一致，禁止四舍五入或泛化。
3. 一条一个事实：每个要点只讲一个事实/事件/决策，禁止合并。
4. 结构化：markdown 标题 + 编号/列表分区，禁止平铺长段落。
5. 语言：跟随内容语言（中文内容输出中文）。

# 输出
仅输出 markdown 结果本身，无额外解释、无代码围栏。
''';

  /// Email-thread playbook, condensed from the app's
  /// email-thread-summarizer skill: chronological timeline, cross-checked
  /// technical points, risks, and a per-party to-do list.
  @visibleForTesting
  static const String emailThreadSystemPrompt = r'''
# 角色
你是面向硬件/项目工程师的项目秘书。用户给你客户或合作伙伴的邮件线程（常中英混杂、倒序引用、夹带签名档与保密声明），你负责理清并总结。

# 铁律（违反即为失败）
1. 绝不编造：没有邮件正文就明确说明缺少内容，绝不凭空生成。
2. 数字保真：所有数值、型号、寄存器名、命令名、日期与原文逐字一致（如 4.19 V、0xF091、CAL_COV 原样保留）。
3. 数值漂移必须标注：同一参数多封邮件中变化时，以最新一封为准，并在风险区标出变更过程。
4. 区分已拍板与未拍板：只有最新邮件明确决定的写"已决定"；讨论未定案的写"未拍板/待澄清"。
5. 标题≠范围：邮件标题涵盖范围与最终实际决定范围不一致时，必须指出差异。
6. 去噪不丢信息：剥离签名档、保密声明、引用标记（>、On ... wrote:），但被引用段落里的实质内容必须纳入时间线。
7. 时间正序：把线程按时间从早到晚重排后再总结。

# 输出格式（markdown，章节顺序固定）
## 邮件线程详细总结
### 一、主题与背景
- **邮件主题**：`<Subject>`
- **双方**：<甲方（姓名，职位，公司）> ↔ <乙方（姓名，职位，公司）>
- **对象**：<项目/产品/芯片型号等>
- **核心诉求演变**：<最初诉求> → <最终结论>

### 二、时间线（按时间正序，共 N 封）
| 日期 | 发件人 | 关键内容 |
|---|---|---|
| MM-DD | XXX | 1~3 句：诉求/结论/关键数字 |
（每封一行，纯礼节/催办邮件也要列出）

### 三、技术要点
1. **<要点一>**：<结论>（无法核对的注明"未验证"）

### 四、风险与注意点
- **数值已变更**：<旧值> → <新值>，以新值为准
- **范围差异**：<标题/早期讨论范围> vs <实际决定范围>
- **依赖关系**：<谁等谁，先后顺序>
- **未明确的点**：<容差/参数/决策缺口，逐条列出>

## To Do List
### A. 我方
| # | 优先级 | 事项 | 验收标准 | 依赖 |
|---|---|---|---|---|
| A1 | 🔴 P0 | <动词开头的可执行动作> | <怎样算完成> | <前置项或"无"> |
### B. 对方
| # | 责任人 | 事项 |
（只收录对方明确承诺/认领的事项）
### C. 联合验证（后续节点）
- [ ] <双方共同完成的验证项>

优先级：P0 = 阻塞交付或有明确期限；P1 = 有依赖需排期；P2 = 记录归档。
仅输出 markdown 结果本身，无额外解释、无代码围栏。
''';

  /// AI Prompts page (v1.5.7): rewrites a rough user requirement into an
  /// expert-grade, copy-ready prompt following the prompt-engineering
  /// playbook in [promptEngineerSystemPrompt]. The model may answer with up
  /// to 3 clarifying questions when key info is missing — the raw output is
  /// returned untouched so the UI can render whatever shape came back.
  Future<String> generatePrompt(String requirement) async {
    try {
      final text = await _chat(
        temperature: 0.5,
        maxTokens: 2000,
        responseTimeout: const Duration(seconds: 120),
        messages: [
          {'role': 'system', 'content': promptEngineerSystemPrompt},
          {'role': 'user', 'content': '# 用户需求\n$requirement'},
        ],
      );
      final result = _extractContentMultiLine(text).trim();
      if (result.isEmpty) {
        throw AiServiceException('Empty prompt returned by the model.');
      }
      return result;
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Prompt generation timed out.');
    }
  }

  /// System prompt for the AI Prompts page (exposed for tests): the
  /// prompt-engineering expert persona, workflow, quality rules and the
  /// strict output contract. The user's rough requirement travels as the
  /// user turn under the `# 用户需求` heading (the `{{input}}` slot of the
  /// original template).
  @visibleForTesting
  static const String promptEngineerSystemPrompt = r'''
# 角色
你是资深 AI 提示词工程专家，精通主流模型（Claude/GPT/Gemini 等）的指令遵循特性。
你的唯一任务：把用户给出的粗糙需求，改写成一条专家级、可直接复制使用的提示词。

# 工作流程
1. 解析输入，提取：任务类型、目标产物、受众、领域、约束条件、输出格式、语言；
2. 判断需求完整度：
   - 仅当缺失【会直接导致产物错误】的关键信息时（如分析任务无数据来源、
     写作任务无受众且无法合理推断），输出最多 3 个澄清问题后停止，等待补充；
   - 软件需求类特例：平台与技术栈缺失时优先追问——这是必然导致产物错误的信息，
     问句不超过 2 个："目标平台？（网页/iOS/Android/Windows桌面/跨端）"
     "有技术栈偏好吗？没有则由我推荐"；其余信息照常推断补全；
   - 其余所有缺失信息一律基于常识补全并标注假设，禁止追问；
3. 按任务类型选用骨架：
   - 软件/应用需求类（网页/Web App/移动端/桌面端通用）：
     一句话定位 → 平台与技术栈 → 用户与使用场景 → 功能清单（编号，逐条可验收）
     → 关键交互与视觉要求 → 数据/存储/集成 → 明确不做的事项 → 验收标准；
   - 编程实现类（技术方案已定的具体开发任务）：
     角色 → 目标 → 技术约束 → 实现要求 → 测试要求 → 验收标准
     → 执行规则（先诊断后动手：改 bug/回归类任务先报根因再修；
        遇阻即停：与现有方案冲突时停下来给选项，不自行换路线）→ 禁止事项；
   - 写作/文案类：角色 → 受众与语气 → 任务 → 结构要求 → 参考示例 → 禁止事项；
   - 分析/决策类：背景 → 问题定义 → 分析框架 → 输出格式 → 判断标准；
   - 其他通用：目标 → 上下文 → 要求 → 输出格式。
4. 按「质量规则」逐条自检后输出最终提示词。

# 质量规则（生成物必须全部满足）
1. 省 token：零客套——禁用"请你/麻烦/一名优秀的"；一句话说清的不写两句；
   简单任务全稿 <150 字，中等 <400 字，复杂任务也只保留影响产出的信息；
2. 明确：一切可量化处写数值（字数/条数/版本/文件路径/格式），
   禁用"尽量/适当/一些/相关"等模糊词；
3. 结构化：用 markdown 标题或编号分区，每区单一职责，便于执行方 AI 定位指令；
4. 验收内嵌：必须含"完成标准"，让执行方 AI 能自检是否达标；
5. 负面清单：列至少 2 条禁止项（取自该任务类型最常见的跑偏方向）；
6. 假设透明：你补全的信息集中在末尾「⚠ 假设（可修改）」区块，不散落正文；
7. 语言：默认生成中文提示词，用户明示英文场景时除外。

# 输出格式（严格遵守，不要输出任何额外解释）
### 📋 提示词
（代码块包裹的完整提示词正文）

### ⚠ 假设（可修改）
- （仅当第 2 步有补全时输出此节）

### 💡 使用建议
一句话：适配的模型类型与最值得调整的参数。
''';

  /// Extracts the FIRST fenced code block from the AI output — the prompt
  /// body proper — for the one-click Copy button. Returns the whole output
  /// unchanged when no code block is found.
  static String extractPromptBody(String aiOutput) {
    final m = RegExp(r'```[a-zA-Z]*\n([\s\S]*?)```').firstMatch(aiOutput);
    if (m == null) return aiOutput;
    return m.group(1)?.trim() ?? aiOutput;
  }

  /// Formats a list of (timestamp, content) work records into the numbered,
  /// `---`-separated block the summarizer prompt expects.
  static String formatWorkLogRecords(
      List<({int timestamp, String content})> records) {
    final f = DateFormat('yyyy-MM-dd HH:mm');
    final buf = StringBuffer();
    for (var i = 0; i < records.length; i++) {
      if (i > 0) buf.write('\n\n---\n\n');
      buf.write(
          '[${i + 1}] ${f.format(DateTime.fromMillisecondsSinceEpoch(records[i].timestamp))}\n'
          '${records[i].content}');
    }
    return buf.toString();
  }

  /// System prompt for the work-log summarizer (exposed for tests).
  @visibleForTesting
  static String workLogSystemPrompt({
    required bool outputChinese,
    required String dateRange,
  }) {
    if (outputChinese) {
      return '你是工作汇报总结助手。请先通读全部工作记录、理解整体上下文：'
          '识别主要工作主题，将相互关联的事项归类到同一工作类别（同一项目、'
          '同一专项或同类事务），把握时间脉络与因果关联，'
          '区分已完成、进行中与受阻的工作；在充分理解、归类和思考的基础上，'
          '再提炼关键要点，生成结构化的中文总结。\n\n'
          '输出格式（严格遵守，不得增删层级，不得更换或省略emoji）：\n'
          '## 📋 工作总结 ($dateRange)\n'
          '### 🔑 要点总结\n'
          '- （3-5 条，概括本次工作记录的核心结论）\n'
          '### 📝 要点详述\n'
          '**1. 议题标题**\n'
          '- 要点\n'
          '  - 细节\n'
          '    - 更细的细节\n'
          '**2. 议题标题**\n'
          '- 要点\n'
          '  - 子项\n\n'
          '硬性规则：\n'
          '- 只输出纯Markdown，严禁输出LaTeX、美元符号或"\$1"之类的编号占位符；\n'
          '- 保持层级结构：一级以"- "开头，二级用两个空格缩进"  - "，'
          '三级用四个空格缩进"    - "，严禁把所有内容写成平铺的段落；\n'
          '- 每条一个事实：一行只说一件事，不要把多件事合并到一行；\n'
          '- 原文的料号、型号、编号、缩写、测量值、设备名原样保留（如"FEB-150"），'
          '不要改写或泛化这些标识；但"原样保留"仅指这类标识本身：'
          '所有描述性文字（包括英文描述和括号注释）都必须翻译成中文，'
          '不要保留未翻译的外文描述；\n'
          '- 已经存在的机制在条目末尾标注 (already in place)，待办事项标注 *To-do*；\n'
          '- 议题标题用"**N. 标题**"加粗格式，编号用纯数字"1. 2. 3."；'
          '每个议题代表一个工作类别或主题，把相互关联的记录归并到同一议题，'
          '不要按时间顺序逐条流水账式罗列；\n'
          '- 思考过程只在内部进行，不要输出任何分析步骤或额外说明。';
    }
    return 'Role: work summarizer.\n'
        'First read ALL the records and understand the overall context: '
        'identify the main work themes, categorize related items into the '
        'same work category (same project, same initiative, or similar type '
        'of work), follow the chronological progression and cause-effect '
        'links, and distinguish completed vs in-progress vs blocked work. '
        'Only after this understanding, categorization and reflection, '
        'distill the key points and write the '
        'summary.\n'
        'Rule: read the input but write ONLY in the requested output language.\n'
        'Output EXACTLY this Markdown structure (do not add or remove levels, '
        'do not swap or drop the emoji):\n'
        '## 📋 Work Summary\n'
        '### 🔑 Key Points\n'
        '- (3-5 bullets summarizing the core conclusions of these records)\n'
        '### 📝 Detailed Breakdown\n'
        '**1. Topic title**\n'
        '- point\n'
        '  - detail\n'
        '    - finer detail\n'
        '**2. Topic title**\n'
        '- point\n'
        '  - sub-item\n\n'
        'Hard rules:\n'
        '- Output plain Markdown only. NEVER output LaTeX, dollar signs, or '
        '"\$1"-style numbering placeholders.\n'
        '- Preserve the hierarchy: level 1 starts with "- ", level 2 is '
        'indented with two spaces "  - ", level 3 with four spaces "    - ". '
        'NEVER flatten everything into plain paragraphs.\n'
        '- One fact per line: each bullet states a single fact — do not merge '
        'multiple facts into one line.\n'
        '- Keep part numbers, model numbers, abbreviations, measurements '
        'and station names from the source verbatim (e.g. "FEB-150") — '
        'never rewrite or generalize those identifiers. But "verbatim" '
        'applies ONLY to such identifiers: ALL descriptive words and '
        'phrases — including any Chinese text and parenthetical notes '
        'like "(带双面胶)" — MUST be translated into the requested output '
        'language; never leave a Chinese description untranslated.\n'
        '- Append (already in place) to items describing existing mechanisms, '
        'and mark to-do items with *To-do*.\n'
        '- Topic titles use the bold form "**N. Title**" numbered with plain '
        'digits "1. 2. 3."; each topic represents ONE work category or theme '
        '— group related records into the same topic instead of listing them '
        'chronologically one by one.\n'
        '- Keep your reasoning internal — output ONLY the final summary, no '
        'analysis steps or extra commentary.';
  }

  /// User prompt for the work-log summarizer (exposed for tests).
  @visibleForTesting
  static String workLogUserPrompt({
    required String recordsText,
    required String dateRange,
    required String inputLang,
    required String outputLang,
  }) {
    final inputName = _langName(inputLang);
    final outputName = _langName(outputLang);
    if (outputLang == 'zh') {
      return '请用$outputName总结以下工作记录（$dateRange）：\n\n$recordsText';
    }
    return 'Produce a $outputName summary of these work records ($dateRange).\n'
        'Respond ENTIRELY in $outputName. Do NOT write any $inputName.\n\n'
        '=== BEGIN INPUT (read in $inputName, respond in $outputName) ===\n'
        '$recordsText\n'
        '=== END INPUT ===\n\n'
        'Now write the $outputName summary:';
  }

  static String _langName(String code) => _workLogLangNames[code] ?? code;

  static const _workLogLangNames = {
    'zh': 'Chinese',
    'en': 'English',
    'ja': 'Japanese',
    'ko': 'Korean',
    'fr': 'French',
    'de': 'German',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'ar': 'Arabic',
    'it': 'Italian',
    'nl': 'Dutch',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
    'ms': 'Malay',
    'tr': 'Turkish',
    'pl': 'Polish',
    'sv': 'Swedish',
    'da': 'Danish',
    'fi': 'Finnish',
    'el': 'Greek',
    'cs': 'Czech',
    'ro': 'Romanian',
    'hu': 'Hungarian',
    'uk': 'Ukrainian',
    'hi': 'Hindi',
    'bn': 'Bengali',
    'he': 'Hebrew',
    'fa': 'Persian',
  };

  /// Strips `"$1"`-style numbering placeholders that some models emit
  /// (e.g. `#### $1. Title` or a bare `$1` line). The digit is kept and the
  /// dollar sign dropped, so `#### $1. Title` becomes `#### 1. Title`.
  /// Real inline LaTeX is left alone because genuine TeX rarely starts with
  /// a bare integer right after `$`.
  static String stripDollarPlaceholders(String text) =>
      text.replaceAllMapped(RegExp(r'\$(\d+)\$?'), (m) => m.group(1) ?? '');

  /// Normalizes LLM output whitespace/markdown the same way the extension
  /// did: unify newlines, trim trailing spaces, collapse 3+ blank lines,
  /// strip leading/trailing blanks, tidy list-marker spacing and CJK
  /// punctuation spacing.
  @visibleForTesting
  static String autoFormatResult(String text) {
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    t = t.split('\n').map((l) => l.trimRight()).join('\n');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    t = t.replaceAll(RegExp(r'^\n+'), '').replaceAll(RegExp(r'\n+$'), '');
    t = stripDollarPlaceholders(t);
    // NOTE: these use replaceAllMapped because Dart's replaceAll does NOT
    // interpret "$1"-style group references — it would insert the literal
    // text "$1" into the output (which is exactly the artifact that leaked
    // into exported summaries before v1.4.21).
    t = t.replaceAllMapped(
        RegExp(r'^([\s]*[-*+])\s{2,}', multiLine: true), (m) => '${m[1]} ');
    t = t.replaceAllMapped(
        RegExp(r'^([\s]*\d+\.)\s{2,}', multiLine: true), (m) => '${m[1]} ');
    t = t.replaceAllMapped(
        RegExp(r'([。！？；])([^\n\s])'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAllMapped(RegExp(r'\s+([。！？，；：、])'), (m) => '${m[1]}');
    return t;
  }

  // ------------------------------------------------------------------

  static String _enhancePrompt(bool chinese) => chinese
      ? '你是工作汇报助手。请先整体理解该任务：结合标题、描述、子步骤与报告期内的'
          '执行日志，思考任务的实际进展、关键成果与因果关联；再把报告期内的执行日志'
          '按工作类别归类（如排查定位、方案实施、验证测试、协调沟通等），'
          '在理解与归类的基础上提炼要点，再按以下格式输出：\n'
          'TITLE: <把任务标题翻译成中文，保留型号/缩写等技术术语>\n'
          'SUMMARY:\n'
          '- <要点1>\n'
          '- <要点2>\n'
          '要求：SUMMARY 下用 1~3 个要点总结该任务在报告期内的执行日志'
          '（已完成的任务要总结实际完成的内容）；每个要点覆盖一个工作类别/方面、'
          '把同类工作合并到同一要点，不要逐条罗列日志；每个要点单独一行、以"- "开头、'
          '信息必须完整自洽、禁止在半途截断（单条建议不超过40个汉字）；'
          '若期内无日志则总结任务当前状态。'
          '除 TITLE 行与 SUMMARY 要点外，不要任何额外说明、引号或markdown。'
      : 'You are a work-report assistant. First understand the task as a '
          'whole — relate its title, description, sub-steps and the execution '
          'logs inside the reporting period, and reason about what actually '
          'progressed and what was accomplished; then categorize those '
          'execution-log entries into work categories (e.g. investigation, '
          'implementation, verification, coordination) and distill the key '
          'points from that categorization. Then output in this exact '
          'format:\n'
          'TITLE: <the task title translated into English, keeping model '
          'numbers / acronyms unchanged>\n'
          'SUMMARY:\n'
          '- <point 1>\n'
          '- <point 2>\n'
          'Rules: write the TITLE and EVERY SUMMARY bullet in English. The '
          'task information below may be in Chinese — translate ALL of it '
          'into English; your ENTIRE output must contain ZERO Chinese '
          'characters (any Chinese character in the output is a failure). '
          'Under SUMMARY, give 1-3 bullet points summarizing the '
          "task's execution logs inside the reporting period (for completed "
          'tasks, summarize WHAT was accomplished); each bullet covers ONE '
          'work category/aspect — merge same-category work into the same '
          'bullet instead of listing log entries one by one; each point on '
          'its own '
          'line starting with "- ", complete and self-contained — NEVER cut '
          'a phrase short (aim for one line, roughly 100 chars max); if '
          'there are no logs in the period, summarize the current task '
          'state. Output nothing except the TITLE line and the SUMMARY '
          'bullets — no extra prose, quotes or markdown.';

  /// Exposed for tests so the language contract of the enhance prompt can
  /// be asserted without making a network call.
  @visibleForTesting
  static String enhancePromptForTest(bool chinese) => _enhancePrompt(chinese);

  /// Exposed for tests so the reasoning-model detection (which decides
  /// whether `temperature` is omitted) can be asserted without a network
  /// call.
  @visibleForTesting
  static bool isReasoningModelForTest(String model) =>
      _isReasoningModel(model);

  /// Compact plain-text digest of a task fed to the summarizer. Includes
  /// EVERY execution-log entry inside the report period ([periodEntries]).
  static String _taskDigest(Task t, List<ExecutionEntry> periodEntries) {
    final b = StringBuffer('title: ${t.title}');
    if (t.description != null && t.description!.trim().isNotEmpty) {
      var d = t.description!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (d.length > 300) d = '${d.substring(0, 300)}…';
      b.write('\ndescription: $d');
    }
    b.write('\nstatus: ${t.status.name}, priority: ${t.priority.label}');
    if (t.subSteps.isNotEmpty) {
      final done = t.subSteps.where((s) => s.completed).length;
      final names = t.subSteps
          .take(6)
          .map((s) => '${s.completed ? '[x]' : '[ ]'} ${s.title}')
          .join('; ');
      b.write('\nsub-steps ($done/${t.subSteps.length}): $names');
    }
    if (periodEntries.isNotEmpty) {
      final f = DateFormat('MM-dd');
      var budget = 1200; // keep the prompt bounded for chatty tasks
      final lines = <String>[];
      for (final e in periodEntries) {
        final line =
            '${f.format(e.timestamp)} ${e.type.name}: ${e.content.replaceAll(RegExp(r'\s+'), ' ').trim()}';
        if (budget - line.length < 0) {
          lines.add('…(${periodEntries.length - lines.length} more)');
          break;
        }
        budget -= line.length;
        lines.add(line);
      }
      b.write(
          '\nexecution log in reporting period (${periodEntries.length} entries):\n'
          '${lines.join('\n')}');
    } else {
      b.write('\nexecution log in reporting period: (none)');
    }
    return b.toString();
  }

  /// Parses the "TITLE: ... / SUMMARY: ..." reply. Tolerant of BOTH
  /// shapes models emit:
  ///   TITLE: X
  ///   SUMMARY: single line here
  /// and
  ///   TITLE: X
  ///   SUMMARY:
  ///   - bullet one
  ///   - bullet two
  /// The bullet form used to yield an EMPTY summary (only same-line text
  /// was read), which aiEnhance then dropped — silently pushing tasks
  /// (typically completed ones with multi-point results) back to the
  /// heuristic Details. Returns the summary as bullet lines joined by
  /// '\n' (markers stripped); falls back to the whole reply when no
  /// SUMMARY line exists at all. Bullets are kept at FULL length — an
  /// earlier 120-char cap here truncated complete summaries, which users
  /// perceived as "the Details content is cut off".
  static ({String title, String summary}) _parseEnhance(
      String raw, String originalTitle) {
    String? title;
    final bullets = <String>[];
    var inSummary = false;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      final upper = t.toUpperCase();
      if (upper.startsWith('TITLE:')) {
        title ??= t.substring('TITLE:'.length).trim();
        inSummary = false;
        continue;
      }
      if (upper.startsWith('SUMMARY:')) {
        final rest = t.substring('SUMMARY:'.length).trim();
        if (rest.isNotEmpty) bullets.add(_stripBullet(rest));
        inSummary = true;
        continue;
      }
      if (inSummary && t.isNotEmpty) bullets.add(_stripBullet(t));
    }
    if (title == null || title.isEmpty) title = originalTitle;
    var summary = bullets.where((s) => s.isNotEmpty).take(4).join('\n');
    if (summary.isEmpty) {
      // No SUMMARY line at all — salvage whatever is not a TITLE: or
      // SUMMARY: marker line.
      summary = raw
          .split('\n')
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty &&
              !s.toUpperCase().startsWith('TITLE:') &&
              !s.toUpperCase().startsWith('SUMMARY:'))
          .map(_stripBullet)
          .where((s) => s.isNotEmpty)
          .take(4)
          .join('\n');
    }
    return (title: title, summary: summary);
  }

  /// Removes a leading list marker ("-", "*", "•", "1." / "1)") from a
  /// summary line so the renderer controls the bullet styling.
  static String _stripBullet(String s) =>
      s.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), '').trim();

  /// Pulls the assistant text out of an OpenAI-style chat response body,
  /// preserving line breaks — needed for the two-line TITLE:/SUMMARY:
  /// reply of [enhanceTask].
  String _extractContentMultiLine(String raw) {
    final decoded = jsonDecode(_stripFences(raw));
    if (decoded is Map<String, dynamic> &&
        decoded['choices'] is List &&
        (decoded['choices'] as List).isNotEmpty) {
      final content =
          (decoded['choices'] as List).first?['message']?['content'];
      if (content is String) return content.trim();
    }
    return raw.trim();
  }

  /// Resolves the chat-completions endpoint, validating the configured
  /// base URL first. Throws an [AiServiceException] with an actionable
  /// message instead of dart:io's inscrutable "No host specified in
  /// URI" ArgumentError when the user forgot the http(s):// scheme or
  /// pasted a broken URL.
  Uri _buildUri() {
    final uri = Uri.tryParse(_normalizeBaseUrl(baseUrl));
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw AiServiceException('Invalid AI base URL "$baseUrl" — expected '
          'http(s)://host[:port][/v1]. Fix it in Settings → AI.');
    }
    return uri.resolve('chat/completions');
  }

  String _normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    // Accept both ".../v1" and ".../v1/chat/completions" style inputs.
    if (u.endsWith('/chat/completions')) {
      u = u.substring(0, u.length - '/chat/completions'.length);
    }
    if (!u.endsWith('/v1')) {
      u = '$u/v1';
    }
    return '$u/';
  }

  List<ParsedTask> _parseResponse(String raw) {
    final decoded = jsonDecode(_stripFences(raw));
    final Map<String, dynamic> root =
        decoded is Map<String, dynamic> ? decoded : {'tasks': decoded};

    // OpenAI wrapper: {"choices":[{"message":{"content":"..."}}]}
    dynamic payload = root;
    if (root.containsKey('choices') && root['choices'] is List) {
      final choices = root['choices'] as List;
      if (choices.isNotEmpty) {
        final content = choices.first?['message']?['content'];
        if (content is String) {
          payload = jsonDecode(_stripFences(content));
        }
      }
    }

    final list = (payload is Map && payload['tasks'] is List)
        ? payload['tasks'] as List
        : (payload is List ? payload : <dynamic>[]);

    return list
        .whereType<Map>()
        .map((m) => _mapTask(Map<String, dynamic>.from(m)))
        .where((t) => t.title.trim().isNotEmpty)
        .toList();
  }

  ParsedTask _mapTask(Map<String, dynamic> m) {
    return ParsedTask(
      title: (m['title'] ?? '').toString().trim(),
      description: (m['description'] ?? '').toString().trim(),
      priority: _mapPriority((m['priority'] ?? '').toString()),
      tags: _stringList(m['tags']),
      subSteps: _stringList(m['subSteps'] ?? m['sub_steps'] ?? m['steps']),
    );
  }

  Priority _mapPriority(String raw) {
    final p = raw.trim().toUpperCase().replaceAll(RegExp(r'[^0-3]'), '');
    switch (p) {
      case '0':
        return Priority.p0Critical;
      case '1':
        return Priority.p1High;
      case '3':
        return Priority.p3Low;
      default:
        return Priority.p2Medium;
    }
  }

  List<String> _stringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return [];
  }

  String _stripFences(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }

  String _shorten(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

class AiServiceException implements Exception {
  final String message;
  AiServiceException(this.message);

  @override
  String toString() => message;
}
