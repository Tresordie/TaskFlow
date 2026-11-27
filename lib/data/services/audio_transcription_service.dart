import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Local offline speech recognition for the AI Parse page.
///
/// Ported from the voice_transcription reference project (`offline.ts` +
/// `fileWorker.ts`): the non-streaming **SenseVoice int8** model (~228 MB,
/// bundled with the app as an asset) recognizes zh/en/ja/ko/yue audio with
/// automatic punctuation and number normalization, in 30-second segments —
/// the model is designed for short utterances, and overly long segments slow
/// down markedly and hurt punctuation quality.
///
/// Architecture mirrors the reference worker chain: ALL transcription jobs
/// run in ONE long-lived worker isolate, serially. The SenseVoice model is
/// loaded once and stays resident, so consecutive attachments skip the
/// multi-second model load. Audio decoding (via the `audio_decoder` FFI
/// plugin) also runs inside this isolate — that both serializes the plugin's
/// fixed scratch buffers and keeps blocking calls off the UI isolate.
///
/// Cancellation is cooperative: `cancelCurrent()` sets a flag consumed at
/// the next segment boundary, so latency is bounded by one segment decode
/// (~1-3 s). Cancellation during the (blocking) audio decode takes effect
/// once the decode finishes.
class AudioTranscriptionService {
  AudioTranscriptionService._();

  static AudioTranscriptionService? _instance;

  /// Singleton — one worker isolate (and one resident model) per app run.
  static AudioTranscriptionService get instance =>
      _instance ??= AudioTranscriptionService._();

  /// Audio extensions transcribable on this platform (decoder-supported).
  static const supportedAudioExtensions = [
    'mp3', 'wav', 'm4a', 'aac', 'ogg', 'oga', 'flac', 'm4b',
  ];

  /// Pickable-but-undecodable extensions — accepted in the picker so the
  /// user gets a precise error instead of a mysteriously greyed-out file.
  static const knownUnsupportedAudioExtensions = ['opus', 'webm', 'amr'];

  static bool isSupportedAudio(String extension) =>
      supportedAudioExtensions.contains(extension.toLowerCase());

  static const _pcmSampleRate = 16000;

  /// SenseVoice segment length (seconds) — matches the reference project.
  static const _segmentSeconds = 30;

  // Kept in a field so the spawned isolate is never collected while the
  // service singleton lives.
  // ignore: unused_field
  Isolate? _worker;
  SendPort? _workerPort;
  ReceivePort? _readyPort;

  /// Transcribes the audio file at [path] and returns the recognized text
  /// (joined across segments). [onProgress] receives stage updates;
  /// [onDuration] fires once with the audio duration in seconds after the
  /// decode stage. Throws [TranscriptionException] on failure.
  Future<String> transcribeFile(
    String path, {
    void Function(TranscriptionProgress progress)? onProgress,
    void Function(double durationSec)? onDuration,
  }) async {
    final workerPort = await _ensureWorker();
    final reply = ReceivePort();
    final completer = Completer<Object>();
    final subscription = reply.listen((message) {
      final map = message as Map;
      switch (map['type'] as String) {
        case 'stage':
        case 'progress':
          onProgress?.call(TranscriptionProgress(
            stage: map['stage'] as String,
            done: (map['done'] as num?)?.toInt() ?? 0,
            total: (map['total'] as num?)?.toInt() ?? 0,
          ));
        case 'done':
          if (!completer.isCompleted) {
            completer.complete({
              'text': map['text'] as String,
              'durationSec': (map['durationSec'] as num?)?.toDouble() ?? 0.0,
            });
          }
        case 'error':
          if (!completer.isCompleted) {
            completer.complete(
                TranscriptionError(TranscriptionException(map['message'] as String)));
          }
        case 'cancelled':
          if (!completer.isCompleted) {
            completer.complete(const TranscriptionError(
                TranscriptionException('转写已取消')));
          }
      }
    });
    try {
      // Platform channels (path_provider) and asset materialization only
      // work on the MAIN isolate — resolve everything here and pass it to
      // the worker via the job message (statics don't cross isolates).
      final modelDir = _modelDir ?? await ensureModelReady();
      final tmpDir = (await getTemporaryDirectory()).path;
      workerPort.send({
        'type': 'transcribe',
        'path': path,
        'modelDir': modelDir,
        'tmpDir': tmpDir,
        'reply': reply.sendPort,
      });
      final result = await completer.future;
      if (result is TranscriptionError) throw result.exception;
      final payload = result as Map;
      final duration = payload['durationSec'] as double;
      if (duration > 0) onDuration?.call(duration);
      return payload['text'] as String;
    } finally {
      subscription.cancel();
      reply.close();
    }
  }

  /// Cancels the in-flight transcription, if any. Queued (not yet started)
  /// jobs are unaffected.
  void cancelCurrent() {
    _workerPort?.send({'type': 'cancel'});
  }

