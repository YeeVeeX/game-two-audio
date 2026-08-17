/*
 * gta_shim.c — game-two-audio flat-C surface for ruby-ffi.
 *
 * Why this exists (ADR 0001): the Ruby side binds ONLY flat functions with
 * primitive/opaque-pointer args. No miniaudio struct layout is ever replicated
 * in Ruby (config structs are version-fragile and by-value APIs are hostile to
 * FFI). This file is the thin waist; it is also the future home of the C-side
 * command buffer (the ADR's named escalation path if per-call FFI cost exceeds
 * the 0.5 ms p95 bound).
 *
 * Structural laws honored here:
 *  - No callbacks are ever exposed to Ruby. Poll + schedule-ahead only.
 *  - Determinism preconditions (ADR gate): jobThreadCount = 0 +
 *    MA_RESOURCE_MANAGER_FLAG_NO_THREADING + synchronous full decode at load.
 *    NO_THREADING forces a non-blocking job queue (miniaudio.h L70047), so
 *    loads pump the job queue to completion on the CALLING (game) thread.
 *
 * Compiled into vendor/miniaudio.dll alongside miniaudio_impl.c (see
 * vendor/VERSION for the exact command + hashes).
 */

#include <stdlib.h>
#include <string.h>
#include "miniaudio.h"

#define GTA_API __declspec(dllexport)

typedef struct
{
    ma_resource_manager resourceManager;
    ma_engine engine;
} gta_engine;

static ma_result gta_lastResult = MA_SUCCESS;

GTA_API int gta_last_result(void)
{
    return (int)gta_lastResult;
}

GTA_API const char* gta_version(void)
{
    return ma_version_string();
}

/*
 * useDevice = 0: deterministic offline engine (noDevice; caller drives the
 *                clock via gta_engine_read_f32). The ADR ship-gate mode.
 * useDevice = 1: real default playback device (spike 02 / runtime mode).
 *
 * Both modes share identical resource-manager constraints so the load path
 * behaves the same everywhere: zero job threads, NO_THREADING, decode to
 * f32/channels/sampleRate at load time. The device thread (mode 1) only ever
 * mixes preloaded buffers — it never touches Ruby.
 */
GTA_API gta_engine* gta_engine_create(int useDevice, ma_uint32 channels, ma_uint32 sampleRate)
{
    gta_engine* e;
    ma_resource_manager_config rmConfig;
    ma_engine_config engineConfig;
    ma_result result;

    e = (gta_engine*)calloc(1, sizeof(gta_engine));
    if (e == NULL) {
        gta_lastResult = MA_OUT_OF_MEMORY;
        return NULL;
    }

    rmConfig = ma_resource_manager_config_init();
    rmConfig.jobThreadCount    = 0;
    rmConfig.flags             = MA_RESOURCE_MANAGER_FLAG_NO_THREADING; /* implies NON_BLOCKING job queue */
    rmConfig.decodedFormat     = ma_format_f32;
    rmConfig.decodedChannels   = channels;
    rmConfig.decodedSampleRate = sampleRate;

    result = ma_resource_manager_init(&rmConfig, &e->resourceManager);
    if (result != MA_SUCCESS) {
        gta_lastResult = result;
        free(e);
        return NULL;
    }

    engineConfig = ma_engine_config_init();
    engineConfig.pResourceManager = &e->resourceManager;
    engineConfig.channels         = channels;
    engineConfig.sampleRate       = sampleRate;
    engineConfig.noDevice         = useDevice ? MA_FALSE : MA_TRUE;

    result = ma_engine_init(&engineConfig, &e->engine);
    if (result != MA_SUCCESS) {
        gta_lastResult = result;
        ma_resource_manager_uninit(&e->resourceManager);
        free(e);
        return NULL;
    }

    gta_lastResult = MA_SUCCESS;
    return e;
}

GTA_API void gta_engine_destroy(gta_engine* e)
{
    if (e == NULL) {
        return;
    }
    ma_engine_uninit(&e->engine);
    ma_resource_manager_uninit(&e->resourceManager);
    free(e);
}

GTA_API int gta_engine_read_f32(gta_engine* e, float* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead)
{
    return (int)ma_engine_read_pcm_frames(&e->engine, pFramesOut, frameCount, pFramesRead);
}

