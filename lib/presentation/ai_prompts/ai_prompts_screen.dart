import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../data/services/ai_service.dart';
import '../../providers/ai_provider.dart';
import '../shared/app_markdown_body.dart';

/// AI Prompts (v1.5.7) — paste a rough requirement, get an expert-grade,
/// copy-ready prompt rewritten by the configured LLM following the
/// prompt-engineering playbook in [AiService.promptEngineerSystemPrompt].
///
/// Flow: input → Generate → the model either returns the finished prompt
/// (📋 提示词 / ⚠ 假设 / 💡 使用建议 sections) or up to 3 clarifying
/// questions when key info is missing. The full output renders as Markdown;
/// "Copy prompt" grabs the first fenced code block (the prompt body proper).
/// Nothing is persisted — the page is a scratchpad by design.
class AiPromptsScreen extends ConsumerStatefulWidget {
  const AiPromptsScreen({super.key});

  @override
  ConsumerState<AiPromptsScreen> createState() => _AiPromptsScreenState();
}

class _AiPromptsScreenState extends ConsumerState<AiPromptsScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  bool _generating = false;
  String? _error;
  String _result = '';

  @override
  void dispose() {
    _inputController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

            // ── Input ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _inputController,
                minLines: 4,
                maxLines: 8,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText:
                      'e.g. 写一个周报总结工具 / 帮我分析这份销售数据 / 写一篇产品发布文案…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),

            // ── Actions ─────────────────────────────────────────────
            // AnimatedBuilder on the controller: the Generate button's
            // enabled state must react to typing (a plain TextField change
            // never rebuilds this widget on its own).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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
                      child: Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _generating
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
                              : AppMarkdownBody(data: _result),
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
