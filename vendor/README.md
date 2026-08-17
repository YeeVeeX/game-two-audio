# vendor/ — pinned miniaudio

Arrives in M1, first spike step:
1. Download the pinned miniaudio release amalgamation (`miniaudio.h` + a one-line
   `miniaudio_impl.c` defining `MINIAUDIO_IMPLEMENTATION`) — commit BOTH.
2. Build once (MSYS2 UCRT64): `gcc -shared -O2 -o vendor/miniaudio.dll vendor/miniaudio_impl.c`
3. Record in `vendor/VERSION`: miniaudio release tag + `sha256sum miniaudio.dll` output.

Law (AGENTS.md): one binary for both machines; rebuilds are deliberate (`rake dll`),
bump VERSION, and rerun the full gate.
