# M3 owner listen sheet — presentation axis (Rule 2, second score)

**Status: WAITING FOR OWNER LISTEN.** Nobody has listened to these renders.
The mechanical metrics below are measured; every subjective box is blank on
purpose. Owner is the tester: play each file, listen at the timestamps, score.

## How to play

- Files: `tmp/gate/<name>.wav` — regenerate any time with `rake gate`
  (bit-identical by construction; md5s in `drafts/_m3-verdict-20260819.md`).
- Format: **stereo float32 WAV, 48 kHz**. Audacity, VLC, foobar2000 play it;
  stock Windows Media Player may refuse f32 — use one of the above.
- These are engineering fixtures: pure sine tones standing in for real assets
  (400 Hz = calm music, 1000 Hz = combat music, 880 Hz = ui, 500 Hz = a long
  sfx drone, 1500 Hz = a boss stinger, 2100 Hz = a blip swarm). Score the
  *behavior* (timing, ducking, transitions, balance), not the tone quality.
- Score 1–5 per box (1 = broken/unpleasant, 3 = acceptable, 5 = right).
  A box under 3 anywhere = presentation gate fails; M4 picks it up.

## Mechanical metrics (measured, 2026-08-19 gate run)

| replay | peak (dBFS) | rms (dBFS) | crest | samples > 1.0 |
|---|---|---|---|---|
| replay_cues | 0.6353 (−3.94) | 0.2383 (−12.46) | 8.52 dB | 0 |
| replay_duck_overlap | 0.5338 (−5.45) | 0.1904 (−14.41) | 8.95 dB | 0 |
| replay_music | 0.4507 (−6.92) | 0.1699 (−15.40) | 8.47 dB | 0 |
| replay_music_churn | 0.2506 (−12.02) | 0.1477 (−16.61) | 4.59 dB | 0 |
| replay_spatial | 0.3449 (−9.25) | 0.1850 (−14.65) | 5.41 dB | 0 |
| replay_ui_cap | 0.8164 (−1.76) | 0.2585 (−11.75) | 9.99 dB | 0 |

Headroom decision behind these numbers: sfx bus staged −3 → −10 dB, no
limiter; every replay gated under −1 dBFS sample peak (was +0.93 dBFS with
4627 over-full-scale samples before staging). **Question for your ears:** does
sfx now sit too far *under* the music? See the balance boxes below.

## replay_cues.wav (6.0 s) — cue spam, steal, duck

| time | what happens | listen for |
|---|---|---|
| 0.00 | calm music (400 Hz) from the very first sample | no click/ramp-up at start |
| 0.17 | ui blip (880 Hz, 200 ms) | clean entry over music |
| 2.00 | long drone enters (500 Hz) | audible under everything until 3.50 |
| 2.02–2.78 | 47 blips stack up (2100 Hz swarm builds) | steady crescendo, no crackle |
| 3.50 | boss stinger (1500 Hz) + **the steal**: the 500 Hz drone is cut at this exact instant + music ducks −12 dB over 50 ms | is the drone cut audible as a glitch, or masked? does the duck read as intentional? |
| 4.05–4.25 | duck releases, music back to full over 200 ms | smooth return, no pump |
| 5.50 | boss stinger ends | — |

| axis | score (1–5) | notes |
|---|---|---|
| timing feel (cue entries land where listed) | ☐ | |
| duck audibility (dip reads as intentional) | ☐ | |
| steal audibility (drone cut: glitch or acceptable?) | ☐ | |
| harshness / balance (swarm vs music) | ☐ | |

## replay_ui_cap.wav (2.0 s) — ui cap, in-category steal

| time | what happens | listen for |
|---|---|---|
| 0.03–0.10 | drone (500 Hz) + two faint blips | — |
| 0.17–0.52 | 8 ui pings enter, one per 50 ms (880 Hz, coherent — they sum into one louder tone) | stepped build-up |
| 0.67 | **cap steal**: oldest ping cut, louder ui blip (200 ms) rides over | any click at the cut? |
| 0.87 | blip ends; 7 pings remain (slightly quieter than before 0.67) | the 8→7 drop is subtle — audible at all? |
| 1.37–1.72 | pings end one by one | clean tails |

