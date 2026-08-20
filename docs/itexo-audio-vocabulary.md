# Itexo audio-design vocabulary — banked 2026-08-18 (integration-readiness input)

**Status: vocabulary bank only. PARKED with integration (owner order).** No cue
tables, code, or replays change on this bank; each slot unparks per its
PARKING_LOT.md trigger.

**Source:** `gamesmith/docs/itexo-corpus-addendum.md`
(md5 `cabd71a8f8a4a0cedee1410ef98e9099`, verified at banking), routed here by
game-two triage `game-two/drafts/_itexo-intake-triage-20260818.md` (route
manifest row: game-two-audio). Citations below are addendum sections.

**Era caveat (applies to every slot):** evidence is 2019-era Tibia-12 footage,
creator-edited stream montages — and the "audio" evidence is mostly *textual*
(screen text standing in for what a modern game would voice/sound). Each slot
is a **slot to fill, not a sound to copy**. Footage-derived; cite, don't
redistribute. Repo laws hold: mechanical cue ids only, data-driven tables,
audio stays a pure event sink.

Naming below: slot ids and candidate cue ids are mechanical placeholders
(non-negotiable 6). Game-fiction names from the source corpus are not used;
one corpus line is quoted verbatim as attributed evidence.

---

## S1 — telegraph_pre_cast: per-ability telegraph lines/stings with fixed lead time

