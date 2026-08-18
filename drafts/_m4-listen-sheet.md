# M4 owner listen sheet — musical listen track (presentation axis, take 2)

**Status: WAITING FOR OWNER LISTEN.** Take 1 (sine fixtures,
`drafts/_m3-listen-sheet.md`) was falsified as listen material by the owner
(2026-08-19): raw tones swamped the behaviors. This sheet scores the SAME six
behaviors on the **musical listen track** — same replays, same choreography,
same timestamps (mirror law, `test/listen_track_test.rb`), musical material.

## How to play

- Files: `tmp/listen/<name>.wav` — regenerate any time with `rake listen`
  (bit-identical; hashes in the M4 verdict once cut).
- Format: **stereo float32 WAV, 48 kHz** — Audacity, VLC, foobar2000; stock
  Windows Media Player may refuse f32. Headphones for `replay_spatial`.
- Renders sit conservative under the −1 dBFS ceiling (peaks ≈ −10 to −15
  dBFS): set your playback volume comfortably and keep it FIXED across files
  — two boxes are balance judgments.
- The material: calm music = warm slow pad (A minor, 3 chords + soft top
  notes); combat music = driving bass riff with stabs; drone sfx = dark low
  drone; boss stinger = impact hit + falling pitch + decaying swell; UI =
  bell plucks/pings; the swarm = soft bell-pip rain. All placeholder
  synthesis, all in A minor at 120 bpm — real stems come later (Reaper spec:
  `docs/listen-track.md`). Judge the **behaviors**; prose-note any material
  taste too, it feeds the Reaper stem specs.
- Score 1–5 per box (1 = broken/unpleasant, 3 = acceptable, 5 = right).
  A box under 3 anywhere = presentation gate fails; the fix lands with a
  regression guard.

## Mechanical metrics (measured, 2026-08-19 listen run)

| replay | peak (dBFS) | rms (dBFS) | crest | samples > 1.0 |
|---|---|---|---|---|
| replay_cues | −11.21 | −24.67 | 13.46 dB | 0 |
| replay_duck_overlap | −12.38 | −25.96 | 13.58 dB | 0 |
| replay_music | −11.39 | −26.65 | 15.26 dB | 0 |
| replay_music_churn | −15.10 | −28.14 | 13.04 dB | 0 |
| replay_spatial | −12.03 | −24.63 | 12.60 dB | 0 |
| replay_ui_cap | −10.21 | −23.42 | 13.21 dB | 0 |

Bus staging is IDENTICAL to the gate corpus (music −6, sfx −10, ui −6 dB) —
the standing question from M3 is still: **does sfx sit too quiet under the
music at −10 dB?**

## replay_cues.wav (6.0 s) — cue spam, steal, duck

| time | what happens | listen for |
|---|---|---|
| 0.00 | calm pad from the very first sample | no click/ramp-up at start |
| 0.17 | UI confirm pluck | clean entry over the pad |
| 2.00 | low drone enters | audible under everything until 3.50 |
| 2.02–2.78 | 47 bell-pips stack into a rain texture | steady shimmer build, no crackle |
| 3.50 | boss stinger (impact + falling pitch) + **the steal**: the low drone is cut at this exact instant + music ducks −12 dB over 50 ms | is the drone cut audible as a glitch, or masked by the stinger? does the duck read as intentional? |
| 4.05–4.25 | duck releases, pad back to full over 200 ms | smooth return, no pump |
| 5.50 | stinger tail ends | — |

| axis | score (1–5) | notes |
|---|---|---|
| timing feel (cue entries land where listed) | ☐ | |
| duck audibility (dip reads as intentional) | ☐ | |
| steal audibility (drone cut: glitch or acceptable?) | ☐ | |
| harshness / balance (pip rain + stinger vs pad) | ☐ | |

## replay_ui_cap.wav (2.0 s) — UI cap, in-category steal

