import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/ai_service.dart';
import 'ai_provider.dart';

/// Session-scoped state for the AI Parse page (v1.6.1).
///
/// ShellRoute DISPOSES the page widget on every navigation, so an AI call
/// started from the screen would be orphaned (its `setState` throws after
/// dispose) and the result lost. Lifting the AI work into this notifier —
/// which lives in the root ProviderContainer for the whole app session —
/// keeps the summarize/parse running while the user browses other pages,
/// and the result is waiting in [state] when they come back.
///
/// Persistence contract (user requirement): the generated [summary] is
/// kept until a NEW analyze run starts — only then is it cleared and
/// replaced.
class AiParseSessionState {
  final String notes;
  final String instructions;
  final List<({String name, String content})> attachments;
  final String summary;
  final bool summarizing;
  final String? error;
  final List<ParsedTask> results;

  const AiParseSessionState({
    this.notes = '',
    this.instructions = '',
    this.attachments = const [],
    this.summary = '',
    this.summarizing = false,
    this.error,
    this.results = const [],
  });

  bool get hasInput => notes.trim().isNotEmpty || attachments.isNotEmpty;

  AiParseSessionState copyWith({
    String? notes,
    String? instructions,
    List<({String name, String content})>? attachments,
    String? summary,
    bool? summarizing,
    String? error,
    bool clearError = false,
    List<ParsedTask>? results,
    bool clearSummary = false,
    bool clearResults = false,
  }) {
    return AiParseSessionState(
      notes: notes ?? this.notes,
      instructions: instructions ?? this.instructions,
      attachments: attachments ?? this.attachments,
      summary: clearSummary ? '' : (summary ?? this.summary),
      summarizing: summarizing ?? this.summarizing,
      error: clearError ? null : (error ?? this.error),
      results: clearResults ? const [] : (results ?? this.results),
    );
  }
}

class AiParseSessionNotifier extends StateNotifier<AiParseSessionState> {
  AiParseSessionNotifier() : super(const AiParseSessionState());

  void setNotes(String value) => state = state.copyWith(notes: value);

  void setInstructions(String value) =>
      state = state.copyWith(instructions: value);

  void addAttachment({required String name, required String content}) =>
      state = state.copyWith(
        attachments: [
          ...state.attachments,
          (name: name, content: content),
        ],
      );

  void removeAttachment(int index) => state = state.copyWith(
        attachments: [...state.attachments]..removeAt(index),
      );

  void showError(String message) => state = state.copyWith(error: message);

  void clearError() => state = state.copyWith(clearError: true);

  /// Test hook: simulates a finished AI run without hitting the network.
  void setSummaryForTest(String summary) =>
      state = state.copyWith(summarizing: false, summary: summary);

  void clearResults() => state = state.copyWith(clearResults: true);

  /// v1.6.1: runs the analyze/summarize call INSIDE the notifier so it
  /// keeps running (and lands in [AiParseSessionState.summary]) even when
  /// the user switches to another page mid-flight. The previous summary is
  /// KEPT while the new run is in flight (and on failure) — it is replaced
  /// only when the new result lands, per the user contract "keep the
  /// summary until the next one is generated".
  Future<void> summarize({
    required String content,
    required String instructions,
    required bool email,
    required AiConfig config,
  }) async {
    if (state.summarizing) return;
    state = state.copyWith(
      summarizing: true,
      clearError: true,
      clearResults: true,
    );
    try {
      final service = AiService(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      );
      final result = await service.analyzeContent(
        content: content,
        instructions: instructions,
        email: email,
      );
      state = state.copyWith(summarizing: false, summary: result);
    } catch (e) {
      state = state.copyWith(summarizing: false, error: e.toString());
    }
  }

  /// Classic structured task extraction — same app-session lifetime
  /// guarantee as [summarize]. A previous analyze summary is cleared only
  /// when the new tasks land, never on start or on failure.
  Future<void> parseTasks({
    required String notes,
    required AiConfig config,
  }) async {
    if (state.summarizing) return;
    state = state.copyWith(
      summarizing: true,
      clearError: true,
      clearResults: true,
    );
    try {
      final service = AiService(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      );
      final tasks = await service.parseNotes(notes);
      state = state.copyWith(
        summarizing: false,
        clearSummary: true,
        results: tasks,
      );
      if (tasks.isEmpty) {
        state = state.copyWith(
          error: 'No actionable tasks found in the notes.',
        );
      }
    } catch (e) {
      state = state.copyWith(summarizing: false, error: e.toString());
    }
  }
}

final aiParseSessionProvider =
    StateNotifierProvider<AiParseSessionNotifier, AiParseSessionState>((ref) {
  return AiParseSessionNotifier();
});
