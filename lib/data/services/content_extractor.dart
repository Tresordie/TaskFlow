import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:xml/xml.dart';

import 'audio_transcription_service.dart';

/// Text extraction for the AI Parse page's file input (v1.6.0).
///
/// Supported: plain text (txt/md/markdown/csv/log/json/eml — .eml emails
/// are plain RFC-822 text), HTML (tags stripped), and the OOXML office
/// formats docx / xlsx / pptx, which are ZIP+XML containers unpacked with
/// the pure-Dart `archive` package. PDF text extraction is pure Dart via
/// `pdf_document` — no native DLLs ship with the app.
///
/// v1.15.0: docx tables are reconstructed as Markdown tables and xlsx is
/// re-extracted sheet-by-sheet with row/column structure preserved (the
/// v1 approach dumped only the shared-strings pool, so the AI could not see
/// which value lived in which cell). Audio files route to
/// [AudioTranscriptionService] — see [audioExtensions] / [isAudioExtension].
///
/// Hard limit: 150 MB per file (user requirement) — enforced BEFORE any
/// read so a huge attachment never lands in memory.
class ContentExtractor {
  ContentExtractor._();

  static const maxFileBytes = 150 * 1024 * 1024; // 150 MB

  /// Extensions accepted by the file picker / extractor.
  static const supportedExtensions = [
    'txt', 'md', 'markdown', 'csv', 'log', 'json', 'eml',
    'html', 'htm', 'xml',
    'docx', 'xlsx', 'pptx',
    'pdf',
  ];

  /// Audio extensions — parsed by the local transcription pipeline instead
  /// of [extract]. `opus/webm/amr` are INCLUDED so picking one yields a
  /// precise "convert to mp3/wav" error rather than a filtered picker.
  static const audioExtensions = [
    'mp3', 'wav', 'm4a', 'aac', 'ogg', 'oga', 'flac', 'm4b',
    'opus', 'webm', 'amr',
  ];

  /// Everything the AI Parse picker accepts (documents + audio).
  static const pickerExtensions = [...supportedExtensions, ...audioExtensions];

  static bool isAudioExtension(String ext) =>
      audioExtensions.contains(ext.toLowerCase());

  /// Extracts the text content of [file]. Throws [FormatException] with a
  /// user-facing message for unsupported extensions or oversized files.
  /// (Audio files never reach here — the session notifier routes them to
  /// the transcription service first.)
  static Future<String> extract(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      if (isAudioExtension(ext)) {
        throw FormatException(
            '音频文件应由转写流水线处理（.$ext 被直接送入文本提取）');
      }
      throw FormatException(
          '不支持的文件类型：.$ext（支持 ${pickerExtensions.join(', ')}）');
    }
    final size = await file.length();
    if (size > maxFileBytes) {
      throw FormatException(
          '文件过大：${(size / 1024 / 1024).toStringAsFixed(1)} MB（上限 150 MB）');
    }

