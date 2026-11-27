import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/services/audio_transcription_service.dart';
import 'package:taskflow/data/services/content_extractor.dart';

/// v1.15.0 ContentExtractor upgrades:
///  - xlsx sheet-by-sheet reconstruction (workbook.xml sheet order,
///    relationship targets, cell references, shared/inline strings),
///  - docx table → Markdown table conversion,
///  - audio extension routing helpers + transcript part joining.
///
/// The OOXML fixtures are built with the same `archive` package the
/// extractor uses — a minimal-but-honest zip container.
void main() {
  group('extractXlsx — sheet structure reconstruction', () {
    test('emits sheet names in tab order with aligned cell columns',
        () async {
      final file = await _writeTempXlsx();
      final text = await ContentExtractor.extract(file);

      // Sheet headers, in workbook.xml order (not filename order).
      expect(text, contains('## Sheet: 汇总'));
      expect(text, contains('## Sheet: 明细'));

      // Alignment: row with a gap (A1, C1) keeps column 2 empty.
      expect(text, contains('参数\t\t备注'));

      // Shared strings resolve per cell; numbers stay raw.
      expect(text, contains('温度上限\t85\t注意'));
      expect(text, contains('4.19\t0x1F\tPASS'));

      // Inline strings and booleans; cells without `t` emit the raw value.
      expect(text, contains('内联值'));
      expect(text, contains('TRUE'));
      expect(text, contains('注释'));

      // Empty rows between populated ones simply don't appear (row 3 gap).
      expect(text, isNot(contains('\t\n\t')));
    });

    test('still works when workbook.xml has no resolvable rels', () async {
      // Missing workbook.xml → friendly error (the old shared-strings dump
      // would have silently produced garbage).
      final file = await _writeTempXlsx(brokenWorkbook: true);
      final text = await ContentExtractor.extract(file);
      expect(text, contains('## Sheet: Sheet1'));
    });
  });

  group('extractDocx — table reconstruction', () {
    test('tables become Markdown tables, paragraphs stay lines', () async {
      final file = await _writeTempDocx();
      final text = await ContentExtractor.extract(file);

      expect(text, contains('结论先行段落'));
      expect(text, contains('| 参数 | 规格 | 实测 |'));
      expect(text, contains('| --- | --- | --- |'));
      expect(text, contains('| 电压 | 4.2 V | 4.19 V |'));
      // Multi-paragraph cells flatten to one line; pipes are escaped so the
      // Markdown table cannot be broken by cell content.
      expect(text, contains(r'备注 含竖线\|字符'));
      expect(text, contains('两段 合并一行'));
      expect(text, contains('结尾段落'));
    });
  });

  group('audio routing helpers', () {
    test('audio extension classification', () {
      for (final ext in ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac']) {
        expect(ContentExtractor.isAudioExtension(ext), isTrue, reason: ext);
      }
      for (final ext in ['opus', 'webm', 'amr']) {
        expect(ContentExtractor.isAudioExtension(ext), isTrue, reason: ext);
      }
      expect(ContentExtractor.isAudioExtension('docx'), isFalse);
      expect(ContentExtractor.isAudioExtension('MP3'), isTrue);
    });

    test('picker list = documents + audio (opus included for a clear error)',
        () {
      expect(ContentExtractor.pickerExtensions, contains('docx'));
      expect(ContentExtractor.pickerExtensions, contains('opus'));
      expect(ContentExtractor.pickerExtensions, contains('webm'));
    });

    test('extract() rejects audio with routing guidance', () async {
      final f = File(
          '${Directory.systemTemp.path}/not_audio_${DateTime.now().microsecondsSinceEpoch}.mp3');
      await f.writeAsString('bytes');
      addTearDown(() => f.delete());
      await expectLater(
        ContentExtractor.extract(f),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('音频文件应由转写流水线处理'),
        )),
      );
    });

    test('transcribable extension set matches the decoder contract', () {
      for (final ext in AudioTranscriptionService.supportedAudioExtensions) {
        expect(ContentExtractor.isAudioExtension(ext), isTrue, reason: ext);
      }
      expect(AudioTranscriptionService.isSupportedAudio('M4A'), isTrue);
      expect(AudioTranscriptionService.isSupportedAudio('opus'), isFalse);
    });
  });

  group('joinTranscriptParts (segment joining)', () {
    test('Chinese fragments glue directly, ASCII gets a space', () {
      expect(
        joinTranscriptParts(['今天开会讨论', '测试计划']),
        '今天开会讨论测试计划',
      );
      expect(
        joinTranscriptParts(['The firmware version is 2.4.1', 'and it fails']),
        'The firmware version is 2.4.1 and it fails',
      );
    });

    test('empty segments are dropped, punctuation keeps spacing rules', () {
      expect(joinTranscriptParts(['', '结果为 PASS', '', ''], ), '结果为 PASS');
      expect(joinTranscriptParts(['value is 42', '. Next']), 'value is 42. Next');
    });
  });
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