GTA_API ma_uint64 gta_engine_time_pcm(gta_engine* e)
{
    return ma_engine_get_time_in_pcm_frames(&e->engine);
}

GTA_API ma_uint32 gta_engine_sample_rate(gta_engine* e)
{
    return ma_engine_get_sample_rate(&e->engine);
}

GTA_API ma_uint32 gta_engine_channels(gta_engine* e)
{
    return ma_engine_get_channels(&e->engine);
}

/*
 * Synchronous full-decode load (MA_SOUND_FLAG_DECODE, no ASYNC), then pump the
 * (non-blocking) job queue dry on this thread. Spatializer and pitch shifter
 * are disabled: 2D pan/volume via ma_sound_set_pan/ma_sound_set_volume only.
 */
GTA_API ma_sound* gta_sound_create(gta_engine* e, const char* pFilePath)
{
    ma_sound* s;
    ma_result result;

    s = (ma_sound*)calloc(1, sizeof(ma_sound));
    if (s == NULL) {
        gta_lastResult = MA_OUT_OF_MEMORY;
        return NULL;
    }

    result = ma_sound_init_from_file(&e->engine, pFilePath,
                                     MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
                                     NULL, NULL, s);
    if (result != MA_SUCCESS) {
        gta_lastResult = result;
        free(s);
        return NULL;
    }

    /* Drain any pending jobs on the calling thread (NON_BLOCKING queue). */
    while (ma_resource_manager_process_next_job(&e->resourceManager) == MA_SUCCESS) { }

    gta_lastResult = MA_SUCCESS;
    return s;
}

GTA_API void gta_sound_destroy(ma_sound* s)
{
    if (s == NULL) {
        return;
    }
    ma_sound_uninit(s);
    free(s);
}

GTA_API int gta_sound_start(ma_sound* s)                  { return (int)ma_sound_start(s); }
GTA_API int gta_sound_stop(ma_sound* s)                   { return (int)ma_sound_stop(s); }
GTA_API void gta_sound_set_volume(ma_sound* s, float v)   { ma_sound_set_volume(s, v); }
GTA_API void gta_sound_set_pan(ma_sound* s, float pan)    { ma_sound_set_pan(s, pan); }
GTA_API void gta_sound_set_looping(ma_sound* s, int loop) { ma_sound_set_looping(s, loop ? MA_TRUE : MA_FALSE); }
GTA_API int gta_sound_at_end(ma_sound* s)                 { return ma_sound_at_end(s) ? 1 : 0; }
GTA_API int gta_sound_is_playing(ma_sound* s)             { return ma_sound_is_playing(s) ? 1 : 0; }
GTA_API int gta_sound_seek_pcm(ma_sound* s, ma_uint64 f)  { return (int)ma_sound_seek_to_pcm_frame(s, f); }

/* Schedule-ahead surface (absolute engine-clock frames). ADR structural law 3. */
GTA_API void gta_sound_set_start_time_pcm(ma_sound* s, ma_uint64 t) { ma_sound_set_start_time_in_pcm_frames(s, t); }
GTA_API void gta_sound_set_stop_time_pcm(ma_sound* s, ma_uint64 t)  { ma_sound_set_stop_time_in_pcm_frames(s, t); }

GTA_API void gta_sound_set_stop_time_with_fade_pcm(ma_sound* s, ma_uint64 stopTime, ma_uint64 fadeLen)
{
    ma_sound_set_stop_time_with_fade_in_pcm_frames(s, stopTime, fadeLen);
}

/* Fade starting now (relative). */
GTA_API void gta_sound_set_fade_pcm(ma_sound* s, float volBeg, float volEnd, ma_uint64 lenFrames)
{
    ma_sound_set_fade_in_pcm_frames(s, volBeg, volEnd, lenFrames);
}

/* Fade starting at an absolute engine-clock frame (quantized transitions). */
GTA_API void gta_sound_set_fade_start_pcm(ma_sound* s, float volBeg, float volEnd, ma_uint64 lenFrames, ma_uint64 absStartFrame)
{
    ma_sound_set_fade_start_in_pcm_frames(s, volBeg, volEnd, lenFrames, absStartFrame);
}
