# vendor/ — pinned miniaudio

Pinned in M1 (2026-08-17), tag 0.11.25:
1. `miniaudio.h` — pinned release amalgamation (committed).
2. `miniaudio_impl.c` — one-line implementation TU (`#define MINIAUDIO_IMPLEMENTATION`).
3. `gta_shim.c` — our flat-C FFI surface (opaque pointers + primitives only; Ruby
   never replicates a miniaudio struct layout). Also the future home of the C-side
   command buffer (ADR escalation path).
4. Build once (RubyInstaller devkit UCRT64 gcc):
   `gcc -shared -O2 -o vendor/miniaudio.dll vendor/miniaudio_impl.c vendor/gta_shim.c`
5. Record in `vendor/VERSION`: release tag + sha256 of dll, header, and both TUs.

Law (AGENTS.md): one binary for both machines; rebuilds are deliberate (`rake dll`),
bump VERSION, and rerun the full gate.
