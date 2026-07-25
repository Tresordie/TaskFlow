import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models/work_log.dart';
import '../data/repositories/work_log_repository.dart';
import '../data/services/ai_service.dart';
import 'ai_provider.dart';

final workLogRepositoryProvider = Provider<WorkLogRepository>((ref) {
  return WorkLogRepository();
});

/// Immutable UI state for the Work Log page.
class WorkLogState {
  final List<WorkLogRecord> records;
  final List<WorkLogSummary> summaries;
  final String inputLang;
  final String outputLang;
  final bool loaded;
  final bool generating;

  /// The most recent summary text (rendered in the result panel).
  final String result;
  final String? error;

  const WorkLogState({
    this.records = const [],
    this.summaries = const [],
    this.inputLang = 'zh',
    this.outputLang = 'zh',
    this.loaded = false,
    this.generating = false,
    this.result = '',
    this.error,
  });

  WorkLogState copyWith({
    List<WorkLogRecord>? records,
    List<WorkLogSummary>? summaries,
    String? inputLang,
    String? outputLang,
    bool? loaded,
    bool? generating,
    String? result,
    Object? error = _unset,
  }) {
    return WorkLogState(
      records: records ?? this.records,
      summaries: summaries ?? this.summaries,
      inputLang: inputLang ?? this.inputLang,
      outputLang: outputLang ?? this.outputLang,
      loaded: loaded ?? this.loaded,
      generating: generating ?? this.generating,
      result: result ?? this.result,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

const Object _unset = Object();

final workLogProvider =
    StateNotifierProvider<WorkLogNotifier, WorkLogState>((ref) {
  return WorkLogNotifier(ref);
});

class WorkLogNotifier extends StateNotifier<WorkLogState> {
  final Ref _ref;

  WorkLogNotifier(this._ref) : super(const WorkLogState()) {
    _load();
  }

  WorkLogRepository get _repo => _ref.read(workLogRepositoryProvider);

  Future<void> _load() async {
    final records = await _repo.loadRecords();
    final summaries = await _repo.loadSummaries();
    final langs = await _repo.loadLangs();
    state = state.copyWith(
      records: records,
      summaries: summaries,
      inputLang: langs.inputLang,
      outputLang: langs.outputLang,
      loaded: true,
    );
  }

  // ── Records ──────────────────────────────────────────────────────────

  Future<void> addRecord(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final record =
        WorkLogRecord(id: now.toString(), content: text, timestamp: now);
    final records = [record, ...state.records];
    state = state.copyWith(records: records);
    await _repo.saveRecords(records);
    await _repo.saveDraft('');
  }

  Future<void> updateRecord(String id, String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = state.records
        .where((r) => r.id != id)
        .toList();
    records.insert(
        0, WorkLogRecord(id: id, content: text, timestamp: now));
    state = state.copyWith(records: records);
    await _repo.saveRecords(records);
    await _repo.saveDraft('');
  }

  Future<void> deleteRecord(String id) async {
    final records = state.records.where((r) => r.id != id).toList();
    state = state.copyWith(records: records);
    await _repo.saveRecords(records);
  }

  Future<void> clearRecords() async {
    state = state.copyWith(records: []);
    await _repo.saveRecords([]);
  }

  Future<void> saveDraft(String text) => _repo.saveDraft(text);

  // ── Languages ────────────────────────────────────────────────────────

  Future<void> setLangs(
      {required String inputLang, required String outputLang}) async {
    state = state.copyWith(inputLang: inputLang, outputLang: outputLang);
    await _repo.saveLangs(inputLang: inputLang, outputLang: outputLang);
  }

  // ── AI summary ───────────────────────────────────────────────────────

  /// Summarizes [records] (already filtered/selected by the caller).
  Future<void> generateSummary(List<WorkLogRecord> records) async {
    if (records.isEmpty) {
      state = state.copyWith(
          error: 'No work records to summarize. Adjust the filter or select records.');
      return;
    }
    final config = _ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      state = state.copyWith(
          error: 'AI is not configured. Set Base URL / API Key / Model in Settings → AI.');
      return;
    }

    state = state.copyWith(generating: true, error: null, result: '');
    try {
      // Records are newest-first; reverse for chronological prompt order.
      final chronological = records.reversed.toList();
      final recordsText = AiService.formatWorkLogRecords([
        for (final r in chronological)
          (timestamp: r.timestamp, content: r.content),
      ]);
      final dateRange = _dateRange(chronological);

      final service = AiService(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      );
      final result = await service.summarizeWorkLog(
        recordsText: recordsText,
        dateRange: dateRange,
        inputLang: state.inputLang,
        outputLang: state.outputLang,
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final summary = WorkLogSummary(
        id: now.toString(),
        dateRange: dateRange,
        content: result,
        inputLang: state.inputLang,
        outputLang: state.outputLang,
        timestamp: now,
      );
      final summaries = [summary, ...state.summaries];
      state = state.copyWith(
        generating: false,
        result: result,
        summaries: summaries,
      );
      await _repo.saveSummaries(summaries);
    } on AiServiceException catch (e) {
      state = state.copyWith(generating: false, error: e.message);
    } catch (e) {
      state = state.copyWith(generating: false, error: e.toString());
    }
  }

  /// Loads a past summary back into the result panel.
  void loadSummary(WorkLogSummary summary) {
    state = state.copyWith(result: summary.content, error: null);
  }

  Future<void> deleteSummary(String id) async {
    final summaries = state.summaries.where((s) => s.id != id).toList();
    state = state.copyWith(summaries: summaries);
    await _repo.saveSummaries(summaries);
  }

  Future<void> clearSummaries() async {
    state = state.copyWith(summaries: []);
    await _repo.saveSummaries([]);
  }

  static String _dateRange(List<WorkLogRecord> chronological) {
    if (chronological.isEmpty) return '';
    final f = DateFormat('yyyy-MM-dd');
    final first = f.format(chronological.first.dateTime);
    final last = f.format(chronological.last.dateTime);
    return first == last ? first : '$first to $last';
  }
}
