# cx: the static heap is still 128 KB (`lib/alloc_cx.cyr` `_CX_HEAP_SLOTS`) though cxvm's guest memory is 8 MiB since 6.7.12 — RESOLVED

> ✅ **RESOLVED in v6.7.14** (LIB-7, `d1f41d46f`; LIB-7r, `22add1966`. No decision was needed: a cap. cxvm serves brk (12) in guest space. The break starts at the image end, and it moves while it stays 1 MiB below both the live guest sp and the 8 MiB segment's top (the segment bound is LIB-7r, the review's must-fix). Granted memory reads zero, and the guest stack traps at the break. `lib/alloc_cx.cyr` bumps over the break: `_cx_heap_buf` / `_CX_HEAP_SLOTS` are gone, and exhaustion states what it reached, `alloc: cx heap exhausted at <N> B (the guest break cannot grow by <M> B more)`. The heap reaches ~7 MiB less the image, and an `alloc(16)` program's `.cyx` is 22,494 B (151,546 B before). The filed `audit_walk_fifo.tcyr` runs past its two 2 MB buffers to its summary on x86_64, ach, wine and cass, with no `alloc:` line. Its mkdir premise rows answer -38 under D55, a separate filed shape. On pi and ecb it now stops mid-file on the filed fork → close renumbering. The crossos corpus on cx goes from 235 to 238 files passing. A 6.7.14 `.cyx` that allocates needs the 6.7.14 cxvm: 6.7.13's stops at `cxvm: guest address out of range`. Rows: `tests/gates/codegen/cx_heap_guest_brk.sh`, 13 rows. They cover 3 MiB read back, the named exhaustion (7,274,496 B), the stack trap at the break, zeroed memory, brk's contract, the `.cyx` size, audit_walk_fifo, alloc_reset, a brk-less cxvm named, and H10 a raised sp bounded by the segment. Mutations MH1–MH5 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane (l6712-stdlib, after D12 grew the cx code
region to 4 MiB and cxvm's guest memory 1 MB → 8 MiB).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a cx program that allocates more than 128 KB stops with the loud, named
`alloc: cx static heap exhausted (128 KB)` (exit 1), never a silent wrong answer; no file on a cx leg meets it today.
**Discovered:** 2026-10-15, the review of the 6.7.12 stdlib lane (the D12 bite,
`issues/archived/2026-10-12-cx-codebuf-512k-overflows-yukti-crossos-test.md`). A shape beyond D12's filed surface (the code
region and cxvm's caps), so filed, not absorbed.

## Reproduction

```sh
cd /home/macro/.cache/c6/wt6712/stdlib          # any tree at or after 6.7.12's cx bites
cat src/main_cx.cyr | build/cycc > cycc_cx; cat programs/cxvm.cyr | build/cycc > cxvm; chmod +x cycc_cx cxvm
cat tests/tcyr/crossos/audit_walk_fifo.tcyr | ./cycc_cx > awf.cyx; echo "compile rc=$?"
mkdir scratch && cd scratch && ../cxvm < ../awf.cyx; echo "cxvm rc=$?"
```

```text
compile rc=0                      (a 412,069-byte .cyx)
  FAIL: premise: the fixture directory was created (got -14, expected 0)
  FAIL: premise: a non-source file was created inside it (got -2, expected 2)
=== a directory still walks ===
alloc: cx static heap exhausted (128 KB)
cxvm rc=1
```

The two `premise` FAILs are the separate untranslated-pointer-wrapper shape (`sys_mkdir` hands the host a guest
address and answers -EFAULT; staged as `2026-10-15-cx-untranslated-pointer-wrappers-can-reach-cxvm-image.md`). The stop
is the heap: `audit_fmt_walk` (lib/audit_walk.cyr :353-355) takes two 2,000,000-byte buffers, and the first `alloc`
past 131,072 bytes aborts. audit_walk_fifo.tcyr is not on a cx leg today (cx_crossos_rows_run runs a named set).

## Root cause

`lib/alloc_cx.cyr` is a static bump heap — `enum CxHeap { _CX_HEAP_SLOTS = 16384; }`, `var _cx_heap_buf[_CX_HEAP_SLOTS];`
(16384 × 8 B = 128 KB) — sized at v6.6.6 / 6.6.10 for cxvm's 1 MB guest, which also held the code, the rest of the data
and the downward stack ("this cannot be raised much without shrinking the usable stack — raise _CX_MEM_SIZE in
programs/cxvm.cyr first if it ever needs to be"). 6.7.12 (D12) raised `_CX_MEM_SIZE` to 8 MiB for the 4 MiB code
region but left the heap at 128 KB, so a cx program still gets 128 KB of `alloc()` with ~3 MiB of guest memory spare
beside a 1 MB .cyx.

## Fix direction (for whoever places it)

Size the heap from the 8 MiB guest: raise `_CX_HEAP_SLOTS` so code (≤ 4 MiB) + data + heap + a stack floor fit
`_CX_MEM_SIZE`, keep the exhaustion message deriving its size from the slot count (it hard-codes "128 KB"), and add a
cx row that allocates past 128 KB (and one that still meets the named exhaustion). A heap that holds audit_walk's two
2 MB buffers needs more than 4 MiB, which together with a 4 MiB program exceeds 8 MiB — so the fix also decides whether
the heap or the guest grows, or whether audit_walk's 2 MB buffers are cx-sized.
