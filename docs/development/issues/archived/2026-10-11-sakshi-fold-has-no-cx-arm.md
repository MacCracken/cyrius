# `lib/sakshi.cyr` (the sakshi fold) has no cx arm: any program that includes it does not compile for cx — RESOLVED

> ✅ **RESOLVED in v6.7.10** (sakshi 2.5.9 refolded (`243ae06`): the `CYRIUS_TARGET_CX` arm. `cx_crossos_rows_run.sh` R18 runs a sakshi program on cxvm (2.5.8 back → RED). The issue's second acceptance item, `yukti_statfs_and_stdlib_constants.tcyr` compiling for cx, now gets past sakshi and stops at cx's fixed 512 KiB code buffer — a separate defect, filed as issues/archived/2026-10-12-cx-codebuf-512k-overflows-yukti-crossos-test.md (6.7.12). CHANGELOG [6.7.10])

**Status:** ✅ **RESOLVED in v6.7.10** (see the banner). Was: 🟡 **OPEN** — reported by the 6.7.9 quick lane (bite 1, seen while sweeping `tests/tcyr/crossos/` for cx).
Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B, and the `cycc_cx` it builds
from `src/main_cx.cyr`): a two-line program that includes `lib/sakshi.cyr` stops with 10 "undefined variable" errors
on cx and builds on every native target. Every installed `lib/sakshi.cyr` from 6.6.0 to 6.7.9 has no
`CYRIUS_TARGET_CX` arm (`grep -c CYRIUS_TARGET_CX` = 0).
**Placement:** 6.7.10 — the 6.7.9 fold wave (roadmap.md § *6.7.10*; moved from 6.7.12 2026-10-11 with bayan's refold,
user: "do the stdlib updates so they can be folded into 6.7.10") — never 7.x. ⛔ The fix is sakshi 2.5.9, prepared
2026-10-11 (the user tags it), then a byte-identical re-vendor: cyrius 6.7.10 cannot tag with the refold pending.
**Discovered:** 2026-10-11 during 6.7.9's quick lane: `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr`
does not compile for cx, and its first error is in `lib/sakshi.cyr:248`.
**Severity:** Medium — a hard compile failure, by name, on one target; no wrong value. A folded-stdlib defect, so high
priority.
**Affects:** `lib/sakshi.cyr` as vendored in every installed cyrius, 6.6.0 – 6.7.9 (sakshi 2.5.8 today), on the cx target only.

## Summary

sakshi's private syscall numbers (`_SK_SYS_WRITE`, `_SK_SYS_CLOSE`, `_SK_SYS_EXIT`, `_SK_SYS_SOCKET`,
`_SK_SYS_SENDTO`, …) are declared under `#ifdef CYRIUS_TARGET_AGNOS`, `#ifdef CYRIUS_ARCH_X86` and
`#ifdef CYRIUS_ARCH_AARCH64`. The cx driver predefines `CYRIUS_TARGET_CX` and no `CYRIUS_ARCH_*`
(`src/main_cx.cyr:287`), so none of the three arms is taken and every use of those names is undefined. cyrius's own
`lib/syscalls.cyr` has a `CYRIUS_TARGET_CX` arm (`lib/syscalls.cyr:92`), as `lib/atomic.cyr`, `lib/fnptr.cyr` and
the bayan fold do; sakshi does not. Any program that includes `lib/sakshi.cyr` directly or through a fold that
requires it (yukti's test above) cannot target cx.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'include "lib/sakshi.cyr"\nsyscall(60, 0);\n' > /tmp/sk.cyr
cat src/main_cx.cyr | build/cycc > /tmp/cycc_cx && chmod +x /tmp/cycc_cx
cat /tmp/sk.cyr | /tmp/cycc_cx > /tmp/sk.cyx; echo "rc=$?"
# rc=1:
# error:lib/sakshi.cyr:248:26: undefined variable '_SK_SYS_WRITE' (missing include or enum?)
# error:lib/sakshi.cyr:249:25: undefined variable '_SK_SYS_EXIT' (missing include or enum?)
# ... 10 errors: _SK_SYS_CLOSE x4, _SK_SYS_WRITE x3, _SK_SYS_EXIT, _SK_SYS_SOCKET, _SK_SYS_SENDTO
cat /tmp/sk.cyr | build/cycc > /tmp/sk && /tmp/sk; echo "x86_64 rc=$?"   # 0
```

Expected: the program compiles for cx and runs on cxvm (exit 0), as `lib/syscalls.cyr` / `lib/assert.cyr` programs do.

## Root cause

`lib/sakshi.cyr:40-90` (sakshi's `src/syscalls.cyr`, folded): the arch-dispatched `const _SK_SYS_*` block has no arm
for a target that defines neither `CYRIUS_ARCH_X86` nor `CYRIUS_ARCH_AARCH64`.

## Proposed fix

In sakshi's source repo (never the vendored copy): a `#ifdef CYRIUS_TARGET_CX` arm in `src/syscalls.cyr` with the
numbers the cx guest contract serves (docs/platform-status.md § *cyrius-x guest contract*): `write` 1, `open` 2,
`close` 3, `exit` 60 (pointer-translated) and `clock_gettime` 228 (served through the host). `socket` / `sendto` and
`nanosleep` are passed raw WITHOUT pointer translation on cx, so `sakshi_output_udp` refuses up front on cx as it does
on Windows, and the clock takes the `clock_gettime` path with no TSC calibration (its `cpuid` / `rdtsc` asm is already
under `CYRIUS_ARCH_X86`). A sakshi release, the user's tag, a byte-identical re-vendor and its `docs/ecosystem.md`
row; on the cyrius side a cx row (a sakshi program built with `cycc_cx` and run on cxvm: a span, a log line to stderr,
exit 0) in `tests/gates/codegen/cx_crossos_rows_run.sh`, and `yukti_statfs_and_stdlib_constants.tcyr` compiling for
cx.

## Consumer-side workaround

None on cx short of not including sakshi (or a fold that requires it).
