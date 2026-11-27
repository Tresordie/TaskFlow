import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/providers/ai_parse_providers.dart';

/// v1.15.0 attachment pipeline contracts: per-file status transitions land
/// in the session state (extracting/ready/failed), failed attachments never
/// abort the page, and unsupported audio formats fail fast with a
/// conversion hint — all without any AI configuration.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('taskflow_attach_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('document attachment flows to ready with extracted content',
      () async {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    final file = File('${tmp.path}/notes.txt');
    await file.writeAsString('第一行\n第二行\n');

    await n.addAttachmentFile(file.path);

    expect(n.state.attachments, hasLength(1));
    final a = n.state.attachments.single;
    expect(a.status, AiParseAttachmentStatus.ready);
    expect(a.kind, AiParseAttachmentKind.doc);
    expect(a.ext, 'txt');
    expect(a.content, '第一行\n第二行');
    expect(a.error, isNull);
    expect(n.state.attachmentsReady, isTrue);
  });

  test('unsupported audio fails fast with a conversion hint', () async {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    final file = File('${tmp.path}/voice.opus');
    await file.writeAsBytes([1, 2, 3]);

    await n.addAttachmentFile(file.path);

    final a = n.state.attachments.single;
    expect(a.status, AiParseAttachmentStatus.failed);
    expect(a.kind, AiParseAttachmentKind.audio);
    expect(a.error, contains('opus/webm/amr'));
    expect(a.error, contains('mp3/wav/m4a'));
    // A failed attachment blocks the analyze button but never throws out.
    expect(n.state.attachmentsReady, isFalse);
    expect(n.state.error, isNull);
  });

  test('document extraction failure marks the attachment failed', () async {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    final file = File('${tmp.path}/broken.docx');
    await file.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]); // not a zip

    await n.addAttachmentFile(file.path);

    final a = n.state.attachments.single;
    expect(a.status, AiParseAttachmentStatus.failed);
    expect(a.error, isNotNull);
  });

  test('removeAttachment works by index across statuses', () async {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    final ok = File('${tmp.path}/a.md');
    await ok.writeAsString('# 笔记\n');
    final bad = File('${tmp.path}/b.opus');
    await bad.writeAsBytes([1]);

    await n.addAttachmentFile(ok.path);
    await n.addAttachmentFile(bad.path);
    expect(n.state.attachments, hasLength(2));

    n.removeAttachment(1);
    expect(n.state.attachments, hasLength(1));
    expect(n.state.attachments.single.name, 'a.md');
    expect(n.state.attachmentsReady, isTrue);
  });

  test('template and output-language selections persist in session state',
      () {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    expect(n.state.selectedTemplateId, 'free');
    expect(n.state.outputLanguage, '');

    n.setTemplate('M1');
    n.setOutputLanguage('English（英语）');
    expect(n.state.selectedTemplateId, 'M1');
    expect(n.state.outputLanguage, 'English（英语）');

    n.setTemplate('free');
    n.setOutputLanguage('');
    expect(n.state.selectedTemplateId, 'free');
    expect(n.state.outputLanguage, '');
  });

  test('direct addAttachment (text in hand) lands as a ready doc record',
      () {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    n.addAttachment(name: 'paste.txt', content: 'raw');
    final a = n.state.attachments.single;
    expect(a.status, AiParseAttachmentStatus.ready);
    expect(a.content, 'raw');
    expect(n.state.attachmentsReady, isTrue);
  });

  test(
      'regression: extraction works when the notifier lives in a container '
      'that also holds a Timer-bearing StateNotifier', () async {
    // Mirrors the real app: the session notifier is created BY a
    // StateNotifierProvider (so Riverpod listeners are attached to it and
    // its graph reaches the whole ProviderContainer) and the container
    // holds a Timer-bearing notifier like SyncNotifier. The v1.15.0 bug:
    // the Isolate.run closure defined inside the notifier's async method
    // captured that whole graph → SendPort.send rejected it with
    // "object is unsendable" and every document attachment failed.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(timerProvider, (_, __) {});
    container.listen(aiParseSessionProvider, (_, __) {});
    final notifier = container.read(aiParseSessionProvider.notifier);

    final file = File('${tmp.path}/container_doc.txt');
    await file.writeAsString('容器内提取\n');
    await notifier.addAttachmentFile(file.path);

    final a = notifier.state.attachments.single;
    expect(a.status, AiParseAttachmentStatus.ready,
        reason: a.error ?? 'should be ready');
    expect(a.content, '容器内提取');
  });
}

/// Timer-bearing notifier standing in for SyncNotifier (which carries
/// auto-sync Timers) in the regression test above.
class _TimerNotifier extends StateNotifier<int> {
  Timer? _timer;

  _TimerNotifier() : super(0) {
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => state++);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider<_TimerNotifier, int>((ref) => _TimerNotifier());
