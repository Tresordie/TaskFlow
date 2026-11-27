/// Timeline visualization for the AI Parse HTML export — Dart port of the
/// voice_transcription reference `src/lib/ai/timeline.ts` (v1.15.3).
///
/// The reference upgrades two markdown shapes into intuitive timelines
/// (timeline.md spec: vertical line + colored phase nodes + date capsules;
/// task style: status rings + strikethrough done + overdue red):
///  * tables carrying a time column (`detectTimeline`),
///  * lists whose items lead with a phase emoji or a date
///    (`parseTimelineListItems`).
/// All markup uses INLINE styles + hex colors so preview / exported HTML /
/// print PDF stay identical (reference header comment).
///
/// Integration mirrors `renderRichMarkdown`: after the mermaid/SVG figure
/// pass, tables are upgraded first, then top-level lists. Block boundaries
/// are located in the HTML string and only the matched block is replaced —
/// the document is NEVER re-serialized through an HTML parser (that would
/// lowercase SVG camelCase attributes like viewBox).
///
/// Emoji literals are written as \u{...} escapes so the source stays
/// encoding-proof (the reference regexes are emoji-alternations).
library;

import 'package:html/dom.dart' as hdom;
import 'package:html/parser.dart' as html_parser;

// ---------- emoji constants (codepoints, see reference EMOJI_COLORS) ----------

const String _eBlueCircle = '\u{1F535}'; // 🔵
const String _eBlueSquare = '\u{1F7E6}'; // 🟦
const String _eBrownCircle = '\u{1F7E4}'; // 🟤
const String _eBrownSquare = '\u{1F7EB}'; // 🟫
const String _eRedCircle = '\u{1F534}'; // 🔴
const String _eRedSquare = '\u{1F7E5}'; // 🟥
const String _eGreenCircle = '\u{1F7E2}'; // 🟢
const String _eGreenSquare = '\u{1F7E9}'; // 🟩
const String _eYellowCircle = '\u{1F7E1}'; // 🟡
const String _eYellowSquare = '\u{1F7E8}'; // 🟨
const String _eOrangeSquare = '\u{1F7E7}'; // 🟧
const String _eWhiteCircle = '\u{26AA}'; // ⚪
const String _eWhiteSquare = '\u{2B1C}'; // ⬜
const String _eBlackCircle = '\u{26AB}'; // ⚫
const String _eDone = '\u{2705}'; // ✅
const String _eFail = '\u{274C}'; // ❌
const String _eBox = '\u{1F4E6}'; // 📦
const String _eWip = '\u{1F6A7}'; // 🚧
const String _eLoop = '\u{1F504}'; // 🔄
const String _eWarn = '\u{26A0}'; // ⚠

/// One timeline row.
class TimelineEntry {
  final String time;
  final String title;
  final String desc;
  final String status;

  /// Explicit node color (list path: emoji semantics; table path: renderer
  /// heuristic fallback).
  final String? color;

  const TimelineEntry({
    required this.time,
    required this.title,
    required this.desc,
    required this.status,
    this.color,
  });
}

/// event = phase dots (blue/brown/red); task = status rings + overdue red.
class TimelineData {
  final List<TimelineEntry> entries;
  final String style; // 'event' | 'task'

  const TimelineData({required this.entries, required this.style});
}

/// One parsed list item input ({text, strong} in the reference).
class TimelineListItem {
  final String text;
  final String? strong;

  const TimelineListItem({required this.text, this.strong});
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Time-column test: header keyword or mm:ss value shape.
bool _isTimeText(String s) =>
    RegExp(r'时间|日期|时间戳|时间点|when|date', caseSensitive: false)
        .hasMatch(s) ||
    RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s.trim());

