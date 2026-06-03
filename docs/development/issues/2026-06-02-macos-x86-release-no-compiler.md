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

## UPDATE 2026-06-02 (cont.) — layer 3 FIXED, layer 4 pinned → dedicated-driver call

Continued on `ach`. Checkpoint-bisected the post-140 SIGSEGV.

- **Layer 3 — `/proc/self/cmdline` arg parse (FIXED).** cycc scanned
  `/proc/self/cmdline` for `--version`/`--strict`/`--lex-ts`. macOS has no
  `/proc`; the failed `open` returns errno via Darwin's **carry-flag
  convention (POSITIVE rax)**, so the Linux-shaped `if (_vn > 0)` guard
  fired on garbage and the arg loop walked off the 256-byte stack buffer.
  Fixed: `#ifdef CYRIUS_TARGET_MACOS` skips the `/proc` scan (`_vn`=0). cycc
  now clears cmdline + heap + `_init_cyrius_lib` on `ach` (verified by
  checkpoint: CP-heap, CP-init print). `--version`/`--strict`/`--lex-ts`
  from argv on macho need stack-argv (layer 4). x86 ELF self-host
  byte-identical (gated).

- **Layer 4 — `_read_env` / argv parking (OPEN — the current SIGSEGV; needs
  the dedicated-driver decision).** Next crash is in `_read_env`
  (`backend/common/runtime.cyr`). Its `#ifdef CYRIUS_TARGET_MACOS` branch
  calls `_macho_x28()`, whose body is **arm64 inline asm** (`mov x0, x28`)
  — on x86 those bytes decode to garbage and there is no parked argv base,
  so `load64(garbage)` → SIGSEGV. `_macho_argv_base()` (lib/args_macos.cyr)
  has the same arm64-only asm. The arm64 fix (v6.0.33) was a **driver entry
  prologue** (`stp x0,x1,[sp,#-16]!; mov x28,sp`) parking argc/argv, read
  back via `_macho_x28()`.

  **Why this forces the architecture decision:** the prologue must be the
  first instructions of cycc's OWN `.text`, but `main.cyr`'s entry sequence
  is emitted by whatever compiler builds cycc — and a Linux `cc_x` (built
  without the macho prologue branch) won't emit it into the first
  x86-macho cycc, so that cycc can't run to self-host the prologue in
  (chicken-and-egg). arm64 sidestepped this with a **dedicated
  `main_aarch64_macho.cyr`** whose prologue + macho specifics are
  unconditional top-level emit. The x86 path almost certainly wants the
  same: a **dedicated `main_x86_macho.cyr`** (peer of the arm64 driver)
  rather than continued `#ifdef`-ing of `main.cyr`. RECOMMEND adopting the
  dedicated driver for layer 4 onward.

### Landed so far (gated, ELF self-host byte-identical)
- Layer 1: mmap heap bootstrap (`main.cyr`).
- Layer 2: `EMACHO_SYSXLAT` (`backend/x86/emit.cyr`).
- Layer 3: skip `/proc/self/cmdline` on macho (`main.cyr`).
Remaining: layer 4 (argv parking / `_read_env` / `_macho_x28` x86) — pending
the dedicated-driver call — then envp + the `--version`/`--strict` flags.

## UPDATE 2026-06-02 (cont.) — dedicated driver built; layers 1-4 cleared; layer 5 = PREPROCESS crash

Per the architecture decision, created **`src/main_x86_macho.cyr`** — a lean
dedicated x86 Mach-O driver (peer of `main_aarch64_macho.cyr`). It hardcodes
`_TARGET_MACHO=1` + `CYRIUS_TARGET_MACOS`, mmaps the heap, skips `/proc`, and
includes the x86 backend (+ `pe/emit.cyr` for the `_pe_text_rva` symbols
`x86/fixup.cyr` references). Also made `_macho_x28()` (runtime.cyr) and
`_macho_argv_base()` (lib/args_macos.cyr) return **0 on `#ifdef
CYRIUS_ARCH_X86`** so `_read_env`/`args_init` fall through safely instead of
running arm64 asm (`mov x0,x28`) as x86 garbage.

Result on `ach`: cycc now clears heap → `_init` → predefines, and reaches
**PREPROCESS** — i.e. layers 1-4 (brk, syscall xlat, /proc, _read_env) are
all resolved. New crash:

