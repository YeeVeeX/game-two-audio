# M4 owner listen feedback — verbatim record (2026-08-19)

**Provenance**: owner (Gabriel) in session chat, 2026-08-19, after playing the
six `tmp/gate/replay_*.wav` renders (regenerated this session, hash set
identical to the M3 pins; folder opened for the owner via Explorer). Player
used: not stated.

## Verbatim feedback

> they all sound like a constant hum, or high pitch drone, doesn't sound good
> at all, I prefer we use Reaper and our musical/audio knowledge for better
> results

## Score boxes

**All 17 boxes returned UNSCORED.** The owner did not score per-axis; the
feedback is a global verdict on the renders as heard. No number below is an
owner score; nothing here is agent-scored (a machine cannot score
presentation).

## Reading (dev of record — kept separate from the verbatim record)

- The renders ARE pure sine fixtures (by design: 400/500/880/1000/1500/2100 Hz
  stand-ins; the sheet's "score the behavior, not the tone quality" caveat).
  The owner's description — constant hum / high-pitch drone — is an accurate
  description of the fixture material itself.
- **Finding: the listen instrument failed, not (necessarily) the behaviors.**
  "Score behavior through raw sines" proved not humanly executable — the
  material swamps the behaviors under evaluation (duck feel, steal transient,
  crossfade smoothness, balance). The presentation axis therefore remains
  OPEN: the sub-questions (steal click? re-attack stutter? sfx too quiet at
  −10 dB?) are still unanswered by ears.
- **Presentation gate status: FAIL on fixture material** (global owner verdict
  "doesn't sound good at all"), boxes unscorable through this material. This
  is a listen-instrument defect to fix, not an engine defect: no evidence in
  this feedback touches the miniaudio/FFI decision (ADR 0001 ACCEPTED), the
  gate corpus accuracy pins, or the pinned behaviors.
- "Use Reaper" = asset-production direction, not a runtime direction (Reaper
  does not run in-game). Owner musical judgment enters through better fixture
  material + the tuning decisions the re-listen will drive (duck depth, fade
  lengths, balance staging — all data/audio/*.json values).

## Owner follow-up (verbatim, same session)

> audio and music

Read with the prior message ("use Reaper and our musical/audio knowledge"):
owner directs the musical listen track forward, using the curated audio/music
knowledge (KB music-production domain) as the production guide. Immediate stem
source = generated musical stems (midi-writing-mcp unavailable in this harness
→ deterministic in-repo synthesis); owner Reaper stems stay open as the
replacement path via a written spec.

## Triage (AGREED direction — musical listen track)

Two-track fixture split:

1. **Accuracy corpus stays sine** — goertzel bins / float-exact zeros /
   coherent-sum arithmetic require spectrally pure, phase-deterministic
   material. 6/6 green, hashes pinned, untouched.
2. **New musical listen track** — same engine, same choreography, musical
   stems; renders for ears only:
   - source (a): `midi-writing-mcp` generated stems (contract-sanctioned,
     immediate);
   - source (b): owner-produced Reaper stems to a written spec (in-house =
     no copyright issue; mechanical placeholder filenames; previews the
     game-two-assets export lane).
   Owner re-listens against a re-cut sheet; scores then drive M4 fixes.

Constraints that hold regardless: no copyrighted audio ever; placeholder
mechanical names; tunables in data, not code; engine/DLL untouched (no
rebuild on taste grounds); integration stays PARKED.

## Owner feedback — take 2, musical listen track (verbatim, 2026-08-19)

> they sound better, still too simple for my taste, I would like to be able
> to select and tweak my sounds on my plugins or run the midi through my
> analog synths, what is the best approach? we can use those you made as
> placeholders in the meanwhile for the prototype, but I still here some
> constant string-like sound in the back of each of those sounds not sure if
> that is intended or not

Reading (dev of record): (1) direction improved; material still too simple —
per-box scores STILL OPEN; (2) owner wants a plugin/analog-synth production
loop (MIDI out of the repo, rendered audio back in) — design question,
answered + built same session (MIDI export of the placeholder compositions +
file-type fixture return seam); (3) synthesis placeholders ACCEPTED as the
prototype interim — material-quality complaint does NOT gate the behaviors
re-listen; (4) possible defect report: "constant string-like sound in the
back of each" — investigated mechanically same session; verdict recorded in
the M4 verdict + explained to the owner (calm-pad sustained root drone —
intended composition, with the churn silent-window ear-discriminator offered
and a data knob named if it still bothers).
