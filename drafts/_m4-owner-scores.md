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

## Owner feedback — M4b Reaper loop, calm slot session (verbatim, 2026-08-18)

Context: live bridge loop running; owner replaced the disposable ReaSynth on
track 1 (`mstem_calm_6s`) with their instrument of choice and tweaked it
while the region looped, then ordered the render:

> ok done I replaced vst on channel 1 for my sound of choice, already
> tweaked it while it loops, haven't test the rest, we can render this calm
> layer (maybe get different sound layers for reference or different rooms
> inside the same area, etc

Reading (dev of record): (1) first owner-designed stem enters the listen
track — `mstem_calm_6s` rendered/imported (sha `5562a026e26f…`, stem peak
−19.45 dBFS, rms −31.96 dBFS); remaining six slots stay on synthesis
placeholders (partial replacement is the loop's expected state). (2) "different
sound layers for reference" = A/B exploration — served by the existing
revision retention (`inbox/runs/<stamp>-<slot>/`, every take kept, any
retained revision re-pinnable on request). (3) "different rooms inside the
same area" = runtime music/ambience variation per zone — that is
music-state-machine schema + game-two zone events, i.e. the
`music_set_state` derivation design item in docs/integration-readiness.md;
stays PARKED with integration (recorded here so the idea isn't lost; the
listen track's mirror law keeps exactly the two pinned music states).
No presentation scores given yet; the 17 boxes remain open.

## Owner verdict — all-owner-stems listen + in-game direction (verbatim, 2026-08-18)

Context: all seven slots owner-designed (bridge loop, same session); full-set
listen sha set da2a62a1/ec8303fe/d644b61e/7229d606/f5d13763/cf2e0d99; owner
played tmp/listen renders, then:

> they sound good, I would like to test them in game so please stage them in
> a way we can merge them into the main game-two project, or what is the
> best approach? How did we plan this?

Reading (dev of record): (1) global presentation verdict POSITIVE ("they
sound good") on the all-owner material — recorded as such; the 17 per-box
scores were not returned; owner direction supersedes box-by-box scoring with
IN-GAME listening as the presentation instrument of record (the M4 verdict
names the boxes as open-by-owner-choice, not invented). (2) "stage for
merge into game-two" = the integration question — answered from the pinned
plan: evaluation stems never copy into game-two (listen-stems lane law);
runtime path = game-two-assets exports lane (its named trigger — first real
asset need — fired with this request); hearing them in game requires the
parked integration order to lift (docs/integration-readiness.md is the
runway). Handoff package staged this session; explicit order-lift question
put to the owner.
