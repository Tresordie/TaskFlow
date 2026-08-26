import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../data/services/ai_service.dart';
import '../../providers/ai_provider.dart';
import '../../providers/typography_provider.dart';
import '../../core/theme/font_stack.dart';
import '../shared/app_markdown_body.dart';
import '../shared/markdown_editor_field.dart';

/// AI Prompts (v1.5.7) — paste a rough requirement, get an expert-grade,
/// copy-ready prompt rewritten by the configured LLM following the
/// prompt-engineering playbook in [AiService.promptEngineerSystemPrompt].
///
/// Flow: input → Generate → the model either returns the finished prompt
/// (📋 提示词 / ⚠ 假设 / 💡 使用建议 sections) or up to 3 clarifying
/// questions when key info is missing. The full output renders as Markdown;
/// "Copy prompt" grabs the first fenced code block (the prompt body proper).
/// Nothing is persisted — the page is a scratchpad by design.
///
/// v1.5.8 polish: the input is a full MarkdownEditorField (Write/Preview,
/// markdown toolbar parity with every other input area), resizable via the
/// drag grip below it, and both the input text and the rendered output
/// follow the font family / size configured in Settings (input typography
/// for the field, content typography for the output card).
class AiPromptsScreen extends ConsumerStatefulWidget {
  const AiPromptsScreen({super.key});

  @override
  ConsumerState<AiPromptsScreen> createState() => _AiPromptsScreenState();
}

class _AiPromptsScreenState extends ConsumerState<AiPromptsScreen> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollController = ScrollController();

  bool _generating = false;
  String? _error;
  String _result = '';

  // Resizable input area height (logical pixels) — drag the grip handle
  // below the field, mirroring the Work Log / AI Parse input behavior.
  double _inputHeight = 180;
  static const double _minInputHeight = 120;
  static const double _maxInputHeight = 420;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final input = _inputController.text.trim();
    if (input.isEmpty || _generating) return;

    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      setState(() => _error =
          'AI is not configured yet. Open Settings → AI Assistant to set your API endpoint first.');
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
      _result = '';
    });

    try {
      final service = AiService(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      );
      final result = await service.generatePrompt(input);
      setState(() {
        _result = result;
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _generating = false;
        _error = e.toString();
      });
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what copied to clipboard')),
    );
  }

  /// Preview / output style sheet — the SAME content typography for both,
  /// so what you see while composing matches the generated-prompt card.
  /// The fenced code block (the prompt body proper) gets a quiet tinted
  /// panel so the copy target reads as the artifact it is.
  MarkdownStyleSheet _previewSheet(ThemeData theme) {
    final sheet = MarkdownStyleSheet(
      p: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: theme.colorScheme.onSurface.withOpacity(0.88)),
      listIndent: 26,
      code: TextStyle(
        fontSize: 12.5,
        height: 1.5,
        fontFamily: 'Consolas',
        fontFamilyFallback: const ['Courier New', ...FontStack.fallback],
        color: theme.colorScheme.onSurface.withOpacity(0.92),
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.045),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );
    return applyContentTypography(context, sheet);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The input field follows Settings → Fonts (input area): family + size.
    final inputStyle = applyInputTypography(
      context,
      const TextStyle(fontSize: 13.5, height: 1.55),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_fix_high,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'AI Prompts',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Describe what you need — get an expert-grade prompt to copy into any AI.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

            // ── Input (markdown editor, resizable) ──────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: MarkdownEditorField(
                controller: _inputController,
                focusNode: _inputFocus,
                height: _inputHeight,
                minLines: 4,
                maxLines: 24,
                style: inputStyle,
                hintText:
                    'Describe what you need, in any form…\n\ne.g.\n- 写一个周报总结工具\n- 帮我分析这份销售数据\n- 写一篇产品发布文案（面向开发者社区）',
                hardenLineBreaks: true,
                styleSheet: _previewSheet(theme),
              ),
            ),

            // Resize grip handle at the bottom edge of the textarea —
            // drag up/down to resize, matching Work Log / AI Parse.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _inputHeight = (_inputHeight + details.delta.dy)
                      .clamp(_minInputHeight, _maxInputHeight);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: SizedBox(
                  height: 12,
                  width: double.infinity,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Actions ─────────────────────────────────────────────
            // AnimatedBuilder on the controller: the Generate button's
            // enabled state must react to typing (a plain TextField change
            // never rebuilds this widget on its own).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: AnimatedBuilder(
                animation: _inputController,
                builder: (context, _) {
                  final hasInput = _inputController.text.trim().isNotEmpty;
                  return Row(
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _generating || !hasInput ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_fix_high, size: 16),
                        label: Text(_generating ? 'Generating…' : 'Generate'),
                      ),
                      const Spacer(),
                      if (_result.isNotEmpty) ...[
                        TextButton.icon(
                          onPressed: () => _copy(
                              AiService.extractPromptBody(_result),
                              'Prompt'),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy prompt'),
                        ),
                        const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: () => _copy(_result, 'Output'),
                          icon: const Icon(Icons.copy_all, size: 16),
                          label: const Text('Copy all'),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),

            const SizedBox(height: 8),

            // ── Result ──────────────────────────────────────────────
            Expanded(
              child: _result.isEmpty && !_generating
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_outlined,
                              size: 40,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.25)),
                          const SizedBox(height: 8),
                          Text(
                            'The generated prompt appears here',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.verified_outlined,
                                    size: 15,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _generating ? 'GENERATING' : 'RESULT',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _generating
                                ? Row(
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Rewriting your requirement into an expert prompt…',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  )
                                : AppMarkdownBody(
                                    data: _result,
                                    styleSheet: _previewSheet(theme),
                                  ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
