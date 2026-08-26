import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/presentation/ai_parse/ai_parse_screen.dart';
import 'package:taskflow/providers/ai_parse_providers.dart';
import 'package:taskflow/providers/ai_provider.dart';

/// v1.6.1 contracts for the AI Parse session: the state lives in an
/// app-session notifier (ai_parse_providers.dart), so switching pages
/// mid-summarization neither cancels the AI call nor loses the produced
/// summary — and the summary is kept until a NEW run starts.
void main() {
  test('summarize runs inside the notifier and reports failures in state',
      () async {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    // 127.0.0.1:9 is never reachable; flutter_test also blocks real HTTP —
    // either way the call fails fast and lands in state.error instead of
    // throwing into a disposed widget.
    const config =
        AiConfig(baseUrl: 'http://127.0.0.1:9', apiKey: 'k', model: 'm');
    n.setSummaryForTest('旧总结');
    final future = n.summarize(
      content: '内容',
      instructions: '总结要点',
      email: false,
      config: config,
    );
    // While in flight the state is busy and the OLD summary is kept — it is
    // replaced only when a new result lands.
    expect(n.state.summarizing, isTrue);
    expect(n.state.summary, '旧总结');
    await future;
    expect(n.state.summarizing, isFalse);
    expect(n.state.error, isNotNull);
    // Failed run keeps the previous summary (never destroys content).
    expect(n.state.summary, '旧总结');
  });

  test('attachments / notes / results survive until explicitly changed', () {
    final n = AiParseSessionNotifier();
    addTearDown(n.dispose);
    n.setNotes('会议纪要');
    n.setInstructions('按要点总结');
    n.addAttachment(name: 'a.txt', content: 'raw');
    n.showError('oops');
    n.clearError();
    expect(n.state.notes, '会议纪要');
    expect(n.state.instructions, '按要点总结');
    expect(n.state.attachments, hasLength(1));
    expect(n.state.error, isNull);

    n.removeAttachment(0);
    expect(n.state.attachments, isEmpty);

    n.clearResults();
    expect(n.state.results, isEmpty);
  });

  testWidgets(
      'input and summary survive leaving and returning to the page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AiParseScreen())),
      ),
    );
    await tester.pumpAndSettle();
    // The notes editor is the second TextField (after the instructions box).
    await tester.enterText(find.byType(TextField).last, '会议记录草稿');
    await tester.pumpAndSettle();

    // Simulate a finished AI run landing while the page is up.
    container.read(aiParseSessionProvider.notifier).setSummaryForTest(
        '## 总结结果\n\n要点一、要点二。');
    await tester.pumpAndSettle();
    expect(find.text('总结结果'), findsOneWidget);
    expect(find.text('Copy Markdown'), findsOneWidget);
    expect(find.text('Save .md'), findsOneWidget);
    expect(find.text('Save .html'), findsOneWidget);

    // Navigate "away" — the shell disposes the screen; pump a placeholder.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: Text('other page'))),
      ),
    );
    await tester.pumpAndSettle();

    // Back to the page — input AND summary must be restored.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AiParseScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, '会议记录草稿');
    expect(find.text('总结结果'), findsOneWidget);
    expect(find.text('Copy Markdown'), findsOneWidget);
  });
}
