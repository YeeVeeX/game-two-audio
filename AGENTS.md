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

## Current cycle: M5 — integration (owner order LIFTED 2026-08-18)

**The audio order is lifted** — owner, in writing, 2026-08-18: "audio order
lifted" (verbatim + context: `drafts/_m4-owner-scores.md`). Integration
proceeds from `docs/integration-readiness.md` (the prepared runway). M4b
closed same day: `drafts/_m4b-verdict-20260818.md`.

M4b outcome (2026-08-18): live Reaper bridge co-processing loop shipped
(bridge client + reaper:setup + per-slot reaper:render + selective import);
**all seven listen slots are owner VST renders** (bridge loop, one session);
full-set listen sha set pinned (cues da2a62a1, duck ec8303fe, music
d644b61e, churn 7229d606, spatial f5d13763, ui_cap cf2e0d99); gate md5 set
UNCHANGED all session; owner global verdict "they sound good" — the 17
per-box scores stay open BY OWNER CHOICE with **in-game listening as the
presentation instrument of record**; production handoff staged + verified
(`handoff/audio-v1/`, seven 24-bit originals + provenance manifest).

M5 scope:
1. **Assets lane**: game-two-assets ingests `handoff/audio-v1` through its
   exports/manifest law (its seat's work; LUFS measured at its gate — never
   here). The listen-stems lane stays evaluation-only, unchanged.
2. **Engine integration** (game-two seat, per integration-readiness.md) —
   **QUEUED by game-two's dev of record behind its v18 fun-verification
   ritual ("the SEVENTEENTH", owner-paced; receipt 2026-08-18, archived in
   mail done/)**; its scope docs already carry the lift. When the trigger
   adjudicates (spark-up ready:
   `drafts/_next-session-m5a-game-two-integration.txt`): scope-doc
   verification, ~15-line adapter, boot/teardown order, real-device
   smoke, gate re-pin on the integration machine, the clock-domain anchor
   measurement, music_set_state derivation decision (recommendation on file:
   audio-side, data-driven), and an initial ~6-event cue mapping chosen with
   the owner (full 44-row table decided iteratively after the first in-game
   listen).
3. **Presentation closure**: the first in-game listen is the verdict of
   record for the open boxes + the −10 dB sfx balance question (headroom
   ceiling held mechanically all session; worst peak −11.82 dBFS).
4. Foreign-dirty files (PARKING_LOT.md, docs/integration-readiness.md —
   another session's uncommitted edits): their PARKED wording is superseded
   by the trail record; edit the status lines only after that work lands.

M3 closed 2026-08-19: replay corpus 2 → 6 (per_category_caps enforced +
rendered — in-category steal past a global-best decoy, 7/8 coherent proof; duck
overlap — pure hold extension, single extended release, mid-release re-attack,
`group_fade_at count == 4` pinned; music churn with the stem-reuse path finally
RENDERED + ignored requests pinned by per-stem log counts; payload pan sweep
with float-exact opposite-channel zeros); harness grew `log` (exact op-count)
and `peak` expectation types + an always-on metrics block (peak/rms/crest/
over-1.0). Headroom decision (dev of record, KB-cited): data-staged, NO
limiter — sfx bus −3 → −10 dB, every replay gated under −1 dBFS sample peak
(worst now −1.76 dBFS, over-1.0 = 0 everywhere; was +0.93 dBFS / 4627 overs).
Evidence: `drafts/_m3-verdict-20260819.md`. New pinned facts: same-depth duck
overlap issues NO fade (extension moves duck_end only); with sum(caps) ==
max_voices the global steal path is unreachable for capped categories;
collapse-ratio numerators are leakage floors — they don't scale with staging.

M4 scope + status (2026-08-19) — CLOSED except where moved to M5 above:
1. **Owner listen** (presentation axis, Rule 2's second score — accuracy is
   green, presentation is UNSCORED): take 1 (sine fixtures) falsified by the
   owner's ears ("constant hum"); take 2 (musical listen track,
   `data/audio_listen/` + `rake listen`) approved in direction, ACCEPTED as
   prototype placeholder material; **the 17 score boxes are still open**
   (`drafts/_m4-listen-sheet.md`; sub-3 box = presentation-gate FAIL, fix
   lands with a replay/expectation guard). Verbatim feedback trail:
   `drafts/_m4-owner-scores.md`. Mirror law pinned by
   `test/listen_track_test.rb`; gate corpus untouched (md5 set verified).
