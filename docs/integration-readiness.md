# Integration readiness — game-two-audio → game-two

**Status: LIVE — order lifted 2026-08-18; game-two's M5a lane executed the
integration on its own seat** (real-device smoke + in-game listens of record,
owner verdict "acceptable for now": mail
`done/from-game-two-m5-listen-verdict.md`; game-two commits
`34bec50`/`eaf5e9b`/`dd84010` consume owner audio, cited in
`handoff/audio-v12/BANKED.md`). This doc was the prepared runway and stays as
the seam reference; cue-mapping decisions now proceed iteratively in game-two
custody (its ear-check loop), so the table below is the pre-integration
proposal snapshot. This repo still never writes into game-two.

Sources read live 2026-08-19 (read-only): `game-two/src/game/world.rb`
(`World::EVENTS`, 44 symbols), `game-two/src/core/event_bus.rb`.

## 1. Event mapping table

game-two publishes events on `Core::EventBus` (explicit registration,
`emit(type, **payload)`, symbol keys, queued + flushed once per frame via
`#process`). `AudioSystem#handle_event` already accepts Symbol or String
names and returns nil on unmapped events (audio is a sink; unmapped = not
ours). Mapping = adding cue entries whose `"event"` field names the game-two
symbol; zero code.

Semantic notes below are **proposals from event names only** (mechanical
placeholder discipline: cue ids stay mechanical; no fiction names).

Cue archetypes available today: `ui_confirm` class (toll_paid: short ui
blip), `stinger+duck` class (boss1_spawn: sfx hit that ducks music),
`spatial one-shot` class (drone_low: pan/distance payload), plus the music
state machine (calm/combat/silent). Candidate archetype *extensions* banked
from the Itexo corpus (telegraph lead-time pairing, 3-way deny taxonomy,
low-stock variant bands, ceremony stinger tiers, yield/no-yield registration):
`docs/itexo-audio-vocabulary.md` — parked, per-slot triggers in PARKING_LOT.md.

| game-two event | status | proposed archetype |
|---|---|---|
| attack_started | needs-cue-decision | spatial one-shot (attacker pos) |
| special_started | needs-cue-decision | stinger class, maybe duck |
| attack_hit | needs-cue-decision | spatial one-shot |
| damage_dealt | needs-cue-decision | likely NO cue (attack_hit covers; avoid double-fire) |
| actor_died | needs-cue-decision | spatial one-shot |
| dodged | needs-cue-decision | short one-shot |
| telegraph | needs-cue-decision | one-shot; also a music-tension candidate |
| projectile_fired | needs-cue-decision | spatial one-shot |
| fight_resolved | needs-cue-decision | stinger; **music-state candidate (→ calm)** |
| zone_entered | needs-cue-decision | ambience/one-shot; **music-state candidate** |
| possession_changed | needs-cue-decision | stinger |
| seal_breached | needs-cue-decision | stinger + duck |
| home_rehomed | needs-cue-decision | ui confirm |
| pack_wiped | needs-cue-decision | stinger + duck |
| pack_respawned | needs-cue-decision | one-shot |
| pack_mark_set | needs-cue-decision | ui confirm |
| drop_spawned | needs-cue-decision | spatial one-shot |
| drop_picked_up | needs-cue-decision | ui confirm |
| drop_decayed | needs-cue-decision | subtle one-shot or none |
| banked | needs-cue-decision | ui confirm (toll_paid archetype) |
| banked_spent | needs-cue-decision | ui confirm |
| carried_lost | needs-cue-decision | stinger |
| tribute_paid | needs-cue-decision | ui confirm (closest to toll_paid placeholder) |
| provision_bought / provision_used | needs-cue-decision | ui confirm |
| provision_refused | needs-cue-decision | ui deny blip |
| corpse_loaded / corpse_looted | needs-cue-decision | one-shot |
| body_regrown / body_dissolved | needs-cue-decision | one-shot |
| respawn_telegraphed | needs-cue-decision | telegraph one-shot |
| human_retargeted / human_leashed / human_respawned | needs-cue-decision | likely none or subtle |
| taunted | needs-cue-decision | one-shot |
| inscribed / mark_consumed / inscription_burned | needs-cue-decision | ui confirm |
| vessel_kept / vessel_seized / seizure_ended | needs-cue-decision | stinger |
| challenger_engaged | needs-cue-decision | **boss1_spawn archetype (stinger + duck); music-state candidate (→ combat)** |
| challenger_chant_started / chant_interrupted | needs-cue-decision | stinger / interrupt hit |

Harness-only cues (never map): `filler_blip`, `hud_ping`, `drone_low` as
such (its *archetype* maps; the 500 Hz test cue does not). All 44 events are
currently **unmapped by design** — identity-mapped placeholder events
(`boss1_spawn`, `toll_paid`…) are not in the game-two whitelist, so today's
sink would correctly ignore every real event.

