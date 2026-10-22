# cycc_cx built for agnos reads its flags from /proc/self/cmdline, which agnos does not have, so `--version` / `--syntax-only` are never seen there — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TT-5, `c45151b55` — no decision needed (the issue's "none"). The agnos `cycc_cx` reads `--version` and `--syntax-only` off the init stack: src/common/util.cyr's entry-stack block (`_macho_x28`, `_ARGV_FLAG_ONE`, `_ARGV_FLAGS_MACHO`) is compiled on every target that is neither Linux nor Windows (macOS and agnos; its x86 r15 arm is agnos's layout), src/main_cx.cyr's /proc scan `_cx_cmdline_flags` is Linux's alone and agnos takes the macOS arm, and `_cmdline_read` answers 0 at once on agnos (the filing's interim, kept). Under the fake agnos kernel `cycc_cx --version` now writes the version to fd 1 (`txt 1 cycc <version>`) and exits 0 with no open#7 (it sent `sc 7 -100 …` — Linux openat's shape — and compiled stdin), and `--syntax-only` lets `var x = nope;` compile. The four duplicate-symbol warnings the evidence quotes are gone (TT-7, `b35498162`: the driver declares agnos's SYS_* itself; TT-10, `e999a3d9d`: the same for src/main.cyr's agnos build). Found beside it and fixed — the agnos `cycc_cx` had never compiled a program: TT-4 (`f2c4f0a14`, the preprocessor's 24 MiB buffer mapped with agnos mmap #27 / munmap #28, a refused map named on every target), TT-6 (`fc69b8536`, the fake kernel sets PTRACE_O_EXITKILL), TT-8 (`0dcf6fa39`, READFILE's opens through `_rf_open`, agnos open#7(name, namelen)), TT-9 (`d927f6a70`, `_read_env`'s init-stack arm serves agnos), and the review fixes TT-9r (`7eba160e7`, the pin check runs on agnos, 6.7.12's D5) and TT-9r2 (`5110ba614`, the envp walk bounded at 256 entries). Rows: `tests/gates/platform/agnos_peer_fake_kernel.sh` axis 14 C0 – C9 (C3 `--version`, C4 `--syntax-only`; the /proc arm restored → RED C3 / C4) and the tracer-death row. ⚠ Verified under the local ptrace fake kernel only: the filing's row asked for agnos's own CI or a qemu-system leg, and no agnos runtime is reachable from cyrius. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 tools lane (unit T3), while moving every /proc driver onto
the one whole-line reader (`_cmdline_read`, issues/archived/2026-10-18-cmdline-read-cuts-ts-path-at-255-bytes.md).
Pre-existing (the 6.7.16 open's `src/main_cx.cyr` has the same arm). Not measured on agnos: no agnos runtime is
reachable from this lane; the evidence below is the source and the agnos build's own diagnostics.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 tools lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; t16 lane, wave 3, unit TT2) — never 7.x.
**Severity:** Low — only a cx compiler built with `CYRIUS_TARGET_AGNOS=1` and run on agnos is affected. There it
reads no flag at all: `cycc_cx --version` compiles its stdin instead of printing the version (the defect class
6.6.6 fixed on the aarch64 and cx drivers), and `--syntax-only` is ignored.
**Kind:** tooling (cx driver, agnos arm).

## Evidence

`src/main_cx.cyr` (the 6.7.16 open, 480de63eb):

```cyrius
# /proc/self/cmdline on Linux + agnos, ...
#ifdef CYRIUS_TARGET_AGNOS
_cx_cmdline_flags();
#endif
```

1. agnos has no `/proc/self/cmdline`. `lib/args_agnos.cyr` says so ("agnos has no /proc/self/cmdline (the Linux
   source)"); agnos programs read argv off the init stack the entry parks in r15. src/main.cyr's agnos predefine
   comment says the same ("NOT CYRIUS_TARGET_LINUX (no /proc, different syscall numbers)").
2. The open is not even agnos-shaped. In the agnos build, `lib/alloc.cyr` includes `lib/syscalls.cyr`, whose
   agnos enum redefines the driver's `SYS_*` (the last definition wins for every use, measured with a two-enum
   probe: a fn above the second definition reads the second value):

   ```
   $ CYRIUS_TARGET_AGNOS=1 ./build/cycc < src/main_cx.cyr > cx_ag
   warning:lib/syscalls_x86_64_agnos.cyr:58:17: duplicate symbol 'SYS_EXIT' redefined with conflicting value (last definition wins)
   warning:lib/syscalls_x86_64_agnos.cyr:65:17: duplicate symbol 'SYS_READ' redefined with conflicting value (last definition wins)
   warning:lib/syscalls_x86_64_agnos.cyr:67:18: duplicate symbol 'SYS_CLOSE' redefined with conflicting value (last definition wins)
   warning:lib/syscalls_x86_64_agnos.cyr:68:17: duplicate symbol 'SYS_OPEN' redefined with conflicting value (last definition wins)
   ```

   so the scan calls agnos `open` (7), whose signature is `open(name, namelen[, flags])`. At the 6.7.16 open it
   passed `("/proc/self/cmdline", 0, 0)` (a namelen of 0); since 6.7.16 the shared reader's `SYS_OPEN != 2` arm
   passes the Linux openat shape `(-100, "/proc/self/cmdline", 0, 0)`. Neither can name a file, and the file does
   not exist: the open fails, the reader returns 0, and no flag is read. (The reader's mmap and read follow only
   a successful open.)

## Root cause

The cx driver's agnos arm reuses the Linux /proc scan. agnos delivers argv on the init stack (r15, as
`lib/args_agnos.cyr` reads it), not through a pseudo-file.

## Fix direction

Read the agnos flags off the parked init stack, as `_ARGV_FLAGS_MACHO` does for the x86 Mach-O driver (the same
inline layout, `[r15] = argc`, `argv[i]` at `r15 + 8 + i*8`), after the driver parks r15 at its entry. A row:
`CYRIUS_TARGET_AGNOS=1` cycc_cx prints its version for `--version` on agnos (agnos's own CI, or a qemu-system leg
if cyrius grows one).

Interim (the 6.7.16 tools review's suggestion): `#ifdef CYRIUS_TARGET_AGNOS return 0; #endif` at the top of
src/common/util.cyr's `_cmdline_read`, so the agnos build makes no open with the Linux openat argument shape (agnos
`open(name, namelen)` gets a name pointer of 0xFFFF…FF9C and a pointer as namelen) until the init-stack reader lands.
