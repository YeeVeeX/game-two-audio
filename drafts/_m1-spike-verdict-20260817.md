# M1 spike verdict — ADR 0001 falsification list (2026-08-17)

Executor: dev of record. Environment: Windows 11, Ruby 3.4.10 x64-mingw-ucrt (+PRISM,
no YJIT), miniaudio **0.11.25** pinned (vendor/VERSION, dll sha256 `720d8b8a…07cd`),
gcc 16.1.0 UCRT64 (RubyInstaller devkit). Runner: `bundle exec rake spike` — all five
scripts exit 0 in one run; every measurement below is pasted from live output.

**Verdict: 5/5 PASS → ADR 0001 flips to ACCEPTED.** No fallback-ladder reopen.

Design note (in-plan, documented for the record): the FFI surface is a flat C shim
(`vendor/gta_shim.c`, `gta_*` exports compiled into the pinned DLL) rather than
Ruby-side struct replication — miniaudio's by-value config structs are version-fragile
and a one-byte layout drift would silently corrupt every measurement here. Ruby binds
only opaque pointers + primitives (`src/gta/native.rb`). The shim is also the ADR's
named escalation home (C-side command buffer) — not needed, see item 3 margins.

## Item 1 — offline render determinism: PASS

`spike/01_offline_render_determinism.rb`. Preconditions held (none relaxed):
`jobThreadCount=0` + `MA_RESOURCE_MANAGER_FLAG_NO_THREADING` + full synchronous decode
(`MA_SOUND_FLAG_DECODE`, no ASYNC) + job queue drained on the calling thread at load.
Program: 3 tones, schedule-ahead starts (frames 0/12k/24k), pan/volume, fade-in via
`fade_start`, stop-with-fade; 144_000 frames rendered in fixed 512-frame chunks;
fresh engine per render.

```
render A: 1152000 bytes  sha256=51d9020db2c8433a6cea67465649bfe115375f839ee9e8d5e3a4118d09676292
render B: 1152000 bytes  sha256=51d9020db2c8433a6cea67465649bfe115375f839ee9e8d5e3a4118d09676292
rms early=0.2088 mid=0.28628 tail=0.0
```

Byte-identical in-process AND across three separate process runs (same sha256 every
run). Non-silence guarded (rms windows) so an all-zero false pass is impossible; tail
after all stops is exact float zero. Artifacts: `tmp/spike01_render_{a,b}.wav`, both
sha256 `006054bda19933538edee42f6b31593ce798b23a85e8a214842b74a634d77291`.

## Item 2 — Gosu bypass via SDL_AUDIODRIVER=dummy: PASS

