# ADR 0001 — Audio foundation: miniaudio engine API bridged via ruby-ffi

- Status: **ACCEPTED** — 2026-08-17, all five spike falsification items passed
  (`drafts/_m1-spike-verdict-20260817.md`; measurements + artifact hashes therein).
  v2 council reconciliation: `drafts/_council-reconciliation-adr1.md`.
- Date: 2026-08-17 (v2 same day, post-council)
- Deciders: dev of record (this project), owner (veto)
- Evidence base: `knowledge/sources/gosu-audio-architecture-2026-08/` (pass-1 verified
  2026-08-17) + vault notes `game-research/ruby-gosu-audio-engine-selection.md`,
  `game-research/game-audio-architecture-2d-deterministic.md`

## Context

game-two (Ruby 3.4.10 no-YJIT, Gosu 1.4.6 source-compiled x64-mingw-ucrt, Windows 11,
tick-locked deterministic lockstep coop, md5-compared replays, p95 tick < 16.6 ms) needs
audio beyond `Gosu::Sample/Song`: voice pooling with steal policies, bus graph
(master/music/sfx/ui) with ducking + dynamic LPF, 2D pan/attenuation, music state machine
(crossfades, stems), music streaming. Audio is owner-ordered OUT of the game-two repo;
this sibling project develops the system to integration-readiness (lore-project pattern).

Gosu 1.4.6's audio ceiling is verified: mojoAL over SDL2 audio + bundled SDL_sound
decoders; `Sample→Channel` (volume/speed/pan) + one `Song`; no buses, no DSP, no offline
render, no callback hooks. It cannot host the target features.

## Decision

1. **Engine: miniaudio (high-level engine API), bridged via ruby-ffi, all state C-side.**
   - Verified: single C file; engine layer (`ma_engine`, `ma_sound`, `ma_sound_group`,
     `ma_node_graph`, spatializer, filters); **first-class device-less operation**
     (`engineConfig.noDevice = MA_TRUE` + `ma_engine_read_pcm_frames()`) — the CI gate is
     a documented mode, not a hack; license dual Unlicense/MIT-0 (zero obligations).
   - We own a thin FFI layer (no maintained gem exists — verified gem-graveyard finding).
2. **Gosu audio is bypassed entirely; miniaudio owns the (single) audio device.**
   - WASAPI shared mode makes coexistence safe (verified), but single-owner is the clean
     architecture. `ENV["SDL_AUDIODRIVER"]="dummy"` before Gosu init silences Gosu's stack
     — **spike must validate the timing** (hint read at SDL audio init; Gosu inits lazily).
3. **Structural law: the audio thread never enters Ruby.** Verified ffi callback semantics
   (foreign-thread callback = new Ruby thread per invocation) make callbacks structurally
   unusable; the Ruby↔C surface is exclusively game-thread FFI calls. No Ruby procs
   registered as callbacks, ever. Timing-sensitive control is **poll + schedule-ahead**,
   not callbacks: the game thread computes target positions in PCM frames and schedules
   transitions via `ma_sound_set_start_time_in_pcm_frames` / `set_stop_time_in_pcm_frames`
   and `ma_sound_set_fade_in_pcm_frames(volumeBeg, volumeEnd, length)` against
   `ma_engine_get_time_in_pcm_frames` (all verified in miniaudio.h) — sample-accurate
   quantized stem transitions, crossfades, and smoothed ducking without a single callback.
   End-of-sound is polled (`ma_sound_at_end`).
4. **AudioSystem is a pure event-bus sink** (game-two `EventBus::EVENTS` pattern): sim
   events → data-driven cue tables (`data/audio/*.json`) → FFI commands. No audio state in
   sim state, saves, or netplay handshake; audio derives fully from (event stream, tick).
