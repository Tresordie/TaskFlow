import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:xml/xml.dart';

/// Text extraction for the AI Parse page's file input (v1.6.0).
///
/// Supported: plain text (txt/md/markdown/csv/log/json/eml — .eml emails
/// are plain RFC-822 text), HTML (tags stripped), and the OOXML office
/// formats docx / xlsx / pptx, which are ZIP+XML containers unpacked with
/// the pure-Dart `archive` package. PDF text extraction is pure Dart via
/// `pdf_document` — no native DLLs ship with the app.
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

  /// Extracts the text content of [file]. Throws [FormatException] with a
  /// user-facing message for unsupported extensions or oversized files.
  static Future<String> extract(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      throw FormatException(
          '不支持的文件类型：.$ext（支持 ${supportedExtensions.join(', ')}）');
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

  /// .docx → word/document.xml; paragraph ends become line breaks.
  static String extractDocx(File file) {
    final archive = _openZip(file);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) {
      throw const FormatException('无效的 Word 文档（缺少 document.xml）');
    }
    final xmlStr = utf8.decode(entry.content as List<int>);
    return _xmlToText(xmlStr, paragraphTags: ['w:p']);
  }

  /// .xlsx → xl/sharedStrings.xml (all shared string values). Cell-level
  /// table structure is not reconstructed in v1 — the AI receives every
  /// text value in sheet order.
  static String extractXlsx(File file) {
    final archive = _openZip(file);
    final entry = archive.findFile('xl/sharedStrings.xml');
    if (entry == null) return '';
    final xmlStr = utf8.decode(entry.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);
    return doc
        .findAllElements('t', namespace: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .join('\n');
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
