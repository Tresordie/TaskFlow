import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

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
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
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

      final response = await request.close().timeout(const Duration(seconds: 90));
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
      final response = await request.close().timeout(const Duration(seconds: 30));
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
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 15));
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
      final response = await request.close().timeout(const Duration(seconds: 60));
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

  // ------------------------------------------------------------------

  static String _enhancePrompt(bool chinese) => chinese
      ? '你是工作汇报助手。针对用户给出的单个任务，按以下格式输出：\n'
          'TITLE: <把任务标题翻译成中文，保留型号/缩写等技术术语>\n'
          'SUMMARY:\n'
          '- <要点1>\n'
          '- <要点2>\n'
          '要求：SUMMARY 下用 1~3 个要点总结该任务在报告期内的执行日志'
          '（已完成的任务要总结实际完成的内容）；每个要点单独一行、以"- "开头、'
          '信息必须完整自洽、禁止在半途截断（单条建议不超过40个汉字）；'
          '若期内无日志则总结任务当前状态。'
          '除 TITLE 行与 SUMMARY 要点外，不要任何额外说明、引号或markdown。'
      : 'You are a work-report assistant. For the single task given by the '
          'user, output in this exact format:\n'
          'TITLE: <the task title translated into English, keeping model '
          'numbers / acronyms unchanged>\n'
          'SUMMARY:\n'
          '- <point 1>\n'
          '- <point 2>\n'
          'Rules: under SUMMARY, give 1-3 bullet points summarizing the '
          "task's execution logs inside the reporting period (for completed "
          'tasks, summarize WHAT was accomplished); each point on its own '
          'line starting with "- ", complete and self-contained — NEVER cut '
          'a phrase short (aim for one line, roughly 100 chars max); if '
          'there are no logs in the period, summarize the current task '
          'state. Output nothing except the TITLE line and the SUMMARY '
          'bullets — no extra prose, quotes or markdown.';

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
      b.write('\nexecution log in reporting period (${periodEntries.length} entries):\n'
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
    var summary =
        bullets.where((s) => s.isNotEmpty).take(4).join('\n');
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
      final content = (decoded['choices'] as List).first?['message']?['content'];
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
      throw AiServiceException(
          'Invalid AI base URL "$baseUrl" — expected '
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
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
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