/// Detects timeline data in a table: needs a time column + a title column
/// (verbatim port of the reference `detectTimeline`).
TimelineData? detectTimeline(List<String> header, List<List<String>> rows) {
  if (rows.length < 2 || header.length < 2) return null;

  var timeCol = header.indexWhere(_isTimeText);
  if (timeCol < 0) {
    // Value-shape fallback: first column all mm:ss.
    timeCol = rows.every((r) => RegExp(r'^\d{1,2}:\d{2}(\.\d+)?$')
            .hasMatch((r.isNotEmpty ? r[0] : '').trim()))
        ? 0
        : -1;
  }
  if (timeCol < 0) return null;

  final used = <int>{timeCol};
  int pick(RegExp re) {
    for (var i = 0; i < header.length; i++) {
      if (!used.contains(i) && re.hasMatch(header[i])) {
        used.add(i);
        return i;
      }
    }
    return -1;
  }

  final statusCol = pick(RegExp(r'状态|完成情况|进度|结果', caseSensitive: false));
  var titleCol =
      pick(RegExp(r'事件|标题|事项|任务|议题|节点|动作|阶段', caseSensitive: false));
  final descCol =
      pick(RegExp(r'内容|说明|详情|描述|要点|备注|结论|负责人|发言人', caseSensitive: false));
  if (titleCol < 0) {
    // No explicit title column: first unused one.
    for (var i = 0; i < header.length; i++) {
      if (!used.contains(i)) {
        titleCol = i;
        used.add(i);
        break;
      }
    }
  }
  if (titleCol < 0) return null;

  String cell(List<String> r, int i) =>
      (i >= 0 && i < r.length ? r[i] : '').trim();

  final entries = <TimelineEntry>[];
  for (final r in rows) {
    final time = cell(r, timeCol);
    final title = cell(r, titleCol);
    final status = statusCol >= 0 ? cell(r, statusCol) : '';
    final rest = <String>[
      for (var i = 0; i < header.length; i++)
        if (!used.contains(i)) cell(r, i),
    ].where((s) => s.isNotEmpty).toList();
    final descParts = <String>[
      if (descCol >= 0) cell(r, descCol),
      ...rest,
    ].where((s) => s.isNotEmpty).toList();
    final seen = <String>{};
    final desc = descParts.where(seen.add).join(' · ');
    if (time.isEmpty && title.isEmpty) continue;
    entries.add(
        TimelineEntry(time: time, title: title, desc: desc, status: status));
  }
  if (entries.length < 2) return null;

  return TimelineData(
    entries: entries.take(40).toList(),
    style: statusCol >= 0 ? 'task' : 'event',
  );
}

// ---------- phase / status colors (timeline.md semantics) ----------

String _phaseColor(String text) {
  if (RegExp('完成|$_eDone|成功|通过|正常|已解决', caseSensitive: false)
      .hasMatch(text)) {
    return '#1a7f37';
  }
  if (RegExp('失败|风险|$_eWarn|异常|故障|错误|升级', caseSensitive: false)
      .hasMatch(text)) {
    return '#b42318';
  }
  if (RegExp('卡点|阻塞|停滞|延期|待确认|待补|pending', caseSensitive: false)
      .hasMatch(text)) {
    return '#9a6700';
  }
  return '#0b6bcb';
}

class _TaskStatus {
  final String color;
  final String icon;
  final bool done;
  const _TaskStatus(this.color, this.icon, this.done);
}

_TaskStatus _taskStatus(String text) {
  if (RegExp('完成|$_eDone|已归档|已关闭', caseSensitive: false).hasMatch(text)) {
    return _TaskStatus('#22c55e', _eDone, true);
  }
  if (RegExp('归档|$_eBox', caseSensitive: false).hasMatch(text)) {
    return _TaskStatus('#6b7280', _eBox, true);
  }
  if (RegExp('逾期|失败|$_eFail|超时', caseSensitive: false).hasMatch(text)) {
    return _TaskStatus('#ef4444', _eFail, false);
  }
  return _TaskStatus('#3b82f6', _eWip, false);
}

// ---------- HTML rendering (inline styles, preview/export universal) ----------

