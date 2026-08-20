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