| time | what happens | listen for |
|---|---|---|
| 0.03–0.10 | low drone + two faint pips | — |
| 0.17–0.52 | 8 sonar pings enter, one per 150 ms | rising ping cascade |
| 0.67 | **cap steal**: oldest ping cut, the two-note confirm pluck rides over | any click at the cut? |
| 0.87 | confirm ends; 7 ping tails remain | the 8→7 drop is subtle — audible at all? |
| 1.37–1.72 | pings end one by one | clean tails |

| axis | score (1–5) | notes |
|---|---|---|
| steal transient (click/pop at 0.67?) | ☐ | |
| ui level (pings/confirm clearly audible, not piercing?) | ☐ | |

## replay_duck_overlap.wav (3.7 s) — duck extension + re-attack

| time | what happens | listen for |
|---|---|---|
| 0.33 | boss stinger 1, pad ducks −12 dB over 50 ms | attack feel |
| 0.67 | boss stinger 2 stacks. **Pad must NOT move** — the duck silently holds longer | any re-dip/wobble here is a defect |
| 1.22 | release begins: pad climbing back over 200 ms | — |
| 1.27 | boss 3 interrupts the climb: pad **re-ducks from wherever it was** (~25 % up) | does the catch-and-re-dip sound smooth or like a stutter? |
| 1.82–2.02 | final release, pad to full | smooth, single recovery |
| 2.33 / 2.67 / 3.27 | stinger tails end in turn | — |

| axis | score (1–5) | notes |
|---|---|---|
| duck audibility (both dips intentional) | ☐ | |
| extension transparency (nothing at 0.67) | ☐ | |
| re-attack smoothness (1.27) | ☐ | |

## replay_music.wav (6.7 s) — one transition + fade to silence

| time | what happens | listen for |
|---|---|---|
| 0.00 | calm pad | — |
| 0.33 | UI confirm over the pad | — |
| 4.00–4.20 | crossfade calm pad → combat riff exactly on the bar | does the swap feel on-beat? any mid-fade hole/bump? (fades are linear) |
| 6.00–6.20 | combat fades to silence | linear fade acceptable? |
| 6.20–6.67 | dead silence | truly silent tail |

| axis | score (1–5) | notes |
|---|---|---|
| transition smoothness | ☐ | |
| transition timing feel (lands on the bar) | ☐ | |

## replay_music_churn.wav (7.0 s) — churn + stem reuse

| time | what happens | listen for |
|---|---|---|
| 2.00–2.20 | calm → combat crossfade (two follow-up requests deliberately ignored) | **nothing** may twitch after the fade completes |
| 4.00–4.20 | combat fades to silence | — |
| 4.20–6.00 | silence | truly dead |
| 6.00–6.20 | calm pad **returns from silence** (the reused stem) on the bar | clean re-entry: no click, no partial-phase blip, no early leak before 6.00 |
| 6.20–7.00 | calm pad at full level | — |

| axis | score (1–5) | notes |
|---|---|---|
| transition smoothness (both fades) | ☐ | |
| reuse re-entry cleanliness (6.00) | ☐ | |

## replay_spatial.wav (12.7 s) — pan extremes

| time | what happens | listen for |
|---|---|---|
| 0.17–4.17 | drone hard **LEFT** (pad stays centered) | fully left? any right-ear bleed? |
| 4.33–8.33 | drone **CENTER** | dead center, same loudness as the sides? |
| 8.50–12.50 | drone hard **RIGHT** | fully right? |

Headphones. Balance mode means the center segment plays in both ears at full
level — it may feel *louder* than the sides; note whether that bothers you
(it drives the pan-law question for real assets).

| axis | score (1–5) | notes |
|---|---|---|
| pan placement (left/center/right where stated) | ☐ | |
| center-vs-side loudness feel | ☐ | |

## Overall

| axis | score (1–5) | notes |
|---|---|---|
| overall mix balance (music vs sfx vs ui at the current −10 dB sfx staging) | ☐ | |
| anything harsh / fatiguing | ☐ | |

Free-form notes (material taste for the Reaper stems welcome here):

>

Return the sheet (or say scores in chat); they get recorded verbatim into
`drafts/_m4-owner-scores.md` before anything is acted on.
