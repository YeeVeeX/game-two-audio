# game-two-audio — audio foundation for the game-two program

Sibling project of `workspace/game-two` (same pattern as game-two-lore): **audio is
owner-ordered OUT of the game-two repo**; this project develops the audio system to
integration readiness. Dev agent is the **dev of record** (design calls are the dev's to
make and defend); owner is the tester. The audio order was LIFTED 2026-08-18
(`drafts/_m4-owner-scores.md`); integration flows through game-two's seat —
this repo still never writes into game-two.

<!-- FAMILY-BLOCK BEGIN -->
## Workspace family (game-two program) — synced 2026-08-22

- **Peers:** Gabriel (owner-founder, es-CR) + Junior (co-creator,
  pt-br) co-direct the whole program with equal creative standing —
  design, code, audio/assets, ideas flow from BOTH; neither is the
  other's worker. Owner overrides are law and get RECORDED (one line)
  in the affected repo.
- **Never gate on peer availability (owner order 2026-08-22):** solo
  progress is the default in every repo — peer online = good, absent =
  keep moving, symmetric both ways; the dev of record proactively
  surfaces REAL recorded work items (never fabricated ones). Peer
  ratifications land async in the hub chat.
- **Hub-and-spoke:** the game-two dev chat is the HUB; work in this
  repo runs as bounded sessions under its own dev-of-record.
  Cross-repo asks travel by SEAT MAIL (`~/.pi/agent/mail/<repo>/`),
  digest-stamped (md5), answered with `RECEIPT:` lines. Deliveries
  INTO game-two obey game-two's intake rules (owner-approved +
  digest-grounded + docs-only banking).
- **Seat-lease law:** no session ever writes into a sibling workspace
  tree — read tool for reading, mail for asking, md5 as the
  byte-identity arbiter.
- **Sovereignty:** this block never overrides local law — this repo's
  own invariants win inside this repo.
- **Contract mirror:** AGENTS.md is ground truth; CLAUDE.md is a thin
  pointer to it so Claude sessions load the same contract (AGENTS.md
  wins on any disagreement).
<!-- FAMILY-BLOCK END -->

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
2. **Engine integration** — **LIVE on the game-two side (M5a, executed
   2026-08-18 by its seat)**: real-device smoke + in-game listens of record
   landed there (owner verdict of record "acceptable for now"; mail
   `done/from-game-two-m5-listen-verdict.md`), and game-two consumes owner
   audio in commits `34bec50`/`eaf5e9b`/`dd84010` (asks 7–9; cited in
   `handoff/audio-v12/BANKED.md`). The clock-domain anchor measurement came
   back via its r2 cue-spec mail and the fix landed here (item 5). Cue
   mapping proceeds iteratively in game-two custody (its ear-check loop);
   this seat serves cue-spec asks + banked originals. Superseded spark-up
   kept for the record: `drafts/_next-session-m5a-game-two-integration.txt`.
3. **Presentation closure**: the first in-game listen is the verdict of
   record for the open boxes + the −10 dB sfx balance question (headroom
   ceiling held mechanically all session; worst peak −11.82 dBFS).
4. Foreign-dirty files — **RESOLVED 2026-08-20**: the inherited vocab-bank
   edits landed verbatim (commit `90e78aa`), the owner's live Reaper state
   pinned (`93d57ef`), and the stale PARKED wording in PARKING_LOT.md /
   docs/integration-readiness.md / this file truth-synced same session.
5. **Clock-domain anchor — LANDED 2026-08-19** (the one item game-two's r2
   cue-spec mail left this seat; measured linear ~800 frames/s drift):
   anchored tick→frame map, engine clock read only at boot + music-boundary
   anchor points, one-tick re-anchor threshold; noDevice gate mechanically
   inert (six pins unchanged); falsified via replay_clock_drift (skewed
   deterministic clock; pre-anchor code fails 9 checks); same-tick
   double-duck pinned by replay_duck_sametick + unit tests. Record:
   `drafts/_m5-clock-anchor-verdict-20260819.md`.

Trail 2026-08-20: audio-v12 banked — `a5eb75a` (ask-8 evolving 64 s calm
loop) + `d9534df` (ask-7 zone-change + ask-9 throws ×4), game-side 16-bit
commits cited in `handoff/audio-v12/BANKED.md`; M5 truth-sync consolidation
landed the inherited vocab bank + owner .rpp and synced these status lines
(worldbuilder cue families parked with named triggers in PARKING_LOT.md).

Trail 2026-08-24: J-6 runtime bus-volume API landed (game-two menu ask,
`done/from-game-two-j6-volume-api.md`): `set_bus_volume` (user trim, clamp
[−60, 0], floor = true mute, unknown bus refuses loud) + `bus_ids`;
contract row docs/integration-readiness.md §2b; gate replay_bus_volume
added via the runner's optional "volume" block — 8 prior pins byte-
unchanged, 9/9 green, listen 9/9. T3 footstep/ambience cue spec received
same session (`done/from-game-two-t3-cue-spec.md`): zero library work owed
until owner renders land; PARKING_LOT entries truth-synced.

M3 CLOSED 2026-08-19 — record: `drafts/_m3-verdict-20260819.md` (replay
corpus 2 → 6; harness `log`/`peak` expectation types + always-on metrics
block). Headroom law (dev of record, KB-cited): sfx bus at −10 dB, every
replay gated under −1 dBFS sample peak; a limiter stays OUT unless
listening demands it (DLL-rebuild scope break — re-ask first). Pinned
facts: same-depth duck overlap issues NO fade (extension moves duck_end
only); with sum(caps) == max_voices the global steal path is unreachable
for capped categories; collapse-ratio numerators are leakage floors —
they don't scale with staging.

M4 CLOSED 2026-08-19 (except items moved to M5 above) — records:
`drafts/_m4-owner-scores.md` (verbatim owner feedback trail),
`drafts/_m4b-verdict-20260818.md`. Live remainders: the 17 listen-sheet
score boxes stay open BY OWNER CHOICE with in-game listening as the
presentation instrument of record (`drafts/_m4-listen-sheet.md`); owner
production loop LIVE end-to-end (roles pinned: owner = ears + sound
design (Reaper/VST/analog); dev = ALL format/validation/render
automation, never scores presentation).

**OUT of scope (→ PARKING_LOT.md):** HRTF/binaural; audio occlusion
raycasts; runtime asset hot-reload; network-synced audio; LUFS metering in
the gate (lives in the assets pipeline); distance-attenuation DSP (payload
plumbed; needs a cue-table field + replay); footstep-material cues +
region-ambience beds (T3 spec in hand — `done/from-game-two-t3-cue-spec.md`;
waiting on owner renders). Integration
is NO LONGER parked (order lifted 2026-08-18; PARKING_LOT.md entry updated
2026-08-20).

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
  incl. log op-counts and −1 dBFS peak ceilings; 8/8 green ×3 2026-08-19 — the
  six M3-era pins unchanged plus replay_clock_drift (skewed-clock anchor
  falsification via the runner's per-replay "clock" block) and
  replay_duck_sametick). The ship gate for all audio work.
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
