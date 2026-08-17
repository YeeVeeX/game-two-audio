# Council reconciliation — ADR 0001 round 1 (2026-08-17)

Consults: deepseek (v3.2), qwen-coder (qwen3-coder-next); briefs + raw JSON in this dir.
Budget: 2 consults, 2000 out-tokens each (actual spend logged by `council budget`).
Adjudication method: every REFUTED verdict re-verified against the local primary
(`knowledge/.scratch/gosu-audio-research-2026-08/verify/miniaudio.h`, 4.1MB master fetch).

## Findings ADOPTED into ADR v2

1. **Bit-exact WAV across arbitrary conditions was over-claimed** (both models REFUTED).
   Resolution: gate = SAME-MACHINE double-render byte-compare (mirrors game-two's md5
   frame-gate discipline, which is also same-machine) + portable feature-level assertions
   (per-window RMS envelope, cue presence/timing, silence floors). Determinism
   preconditions made explicit and spike-proven: `jobThreadCount = 0` +
   `MA_RESOURCE_MANAGER_FLAG_NO_THREADING` (verified present, miniaudio.h L1617/L10376/
   L10515) + full synchronous decode at load → mixing runs single-threaded on the caller
   thread inside `ma_engine_read_pcm_frames`. Cross-machine bit-exactness explicitly OUT
   of scope (FMA/denormal variance).
2. **"Poll-only" was under-specified for music timing** (deepseek REFUTED with the right
   mechanism). Resolution: poll + SCHEDULE-AHEAD. Verified APIs:
   `ma_sound_set_start_time_in_pcm_frames` / `set_stop_time` (engine-clock scheduling,
   documented with examples), `ma_sound_set_fade_in_pcm_frames(volumeBeg, volumeEnd,
   length)` (crossfades + smoothed ducking), `ma_engine_get_time_in_pcm_frames`,
   `ma_sound_at_end`. Game thread computes the quantization boundary in PCM frames and
   schedules the transition AT that frame — sample-accurate, zero callbacks.
3. **FFI per-call overhead needs a measured bound, not a shrug** (deepseek UNCERTAIN).
   Resolution: spike target pinned — full worst-case tick command batch (64 voices) must
   cost < 0.5 ms p95; C-side command-buffer (one FFI flush per tick) is the NAMED
   escalation path if exceeded, not built up front.
4. **GC covert channel in lockstep** (deepseek UNCERTAIN, legit): cue tables parse at
   load only; zero-per-event-allocation target; slow-peer-stall risk documented (game-two
   already slows rather than skips under load, so the failure mode is visible, not silent).
5. **Vendored-DLL reproducibility concern** (deepseek REFUTED the plan): concern adopted
   via pinned miniaudio release + committed amalgamation source + recorded sha256 +
   documented `rake dll` rebuild. His fix (compile at `bundle install`) REJECTED: two
   machines producing different binaries is worse for comparability; a plain-C ABI DLL
   built once runs on both.

## Council claims REFUTED by primary evidence

- qwen: `ma_engine_update()` / `ma_scheduler_execute()` — **do not exist** (0 greps in
  miniaudio.h). The "engine reads wall-clock internally, no manual advance" argument
  built on them is void: in noDevice mode the caller IS the clock (`ma_engine_read_pcm_frames`).
- qwen: "Empirical evidence: I ran a spike on Windows 11 with miniaudio v0.11.18... WAVs
  differing in sample 3472" — **fabricated** (a consult cannot run spikes; treat all its
  specific numbers as synthetic). Lesson re-confirmed: council REASONING is valuable,
  council EVIDENCE must be independently verified.
- qwen: Vorbis decode nondeterminism via "floor1_encode noise-shaping RNG" — that is the
  ENCODER path; stb_vorbis DECODE of a fixed file is deterministic. Claim rejected.
- qwen: Gosu `audio.cpp:Gosu::init_audio()` quoted code — file is `Audio.cpp` and the
  snippet is not in the v1.4.6 tree as quoted; the underlying timing concern (env var must
  precede first audio init) was already an ADR spike item and deepseek CONFIRMED the
  pattern. Split resolved: pattern stands, timing validated in spike at process entry.

## Verdict

ADR revised to v2 (same decision, corrected gate semantics + music-timing mechanism +
packaging pins + measured FFI bound). Blocking findings: none remaining. Spike list is
the falsification instrument; failure reopens at the fallback ladder (SoLoud → FMOD after
first-party license re-read).
