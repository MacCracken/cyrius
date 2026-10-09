# cx: a fn returning a 16-byte struct is refused ("int-class 16B struct pair-return ABI not supported") — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b: a cx compiler built from this tree
(`cat src/main_cx.cyr | build/cycc`) refuses `fn p2(a, b): P2` (16 B) at its `return r;` and at the caller's
`var q: P2 = p2(20, 22);`; the same source exits 42 on x86_64. A 24 B struct return (retptr) and a
`return (a, b);` pair both run correctly under `cxvm` (exit 42). `tests/tcyr/crossos/for_step_struct_assign.tcyr`
fails to compile for cx with four such errors.
**Placement:** 6.7.8 — features: checked dyn + C2 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 B8 lane (roadmap commit e95f295d, pre-existing since v5.10.45); filed 2026-10-08 from roadmap.md.
**Severity:** Medium
**Affects:** cycc v5.10.45 – 6.7.6, cx target only (`src/main_cx.cyr`)

## Summary

On x86_64, aarch64, PE and Mach-O, a 9–16 B integer-class struct is returned in the register pair (rax:rdx /
x0:x1). The cx backend's pair emitters are still the v5.10.45 "Phase 1" stubs that raise a compile error, so any
program that returns (or receives) a 16 B struct by value does not build for cx — including a `tests/tcyr/crossos/`
file, so the cross-OS suite cannot claim cx coverage for that shape. The refusal is loud (no miscompile).

## Reproduction

```cyrius
struct P2 { x; y; }
fn p2(a, b): P2 { var r: P2 = P2 { a, b }; return r; }
fn main(): i64 {
    var q: P2 = p2(20, 22);
    return q.x + q.y;
}
var r = main();
syscall(60, r);
```

```sh
cat src/main_cx.cyr | build/cycc > /tmp/cxcc && chmod +x /tmp/cxcc
cat programs/cxvm.cyr | build/cycc > /tmp/cxvm && chmod +x /tmp/cxvm
cat repro.cyr | /tmp/cxcc > /tmp/r.cyx; echo $?          # 1
/tmp/cxvm < /tmp/r.cyx; echo $?                          # (no program)
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?   # 42 on x86_64
```

Actual (cx): `error:<source>:2:54: cx: int-class 16B struct pair-return ABI not supported` and the same at 4:27.
Expected: a `.cyx` that `cxvm` runs to exit 42.

## Root cause

`EFLLOAD_STRUCT_INT_PAIR` / `EFLSTORE_STRUCT_INT_PAIR` (`src/backend/cx/emit.cyr:1029` / `:1033`) are `ERR_MSG`
stubs. The x86 versions (`src/backend/x86/emit.cyr:5037` / `:5064`) load/store the 2-slot local from/to rax:rdx;
the frontend calls them for the callee's return (`src/frontend/parse_fn.cyr:1942`, `:1958`), the caller's receive
(`parse_fn.cyr:2764`, `:2978`) and an operator operand temp (`src/frontend/parse_expr.cyr:5778`).
cx already has both halves of a pair convention: multi-value return uses r0 + r4 (the rdx peer, `EMOVRDXRAX` /
`EMOVRA_RDX`, `emit.cyr:334`–`335`, live since v6.5.21), and f64v2 returns use r0 + r1 (`EFLLOAD_F64V2_PAIR`,
`emit.cyr:868`).

## Proposed fix

Implement the two cx emitters as the x86 ones are shaped: lo = `[fp - (idx+1)*8]`, hi = `[fp - idx*8]`, with lo in
r0 and hi in r4 — the register the shared frontend already treats as rdx on cx, so any path that moves the pair
through `EMOVRA_RDX` / `EMOVRDXRAX` stays consistent (speculation: r4 vs r1 must be checked against every frontend
site that reads the high half after a struct call). No language change. Then drop the cx exclusion note from
`tests/tcyr/crossos/for_step_struct_assign.tcyr`'s header and run it under `cxvm`; add a cx row (16 B return,
receive, method return, operator operand) to the cx gate (`tests/gates/codegen/`).
