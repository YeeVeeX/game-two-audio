# M5 clock-domain anchor — verdict (2026-08-19)

Closes the ONE item game-two's r2 cue-spec mail left on this seat
(`from-game-two-m5-cue-spec.md`): the integration-readiness §3 open item,
now with real-device numbers. Also closes the r1 leftover: same-tick
double-duck verification.

## Measured problem (game-two seat, 2026-08-18, two independent sessions)

Anchors at tick 1800, `gta_engine_time_pcm`, control thread only:

```
session A: tick=3600 drift=-23520 · tick=5400 drift=-48000   (90 s)
session B: tick=3600 drift=-23520 · tick=5400 drift=-49920   (90 s)
```

LINEAR ≈ 800 frames/s (tick clock ~1.7% faster than the device clock;
Gosu update cadence > 60.0 Hz). One-tick threshold crossed within ~2 s.
A boot-time anchor cannot absorb a linear rate — the contract's
re-anchor-at-music-boundaries clause is load-bearing, as warned.

## The fix (audio-side custody, integration-readiness §3 candidate, verbatim)

- `frame_for(tick) = anchor_frame + (tick − anchor_tick) * tick_frames`
  replaces bare `tick * tick_frames` everywhere on the control path
  (handle_event, update, music request).
- Engine clock read at exactly TWO anchor points: once at boot
  (construction; 0 in noDevice) and at a music transition that is about
  to schedule. Never per-command, never per-tick — the "audio thread
  never enters Ruby / clock never read on the control path" law narrows
  to its contract form: reads only at anchor points, on the control
  thread, via a diagnostic-class Native call (a pure read is not a
  command; recorder equivalence untouched).
- Re-anchor threshold: |engine_now − frame_for(tick)| **> one tick**
  (contract text "exceeds a tick"; tick_frames from engine.json — no new
  tunable). The threshold also absorbs mid-tick sampling jitter on a
  live device.
- After a re-anchor, in-flight duck windows keep their old-map absolute
  frames; update()'s release check tracks the new map, so releases land
  where the DEVICE clock meets duck_end (uniformly late pre-correction,
  exact after). Map-jumped-past-duck_end degrades gracefully (miniaudio
  evaluates the fade as partially elapsed).

## Determinism proof (Rule 2/3 discipline)

1. **noDevice inertness**: lockstep harness ⇒ engine_now == frame_for(tick)
   at every control moment ⇒ drift ≡ 0 ⇒ anchor never moves. Proven
   end-to-end: all SIX pre-existing gate pins (md5 + wav sha) byte-identical
   before/after the change; three consecutive full gate runs identical.
2. **Deterministic drift instrument**: gate runner gained an optional
   per-replay `"clock": { "advance_frames_per_tick": N }` — the noDevice
   clock advances at a skewed rate, reproducing device drift bit-exactly
   (same skew every render; double-render byte-compare still gates).
   `from_tick` windows map through the actual advance rate. Absent the
   block, behavior is unchanged (proven by the six pins).
3. **Falsification**: `replay_clock_drift` (advance 400 vs tick_frames 800 —
   brutal on purpose so the tick-domain and clock-domain bar grids diverge
   a full bar inside a 4.7 s render; the real device rate is the same
   mechanism on a longer horizon). Two transitions, both forced through
   re-anchors (drift −52000 then −60000 — proving LINEAR absorption, not
   one-shot). Pre-anchor code run against the same replay: **FAILS 9
   checks** (both post-boundary goertzel window pairs + five log counts) —
   the replay discriminates.
4. **New pins** (same-machine): replay_clock_drift md5
   `d188909ddc2feade6d2c6f6b8d77e33b` wav `8d13148a…`; replay_duck_sametick
   md5 `e591778227a0e439cae69d3dec614382` wav `3dcfe495…`. Gate is now 8/8.

## Same-tick double-duck (r1 leftover)

New cue `boss2_spawn` (mechanical name; same duck rule as boss1_spawn on
purpose — the game-side pair challenger_engaged + seal_breached shares one
frame and one depth). `replay_duck_sametick`: both cues at tick 20 ⇒ the
second apply_duck computes the SAME duck_end (degenerate pure extension,
issues nothing) ⇒ `group_fade_at bus_music == 2` (ONE attack, ONE release
at 42400), both voices audible during the hold (1500 Hz + 2100 Hz
goertzel), duck depth/recovery ratios identical to the single-duck
contract. Unit twin in audio_system_test. Listen mirror row added
(msfx_swarmpip_4s, 4 s — mirror law holds; the six pinned listen shas
unchanged, two new listen renders clean).

## Laws re-verified

- `rake`: 91 runs, 457 assertions, 0 failures (4 new anchor/duck tests,
  incl. threshold-exactly-one-tick inertness).
- Steady-state allocation law: green (frame_for is pure integer math; the
  clock read lives on the rare music-transition event path only).
- Foreign-dirty `docs/integration-readiness.md` NOT edited (its §3 open
  item is closed by this record; the file's wording updates when that
  session's work lands — AGENTS M5 note carries the status).

## Receipt

Mailed to game-two per r2 format: commit hash + drift replay pins +
double-duck confirmation.
