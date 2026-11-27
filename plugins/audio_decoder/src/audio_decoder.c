#include "audio_decoder.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// miniaudio (vendored single header) — wav / mp3 / ogg / flac decoding plus
// channel/rate conversion. Device output, encoding and generation are
// compiled out: this plugin only ever decodes files.
// ---------------------------------------------------------------------------
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DEVICE_IO
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#if defined(_WIN32)
// COBJMACROS exposes the C-style IMFxxx_Method macros for COM calls from C.
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#endif

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#endif

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

static void set_err(char* err_buffer, int err_buffer_size, const char* msg) {
    if (err_buffer == NULL || err_buffer_size <= 0) return;
    snprintf(err_buffer, (size_t)err_buffer_size, "%s", msg);
    err_buffer[err_buffer_size - 1] = '\0';
}

static int extension_is(const char* path, const char* ext) {
    const char* slash = strrchr(path, '/');
    const char* back = strrchr(path, '\\');
    const char* base = slash > back ? slash : (back ? back : path);
    const char* dot = strrchr(base, '.');
    if (dot == NULL || dot == base) return 0;
    const char* e = dot + 1;
    size_t n = strlen(ext);
    if (strlen(e) != n) return 0;
    for (size_t i = 0; i < n; i++) {
        char a = e[i], b = ext[i];
        if (a >= 'A' && a <= 'Z') a = (char)(a + 32);
        if (a != b) return 0;
    }
    return 1;
}

// UTF-8 safe output-file open (MSVC fopen uses the ANSI codepage).
static FILE* open_output_file(const char* path) {
    FILE* f = NULL;
#if defined(_WIN32)
    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (wlen <= 0) return NULL;
    wchar_t* wpath = (wchar_t*)malloc((size_t)wlen * sizeof(wchar_t));
    if (wpath == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);
    f = _wfopen(wpath, L"wb");
    free(wpath);
#else
    f = fopen(path, "wb");
#endif
    if (f != NULL) {
        static char io_buf[1 << 16];
        setvbuf(f, io_buf, _IOFBF, sizeof(io_buf));
    }
    return f;
}

static int write_all(FILE* f, const void* samples_s16, size_t byte_count) {
    if (byte_count == 0) return 0;
    if (fwrite(samples_s16, 1, byte_count, f) != byte_count) return -1;
    return 0;
}

// ---------------------------------------------------------------------------
// miniaudio path — wav / mp3 / ogg / flac on every platform. The decoder is
// initialized with the TARGET format (s16 / mono / 16 kHz) and miniaudio's
// built-in data converter performs channel mixdown + resampling while read.
// ---------------------------------------------------------------------------
static int decode_with_miniaudio(const char* path, FILE* out,
                                 double* duration_sec_out, char* err,
                                 int err_size) {
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_s16, 1, 16000);
    ma_decoder decoder;
    ma_result r = ma_decoder_init_file(path, &cfg, &decoder);
    if (r != MA_SUCCESS) {
        set_err(err, err_size, "无法解码该音频文件（miniaudio）");
        return AUDIO_DECODER_ERR_DECODE;
    }

    ma_uint64 length_frames = 0;
    if (ma_decoder_get_length_in_pcm_frames(&decoder, &length_frames) == MA_SUCCESS &&
        length_frames > 0) {
        *duration_sec_out = (double)length_frames / 16000.0;
    }

    static ma_int16 buf[32768]; // 64 KB of s16 mono samples
    int result = 0;
    size_t total_bytes = 0;
    for (;;) {
        ma_uint64 frames_read = 0;
        r = ma_decoder_read_pcm_frames(&decoder, buf,
                                       (ma_uint64)(sizeof(buf) / sizeof(buf[0])),
                                       &frames_read);
        if (r != MA_SUCCESS) {
            set_err(err, err_size, "音频解码中途失败（miniaudio）");
            result = AUDIO_DECODER_ERR_DECODE;
            break;
        }
        if (frames_read == 0) break;
        size_t bytes = (size_t)frames_read * sizeof(ma_int16);
        if (write_all(out, buf, bytes) != 0) {
            set_err(err, err_size, "写 PCM 临时文件失败");
            result = AUDIO_DECODER_ERR_WRITE;
            break;
        }
        total_bytes += bytes;
    }
    ma_decoder_uninit(&decoder);
    if (result == 0 && *duration_sec_out <= 0.0 && total_bytes > 0) {
        *duration_sec_out = (double)total_bytes / 2.0 / 16000.0;
    }
    return result;
}