Future<File> _writeTempXlsx({bool brokenWorkbook = false}) async {
  final dir = await Directory.systemTemp.createTemp('taskflow_xlsx_');
  final path = '${dir.path}/fixture.xlsx';

  final sharedXml = '''<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>参数</t></si>
  <si><t>备注</t></si>
  <si><t>温度上限</t></si>
  <si><t>注意</t></si>
  <si><t>0x1F</t></si>
  <si><t>PASS</t></si>
  <si><t>内联值</t></si>
</sst>''';

  // Sheet1 = "汇总" (workbook lists it first even though the file is sheet2).
  final sheet2Xml = '''<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>
    <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>85</v></c><c r="C2" t="s"><v>3</v></c></row>
    <row r="4"><c r="A4"><v>4.19</v></c><c r="B4" t="s"><v>4</v></c><c r="C4" t="s"><v>5</v></c></row>
  </sheetData>
</worksheet>''';

  final sheet1Xml = '''<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>内联值</t></is></c><c r="B1" t="b"><v>1</v></c></row>
    <row r="2"><c r="A2"><v>注释</v></c></row>
  </sheetData>
</worksheet>''';

  final workbookXml = brokenWorkbook
      ? '''<?xml version="1.0"?><workbook><sheets/></workbook>'''
      : '''<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="汇总" sheetId="1" r:id="rId2"/>
    <sheet name="明细" sheetId="2" r:id="rId1"/>
  </sheets>
</workbook>''';

  final relsXml = '''<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
</Relationships>''';

  final encoder = ZipEncoder();
  final archive = Archive()
    ..addFile(_memFile('xl/sharedStrings.xml', utf8.encode(sharedXml)))
    ..addFile(_memFile('xl/worksheets/sheet1.xml', utf8.encode(sheet1Xml)))
    ..addFile(_memFile('xl/worksheets/sheet2.xml', utf8.encode(sheet2Xml)))
    ..addFile(_memFile('xl/workbook.xml', utf8.encode(workbookXml)))
    ..addFile(_memFile('xl/_rels/workbook.xml.rels', utf8.encode(relsXml)));
  File(path).writeAsBytesSync(encoder.encode(archive)!);
  addTearDown(() => dir.delete(recursive: true));
  return File(path);
}

ArchiveFile _memFile(String name, List<int> bytes) {
  final f = ArchiveFile(name, bytes.length, bytes);
  return f;
}

Future<File> _writeTempDocx() async {
  final dir = await Directory.systemTemp.createTemp('taskflow_docx_');
  final path = '${dir.path}/fixture.docx';
  final documentXml = '''<?xml version="1.0"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>结论先行段落</w:t></w:r></w:p>
    <w:tbl>
      <w:tr>
        <w:tc><w:p><w:r><w:t>参数</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>规格</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>实测</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>电压</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>4.2 V</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>4.19 V</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>备注</w:t></w:r></w:p><w:p><w:r><w:t>含竖线|字符</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>两段</w:t></w:r></w:p><w:p><w:r><w:t>合并一行</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>OK</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
    <w:p><w:r><w:t>结尾段落</w:t></w:r></w:p>
  </w:body>
</w:document>''';

  final encoder = ZipEncoder();
  final archive = Archive()
    ..addFile(_memFile('word/document.xml', utf8.encode(documentXml)));
  File(path).writeAsBytesSync(encoder.encode(archive)!);
  addTearDown(() => dir.delete(recursive: true));
  return File(path);
}
