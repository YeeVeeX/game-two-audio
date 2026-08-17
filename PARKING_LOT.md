# Parking lot — named triggers, never silent scope creep

- **Integration into game-two** — TRIGGER: owner lifts the audio order (game-two
  AGENTS.md "OUT of scope: audio"). Until then this repo only reaches
  integration-readiness: event contract + gate + PoC.
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
