# The aarch64 compiler has no TypeScript front end: `--parse-ts` / `--lex-ts` are ignored, so the aarch64 tarball's `ts_test_runner` fails every file — RESOLVED

> ✅ **RESOLVED in v6.7.15** (PL-13, `19bf04a4c` — the user's decision D38, 2026-10-18: "Run the TypeScript front end, as on x86_64 Linux". The TS pieces of `src/main.cyr` moved into shared includes at its own token positions (`src/frontend/ts/driver_flags.cyr`, `driver_input.cyr`, `driver.cyr`), so cycc is byte-identical; the aarch64 Linux cross and native, both macOS and both Windows compilers include them and take the flags through the new `driver_args.cyr` (/proc, the Mach-O entry stack, GetCommandLineW split as CommandLineToArgvW). The filed repro on pi: `ts_test_runner` `0/1 passed (1 failed)` rc 1 → `1/1 passed` rc 0; `--parse-ts` on `let x: number = 1;` rc 0 (it gave a cyrius parse error), on `var x = 42;` rc 0 and no binary. Each compiler grows by its measured ~262 – 336 KB (`cycc-native-aarch64` +270,952 B, `cycc.exe` +297,984 B); `cycc_cx` has none. `cyrius build --target=js` follows the include graph and runs on every POSIX host; Windows still refuses by name, now pointing at `cycc.exe --emit-js`. Rows: the new `tests/gates/platform/ts_flags_every_driver.sh` (the repro verbatim on the native compiler; a 271-row stdin / path table equal to x86_64's on five drivers under native, qemu and wine; both Mach-O builds checked; `ts_test_runner` in an aarch64 install layout 1/1 and 0/1); `emit_js_per_host_fork.sh` (renamed from `emit_js_refused_off_x86_linux.sh`); the cross-OS legs' TS rows on ecb, ach, pi and cass; a 283-row harness equal to x86_64's on real pi, ecb, ach and cass. Mutations each RED: the 6.7.14 drivers, the `--pa` arm dropped, `_ts_args_win()` dropped, the read loop back to fd 0. Filed beside it: a TS path past the 255-byte /proc/self/cmdline read is cut (6.7.16). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 platform lane (unit P3), running the aarch64-linux tarball's
install smoke on pi after D59 made that tarball ship every `[release] bins` entry built for aarch64.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D38 — Run the TypeScript front end, as on x86_64 Linux.
**Severity:** Low — one tool (`ts_test_runner`) cannot do its job on aarch64 Linux; a TS walk reports every file as a
failure. No cyrius program is miscompiled.
**Affects:** `src/main_aarch64.cyr` (the aarch64-linux compiler the aarch64 tarball ships as `bin/cycc`; the native
`src/main_aarch64_native.cyr` and `src/main_aarch64_macho.cyr` have the same argument loop); `programs/ts_test_runner.cyr`
as shipped in `cyrius-<v>-aarch64-linux.tar.gz`.

## Reproduction

On pi (Linux aarch64), from the 6.7.14 aarch64-linux tarball laid out as install.sh lays it out (throwaway HOME /
CYRIUS_HOME):

```
$ mkdir ts && printf 'let x: number = 1;\n' > ts/a.ts && ts_test_runner ts; echo rc=$?
Walking ts for .ts files...

0/1 passed (1 failed)
rc=1
```

The same file through the x86_64 compiler parses clean; through the aarch64 compiler (the same binary, under
qemu-aarch64 on x86_64) the flag is ignored and the TypeScript is compiled as cyrius:

```
$ ./build/cycc --parse-ts < a.ts; echo x86rc=$?
x86rc=0
$ qemu-aarch64 ./cycc-aarch64-native --parse-ts < a.ts; echo a64rc=$?
error:<source>:1:5: expected '=', got identifier 'x'
    let x: number = 1;
        ^
error:<source>:1:6: undefined variable 'let'
    let x: number = 1;
         ^
a64rc=1
$ echo 'var x = 42;' | qemu-aarch64 ./cycc-aarch64-native --parse-ts > out; echo rc=$?    # an ELF, not a parse verdict
rc=0
```

## Root cause

The TS front end (`src/frontend/ts/lex.cyr`, `src/frontend/ts/parse.cyr`) and the `--parse-ts` / `--lex-ts` flags
(`_ts_parse_only_mode`, src/main.cyr:709-710 and :759-860) exist only in the x86_64 driver `src/main.cyr`. The aarch64
driver's `/proc/self/cmdline` loop (src/main_aarch64.cyr:60-125) knows `--ve`, `--sy`, `--al` and `--pie` and skips
anything else without a word, so `--parse-ts` falls through to "compile stdin as cyrius". `ts_test_runner` runs
`$HOME/.cyrius/bin/cycc --parse-ts` (programs/ts_test_runner.cyr:183-193), which on an aarch64 install is that
compiler, and reads its non-zero exit as a parse failure.

## Fix direction (for whoever places it)

Either give the aarch64 drivers the TS front end and the two flags (the include pair and the flag arms main.cyr has;
cybs never compiles these drivers, but the native aarch64 compiler and `cyrius pulsar` follow), or make the aarch64
driver refuse a flag it does not implement by name instead of compiling stdin as cyrius. Which one is the user's call:
the second leaves `ts_test_runner` refusing on aarch64 instead of reporting false failures. A row: `ts_test_runner`
over a clean `.ts` file on the aarch64 tarball (pi, or qemu-aarch64) reports 1/1.
