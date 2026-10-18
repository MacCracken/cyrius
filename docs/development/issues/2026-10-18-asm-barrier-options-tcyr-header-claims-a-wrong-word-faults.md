# asm_barrier_options.tcyr's header says a wrong barrier word faults (SIGILL), but a wrong option CRm runs as the full-system barrier — OPEN

**Status:** 🟡 **OPEN** — read 2026-10-18 on the 6.7.15 infratools lane (l6715-infratools, e3133d664 / 1e298f122).
Filed from the lane's review.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 infratools review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Cosmetic. The defect is the accuracy of one comment. Nothing compiles or runs differently, and the gate
that does pin the words (asm_mnemonics_whole.sh axes 6 and 9) is green.
**Affects:** tests/tcyr/crossos/asm_barrier_options.tcyr, lines 5-7 of its header.

## Evidence

The header reads:

```text
# Every barrier option the aarch64 assembler takes is EXECUTED here, on each host's own compiler: `dmb` / `dsb`
# with each of their twelve options, `isb sy`, and the bare trio (the full-system barrier). A barrier is
# unprivileged, so a wrong word faults (SIGILL) instead of passing; asm_mnemonics_whole.sh checks the words
```

The same lane's bite 1 (390b2108c) says otherwise, in its commit text and in the guide text it added. The old bare
`dmb` D50330BF was `dmb #0` and `isb` D50330DF was `isb #0`. Those are reserved options, which "the architecture runs
as sy". The old `dsb` D503309F was SSBB, and "qemu-user runs both old and new without a trap, so only the decode
shows it". A barrier whose CRm (option) field is wrong is still a barrier in the barrier encoding space, and it runs.
Only an encoding outside that space traps, as the old `wfe` D5031020 did (`msr S0_3_C1_C0_1, x0`, UNDEFINED at EL0).
So if an option's CRm were mis-encoded, for example `ish` emitted as `ishst`'s or the reserved `#0`, every row of
this tcyr would still pass on qemu-aarch64 and on pi / ecb.

## Root cause

The comment states a stronger guarantee than the row gives. The row proves that each option word compiles on the
host's own compiler and executes without a trap. That the CRm is the right one is pinned only by
asm_mnemonics_whole.sh axis 9: the 25 option forms against llvm-mc's words, run on the cross compiler.

## Fix

Rewrite the sentence to match what the row proves, keeping the pointer to the gate. For example: "A barrier is
unprivileged, so this row proves that each option word compiles on the host's compiler and executes; a wrong option
(CRm) still runs as a barrier and does not fault, so the words themselves are pinned by asm_mnemonics_whole.sh (axes
6 and 9, against llvm-mc)." This is a comment-only change, with no row needed (the tcyr's assertions are unchanged).
