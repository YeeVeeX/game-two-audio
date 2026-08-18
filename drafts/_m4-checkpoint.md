# M4 checkpoint — waiting on owner listen (2026-08-19)

**Status: entry-gate case (c) — no owner scores available this session.** The
owner was offered the walkthrough in chat and deferred. Per the M4 contract
there is no other M4 work: no replays invented for proven behaviors, no
taste-driven data tuning without ears, no parked items touched. Session closed
clean after the floor check.

## Entry-gate evidence (checked this session)

- `drafts/_m3-listen-sheet.md`: every score box blank (`☐`), file untouched
  since its creation commit d0453e8 (verified via `git log -- <sheet>`).
- No scores in chat; no owner-scores file in `drafts/`.
- Nothing was scored by the agent (a machine cannot score presentation — that
  is the axis this milestone exists to close).

## Floor check (all green, this session, HEAD 7fd9188)

- `git pull --ff-only`: already up to date; working tree clean.
- `bundle exec rake`: 50 runs / 228 assertions, 0 failures.
- `bundle exec rake spike`: 5/5 (spike-01 floor intact).
- `bundle exec rake gate`: 6/6 PASS, run twice in separate processes —
  md5/hash set identical to the M3 pinned table both times:

| replay | log md5 | peak (dBFS) |
|---|---|---|
| replay_cues | 6e52c7cb9b636388269ad02840a7eee8 | −3.94 |
| replay_duck_overlap | 306f5a41231b9f42be2a884542fb66f6 | −5.45 |
| replay_music | 34f9c630493d4a318d1dc517132ffacf | −6.92 |
| replay_music_churn | 228403226b6581606047df35b53670b5 | −12.02 |
| replay_spatial | 39e7aec56b8bf247bf48882990f318ef | −9.25 |
| replay_ui_cap | 478e5a5c0ca35479ca534b73488ca10e | −1.76 |

over-1.0 = 0 on all six; −1 dBFS ceiling (0.8913) holding on every replay.

## What M4 is waiting for

Owner plays the six WAVs against `drafts/_m3-listen-sheet.md` (17 boxes,
~38 s of audio total; f32-capable player — Audacity/VLC/foobar2000;
headphones for replay_spatial). WAVs live in `tmp/gate/` (not committed) —
regenerate bit-identically any time with `rake gate`.

Scores return via sheet edits or chat. Next session then follows
`drafts/_next-session-m4-listen-closure.txt`: record scores VERBATIM into
`drafts/_m4-owner-scores.md` → triage matrix (sub-3 box = presentation-gate
FAIL, fix lands with its regression guard) → headroom closure (the standing
question: does sfx sit too quiet at −10 dB?) → verdict + AGENTS cycle update.

Pre-thought fix designs (steal micro-fade dying-ring, sfx restage −10 → −8
arithmetic, duck retune, pan-law/crossfade-curve scope-break re-asks) are in
the next-session prompt; none built speculatively.

## Standing constraints (unchanged)

- Integration PARKED on owner order; `docs/integration-readiness.md` is the
  runway, not permission.
- Limiter / LUFS / distance-DSP / pan-law stay parked behind their named
  triggers (PARKING_LOT.md); a limiter or pan-mode change = DLL rebuild =
  re-ask with the failing score as evidence.
- Knowledge-repo correction queue (SDL_AUDIODRIVER timing, empty-graph read,
  started-groups starvation, spike-04 sha provenance) stays queued for a
  knowledge session.
