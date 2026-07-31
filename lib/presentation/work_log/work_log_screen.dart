import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/markdown/html_export.dart';
import '../../data/models/work_log.dart';
import '../../providers/work_log_provider.dart';
import '../shared/markdown_editor_field.dart';
import '../shared/markdown_input.dart';
import '../shared/selectable_markdown_body.dart';

/// Work Log page — ported from the LinguaFlow Chrome extension's
/// workreport.html. Free-form work records → AI-generated structured
/// summary, with date/time filtering, multi-select, draft auto-save and
/// Markdown / HTML export.
class WorkLogScreen extends ConsumerStatefulWidget {
  const WorkLogScreen({super.key});

  @override
  ConsumerState<WorkLogScreen> createState() => _WorkLogScreenState();
}

class _WorkLogScreenState extends ConsumerState<WorkLogScreen> {
  final _inputController = TextEditingController();
  late final FocusNode _inputFocus;

  // Filters (null = unconstrained). Date filters compare the calendar day;
  // time filters compare the time-of-day, mirroring the extension.
  DateTime? _dateFrom;
  DateTime? _dateTo;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;

  final Set<String> _selectedIds = {};
  String? _editingId;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode(onKeyEvent: _onInputKey);
    // Restore draft once records have loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onInputKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          MarkdownInput.outdent(_inputController);
        } else {
          MarkdownInput.indent(_inputController);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        _saveRecord();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ── Draft auto-save ──────────────────────────────────────────────────

  Future<void> _restoreDraft() async {
    final draft = await ref.read(workLogRepositoryProvider).loadDraft();
    if (draft.isNotEmpty && _inputController.text.isEmpty) {
      _inputController.text = draft;
    }
  }

  void _onInputChanged() {
    // Debounced draft persistence.
    ref.read(workLogProvider.notifier).saveDraft(_inputController.text);
  }

  // ── Records ──────────────────────────────────────────────────────────

  void _saveRecord() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _toast('Please enter some work content');
      return;
    }
    final notifier = ref.read(workLogProvider.notifier);
    if (_editingId != null) {
      notifier.updateRecord(_editingId!, text);
      _toast('Record updated');
    } else {
      notifier.addRecord(text);
      _toast('Record saved');
    }
    _inputController.clear();
    setState(() => _editingId = null);
  }

  void _editRecord(WorkLogRecord r) {
    setState(() {
      _editingId = r.id;
      _inputController.text = r.content;
    });
    _inputFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _editingId = null);
    _inputController.clear();
  }

  Future<void> _deleteRecord(WorkLogRecord r) async {
    await ref.read(workLogProvider.notifier).deleteRecord(r.id);
    setState(() => _selectedIds.remove(r.id));
  }

  Future<void> _clearAllRecords() async {
    final ok = await _confirm('Clear all work records? This cannot be undone.');
    if (ok) {
      await ref.read(workLogProvider.notifier).clearRecords();
      setState(() => _selectedIds.clear());
    }
  }

  // ── Filtering ────────────────────────────────────────────────────────

  List<WorkLogRecord> _filteredRecords(List<WorkLogRecord> all) {
    return all.where((r) {
      final dt = r.dateTime;
      if (_dateFrom != null) {
        final from =
            DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
        if (dt.isBefore(from)) return false;
      }
      if (_dateTo != null) {
        final to =
            DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
        if (dt.isAfter(to)) return false;
      }
      if (_timeFrom != null) {
        final minutes = dt.hour * 60 + dt.minute;
        if (minutes < _timeFrom!.hour * 60 + _timeFrom!.minute) return false;
      }
      if (_timeTo != null) {
        final minutes = dt.hour * 60 + dt.minute;
        if (minutes > _timeTo!.hour * 60 + _timeTo!.minute) return false;
      }
      return true;
    }).toList();
  }

  bool get _hasFilter =>
      _dateFrom != null ||
      _dateTo != null ||
      _timeFrom != null ||
      _timeTo != null;

  void _clearFilter() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _timeFrom = null;
      _timeTo = null;
    });
  }

  // ── Selection ────────────────────────────────────────────────────────

  void _toggleSelect(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _toggleSelectAll(List<WorkLogRecord> filtered) {
    setState(() {
      final allSelected = filtered.isNotEmpty &&
          filtered.every((r) => _selectedIds.contains(r.id));
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(filtered.map((r) => r.id));
      }
    });
  }

  // ── Summary ──────────────────────────────────────────────────────────

  Future<void> _generate(List<WorkLogRecord> filtered) async {
    final source = _selectedIds.isEmpty
        ? filtered
        : filtered.where((r) => _selectedIds.contains(r.id)).toList();
    await ref.read(workLogProvider.notifier).generateSummary(source);
  }

  Future<void> _copySummary(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Summary copied to clipboard');
  }

  Future<void> _download(String text, {required bool markdown}) async {
    if (text.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final ext = markdown ? 'md' : 'html';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save summary',
        fileName: 'work-summary-$stamp.$ext',
      );
      if (path != null) {
        final content = markdown ? text : _wrapHtml(_markdownToHtml(text));
        await File(path).writeAsString(content);
        _toast('${ext.toUpperCase()} saved');
      }
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workLogProvider);
    final notifier = ref.read(workLogProvider.notifier);
    final theme = Theme.of(context);
    final filtered = _filteredRecords(state.records);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — same gradient / accent-bar style as the other screens.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withOpacity(0.06),
                theme.colorScheme.surface,
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Work Log', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Record daily work · AI-generated key-point summary',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Two-column body: capture (input + records) on the left, AI output
        // (summary + history) on the right. The bottom card of each column
        // fills the remaining height and scrolls its list internally, so no
        // bare page background is left below short content.
        //
        // v1.4.28: each column is its own selection scope. The disabled
        // barrier hides both columns from the app-wide SelectionArea, and
        // each column's own SelectionArea restores drag selection inside
        // it. Without the barrier, one drag across the AI summary could
        // extend the document-order selection range into the left column
        // and highlight the New record / Work records text too.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
            child: SelectionContainer.disabled(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildInputCard(theme),
                          const SizedBox(height: 14),
                          Expanded(
                              child:
                                  _buildRecordsCard(state, filtered, theme)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSummaryCard(state, notifier, filtered, theme),
                          const SizedBox(height: 14),
                          Expanded(child: _buildHistoryCard(state, theme)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Language selector (lives inside the summary card) ────────────────

  Widget _buildLanguageRow(
      WorkLogState state, WorkLogNotifier notifier, ThemeData theme) {
    final langs = kWorkLogLanguages.entries.toList();
    List<DropdownMenuItem<String>> items() => [
          for (final e in langs)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value,
                  style: const TextStyle(fontSize: 12.5),
                  overflow: TextOverflow.ellipsis),
            ),
        ];

    // Compact dropdown box (v1.4.22: labels bigger, boxes smaller).
    InputDecoration dropdownDecoration() => const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          border: OutlineInputBorder(),
        );

    TextStyle labelStyle() => theme.textTheme.labelMedium!.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        );

    TextStyle valueStyle() => theme.textTheme.bodyMedium!.copyWith(
          fontSize: 12.5,
          color: theme.colorScheme.onSurface,
        );

    return Row(
      children: [
        Icon(Icons.translate,
            size: 15, color: theme.colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 6),
        Text('Input', style: labelStyle()),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: state.inputLang,
            isDense: true,
            isExpanded: true,
            style: valueStyle(),
            decoration: dropdownDecoration(),
            items: items(),
            onChanged: (v) {
              if (v != null) {
                notifier.setLangs(inputLang: v, outputLang: state.outputLang);
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Text('Output', style: labelStyle()),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: state.outputLang,
            isDense: true,
            isExpanded: true,
            style: valueStyle(),
            decoration: dropdownDecoration(),
            items: items(),
            onChanged: (v) {
              if (v != null) {
                notifier.setLangs(inputLang: state.inputLang, outputLang: v);
              }
            },
          ),
        ),
      ],
    );
  }

  // ── Input card ───────────────────────────────────────────────────────

  Widget _buildInputCard(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note,
                    size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('New record',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (_editingId != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Editing existing record',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 20),
            MarkdownToolbar(
              controller: _inputController,
              refocus: _inputFocus,
            ),
            const SizedBox(height: 8),
            MarkdownEditorField(
              controller: _inputController,
              focusNode: _inputFocus,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
              hintText:
                  '''Enter today's work...

e.g.
- Finished the login module front-end
- Fixed the order-list pagination bug
- Joined the requirements review meeting''',
              hardenLineBreaks: true,
              // Preview with the SAME style sheet used to render the saved
              // records below, so the preview is a true WYSIWYG of what gets
              // stored.
              styleSheet: _recordMarkdownStyleSheet(theme),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Ctrl+Enter to save · draft auto-saved',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withOpacity(0.45)),
                ),
                const Spacer(),
                if (_editingId != null) ...[
                  OutlinedButton.icon(
                    onPressed: _cancelEdit,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close, size: 14),
                    label:
                        const Text('Cancel', style: TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  onPressed: _saveRecord,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 11),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(_editingId != null ? Icons.edit : Icons.save,
                      size: 16),
                  label: Text(
                    _editingId != null ? 'Update' : 'Save record',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Records card ─────────────────────────────────────────────────────

  Widget _buildRecordsCard(
      WorkLogState state, List<WorkLogRecord> filtered, ThemeData theme) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('HH:mm');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row (Spacer is only legal in a Flex, so the action
            // buttons live here, not inside the chip Wrap below).
            Row(
              children: [
                Icon(Icons.list_alt,
                    size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Work records',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('${state.records.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary)),
                ),
                if (_hasFilter) ...[
                  const SizedBox(width: 7),
                  Text('filtered: ${filtered.length}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ],
                if (_selectedIds.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text('(${_selectedIds.length} selected)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary)),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _toggleSelectAll(filtered),
                  icon: const Icon(Icons.checklist, size: 14),
                  label: const Text('Select all',
                      style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: state.records.isEmpty ? null : _clearAllRecords,
                  icon: const Icon(Icons.delete_sweep, size: 14),
                  label:
                      const Text('Clear all', style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Filter chips row.
            Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filterChip(
                  label: _dateFrom == null
                      ? 'From date'
                      : dateFmt.format(_dateFrom!),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _dateFrom = picked);
                  },
                ),
                _filterChip(
                  label: _dateTo == null ? 'To date' : dateFmt.format(_dateTo!),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateTo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _dateTo = picked);
                  },
                ),
                _filterChip(
                  label: _timeFrom == null
                      ? 'From time'
                      : _timeFrom!.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                        context: context,
                        initialTime: _timeFrom ?? TimeOfDay.now());
                    if (picked != null) setState(() => _timeFrom = picked);
                  },
                ),
                _filterChip(
                  label: _timeTo == null ? 'To time' : _timeTo!.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                        context: context,
                        initialTime: _timeTo ?? TimeOfDay.now());
                    if (picked != null) setState(() => _timeTo = picked);
                  },
                ),
                if (_hasFilter)
                  TextButton(
                    onPressed: _clearFilter,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear filter',
                        style: TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
            const Divider(height: 20),
            // Body: fills the remaining card height, scrolls internally.
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyRecords(theme)
                  : ListView(
                      primary: false,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final r in filtered)
                          _recordRow(r, dateFmt, timeFmt, theme),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Centered empty state for the records list — drawn inside the filled
  /// card so a short list never leaves bare page background below.
  Widget _buildEmptyRecords(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 38, color: theme.colorScheme.onSurface.withOpacity(0.22)),
          const SizedBox(height: 10),
          Text(
            _hasFilter
                ? 'No records match the current filter.'
                : 'No work records yet',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.55)),
          ),
          if (!_hasFilter) ...[
            const SizedBox(height: 4),
            Text(
              'Enter content above and click "Save record" (Ctrl+Enter).',
              style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurface.withOpacity(0.38)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required VoidCallback onTap}) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      onPressed: onTap,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// Shared Markdown styling for work records. Used by BOTH the input
  /// Preview and the saved record rows so the preview is a true WYSIWYG of
  /// what gets stored ("input-as-preview").
  MarkdownStyleSheet _recordMarkdownStyleSheet(ThemeData theme) {
    return MarkdownStyleSheet(
      p: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: theme.colorScheme.onSurface.withOpacity(0.85)),
      listIndent: 16,
    );
  }

  Widget _recordRow(WorkLogRecord r, DateFormat dateFmt, DateFormat timeFmt,
      ThemeData theme) {
    final selected = _selectedIds.contains(r.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withOpacity(0.06)
            : theme.colorScheme.surface,
        border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.4)
                : theme.colorScheme.outline.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelect(r.id),
            ),
          ),
          const SizedBox(width: 8),
          // Date + time are merged into a SINGLE Text.rich (v1.4.28): as two
          // separate Text selectables, a drag that starts at the content's
          // top-left landed "above" the time Text, whose adjustDragOffset()
          // snapped the start edge back to offset 0 (SelectionResult.previous)
          // and the app-wide _initSelection stopped before ever reaching the
          // content — so records could not be selected left-to-right. One
          // selectable spanning both lines removes that geometric dead-zone.
          SizedBox(
            width: 74,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${dateFmt.format(r.dateTime)}\n',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: timeFmt.format(r.dateTime),
                    style: TextStyle(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            // SelectableMarkdownBody (single selectable document) so the
            // record can be drag-selected and right-click → "Copy as
            // Markdown" to grab the original Markdown source — same pattern
            // as the Execution Log Notes.
            child: SelectableMarkdownBody(
              data: r.content,
              hardenLineBreaks: true,
              styleSheet: _recordMarkdownStyleSheet(theme),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 15),
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editRecord(r),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 15),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            onPressed: () => _deleteRecord(r),
          ),
        ],
      ),
    );
  }

  // ── Summary card ─────────────────────────────────────────────────────

  Widget _buildSummaryCard(WorkLogState state, WorkLogNotifier notifier,
      List<WorkLogRecord> filtered, ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('AI Key-Point Summary',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      state.generating ? null : () => _generate(filtered),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: state.generating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome, size: 15),
                  label: Text(
                    state.generating ? 'Generating...' : 'Generate',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildLanguageRow(state, notifier, theme),
            if (state.error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(state.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 96, maxHeight: 280),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: state.result.isEmpty
                  ? Text(
                      'Pick a date range (or select records) and click "Generate" — the AI will distill your key points.',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface.withOpacity(0.45)),
                    )
                  : SingleChildScrollView(
                      primary: false,
                      // Selectable + right-click "Copy as Markdown" for the
                      // AI summary output.
                      child: SelectableMarkdownBody(
                        data: state.result,
                        hardenLineBreaks: true,
                      ),
                    ),
            ),
            if (state.result.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copySummary(state.result),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy', style: TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _exporting
                        ? null
                        : () => _download(state.result, markdown: true),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('MD', style: TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _exporting
                        ? null
                        : () => _download(state.result, markdown: false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('HTML', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── History card ─────────────────────────────────────────────────────

  Widget _buildHistoryCard(WorkLogState state, ThemeData theme) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('HH:mm');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Summary history',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('${state.summaries.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed:
                      state.summaries.isEmpty ? null : _clearAllSummaries,
                  icon: const Icon(Icons.delete_sweep, size: 14),
                  label:
                      const Text('Clear all', style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // Body: fills the remaining card height, scrolls internally.
            Expanded(
              child: state.summaries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_outlined,
                              size: 34,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.22)),
                          const SizedBox(height: 10),
                          Text(
                            'No history yet',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Generated summaries are saved automatically.',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.38)),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      primary: false,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final s in state.summaries)
                          InkWell(
                            onTap: () => ref
                                .read(workLogProvider.notifier)
                                .loadSummary(s),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 70,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(dateFmt.format(s.dateTime),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    theme.colorScheme.primary,
                                                fontWeight: FontWeight.w600)),
                                        Text(timeFmt.format(s.dateTime),
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withOpacity(0.5))),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${s.dateRange} · ${kWorkLogLanguages[s.outputLang] ?? s.outputLang}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.7)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          s.content.length > 100
                                              ? '${s.content.substring(0, 100)}...'
                                              : s.content,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              height: 1.4,
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.55)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 15),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => ref
                                        .read(workLogProvider.notifier)
                                        .deleteSummary(s.id),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearAllSummaries() async {
    final ok =
        await _confirm('Clear all summary history? This cannot be undone.');
    if (ok) await ref.read(workLogProvider.notifier).clearSummaries();
  }

  // ── Markdown → HTML export (logic lives in core/markdown/html_export.dart
  //    so it is unit-testable; see test/html_export_test.dart) ────────────

  String _wrapHtml(String body) => wrapHtmlExportPage(body);

  String _markdownToHtml(String src) => markdownToHtmlExport(src);
}
