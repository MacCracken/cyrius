# cx's fixed 512 KiB code buffer: `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr` stops with a bare "codebuf overflow" on cx — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-7, `82e3147f`, with LIB-7r, `d3a5d87b`, and LIB-9, `92bf2a1f`: cx bytecode goes into a 4 MiB code region allocated off the compiler arena (it was the fixed 512 KiB at `S + 0x54A000`), refused past it by name — "error: cx bytecode exceeds the cx code region (4194304 B): <n> B emitted when fn '<name>' … reached it — build this program for a native target" — and cxvm's guest memory is 8 MiB with its `.cyx` read cap and VM stacks to match (D12, the user 2026-10-15: grow); the two cx-only heap regions are freed. `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr` now compiles for cx (a 1,076,387 B `.cyx`) and cxvm prints `2 passed, 0 failed` (it was `error: codebuf overflow`, rc 1); TLS / sigil stay refused by name. Rows: `cx_crossos_rows_run.sh` R19 (the yukti file), R20 (the named refusal), R21 (a 4.1 MB `.cyx` runs) — 66/66; `cx_tailcall_and_vm_traps.sh` at the 8 MiB boundary, D5b, B3 / B4 at depth 524288 — 29/29; run on pi, ecb, ach and cass. Filed alongside: the cx `jz` / `jnz` 16-bit offset (`2026-10-15-cx-conditional-jump-past-128k-wraps-silently.md`) and the 128 KB cx static heap (`2026-10-15-cx-static-heap-128k-while-guest-is-8-mib.md`), both 6.7.14. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-12 in the 6.7.10 refold worktree (`build/cycc` 2,057,744 B, its `cycc_cx` from
`src/main_cx.cyr`, sakshi 2.5.9 refolded): the test now gets past the sakshi fold (the 10 "undefined variable
'_SK_SYS_*'" errors of issue 2026-10-11-sakshi-fold-has-no-cx-arm are gone) and stops at `error: codebuf overflow`,
rc 1, no `.cyx`. The x86 build of the same file compiles and passes.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D12 — grow (cx bytecode off-heap, cxvm caps to match).
**Discovered:** 2026-10-12, the 6.7.10 sakshi refold: closing the sakshi cx issue named this test compiling for cx as
part of its acceptance; the sakshi half holds (`cx_crossos_rows_run.sh` R13), this half is a separate defect.
**Severity:** Medium — a hard refusal on one target, no wrong value; and the message names no limit, no size and no
remedy.
**Affects:** every cycc_cx, at least since 6.6.11 (the cap is older; 6.6.11 named it for tls / sigil only).

## Summary

cx bytecode goes into a FIXED 512 KiB region (`S + 0x54A000`, `src/backend/cx/emit.cyr` `EB`: `if (cp >= 524288)`
→ "error: codebuf overflow", exit 1); cx code runs about 3.2× an x86 build's size, and cxvm caps its code / guest
memory at 1 MB. A program the size of yukti + patra + sakshi + their stdlib leaves overflows it. 6.6.11 met the same
wall for `lib/tls.cyr` / `lib/sigil.cyr` and declared those out of cx's scope BY NAME (`_cx_scope_refused`), so they
fail up front with a message; any other large program still dies mid-emit with a message that names nothing.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
build/cycc < src/main_cx.cyr > /tmp/cycc_cx && chmod +x /tmp/cycc_cx
/tmp/cycc_cx < tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr > /tmp/y.cyx; echo "rc=$?"
# rc=1 — error: codebuf overflow
```

## Root cause

`src/main_cx.cyr` maps cx's code at a fixed 512 KiB region and `EB` refuses at 524,288 B; the region never grows
(`_codebuf_cap` is read only by the x86 / aarch64 EB). cxvm's own 1 MB code / guest caps bound it from the other side.

## Proposed fix

Decide the cx program-size ceiling, then either (a) grow cx's code region (a heap-map change in `main_cx.cyr` only —
not the seed chain — and cxvm's caps to match), or (b) keep the ceiling and make the overflow a named, sized
refusal (`cx code exceeds 512 KiB at <fn>: …`) and refuse known-large modules by name as 6.6.11 did. Either way
`yukti_statfs_and_stdlib_constants.tcyr` either compiles for cx or is refused by name, and a row in
`cx_crossos_rows_run.sh` pins the result.

## Consumer-side workaround

None on cx for a program this large.
