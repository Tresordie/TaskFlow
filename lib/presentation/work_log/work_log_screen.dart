import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/work_log.dart';
import '../../providers/work_log_provider.dart';
import '../shared/markdown_input.dart';

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
    final draft =
        await ref.read(workLogRepositoryProvider).loadDraft();
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
        final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
        if (dt.isBefore(from)) return false;
      }
      if (_dateTo != null) {
        final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
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
      _dateFrom != null || _dateTo != null || _timeFrom != null || _timeTo != null;

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
        final content =
            markdown ? text : _wrapHtml(_markdownToHtml(text));
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
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
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Work Log', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Record daily work · AI-generated key-point summary',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.55)),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
            children: [
              _buildLanguageBar(state, notifier, theme),
              const SizedBox(height: 14),
              _buildInputCard(theme),
              const SizedBox(height: 14),
              _buildRecordsCard(state, filtered, theme),
              const SizedBox(height: 14),
              _buildSummaryCard(state, filtered, theme),
              const SizedBox(height: 14),
              _buildHistoryCard(state, theme),
            ],
          ),
        ),
      ],
    );
  }

  // ── Language bar ─────────────────────────────────────────────────────

  Widget _buildLanguageBar(WorkLogState state, WorkLogNotifier notifier,
      ThemeData theme) {
    final langs = kWorkLogLanguages.entries.toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text('Input', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: state.inputLang,
                isDense: true,
                items: [
                  for (final e in langs)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.setLangs(
                        inputLang: v, outputLang: state.outputLang);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text('Summary output', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: state.outputLang,
                isDense: true,
                items: [
                  for (final e in langs)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.setLangs(
                        inputLang: state.inputLang, outputLang: v);
                  }
                },
              ),
            ),
          ],
        ),
      ),
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
            MarkdownToolbar(
              controller: _inputController,
              refocus: _inputFocus,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText:
                    'Enter today\'s work...\n\ne.g.\n- Finished the login module front-end\n- Fixed the order-list pagination bug\n- Joined the requirements review meeting',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Ctrl+Enter to save · draft auto-saved',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.45)),
                ),
                const Spacer(),
                if (_editingId != null) ...[
                  OutlinedButton.icon(
                    onPressed: _cancelEdit,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  onPressed: _saveRecord,
                  icon: Icon(_editingId != null ? Icons.edit : Icons.save,
                      size: 16),
                  label: Text(_editingId != null ? 'Update' : 'Save record'),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Work records',
                    style: theme.textTheme.titleMedium),
                Text('${state.records.length}',
                    style: theme.textTheme.bodySmall),
                if (_hasFilter)
                  Text('(filtered: ${filtered.length})',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(width: 12),
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
                  label:
                      _dateTo == null ? 'To date' : dateFmt.format(_dateTo!),
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
                  label: _timeTo == null
                      ? 'To time'
                      : _timeTo!.format(context),
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
                    child: const Text('Clear filter'),
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _toggleSelectAll(filtered),
                  icon: const Icon(Icons.checklist, size: 16),
                  label: const Text('Select all'),
                ),
                if (_selectedIds.isNotEmpty)
                  Text('(${_selectedIds.length} selected)',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: state.records.isEmpty ? null : _clearAllRecords,
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
            const Divider(height: 20),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    state.records.isEmpty
                        ? 'No records yet — enter content above and click "Save record".'
                        : 'No records match the current filter.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
              )
            else
              ...filtered.map((r) => _recordRow(r, dateFmt, timeFmt, theme)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({required String label, required VoidCallback onTap}) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _recordRow(WorkLogRecord r, DateFormat dateFmt, DateFormat timeFmt,
      ThemeData theme) {
    final selected = _selectedIds.contains(r.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          SizedBox(
            width: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateFmt.format(r.dateTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600)),
                Text(timeFmt.format(r.dateTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.content,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Edit',
            onPressed: () => _editRecord(r),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Delete',
            onPressed: () => _deleteRecord(r),
          ),
        ],
      ),
    );
  }

  // ── Summary card ─────────────────────────────────────────────────────

  Widget _buildSummaryCard(
      WorkLogState state, List<WorkLogRecord> filtered, ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('AI Key-Point Summary',
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: state.generating
                      ? null
                      : () => _generate(filtered),
                  icon: state.generating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(state.generating ? 'Generating...' : 'Generate'),
                ),
              ],
            ),
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
              constraints: const BoxConstraints(minHeight: 100),
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.45),
                          fontStyle: FontStyle.italic),
                    )
                  : MarkdownBody(
                      data: state.result,
                      selectable: true,
                    ),
            ),
            if (state.result.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copySummary(state.result),
                    icon: const Icon(Icons.copy, size: 15),
                    label: const Text('Copy'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _exporting
                        ? null
                        : () => _download(state.result, markdown: true),
                    icon: const Icon(Icons.download, size: 15),
                    label: const Text('MD'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _exporting
                        ? null
                        : () => _download(state.result, markdown: false),
                    icon: const Icon(Icons.download, size: 15),
                    label: const Text('HTML'),
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
                Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Summary history',
                    style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Text('${state.summaries.length}',
                    style: theme.textTheme.bodySmall),
                const Spacer(),
                TextButton.icon(
                  onPressed:
                      state.summaries.isEmpty ? null : _clearAllSummaries,
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
            const Divider(height: 20),
            if (state.summaries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No history yet — generated summaries are saved automatically.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
              )
            else
              ...state.summaries.map((s) => InkWell(
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
                            color:
                                theme.colorScheme.outline.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 78,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dateFmt.format(s.dateTime),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600)),
                                Text(timeFmt.format(s.dateTime),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.5))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${s.dateRange} · ${kWorkLogLanguages[s.outputLang] ?? s.outputLang}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.content.length > 100
                                      ? '${s.content.substring(0, 100)}...'
                                      : s.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () => ref
                                .read(workLogProvider.notifier)
                                .deleteSummary(s.id),
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _clearAllSummaries() async {
    final ok = await _confirm('Clear all summary history? This cannot be undone.');
    if (ok) await ref.read(workLogProvider.notifier).clearSummaries();
  }

  // ── Markdown → HTML export (ported from the extension) ───────────────

  String _wrapHtml(String body) {
    return '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="UTF-8"/>\n'
        '<title>Work Summary</title>\n'
        '<style>\n'
        '  body{font-family:Inter,"Segoe UI",sans-serif;background:#0a0a0f;color:#e8eaf0;'
        'padding:40px 48px;max-width:960px;margin:0 auto;line-height:1.85;font-size:15px;}\n'
        '  h2{color:#a78bfa;font-size:1.5rem;border-bottom:1px solid rgba(139,92,246,0.3);padding-bottom:10px;margin:32px 0 16px;}\n'
        '  h3{color:#22d3ee;font-size:1.15rem;margin:24px 0 10px;}\n'
        '  h4{color:#c4b5fd;font-size:1rem;margin:18px 0 8px;}\n'
        '  ul,ol{margin:8px 0 16px 20px;}\n'
        '  li{margin:6px 0;line-height:1.7;}\n'
        '  strong{color:#c4b5fd;}\n'
        '  hr{border:none;border-top:1px solid rgba(139,92,246,0.15);margin:24px 0;}\n'
        '  p{margin:8px 0;}\n'
        '  code{background:rgba(139,92,246,0.12);padding:2px 6px;border-radius:4px;font-size:0.9em;}\n'
        '  a{color:#22d3ee;}\n'
        '</style>\n</head>\n<body>\n$body\n</body>\n</html>';
  }

  String _markdownToHtml(String md) {
    String escape(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    final lines = escape(md).split('\n');
    final out = <String>[];
    String? inList; // 'ul' | 'ol' | null

    void closeList() {
      if (inList != null) {
        out.add('</$inList>');
        inList = null;
      }
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        closeList();
        continue;
      }
      if (RegExp(r'^---+\s*$').hasMatch(line)) {
        closeList();
        out.add('<hr>');
        continue;
      }
      var m = RegExp(r'^##\s+(.+)').firstMatch(line);
      if (m != null) {
        closeList();
        out.add('<h2>${m[1]}</h2>');
        continue;
      }
      m = RegExp(r'^###\s+(.+)').firstMatch(line);
      if (m != null) {
        closeList();
        out.add('<h3>${m[1]}</h3>');
        continue;
      }
      m = RegExp(r'^####\s+(.+)').firstMatch(line);
      if (m != null) {
        closeList();
        out.add('<h4>${m[1]}</h4>');
        continue;
      }
      m = RegExp(r'^[-*]\s+(.+)').firstMatch(line);
      if (m != null) {
        if (inList != 'ul') {
          closeList();
          out.add('<ul>');
          inList = 'ul';
        }
        out.add('<li>${m[1]}</li>');
        continue;
      }
      m = RegExp(r'^\d+\.\s+(.+)').firstMatch(line);
      if (m != null) {
        if (inList != 'ol') {
          closeList();
          out.add('<ol>');
          inList = 'ol';
        }
        out.add('<li>${m[1]}</li>');
        continue;
      }
      closeList();
      var text = line
          .replaceAll(RegExp(r'\*\*(.+?)\*\*'), '<strong>\$1</strong>')
          .replaceAll(RegExp(r'`(.+?)`'), '<code>\$1</code>');
      out.add('<p>$text</p>');
    }
    closeList();
    return out.join('\n');
  }
}