/// Event timeline: vertical line + phase dot + date capsule + title/desc.
String _eventTimelineHtml(TimelineData data) {
  final items = data.entries.map((e) {
    final color = e.color ?? _phaseColor('${e.time} ${e.title} ${e.status}');
    return '<div style="position:relative;margin-bottom:16px;padding-left:4px;">\n'
        '  <span style="position:absolute;left:-24px;top:6px;width:11px;height:11px;border-radius:50%;background:$color;border:2px solid #ffffff;box-shadow:0 0 0 1px #d1d5db;"></span>\n'
        '${e.time.isNotEmpty ? '  <span style="display:inline-block;background:#eff6ff;color:#0b6bcb;border-radius:999px;padding:1px 10px;font-size:12px;font-weight:600;">${_esc(e.time)}</span>\n' : ''}'
        '  <div style="font-weight:700;color:#111827;margin-top:3px;">${_esc(e.title)}</div>\n'
        '${e.desc.isNotEmpty ? '  <div style="color:#6b7280;font-size:13px;margin-top:2px;">${_esc(e.desc)}</div>\n' : ''}'
        '</div>';
  }).join('\n');
  return '<div style="border:1px solid #e5e7eb;border-radius:12px;background:#ffffff;padding:20px 24px 8px;">\n'
      '  <div style="position:relative;padding-left:26px;">\n'
      '    <div style="position:absolute;left:9px;top:8px;bottom:14px;width:2px;background:#d1d5db;"></div>\n'
      '    $items\n'
      '  </div>\n'
      '</div>';
}

/// Task timeline: status ring + title (strikethrough when done) + badge.
String _taskTimelineHtml(TimelineData data) {
  final items = data.entries.map((e) {
    final st = _taskStatus(e.status.isNotEmpty ? e.status : e.title);
    final done = st.done || e.status.contains(_eDone);
    final overdue =
        RegExp('逾期|超时|$_eFail').hasMatch('${e.status} ${e.title}');
    final titleStyle = done
        ? 'font-weight:700;color:#9ca3af;text-decoration:line-through;'
        : overdue
            ? 'font-weight:700;color:#b42318;'
            : 'font-weight:700;color:#111827;';
    return '<div style="position:relative;margin-bottom:14px;">\n'
        '  <span style="position:absolute;left:-24px;top:2px;width:14px;height:14px;border-radius:50%;background:#ffffff;border:3px solid ${e.color ?? st.color};"></span>\n'
        '  <div style="$titleStyle">${st.icon} ${_esc(e.title)}${e.status.isNotEmpty ? ' <span style="display:inline-block;border-radius:999px;padding:0 8px;font-size:11px;font-weight:600;background:${st.color};color:#ffffff;">${_esc(e.status)}</span>' : ''}</div>\n'
        '${e.time.isNotEmpty ? '  <div style="color:#6b7280;font-size:12px;margin-top:1px;">⏱ ${_esc(e.time)}${overdue ? ' · <span style="color:#b42318;font-weight:600;">已逾期</span>' : ''}</div>\n' : ''}'
        '${e.desc.isNotEmpty ? '  <div style="color:#6b7280;font-size:13px;margin-top:2px;">${_esc(e.desc)}</div>\n' : ''}'
        '</div>';
  }).join('\n');
  return '<div style="border:1px solid #e5e7eb;border-radius:12px;background:#ffffff;padding:20px 24px 8px;">\n'
      '  <div style="position:relative;padding-left:26px;">\n'
      '    <div style="position:absolute;left:9px;top:8px;bottom:12px;width:2px;background:#d1d5db;"></div>\n'
      '    $items\n'
      '  </div>\n'
      '</div>';
}

/// Renders the visual timeline (inline-styled, self-contained).
String renderTimelineHtml(TimelineData data) =>
    data.style == 'task' ? _taskTimelineHtml(data) : _eventTimelineHtml(data);

// ---------- list timeline detection (G-SPEC "phase emoji + date" lists) ----------

/// Phase emoji → semantic color (blue=progress / brown=stalled / red=escalated).
final Map<String, String> _emojiColors = {
  _eBlueCircle: '#0b6bcb', _eBlueSquare: '#0b6bcb',
  _eBrownCircle: '#9a6700', _eBrownSquare: '#9a6700',
  _eRedCircle: '#b42318', _eRedSquare: '#b42318', _eFail: '#b42318',
  _eGreenCircle: '#1a7f37', _eGreenSquare: '#1a7f37', _eDone: '#1a7f37',
  _eYellowCircle: '#9a6700', _eYellowSquare: '#9a6700', _eOrangeSquare: '#9a6700',
  _eWhiteCircle: '#6b7280', _eWhiteSquare: '#6b7280', _eBlackCircle: '#6b7280',
  _eBox: '#6b7280',
};