// ---------------------------------------------------------------------------
// Apple path — m4a / aac via AudioToolbox ExtAudioFile. The client data
// format is requested as s16 / mono / 16 kHz and ExtAudioFile's internal
// AudioConverter performs decode + mixdown + resampling while read.
// ---------------------------------------------------------------------------
#if defined(__APPLE__)
static int decode_with_audiotoolbox(const char* path, FILE* out,
                                    double* duration_sec_out, char* err,
                                    int err_size) {
    CFStringRef cf_path =
        CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, path);
    if (cf_path == NULL) {
        set_err(err, err_size, "无法打开音频文件");
        return AUDIO_DECODER_ERR_OPEN;
    }
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cf_path,
                                                 kCFURLPOSIXPathStyle, false);
    CFRelease(cf_path);
    if (url == NULL) {
        set_err(err, err_size, "无法打开音频文件");
        return AUDIO_DECODER_ERR_OPEN;
    }

    ExtAudioFileRef file = NULL;
    OSStatus st = ExtAudioFileOpenURL(url, &file);
    CFRelease(url);
    if (st != noErr || file == NULL) {
        set_err(err, err_size, "无法打开音频文件（AudioToolbox）");
        return AUDIO_DECODER_ERR_OPEN;
    }

    AudioStreamBasicDescription client;
    memset(&client, 0, sizeof(client));
    client.mSampleRate = 16000;
    client.mFormatID = kAudioFormatLinearPCM;
    client.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    client.mBitsPerChannel = 16;
    client.mChannelsPerFrame = 1;
    client.mBytesPerFrame = 2;
    client.mFramesPerPacket = 1;
    client.mBytesPerPacket = 2;
    st = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                 sizeof(client), &client);
    if (st != noErr) {
        ExtAudioFileClose(file);
        set_err(err, err_size, "该音频格式不受支持（AudioToolbox 客户端格式设置失败）");
        return AUDIO_DECODER_ERR_UNSUPPORTED;
    }

    const UInt32 buf_frames = 32768;
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = 1;
    abl.mBuffers[0].mDataByteSize = buf_frames * 2;
    abl.mBuffers[0].mData = malloc(buf_frames * 2);
    if (abl.mBuffers[0].mData == NULL) {
        ExtAudioFileClose(file);
        set_err(err, err_size, "内存分配失败");
        return AUDIO_DECODER_ERR_DECODE;
    }

    int result = 0;
    size_t total_bytes = 0;
    for (;;) {
        UInt32 frames = buf_frames;
        st = ExtAudioFileRead(file, &frames, &abl);
        if (st != noErr) {
            set_err(err, err_size, "音频解码中途失败（AudioToolbox）");
            result = AUDIO_DECODER_ERR_DECODE;
            break;
        }
        if (frames == 0) break;
        if (write_all(out, abl.mBuffers[0].mData, (size_t)frames * 2) != 0) {
            set_err(err, err_size, "写 PCM 临时文件失败");
            result = AUDIO_DECODER_ERR_WRITE;
            break;
        }
        total_bytes += (size_t)frames * 2;
    }
    free(abl.mBuffers[0].mData);
    ExtAudioFileClose(file);
    if (result == 0 && total_bytes > 0) {
        *duration_sec_out = (double)total_bytes / 2.0 / 16000.0;
    }
    return result;
}
#endif

