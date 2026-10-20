# intrinsic_names_reserved.sh axis 5 (D11's `mulh64(..);` / `sizeof(..);` statement refusal) runs on the x86_64 compiler only — the aarch64, cx, PE and Mach-O legs are ungated — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-20 by the 6.7.16 frontend lane review (lane head 478e4f6cd). The refusal itself
is correct on all five compilers (measured below); the gap is that no gate would see it regress off x86_64.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend review, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF1) — never 7.x.
**Severity:** Low (test coverage) — no defect today; a target fork that stops refusing D11's shape would ship green.
**Kind:** bug (gate coverage).

## Reproduction

`tests/gates/frontend/intrinsic_names_reserved.sh`, axis 5 (added at e27dea14d for
issues/2026-10-18-intrinsic-as-bare-statement-is-undefined-function.md, D11): its `stmt()` helper compiles every row
with `"$CC"` only (`CC=${CYCC:-"$ROOT/build/cycc"}`, the x86_64 ELF compiler). No row builds or runs
`src/main_aarch64.cyr`, `src/main_cx.cyr` or `src/main_win.cyr`, or sets `CYRIUS_MACHO=1` / `CYRIUS_TARGET_WIN=1`.

The sibling gate tests/gates/diagnostics/in_sync_refusal_next_statement.sh (same lane) builds the aarch64 and cx
compilers from the tree and runs every row on five legs (`LEGS`, its `comp <leg>` helper: x86_64, aarch64, cx, PE,
Mach-O).

Measured by hand on the lane head 478e4f6cd, each compiler built from the tree (`./build/cycc < src/main_<x>.cyr`;
`win` = the src/main_win.cyr cross compiler, `pe-env` = `CYRIUS_TARGET_WIN=1 build/cycc`), the gate's st_mh / st_sz
sources:

```
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { mulh64(2, 3); return 0; }      # st_sz: sizeof(H);
syscall(60, go());
```

```
st_mh x86   rc=1 bytes=0 :: error:<source>:3:16: the value of 'mulh64(..)' is discarded - a statement is an assignment or a call|
st_mh a64   rc=1 bytes=0 :: (same line)
st_mh cx    rc=1 bytes=0 :: (same line)
st_mh win   rc=1 bytes=0 :: (same line)
st_mh macho rc=1 bytes=0 :: (same line)
st_mh pe-env rc=1 bytes=0 :: (same line)
st_sz x86   rc=1 bytes=0 :: error:<source>:3:16: the value of 'sizeof(..)' is discarded - a statement is an assignment or a call|
st_sz a64 / cx / win / macho / pe-env: rc=1 bytes=0, the same line
```

## Root cause

Axis 5 was written against `$CC` alone. The frontend is shared today, so the legs agree, but each target is its own
compiler build (src/main_aarch64.cyr, src/main_cx.cyr, src/main_win.cyr) and the gate does not hold them to the
refusal: the slot-open shape compiled under `--allow-undef` and its binary died with SIGILL (exit 132).

## Direction

Run axis 5's `stmt` rows (and `st_val`'s value-form run, under qemu-aarch64 / cxvm where those are available) on the
five legs the way in_sync_refusal_next_statement.sh does (its `comp <leg>` helper): build cc_a64 / cc_cx from the
tree, a `CYRIUS_MACHO=1` leg and the `CYRIUS_TARGET_WIN=1` PE leg. Mutation: `_stmt_intrinsic` returning 0 at once ->
RED on every leg.
