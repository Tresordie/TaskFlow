import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/markdown/html_export.dart';
import '../../core/markdown/html_sanitize.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/task.dart';
import '../../data/services/ai_service.dart';
import '../../data/services/content_extractor.dart';
import '../../data/services/summary_templates.dart';
import '../../data/services/summarize_pipeline.dart'
    show kOutputLanguages;
import '../../providers/ai_parse_providers.dart';
import '../../providers/ai_provider.dart';
import '../../providers/color_settings_provider.dart';
import '../../providers/typography_provider.dart';
import '../../providers/task_providers.dart';
import '../shared/app_markdown_body.dart';
import '../shared/markdown_input.dart';
import '../shared/selectable_markdown_body.dart';

/// Phase 2 — AI note parsing.
/// Paste raw notes / attach documents & audio → LLM turns them into
/// structured tasks, or follows your prompt + template to parse & summarize
/// (v1.15.0: multi-attachment list, local SenseVoice audio transcription,
/// 25 summary templates, 17 output languages, streaming output).
class AiParseScreen extends ConsumerStatefulWidget {
  const AiParseScreen({super.key});

  @override
  ConsumerState<AiParseScreen> createState() => _AiParseScreenState();
}

class _AiParseScreenState extends ConsumerState<AiParseScreen> {
  final _notesController = TextEditingController();
  final _scrollController = ScrollController();
  // v1.6.0: free-form parsing instructions + attached documents.
  final _instructionsController = TextEditingController();
  late final FocusNode _instructionsFocus =
      markdownIndentFocusNode(_instructionsController);
  late final FocusNode _notesFocus;

  bool _creating = false;
  bool _previewMode = false;

  // v1.15.0: template picker panel state.
  bool _templatePanelOpen = false;
  String _scenarioFilter = '';

  // Resizable notes input area height (logical pixels) — drag the grip
  // handle below the field, mirroring the Work Log input behavior.
  double _notesHeight = 200;
  static const double _minNotesHeight = 100;
  static const double _maxNotesHeight = 500;

  @override
  void initState() {
    super.initState();
    _notesFocus = markdownIndentFocusNode(_notesController);
    // v1.6.1: restore the session draft (input, summary and results all
    // survive page switches — see ai_parse_providers.dart) and keep it in
    // sync while the user types.
    final session = ref.read(aiParseSessionProvider);
    _notesController.text = session.notes;
    _instructionsController.text = session.instructions;
    _notesController.addListener(_persistNotes);
    _instructionsController.addListener(_persistInstructions);
  }

  void _persistNotes() {
    ref.read(aiParseSessionProvider.notifier).setNotes(_notesController.text);
  }

  void _persistInstructions() {
    ref
        .read(aiParseSessionProvider.notifier)
        .setInstructions(_instructionsController.text);
  }

