# M5 — live owner production session: T3 lanes staged + stone 8-take family banked (2026-08-25)

Owner present, Reaper open (live bridge, `owner_project_001.rpp` — his
gitignored working document). Three owner asks served in sequence. All
mutations bridge-driven with a fresh `tmp/reaper_backup_*.rpp` before
each pass (owner-document law); every change verified by independent
read-back, never trusted from the mutating script.

## 1. Section/region staging (owner ask: "set the sections/regions up with notes")

Layout appended after his existing material (ends 243 s; 120 bpm grid):

- 4 step lanes (tracks 15–18, disposable ReaSynth, one C3 trigger note,
  es-CR item notes from the T3 mail): regions at 250/252/254/256.
- 3 bed lanes (tracks 19–21): 60 s work areas at 260/324/388 with the
  render region deliberately the SECOND 30 s — the calm-seam lesson
  applied at design time (loop inherits its own tails; the click class
  is dead by construction).
- Calm re-render (option a) staged: work area 452–580, region
  `msfx_calm_evolving_64s` = [516, 580] (second 64 s pass); his original
  region at 162–226 renamed `msfx_calm_evolving_64s_old0824` so the new
  region owns the $region export name (rename precedent:
  `msfx_throw_200ms_*_old0819`).
- 3 es-CR guide markers in the ruler.

## 2. Calm ×2 duplication (owner: "ok I agree, do it")

His 8 items ([162,226): 4 on `mstem_calm_6s` + 4 on `msfx_drone_4s`)
duplicated via item state chunks (GUIDs stripped) at +290 s and +354 s
on their own tracks — same FX chains apply, so the two passes ARE the
piece playing twice. Pre-checked mechanically: 0 tempo markers and
0 envelope points in the window (item copy is therefore complete).
Read-back: pass1 == originals+290 EXACT, pass2 == originals+354 EXACT
(first comparator printed a false MISMATCH — unstable sort on equal
positions; fixed sort key [pos, track], then EXACT both).

## 3. Stone: 8 takes → per-take export → audio-v13 (owner ask: "export each separately, label sequentially, randomized in game")

Found: owner performed 8 takes on the stone track (Arturia Pigments,
one note each — pitches 48/49/46/50/44/45/42/46, vel 100, dur 0.120 s)
PACKED back-to-back in two 0.6 s items at 250.0/250.6.

**Restructure decision (defended):** packed takes cannot export cleanly —
back-to-back 0.15 s windows bake the previous take's synth release into
the next take's file (cross-take bleed). Mechanical fix, performance
data untouched: the 8 notes moved into 8 one-note items at 246.0+k·0.5 s
(dodge-family spacing; lane [246, 249.65] verified empty of foreign
audible items first), regions `msfx_step_stone_150ms_a..h` exactly
[pos, pos+0.150]. Take letters = his performance order. The old single
`msfx_step_stone_150ms` region retired (a bare name would collide with
the family and no single-take file exists in the contract anymore).

**Render:** per-region bridge renders (render_reaper_slot mechanics:
custom bounds + fixed pattern, master mix, tail OFF), 24-bit config
verified from the project's own RENDER_FORMAT blob (`evaw` bytes[4]=24 —
v12 heritage, not fabricated); canonical all-regions/$region/inbox
render config restored after (ensure block) + project saved.

**Validation (all 8 pass):** RIFF walk PCM 24-bit mono 48 kHz; frames
= 7,200 exactly (0.150 s); non-silent; peaks −15.12…−18.97 dBFS — all
below the v12 throw reference (−14.70 dBFS): mechanically "bajitos",
in-game listen still the presentation verdict of record.

**Banked:** `handoff/audio-v13/` (8 WAVs + BANKED.md, v12 manifest
format, sha256 pins, game-side lines PENDING their commits). Runtime
lane only — listen stems/data/audio_listen untouched by the banking.

## Incident log (honesty row)

- Marker-move loop in the staging pass duplicated the "T3 PASOS" guide
  marker ×8 — mutating markers mid-EnumProjectMarkers re-sorts the list
  under the cursor. Cleaned same session (collect-then-mutate pattern;
  read-back: dupes_found=8, deleted=7, one survivor). Lesson: never
  mutate REAPER markers/regions inside an enumeration loop.

## Open question for the owner (flagged, NOT fixed silently)

The dirt/grass/wood trigger items now sit +1.05 s right of their regions
(253.05/255.05/257.05 vs regions at 252/254/256) and grass/wood tracks
lost their ReaSynth. If that drift was accidental, say the word and the
lane gets re-squared mechanically; if it's your working style, the
regions move to the items instead — either is a one-liner at render
time. Nothing exported from those lanes yet, so nothing is wrong today.

RESOLVED same session: owner confirmed accidental ("it was accidental,
fix it please") — items moved home (253.05→252.0, 255.05→254.0,
257.05→256.0), ReaSynth restored on grass/wood, read-back verified all
three lanes + stone family intact, project saved (backup
`tmp/reaper_backup_20260825_062519.rpp`).

## Verification state

- No src/data/harness surface touched → the session-start gate baseline
  stands (9/9 green, pins byte-identical; suite re-ran green in the
  banking commit's pre-commit hook).
- Renders live in `tmp/t3_render_20260825-061701/` (never overwritten);
  banked copies sha-verified identical at copy time.
