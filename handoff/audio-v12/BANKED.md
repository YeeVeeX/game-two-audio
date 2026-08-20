# handoff/audio-v12 — banked 2026-08-20

- `msfx_calm_evolving_64s.wav` — owner original (ask 8, game-two M5a
  verdict §Ear-check 2): two-layer evolving calm music loop, master mix
  rendered in the owner's Reaper session.
- Format: PCM 24-bit mono 48 kHz, 64.000 s (32 bars @ 120 bpm),
  9,216,690 bytes. Header-verified (RIFF walk: data_bytes=9216000).
- Source sha256 (this file, 24-bit original):
  `d2148df778a644ec546879757190d7e6f87a0faba7ff6b3b9eff166930c9d723`
- Game-side 16-bit copy sha256 (converted, lives in game-two):
  `6fe9a1a805cb0cb644d5c8f4d88a7270377a87a353b46c1d002e2543d60380e4`
- Game-two commit carrying the 16-bit copy + fixture pin: `34bec50`.
- Convention: sources bank here (mirrors audio-v1/audio-v1.1); game-side
  carries the converted 16-bit copies.

## Banked 2026-08-20 (second pass — zone-change + throws)

All owner originals, PCM 24-bit mono 48 kHz, header-verified (RIFF walk).

- `mui_zone_change_1200ms.wav` — owner original (ask 7): zone-change UI
  render, 1.200 s (data_bytes=172800).
  - Source sha256:
    `9a135062675c5b0938d7bb6b084796c7695473531e86aa1bef49f78fbe1e61c5`
  - Game-side 16-bit sha256 (game-two `eaf5e9b`):
    `91090005d1caf7a51ac815e336f96dac155e370dd87b014d7c5f4331b6c230bd`
- `msfx_throw_1800ms_a.wav` — owner original (ask 9): throw take a with
  baked reverb tail, 1.800 s (data_bytes=259200).
  - Source sha256:
    `069a319318ace36b0841a1749861a634359aa4833e95b2762813e3e60f0ca7b5`
  - Game-side 16-bit sha256 (game-two `dd84010`):
    `72c390200ad2aaca572794416e65c63a9560b58d3f67399a6aa45edbce1e5503`
- `msfx_throw_1800ms_b.wav` — owner original (ask 9): throw take b with
  baked reverb tail, 1.800 s (data_bytes=259200).
  - Source sha256:
    `72148d1042a98737f720dbed72d0ff9f8144a22112748521dda7d755a9f5ff33`
  - Game-side 16-bit sha256 (game-two `dd84010`):
    `41c32677a224820f0497b793d9c4d9c4de79c0373352a3f27a3028a18f14b8eb`
- `msfx_throw_1800ms_c.wav` — owner original (ask 9): throw take c with
  baked reverb tail, 1.800 s (data_bytes=259200).
  - Source sha256:
    `aa3a580a66eb29910c30b90206acccd26858789bb7484804812370ca68cee9e2`
  - Game-side 16-bit sha256 (game-two `dd84010`):
    `3390935e34c637464bc79fa4d6a54b2db30881b0543438f9fa97008005e563ec`
- `msfx_throw_1800ms_d.wav` — owner original (ask 9): throw take d with
  baked reverb tail, 1.800 s (data_bytes=259200).
  - Source sha256:
    `94f7ed277edd176fc304403e5a2a40733c81b8df5f88b8b4bc3c872c4387723f`
  - Game-side 16-bit sha256 (game-two `dd84010`):
    `e7f7bbc4d21b8d7bd90d289ba3a9b9d3708951bd4b6dddb4e643485638bc40f7`

Note: the old 200 ms throw sources (`msfx_throw_200ms_*.wav`) were never
banked — superseded pre-banking by the owner's tail decision.