- **Layer 5 — SIGSEGV inside `PREPROCESS(S)` (OPEN).** Checkpoints: CP-heap,
  CP-prePP print; a heap-write probe at `S+0x459D000` AND `S+0x4D9C000`
  (preprocess_out start + near heap end) both succeed, so the mmap heap is
  fully accessible. CP-preLEX (after PREPROCESS) does not print. PREPROCESS
  is arch-independent and works on arm64-macho + x86-ELF, so this is an
  **x86-macho codegen/runtime** defect, not a frontend bug.
  **Leading hypothesis: Darwin LC_MAIN entry stack alignment.** ELF `_start`
  enters at `rsp%16==0`; macOS LC_MAIN *calls* `main(argc,argv,envp,apple)`,
  so cycc's top-level code runs at `rsp%16==8`. cycc's codegen assumes the
  ELF alignment, so any SSE-aligned op (movaps/movapd) deep in PREPROCESS
  would `#GP` → SIGSEGV. The fix likely belongs in the **shared macho entry
  emit** (so cycc's OWN entry is realigned by whatever builds it — the
  driver-level prologue can't fix cycc's own entry, the bootstrap problem),
  paired with the x86 entry prologue (realign + later argv parking).
  Next: confirm the alignment hypothesis (e.g. dtrace/lldb on `ach`, or an
  emitted `sub rsp,8`/`and rsp,-16` at the macho entry) and land the fix in
  backend/macho/emit.cyr's x86 entry path.

### Landed this session (gated/macho-only, x86 ELF self-host byte-identical)
- `src/main_x86_macho.cyr` (NEW dedicated driver).
- `_macho_x28` / `_macho_argv_base` x86-safe (return 0).
- (plus layers 1-3 from earlier: mmap heap + EMACHO_SYSXLAT + /proc-skip — the
  layer-1/3 #ifdefs in main.cyr are now superseded by the dedicated driver
  and can be reverted in a cleanup once the driver path is the build default.)
Remaining: layer 5 (macho entry alignment) → then re-test full compile +
self-host on `ach`, then argv/--version prologue, then the release packaging
+ real-install gate (build-macos-x86-tarball.sh).

## UPDATE 2026-06-02 (cont.) — ★ COMPILER SELF-HOSTS on Intel Mac (layer 5 FIXED)

Layer 5 pinned + fixed on `ach`. The PREPROCESS SIGSEGV was NOT alignment —
it was `PP_IFDEF_PASS`'s own `mmap` (tries Linux flags 34, falls back to
macOS `0x1002` on failure) where the **failure check `if (tmp < 0)` never
fired**: Darwin returns syscall errors via the **CARRY flag with a POSITIVE
errno**, not Linux's negative return. arm64's `ESYSCALL` converts this with
`csneg x0,x0,x0,cc`; the x86 `EMACHO_SYSXLAT` only renumbered, never
converted — so every `result < 0` check on x86-macho silently passed on
failure → garbage pointer → SIGSEGV.

**Fix (the keystone):** `ESYSCALL` now emits `jnc +3; neg rax` after every
Mach-O `syscall` (x86 `csneg` equivalent) — negate rax only when carry/error
is set. 5 bytes, gated `_TARGET_MACHO==1`.

**RESULT — verified on `ach` (Intel, Darwin 13.7.8):**
- cycc runs (was SIGSYS at instruction one).
- compiles trivial → `./out` exits 42 ✓
- compiles fib (recursion + while + arithmetic) → exits 88 ✓
- **self-hosts byte-identical**: c0 (cross-built) → c2 (741376 B) → c3;
  `cmp c2 c3` byte-identical. The Intel-Mac cycc reproduces itself. ✓
- x86 ELF self-host byte-identical; arm64 macho self-host byte-identical;
  check.sh 82/82 — no regressions (carry-negate is macho-gated).

Layers 1-5 DONE. **The x86-macOS COMPILER is functional and self-hosts.**

### Remaining for the full pillar (PILLAR RULE: install.sh → working cyrius)
1. **argv entry prologue** (deferred layer-4 follow-up): the `cyrius` wrapper
   + tools (cyrfmt/lint/doc) need argv. Emit `push rsi; push rdi; mov r13,sp`
   into each macho output's entry (cycc itself needs no argv — reads stdin),
   and make `_macho_x28`/`_macho_argv_base` read r13 (only callers that
   actually parked it — i.e. the wrapper/tools, not cycc). `--version`/
   `--strict` ride on this too.
2. **`scripts/build-macos-x86-tarball.sh`** (mirror the arm64 one) — package
   cycc + driver + wrapper + tools as x86_64 Mach-O.
3. **install.sh** x86-macho path + **release.yml** `build-macos` → the tarball.
4. **Real-install gate on `ach`**: install.sh → `cyrius build fn-main-42` →
   exit 42. Do NOT close the pillar until this passes on hardware.
