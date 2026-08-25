# handoff/audio-v13 — banked 2026-08-25

T3 footstep intake, first delivery: the STONE material arrived as an
8-take rotation family (owner chose 8 takes over the spec's 1 — richer
rotation, same contract; game-side randomization per the variants.json
precedent, their custody).

All owner originals: performed by the owner in his Reaper session
(Arturia Pigments patch, one performance note per take), rendered
per-region through the live bridge at PCM 24-bit mono 48 kHz,
0.150 s = 7,200 frames exactly (data_bytes=21600 each). Header-verified
(RIFF walk) + peak-measured at intake; every take sits below the v12
throw family reference peak (−14.70 dBFS) per the "bajitos" law from the
T3 cue-spec mail.

- `msfx_step_stone_150ms_a.wav` — take a (peak −15.96 dBFS)
  - Source sha256:
    `8e7890ee567cc902c9ee0a9d5c1333784e2a0056b1bfa2f13252ea373fb52ec1`
  - Game-side 16-bit sha256: PENDING (lands with game-two's commit)
- `msfx_step_stone_150ms_b.wav` — take b (peak −16.79 dBFS)
  - Source sha256:
    `b9ab80603c53ffb9e1741721c8fa892b20301f28d46512409a0dd22def569372`
  - Game-side 16-bit sha256: PENDING
- `msfx_step_stone_150ms_c.wav` — take c (peak −17.36 dBFS)
  - Source sha256:
    `62429845701c7f30e273c05d2792ea80280f8037c7ce91a513bdf89d22a3cff9`
  - Game-side 16-bit sha256: PENDING
- `msfx_step_stone_150ms_d.wav` — take d (peak −17.36 dBFS)
  - Source sha256:
    `346d9af6af61d19dec91028e05999fbcd5003ea9539e3e065cbfae0b9d4b83b3`
  - Game-side 16-bit sha256: PENDING
- `msfx_step_stone_150ms_e.wav` — take e (peak −15.12 dBFS)
  - Source sha256:
    `c13916143c7e7049acf7f1eb59a1e33d3c0145d829f0b8702e1d060eab4b7746`
  - Game-side 16-bit sha256: PENDING
- `msfx_step_stone_150ms_f.wav` — take f (peak −18.94 dBFS)
  - Source sha256:
    `3a93358445b9a8a4ab4895d7711302cdf5f56f94a425caf4e669abc804c90cff`
  - Game-side 16-bit sha256: PENDING
- `msfx_step_stone_150ms_g.wav` — take g (peak −17.39 dBFS)
  - Source sha256:
    `0a09e8ef6c4cbf3a47f12a2e4e1528c33a325284c90bfbb56750c4f2f99d0cf6`
  - Game-side 16-bit sha256: PENDING
- `msfx_step_stone_150ms_h.wav` — take h (peak −18.97 dBFS)
  - Source sha256:
    `bd512347c8fd45eb798b493ebbad77b2826caa6e36e78ec8d19caa72a16f1dc3`
  - Game-side 16-bit sha256: PENDING

Still owed to v13 as the owner records (his pace): `msfx_step_dirt/`
`grass/wood_150ms`, `mamb_meadow/town/dungeon_30s` beds, and the
`msfx_calm_evolving_64s` loop-aware re-render (seam mail 2026-08-24;
2×-render work area staged at 452–580, region renders the second pass).

Convention: sources bank here (mirrors audio-v12); game-side carries the
converted 16-bit copies; PENDING lines fill in when game-two cites its
commits back.