// ---------------------------------------------------------------------------
// Windows path — m4a / aac via the Media Foundation Source Reader (system
// AAC decoder, no extra binaries). Output is requested as plain 16-bit PCM
// at the source rate/channels, then streamed through a miniaudio
// ma_data_converter to reach s16 / mono / 16 kHz.
// ---------------------------------------------------------------------------
#if defined(_WIN32)
static int decode_with_mediafoundation(const char* path, FILE* out,
                                       double* duration_sec_out, char* err,
                                       int err_size) {
    int result = 0;
    size_t total_bytes = 0;
    IMFSourceReader* reader = NULL;
    IMFMediaType* out_type = NULL;
    ma_data_converter converter;
    int converter_ready = 0;
    UINT32 src_channels = 1;

    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (wlen <= 0) {
        set_err(err, err_size, "无法打开音频文件");
        return AUDIO_DECODER_ERR_OPEN;
    }
    wchar_t* wpath = (wchar_t*)malloc((size_t)wlen * sizeof(wchar_t));
    if (wpath == NULL) {
        set_err(err, err_size, "内存分配失败");
        return AUDIO_DECODER_ERR_DECODE;
    }
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);

    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(hr)) {
        free(wpath);
        set_err(err, err_size, "Media Foundation 初始化失败");
        return AUDIO_DECODER_ERR_DECODE;
    }

    hr = MFCreateSourceReaderFromURL(wpath, NULL, &reader);
    free(wpath);
    if (FAILED(hr) || reader == NULL) {
        MFShutdown();
        set_err(err, err_size, "无法打开音频文件（Media Foundation）");
        return AUDIO_DECODER_ERR_OPEN;
    }

    // Select only the first audio stream, per the Source Reader docs.
    IMFSourceReader_SetStreamSelection(reader, MF_SOURCE_READER_ALL_STREAMS, FALSE);
    if (FAILED(IMFSourceReader_SetStreamSelection(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE))) {
        set_err(err, err_size, "文件中没有音频流（Media Foundation）");
        result = AUDIO_DECODER_ERR_UNSUPPORTED;
        goto done;
    }

    hr = MFCreateMediaType(&out_type);
    if (FAILED(hr)) {
        set_err(err, err_size, "Media Foundation 类型创建失败");
        result = AUDIO_DECODER_ERR_DECODE;
        goto done;
    }
    IMFMediaType_SetGUID(out_type, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
    IMFMediaType_SetGUID(out_type, &MF_MT_SUBTYPE, &MFAudioFormat_PCM);
    IMFMediaType_SetUINT32(out_type, &MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    // Rate/channels are intentionally NOT pinned: the reader hands back the
    // native layout as 16-bit PCM and the ma_data_converter below normalizes
    // it to s16 / mono / 16 kHz.
    hr = IMFSourceReader_SetCurrentMediaType(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL, out_type);
    if (FAILED(hr)) {
        set_err(err, err_size, "该音频格式不受支持（Media Foundation 解码器不可用）");
        result = AUDIO_DECODER_ERR_UNSUPPORTED;
        goto done;
    }

    {
        IMFMediaType* actual = NULL;
        UINT32 rate = 0;
        if (SUCCEEDED(IMFSourceReader_GetCurrentMediaType(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, &actual)) &&
            actual != NULL) {
            IMFMediaType_GetUINT32(actual, &MF_MT_AUDIO_SAMPLES_PER_SECOND, &rate);
            IMFMediaType_GetUINT32(actual, &MF_MT_AUDIO_NUM_CHANNELS, &src_channels);
            IMFMediaType_Release(actual);
        }
        if (rate == 0) rate = 44100;
        if (src_channels == 0) src_channels = 1;

        ma_data_converter_config ccfg = ma_data_converter_config_init(
            ma_format_s16, ma_format_s16, (ma_uint32)src_channels, 1, (ma_uint32)rate, 16000);
        if (ma_data_converter_init(&ccfg, NULL, &converter) != MA_SUCCESS) {
            set_err(err, err_size, "重采样器初始化失败");
            result = AUDIO_DECODER_ERR_DECODE;
            goto done;
        }
        converter_ready = 1;
    }

    {
        static ma_int16 out_buf[32768];
        for (;;) {
            DWORD flags = 0;
            IMFSample* sample = NULL;
            hr = IMFSourceReader_ReadSample(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, NULL, &flags, NULL, &sample);
            if (FAILED(hr)) {
                set_err(err, err_size, "音频解码中途失败（Media Foundation）");
                result = AUDIO_DECODER_ERR_DECODE;
                break;
            }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
                if (sample != NULL) IMFSample_Release(sample);
                break;
            }
            if (sample == NULL) continue;

            IMFMediaBuffer* buffer = NULL;
            if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &buffer)) && buffer != NULL) {
                DWORD len = 0;
                BYTE* data = NULL;
                if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &data, NULL, &len)) && data != NULL && len > 0) {
                    // s16 frames in the SOURCE channel layout.
                    ma_uint64 in_frames = (ma_uint64)(len / 2 / src_channels);
                    const ma_int16* src = (const ma_int16*)data;
                    while (in_frames > 0 && result == 0) {
                        // miniaudio 0.11: counts are IN/OUT — input receives
                        // the available frames, output the buffer capacity;
                        // on return they hold consumed / produced.
                        ma_uint64 consumed = in_frames;
                        ma_uint64 produced =
                            sizeof(out_buf) / sizeof(out_buf[0]);
                        ma_data_converter_process_pcm_frames(
                            &converter, src, &consumed, out_buf, &produced);
                        if (consumed == 0 && produced == 0) break;
                        src += consumed * src_channels;
                        in_frames -= consumed;
                        if (produced > 0) {
                            if (write_all(out, out_buf, (size_t)produced * 2) != 0) {
                                set_err(err, err_size, "写 PCM 临时文件失败");
                                result = AUDIO_DECODER_ERR_WRITE;
                            }
                            total_bytes += (size_t)produced * 2;
                        }
                    }
                    IMFMediaBuffer_Unlock(buffer);
                }
                IMFMediaBuffer_Release(buffer);
            }
            IMFSample_Release(sample);
            if (result != 0) break;
        }
    }

