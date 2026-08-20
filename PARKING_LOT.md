# Parking lot — named triggers, never silent scope creep

- **Integration into game-two** — TRIGGER FIRED 2026-08-18: owner lifted the audio
  order in writing ("audio order lifted", `drafts/_m4-owner-scores.md`). Integration is
  LIVE on the game-two side — its M5a lane consumes owner audio (game-two commits
  `34bec50`/`eaf5e9b`/`dd84010`, cited in `handoff/audio-v12/BANKED.md`); cue mapping
  proceeds iteratively in game-two custody.
- **HRTF / binaural spatialization** — TRIGGER: 2D pan+attenuation proves insufficient
  in a real playtest verdict. miniaudio has spatializer support; not before.
- **Occlusion via map raycasts** — TRIGGER: a zone design where the LPF-proxy audibly
  lies. Needs game-two map data access; parked with integration.
- **Runtime asset hot-reload** — TRIGGER: iteration friction demonstrated in a session
  log (cold restart cost measured, not felt).
- **C-side command buffer (one FFI flush/tick)** — TRIGGER: ADR spike item 3 fails the
  0.5 ms p95 bound (this is the ADR's named escalation path).
- **Network-relevant audio (positional voice, synced music start)** — TRIGGER: game-two
  always-online fork unparks (its own named trigger).
- **FMOD reconsideration** — TRIGGER: spike falsifies miniaudio AND SoLoud; requires a
  fresh first-party read of fmod.com/licensing + /attribution (terms were UNVERIFIABLE
  2026-08-17, JS-walled).
- **game-two-assets audio export lane** — TRIGGER: first real (non-tone, non-MIDI-stem)
  asset need; coordinate with that repo's manifest pipeline, don't improvise formats.
- **Master limiter (custom C node)** — TRIGGER: owner listen verdict says the data-staged
  headroom (M3: sfx −10 dB, −1 dBFS ceiling pinned per replay) audibly hurts the mix, or
  real assets overflow the budget. A limiter = DLL rebuild = vendor-law ceremony; re-ask.
- **LUFS (K-weighted) metering in the gate** — TRIGGER: asset handshake with
  game-two-assets decides loudness conformance is gated here rather than in the export
  pipeline (docs/integration-readiness.md §4).
- **Distance-attenuation DSP** — TRIGGER: game design asks for it; :distance payload is
  already plumbed as pool-steal metadata; the DSP needs a cue-table field + gate replay.
- **Footstep-material cue family** — TRIGGER: game-two's builder-era cue-spec mail
  arrives with material-keyed movement events (its Lane 3 tile-type registry, game-two
  `2471b5d`; heads-up mail `done/from-game-two-worldbuilder-cue-families.md`). Flagged
  concerns carried: step spam needs a cheap voice/priority lane or cadence gate;
  per-material render sets reuse the attack-cue-spec handoff shape.
- **Region-ambience beds** — TRIGGER: same lane (heads-up mail above); decide a
  music_set_state-adjacent surface vs a second ambient bus AT SPEC TIME, not before.

Itexo vocabulary bank (2026-08-18, `docs/itexo-audio-vocabulary.md`; source addendum md5
`cabd71a8f8a4a0cedee1410ef98e9099`; the integration unpark above FIRED 2026-08-18 — each
slot now waits on its own per-slot trigger):

- **S1 telegraph_pre_cast — per-ability telegraph cues, fixed lead** — TRIGGER: integration
  unparks and game-two's telegraphed-ability events get cue decisions (addendum §2.3).
  Accept: replay pins telegraph-cue onset exactly K ticks before its ability event, every
  cycle, per-ability log op-counts distinct.
- **S2 deny_* — three-cue denial taxonomy (lane A / lane B / empty)** — TRIGGER: integration
  unparks and game-two exposes which denial fired (event or payload discriminator; §2.9 +
  §2.2 empty-resource line). Accept: interleaved-spam replay pins each denial type to its
  own cue by log op-counts, RMS window proves micro-cue (no stacking).
- **S3 low_stock_* — consume-cue escalation bands + last-few warning** — TRIGGER: a counted
  consumable event carries a stock payload; needs a cue-schema variant-band field (same
  shape as distance-attenuation's parked field) (addendum §2.2). Accept: stock 30→0 sweep
  replay pins band switches at table thresholds via per-variant log op-counts.
- **S4 milestone_stinger_* — minor/major/award ceremony tiers** — TRIGGER: game-two lands
  milestone/ceremony events (its triage action 4) and integration unparks (addendum §2.6,
  staging lesson §2.11). Accept: three-tier replay proves tier-distinct cues with
  tier-scaled duck (award duck strictly longest) via log + group_fade_at counts.
- **S5 register_yield/register_none — honest ledger-tick pair** — TRIGGER: integration
  unparks and the yield/no-yield discriminator is decided (event or payload) with game-two
  (addendum §2.9 instrument-trust + §2.1). Accept: alternating replay pins register_none to
  empty-loot payloads only; RMS asserts the dry variant measurably smaller than yield.
