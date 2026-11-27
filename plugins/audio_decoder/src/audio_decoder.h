#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

// Audio file → raw PCM decoder for the TaskFlow AI Parse page.
//
// Converts a supported audio file to a raw (headerless) PCM stream:
// 16 kHz, mono, signed 16-bit little-endian — the exact input format the
// sherpa-onnx SenseVoice recognizer consumes.
//
// Format support:
//  - wav / mp3 / ogg / flac: every platform (vendored miniaudio).
//  - m4a / aac: Apple platforms via AudioToolbox (ExtAudioFile) and
//    Windows via Media Foundation Source Reader (system AAC decoder).
//  - opus / webm / amr etc.: NOT supported — reported via
//    AUDIO_DECODER_ERR_UNSUPPORTED with a user-facing message.

#define AUDIO_DECODER_ERR_OPEN        -1
#define AUDIO_DECODER_ERR_UNSUPPORTED -2
#define AUDIO_DECODER_ERR_DECODE      -3
#define AUDIO_DECODER_ERR_WRITE       -4

// Blocking call (run it on a worker isolate). Writes the decoded stream to
// [out_path] and, on success, stores the duration in seconds in
// *duration_sec_out (when non-NULL).
//
// [path] and [out_path] are UTF-8 encoded. On failure a human-readable
// UTF-8 message is written to [err_buffer] (always NUL-terminated) and one
// of the AUDIO_DECODER_ERR_* codes is returned.
FFI_PLUGIN_EXPORT int audio_decoder_decode_pcm16k_mono(
    const char* path,
    const char* out_path,
    double* duration_sec_out,
    char* err_buffer,
    int err_buffer_size);