done:
    if (converter_ready) ma_data_converter_uninit(&converter, NULL);
    if (out_type != NULL) IMFMediaType_Release(out_type);
    if (reader != NULL) IMFSourceReader_Release(reader);
    MFShutdown();
    if (result == 0 && total_bytes > 0) {
        *duration_sec_out = (double)total_bytes / 2.0 / 16000.0;
    }
    return result;
}
#endif

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT int audio_decoder_decode_pcm16k_mono(
    const char* path, const char* out_path, double* duration_sec_out,
    char* err_buffer, int err_buffer_size) {
    if (path == NULL || out_path == NULL) {
        set_err(err_buffer, err_buffer_size, "参数错误");
        return AUDIO_DECODER_ERR_OPEN;
    }
    if (duration_sec_out != NULL) *duration_sec_out = 0.0;

    FILE* out = open_output_file(out_path);
    if (out == NULL) {
        set_err(err_buffer, err_buffer_size, "无法创建 PCM 临时文件");
        return AUDIO_DECODER_ERR_WRITE;
    }

    int result;
    if (extension_is(path, "wav") || extension_is(path, "mp3") ||
        extension_is(path, "ogg") || extension_is(path, "oga") ||
        extension_is(path, "flac")) {
        result = decode_with_miniaudio(path, out, duration_sec_out, err_buffer, err_buffer_size);
    } else if (extension_is(path, "m4a") || extension_is(path, "aac") || extension_is(path, "m4b")) {
#if defined(__APPLE__)
        result = decode_with_audiotoolbox(path, out, duration_sec_out, err_buffer, err_buffer_size);
#elif defined(_WIN32)
        result = decode_with_mediafoundation(path, out, duration_sec_out, err_buffer, err_buffer_size);
#else
        set_err(err_buffer, err_buffer_size, "当前平台不支持解码 m4a/aac");
        result = AUDIO_DECODER_ERR_UNSUPPORTED;
#endif
    } else if (extension_is(path, "opus") || extension_is(path, "webm") || extension_is(path, "amr")) {
        set_err(err_buffer, err_buffer_size,
                "暂不支持该音频格式（opus/webm/amr），请先转换为 mp3/wav/m4a 后再添加");
        result = AUDIO_DECODER_ERR_UNSUPPORTED;
    } else {
        set_err(err_buffer, err_buffer_size,
                "不支持的音频格式，支持：mp3 / wav / m4a / aac / ogg / flac");
        result = AUDIO_DECODER_ERR_UNSUPPORTED;
    }

    fclose(out);
    if (result != 0) remove(out_path);
    return result;
}
