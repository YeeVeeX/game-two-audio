# game-two-audio — audio foundation for the game-two program

Sibling project of `workspace/game-two` (same pattern as game-two-lore): **audio is
owner-ordered OUT of the game-two repo**; this project develops the audio system to
integration readiness. Dev agent is the **dev of record** (design calls are the dev's to
make and defend); owner is the tester. Nothing here touches game-two until the owner
lifts the audio order.

## The decision (pinned)

**miniaudio (engine API) bridged via ruby-ffi; Gosu audio bypassed entirely.**
ADR: `docs/adr/0001-audio-foundation.md` (**ACCEPTED 2026-08-17** — all five spike
falsification items passed, `drafts/_m1-spike-verdict-20260817.md`; council
reconciliation `drafts/_council-reconciliation-adr1.md`). Evidence:
`~/knowledge/sources/gosu-audio-architecture-2026-08/` (pass-1 verified) + vault notes
`game-research/ruby-gosu-audio-engine-selection.md`,
`game-research/game-audio-architecture-2d-deterministic.md` (query via
`hub kb query --domain game-research "<topic>"`).

## Non-negotiables (inherited from game-two + ADR structural laws)

1. **The audio thread never enters Ruby.** No Ruby procs as FFI callbacks, ever. Control
   is poll + schedule-ahead (`ma_sound_set_start_time_in_pcm_frames`,
   `ma_sound_set_fade_in_pcm_frames`, `ma_engine_get_time_in_pcm_frames`).
2. **Audio is a pure event sink.** Consumes sim events; never feeds state back into sim,
   saves, or netplay handshake. Audio state derives from (event stream, tick) alone.
3. **Rule 2 analog is the ship-gate**: scripted replay → command log (md5, bit-exact) →
   `noDevice` offline render → WAV artifact → same-machine double-render byte-compare +
   feature assertions (RMS windows, cue timing, silence floors) + critic listen.
   Accuracy and presentation scored separately. Never "sounds right to me".
4. **Data-driven**: cue/bus/music tables live in `data/audio/*.json`. Zero tunable
   constants in code (game-two law).
5. **Tests**: minitest, `rake` runs them. **No mocks in integration tests** — real DLL,
   real render, or skip loudly.
6. **Placeholder names only** (owner order 2026-08-16 inherited): cue ids are mechanical
   (`boss1_spawn`, `toll_paid`); no fiction names in code, data, or docs.
7. **Per-tick allocation discipline**: zero Ruby allocations on the steady-state audio
   path; cue tables parse at load; `GC.stat` deltas watched in the perf harness.

## Current cycle: M3 — replay corpus + critic listen + integration-readiness

M2 closed 2026-08-18: AudioSystem event sink + `rake gate` harness + bus graph with
ducking, both scripted replays green through the FULL gate (replay → command log md5 →
noDevice render → WAV → double-render byte-compare → feature assertions); recorder
on/off byte-identical; steady-state 0 allocs/tick (scaling proof). Evidence:
`drafts/_m2-gate-verdict-20260818.md`. One deliberate DLL rebuild added the sound-group
shim surface (all symbols header-verified; `vendor/VERSION` bumped; floor rerun green).
New pinned facts live in `test/native_smoke_test.rb`: bus graph never starves the
render loop (groups started by default); scheduled group fades land sample-exact; one
pending fade slot per node → duck release issues from update() after the hold.

M3 scope:
1. **Replay corpus growth**: more scripted replays under `harness/replays/` (pool-cap
   pressure incl. `per_category_caps` enforcement, duck overlap/re-attack, music
   state churn, payload-driven spatial sweeps); every new audio behavior lands with a
   replay that would catch its regression.
2. **Critic listen** (Rule 2 presentation axis): scored listen pass on the gate WAVs,
   separate from accuracy; includes the mix-headroom question flagged in the M2
   verdict (replay_cues peaks ~1.3 in f32 — limiter/headroom policy decision).
3. **Integration-readiness checklist** (still PARKED on owner order — prepare, do not
   integrate): event-name/payload mapping table against game-two `EventBus::EVENTS`,
   real-device mode notes, asset-pipeline handshake with game-two-assets
   (exports/ formats + LUFS targets).
4. Knowledge-repo correction queue (owned by a knowledge session, not this repo):
   SDL_AUDIODRIVER timing, empty-graph read semantics, started-groups starvation
   change (M2 fact 1).

**OUT of scope (→ PARKING_LOT.md):** integration into game-two (gated on owner order);
HRTF/binaural; audio occlusion raycasts; runtime asset hot-reload; network-synced audio.

## Environment (mirrors game-two, verified there 2026-08-09)

- Ruby 3.4.10 at `C:\Ruby34-x64` — not on Git Bash PATH: `export PATH="/c/Ruby34-x64/bin:$PATH"`.
- No YJIT (RubyInstaller build). MSYS2/UCRT devkit present (needed once, for `rake dll`).
- `vendor/miniaudio.dll` is the pinned engine binary (sha256 in `vendor/VERSION`;
  amalgamation source committed next to it). Do not rebuild casually; `rake dll`
  documents the exact command; a rebuild bumps `vendor/VERSION` and reruns the full gate.

## Commands

- `rake` — run tests (minitest; includes a mini-replay gate smoke).
- `rake spike` — M1 falsification runner (5/5 green 2026-08-17; kept as regression
  floor; spike 02 needs the :spike bundler group — gosu — and a desktop session).
- `rake gate` — M2 deterministic replay gate (harness/replays/*.json → command-log
  md5 + WAV artifacts under tmp/gate/ + double-render byte-compare + assertions;
  2/2 green 2026-08-18). The ship gate for all audio work.
- swarmforge: `PATH="/c/Users/gabri/workspace/swarm-forge/.venv/Scripts:$PATH"
  swarmforge gauntlet --repo .` (test stage = rake, see swarmforge.toml).

## Coordination contract

- **game-two** (read-only reference): event names/payloads must match its
  `EventBus::EVENTS` whitelist at integration time; integration itself is PARKED until
  the owner lifts the audio order. Never write into that repo from here.
- **game-two-assets**: runtime audio files will arrive via its `exports/` pipeline
  (formats/loudness per `music-production/game-audio-pipeline.md` LUFS targets). Until
  then, spike audio = generated test tones + `midi-writing-mcp` stems (no copyrighted
  audio in this repo, ever).
- **knowledge repo**: research corpus + vault notes are the citation base; new findings
  from the spike flow BACK as corrections (e.g., the `SDL_AUDIODRIVER` timing verdict).

## Layout

- `src/` — AudioSystem (event sink, voice pool, music state machine), CommandIO
  recorder, analysis, renderer + FFI bindings
- `spike/` — M1 falsification scripts (one per ADR list item)
- `harness/` — gate runner + CLI + `replays/*.json` (rake gate)
- `data/audio/` — engine/cue/bus/music/fixture JSON tables
- `vendor/` — pinned miniaudio (source + DLL + VERSION)
- `docs/adr/` — decisions; `drafts/` — council records, verdicts, session notes
- `test/` — minitest
