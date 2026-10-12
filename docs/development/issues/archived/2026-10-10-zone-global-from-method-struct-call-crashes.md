# A declaration-zone global set from a METHOD returning a 9-16 byte struct compiles and crashes at startup — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 19, l679-crit; CHANGELOG [6.7.9]) The declaration zone's replay (`_gvi_expr`, parse_decl.cyr) now runs the struct half of PARSE_VAR's top-level check, `_sc_global_pair` (parse_fn.cyr, split out of `_sc_global_receive` and shared): a whole 9-16 B method, generic-method, wrapped `(Q0.mk())` or operator (`Q0 + Q1`) result into a global of the same struct is refused by name, as the free call and the post-statement line are — once: a line already refused inside its initialiser is not refused again. The repro exits 1 at compile with the filed message. 6.7.8's dyn-only `_gvi_dyn_mcall` is subsumed and removed. Rows Z1-Z10 / ZK1-ZK3 in tests/gates/frontend/struct_result_type_refused.sh, mutation-proven (its ledger). The user's decision 3(c).

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above and *Resolution* below. Reproduced on the 6.7.9 lane
tip @ 07c97d5d before the fix: the repro builds rc 0 and runs to SIGSEGV (139). As filed:
🟡 OPEN — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: the repro compiles clean (rc 0, no diagnostic) and the binary dies of SIGSEGV (rc 139). The same with
the installed 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers (6.7.0 is where an inherent `impl Q {` starts to parse).
The free-call form (`var G3: Q = mkf();`), the same method line after the first top-level statement, and a 24-byte
method result are each refused by name ("'Q_mk' returns a struct by value, and a struct result needs storage in a
fn's frame — call it inside a fn").
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D6 (a dyn destination; D6 refuses that form for a
dyn, `_gvi_dyn_mcall`, gate row C9b).
**Severity:** High — a clean build of a program that cannot run (SIGSEGV before `main`), with no diagnostic.
**Affects:** cycc 6.7.0 – 6.7.8, x86_64 measured (the replay is shared frontend code)

## Summary

A global declared before the first top-level statement (the declaration zone) is initialised by a replay of its
initialiser. A 9-16 byte struct result comes back in rax:rdx and the replay has no frame to receive it. For a whole
free call that is refused by name (6.6.6 / 6.6.11, `_refuse_toplevel_pair_init`), and after the first statement
PARSE_VAR refuses the method form too. In the zone a METHOD call (`Q0.mk()`) gets neither: the replay stores rax —
the struct's first WORD — into the global's slot as if it were the address of an inline struct, and the first
`G2.a` dereferences it.

## Reproduction

`docs/development/issues/repros/2026-10-10-zone-global-from-method-struct-call-crashes.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q = Q { self.a + 1, self.b + 2 }; return q; } }
var Q0: Q = Q { 4, 5 };
var G2: Q = Q0.mk();                     # compiles; the binary SIGSEGVs (rc 139); want exit 57
syscall(60, G2.a * 10 + G2.b);
```

```
actual:   compile rc 0, no diagnostic; run: Segmentation fault, rc 139
expected: refused by name, as `var G3: Q = mkf();` in the same place and this line after a statement are:
          error: 'Q_mk' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`_gvi_expr` (`src/frontend/parse_decl.cyr:5257`) calls `_refuse_toplevel_pair_init`
(`src/frontend/parse_fn.cyr:4468`), which returns at its first test for a method call: `_gcall_open(S, ti)` on the
receiver name `Q0` finds no `(`. It then parses the initialiser with the struct-copy arms up and stores rax. 6.7.8
added the method case for a dyn destination only (`_gvi_dyn_mcall`, `src/frontend/parse_types.cyr:1818`).

## Proposed fix

Refuse a whole METHOD call returning a 9-16 byte struct in the zone replay by name, the way `_gvi_dyn_mcall` does for
a dyn — generalise that helper to any struct destination (the method's return class from `_ret_agg_class`). Rows: the
repro (refused, rc 1, the named message); a chain `Q0.mk().mk()`; a generic method; an 8-byte method result (stays
legal: it fits rax); the free-call and post-statement forms unchanged.

## Consumer-side workaround

Initialise the global inside a fn (`fn init() { G2 = Q0.mk(); }`) or declare it after the first top-level statement
(where the same line is refused by name, so the build says what to do).

## Resolution (6.7.9)

The post-statement path already refused every one of these shapes: PARSE_VAR's top-level arm ends in
`_sc_global_receive` (parse_fn.cyr), whose struct half refuses a whole method / operator result recorded with no temp
(`_sc_whole` -1: `_sc_pre` gives a 9-16 B result no frame at top level, `_sc_post` records it) into a global of the
same struct. The zone's replay, `_gvi_expr` (parse_decl.cyr), ran only the type half, `_sc_global_mismatch`. That
struct half is now its own helper, `_sc_global_pair`, called by both: `_sc_global_receive` keeps its dyn and vector
arms in front of it, and `_gvi_expr` calls it where it called `_sc_global_mismatch`. A line refused INSIDE its
initialiser is that refusal alone. That covers an operand, as in `var G: Pt = mk2(3) + H;` (struct_value_codegen L15,
one error since 6.7.6), and a bad argument. The zone checks `_scv_err` before the result refusal. `_scv_disarm` sets
`_scv_err` when `_had_error` went from 0 at the arm to 1 at the disarm. The follow-up commit after bite 19 (met in
passing) moved that test into the shared `_sc_global_pair`, so the post-statement line reports once too (rows
Z11-Z13). Before it, that line drew a second error for the result.

Premise check, past the filing: the hole was wider than a method on a single name. The same zone line also built and
SIGSEGV'd for a generic method (`Q0.gmk(1)`), a wrapped method (`(Q0.mk())`) and an overloaded operator (`Q0 + Q1`,
`Q_add` returning `Q`). The post-statement line refuses all of them, and the guide's top-level section already said
"the method and operator forms alike" are a compile error at top level, the leading block included. The fix covers
them all, because it keys on the call's record and not on the token shape. The proposed fix (generalise
`_gvi_dyn_mcall`, which matched only `IDENT . IDENT ( .. ) ;`) would have missed the wrapped and operator forms. That
helper is now redundant: a dyn is a 16 B struct, so the shared check refuses `var Z2: dyn Show = Z.me();` too
(dyn_checked.sh C9b, now positioned at the `;`, as C9a after a statement is). It is removed. Unchanged: the chain
`Q0.mk().mk()` (`_method_chain` refused it already); a 24 B result (`_sc_pre`); the free call
(`_refuse_toplevel_pair_init`); an 8 B result, which fits rax and stays legal; an untyped `var G = Q0.mk();` and a
scalar annotation, which keep the first word, as after a statement.

Rows, in tests/gates/frontend/struct_result_type_refused.sh. Each Z row needs exactly one error line:
- Z1 the repro verbatim; Z2 the chain; Z3 a generic method; Z4 `(Q0.mk())`; Z5 the operator.
- Z6 the free call, Z7 a 24 B method and Z8 the post-statement line (all unchanged).
- Z9 a refused right operand (`Q0 + Q0.mk()`) and Z10 a bad argument (`Q0.gmk(nope)`) in the zone: that refusal
  alone.
- ZK1 an 8 B method in the zone (7); ZK2 untyped, the first word (50); ZK3 the workaround, the call in a fn (57).
  Each acceptance is checked against a field-by-field control.

Mutations, in scratch trees, with the gate run there:
- the 6.7.8 compiler and the pre-fix tree: RED Z1 Z3 Z4 Z5, each BUILT;
- `_gvi_expr` back on `_sc_global_mismatch` alone: RED Z1 Z3 Z4 Z5 and dyn_checked C9b;
- `_sc_global_pair` without its -1 refusal: RED Z1 Z3 Z4 Z5 Z8 and dyn_checked C9a C9b;
- `_gvi_expr` without its `_scv_err` test: RED Z9 Z10 (two error lines) and struct_value_codegen L15.

The aarch64, cx and PE forks built from the tree refuse Z1 / Z3 / Z4 / Z5 / Z9 / Z10 the same way, with one error
line each, and build ZK1 (7 under qemu-aarch64). The corpus differential compared the pre-fix stage-1 compiler with
the fixed one over 1,064 sources: the `.tcyr` / `.bcyr` / `.fcyr` corpus, `programs/`, `cbt/`, `lib/`, the test
fixtures and the issue repros. Output is byte-identical, with the same exit codes and diagnostics, except for the
repro. The guide's top-level section names the zone forms.