| axis | score (1–5) | notes |
|---|---|---|
| steal transient (click/pop at 0.67?) | ☐ | |
| ui level vs music (pings audible enough?) | ☐ | |

## replay_duck_overlap.wav (3.7 s) — duck extension + re-attack

| time | what happens | listen for |
|---|---|---|
| 0.33 | boss 1 (1500 Hz), music ducks −12 dB over 50 ms | attack feel |
| 0.67 | boss 2 stacks (louder 1500 Hz). **Music must NOT move** — the duck silently holds longer | any re-dip/wobble here is a defect |
| 1.22 | release begins: music climbing back over 200 ms | — |
| 1.27 | boss 3 interrupts the climb: music **re-ducks from wherever it was** (~25 % up) | does the catch-and-re-dip sound smooth or like a stutter? |
| 1.82–2.02 | final release, music to full | smooth, single recovery |
| 2.33 / 2.67 / 3.27 | bosses end in turn | — |

| axis | score (1–5) | notes |
|---|---|---|
| duck audibility (both dips intentional) | ☐ | |
| extension transparency (nothing at 0.67) | ☐ | |
| re-attack smoothness (1.27) | ☐ | |

## replay_music.wav (6.7 s) — one transition + fade to silence

| time | what happens | listen for |
|---|---|---|
| 0.00 | calm music (400 Hz) | — |
| 0.33 | ui blip over music | — |
| 4.00–4.20 | crossfade calm → combat (400 → 1000 Hz) exactly on the bar | does the swap feel on-beat? equal-power enough (no mid-fade hole/bump)? |
| 6.00–6.20 | fade to silence | linear fade acceptable? |
| 6.20–6.67 | dead silence | truly silent tail |

| axis | score (1–5) | notes |
|---|---|---|
| transition smoothness | ☐ | |
| transition timing feel (lands on the bar) | ☐ | |

## replay_music_churn.wav (7.0 s) — churn + stem reuse

| time | what happens | listen for |
|---|---|---|
| 2.00–2.20 | calm → combat crossfade (requests at 2.08 s and 2.33 s are deliberately ignored) | **nothing** may twitch after the fade completes |
| 4.00–4.20 | combat fades to silence | — |
| 4.20–6.00 | silence | truly dead |
| 6.00–6.20 | calm stem **returns from silence** (the reused stem) on the bar | clean re-entry: no click, no partial-phase blip, no early leak before 6.00 |
| 6.20–7.00 | calm at full level | — |

| axis | score (1–5) | notes |
|---|---|---|
| transition smoothness (both fades) | ☐ | |
| reuse re-entry cleanliness (6.00) | ☐ | |

## replay_spatial.wav (12.7 s) — pan extremes

| time | what happens | listen for |
|---|---|---|
| 0.17–4.17 | drone hard **LEFT** (music stays centered) | fully left? any right-ear bleed? |
| 4.33–8.33 | drone **CENTER** | dead center, same loudness as the sides? |
| 8.50–12.50 | drone hard **RIGHT** | fully right? |

Headphones recommended. Balance mode means the center segment plays in both
ears at full level — it may feel *louder* than the sides; note whether that
bothers you (it drives the pan-law question for real assets).

| axis | score (1–5) | notes |
|---|---|---|
| pan placement (left/center/right where stated) | ☐ | |
| center-vs-side loudness feel | ☐ | |

## Overall

| axis | score (1–5) | notes |
|---|---|---|
| overall mix balance (music vs sfx vs ui after the −10 dB sfx staging) | ☐ | |
| anything harsh / fatiguing | ☐ | |

Free-form notes:

>

Return the sheet (or just say scores in chat); M4 incorporates the feedback.
