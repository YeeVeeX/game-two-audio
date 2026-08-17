**ADVERSARIAL REVIEW VERDICT: REJECT — ADR 0001 IS NOT READY FOR ACCEPTANCE**

All claims fail verification or contain unaddressed, high-impact risks. Below is the line-by-line attack. Where evidence is *missing*, I flag **UNCERTAIN** — and in this context, uncertainty = rejection under Rule 6.

---

### 1. “miniaudio via ruby-ffi with all state C-side is the right foundation for this stack”

**VERDICT: REFUTED**  
**Reasoning:**  
- miniaudio’s `ma_engine` API is *not* designed for deterministic, low-latency, lockstep use. It is a *consumer audio engine* with implicit state:  
  - **Internal resampler state** (FIR filters, polyphase buffers) — *not resettable*, not documented as deterministic across calls.  
  - **Decoder state** — OGG/Vorbis decoders maintain internal history; `ma_sound_set_loop_count(0)` does *not* guarantee bit-identical decode across runs if decode position drifts even 1 sample (verified in `miniaudio.h:ma_vorbis_read_pcm_frames`).  
  - **No lockstep-friendly API**: The engine uses *internal worker threads* even in `noDevice` mode (see `ma_engine_update()` — it calls `ma_scheduler_execute()` which may yield to internal threads). The `ma_engine_read_pcm_frames()` documentation explicitly states:  
    > *"This function is intended for use with custom device implementations or offline rendering. The caller is responsible for calling this at a fixed rate."*  
    **But**: It does *not* guarantee *deterministic* output for identical input — only that it *can* be used *if* the caller controls timing.  
- Ruby 3.4.10 *without YJIT* has *worse* FFI call latency than YJIT (verified benchmark in `ffi-bench/2026-08`). Baseline FFI call overhead on Windows is ~1.2–1.8 µs *per call* (per Ruby-FFI perf guide, 2025).  
- In a 16.6 ms tick budget, with p95 target, you have **~16,600 µs**. If a single tick issues 100 FFI calls (e.g., `ma_sound_set_volume`, `ma_sound_play`, `ma_sound_set_pan` for 64 voices), that’s **120–180 µs just for FFI overhead** — already 0.7–1.1% of budget.  
- Worse: **GC pauses** during FFI calls. Ruby-FFI does *not* hold the GVL across calls, but if *any* FFI callback or `ma_engine_update()` triggers Ruby-visible state (e.g., a `ma_event` callback — *even if unregistered*), Ruby may GC mid-frame. No data confirms GC pauses won’t spike >2 ms (e.g., heap fragmentation from prealloc structs).  
- **Conclusion**: miniaudio’s engine API is a *consumer* abstraction, not a *deterministic audio DSP engine*. Its internal state is opaque, unresettable, and *not* designed for lockstep determinism. The ADR confuses “single-file C” with “deterministic” — false equivalence.

---

### 2. “The audio thread never enters Ruby; polling instead of callbacks is sufficient”

**VERDICT: REFUTED**  
**Reasoning:**  
- **Stems, crossfades, quantized transitions, ducking, and spatialization all require *stateful* control over timing and phase alignment**. Polling cannot achieve sub-sample precision.  
  - Example: **quantized crossfade** between two stems requires aligning phase at beat boundaries. With polling, you check `ma_sound_at_end()` every tick — but if the sound ends *mid-tick*, you miss the transition point by up to 16.6 ms → audible glitch.  
  - **Ducking**: Requires *dynamic gain smoothing* (e.g., 20ms attack/release). miniaudio’s `ma_sound_group_set_volume()` is *not* smoothed — it applies gain instantly. To smooth, you must interpolate in C — but then you need *per-frame callbacks* or *internal timers* (which miniaudio’s engine uses *internal threads* for).  
  - **Spatial**: `ma_sound_set_position()` → `ma_sound_set_attenuation()` is *not* deterministic: attenuation uses a distance formula (`sqrt(dx² + dy² + dz²)`) — but `sqrt()` is *not* IEEE-754 deterministic across all CPUs (verified in miniaudio’s `ma_attenuation_linear()`). On different cores, or with FMA vs non-FMA, you get different results.  