  /// Resolves the bundled model to real files and caches the directory
  /// (main-isolate instance field — statics don't cross isolates, so the
  /// path travels to the worker inside each job message). Call from the
  /// MAIN isolate (platform channels / asset files are its territory).
  Future<String> ensureModelReady() async {
    final dir = await _modelTargetDir();
    final model = File(p.join(dir, 'model.int8.onnx'));
    final tokens = File(p.join(dir, 'tokens.txt'));
    if (model.existsSync() &&
        model.lengthSync() == _modelAssetBytes &&
        tokens.existsSync() &&
        tokens.lengthSync() == _tokensAssetBytes) {
      return _modelDir = dir;
    }

    final modelAsset = await _locateAssetFile('assets/models/sensevoice/model.int8.onnx');
    final tokensAsset = await _locateAssetFile('assets/models/sensevoice/tokens.txt');
    if (modelAsset == null || tokensAsset == null) {
      throw const TranscriptionException(
          '找不到内置的 SenseVoice 模型资源（请先运行 scripts/fetch_asr_model.ps1 并重新构建应用）');
    }
    Directory(dir).createSync(recursive: true);
    // Copy via a temp + rename so a killed copy can never look complete.
    final tmp = File('${model.path}.tmp');
    await File(modelAsset).copy(tmp.path);
    if (tmp.lengthSync() != _modelAssetBytes) {
      tmp.deleteSync();
      throw const TranscriptionException('SenseVoice 模型资源校验失败（文件不完整，请重新构建）');
    }
    await tmp.rename(model.path);
    await File(tokensAsset).copy(tokens.path);
    return _modelDir = dir;
  }

  /// Cached model directory (main isolate only — see transcribeFile).
  String? _modelDir;

  // -------------------------------------------------------------------------
  // Worker plumbing (main isolate side)
  // -------------------------------------------------------------------------

  Future<SendPort> _ensureWorker() async {
    if (_workerPort != null) return _workerPort!;
    _readyPort?.close();
    final ready = ReceivePort();
    _readyPort = ready;
    final completer = Completer<SendPort>();
    ready.listen((message) {
      final map = message as Map;
      if (map['type'] == 'worker-ready' && !completer.isCompleted) {
        completer.complete(map['port'] as SendPort);
      }
    });
    _worker = await Isolate.spawn(_workerMain, ready.sendPort);
    return completer.future;
  }

  // -------------------------------------------------------------------------
  // Worker isolate body
  // -------------------------------------------------------------------------

  @pragma('vm:entry-point')
  static Future<void> _workerMain(SendPort mainPort) async {
    final inbox = ReceivePort();
    mainPort.send({'type': 'worker-ready', 'port': inbox.sendPort});

    // sherpa-onnx FFI binding state is PER ISOLATE — initialize here, not
    // just on the main isolate.
    sherpa.initBindings();

    sherpa.OfflineRecognizer? recognizer;
    final jobs = <Map>[];
    // The ACTIVE job record (isolate transfers deserialize as Map, so the
    // cancelled flag is set via dynamic indexing).
    Map? active;
    var draining = false;

    Future<void> drain() async {
      if (draining) return;
      draining = true;
      try {
        while (jobs.isNotEmpty) {
          final job = jobs.removeAt(0);
          active = job;
          try {
            await _runJob(
                job, () => recognizer ??= _createRecognizer(job['modelDir'] as String));
          } finally {
            active = null;
          }
        }
      } finally {
        draining = false;
      }
    }

    inbox.listen((message) {
      final map = message as Map;
      if (map['type'] == 'cancel') {
        // Only the ACTIVE job is cancellable; queued jobs haven't started.
        active?['cancelled'] = true;
      } else if (map['type'] == 'transcribe') {
        jobs.add(map);
        unawaited(drain());
      }
    });
  }

