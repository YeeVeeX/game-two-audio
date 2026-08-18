# M2 gate verdict — AudioSystem event sink + deterministic gate harness (2026-08-18)

Executor: dev of record. Environment: Windows 11, Ruby 3.4.10 x64-mingw-ucrt (no
YJIT), miniaudio **0.11.25** pinned (rebuilt this cycle — see below), gcc 16.1.0
UCRT64. Every number below is pasted from live output. Suites: `bundle exec rake`
(34 runs / 167 assertions), `rake spike` (M1 floor, 5/5), `rake gate` (2/2 replays).

**Verdict: M2 scope complete.** Both scripted replays run end-to-end through the
full gate: replay → command log (md5, bit-exact) → noDevice render → WAV artifact →
double-render byte-compare → feature assertions. The M1 spike floor did not move
(spike 01 render sha256 `51d9020db2c8433a…` unchanged pre/post everything).

## DLL rebuild (the one deliberate rebuild, vendor law honored)

Bus-graph shim surface added to `vendor/gta_shim.c`: `gta_group_create/destroy/
set_volume/get_volume`, `gta_group_set_fade_pcm`, `gta_group_set_fade_start_pcm`,
`gta_sound_create_in_group` — 30 `gta_*` exports total. Every symbol verified
against the pinned header FIRST (fabrication precedent respected):

- `ma_sound_group` **is** `typedef ma_sound` (miniaudio.h L11274); every
  `ma_sound_group_*` fn delegates to the `ma_sound_*` fn on the same pointer
  (L79839+). No `ma_sound_group_set_fade_start_in_pcm_frames` exists in 0.11.25 —
  the shim's absolute-start group fade performs the same delegation miniaudio
  itself uses (documented in the shim with line refs).
- Groups are **started by default** (L77064); sounds stopped by default (L77059).
- `ma_sound_init_from_file` takes the group as arg 4 (L11391).

`vendor/VERSION` bumped (dll `15f03e02…4e65`, gta_shim.c `da7ad9ab…f099`; header +
impl TU sha256s unchanged from M1). Deps still KERNEL32 + UCRT only. `rake` +
`rake spike` rerun green on the new binary BEFORE any M2 code landed.

## New facts pinned live this cycle (encoded in test/native_smoke_test.rb)

1. **A bus graph never starves the render loop**: with started-by-default groups
   attached to the endpoint, `gta_engine_read_f32` returns full frame counts of
   float-exact silence even with zero sounds — the M1 empty-graph-starvation guard
   applies only before bus creation.
2. **Scheduled group fades land sample-exact**: `gta_group_set_fade_start_pcm`
   (1.0→0.0 over [4096, 8192)) leaves post-fade RMS at exact float 0.0.
3. **One pending fade slot per engine node** (header L79260-63; consumed into the
   fader at the next processed chunk, L76694-711): duck attack and release can
   never be pre-stacked on the same group. Consequence encoded in design: the
   release fade is issued from `update()` on the last tick before the hold
   expires; `AudioData` validates `hold_frames >= tick_frames` so the release
   start frame is never in the past.

## Architecture landed (src/gta/, harness/)

- **`AudioSystem`** (`audio_system.rb`): pure event sink. `handle_event(tick,
  name, payload)` + `update(tick)`; all timing = `tick * tick_frames` (from
  `data/audio/engine.json`) — the engine clock is never read on the control path.
  Voice pool steal executes exactly like spike 04 (stop victim → destroy → load
  into slot); music transitions bar-quantized ≥ 1 tick ahead, fully scheduled at
  request via absolute-clock calls (spike 05 pattern), requests ignored while one
  is pending (deterministic policy); ducking = schedule-ahead GROUP fades only;
  end-of-sound polled. Diagnostics only flow out (active_voices, dropped_cues,
  music_state).
- **`CommandIO` + `CommandLog`** (`command_io.rb`): the single choke point — FFI
  forward + optional log line per command, same code path, so the log cannot lie.
  Floats serialize as IEEE-754 f32 hex bits (what crosses the FFI); `%.9g` human
  column is decoration; **the md5 rides the canonical hex lines only**. Handles
  are mechanical (`sound_007`, `bus_music`, `stem_a`); machine paths never enter
  the log (fixture keys logged instead).
- **Schema growth** (`data/audio/*.json` + `audio_data.rb` validation): engine
  table (tick_frames 800), fixtures manifest (generated tones only), cues with
  event/file/bus/priority/gain/pan/spatial/duck (dB + attack/hold/release frames),
  music states (calm/combat/silent) + initial_state + stem file/gain refs. Zero
  new numbers in code.
- **Gate harness** (`harness/gate_runner.rb`, `run_gate.rb`, `rake gate`): per
  replay, TWO full fresh renders (fresh engine + fresh AudioSystem each), byte
  compare + log-md5 compare, WAV + pretty log artifacts under `tmp/gate/`,
  expectation table (goertzel / rms / silence / ratio windows, authored in ticks
  or frames), nonzero exit on any fail.
- Analysis helpers promoted to `src/gta/analysis.rb`; spike support delegates
  (floor rerun green — same sha256s, midpoints 0.0).

## Gate results (rake gate, two consecutive full runs, separate processes)