    switch (ext) {
      case 'html':
      case 'htm':
        return stripHtml(await file.readAsString());
      case 'docx':
        return extractDocx(file);
      case 'xlsx':
        return extractXlsx(file);
      case 'pptx':
        return extractPptx(file);
      case 'pdf':
        return extractPdf(file);
      default:
        return (await file.readAsString()).trim();
    }
  }

  /// Strips scripts/styles/tags from HTML, keeping visible text with
  /// block-level line breaks so the AI sees a readable document.
  static String stripHtml(String html) {
    var s = html
        .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // Collapse the whitespace explosion, keep line structure.
    final lines = s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty);
    return lines.join('\n').trim();
  }

  static Archive _openZip(File file) {
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive;
  }

  /// .docx → word/document.xml. v1.15.0: document-order walk — paragraphs
  /// become lines AND `w:tbl` tables are reconstructed as Markdown tables
  /// (`| a | b |` rows), so the AI sees tabular relationships instead of a
  /// flat text dump.
  static String extractDocx(File file) {
    final archive = _openZip(file);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) {
      throw const FormatException('无效的 Word 文档（缺少 document.xml）');
    }
    final xmlStr = utf8.decode(entry.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);
    final lines = <String>[];
    _emitDocxNodes(doc.rootElement, lines);
    final result =
        lines.map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n').trim();
    if (result.isEmpty) {
      throw const FormatException('Word 文档中没有可提取的文本');
    }
    return result;
  }

  /// Recursively emits [node]: `w:p` paragraphs as text lines, `w:tbl`
  /// tables as Markdown tables; other containers are descended into
  /// (document order preserved).
  static void _emitDocxNodes(XmlNode node, List<String> lines) {
    for (final child in node.childElements) {
      if (_localName(child) == 'p') {
        final text = _docxParagraphText(child);
        if (text.trim().isNotEmpty) lines.add(text.trim());
      } else if (_localName(child) == 'tbl') {
        final table = _docxTableMarkdown(child);
        if (table.isNotEmpty) lines.add(table);
      } else {
        _emitDocxNodes(child, lines);
      }
    }
  }

  /// All `w:t` run text of a paragraph; `w:tab` widens to spaces and
  /// `w:br` / `w:cr` become line breaks (flattened to spaces inside cells).
  static String _docxParagraphText(XmlElement paragraph) {
    final buf = StringBuffer();
    void walk(XmlNode node) {
      for (final child in node.childElements) {
        switch (_localName(child)) {
          case 't':
            buf.write(child.innerText);
          case 'tab':
            buf.write('  ');
          case 'br':
          case 'cr':
            buf.write(' ');
          default:
            walk(child);
        }
      }
    }

    walk(paragraph);
    return buf.toString();
  }

  /// `w:tbl` → Markdown table. First row becomes the header row (a
  /// synthetic separator follows). Pipe characters in cells are escaped so
  /// the Markdown table cannot be broken by cell content.
  static String _docxTableMarkdown(XmlElement table) {
    final rows = <List<String>>[];
    for (final tr in table.childElements) {
      if (_localName(tr) != 'tr') continue;
      final cells = <String>[];
      for (final tc in tr.childElements) {
        if (_localName(tc) != 'tc') continue;
        final cellBuf = <String>[];
        for (final p in tc.childElements) {
          if (_localName(p) != 'p') continue;
          final t = _docxParagraphText(p).trim();
          if (t.isNotEmpty) cellBuf.add(t);
        }
        cells.add(cellBuf.join(' ').replaceAll('|', r'\|'));
      }
      rows.add(cells);
    }
    if (rows.isEmpty) return '';

    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    String rowLine(List<String> cells) => '| ' +
        List.generate(width, (i) => i < cells.length ? cells[i] : '')
            .join(' | ') +
        ' |';
    final out = <String>[rowLine(rows.first), '| ' + List.filled(width, '---').join(' | ') + ' |'];
    for (var i = 1; i < rows.length; i++) {
      out.add(rowLine(rows[i]));
    }
    return out.join('\n');
  }

  /// .xlsx → sheet-by-sheet reconstruction (v1.15.0): workbook.xml gives the
  /// sheet names in tab order, the relationship file maps each sheet to its
  /// part, and each worksheet is emitted as `## Sheet: <name>` followed by
  /// TAB-separated rows whose columns are aligned by cell reference — the
  /// AI can now see which value lived in which cell.
  ///
  /// Number/date cells emit the stored value verbatim (date serial numbers
  /// are NOT converted — formatting styles are out of scope for text
  /// extraction). Booleans become TRUE/FALSE.
  static String extractXlsx(File file) {
    final archive = _openZip(file);

    // Shared strings: one entry per <si>, concatenating rich-text runs.
    final shared = <String>[];
    final sst = archive.findFile('xl/sharedStrings.xml');
    if (sst != null) {
      final doc = XmlDocument.parse(utf8.decode(sst.content as List<int>));
      for (final si in doc.findAllElements('si', namespace: '*')) {
        final buf = StringBuffer();
        for (final t in si.descendantElements) {
          if (_localName(t) == 't') buf.write(t.innerText);
        }
        shared.add(buf.toString());
      }
    }

    // Sheet name → part path, via workbook.xml + its relationships.
    final wb = archive.findFile('xl/workbook.xml');
    if (wb == null) {
      throw const FormatException('无效的 Excel 工作簿（缺少 workbook.xml）');
    }
    final relsEntry = archive.findFile('xl/_rels/workbook.xml.rels');
    final rels = <String, String>{};
    if (relsEntry != null) {
      final doc = XmlDocument.parse(utf8.decode(relsEntry.content as List<int>));
      for (final rel in doc.findAllElements('Relationship', namespace: '*')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id == null || target == null) continue;
        rels[id] = target;
      }
    }

    final wbDoc = XmlDocument.parse(utf8.decode(wb.content as List<int>));
    final sheets = <({String name, String partPath})>[];
    for (final sheet in wbDoc.findAllElements('sheet', namespace: '*')) {
      final name = sheet.getAttribute('name') ?? '';
      // r:id (relationship id) — namespace-prefixed attribute.
      final rid = sheet.attributes
          .where((a) => a.name.local == 'id')
          .map((a) => a.value)
          .firstWhere((_) => true, orElse: () => '');
      final target = rels[rid];
      if (target == null || name.isEmpty) continue;
      sheets.add((name: name, partPath: _xlsxSheetPath(target)));
    }
    if (sheets.isEmpty) {
      // Fallback: scan for worksheets directly (nameless).
      final parts = archive.files
          .where((f) =>
              RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (var i = 0; i < parts.length; i++) {
        sheets.add((name: 'Sheet${i + 1}', partPath: parts[i].name));
      }
      if (sheets.isEmpty) return '';
    }

    final out = <String>[];
    for (final sheet in sheets) {
      final entry = archive.findFile(sheet.partPath);
      if (entry == null) continue;
      final text = _xlsxSheetText(
          utf8.decode(entry.content as List<int>), shared);
      if (text.isEmpty) continue;
      out.add('## Sheet: ${sheet.name}\n$text');
    }
    return out.join('\n\n').trim();
  }

  /// Resolves a workbook relationship Target (relative to `xl/`, or
  /// package-absolute `/xl/...`) to a zip entry path.
  static String _xlsxSheetPath(String target) {
    var t = target.replaceAll(r'\', '/');
    if (t.startsWith('/')) return t.substring(1);
    return 'xl/$t';
  }

  /// Parses one worksheet XML into aligned TAB-separated rows.
  static String _xlsxSheetText(String xmlStr, List<String> shared) {
    final doc = XmlDocument.parse(xmlStr);
    final rows = <List<String>>[];
    for (final row in doc.findAllElements('row', namespace: '*')) {
      final cells = <String>[];
      var lastIndex = -1;
      for (final c in row.findElements('c', namespace: '*')) {
        final ref = c.getAttribute('r') ?? '';
        final colIndex = _columnIndexFromRef(ref);
        final value = _xlsxCellValue(c, shared);
        // Pad skipped columns so column positions stay meaningful.
        while (cells.length < colIndex) {
          cells.add('');
        }
        cells.add(value);
        lastIndex = colIndex;
      }
      if (cells.any((v) => v.isNotEmpty)) rows.add(cells);
    }
    return rows.map((r) => r.join('\t').trim()).where((r) => r.isNotEmpty).join('\n');
  }

  /// Cell value by `t` attribute: shared string / inline string / formula
  /// string / boolean / raw number.
  static String _xlsxCellValue(XmlElement c, List<String> shared) {
    final t = (c.getAttribute('t') ?? '').toLowerCase();
    final vElement = c.findElements('v', namespace: '*').isEmpty
        ? null
        : c.findElements('v', namespace: '*').first;
    switch (t) {
      case 's':
        final idx = int.tryParse(vElement?.innerText ?? '') ?? -1;
        return (idx >= 0 && idx < shared.length) ? shared[idx] : '';
      case 'inlinestr':
        final buf = StringBuffer();
        for (final el in c.descendantElements) {
          if (_localName(el) == 't') buf.write(el.innerText);
        }
        return buf.toString();
      case 'b':
        return (vElement?.innerText.trim() == '1') ? 'TRUE' : 'FALSE';
      case 'str':
      case 'n':
      default:
        return vElement?.innerText.trim() ?? '';
    }
  }

  /// "BC3" → column index 54 (0-based). Empty ref → next column.
  static int _columnIndexFromRef(String ref) {
    if (ref.isEmpty) return 0;
    var index = 0;
    for (var i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 0x41 && code <= 0x5A) {
        index = index * 26 + (code - 0x41 + 1);
      } else if (code >= 0x61 && code <= 0x7A) {
        index = index * 26 + (code - 0x61 + 1);
      } else {
        break;
      }
    }
    return index - 1;
  }

  /// .pptx → ppt/slides/slideN.xml sorted by N; one block per slide.
  static String extractPptx(File file) {
    final archive = _openZip(file);
    final slides = archive.files
        .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
        .toList()
      ..sort((a, b) {
        final na = int.parse(RegExp(r'(\d+)').firstMatch(a.name)!.group(1)!);
        final nb = int.parse(RegExp(r'(\d+)').firstMatch(b.name)!.group(1)!);
        return na.compareTo(nb);
      });
    if (slides.isEmpty) {
      throw const FormatException('无效的 PPT 文档（没有幻灯片）');
    }
    final out = <String>[];
    for (var i = 0; i < slides.length; i++) {
      final xmlStr = utf8.decode(slides[i].content as List<int>);
      final text = _xmlToText(xmlStr, paragraphTags: ['a:p']);
      if (text.isNotEmpty) out.add('--- Slide ${i + 1} ---\n$text');
    }
    return out.join('\n\n');
  }

  /// PDF text extraction, pure Dart. Page order preserved; pages are
  /// separated by blank lines. Throws a friendly message when the document
  /// is encrypted or contains no extractable text (scanned images).
  static String extractPdf(File file) {
    final bytes = file.readAsBytesSync();
    final doc = PdfDocument.open(bytes);
    final out = <String>[];
    for (var i = 0; i < doc.pageCount; i++) {
      final t = PdfTextExtractor.extract(doc, i).text.trim();
      if (t.isNotEmpty) out.add(t);
    }
    final result = out.join('\n\n').trim();
    if (result.isEmpty) {
      throw const FormatException(
          'PDF 中没有可提取的文本（可能是扫描件/图片型 PDF，需要 OCR）');
    }
    return result;
  }

  /// Generic OOXML text dump: paragraph-level tags become line breaks,
  /// every remaining tag is stripped, entities decoded.
  static String _xmlToText(String xmlStr, {required List<String> paragraphTags}) {
    var s = xmlStr;
    for (final tag in paragraphTags) {
      s = s.replaceAll('</$tag>', '\n');
    }
    // <t> runs keep their text; drop every remaining tag.
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    final lines = s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty);
    return lines.join('\n').trim();
  }
}

String _localName(XmlElement element) => element.name.local;