  @override
  void dispose() {
    _notesController.removeListener(_persistNotes);
    _instructionsController.removeListener(_persistInstructions);
    _notesController.dispose();
    _instructionsController.dispose();
    _instructionsFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// v1.15.0: documents AND audio — each picked file enters the per-file
  /// pipeline (extract / transcribe) with live status in the list.
  Future<void> _attachFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ContentExtractor.pickerExtensions,
    );
    if (picked == null || picked.files.isEmpty) return;
    final notifier = ref.read(aiParseSessionProvider.notifier);
    notifier.clearError();
    for (final f in picked.files) {
      final path = f.path;
      if (path == null) continue;
      // Fire-and-forget per file — status/progress shows up in the list.
      unawaited(notifier.addAttachmentFile(path));
    }
  }

  bool _looksLikeEmail(String text) {
    final lower = text.toLowerCase();
    return lower.contains('from:') && lower.contains('subject:') ||
        text.contains('发件人') && text.contains('主题') ||
        lower.contains('on ') && lower.contains('wrote:');
  }

  Future<void> _parse() async {
    final notes = _notesController.text.trim();
    final instructions = _instructionsController.text.trim();
    final session = ref.read(aiParseSessionProvider);
    if (notes.isEmpty && session.attachments.isEmpty) return;

    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      ref.read(aiParseSessionProvider.notifier).showError(
          'AI is not configured yet. Open Settings → AI Assistant to set your API endpoint first.');
      return;
    }

    final notifier = ref.read(aiParseSessionProvider.notifier);

    // v1.6.0: instructions and/or attachments switch to the ANALYZE mode
    // (free-form markdown summary); the plain no-prompt flow keeps the
    // original structured task extraction.
    // v1.6.1: fire-and-forget — the work runs inside the session notifier
    // (ai_parse_providers.dart), so switching pages neither cancels the AI
    // call nor loses the result; the UI follows the provider state.
    // v1.15.0: only READY attachments join the material (the button is
    // gated on session.attachmentsReady, this is a belt-and-braces filter).
    if (instructions.isNotEmpty || session.attachments.isNotEmpty) {
      final buf = StringBuffer();
      for (final a in session.attachments) {
        if (a.status != AiParseAttachmentStatus.ready) continue;
        buf.writeln('【附件：${a.name}】');
        buf.writeln(a.content);
        buf.writeln();
      }
      if (notes.isNotEmpty) buf.writeln(notes);
      final content = buf.toString().trim();
      final email = session.attachments
              .any((a) => a.name.toLowerCase().endsWith('.eml')) ||
          _looksLikeEmail('$instructions\n$content');
      unawaited(notifier.summarize(
        content: content,
        instructions: instructions,
        email: email,
        config: config,
      ));
      return;
    }

    unawaited(notifier.parseTasks(notes: notes, config: config));
  }

  /// v1.6.1: saves the summary as a Markdown or standalone HTML file
  /// (same pipeline as the Work Log downloads). v1.15.0: the HTML path is
  /// mermaid-aware — diagrams render in the exported file.
  Future<void> _downloadSummary({required bool markdown}) async {
    final summary = ref.read(aiParseSessionProvider).summary;
    if (summary.isEmpty) return;
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ext = markdown ? 'md' : 'html';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle:
            markdown ? 'Save Markdown summary' : 'Save HTML summary',
        fileName: 'ai-summary-$stamp.$ext',
      );
      if (path == null) return;
      final content = markdown
          ? summary
          : await wrapAiParseHtml(summary);
      await File(path).writeAsString(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ext saved: $path', maxLines: 2,
              overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _createSelected() async {
    final session = ref.read(aiParseSessionProvider);
    final selected = session.results.where((t) => t.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _creating = true);
    try {
      final notifier = ref.read(taskListProvider.notifier);
      final count = await notifier.createTasks([
        for (final t in selected)
          TaskDraft(
            title: t.title,
            description: t.description.isEmpty ? null : t.description,
            priority: t.priority,
            tags: t.tags,
            subSteps: t.subSteps,
          ),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Created $count task${count == 1 ? '' : 's'} from notes'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _creating = false);
      ref.read(aiParseSessionProvider.notifier).clearResults();
      _notesController.clear();
      context.go('/today');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create tasks: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  int _selectedCountOf(List<ParsedTask> results) =>
      results.where((t) => t.selected).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(aiConfigProvider);
    // v1.6.1: session state (notes/instructions/attachments/summary/results)
    // lives in the app-level provider — the page renders whatever state the
    // session has, including a summary that finished while the user was on
    // another page.
    final session = ref.watch(aiParseSessionProvider);
    final activeTemplate = findSummaryTemplate(session.selectedTemplateId);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text('AI Parse',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700, fontSize: 18)),
              const Spacer(),
              if (!config.isConfigured)
                TextButton.icon(
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Configure AI'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '粘贴笔记、附加文档或录音 — AI 提取结构化任务，或按模板/提示词总结输出（支持 17 种语言）。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 12),

          // ── v1.6.0: parsing instructions + file attachments ──────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _instructionsController,
                  focusNode: _instructionsFocus,
                  minLines: 1,
                  maxLines: 3,
                  style: applyInputTypography(
                    context,
                    const TextStyle(fontSize: 12.5, height: 1.45),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText:
                        '解析提示词（可选）：如"总结成周报要点" / "提取所有测试数据" / "按邮件线程整理待办"…',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurface.withOpacity(0.35),
                    ),
                    prefixIcon: Icon(Icons.tune,
                        size: 16, color: theme.colorScheme.primary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Attach documents (txt/md/html/docx/xlsx/pptx/pdf/eml…)
              // and audio (mp3/wav/m4a/aac/ogg/flac → local SenseVoice).
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: OutlinedButton.icon(
                  onPressed: session.summarizing ? null : _attachFiles,
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: const Text('附件'),
                ),
              ),
            ],
          ),
          if (session.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AttachmentList(attachments: session.attachments),
          ],
          const SizedBox(height: 10),

          // ── v1.15.0: template + output language selectors ──────
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _templatePanelOpen = !_templatePanelOpen),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  minimumSize: const Size(0, 32),
                ),
                icon: Icon(
                  activeTemplate == null
                      ? Icons.auto_awesome_outlined
                      : Icons.dashboard_customize_outlined,
                  size: 15,
                ),
                label: Text(
                  activeTemplate?.name ?? '自由总结',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.translate,
                  size: 15,
                  color: theme.colorScheme.onSurface.withOpacity(0.45)),
              const SizedBox(width: 4),
              _LanguageDropdown(
                value: session.outputLanguage,
                onChanged: (v) => ref
                    .read(aiParseSessionProvider.notifier)
                    .setOutputLanguage(v),
              ),
              const Spacer(),
              Text(
                'Markdown 输出 · mermaid 图表可渲染',
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                ),
              ),
            ],
          ),
          if (_templatePanelOpen) ...[
            const SizedBox(height: 8),
            _TemplatePicker(
              filter: _scenarioFilter,
              selectedId: session.selectedTemplateId,
              onFilterChanged: (f) => setState(() => _scenarioFilter = f),
              onSelected: (id) {
                ref
                    .read(aiParseSessionProvider.notifier)
                    .setTemplate(id);
                setState(() => _templatePanelOpen = false);
              },
              onClose: () => setState(() => _templatePanelOpen = false),
            ),
          ],
          const SizedBox(height: 10),

          // Notes input with Write / Preview tabs
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tab bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
                  child: Row(
                    children: [
                      _InputTab(
                        label: 'Write',
                        icon: Icons.edit_note,
                        active: !_previewMode,
                        onTap: () => setState(() => _previewMode = false),
                      ),
                      const SizedBox(width: 4),
                      _InputTab(
                        label: 'Preview',
                        icon: Icons.visibility_outlined,
                        active: _previewMode,
                        onTap: () => setState(() => _previewMode = true),
                      ),
                      const Spacer(),
                      Text(
                        'Markdown supported',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                ),
                // Formatting toolbar (Write mode only)
                if (!_previewMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 10, 0),
                    child: MarkdownToolbar(
                      controller: _notesController,
                      refocus: _notesFocus,
                    ),
                  ),
                // Content area
                if (_previewMode)
                  Container(
                    height: _notesHeight,
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    child: _notesController.text.trim().isEmpty
                        ? Text(
                            'Nothing to preview yet…',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.35),
                            ),
                          )
                        : SingleChildScrollView(
                            primary: false,
                            // v1.4.79: whole-document SelectableText preview —
                            // multi-line drag-select, Select all, right-click
                            // Copy / Select all / Copy as Markdown.
                            child: SelectableMarkdownBody(
                              data: sanitizeHtmlInMarkdown(
                                  _notesController.text),
                              hardenLineBreaks: true,
                              styleSheet: applyContentTypography(
                                context,
                                MarkdownStyleSheet.fromTheme(theme).copyWith(
                                  p: const TextStyle(
                                      fontSize: 13, height: 1.5),
                                ),
                              ),
                            ),
                          ),
                  )
                else
                  SizedBox(
                    height: _notesHeight,
                    child: TextField(
                      controller: _notesController,
                      focusNode: _notesFocus,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: applyInputTypography(
                        context,
                        const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          fontFamily: 'Consolas',
                        ),
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Today\'s PVT line review: 1) Metro battery connector torque spec needs re-check (2.5 N·m), station 3 failed 2 units...\n\nMarkdown / plain text / mixed languages all fine.',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Consolas',
                          color: theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                // Resize grip handle — drag up/down to resize the notes
                // input area (same pattern as the Work Log input).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _notesHeight = (_notesHeight + details.delta.dy)
                          .clamp(_minNotesHeight, _maxNotesHeight);
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: SizedBox(
                      height: 10,
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
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action row
          Row(
            children: [
              FilledButton.icon(
                // v1.15.0: gated on attachment processing — every file must
                // be extracted/transcribed before the analyze run starts.
                onPressed: (session.summarizing ||
                        _creating ||
                        !session.attachmentsReady)
                    ? null
                    : _parse,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: session.summarizing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                Theme.of(context).colorScheme.onPrimary))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(session.summarizing
                    ? 'Parsing…'
                    : (session.instructions.trim().isNotEmpty ||
                            session.attachments.isNotEmpty)
                        ? 'Analyze with AI'
                        : 'Parse with AI'),
              ),
              // v1.15.0: cancel button while an analyze run is in flight.
              if (session.summarizing) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => ref
                      .read(aiParseSessionProvider.notifier)
                      .cancelSummarize(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('取消'),
                ),
              ],
              const SizedBox(width: 12),
              // v1.6.0: copy the analyze-mode summary (raw Markdown).
              // v1.6.1: plus one-click Markdown / HTML file downloads.
              if (session.summary.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: session.summary));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Markdown copied to clipboard'),
                          behavior: SnackBarBehavior.floating),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Markdown'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _downloadSummary(markdown: true),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Save .md'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _downloadSummary(markdown: false),
                  icon: const Icon(Icons.web, size: 16),
                  label: const Text('Save .html'),
                ),
                const SizedBox(width: 12),
              ],
              if (session.results.isNotEmpty) ...[
                TextButton(
                  onPressed: () => setState(() {
                    final all = _selectedCountOf(session.results) ==
                        session.results.length;
                    for (final t in session.results) {
                      t.selected = !all;
                    }
                  }),
                  child: Text(_selectedCountOf(session.results) ==
                          session.results.length
                      ? 'Deselect all'
                      : 'Select all'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      (_creating || _selectedCountOf(session.results) == 0)
                          ? null
                          : _createSelected,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  icon: _creating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_task, size: 16),
                  label: Text(_creating
                      ? 'Creating…'
                      : 'Create ${_selectedCountOf(session.results)} task${_selectedCountOf(session.results) == 1 ? '' : 's'}'),
                ),
              ],
            ],
          ),

          // v1.15.0: pipeline stage line (map-reduce progress / generation).
          if (session.summarizing && session.stageText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary.withOpacity(0.7)),
                ),
                const SizedBox(width: 8),
                Text(
                  session.stageText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurface.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ],

          // Error
          if (session.error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Results — v1.6.0: analyze-mode markdown summary first, then the
          // structured task cards from the classic extraction flow.
          // v1.15.0: the summary area updates LIVE while the run streams.
          if (session.summary.isNotEmpty) ...[
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.25),
                  ),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: AppMarkdownBody(
                    data: session.summary,
                    styleSheet: applyContentTypography(
                      context,
                      MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ] else if (session.results.isNotEmpty) ...[
            Text(
              'Extracted ${session.results.length} task${session.results.length == 1 ? '' : 's'} — review and uncheck what you don\'t need:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                itemCount: session.results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _ParsedTaskCard(task: session.results[i]),
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notes_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurface.withOpacity(0.15)),
                    const SizedBox(height: 12),
                    Text(
                      session.summarizing
                          ? 'Thinking…'
                          : 'Parsed tasks will appear here',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// v1.15.0: attachment list card — per-file status/progress rows.
// ---------------------------------------------------------------------------

class _AttachmentList extends ConsumerWidget {
  final List<AiParseAttachment> attachments;

  const _AttachmentList({required this.attachments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.22),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < attachments.length; i++)
            _AttachmentTile(
              attachment: attachments[i],
              removeEnabled: !ref.watch(aiParseSessionProvider).summarizing,
              onRemove: () => ref
                  .read(aiParseSessionProvider.notifier)
                  .removeAttachment(i),
            ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final AiParseAttachment attachment;
  final bool removeEnabled;
  final VoidCallback onRemove;

  const _AttachmentTile({
    required this.attachment,
    required this.removeEnabled,
    required this.onRemove,
  });

  IconData get _icon {
    switch (attachment.ext) {
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
      case 'oga':
      case 'flac':
      case 'm4b':
        return Icons.graphic_eq;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'docx':
        return Icons.article_outlined;
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'eml':
        return Icons.mail_outline;
      case 'html':
      case 'htm':
      case 'xml':
      case 'json':
        return Icons.code;
      default:
        return Icons.description_outlined;
    }
  }

  String get _sizeLabel {
    final bytes = attachment.sizeBytes;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String get _durationLabel {
    final s = attachment.durationSec;
    if (s == null || s <= 0) return '';
    final total = s.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = attachment;
    final isAudio = a.kind == AiParseAttachmentKind.audio;
    final iconColor = isAudio
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    Widget status;
    switch (a.status) {
      case AiParseAttachmentStatus.extracting:
        status = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: theme.colorScheme.primary.withOpacity(0.7)),
            ),
            const SizedBox(width: 6),
            Text('解析中…', style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.55))),
          ],
        );
      case AiParseAttachmentStatus.transcribing:
        final label = a.total > 0
            ? '本地识别中 ${a.done}/${a.total}'
            : '准备中（加载模型/解码音频）…';
        status = Expanded(
          child: Row(
            children: [
              Text(label, style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withOpacity(0.55))),
              const SizedBox(width: 8),
              if (a.total > 0)
                Expanded(
                  child: LinearProgressIndicator(
                    value: a.total > 0 ? a.done / a.total : null,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (a.durationSec != null && a.durationSec! > 0) ...[
                const SizedBox(width: 8),
                Text('时长 ${_durationLabel}',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.45))),
              ],
            ],
          ),
        );
      case AiParseAttachmentStatus.ready:
        final bits = <String>['✓ 已就绪'];
        if (isAudio && a.durationSec != null && a.durationSec! > 0) {
          bits.add('时长 ${_durationLabel}');
        }
        if (a.content.isNotEmpty) {
          bits.add('${a.content.length} 字');
        }
        status = Text(
          bits.join(' · '),
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withOpacity(0.45),
          ),
        );
      case AiParseAttachmentStatus.failed:
        status = Expanded(
          child: Text(
            a.error ?? '处理失败',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.error),
          ),
        );
    }

    return InkWell(
      onTap: a.status == AiParseAttachmentStatus.ready && a.content.isNotEmpty
          ? () => _showPreview(context)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Icon(_icon, size: 17, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_sizeLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(_sizeLabel,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.4))),
                      ],
                      if (isAudio) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '语音',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  status is Row || status is Expanded
                      ? Row(children: [status])
                      : status,
                ],
              ),
            ),
            if (a.status == AiParseAttachmentStatus.ready)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.visibility_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.3)),
              ),
            IconButton(
              onPressed: removeEnabled ? onRemove : null,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(Icons.close,
                  color: theme.colorScheme.onSurface.withOpacity(0.4)),
              tooltip: '移除',
            ),
          ],
        ),
      ),
    );
  }

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          attachment.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 640,
          height: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              attachment.content,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// v1.15.0: template picker + output language dropdown.