/// Task-flavored emojis (majority vote renders the task timeline).
final Set<String> _taskEmojis = {_eDone, _eFail, _eWip, _eBox, _eLoop};

/// Leading phase emoji (⚪/⬜ tolerate the U+FE0F variation selector).
final RegExp _leadEmojiRe = RegExp(
    '^(${[..._emojiColors.keys, ..._taskEmojis].map((e) => (e == _eWhiteCircle || e == _eWhiteSquare) ? '$e\\uFE0F?' : e).join('|')})\\s*');

/// Leading date/timestamp: mm/dd, yyyy-mm-dd, mm月dd日 (optional hh:mm) or
/// mm:ss — only counts when followed by whitespace/punctuation.
final RegExp _leadTimeRe = RegExp(
    r'^((?:\d{4}[年/-])?\d{1,2}[./月-]\d{1,2}日?(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?|\d{1,2}:\d{2}(?::\d{2})?)(?=\s|$|[:：、，,—·])');

final RegExp _titleSplitRe = RegExp(r'　|\s{2,}');
final RegExp _fe0fTail = RegExp(r'️$');

String _stripLeadTime(String s) =>
    s.replaceFirst(_leadEmojiRe, '').replaceFirst(_leadTimeRe, '').trim();

class _ParsedListItem {
  final String time;
  final String title;
  final String desc;
  final String? color;
  final bool task;
  const _ParsedListItem(this.time, this.title, this.desc, this.color, this.task);
}

_ParsedListItem? _parseListItem(String text, String? strong) {
  var t = text.trim();
  if (t.isEmpty) return null;
  String? color;
  var task = false;
  final em = _leadEmojiRe.firstMatch(t);
  if (em != null) {
    final emoji = em.group(1)!.replaceFirst(_fe0fTail, '');
    color = _emojiColors[emoji];
    task = _taskEmojis.contains(emoji);
    t = t.substring(em.end).trim();
  }
  final tm = _leadTimeRe.firstMatch(t);
  var time = '';
  if (tm != null) {
    time = tm.group(1)!.trim();
    t = t.substring(tm.end).trim();
  }
  if (em == null && tm == null) return null;

  String title;
  String desc;
  final st = (strong ?? '').trim();
  if (st.isNotEmpty) {
    title = _stripLeadTime(st);
    if (title.isEmpty) {
      // strong wrapped only the timestamp: title falls back to first段.
      final idx = t.indexOf(_titleSplitRe);
      title = idx > 0 ? t.substring(0, idx).trim() : t;
      desc = idx > 0 ? t.substring(idx).trim() : '';
    } else if (t.startsWith(title)) {
      desc = t.substring(title.length).trim();
    } else if (t.contains(title)) {
      desc = t.replaceFirst(title, ' ').trim();
    } else {
      desc = t;
    }
  } else {
    // No bold: full-width space / double space splits title from desc.
    final idx = t.indexOf(_titleSplitRe);
    title = idx > 0 ? t.substring(0, idx).trim() : t;
    desc = idx > 0 ? t.substring(idx).trim() : '';
  }
  return _ParsedListItem(
      time,
      title.isNotEmpty ? title : t.substring(0, t.length.clamp(0, 40)),
      desc,
      color,
      task);
}

