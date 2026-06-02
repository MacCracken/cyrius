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

## UPDATE 2026-06-02 — diagnosed on `ach`; LAYERED, 2 of N fixes landed

Verified on `ach` (Intel, Darwin 13.7.8). The "SIGSYS on real compile" is
NOT one bug — it's a stack of Linux-startup assumptions in the x86 driver
(`src/main.cyr`), the same class that forced arm64 to get a dedicated
driver (`main_aarch64_macho.cyr`). Pinned by checkpoint-bisecting the
macho cycc startup. Exit code walked 140 → 139 as each layer was fixed:

- **Layer 1 — heap bootstrap via `brk` (FIXED).** `main.cyr` opened with
  `var S = syscall(SYS_BRK, 0)` — the FIRST syscall cycc makes. Darwin has
  no brk → SIGSYS at instruction one (before any output). Fixed with an
  `#ifdef CYRIUS_TARGET_MACOS` mmap branch mirroring the arm64 driver
  (`syscall(9, 0, 0x4D9D000, 3, 0x1002, -1, 0)`). x86 ELF self-host stays
  byte-identical (gated).

- **Layer 2 — x86 syscalls untranslated (FIXED, partial coverage).** The
  x86 backend only pre-classed `exit` (0x2000001 in EEXIT); every other
  syscall carried a raw Linux number → SIGSYS. Added `EMACHO_SYSXLAT`
  (`src/backend/x86/emit.cyr`) — the x86 analog of arm64's `ESYSXLAT`:
  emitted inline before each `syscall` instruction when `_TARGET_MACHO==1`,
  it rewrites rax (Linux number) → `0x2000000 | <BSD number>`. Covers
  read/write/open/close/stat/fstat/lseek/mmap/mprotect/munmap/access/getpid/
  execve/exit/wait4/fcntl/ftruncate/rename/mkdir/rmdir/unlink/symlink/
  readlink/chmod. Args already match (Darwin x86_64 = rdi/rsi/rdx/r10/r8/r9,
  like Linux). NOTE: `fork` (rdx-distinguishes-child quirk) and
  `clock_gettime`/228 are NOT yet covered — the wrapper's process spawn
  will need fork; cycc self-host does not.

- **Layer 3 — `/proc/self/cmdline` arg parsing (OPEN — the current SIGSEGV).**
  With 1+2 fixed, cycc now reaches its arg parser and SIGSEGVs (139).
  `main.cyr:~493` reads `/proc/self/cmdline` to scan for `--version` /
  `--strict`. **macOS has no `/proc`.** Worse, Darwin returns errno via the
  **carry flag with a POSITIVE rax** (not Linux's negative return), so the
  failed `open` yields `_vfd = 2` (ENOENT) — treated as a valid fd — then
  `read(2, …)` returns a garbage length and the arg-walk loop runs off the
  256-byte stack buffer → SIGSEGV. Confirmed by checkpoint: `CP0` (entry,
  pre-cmdline) prints; `CPm` (post-cmdline, pre-heap) does not.

- **Layer 4+ — `_read_env` / envp (LIKELY OPEN, after layer 3).** cycc reads
  env vars (CYRIUS_MACHO etc.) off the entry stack; Darwin's stack layout
  (argc/argv/envp/**apple**[]) differs from Linux. The arm64 driver uses a
  dedicated `_macho_fill_environ`; the x86 driver will need the same. Not
  yet reached (layer 3 crashes first).

### Architectural fork for the fix (project-leader call)

The arm64 path solved this with a **dedicated** `main_aarch64_macho.cyr`
driver. The x86 path is currently reusing `main.cyr` with `#ifdef`s. The
two viable shapes:
  (a) keep `#ifdef`-ing `main.cyr`'s startup (cmdline → stack-argv, errno
      convention, envp) — smaller diff, but main.cyr accretes macho special
      cases; OR
  (b) split a dedicated `main_x86_macho.cyr` driver (peer of the arm64
      one) — cleaner separation, more duplication.
Both need: stack-argv parsing (no /proc), Darwin errno-convention handling,
macho envp reading, and the fork rdx-quirk for the wrapper. Decide before
continuing.

### Landed this session (gated, inert on ELF/Linux)
- `src/main.cyr`: `#ifdef CYRIUS_TARGET_MACOS` mmap heap bootstrap.
- `src/backend/x86/emit.cyr`: `EMACHO_SYSXLAT` + `_msx` helper, wired into
  `ESYSCALL`. x86 ELF self-host verified byte-identical.
