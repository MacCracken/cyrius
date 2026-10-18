# A `--parse-ts` / `--lex-ts` / `--emit-js <file>` path is cut at the 255-byte /proc/self/cmdline read, and the cut name is opened — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 platform lane (unit P5), while giving every driver the TS
flags (6.7.15's D38).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 platform lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
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