// ---------------------------------------------------------------------------

class _TemplatePicker extends StatefulWidget {
  final String filter;
  final String selectedId;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

  const _TemplatePicker({
    required this.filter,
    required this.selectedId,
    required this.onFilterChanged,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<_TemplatePicker> {
  final _listController = ScrollController();

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = summaryTemplates
        .where((t) => widget.filter.isEmpty || t.scenario == widget.filter)
        .toList();

    return Container(
      height: 300,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ScenarioChip(
                label: '全部',
                active: widget.filter.isEmpty,
                onTap: () => widget.onFilterChanged(''),
              ),
              for (final s in summaryScenarios)
                _ScenarioChip(
                  label: s.label,
                  active: widget.filter == s.id,
                  onTap: () => widget.onFilterChanged(s.id),
                ),
              const Spacer(),
              _ScenarioChip(
                label: '✨ 自由总结',
                active: widget.selectedId == 'free',
                onTap: () => widget.onSelected('free'),
              ),
              IconButton(
                onPressed: widget.onClose,
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(Icons.close,
                    color: theme.colorScheme.onSurface.withOpacity(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            // Visible scrollbar + tail padding — a mid-card cut at the panel
            // edge must always read as scrollable content, not clipping.
            child: Scrollbar(
              controller: _listController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _listController,
                padding: const EdgeInsets.only(bottom: 10),
                itemCount: templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) => _TemplateCard(
                  template: templates[i],
                  selected: templates[i].id == widget.selectedId,
                  onTap: () => widget.onSelected(templates[i].id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ScenarioChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary.withOpacity(0.5)
                  : theme.colorScheme.outline.withOpacity(0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final SummaryTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.08)
              : theme.colorScheme.onSurface.withOpacity(0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.55)
                : theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        template.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          template.type,
                          style: TextStyle(
                            fontSize: 9.5,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.55),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${template.modules.length} 个模块',
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LanguageDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Glass mode makes colorScheme.surface TRANSLUCENT — without an opaque
    // dropdownColor the menu lets page content bleed through and the items
    // become unreadable (same pitfall as the v1.13.0 date-picker fix; the
    // dialog theme carries the pinned opaque palette surface).
    final menuColor =
        theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.35),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          dropdownColor: menuColor,
          style: TextStyle(
            fontSize: 12.5,
            color: theme.colorScheme.onSurface,
          ),
          iconEnabledColor: theme.colorScheme.onSurface.withOpacity(0.45),
          iconDisabledColor: theme.colorScheme.onSurface.withOpacity(0.3),
          items: [
            for (final lang in kOutputLanguages)
              DropdownMenuItem<String>(
                value: lang.value,
                child: Text(
                  lang.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _ParsedTaskCard extends ConsumerWidget {
  final ParsedTask task;

  const _ParsedTaskCard({required this.task});

  Color _priorityColor(Priority p) {
    switch (p) {
      case Priority.p0Critical:
        return AppColors.p0Critical;
      case Priority.p1High:
        return AppColors.p1High;
      case Priority.p2Medium:
        return AppColors.p2Medium;
      case Priority.p3Low:
        return AppColors.p3Low;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = ref.watch(colorSettingsProvider);
    final pColor = _priorityColor(task.priority);

    return StatefulBuilder(
      builder: (context, setLocal) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: task.selected ? 1.0 : 0.45,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: task.selected
                    ? theme.colorScheme.primary.withOpacity(0.35)
                    : theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: task.selected,
                        onChanged: (v) {
                          task.selected = v ?? true;
                          setLocal(() {});
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            // v1.4.75: whole-description SelectableText —
                            // multi-line drag-select, Select all, right-click
                            // Copy / Copy as Markdown. HTML sanitized first.
                            SelectableMarkdownBody(
                              data: sanitizeHtmlInMarkdown(task.description),
                              styleSheet: applyContentTypography(
                                context,
                                MarkdownStyleSheet.fromTheme(theme).copyWith(
                                  p: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                    height: 1.45,
                                  ),
                                  pPadding: const EdgeInsets.only(bottom: 4),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Priority chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        task.priority.shortLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: pColor,
                        ),
                      ),
                    ),
                  ],
                ),

                // Tags
                if (task.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in task.tags)
                        Builder(builder: (context) {
                          final tagColor =
                              colors.tagColor(tag) ?? theme.colorScheme.primary;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: tagColor,
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ],

                // Sub-steps preview
                if (task.subSteps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.checklist,
                                size: 13,
                                color:
                                    theme.colorScheme.primary.withOpacity(0.7)),
                            const SizedBox(width: 6),
                            Text(
                              '${task.subSteps.length} sub-step${task.subSteps.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    theme.colorScheme.primary.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final s in task.subSteps)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('•  ',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.4),
                                    )),
                                Expanded(
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.65),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InputTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _InputTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.45)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
