# A `--parse-ts` / `--lex-ts` / `--emit-js <file>` path is cut at the 255-byte /proc/self/cmdline read, and the cut name is opened — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TL-9, `9843878df` — no decision needed: a path or flag the command line holds was cut or dropped. One reader, src/common/util.cyr's `_cmdline_read`, reads /proc/self/cmdline to EOF into a 2 MiB mapping for cycc, cycc_aarch64, the aarch64 native cycc, the Linux-hosted cycc_win and cycc_cx; a line that fills it is refused by name, exit 1 (`error: the command line is longer than 2097151 bytes (/proc/self/cmdline is read whole; a cut copy is never scanned)`). The filed repro, with a 287-byte directory, prints `let x = 1;`, rc 0, on x86, the aarch64 cross, the Windows cross and the native compiler under qemu, and on pi (279 bytes); a flag past byte 255 takes effect (`cycc <300-byte arg> --version` prints the version; it compiled stdin). Rows: emit_js_per_host_fork.sh axis 5 — 23 rows over the five drivers: the repro, a flag after 300 bytes, exactly 2,097,151 bytes read, 2,097,152 refused, a path across the 2 MiB edge refused and never opened (mutants C1 – C3 RED); fork_shared_blocks_single_copy.sh (one reader, each /proc driver calling it once). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 platform lane (unit P5), while giving every driver the TS
flags (6.7.15's D38).
**Placement:** 6.7.16 — Break 2, repair 6 (tools lane, wave 1, unit T3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a TS mode's input path that, with argv[0] and the flag, makes the command line longer than 255
bytes is truncated silently and the truncated name is opened: a "cannot open '<prefix>'" for a file that exists, or,
when the prefix names another file, that file's TypeScript is lexed / parsed / emitted instead. `cyrius build
--target=js <source> <out>` passes the source path as the user wrote it, so a deep absolute path reaches it. Every
other flag past byte 255 is dropped the same way (no message).
**Affects:** every driver that reads its flags from /proc/self/cmdline — src/main.cyr (x86_64 Linux, since v6.0.5's
path form), and since 6.7.15 src/main_aarch64.cyr, src/main_aarch64_native.cyr and the Linux-hosted build of
src/main_win.cyr (`_vbuf[256]`, `syscall(SYS_READ, _vfd, &_vbuf, 255)`). The macOS drivers (argv off the entry stack)
and Windows cycc.exe (GetCommandLineW, split by src/frontend/ts/driver_args.cyr) read the whole command line.

## Reproduction

On x86_64 Linux, with this tree's `build/cycc` (its /proc read is unchanged since v6.0.5):

```
$ D=$PWD/longpath/$(printf 'd%.0s' $(seq 1 120))/$(printf 'e%.0s' $(seq 1 120)); mkdir -p $D
$ printf 'let x: number = 1;\n' > $D/a.ts; echo ${#D}
290
$ ./build/cycc --emit-js $D/a.ts > out.js; echo rc=$?
error: cannot open '/home/macro/.cache/c6/s6715/platform/P5/longpath/ddd…ddd/eeeeeeeeeeeeeeeeeeeeeeeeee'
rc=1
```

The file exists; the name opened is its first 220-odd bytes (255 minus argv[0] and `--emit-js`).

## Root cause

The /proc scan reads at most 255 bytes into a fixed `_vbuf[256]` and treats a short read as the whole command line
(it never reads again); `_ts_input_path` points into that buffer. Nothing tells a cut argument from a whole one.

## Fix direction

Read /proc/self/cmdline to EOF (or until it stops fitting a buffer sized from it), or refuse by name when the read
fills the buffer — never open a truncated path. The same read serves `--version` / `--syntax-only` / `--allow-undef`
/ `--pie`, which are silently dropped past byte 255 today. A row: the reproduction above prints `let x = 1;` and
exits 0 on every /proc driver (x86_64, the aarch64 cross and native compilers under qemu and on pi, the Windows cross
compiler).
