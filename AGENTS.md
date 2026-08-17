# game-two-audio — audio foundation for the game-two program

Sibling project of `workspace/game-two` (same pattern as game-two-lore): **audio is
owner-ordered OUT of the game-two repo**; this project develops the audio system to
integration readiness. Dev agent is the **dev of record** (design calls are the dev's to
make and defend); owner is the tester. Nothing here touches game-two until the owner
lifts the audio order.

## The decision (pinned)

**miniaudio (engine API) bridged via ruby-ffi; Gosu audio bypassed entirely.**
ADR: `docs/adr/0001-audio-foundation.md` (v2, council-reconciled —
`drafts/_council-reconciliation-adr1.md`). Evidence:
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

## Current cycle: M1 — the spike (falsification list)

The ADR is DRAFT v2 until every item passes (list in the ADR):
1. Double `noDevice` render byte-identical (same machine; `jobThreadCount=0`,
   `NO_THREADING`, full decode at load).
2. `SDL_AUDIODRIVER=dummy` at process entry silences Gosu; miniaudio owns the device.
3. Worst-case 64-voice tick command batch p95 < 0.5 ms, GC-clean.
4. Voice pool + steal policy assertable in the rendered WAV.
5. Schedule-ahead quantized transition lands within ±1 PCM frame.

A failed item reopens the ADR at the fallback ladder (SoLoud → FMOD after first-party
license re-read) — it does not get argued around.

**OUT of scope (→ PARKING_LOT.md):** integration into game-two (gated on owner order);
HRTF/binaural; audio occlusion raycasts; runtime asset hot-reload; network-synced audio;
anything the spike doesn't need.

## Environment (mirrors game-two, verified there 2026-08-09)

- Ruby 3.4.10 at `C:\Ruby34-x64` — not on Git Bash PATH: `export PATH="/c/Ruby34-x64/bin:$PATH"`.
- No YJIT (RubyInstaller build). MSYS2/UCRT devkit present (needed once, for `rake dll`).
- `vendor/miniaudio.dll` is the pinned engine binary (sha256 in `vendor/VERSION`;
  amalgamation source committed next to it). Do not rebuild casually; `rake dll`
  documents the exact command; a rebuild bumps `vendor/VERSION` and reruns the full gate.

## Commands

- `rake` — run tests (minitest).
- `rake spike` — M1 falsification runner (wired during M1; each spike item = one script
  under `spike/` with a pass/fail exit).
- Gate tasks (`rake gate`) arrive with the harness once M1 proves the render path.
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

- `src/` — AudioSystem (event sink, voice pool, music state machine) + FFI bindings
- `spike/` — M1 falsification scripts (one per ADR list item)
- `harness/` — replay → render → assert gate tooling (post-M1)
- `data/audio/` — cue/bus/music JSON tables
- `vendor/` — pinned miniaudio (source + DLL + VERSION)
- `docs/adr/` — decisions; `drafts/` — council records, verdicts, session notes
- `test/` — minitest
