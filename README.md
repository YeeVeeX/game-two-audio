# game-two-audio

Audio foundation for the game-two program: **miniaudio bridged via ruby-ffi**, developed
to integration readiness OUTSIDE the game-two repo (owner order).

- Ground truth + laws: `AGENTS.md`
- The decision + falsification list: `docs/adr/0001-audio-foundation.md`
- Council review record: `drafts/_council-reconciliation-adr1.md`

## Quick start

```bash
export PATH="/c/Ruby34-x64/bin:$PATH"
bundle install
rake            # tests
```

Current milestone: **M1 spike** — prove the five ADR falsification items before any
system code grows. See AGENTS.md.
