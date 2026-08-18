# Listen track — the presentation axis's ear instrument (M4)

## Why this exists

The M3 owner listen (2026-08-19, `drafts/_m4-owner-scores.md`) falsified raw
sine fixtures as listen material: the tones read as "constant hum / high pitch
drone" and swamped the behaviors under evaluation. Rule 2 scores accuracy and
presentation separately — and the two need **opposite material**:

- **Accuracy (machine)** needs spectrally pure, phase-deterministic sines —
  goertzel bins, float-exact zeros, coherent-sum arithmetic. That corpus is
  `data/audio/` and `rake gate`, and it is untouched by the listen track
  (verified: all six gate md5s identical before/after the track landed).
- **Presentation (ears)** needs musical material so ducks, steals, and
  crossfades can be *felt*. That is this track: `data/audio_listen/` +
  `rake listen` → `tmp/listen/*.wav`.

## How it works

`rake listen` runs the SAME `harness/replays/*.json` corpus through the SAME
`GTA::Gate::Runner` code path, with:

- `data_dir = data/audio_listen` — mirror tables whose only difference is the
  fixture `file` refs (musical synthesis instead of sines). **Mirror law**:
  every choreography-affecting field (engine timebase, buses, voice_pool,
  cue fields, duck tables, music timing/states) must equal `data/audio/`;
  `test/listen_track_test.rb` pins this mechanically. Bus staging is
  deliberately identical — the −10 dB sfx balance question is exactly what
  the owner's ears must answer.
- `expectation_types: ["peak"]` — sine-tuned accuracy pins (goertzel/ratio/
  rms/silence/log) stay gate-only; the −1 dBFS headroom ceiling is global
  policy and gates listen renders too. Determinism (double render byte-compare
  + double log md5) asserts on every listen run — the ear track is not exempt
  from the determinism law.

Fixture synthesis: `GTA::Fixtures` type `"notes"` — deterministic additive
synthesis (tri/saw/square/bell/noise partial tables in code as instrument
definitions; every pitch, rhythm, envelope, and level in
`data/audio_listen/fixtures.json` per the data-driven law). Everything is
A minor at the shared 120 bpm grid so cues sit in one harmonic world. Fixture
WAVs carry `.sig` sidecars (sha256 of the manifest entry) so data retunes
re-render without manual `tmp/` cleanup.

## Replacing the placeholder stems with Reaper renders (owner path)

The synthesis stems are placeholders. Owner-produced Reaper stems replace them
one-for-one when ready. Spec per stem (in-house original material only — no
third-party audio in this repo, ever; mechanical filenames):

| slot | duration (exact) | musical role |
|---|---|---|
| `mstem_calm_6s` | 6.000 s = 3 bars @ 120 bpm | calm-state music loop (seamless at the bar grid) |
| `mstem_combat_6s` | 6.000 s = 3 bars | combat-state music loop (seamless) |
| `msfx_drone_4s` | 4.000 s | low ambient drone (sits below everything) |
| `msfx_stinger_2s` | 2.000 s | boss-spawn stinger (must cut above the music bed) |
| `msfx_swarmpip_4s` | 4.000 s | soft repeating pip; replays stack up to 47 copies at 16.7 ms offsets — keep it very quiet and transient |
| `mui_confirm_200ms` | 0.200 s | UI confirm blip |
| `mui_ping_1200ms` | 1.200 s | soft UI ping with tail (8 stack at 150 ms spacing) |

Format: 48 kHz mono WAV PCM16. **Durations are load-bearing** — the replay
choreography (steal/duck/transition moments) rides on cue lengths;
`test/listen_track_test.rb` fails on drift. Relative level bands follow KB
`music-production/production-fundamentals.md` (Game Audio Targets, verified
2026-04-09): music bed mid, drone below everything, sfx cutting above music,
UI clear-not-jarring; keep per-file peaks conservative — the render gate
enforces −1 dBFS on the mixed result.

## Owner production loop (plugins / analog synths) — IMPLEMENTED

The composition source of truth is `data/audio_listen/fixtures.json`. The
round trip:

1. **`rake midi`** → `data/audio_listen/midi/<slot>.mid` — each placeholder
   composition as a standard MIDI file (format 0, 120 bpm, division 480;
   deterministic, committed). Pitches are the ET notes of the composition;
   velocity ≈ 127·√amp; wave/envelope/tremolo/glide/noise carried as text
   markers (params stay authoritative in the JSON). Detuned pairs collapse
   to one note + marker — re-create the detune on the instrument.
2. Owner re-voices in Reaper (VSTs) or drives analog gear via MIDI/CV — KB
   `music-production/moog-dfam.md` §6 has game-audio patch recipes (Patch 3
   "alien texture loop" fits the `msfx_drone_4s` slot directly); records/
   renders to the spec above (48 kHz mono PCM16 WAV, exact slot duration).
3. Drop the render under `data/audio_listen/stems/` and swap the manifest
   entry to the **file type**:
   `{ "type": "file", "dur_s": <slot>, "path": "stems/<slot>.wav", "sha256": "<pin>" }`
   — sha256 is the provenance pin (mismatch refuses to load); format and
   exact duration are validated at import (durations are load-bearing).
4. `rake listen` re-renders the six WAVs with the new material; the mirror
   law + peak ceiling + determinism all still gate.

In-house original renders only (no third-party audio, no sample-pack content
with redistribution restrictions committed to the repo). Real *runtime*
assets still arrive via the game-two-assets `exports/` pipeline at
integration time; this track is only this repo's evaluation instrument.

## Commands

```
rake listen   # render the 6 replays with musical fixtures -> tmp/listen/*.wav
rake midi     # export placeholder compositions -> data/audio_listen/midi/*.mid
rake gate     # the accuracy ship-gate (sine corpus) — unchanged
```

Owner listens against `drafts/_m4-listen-sheet.md`.

## Known material notes (owner reports, mechanically verified)

- "Constant string-like sound in the back of each file" (owner, take 2):
  **intended composition** — the calm pad's whole-stem sustained A2 root
  drone (tri, slow tremolo), present wherever calm music plays (every replay
  opens in state `calm`), thickened in `spatial`/`ui_cap`/`cues` by the sfx
  drone sitting on the same A root. Verified: churn's programmed-silence
  window renders float-exact rms=0 (nothing leaks when the system is
  silent); 110 Hz reads constant only in music-on windows. Ear
  discriminator: `replay_music_churn` 4.2–6.0 s must be dead silent. Knob if
  it bothers: the root-drone note's amp in `mstem_calm_6s` (data-only, one
  line) — or the owner's replacement stem simply composes a different bed.