/// List items → timeline data: items leading with a phase emoji or a date
/// (≥2 items, ≥60% hits, ≥50% with time — guards against ordinary lists).
TimelineData? parseTimelineListItems(List<TimelineListItem> items) {
  if (items.length < 2) return null;
  final parsed = items.map((it) => _parseListItem(it.text, it.strong)).toList();
  final hits = parsed.where((p) => p != null).length;
  final withTime = parsed.where((p) => p != null && p.time.isNotEmpty).length;
  if (hits < (items.length * 0.6).ceil().clamp(2, items.length)) return null;
  if (withTime < (items.length * 0.5).ceil().clamp(2, items.length)) return null;

  final entries = <TimelineEntry>[];
  var taskVotes = 0;
  var eventVotes = 0;
  for (var i = 0; i < parsed.length; i++) {
    final p = parsed[i];
    if (p == null) {
      // Unmatched items keep their order/content (no loss on upgrade).
      final t = items[i].text.trim();
      final head = t.substring(0, t.length.clamp(0, 60));
      entries.add(TimelineEntry(
        time: '',
        title: head.isNotEmpty ? head : '（无标题）',
        desc: t.length > 60 ? t.substring(60).trim() : '',
        status: '',
      ));
      continue;
    }
    if (p.task) {
      taskVotes++;
    } else if (p.color != null) {
      eventVotes++;
    }
    entries.add(TimelineEntry(
        time: p.time, title: p.title, desc: p.desc, status: '', color: p.color));
  }
  if (entries.length < 2) return null;
  return TimelineData(
    entries: entries.take(40).toList(),
    style: taskVotes > eventVotes ? 'task' : 'event',
  );
}

// ---------- HTML block upgrades (string-located, fragment-parsed) ----------

final RegExp _tableBlockRe =
    RegExp(r'<table\b[^>]*>[\s\S]*?</table>', caseSensitive: false);
final RegExp _listTagRe =
    RegExp(r'<(ul|ol)\b[^>]*>|</(ul|ol)>', caseSensitive: false);

/// Upgrades every timeline-shaped table to the visual timeline HTML
/// (reference renderRichMarkdown table pass).
String upgradeTimelineTables(String body) {
  return body.replaceAllMapped(_tableBlockRe, (m) {
    final data = _tableData(m[0]!);
    return data == null
        ? m[0]!
        : '<div class="md-figure">${renderTimelineHtml(data)}</div>';
  });
}

TimelineData? _tableData(String tableHtml) {
  final tbl = html_parser.parse(tableHtml).querySelector('table');
  if (tbl == null) return null;
  final theadTh = tbl.querySelectorAll('thead th');
  final firstTr = tbl.querySelector('tr');
  final headerEls =
      theadTh.isNotEmpty ? theadTh : (firstTr?.children ?? <hdom.Element>[]);
  final header = headerEls.map((c) => c.text.trim()).toList();
  final tbodyTr = tbl.querySelectorAll('tbody tr');
  final rowEls = tbodyTr.isNotEmpty
      ? tbodyTr
      : tbl.querySelectorAll('tr').skip(headerEls.isNotEmpty ? 1 : 0).toList();
  final rows = rowEls
      .map((tr) => tr.children.map((td) => td.text.trim()).toList())
      .toList();
  return detectTimeline(header, rows);
}

/// Upgrades top-level timeline-shaped lists (reference list pass). Nested
/// lists are tracked by depth so only whole top-level blocks are replaced.
String upgradeTimelineLists(String body) {
  final out = StringBuffer();
  var pos = 0;
  var depth = 0;
  int? start;
  for (final m in _listTagRe.allMatches(body)) {
    final isOpen = m.group(1) != null;
    if (isOpen) {
      if (depth == 0) start = m.start;
      depth++;
    } else if (depth > 0) {
      depth--;
      if (depth == 0 && start != null) {
        out.write(body.substring(pos, start));
        out.write(_upgradeListBlock(body.substring(start, m.end)));
        pos = m.end;
        start = null;
      }
    }
  }
  out.write(body.substring(pos));
  return out.toString();
}

String _upgradeListBlock(String block) {
  final list = html_parser.parse(block).querySelector('ul, ol');
  if (list == null) return block;
  final lis = list.children.where((c) => c.localName == 'li').toList();
  if (lis.length < 2) return block;
  final items = <TimelineListItem>[];
  for (final li in lis) {
    // Nested lists do not contribute to the item text (reference clone).
    for (final n in li.querySelectorAll('ul, ol')) {
      n.remove();
    }
    items.add(TimelineListItem(
        text: li.text.trim(), strong: li.querySelector('strong')?.text));
  }
  final data = parseTimelineListItems(items);
  return data == null
      ? block
      : '<div class="md-figure">${renderTimelineHtml(data)}</div>';
}
