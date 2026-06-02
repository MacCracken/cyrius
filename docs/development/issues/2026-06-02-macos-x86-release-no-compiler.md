# 2026-06-02 — x86_64-macOS: cycc SIGSYS's on real compiles (runtime arc, not just packaging)

**Filed:** 2026-06-02 (alongside the v6.0.38 arm64 packaging fix)
**Affected:** the x86_64 Mach-O runtime (`CYRIUS_MACHO=1` path) +
`.github/workflows/release.yml` `build-macos`
**Severity:** High — Intel Macs have no working compiler.
**Status:** open — **needs a runtime arc; verifiable on `ach` (Intel Mac,
Darwin x86_64, SSH-wired).**

## Two distinct problems

**1. The x86_64 Mach-O `cycc` crashes on real compiles (the blocker).**
Verified on `ach` (2026-06-02): an x86_64 Mach-O `cycc` (built `cat
src/main.cyr | CYRIUS_MACHO=1 build/cycc`) runs trivial programs
(`fn main(){return 42;}` → exit 42, so the x86 driver's auto-call-main +
exit path are fine), but compiling anything real **exits 140 (SIGSYS,
bad syscall) with 0-byte output**. Root cause: the x86_64 Mach-O syscall
layer is only *partially* translated to the Darwin BSD ABI. The arm64
path got a comprehensive `ESYSXLAT` over the full syscall surface in
v6.0.34; the x86 path (`src/backend/x86/emit.cyr` /
`src/backend/macho/emit.cyr`) only handles a few (e.g. exit =
`0x2000001` at emit.cyr:649) — `cycc`'s read/mmap/write/open/lseek/etc.
hit untranslated numbers → SIGSYS. **This is a backend runtime arc
mirroring arm64's v6.0.32–.34 BSD-ABI work, NOT a packaging patch.**

**2. The release job ships no compiler anyway.** `build-macos` builds
`cyrfmt`/`cyrlint`/`cyrdoc` but not `cycc`/`cyrius` — same packaging hole
fixed for arm64 in v6.0.38. Moot until #1 is fixed (no point packaging a
cycc that SIGSYS's).

## Why it wasn't fixed in v6.0.38 (surfaced, not punted)

The whole v6.0.32–.38 arc was arm64/ecb; the x86 Mach-O runtime is far
less exercised. Shipping it blind would repeat the exact mistake v6.0.38
was about. `ach` is now SSH-wired for verification. The scope (a syscall
ABI arc) is the user's call to slot.

## What to do (when the Intel Mac host is available)

1. Stand up the Intel Mac as an SSH verification host (peer of ecb).
2. Mirror the arm64 work for x86_64:
   - `scripts/build-macos-x86-tarball.sh` (or parameterize the arm64
     script over arch) building `cycc` + `cycc` driver + `cyrius` +
     tools as x86_64 Mach-O.
   - Point `build-macos` at it.
   - Premise-check the x86 macho driver for the same stale-fork bugs the
     arm64 driver had (v6.0.33 entry prologue, v6.0.37 auto-call-main) —
     `src/main.cyr` is the x86 driver; confirm its macho path calls
     `main()` and propagates the exit code.
3. Add the x86 arm of the `cyrius audit` real-install gate against the
   Intel Mac (mirror the ecb install check).
4. Verify the REAL install on the Intel Mac: `install.sh` → `cyrius
   build fn-main-return-42` → exit 42. Do not close until that passes.