5. **Ship-gate (Rule 2 analog): deterministic offline render, same-machine.** Replay
   script → event stream → audio commands → `noDevice` render → WAV artifact. Two gate
   layers:
   - **Same-machine determinism**: double render, byte-compare (exactly game-two's md5
     frame-gate discipline). Preconditions, spike-proven: `jobThreadCount = 0` +
     `MA_RESOURCE_MANAGER_FLAG_NO_THREADING` + full synchronous decode at load — mixing
     then runs single-threaded on the caller thread inside `ma_engine_read_pcm_frames`
     (config points verified in miniaudio.h). Cross-machine bit-exactness is explicitly
     OUT of scope (FMA/denormal variance across CPUs).
   - **Portable feature assertions**: per-window RMS envelope, cue presence/timing,
     silence floors — plus critic listen for presentation (accuracy and presentation
     scored separately, Rule 2).
   The audio COMMAND LOG is also emitted per replay and md5-compared — bit-exact by
   construction, machine-independent.
6. **Packaging: vendored DLL, pinned and hashed.** `vendor/miniaudio.dll` built once via
   MSYS2 (`gcc -shared -O2`, PINNED miniaudio release whose amalgamation source is
   committed alongside), sha256 recorded in `vendor/VERSION`, rebuild documented in
   `rake dll`; loaded by absolute path (`ffi_lib File.expand_path`). One binary for both
   machines (a plain-C ABI DLL built once runs on both; per-machine rebuilds would
   reintroduce drift). Collaborator machines need only `bundle install`.

## Alternatives rejected

- **FMOD Core**: best feature depth, but ALL license terms unverified at decision time
  (fmod.com JS-walled; fast-decay), registration + attribution + commercial-DLL friction
  for a two-machine hobby git repo. Re-enters only after a first-party license re-read.
- **SoLoud**: viable fallback (zlib verified, buses/filters/C-API); weaker maintenance
  cadence than miniaudio; fewer first-party offline-render guarantees.
- **OpenAL Soft**: LGPL v2.0 + no decoder/streaming layer (would rebuild SDL_sound on top).
- **SDL_mixer / Gosu-native / Wwise / BASS / PortAudio**: feature ceiling, licensing, or
  wrong-layer (device I/O without mixer) — see evidence note.

## Consequences

- We own ~200-400 lines of FFI bindings + the C DLL build recipe (accepted: zero-license
  single-file C is the cheapest ownership on offer).
- FFI per-call overhead is real but bounded: worst-case tick command batch (64 voices)
  must measure < 0.5 ms p95 in the spike; the NAMED escalation path if exceeded is a
  C-side command buffer flushed in one FFI call per tick — not built up front.
- Ruby GC pressure is bounded by design (opaque handles, preallocated command structs,
  cue tables parsed at LOAD time only, zero-allocation target on the per-event path);
  `GC.stat` watched in the perf harness. Residual lockstep risk: a GC stall on one peer
  slows that tick — game-two's tick-locked loop slows visibly rather than desyncing, so
  the failure mode is observable, not silent.
- miniaudio version pins in `vendor/VERSION`; upgrades re-run the full gate suite.
- If the spike falsifies a load-bearing assumption (offline render determinism,
  `SDL_AUDIODRIVER` timing, p95 command cost), the ADR reopens at the fallback ladder
  (SoLoud → FMOD-after-license-read), not at a blank page.

## Spike falsification list (passed 2026-08-17 — now the regression floor for the gate harness)

1. init → load ogg/wav (full decode, `jobThreadCount=0`, `NO_THREADING`) → play →
   `noDevice` offline render → WAV out, twice, **byte-identical on the same machine**.
2. Gosu window + `SDL_AUDIODRIVER=dummy` set at process entry (before `require "gosu"`,
   before any audio init): Gosu boots silent, miniaudio owns the device, game renders
   normally.
3. Worst-case tick command batch (64 voices: starts/stops/pans/volumes/fades): p95
   < 0.5 ms, `GC.stat` allocation delta ~0 on the steady-state path.
4. Voice pool: 64 concurrent + steal policy audible + assertable in the rendered WAV.
5. Quantized transition: schedule-ahead stem swap lands on the computed PCM frame
   (verify by rendering and locating the fade midpoint within ±1 frame).
