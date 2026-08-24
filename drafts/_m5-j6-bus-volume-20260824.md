# M5 — J-6 runtime bus-volume API + T3 cue-spec receipt (2026-08-24)

Session scope: two seat-mail asks from game-two (hub), both closed.

## 1. J-6 volume API (ask: done/from-game-two-j6-volume-api.md, brief md5 00802b286e83800aed5e33bbad37e907)

Landed the public runtime control surface for the non-pausing menu's
per-bus volume rows + quick mute. Dev-of-record design calls (defended):

- **Trim semantics, not absolute.** `set_bus_volume(bus_id, db)` takes a
  USER TRIM in dB relative to the authored `volume_db` (cues.json):
  effective gain = `db_to_gain(authored + trim)`. The menu never needs the
  authored values (slider top = 0.0, bottom = floor), and the M3 headroom
  proof (−1 dBFS ceiling, sfx −10 dB budget) holds at EVERY user setting
  because the ceiling forbids exceeding the authored balance.
- **Clamp [−60.0, 0.0]** (`USER_TRIM_DB_FLOOR` / `USER_TRIM_DB_CEILING`).
  Contract constants IN CODE, deliberately not data-tunable — game-side
  prefs persist raw trim dBs whose meaning must never shift under a data
  edit, and a new required JSON field would break game-two's own data
  custody at their next pull. Same class as NEVER / the log grammar.
- **Floor = true mute**: at/below −60 the gain snaps to exactly 0.0
  (digital silence — gate-proven: mute window RMS is exactly 0). Quick
  mute = `set_bus_volume(bus, -60.0)`; restore = re-apply prior trim.
- **Unknown bus = ArgumentError** (named refusal; matches the
  unknown-music-state policy). `bus_ids` (frozen, build order:
  master, music, sfx, ui) is the truth the menu renders rows from.
- **Duck independence** (verified in vendor source before documenting):
  ducks ride the group FADER (`ma_sound_group_set_fade_*`), trims ride the
  group node VOLUME (`ma_sound_group_set_volume` → node output-bus
  volume) — independent multipliers in the miniaudio engine node. Trim
  mid-duck applies at once; duck schedule untouched.
- Applies immediately, unfaded (menu-rate). Logged as ordinary
  `group_set_volume` (zero new log ops; forensics tooling untouched).
- Return value = applied (post-clamp) trim.

Mechanics: `AudioSystem#set_bus_volume` + `#bus_ids` +
`@bus_authored_db` capture at build (src/gta/audio_system.rb); runner
gained an optional `"volume"` replay block ([[tick, bus, db], …], applied
after update(tick), before that tick's render advance — the control-thread
menu call between tick update and device pull); new gate replay
`replay_bus_volume` (trim −20 = exact 0.1× on 500 Hz; bus isolation 400 Hz
ratio 1.0; +6.0 clamps to authored — unclamped would read 2.0×; master
mute window RMS exactly 0; restore ratio 1.0; `group_fade_at` count 0 pins
duck independence at log level; peak −9.25 dBFS); 7 unit tests (clamp both
ends, master 0 dB default, mid-duck schedule integrity, named refusal
issues no commands, frozen bus_ids, log composition).

Verification (Rule 3): `rake` 98 runs 0 failures; `rake gate` 9/9 green
with the 8 prior md5/sha pins byte-identical to the pre-change baseline
(captured first, diffed after); `rake listen` 9/9 clean. Contract row:
docs/integration-readiness.md §2b. Receipt mailed to game-two.

## 2. T3 cue spec (ask: done/from-game-two-t3-cue-spec.md)

Footstep materials (4) + region-ambience beds (3) spec received — the
named triggers for both parked families FIRED. Zero library-side work owed
before owner renders exist (mail's own status). PARKING_LOT.md entries
truth-synced: footstep family now waits on `msfx_step_*_150ms` renders
(mapping rows are game-two custody; priority 10 / no-duck constraints
recorded); ambience-bed architecture call (cue rows vs music-adjacent
family vs parked stereo increment) stays this seat's, decided when
`mamb_*_30s` renders land. Game-side adjacency guard (mail P.S.) already
suppresses dodge-jump steps.