```
== gate: replay_cues ==                            (360 ticks; 66 events; 64-voice pressure)
   command log md5    63f4a1df9af84c8297d3b42eaf0210db     (identical across runs)
   wav sha256         181e91eba39ced82dabd64a5ccdf8cad817351eb1b66747a4ca6f4d44986a318
   PASS double render byte-identical | PASS double command-log md5 match
   PASS goertzel 880 ch0 [0,4800)       amp=1.64e-05 ≤ 0.01     (ui cue absent pre-event)
   PASS goertzel 880 ch0 [8000,12800)   amp=0.2003   ≥ 0.1      (toll_paid at tick 10 exact)
   PASS goertzel 500 ch0 [160000,164800) amp=0.2124  ≥ 0.02     (victim audible pre-steal)
   PASS goertzel 1500 ch0 [160000,164800) amp=1.07e-04 ≤ 0.01
   PASS goertzel 1500 ch0 [168800,173600) amp=0.2123 ≥ 0.05     (stealer enters at 168000)
   PASS goertzel 2100 ch0 [152000,156800) amp=0.8920 ≥ 0.3      (63 coherent fillers)
   PASS rms [0,4800) 0.1772 ≥ 0.1                               (music from frame 0)
   PASS steal collapse  500Hz ratio=0.00942 ≤ 0.02              (106:1 cut at the steal frame)
   PASS duck depth      400Hz ratio=0.251189 ∈ [0.2,0.32]       (theoretical -12 dB = 0.251189)
   PASS duck recovery   400Hz ratio=1 ∈ [0.85,1.15]             (release complete by 204000)
   diagnostics: voices=63 dropped=0 music=calm
== gate: replay_music ==                           (400 ticks; quantized transition + silent tail)
   command log md5    1c16c0613e7a3068250dfaa4d21a5141     (identical across runs)
   wav sha256         3691bf4052cbdff897d58a7ead565c5b372e245f43835e6e976a152b21461621
   PASS double render byte-identical | PASS double command-log md5 match
   PASS goertzel 880 ch0 [16000,20800)  amp=0.2003 ≥ 0.1        (ui cue over music)
   PASS goertzel 400 ch0 [80000,84800)  amp=0.2506 ≥ 0.1        (calm stem)
   PASS goertzel 1000 ch0 [180000,184800) amp=4.1e-16 ≤ 0.01    (combat stem absent pre-boundary)
   PASS goertzel 1000 ch0 [204000,208800) amp=0.2506 ≥ 0.1      (full level post-fade)
   PASS goertzel 400 ch0 [204000,208800) amp=1.7e-15 ≤ 0.005    (calm stem stopped at 201600)
   PASS rms [240000,244800) 0.1772 ≥ 0.1
   PASS silence [300000,316800) rms=0 ≤ 1e-9                    (float-EXACT tail silence)
   PASS transition lands at boundary: 1000Hz mid-fade ratio=0.332131 ∈ [0.2,0.5]  (theoretical 1/3)
   diagnostics: voices=0 dropped=0 music=silent
```

WAV artifact files (f32 WAV with header): `tmp/gate/replay_cues.wav` sha256
`2001d191cbfeb18d7b48c8f852a81b6aeb5ff70706e052263e71ce7797ad9c19`,
`tmp/gate/replay_music.wav` sha256
`ac70c6f2facab4d91fd2517b1e3ea0a4eb7d3824786f52dabfe2f76a0a210698`.
(The gate-table sha256s are of the raw f32 sample bytes.)

## Recorder equivalence + allocation law (production mode)

- **Recorder on vs off renders byte-identically** (integration test, real DLL,
  60-tick replay covering cue + duck + transition scheduling + spatial payload).
- **Zero per-tick Ruby allocations, recorder off** (scaling proof, spike 03
  pattern, pinned fact 4 honored — no clock_gettime in the asserted region):
  `alloc delta @1000 ticks: 11 objects (gc runs 0)`, `@5000 ticks: 0 objects
  (gc runs 0)`. The 11 are one-off (duck release issuance + 9 polled voice-end
  destroys landing in the first window); a real 1-object/tick leak would read
  +4000 at 5k. Steady state = music + active voices + at_end polling + duck
  machine + engine advance.

## Notes for M3 / knowledge queue

- replay_cues mixes ~1.3 peak amplitude (63 coherent fillers by design — 800-frame
  tick offsets are integer cycle counts at 2100 Hz). f32 render has headroom (no
  clipper in the graph, values > 1.0 legal in f32 WAV); a limiter/headroom policy
  is an M3 mix-discipline question for the critic-listen pass.
- Critic listen (presentation score, Rule 2 second axis) NOT run this cycle —
  M3 scope, alongside replay-corpus growth.
- Knowledge-repo correction queue from M1 (SDL_AUDIODRIVER timing, empty-graph
  read) still queued; add: started-by-default groups change the starvation
  semantics (fact 1 above).
- `voice_pool.per_category_caps` present in data but not yet enforced by the
  pool (global max only) — M3 candidate, needs a replay that exercises it.

## Consequence

M2 closes: the ADR 0001 decision-5 gate exists as `rake gate` and is the ship
gate for all future audio work (a failed gate blocks shipping — AGENTS
non-negotiable 3). Cycle advances to M3.