**music_set_state is NOT a game-two event.** The whitelist carries no music
control. Decision needed at integration (owner + dev): either (a) an
audio-side adapter derives music state from sim events (candidates flagged
above: challenger_engaged → combat, fight_resolved → calm, zone_entered →
zone table), or (b) game-two registers a music_set_state event (a game-two
change — owner's call). (a) keeps game-two untouched and the derivation
data-driven; recommended.

## 2. Payload conventions (current contract)

- Payload keys are **symbols** (EventBus `emit(type, **payload)` matches
  `payload[:pan]` reads exactly).
- `:pan` Float −1.0 … +1.0, honored only when the cue declares
  `"spatial": true` (balance mode: −1 hard left, +1 hard right, center =
  both channels full — pinned by replay_spatial).
- `:distance` Float ≥ 0, **pool-steal metadata only** (furthest-first
  tie-break). No distance attenuation exists; if the game wants it, that is
  a new cue-table field + gate replay, not a payload change.
- `music_set_state` shape (if event route (b) is chosen):
  `{ state: "calm" }` — the state name must be a **String** matching
  `music.json` keys; an adapter must `.name` any Symbol (current code
  raises on unknown states — loud by design).
- Tick: `handle_event(tick, name, payload)` takes the **sim tick** (world
  frame counter). All audio timing derives from it (`tick * tick_frames`);
  the engine clock is never read on the control path.

Adapter sketch (lives in game-two at integration, ~15 lines): for each
mapped event `bus.subscribe(type) { |ev| audio.handle_event(world.frame,
ev.type, ev.payload) }`, then once per frame after `bus.process`:
`audio.update(world.frame)`.

## 3. Real-device boot + teardown order

1. **Process entry, before any SDL audio init**: `ENV["SDL_AUDIODRIVER"] =
   "dummy"` (spike 02: the hint is read at SDL audio-subsystem init;
   process entry is the shipped policy — earliest safe point).
2. `require "gosu"`, window creation as normal (Gosu renders, input works;
   its audio goes to the dummy backend — `Sample#play` does not crash).
3. `GTA::Native.gta_engine_create(1, channels, sample_rate)` — use_device=1;
   miniaudio owns WASAPI. One engine per process.
4. `AudioSystem.new(...)` — buses/stems built immediately.
5. Per frame: sim update → `bus.process` (flush; audio handlers fire) →
   `audio.update(tick)`. **No render loop** — the device thread pulls.
6. Teardown order (already encoded in `AudioSystem#destroy`): voices →
   stems → child groups → master group → then `gta_engine_destroy` → then
   process exit / window close.

**Clock domains — LANDED 2026-08-19**
(`drafts/_m5-clock-anchor-verdict-20260819.md`; game-two's r2 cue-spec mail
measured ~800 frames/s linear drift on the real device; the anchor below
shipped with replay_clock_drift falsification). Original analysis kept for
the record: in noDevice gate mode the control code advances the engine clock
itself, so `frame = tick * 800` is exact. On a real device the engine clock
advances on the device thread at the hardware rate while ticks follow the
game loop; `tick * 800` will drift from engine time (spike 02 measured
~58,080 engine frames across 60 window updates). Candidate fix, in-law
(schedule-ahead only, clock read on the control thread at anchor points,
never per-command): anchor `engine_time_at_tick0` once at boot via
`gta_engine_time_pcm` (shim export, verified vendor/gta_shim.c L116), schedule against `anchor + tick * 800`, and
re-anchor at music boundaries if drift exceeds a tick. The real-device
measurement landed and the anchor is pinned (see lead-in). (Reminder: `Process.clock_gettime` allocates on
this build — keep any drift instrumentation out of GC-asserted regions.)

## 4. Asset handshake (game-two-assets `exports/`)

- Runtime audio arrives via game-two-assets `exports/`; **the cue-table
  `"file"` keys are the seam**: today they resolve into the generated-tone
  fixture manifest (`data/audio/fixtures.json`); at integration a manifest
  swap points the same keys at export files. Loader, validation, and cue
  schema unchanged.
- Formats: WAV 48 kHz (engine native rate — no resampler in the render
  path today; keep it that way), PCM16/24 or f32. Loop stems must be
  bar-exact lengths (the transition math assumes it: bar = 96,000 frames at
  120 bpm 4/4).
- Loudness targets per KB `music-production/game-audio-pipeline.md` §7
  (verified 2026-04): game-audio LUFS table — e.g. exploration music −18 to
  −16 LUFS integrated at −3 dBTP; master ceiling −1 dBTP with a safety
  limiter doing ≤ 1–2 dB (`production-fundamentals.md`). Pull the full
  content-type table from the KB note at handshake time; loudness
  conformance is measured in the assets pipeline (this repo's gate measures
  sample peak, not LUFS).
- Gate replays stay tone-based forever (deterministic fixtures); real
  assets get their own smoke replay at integration (load + play + peak
  bound), not a byte-pinned render.
- No third-party audio enters this repo, ever (standing law).

## 5. Performance + determinism restatement (must hold on the integration machine)

| invariant | pinned value | source |
|---|---|---|
| audio command budget, worst-case 64-voice tick | p95 ≤ 0.5 ms (measured 0.033–0.036 ms, 14×) | spike 03 |
| steady-state Ruby allocations per tick (recorder off) | 0 (scaling-proven, re-proven after every M3 branch) | steady_state_alloc_test |
| audio thread enters Ruby | never (no FFI callbacks; poll + schedule-ahead) | ADR 0001 law |
| same-machine double render | byte-identical | rake gate, every replay |
| command-log md5 / WAV sha | same-machine pins; **not** claimed cross-machine (libm pow in db_to_gain and float render paths may differ per machine — re-pin on the integration machine once, then hold) | M3 verdict |
| vendor/miniaudio.dll | sha256 must match `vendor/VERSION` (`15f03e02…4e65`); no rebuild without the vendor law (VERSION bump + full gate rerun) | AGENTS |
| SDL_AUDIODRIVER=dummy | set at process entry | spike 02 |

Integration acceptance = `rake` + `rake gate` green on the integration
machine + the real-device smoke (device opens, tone plays, teardown clean —
spike 02 pattern) before any game-two wiring lands.
