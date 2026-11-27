import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/services/ai_service.dart';
import '../data/services/audio_transcription_service.dart';
import '../data/services/content_extractor.dart';
import '../data/services/summarize_pipeline.dart';
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
/// kept until a NEW analyze run starts — with v1.15.0 streaming output the
/// new run's first delta replaces it progressively; on failure the old
/// summary is kept intact.
class AiParseSessionState {
  final String notes;
  final String instructions;

  /// v1.15.0: attachments are first-class records with per-file processing
  /// state (extraction / transcription progress happens OUTSIDE the analyze
  /// run, as soon as the file is picked).
  final List<AiParseAttachment> attachments;
  final String summary;
  final bool summarizing;

  /// Human-readable stage line while [summarizing]
  /// (`理解全文（分块提取要点） 3/12`, `生成总结`).
  final String stageText;
  final String? error;
  final List<ParsedTask> results;

  /// Selected summary template id ('free' = free mode + G_SPEC).
  final String selectedTemplateId;

  /// Output language value ('' = follow source); see kOutputLanguages.
  final String outputLanguage;

  const AiParseSessionState({
    this.notes = '',
    this.instructions = '',
    this.attachments = const [],
    this.summary = '',
    this.summarizing = false,
    this.stageText = '',
    this.error,
    this.results = const [],
    this.selectedTemplateId = 'free',
    this.outputLanguage = '',
  });

  bool get hasInput =>
      notes.trim().isNotEmpty || attachments.isNotEmpty;

  /// Analyze is blocked while any attachment is still processing.
  bool get attachmentsReady =>
      attachments.every((a) => a.status == AiParseAttachmentStatus.ready);

  AiParseSessionState copyWith({
    String? notes,
    String? instructions,
    List<AiParseAttachment>? attachments,
    String? summary,
    bool? summarizing,
    String? stageText,
    String? error,
    bool clearError = false,
    List<ParsedTask>? results,
    bool clearSummary = false,
    bool clearResults = false,
    String? selectedTemplateId,
    String? outputLanguage,
    bool clearStage = false,
  }) {
    return AiParseSessionState(
      notes: notes ?? this.notes,
      instructions: instructions ?? this.instructions,
      attachments: attachments ?? this.attachments,
      summary: clearSummary ? '' : (summary ?? this.summary),
      summarizing: summarizing ?? this.summarizing,
      stageText: clearStage ? '' : (stageText ?? this.stageText),
      error: clearError ? null : (error ?? this.error),
      results: clearResults ? const [] : (results ?? this.results),
      selectedTemplateId: selectedTemplateId ?? this.selectedTemplateId,
      outputLanguage: outputLanguage ?? this.outputLanguage,
    );
  }
}

/// One file in the AI Parse attachment list.
class AiParseAttachment {
  final String id;
  final String name;
  final String ext;

  /// 0 = unknown/not read yet.
  final int sizeBytes;
  final AiParseAttachmentKind kind;
  final AiParseAttachmentStatus status;

  /// Extracted text (documents) / transcript (audio); empty until [status]
  /// is ready.
  final String content;

  /// Segment progress while transcribing (done/total).
  final int done;
  final int total;

  /// Audio duration in seconds (transcription pipeline reports it).
  final double? durationSec;
  final String? error;

  const AiParseAttachment({
    required this.id,
    required this.name,
    required this.ext,
    required this.kind,
    required this.status,
    this.sizeBytes = 0,
    this.content = '',
    this.done = 0,
    this.total = 0,
    this.durationSec,
    this.error,
  });

