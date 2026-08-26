import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/services/ai_service.dart';
import 'package:taskflow/presentation/ai_prompts/ai_prompts_screen.dart';

/// Contracts for the AI Prompts page (v1.5.7): the prompt-engineering
/// system prompt keeps its structure, the code-block extractor feeds the
/// Copy button, and the screen guides the user when AI is not configured.
void main() {
  group('prompt engineer system prompt', () {
    const sys = AiService.promptEngineerSystemPrompt;

    test('carries the full playbook structure', () {
      expect(sys, contains('# 角色'));
      expect(sys, contains('# 工作流程'));
      expect(sys, contains('# 质量规则'));
      expect(sys, contains('# 输出格式'));
      // The five skeletons are all present.
      expect(sys, contains('软件/应用需求类'));
      expect(sys, contains('编程实现类'));
      expect(sys, contains('写作/文案类'));
      expect(sys, contains('分析/决策类'));
      expect(sys, contains('其他通用'));
      // The strict output contract sections.
      expect(sys, contains('### 📋 提示词'));
      expect(sys, contains('### ⚠ 假设（可修改）'));
      expect(sys, contains('### 💡 使用建议'));
    });

    test('extractPromptBody returns the first fenced code block', () {
      const out = '### 📋 提示词\n```markdown\nLINE1\nLINE2\n```\n'
          '### 💡 使用建议\n一句话。';
      expect(AiService.extractPromptBody(out), 'LINE1\nLINE2');
    });

    test('extractPromptBody falls back to the whole output without a block',
        () {
      expect(AiService.extractPromptBody('没有代码块的回答'), '没有代码块的回答');
    });
  });

  group('ai prompts screen', () {
    testWidgets('generate is disabled while the input is empty',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: AiPromptsScreen()),
      ));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Generate'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('points to Settings when AI is not configured',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: AiPromptsScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '写一个周报工具');
      await tester.pump();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('AI is not configured'),
        findsOneWidget,
      );
    });
  });
}
