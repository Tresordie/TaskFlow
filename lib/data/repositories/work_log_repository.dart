import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/work_log.dart';

/// Persists Work Log records, generated summaries and the input draft in
/// shared_preferences as JSON lists — the same key/value model the
/// LinguaFlow Chrome extension used (chrome.storage.local / localStorage).
class WorkLogRepository {
  static const _kRecords = 'worklog.records';
  static const _kSummaries = 'worklog.summaries';
  static const _kDraft = 'worklog.draft';
  static const _kInputLang = 'worklog.inputLang';
  static const _kOutputLang = 'worklog.outputLang';

  /// Cap matches the extension: keep the lists bounded.
  static const int maxRecords = 200;
  static const int maxSummaries = 50;

  Future<List<WorkLogRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecords);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(WorkLogRecord.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecords(List<WorkLogRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final bounded =
        records.length > maxRecords ? records.sublist(0, maxRecords) : records;
    await prefs.setString(
        _kRecords, jsonEncode(bounded.map((r) => r.toJson()).toList()));
  }

  Future<List<WorkLogSummary>> loadSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSummaries);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(WorkLogSummary.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSummaries(List<WorkLogSummary> summaries) async {
    final prefs = await SharedPreferences.getInstance();
    final bounded = summaries.length > maxSummaries
        ? summaries.sublist(0, maxSummaries)
        : summaries;
    await prefs.setString(
        _kSummaries, jsonEncode(bounded.map((s) => s.toJson()).toList()));
  }

  Future<String> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDraft) ?? '';
  }

  Future<void> saveDraft(String text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      await prefs.remove(_kDraft);
    } else {
      await prefs.setString(_kDraft, text);
    }
  }

  Future<({String inputLang, String outputLang})> loadLangs() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      inputLang: prefs.getString(_kInputLang) ?? 'zh',
      outputLang: prefs.getString(_kOutputLang) ?? 'zh',
    );
  }

  Future<void> saveLangs(
      {required String inputLang, required String outputLang}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInputLang, inputLang);
    await prefs.setString(_kOutputLang, outputLang);
  }
}