  AiParseAttachment copyWith({
    AiParseAttachmentStatus? status,
    String? content,
    int? done,
    int? total,
    double? durationSec,
    String? error,
    bool clearError = false,
  }) {
    return AiParseAttachment(
      id: id,
      name: name,
      ext: ext,
      kind: kind,
      sizeBytes: sizeBytes,
      status: status ?? this.status,
      content: content ?? this.content,
      done: done ?? this.done,
      total: total ?? this.total,
      durationSec: durationSec ?? this.durationSec,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

enum AiParseAttachmentKind { doc, audio }

enum AiParseAttachmentStatus { extracting, transcribing, ready, failed }

class AiParseSessionNotifier extends StateNotifier<AiParseSessionState> {
  AiParseSessionNotifier() : super(const AiParseSessionState());

  int _idCounter = 0;
  String _nextId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  /// Run token: starting a new analyze run invalidates every in-flight
  /// callback of the previous one (late deltas / progress must not clobber
  /// the newer run's state).
  int _runSeq = 0;
  bool _cancelRequested = false;

  void setNotes(String value) => state = state.copyWith(notes: value);

  void setInstructions(String value) =>
      state = state.copyWith(instructions: value);

  void setTemplate(String templateId) =>
      state = state.copyWith(selectedTemplateId: templateId);

  void setOutputLanguage(String language) =>
      state = state.copyWith(outputLanguage: language);

  /// Direct (already-extracted) attachment add — used by tests and by any
  /// caller that has the text in hand. The file-picking flow uses
  /// [addAttachmentFile] instead.
  void addAttachment({required String name, required String content}) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    state = state.copyWith(
      attachments: [
        ...state.attachments,
        AiParseAttachment(
          id: _nextId(),
          name: name,
          ext: ext,
          kind: AiParseAttachmentKind.doc,
          status: AiParseAttachmentStatus.ready,
          content: content,
        ),
      ],
    );
  }

  /// v1.15.0: full attachment pipeline — validates size, then extracts text
  /// (documents, on a worker isolate) or transcribes (audio, via the local
  /// SenseVoice service). Progress lands in state per attachment; failures
  /// mark the attachment failed WITHOUT aborting the page.
  Future<void> addAttachmentFile(String path) async {
    final name = p.basename(path);
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    final isAudio = ContentExtractor.isAudioExtension(ext);
    final kind =
        isAudio ? AiParseAttachmentKind.audio : AiParseAttachmentKind.doc;

    final id = _nextId();
    final file = File(path);
    try {
      final size = await file.length();
      if (size > ContentExtractor.maxFileBytes) {
        state = state.copyWith(
          attachments: [
            ...state.attachments,
            AiParseAttachment(
              id: id,
              name: name,
              ext: ext,
              kind: kind,
              sizeBytes: size,
              status: AiParseAttachmentStatus.failed,
              error: '文件超过 150 MB 上限',
            ),
          ],
        );
        return;
      }

      final placeholder = AiParseAttachment(
        id: id,
        name: name,
        ext: ext,
        kind: kind,
        sizeBytes: size,
        status: isAudio
            ? AiParseAttachmentStatus.transcribing
            : AiParseAttachmentStatus.extracting,
      );
      state = state.copyWith(attachments: [...state.attachments, placeholder]);

      String text;
      if (isAudio) {
        // Known-undecodable formats fail fast with a conversion hint —
        // without touching the model pipeline at all.
        if (!AudioTranscriptionService.isSupportedAudio(ext)) {
          throw const TranscriptionException(
              '暂不支持该音频格式（opus/webm/amr），请先转换为 mp3/wav/m4a 后再添加');
        }
        // Local offline transcription — no API config needed (bundled
        // SenseVoice model); transcribeFile self-ensures the model is
        // materialized before the job starts.
        text = await AudioTranscriptionService.instance.transcribeFile(
          path,
          onProgress: (progress) => _updateAttachment(id, (a) => a.copyWith(
                done: progress.done,
                total: progress.total,
              )),
          onDuration: (seconds) =>
              _updateAttachment(id, (a) => a.copyWith(durationSec: seconds)),
        );
      } else {
        // Heavy ZIP/XML parsing runs off the UI isolate — see the
        // [_extractAttachmentText] doc comment for why the whole Isolate.run
        // call must live in a TOP-LEVEL function.
        text = await _extractAttachmentText(path);
      }
      _updateAttachment(
          id, (a) => a.copyWith(status: AiParseAttachmentStatus.ready, content: text));
    } catch (e) {
      final message =
          e.toString().replaceFirst(RegExp(r'^[A-Za-z]+Exception: '), '');
      _updateAttachment(
        id,
        (a) => a.copyWith(
            status: AiParseAttachmentStatus.failed,
            error: message.isEmpty ? '处理失败' : message),
      );
    }
  }

  void _updateAttachment(
      String id, AiParseAttachment Function(AiParseAttachment) update) {
    if (!mounted) return;
    final index = state.attachments.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final list = [...state.attachments];
    list[index] = update(list[index]);
    state = state.copyWith(attachments: list);
  }

  void removeAttachment(int index) => state = state.copyWith(
        attachments: [...state.attachments]..removeAt(index),
      );

  void showError(String message) => state = state.copyWith(error: message);

  void clearError() => state = state.copyWith(clearError: true);

  /// Test hook: simulates a finished AI run without hitting the network.
  void setSummaryForTest(String summary) =>
      state = state.copyWith(summarizing: false, summary: summary);

  void clearResults() => state = state.copyWith(clearResults: true);

  /// Requests cancellation of the in-flight analyze run. The pipeline stops
  /// at the next chunk/stage boundary; partial output streamed so far stays
  /// in [AiParseSessionState.summary].
  void cancelSummarize() => _cancelRequested = true;

  /// v1.15.0: analyze/summarize via the map-reduce pipeline (ported from
  /// the voice_transcription reference project) — template / user prompt /
  /// output language aware, streaming into [AiParseSessionState.summary].
  /// Still runs INSIDE the notifier so page switches neither cancel the AI
  /// call nor lose the result.
  Future<void> summarize({
    required String content,
    required String instructions,
    required bool email,
    required AiConfig config,
    String? templateId,
    String? outputLanguage,
  }) async {
    if (state.summarizing) return;
    _runSeq++;
    final seq = _runSeq;
    _cancelRequested = false;
    bool isCancelled() => _cancelRequested || seq != _runSeq;
    state = state.copyWith(
      summarizing: true,
      clearError: true,
      clearResults: true,
      clearStage: true,
      // The previous summary is KEPT while the run is in flight (and on
      // failure) and replaced from the first streamed delta onward.
    );
    try {
      final service = AiService(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
      );
      final result = await runSummarize(
        service,
        content: content,
        templateId: templateId ?? state.selectedTemplateId,
        userPrompt: instructions,
        outputLanguage: outputLanguage ?? state.outputLanguage,
        email: email,
        isCancelled: isCancelled,
        onProgress: (stage, done, total) {
          if (seq != _runSeq) return;
          state = state.copyWith(
            stageText: total > 0 ? '$stage $done/$total' : stage,
          );
        },
        onDelta: (delta, full) {
          if (seq != _runSeq) return;
          state = state.copyWith(summary: full, clearStage: true);
        },
      );
      if (seq != _runSeq) return;
      state = state.copyWith(
        summarizing: false,
        summary: result,
        clearStage: true,
      );
    } on AiCancelledException {
      if (seq == _runSeq) {
        state = state.copyWith(summarizing: false, clearStage: true);
      }
    } catch (e) {
      if (seq != _runSeq) return;
      state = state.copyWith(summarizing: false, clearStage: true, error: e.toString());
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
    _runSeq++;
    state = state.copyWith(
      summarizing: true,
      clearError: true,
      clearResults: true,
      clearStage: true,
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
        clearStage: true,
        results: tasks,
      );
      if (tasks.isEmpty) {
        state = state.copyWith(
          error: 'No actionable tasks found in the notes.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        summarizing: false,
        clearStage: true,
        error: e.toString(),
      );
    }
  }
}

final aiParseSessionProvider =
    StateNotifierProvider<AiParseSessionNotifier, AiParseSessionState>((ref) {
  return AiParseSessionNotifier();
});

/// TOP-LEVEL home for the attachment text extraction's `Isolate.run` call.
///
/// The closure handed to `Isolate.run` is created HERE — inside a top-level
/// async function whose context holds only [path] — because ANY closure
/// created inside an async INSTANCE method (even one whose body references
/// just a string) captures the method's whole state-machine context,
/// including `this`. With `this` being a Riverpod StateNotifier, the sent
/// graph reaches its listener chain → the ProviderContainer → every
/// provider element (Timer-bearing notifiers like SyncNotifier) →
/// `SendPort.send` rejects it with "object is unsendable" and every
/// document attachment fails (v1.15.0 regression, caught by the
/// container-scoped test in ai_parse_attachment_flow_test.dart).
Future<String> _extractAttachmentText(String path) =>
    Isolate.run(() => ContentExtractor.extract(File(path)));