  static Future<void> _runJob(
      Map job, sherpa.OfflineRecognizer Function() recognizerProvider) async {
    final reply = job['reply'] as SendPort;
    final path = job['path'] as String;
    final cancelled = () => job['cancelled'] == true;
    void send(Map m) => reply.send(m);

    File? pcmFile;
    try {
      send({'type': 'stage', 'stage': 'loading'});
      final recognizer = recognizerProvider();

      // 1) Decode → raw s16le / 16 kHz / mono PCM temp file (blocking FFI
      //    inside this worker isolate is fine — blocking is its job).
      //    tmpDir comes from the MAIN isolate (platform channels don't
      //    reach background isolates).
      send({'type': 'stage', 'stage': 'decoding'});
      pcmFile = File(p.join((job['tmpDir'] as String),
          'taskflow_asr_${DateTime.now().microsecondsSinceEpoch}.pcm'));
      final durationSec =
          AudioDecoder.decodeToPcm16kMono(path, pcmFile.path);

      // 2) Recognize in 30 s segments.
      final bytes = await pcmFile.length();
      final bytesPerSegment = _segmentSeconds * _pcmSampleRate * 2; // s16
      final totalSegments =
          (bytes / bytesPerSegment).ceil().clamp(1, 1 << 30);
      send({'type': 'progress', 'stage': 'recognizing', 'done': 0, 'total': totalSegments});

      final parts = <String>[];
      final raf = pcmFile.openSync(mode: FileMode.read);
      try {
        final buf = Uint8List(bytesPerSegment);
        var segment = 0;
        while (segment < totalSegments) {
          // Cooperative cancel point: yield to the event loop so a pending
          // cancel message (listen handler) gets a chance to run.
          await Future<void>.delayed(Duration.zero);
          if (cancelled()) {
            send({'type': 'cancelled'});
            return;
          }
          final read = raf.readIntoSync(buf);
          if (read <= 0) break;
          parts.add(_recognizeSegment(recognizer, buf, read));
          segment++;
          send({
            'type': 'progress',
            'stage': 'recognizing',
            'done': segment,
            'total': totalSegments,
          });
        }
      } finally {
        raf.closeSync();
      }
      send({
        'type': 'done',
        'text': joinTranscriptParts(parts),
        'durationSec': durationSec,
      });
    } catch (e) {
      send({
        'type': 'error',
        'message': e is AudioDecoderException ? e.message : '转写失败：$e',
      });
    } finally {
      try {
        if (pcmFile != null && await pcmFile.exists()) await pcmFile.delete();
      } catch (_) {}
    }
  }

  static sherpa.OfflineRecognizer _createRecognizer(String modelDir) {
    return sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: p.join(modelDir, 'model.int8.onnx'),
          // '' = auto language detection (zh/en/ja/ko/yue).
          language: '',
          useInverseTextNormalization: true,
        ),
        tokens: p.join(modelDir, 'tokens.txt'),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    ));
  }

  /// Recognizes one segment of s16 PCM bytes and returns its text.
  static String _recognizeSegment(
      sherpa.OfflineRecognizer recognizer, Uint8List buf, int byteCount) {
    final frames = byteCount ~/ 2;
    if (frames <= 0) return '';
    final floats = Float32List(frames);
    final view = ByteData.sublistView(buf, 0, frames * 2);
    for (var i = 0; i < frames; i++) {
      floats[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: floats, sampleRate: _pcmSampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  // -------------------------------------------------------------------------
  // Model asset extraction (main isolate)
  // -------------------------------------------------------------------------

  static const _modelAssetBytes = 239233841;
  static const _tokensAssetBytes = 315894;

  Future<String> _modelTargetDir() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'models', 'sensevoice');
  }

  /// Native Flutter bundles keep assets as REAL FILES on disk (Windows:
  /// `<exe>/data/flutter_assets`; Apple: the app bundle's flutter_assets
  /// directory) — locating the file lets a 228 MB copy stay in the OS file
  /// layer instead of detouring through Dart heap memory.
  Future<String?> _locateAssetFile(String assetKey) async {
    final segments = assetKey.split('/');
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundleDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      if (Platform.isWindows)
        p.joinAll([exeDir, 'data', 'flutter_assets', ...segments]),
      if (Platform.isIOS || Platform.isMacOS) ...[
        p.joinAll([
          bundleDir,
          'Frameworks',
          'App.framework',
          'flutter_assets',
          ...segments,
        ]),
        p.joinAll([p.dirname(bundleDir), 'flutter_assets', ...segments]),
        p.joinAll([bundleDir, 'flutter_assets', ...segments]),
      ],
    ];
    for (final candidate in candidates) {
      final f = File(candidate);
      if (f.existsSync()) return candidate;
    }
    return null;
  }
}

/// Progress snapshot for the UI: [stage] is one of
/// `loading` / `decoding` / `recognizing`; [done]/[total] carry segment
/// counts while `recognizing`.
class TranscriptionProgress {
  final String stage;
  final int done;
  final int total;

  const TranscriptionProgress({
    required this.stage,
    this.done = 0,
    this.total = 0,
  });
}

/// User-facing transcription failure.
class TranscriptionException implements Exception {
  final String message;
  const TranscriptionException(this.message);

  @override
  String toString() => message;
}

class TranscriptionError {
  final TranscriptionException exception;
  const TranscriptionError(this.exception);
}

/// Joins per-segment transcripts: a space is inserted between fragments only
/// when both sides are ASCII word-ish (mirrors the reference `joinParts`) so
/// Chinese stays glued and English keeps word boundaries.
String joinTranscriptParts(List<String> parts) {
  var out = '';
  for (final part in parts) {
    final t = part.trim();
    if (t.isEmpty) continue;
    if (out.isEmpty) {
      out = t;
      continue;
    }
    final last = out[out.length - 1];
    final needSpace = RegExp(r'[a-zA-Z0-9,.!?;:]$').hasMatch(last) &&
        RegExp(r'^[a-zA-Z0-9(]').hasMatch(t);
    out += (needSpace ? ' ' : '') + t;
  }
  return out;
}