- **Evidence (§2.3, item 5):** the boss shouts a fixed incantation ("CHAMEK ATH
  UTHUL ARAK!" — corpus quotation) before a room-blanketing fire field, every
  cycle. §2.3's mapping calls telegraph-by-utterance the cheapest dodge-enabling
  telegraph a solo-dev game can ship.
- **Slot:** a reliable pre-cast audio channel — per-ability telegraph cue,
  distinct per ability, with a *fixed, data-declared lead time* long enough to
  react. Cue table gains a lead-time relationship between a telegraph cue and
  its ability event; distinctness per ability is a table property, not code.
- **Already in place:** `telegraph`, `respawn_telegraphed`,
  `challenger_chant_started` sit in the game-two whitelist
  (integration-readiness §1); stinger+duck archetype exists (boss1_spawn).
  Missing piece is the *fixed-lead pairing* assertion, and possibly
  schedule-ahead start so the lead is tick-exact.
- **Acceptance idea:** gate replay drives N telegraph→ability cycles; cue-timing
  assertions pin telegraph-cue onset exactly K ticks before each ability event,
  every cycle, with per-ability log op-counts proving distinct cues.

## S2 — deny_*: three-cue denial feedback taxonomy

- **Evidence (§2.9, first two bullets; empty-resource line in §2.2):** two
  independent throttles fire as distinct rejection lines — spell-lane cooldown
  ("You are exhausted.") vs item-rate throttle ("You cannot use objects that
  fast.") — plus resource-empty ("You do not have enough mana."). §2.9's
  anti-pattern note: tempo learned by spam-and-reject via log text only.
- **Slot:** three distinct micro-sound identities — `deny_lane_a` (action-lane
  cooldown), `deny_lane_b` (item-lane throttle), `deny_empty` (resource empty) —
  so tempo becomes learnable by ear instead of log-reading. Empty ≠ cooldown is
  the load-bearing distinction (different player responses: wait vs re-provision).
- **Already in place:** `provision_refused → ui deny blip` row in
  integration-readiness §1; ui_confirm archetype (toll_paid). Missing: the
  three-way taxonomy and a payload/event discriminator for *which* denial.
- **Acceptance idea:** replay interleaves all three denial events under spam
  cadence; log op-counts pin each event type to its own cue file, and a
  short-window RMS assertion proves the cues stay micro (no duck, no tail
  stacking under spam).

## S3 — low_stock_*: attrition escalation on counted consumables

- **Evidence (§2.2):** counted stacks deplete under pressure (~1,030 entry stock;
  burn bursts 1713→1509 in ~24 s; session ends at 13 remaining with "no Have
  mana potion" — the session ends in the ledger, not the death screen).
- **Slot:** low-stock audio escalation — the consume cue thins/sharpens as the
  stack runs down (data-driven variant bands keyed on a stock-count payload),
  plus a distinct last-few warning cue. The escalation curve is a table, not
  code; variant selection happens at event time from payload.
- **Already in place:** `provision_used` in the whitelist; payload-keyed
  behavior exists (pan/distance pattern, §2 of integration-readiness). Missing:
  variant-band cue-table field (nearest existing mechanism: none — this is the
  one slot needing a small cue-schema extension, same shape as the parked
  distance-attenuation field).
- **Acceptance idea:** replay sweeps stock 30→0 on a fixed cadence; per-variant
  log op-counts pin band switches exactly at table thresholds, and the last-few
  cue fires exactly once per band entry.

## S4 — milestone_stinger_*: three-tier ceremony stinger family

- **Evidence (§2.6; staging note §2.11 third bullet):** milestone produces a
  sequence — confetti congratulations event, personalized minted trophy, a
  communal countdown ritual. §2.11's negative lesson: the *ceremony is the
  content* (the thing behind the decade-gate was thin) — so if the trophy is
  the point, stage the ceremony deliberately.
- **Slot:** milestone stinger family with three tiers — `milestone_minor`
  (small advance), `milestone_major`, `milestone_award` (minted-award
  ceremony) — tier is a data property; the award tier earns the biggest
  staging (longest duck, longest tail), because ceremony staging is the
  corpus-proven payoff.
- **Already in place:** stinger+duck archetype (boss1_spawn) and the duck
  machinery (M3: hold-extension overlap semantics pinned). Missing: tier
  family and the events (game-two has no milestone events in today's
  whitelist — trigger depends on triage action 4 landing there).
- **Acceptance idea:** replay fires all three tiers; log op-counts +
  `group_fade_at` counts prove tier-distinct cues with tier-scaled duck
  (award tier's duck window strictly longest), accuracy scored per gate, tier
  *feel* deferred to the owner-listen axis.

## S5 — register_yield / register_none: economic registration beat

- **Evidence (§2.9 last bullet; §2.1 honest-ledger thesis):** stale trackers
  are called fatal for a game whose thesis is auditing your own wager — the
  registration beat must be tick-accurate. Post-engagement loot registration
  includes explicit empty results (routed description: loot lines including an
  explicit "nothing"), and honest negative outcomes are the direction thesis.
- **Slot:** ledger-tick sound identity for post-engagement registration —
  `register_yield` plus a *dry, honest* `register_none` variant. The no-yield
  variant is the design payload: silence would read as a missed event; a
  distinct dry tick keeps the ledger audibly honest.
- **Already in place:** `banked`/`corpse_looted → ui confirm / one-shot` rows;
  ui_confirm archetype. Missing: the yield/no-yield discriminator (event or
  payload — integration-time decision) and the deliberately-dry no-yield cue.
- **Acceptance idea:** replay alternates yield and empty registrations; log
  op-counts pin `register_none` to empty-loot payloads only, with an RMS
  assertion that the dry variant stays strictly smaller/shorter than yield
  (dry by measurement, not adjective).

---

## Cross-cutting notes for integration time

- S1/S2/S5 map onto whitelist events that already exist; S3 needs a payload
  convention; S4 needs game-two-side events (triage action 4). None of the
  five requires DLL work — all are cue-table + (for S3) one schema field +
  replays. No limiter, no new engine features.
- All five produce *fixture-tone* gate replays first (standing law: gate
  replays stay tone-based); real asset identity arrives via the
  game-two-assets handshake (integration-readiness §4).
- Presentation axis (does the denial taxonomy read as three sounds? does the
  award stinger feel minted?) is owner-listen material — same two-axis scoring
  as M4.