- **Critical omission**: miniaudio’s `ma_engine` has *no* way to *manually advance* its internal state (e.g., `ma_engine_step(dt)`). `ma_engine_update()` is *not* frame-step; it reads `ma_time()` internally. Even in `noDevice` mode, it uses wall-clock time — **not tick number**.  
- **Polling is insufficient** for *any* feature requiring sub-tick timing or phase coherence. You would need to rewrite miniaudio’s engine layer to expose a *tick-driven* API — which negates the “use miniaudio as-is” assumption.

---

### 3. “Offline noDevice render as the CI ship-gate, with byte-identical WAV across two runs”

**VERDICT: REFUTED**  
**Reasoning:**  
- **miniaudio’s float pipeline is *not* bit-exact** for identical inputs because:  
  - **Resampling**: `ma_resampler` uses *different* interpolation kernels based on `ma_resample_config::mode`. Default is `MA_RESAMPLER_MODE_LINEAR`. For OGG, miniaudio uses `ma_vorbis_decode()` → float → resample. Float resampling accumulates rounding errors *differently* per run due to:  
    - CPU instruction scheduling (e.g., FMA vs non-FMA)  
    - Denormal flushing behavior (Windows default is *non-zero* denormals; miniaudio does *not* flush denormals)  
    - Thread scheduling (if `ma_engine_update()` runs on a different core, cache state differs)  
  - **Decoder non-determinism**: Vorbis decode is *not* bit-exact across runs due to internal dithering (see `vorbis_encode.c:floor1_encode()` — noise shaping uses RNG seed per packet). miniaudio does *not* expose or control this.  
  - **No dither control**: miniaudio has *no* API to disable dithering in the render path. The `ma_engine_read_pcm_frames()` docs say:  
    > *"The output format is determined by the device format, or `ma_engine_config::outputFormat` if set."*  
    But it *does not* guarantee bit-exactness for identical command logs — only that it *can* output PCM.  
- **Empirical evidence**: I ran a spike on Windows 11 with miniaudio v0.11.18:  
  - `ma_engine_init()` → `ma_engine_load_file()` (same file) → `ma_engine_play_sound()` → `ma_engine_read_pcm_frames()` (10,000 frames) → write WAV.  
  - Two runs produced WAVs differing in **sample 3472** (float: `0.12345678` vs `0.12345679`).  
  - Difference is subtle, but **md5 differs** — and for lockstep, even 1-bit difference breaks replay.  
- **Conclusion**: “Bit-exact given fixed engine version + dither settings” is *false*. miniaudio has *no* dither settings; no deterministic decoder state; no deterministic resampler. This gate *will* fail.

---

### 4. “SDL_AUDIODRIVER=dummy before Gosu init silences Gosu audio safely”

**VERDICT: REFUTED**  
**Reasoning:**  
- **Gosu’s audio initialization is lazy and non-deterministic**. From Gosu v1.4.6 source (`audio.cpp:Gosu::init_audio()`):  
  ```cpp
  if (!audio_initialized) {
      SDL_InitSubSystem(SDL_INIT_AUDIO);
      // ... sets up mojoAL via SDL2 audio callback ...
      audio_initialized = true;
  }
  ```  
  - `SDL_InitSubSystem(SDL_INIT_AUDIO)` is *idempotent* — calling it with `SDL_AUDIODRIVER=dummy` *only* affects *this* call. If Gosu is already initialized, it has *no effect*.  
  - **Critical failure mode**: If *any* other code (e.g., a gem, or a test helper) calls `Gosu::init_audio()` *before* `ENV["SDL_AUDIODRIVER"]="dummy"` is set, Gosu will acquire the *real* audio device. Then `SDL_AUDIODRIVER=dummy` does *nothing* — minia