`spike/02_gosu_bypass.rb`, three child processes (gosu 1.4.6, real window, real
device; driver asserted DIRECTLY via `SDL_GetCurrentAudioDriver()` FFI against the
gosu gem's own SDL2.dll — not inferred from silence):

```
[control]      sdl_driver=wasapi  sample_playing=1          (no override: real driver — dummy is meaningful)
[entry]        sdl_driver=dummy   window_updates=60 window_draws=60
               ma_engine=ok ma_time_delta=58080 ma_at_end=1 (miniaudio owned WASAPI, tone completed)
[post_require] sdl_driver=dummy   sample_playing=1
```

Entry scenario = the ADR claim: Gosu boots + renders 60 frames with SDL audio on the
dummy backend while miniaudio's real-device engine clock advances 58_080 frames and
plays a tone to completion in the same process. `Gosu::Sample#play` under dummy does
not crash.

**Timing verdict (knowledge-repo correction candidate):** `SDL_AUDIODRIVER=dummy` is
honored even when set AFTER `require "gosu"` but before the first SDL audio init —
SDL reads the hint at audio-subsystem init, not at library load. Process-entry
placement stays the shipped policy (simplest safe point); the constraint is
"before first audio init", which is what the evidence note should say.

## Item 3 — worst-case 64-voice command batch: PASS

`spike/03_command_batch_cost.rb`. 64 looping voices; every tick, every voice:
volume + pan + fade + alternating schedule-ahead (start-time / stop-with-fade) +
start re-arm = **320 FFI calls/tick**; 1000 measured ticks after 100 warmup, engine
advanced 800 frames/tick between batches (untimed — that work is the device thread's
in production).

```
batch ms: p50=0.0313 p95=0.0355 p99=0.0552 max=0.2536   (rake-spike rerun: p95=0.0333)
GC (uninstrumented passes): delta@1000=1 delta@5000=0 gc_runs=2
```

p95 ≈ 0.033-0.036 ms — **14x inside the 0.5 ms ADR bound**; the C-side command-buffer
escalation stays unbuilt. Allocation proof is scaling-based because the profiler
itself allocates (probed: `Process.clock_gettime(:nanosecond)` ≈ 1 object/call on
this build; even an empty `while` loop shows ~1 object of GC.stat harness noise):
an uninstrumented 5000-tick pass (1.6M FFI calls) allocated **0 objects** vs 1 at
1000 ticks → per-tick allocations = 0. Fixture LUTs + FFI buffers preallocated;
flonum arithmetic only.

## Item 4 — voice pool steal, assertable in the WAV: PASS

`spike/04_voice_pool_steal.rb` + `src/gta/voice_pool.rb` (pure-policy pool;
max_voices=64 + steal chain `lowest_priority → furthest → oldest` read from
`data/audio/cues.json`; chain unit-tested in `test/voice_pool_test.rb`). Scenario:
64 voices fill the pool (victim = slot 7, 500 Hz, unique lowest priority 10); at
exactly engine frame 48_000 a priority-90 cue (1500 Hz) acquires → pool steals slot 7.

```
goertzel amp   500 Hz: before=0.42 after=3.1e-05    (13557:1 collapse)
goertzel amp  1500 Hz: before=3.4e-05 after=0.6
goertzel amp  2300 Hz: before=0.24 after=0.24       (bystander intact)
concurrent voices: before=64 after=64 (max 64)
```

Steal decision correct (slot 7, victim priority 10), audible and localized in the
render at the steal frame, concurrency never exceeded the pool. Artifact:
`tmp/spike04_steal.wav` sha256 `dd49775c6c0281079be4fd3aa62ee564c0e06d84d649de06001fd4da75cbed05`.

## Item 5 — schedule-ahead quantized transition: PASS

`spike/05_quantized_transition.rb`. Timing from `data/audio/music.json` (120 bpm 4/4
→ bar = 96_000 frames; crossfade 9_600). Transition at bar 2 (frame 192_000) fully
scheduled ONE BAR EARLY via absolute-clock calls (`set_fade_start_pcm`,
`set_start_time_pcm`, `set_stop_time_pcm`); no later adjustment. Stems hard-panned
(balance mode, zero bleed verified at float 0.0); per-frame fade gain extracted by
dividing the transition render by unfaded reference renders (legal because item 1
holds), then least-squares line fit:

```
stem_b first nonzero frame: 192001 (boundary 192000)          → +1, gain(frame 0)=0
fade-out fit: slope=-0.0001041667 (expect -0.0001041667) midpoint=196800.0
fade-in  fit: slope= 0.0001041667 (expect  0.0001041667) midpoint=196800.0
offsets: out=0.0 frames, in=0.0 frames                        (bound: ±1)
post-transition: stem_a rms=0.0  stem_b amp=0.5
```

Fitted midpoints land at **exactly** 196_800.0 (offset 0.0 frames, sub-frame fit
precision); fade slopes match 1/9600 to 10 decimal places. Artifact:
`tmp/spike05_transition.wav` sha256 `bb2336e7154f4f8780f7c074637f04f76468cd92cfafdbf947979605f70a2a08`.

## Pinned facts discovered during the spike (already encoded in code/tests)

1. **Empty node graph reads 0 frames** — `ma_engine_read_pcm_frames` on a graph with
   no attached sounds returns success with framesRead=0 and does not advance the
   clock. Render loops must attach sounds first; encoded in `test/native_smoke_test.rb`
   and guarded in `Spike.render_f32`.
2. **NO_THREADING forces a NON_BLOCKING job queue** (miniaudio.h L70047) — sync loads
   must drain `ma_resource_manager_process_next_job` on the calling thread;
   done inside `gta_sound_create`.
3. `ma_sound_set_stop_time_with_fade_in_pcm_frames(stop, len)` fades over
   `[stop-len, stop]` (header L79324) — fade precedes the stop time.
4. `Process.clock_gettime(:nanosecond)` allocates ~1 Ruby object/call on
   x64-mingw-ucrt — keep it out of allocation-asserted regions.

## Knowledge-repo correction queue (for a later knowledge session — NOT written now)

- `game-research/ruby-gosu-audio-engine-selection.md`: SDL_AUDIODRIVER timing —
  hint read at first SDL audio init, not process/library load (spike 02
  post_require scenario, gosu 1.4.6 / its bundled SDL2.dll, 2026-08-17).
  Process-entry remains the recommended placement.
- Same note: miniaudio 0.11.25 empty-graph read semantics (fact 1 above) worth a
  line in the offline-render section.

## Consequence

ADR 0001 → **ACCEPTED** (v2 semantics unchanged; the falsification list is now the
regression floor for the M2 gate harness). Current cycle advances to M2: AudioSystem
event-sink + replay→render→assert gate harness.
