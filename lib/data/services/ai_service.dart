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
    final uri = _buildUri();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');

      final body = jsonEncode({
        'model': model,
        'temperature': 0.2,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': notes},
        ],
      });
      // write() would encode via the request's latin1 default and throw
      // on Chinese text in the notes ("Invalid argument (string)");
      // add() writes raw UTF-8 bytes instead. (request.encoding itself
      // is immutable on HttpClientRequest.)
      request.add(utf8.encode(body));

      final response =
          await request.close().timeout(const Duration(seconds: 90));
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
            'API error ${response.statusCode}: ${_shorten(text)}');
      }

      return _parseResponse(text);
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw AiServiceException('Request timed out. Check base URL / network.');
    } finally {
      client.close(force: true);
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
    final uri = _buildUri();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      // The digest always contains the raw (usually Chinese) task title;
      // write() would encode it as latin1 and dart:io would throw
      // "Invalid argument (string): Contains invalid characters." — so
      // write raw UTF-8 bytes instead.
      request.add(utf8.encode(jsonEncode({
        'model': model,
        'temperature': 0.3,
        // 200 was too tight: a long task title ate most of the completion
        // budget, so replies got cut off BEFORE the SUMMARY section
        // (completed tasks silently fell back to the "done MM-dd"
        // heuristic) or mid-bullet ("…BMS"). 1000 leaves ample room for
        // the TITLE line plus three full bullets in either language.
        'max_tokens': 1000,
        'messages': [
          {'role': 'system', 'content': _enhancePrompt(chinese)},
          {'role': 'user', 'content': _taskDigest(t, periodEntries)},
        ],
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
            'API error ${response.statusCode}: ${_shorten(text)}');
      }
      return _parseEnhance(_extractContentMultiLine(text), t.title);
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Summary request timed out.');
    } finally {
      client.close(force: true);
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
    final uri = _buildUri();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      final prompt = 'Translate the following ${unique.length} short work '
          'terms into $target. Output EXACTLY ${unique.length} lines, one '
          'translation per line, in the SAME ORDER as given. Output ONLY the '
          'translations — no numbering, no bullets, no explanations. Keep '
          'model numbers / acronyms unchanged. If a term is already in '
          '$target, output it unchanged.\n\n${unique.join('\n')}';
      request.add(utf8.encode(jsonEncode({
        'model': model,
        'temperature': 0.1,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
            'API error ${response.statusCode}: ${_shorten(text)}');
      }
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
    } finally {
      client.close(force: true);
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
    final uri = _buildUri();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.add(utf8.encode(jsonEncode({
        'model': model,
        // Low temperature for factual, structured output.
        'temperature': 0.3,
        // A full report with 15-20 tasks typically needs 3000-6000 tokens.
        'max_tokens': 8192,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': taskData},
        ],
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 180));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
            'API error ${response.statusCode}: ${_shorten(text)}');
      }
      var content = _extractContentMultiLine(text);
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
    } finally {
      client.close(force: true);
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
    final uri = _buildUri();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.add(utf8.encode(jsonEncode({
        'model': model,
        'temperature': 0.1,
        'messages': [
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
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 120));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
            'API error ${response.statusCode}: ${_shorten(text)}');
      }
      final result = _extractContentMultiLine(text).trim();
      if (result.isEmpty) {
        throw AiServiceException('Empty summary returned by the model.');
      }
      return autoFormatResult(result);
    } on SocketException catch (e) {
      throw AiServiceException('Network error: ${e.message}');
    } on TimeoutException {
      throw AiServiceException('Summary request timed out.');
    } finally {
      client.close(force: true);
    }
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
          '- 原文的技术术语、编号、缩写、料号、设备名全部原样保留，不要改写或泛化；\n'
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
        '- Keep ALL technical terms, numbers, abbreviations, part numbers and '
        'station names from the source verbatim — do not rewrite or '
        'generalize them.\n'
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