2. **Owner production loop — LIVE end-to-end, waiting on owner VST choices**:
   roles pinned — **owner = ears + sound design (Reaper/VST/analog); dev = ALL
   format/validation/render automation and never scores presentation**. Built:
   `rake midi`; live Reaper-MCP bridge (the owner's installed auto-start Lua
   server, no `.rpp` fabrication); `rake reaper:setup` → protected
   `owner_project.rpp` + generated `scaffold.rpp`, 7 canonical MIDI items /
   exact non-overlapping regions, disposable ReaSynth audition FX; per-slot
   `rake reaper:render SLOT=<id>` → fresh never-overwritten inbox revision →
   48 kHz/duration verification → selective sha-pinned import → auto listen
   render; manual `rake stems:import` still handles batches. Real Reaper 7.79
   proof: all-regions 7/7 exact and sandbox-imported; per-slot calm render
   exact 288000 frames; production manifest/listen hashes untouched. Current
   owner action: replace ReaSynths with chosen VSTs and tune while each region
   loops; then import the first owner-designed revision.
3. **Headroom closure**: the −1 dBFS ceiling holds mechanically; the open
   half is the balance question (does sfx sit too quiet at −10 dB?). Close
   with the owner's ears; a limiter stays out unless listening demands it
   (that would be a DLL-rebuild scope break — re-ask first).
4. Whatever the listen sheet surfaces (steal transient, re-attack feel,
   center-vs-side pan loudness are the flagged candidates; pre-thought fix
   designs live in `drafts/_next-session-m4-listen-closure.txt` §2).
5. ~~**Integration stays PARKED** on owner order~~ — **order lifted
   2026-08-18** (see M5 block; `docs/integration-readiness.md` is now the
   active runway; its two open design items move to M5).

**OUT of scope (→ PARKING_LOT.md):** HRTF/binaural; audio occlusion
raycasts; runtime asset hot-reload; network-synced audio; LUFS metering in
the gate (lives in the assets pipeline); distance-attenuation DSP (payload
plumbed; needs a cue-table field + replay). Integration is NO LONGER parked
(order lifted 2026-08-18; PARKING_LOT.md line pending edit — foreign-dirty
file).

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
- `rake gate` — deterministic replay gate (harness/replays/*.json → command-log
  md5 + WAV artifacts under tmp/gate/ + double-render byte-compare + assertions
  incl. log op-counts and −1 dBFS peak ceilings; 6/6 green ×3 2026-08-19). The
  ship gate for all audio work.
- `rake listen` — M4 listen track: same replays through the same runner against
  `data/audio_listen/` (musical fixtures; mirror law) → tmp/listen/*.wav for
  the owner's ears; peak ceiling + determinism still gate (docs/listen-track.md).
- `rake midi` — export the listen compositions as SMF scaffolds →
  `data/audio_listen/midi/*.mid` (owner re-voices in Reaper/analog; deterministic).
- `rake reaper:setup` — one-time live-bridge scaffold build; refuses to
  overwrite `owner_project.rpp`; Reaper serializes + verifies WAV render config.
- `rake reaper:render SLOT=<mechanical_id>` — fresh per-slot revision (never
  overwrites inbox audio) → selective import → full listen re-render; `VERIFY=1`
  proves the real render without changing the manifest/stems.
- `rake stems:import` — manual/batch inbox validation, normalization, sha pin,
  and listen render; inbox source files are reported and left in place.
- swarmforge: `PATH="/c/Users/gabri/workspace/swarm-forge/.venv/Scripts:$PATH"
  swarmforge gauntlet --repo .` (test stage = rake, see swarmforge.toml).

## Coordination contract

- **game-two** (integration target; order lifted 2026-08-18): event
  names/payloads must match its `EventBus::EVENTS` whitelist; integration
  work lands via that repo's seat per `docs/integration-readiness.md`.
  Never write into that repo from here — coordination through its seat.
- **game-two-assets**: runtime audio files will arrive via its `exports/` pipeline
  (formats/loudness per `music-production/game-audio-pipeline.md` LUFS targets). Until
  then, spike audio = generated tones/synthesis (no copyrighted audio in this repo,
  ever). **Listen-stems lane is separate**: owner-produced in-house renders live in
  `data/audio_listen/stems/` (sha-pinned fixtures, evaluation-only) — they never
  substitute for the game-two-assets runtime lane at integration.
- **knowledge repo**: research corpus + vault notes are the citation base; new findings
  from the spike flow BACK as corrections (e.g., the `SDL_AUDIODRIVER` timing verdict).

## Layout

- `src/` — AudioSystem (event sink, voice pool, music state machine), CommandIO
  recorder, analysis, renderer + FFI bindings
- `spike/` — M1 falsification scripts (one per ADR list item)
- `harness/` — gate runner + CLI + `replays/*.json` (rake gate) + listen/midi tools
- `data/audio/` — engine/cue/bus/music/fixture JSON tables (accuracy corpus, sines)
- `data/audio_listen/` — mirror tables + musical fixtures + `midi/` scaffolds +
  owner `stems/` (listen track; docs/listen-track.md)
- `vendor/` — pinned miniaudio (source + DLL + VERSION)
- `docs/adr/` — decisions; `drafts/` — council records, verdicts, session notes
- `test/` — minitest
