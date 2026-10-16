# cx: the static heap is still 128 KB (`lib/alloc_cx.cyr` `_CX_HEAP_SLOTS`) though cxvm's guest memory is 8 MiB since 6.7.12 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane (l6712-stdlib, after D12 grew the cx code
region to 4 MiB and cxvm's guest memory 1 MB → 8 MiB).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane; filed from the 6.7.12 stdlib lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
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
