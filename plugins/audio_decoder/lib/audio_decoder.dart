import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Thrown when [AudioDecoder.decodeToPcm16kMono] fails. [code] mirrors the
/// plugin's AUDIO_DECODER_ERR_* return values (-1 open, -2 unsupported,
/// -3 decode, -4 write); [message] is the user-facing text produced by the
/// native layer.
class AudioDecoderException implements Exception {
  final int code;
  final String message;

  const AudioDecoderException(this.code, this.message);

  @override
  String toString() => message;
}

/// Dart bindings for the `audio_decoder` FFI plugin (vendored under
/// `plugins/audio_decoder`).
///
/// The native entry point is a BLOCKING C call — it must run on a worker
/// isolate (e.g. `Isolate.run(() => AudioDecoder.decodeToPcm16kMono(...))`),
/// never on the UI isolate. Calls are expected to be serialized by the
/// caller (the transcription service's single worker isolate), so the
/// fixed-size scratch buffers inside the native file are race-free.
class AudioDecoder {
  AudioDecoder._();

  static ffi.DynamicLibrary? _dylib;
  static int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Double>, ffi.Pointer<Utf8>, int)? _decodeFn;

  static ffi.DynamicLibrary get _lib {
    if (_dylib != null) return _dylib!;
    if (Platform.isWindows) {
      // Windows bundles the plugin DLL next to the executable.
      _dylib = ffi.DynamicLibrary.open('audio_decoder.dll');
    } else {
      // iOS / macOS: the CocoaPods build compiles the C sources directly
      // into the app binary.
      _dylib = ffi.DynamicLibrary.process();
    }
    return _dylib!;
  }

  /// Decodes the audio file at [path] into a raw (headerless) PCM stream —
  /// 16 kHz, mono, signed 16-bit little-endian — written to [outPath].
  ///
  /// Returns the audio duration in seconds. Throws
  /// [AudioDecoderException] with a user-facing message on failure.
  static double decodeToPcm16kMono(String path, String outPath) {
    _decodeFn ??= _lib
        .lookup<ffi.NativeFunction<_DecodeNative>>(
            'audio_decoder_decode_pcm16k_mono')
        .asFunction<_DecodeDart>();

    final pPath = path.toNativeUtf8(); // malloc-backed (toNativeUtf8 default)
    final pOut = outPath.toNativeUtf8();
    final pDuration = calloc<ffi.Double>();
    final errBuf = calloc<ffi.Uint8>(1024);
    try {
      final rc = _decodeFn!(pPath, pOut, pDuration, errBuf.cast(), 1024);
      if (rc != 0) {
        final msg = errBuf.cast<Utf8>().toDartString();
        throw AudioDecoderException(
            rc, msg.isEmpty ? '音频解码失败（错误码 $rc）' : msg);
      }
      return pDuration.value;
    } finally {
      // Free with the SAME allocator that allocated (toNativeUtf8 → malloc).
      malloc.free(pPath);
      malloc.free(pOut);
      calloc.free(pDuration);
      calloc.free(errBuf);
    }
  }
}

typedef _DecodeNative = ffi.Int32 Function(
    ffi.Pointer<Utf8> path,
    ffi.Pointer<Utf8> outPath,
    ffi.Pointer<ffi.Double> durationSec,
    ffi.Pointer<Utf8> errBuffer,
    ffi.Int32 errBufferSize);

typedef _DecodeDart = int Function(
    ffi.Pointer<Utf8> path,
    ffi.Pointer<Utf8> outPath,
    ffi.Pointer<ffi.Double> durationSec,
    ffi.Pointer<Utf8> errBuffer,
    int errBufferSize);
