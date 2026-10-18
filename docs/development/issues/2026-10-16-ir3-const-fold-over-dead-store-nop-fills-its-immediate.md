# `CYRIUS_IR=3`: a constant fold whose span holds a dead-store-eliminated node has its new immediate NOP-filled — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 infra lane (unit I2) while running the `.tcyr` corpus under
`CYRIUS_IR=3`: tests/tcyr/derive/derive_enum_inside_ifdef.tcyr dies with SIGSEGV there (4 / 4 by default), in its
`nested()` helper. Reproduced on the installed 6.6.20, 6.7.0 and 6.7.13 compilers and on this lane's tree.
**Placement:** 6.7.15 — repair 5 (infratools lane, wave 1, unit I1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Medium — a SIGSEGV (or a silently wrong constant, when the corrupted bytes still decode) on valid code
as small as three statements, but only under the opt-in `CYRIUS_IR=3` (no release build uses it).
**Kind:** codegen (IR=3), src/common/ir.cyr.

## Repro

```cyrius
fn nested(): i64 {
    var r = 0;
    r = r + 10;
    r = r + 100;
    return r;
}
syscall(60, nested());
```

```
build/cycc < r.cyr > r && ./r; echo $?                                    # 110
CYRIUS_IR=1 build/cycc < r.cyr > r && ./r; echo $?                        # 110
CYRIUS_IR=3 build/cycc < r.cyr > r && ./r; echo $?                        # 139 (SIGSEGV)
CYRIUS_IR=3 CYRIUS_DSE_CAP=0 build/cycc < r.cyr > r && ./r; echo $?       # 110
CYRIUS_IR=3 CYRIUS_FOLD_OFF=1 build/cycc < r.cyr > r && ./r; echo $?      # 110
```

`ir: 41 nodes, 6 BBs, 3 edges, 3 LASE (6B applied), 1 folds (10B), 2 DSE (3 fp iters)`.

`nested()`'s body, default vs `CYRIUS_IR=3` (r is register-allocated to rbx):

```
default:  31 c0           xor eax,eax           ; r = 0
          48 89 c3        mov rbx,rax
          50              push rax              ; r + 10
          b8 0a 00 00 00  mov eax,0xa
          59              pop rcx
          48 01 c8        add rax,rcx
          48 89 c3        mov rbx,rax
          ...
IR=3:     b8 0a 50 b8 64  mov eax,0x64b8500a    ; the fold's `mov eax, 10` with its imm32 high bytes gone
          00 00           add [rax],al          ; -> SIGSEGV
          ...
```

## Root cause

`ir_const_fold` (src/common/ir.cyr) matches `LOAD_IMM(a), PUSH, LOAD_IMM(b), POP_RCX, OP` and **skips `IR_ELIMINATED`
nodes** inside the pattern ("it cannot separate a LOAD_IMM from the PUSH that consumes it"). Here the dead-store pass
has already eliminated `r = 0`'s `STORE_LOCAL` (`mov rbx, rax`, 3 bytes), which sits between `LOAD_IMM(0)` (`xor
eax, eax`, 2 bytes) and the `PUSH`. The fold writes `EMOVI(10)` (5 bytes) at the LHS's code position across the whole
span and marks the pattern's own nodes `IR_NOP` — but the eliminated store in the middle stays `IR_ELIMINATED`. At the
end of the fixpoint `ir_apply_lase` NOP-fills every `IR_ELIMINATED` node's recorded byte range `[cp, next cp)`, which
is now bytes 2-4 of the fold's `mov eax, imm32`: the immediate's high bytes become `90 90 90`, and the whole-program
NOP compaction then deletes them, splicing the next instruction's bytes into the immediate.

The fix belongs in the fold: a node the rewritten span covers is consumed with it (mark every node in `[ni_a, ni]`
`IR_NOP`, the eliminated ones included), or `ir_apply_lase` must not fill a range a fold has rewritten. Default output is
unaffected either way (the passes run only under `CYRIUS_IR=3`); the check is the repro above, derive_enum_inside_ifdef
under IR=3, and the IR=3 self-host.
