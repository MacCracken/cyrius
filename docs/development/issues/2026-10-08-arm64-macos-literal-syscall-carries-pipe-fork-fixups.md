# arm64-macOS: a folded literal syscall still carries the pipe / fork post-`svc` fixups (64 B a site, XLAT-3) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b by cross-building with the tree's
`build/cycc`: `syscall(39)` on arm64 Mach-O folds to `movz x16,#20` and is still followed by the full 16-word
pipe / fork fixup (3 words before `svc`, 13 after `csneg`). Word-level only; not re-verified on hardware (needs ecb —
the fixups are Darwin behaviour).
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.6.18 (2026-10-06), the XLAT-1 lane's leftover (CHANGELOG [6.6.18] *Known / not fixed*); filed
2026-10-08 from roadmap.md.
**Severity:** Low — size only.
**Affects:** cycc 6.6.18 – 6.7.6 (arm64 Mach-O output).

## Summary

On arm64 Mach-O, `ESYSCALL` (`src/backend/aarch64/emit.cyr:519-575`) brackets every `svc #0x80` with run-time tests
of x16: a pre-`svc` stash of x0 for pipe (`cmp x16,#42` / `b.ne` / `str x0,[sp,#-16]!`), then after `csneg` the fork
child fixup (`cmp x16,#2` …, 5 words) and the pipe fd-buffer store (`cmp x16,#42` …, 8 words). Since XLAT-1
(`_esx_fold`, `:1911`) a literal site's x16 is a compile-time fact — its folded body ends in `movz x16,#d` (checked
by `_esx_body_bad`) — yet the 16 test words (64 B; the roadmap's "~68 B") are emitted regardless. Only two Mach-O
rows can produce those values: `clone 220 → fork 2` (`:911`) and `pipe2 59 → pipe 42` (`:1104`).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
./build/cycc < src/main_aarch64.cyr > /tmp/cca && chmod +x /tmp/cca          # the aarch64 cross compiler
printf 'syscall(39);\nsyscall(3, 0 - 1);\n' > /tmp/x3.cyr
CYRIUS_MACHO_ARM=1 /tmp/cca < /tmp/x3.cyr > /tmp/x3.bin
od -An -v -tx4 /tmp/x3.bin | tr -s ' ' '\n' | grep -A18 '^d2800290$' | head -19
# d2800290 movz x16,#20 (getpid)  f100aa1f 54000041 f81f0fe0   (pipe stash)  d4001001 svc  da803400 csneg
# f1000a1f 54000081 f100043f 54000041 d2800000                  (fork fixup)
# f100aa1f 540000e1 f84107e2 f100001f 5400008b b9000040 b9000441 d2800000   (pipe store)
```

Expected: for a folded `d ∉ {2, 42}`, `svc #0x80; csneg` only (8 B). Actual: 72 B. In the arm64-macOS compiler
itself only 18 svc sites carry it (1,152 B — most of its I/O is `__got` reroutes); the per-site cost is what matters
for programs that issue many literal syscalls.

## Root cause

`ESYSCALL`'s Mach-O arm cannot see the literal: `ESCPOPS` (`src/backend/aarch64/emit.cyr:2047`) folds the chain
(`:2075`) and then calls `ESYSCALL(S)` with no record of the folded x16.

## Proposed fix

Let `ESCPOPS` tell `ESYSCALL` the folded x16 (e.g. read the last kept word, a `movz x16,#d`, or a module var set by
`_esx_fold`): `d == 42` → the pipe halves only; `d == 2` → the fork half only; any other `d`, or an unrouted miss
(the `movz x16,#0xFFFF` head) → no fixup. A variable number (the XLAT-2 stub) and a `#naked` inline chain keep the
run-time tests. Gates: `esysxlat_fold.sh` gains an axis counting `cmp x16,#42` / `cmp x16,#2` words in an
all-literal Mach-O probe (zero, except at the 220 / 59 sites); behaviour on **ecb** via
`tests/tcyr/crossos/fork_refused_stays_negative.tcyr` and the pipe tests. The x86 twin (`EMACHO_PROC_FIXUP`) is part
of `2026-10-08-x86-macos-emacho-sysxlat-not-folded.md`.
