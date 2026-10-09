# A call to a fn defined later is never arity-checked — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 with the tree's `build/cycc`: both repros
compile clean (rc 0, no diagnostic) and run with the surplus argument dropped and a missing one unbound. The same calls
placed after their callees are refused (`'g' expects 1 argument, got 2`). The user decided on 2026-10-09 (fork F2 of the
6.7.7 B6 plan) that EVERY forward call is arity-checked; it is scheduled, not yet fixed.
**Placement:** 6.7.7 (being fixed in this release). B6 (default and named arguments) packs it with the min..max arity
check: fork F2, decided by the user 2026-10-09 ("EVERY forward call is arity-checked, not only calls to defaulted fns",
roadmap.md § Spec, B6). Never 7.x.
**Discovered:** 2026-10-09 during the 6.7.7 B6 planning (both planners; repro `fwd_arity_unchecked.cyr`).
**Severity:** Medium — a silent wrong binary (a surplus argument dropped, a missing one bound to whatever its register
held) with no diagnostic. The workaround is to define the callee above its first call.
**Affects:** cycc 6.2.41 – 6.7.6. The check has skipped forward callees since it was added (6.2.41 as a warning, an
error since 6.5.1).

## Summary

`_CHECK_ARITY` checks only a callee whose body has already been emitted. A call to a fn defined further down the
file, or in a later include, is accepted at any argument count. This holds on every call path that reaches the check:
a plain call, a call that passes too few arguments, an `o.m(..)` method call and a `return f(..)` tail call. A fn
defined inside a top-level block and called above that block is accepted too.

The guide states the exemption as a rule: "Forward calls are exempt from the check — the callee has no body yet"
(`docs/guides/cyrius-guide.md:386`). That reason no longer holds: pass 1 records every definition's parameter count
before pass 2 parses any call.

## Reproduction

`docs/development/issues/repros/2026-10-09-forward-call-arity-unchecked.cyr` covers the plain, too-few, method and
tail shapes. `docs/development/issues/repros/2026-10-09-forward-call-arity-unchecked-toplevel-block.cyr` covers a fn
inside a top-level block.

```sh
cat docs/development/issues/repros/2026-10-09-forward-call-arity-unchecked.cyr | build/cycc > /tmp/fwd && chmod +x /tmp/fwd && /tmp/fwd; echo $?
# actual:   rc 0, no diagnostic, exit 0
# expected: error:<source>:12: 'g' expects 1 argument, got 2      (the tail call)
#           error:<source>:16: 'g' expects 1 argument, got 2
#           error:<source>:17: 'h' expects 3 arguments, got 2
#           error:<source>:18: 'P_m' expects 2 arguments, got 3   (the method)
cat docs/development/issues/repros/2026-10-09-forward-call-arity-unchecked-toplevel-block.cyr | build/cycc > /tmp/tlb && chmod +x /tmp/tlb && /tmp/tlb; echo $?
# actual:   rc 0, exit 6 (g ran with a = 5; the 6 was dropped)
# expected: error:<source>:6: 'g' expects 1 argument, got 2
```

Run them from the repo root.

## Root cause

- `src/frontend/parse_fn.cyr:1431`, the first line of `_CHECK_ARITY`:
  `if (need_off == 1) { if (L64(_fnt_offsets + fi * 8) < 0) { return 0; } }`. A callee with no emitted body has
  offset -1. The header comment (:1415-1429) gives the reason: "a forward-declared callee has offset -1 and pc not yet
  known → checking would 556-false-positive building main.cyr". That stopped being true once pass 1 began recording
  parameter counts.
- Pass 1 now records every definition before pass 2 starts:
  - `_prescan_fn_sig` → `_prescan_params_scan` (:9837) writes `_fnt_params`, and `SFDS(S, fi, start_ti + 1)` (:9993)
    stamps the definition's `fn` token (v6.3.5 CO-01);
  - `_prescan_tail` (:10590) covers fns after the first top-level statement (6.6.5);
  - `_prescan_block_fn` (:10574) covers a fn inside a top-level block (6.6.17).
- All five call sites pass `need_off = 1`: the tail arm (:987), `_owncall_args` (:2700), PARSE_FNCALL (:4571), the
  method loop (`src/frontend/parse_decl.cyr:1645`) and the two operator dispatches (`src/frontend/parse_expr.cyr:5875`,
  `:5923`). The inline replay (:4370) passes 0, because its callee is always backward.

## Proposed fix

Check the call whenever pass 1 recorded the callee, which is one more condition on the same line:

```cyrius
if (need_off == 1) { if (L64(_fnt_offsets + fi * 8) < 0) { if (GFDS(S, fi) == 0) { return 0; } } }
```

A callee pass 1 never recorded keeps the skip. That is a name REGFN registers at the call because no definition exists
(GFDS 0); it ends in the undefined-function diagnostic.

**Evidence that nothing valid stops compiling.** B6 Plan A's scratch compiler has exactly that line and nothing else
changed in `src/` (`cc_gfds`, built at 2fb6ad8b). It was re-measured on 2026-10-09 against the e44470b7 tree over 630
files: every `.tcyr` (recursive), every top-level `programs/*.cyr`, the seven `src/main*.cyr` forks (the self-compile
included) and `cbt/cyrius.cyr`. Result: **0 arity errors** under `cc_gfds` and under `build/cycc`. 629 of the files
compile with rc 0; `programs/io.cyr` is a library fragment that fails on its own (undefined `io_state`) under both. Both
repros above give exactly the expected errors under `cc_gfds`.

**The fix also needs:**
- the `_CHECK_ARITY` header comment rewritten;
- the guide bullet at `docs/guides/cyrius-guide.md:386` rewritten (forward calls are checked);
- a gate row with both repros, plus a mutation that drops the GFDS half.

## Consumer-side workaround

Define (or include) a callee above its first call. That call is then checked.
