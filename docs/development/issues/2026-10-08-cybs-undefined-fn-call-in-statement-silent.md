# cybs compiles a statement-position call to an undefined function silently; the binary segfaults — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b: cybs assembled from the seed
(`bootstrap/asm < bootstrap/cybs.cyr`, byte-identical to `build/cybs`, 21,780 B) compiles `nosuch(1);` with exit 0 and
the program dies with SIGSEGV (exit 139); the expression form `var x = nosuch(1);` is refused (exit 1). A
statement-position call through a fn-pointer VARIABLE (`fp(5);`) takes the same path and also segfaults, where
`build/cycc` refuses it (`undefined function 'fp'`).
**Placement:** unpinned — 6.x-line backlog — never 7.x. (cybs is the trusted root's first rung: the fix is placed,
not slipped in.)
**Discovered:** 6.7.6 (roadmap commit c2178734, 2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — a silent bad binary from the bootstrap compiler. Contained today: cybs only builds `src/`
(→ gen1) and `bootstrap/asm.cyr`, and gen1 (cycc itself) refuses an undefined function when it compiles gen2, so
seed-derive fails loudly — but at the wrong rung, with no name.
**Affects:** `bootstrap/cybs.cyr` as of 6.7.6 (not bisected).

## Reproduction

```cyr
fn main() {
    nosuch(1);
    return 7;
}
var r = main();
syscall(60, r);
```

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > cybs && chmod +x cybs
./cybs < stmt.cyr > stmt && chmod +x stmt; echo "cybs=$?"; ./stmt; echo "run=$?"
# 6.7.6: cybs=0  run=139           expected: cybs refuses, naming 'nosuch'
# the control (`fn f(a) { return a; }` defined, `f(1);`) runs and exits 7
# `var x = nosuch(1);` instead: cybs prints "undefined variable" and exits 1
```

## Root cause

- The statement arm `parse_assign_is_fn_call` (`bootstrap/cybs.cyr:2990`) looks the name up with `find_fn_index`;
  on a miss it does not error but **registers a new fn** (`parse_assign_fn_new`, cybs.cyr:3021, `call register_fn`),
  whose entry `register_fn` sets to -1 (cybs.cyr:1024), so the call is emitted as a placeholder with a type-2 fixup
  (`parse_assign_fn_fixup`, cybs.cyr:3039).
- `fixup_fn_call` (cybs.cyr:4702) reads the entry from `r15 + 0x7300000 + idx*8` and patches `rel32 = entry -
  (site + 4)` with **no check that the entry is still -1** — the call lands one byte before the code start.
- The expression arm (`parse_factor_fn_call`, cybs.cyr:4140) treats a miss as a fn-pointer variable
  (`parse_factor_fn_new`, cybs.cyr:4169 → `find_var_index`), which is why it reports "undefined variable" (itself a
  misleading name for an undefined function — see `2026-10-08-cybs-bare-syntax-error-no-location.md`).

## Proposed fix

In `fixup_fn_call`, refuse an entry of -1: write "cybs: undefined function" (+ the name from the fn-name table at
`r15 + 0x7200000`) and exit 1. That reaches the existing error-exit path and needs few or no new labels — the budget
matters: cybs.cyr defines **501 of the seed's 512 labels** (gate row S, `tests/gates/toolchain/cybs_call_arity_named.sh`).
Then a fn-pointer variable in statement position (`fp(5);`) is refused instead of segfaulting, matching cycc. Gate:
a cybs row asserting `nosuch(1);` exits non-zero with the name. Mandatory after: the seed-derive gate
(`sh scripts/seed-derive-cycc.sh`) and the closure (`cybs(bootstrap/asm.cyr) == bootstrap/asm`). No change to what
cycc compiles; cybs's accepted language only narrows to what cycc already refuses.
