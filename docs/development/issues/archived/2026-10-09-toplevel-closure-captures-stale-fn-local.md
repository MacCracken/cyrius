# A top-level closure captures a global from the previous fn's dead locals when the names match — SIGSEGV — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 13, l679-crit; CHANGELOG [6.7.9]) Outside a fn the closure's capture lookup is empty (`_cl_ctx_enter`, told by the closure's own `_fnst_save` block whether it sits in a fn), so a top-level closure reads the global: the repro exits 12 (was 139) on x86_64, aarch64 (qemu), cx (was 7) and PE (wine, was 5). Gate `frontend/toplevel_closure_stale_locals.sh` (15 rows × host / cx / aarch64, mutation-proven); 806 of 807 tree sources compile identically (the 807th is the repro).

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above and *Resolution* below (reproduced on the 6.7.9 lane tip
@ 98496b04 before the fix: rc 139). As filed: 🟡 OPEN — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B). The repro compiles with no diagnostic and exits 139 on x86_64. It exits 139 on aarch64 too (a cross
compiler built from the merged tree, run under qemu-aarch64). 12 is right, and it is what the same file gives when
`w`'s parameter is renamed. It fails the same way when the name is one of `w`'s locals rather than a parameter, or
its second parameter. A closure inside a fn reading the same global is right. Same results on the 6.7.6 tag, 6.7.0,
6.6.10, 6.6.5 and 6.6.0.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-09 by the 6.7.7 B6 (default and named arguments) review
(`scratchpad/review-b6-spec/repros/preexisting_toplevel_stale_local_capture.cyr`). It predates B6.
**Severity:** High — a silent miscompile: a clean build that crashes, or reads a dead stack slot, with no diagnostic.
**Affects:** cycc ≤ 6.7.6 and the merged 6.7.7 (measured 6.6.0, 6.6.5, 6.6.10, 6.7.0, the 6.7.6 tag, the 6.7.7 tip),
x86_64 and aarch64.

## Summary

A closure literal snapshots the enclosing fn's local table so its pre-scan can tell a capture from a global. At top
level there is no enclosing fn, but the local count and the slot names still hold the LAST fn emitted before the
closure. So a global the closure reads, whose name matches one of that fn's locals or parameters, is taken as a
CAPTURE of that fn's slot. The env is filled from a stack slot of a frame that does not exist at top level. In the repro
that copy crashes (rc 139); what it reads when it does not crash is whatever that address holds.

## Reproduction

`docs/development/issues/repros/2026-10-09-toplevel-closure-captures-stale-fn-local.cyr`:

```cyrius
include "lib/fnptr.cyr"
include "lib/alloc.cyr"
fn w(qa): i64 { return qa; }
alloc_init();
var qa = 5;
var cl = |n| n + qa;
syscall(60, fncall1(cl, 7));
```

```sh
cat docs/development/issues/repros/2026-10-09-toplevel-closure-captures-stale-fn-local.cyr | build/cycc > /tmp/tl \
  && chmod +x /tmp/tl && /tmp/tl; echo $?
# actual:   compiles clean, rc 139 (x86_64 and aarch64)
# expected: 12 — the result with `fn w(zz): i64 { return zz; }`, or with the closure made inside a fn
```

The same crash occurs with `fn w(x, qa)`, with `fn w(x): i64 { var qa = 1; return qa + x; }`, and with an unrelated
global declared after the closure.

## Root cause

The closure literal in `src/frontend/parse_expr.cyr` (merged-tree lines):

```cyrius
var cl_saved_flc = GFLC(S);                                   # :4343
var cl_locsnap = _cl_save_locals(S, cl_saved_flc);            # :4344
...
var cl_ctx = _cl_ctx_enter(S, cl_locsnap, cl_saved_flc);      # :4362
_cl_prescan_captures(S, cl_zero);
```

`GFLC` is not reset to 0 when a fn's body ends. At top level it still counts the previous fn's slots, and the name
table (`S + 0x5D9D000`) still holds their names. `_cl_prescan_ident` (`:412`) finds the global's name in that
snapshot (`_cl_snap_find`) and records a capture (`_cl_cap_add`). The env construction then copies the dead slot.

## Proposed fix

Snapshot nothing when the closure is not inside a fn:

```cyrius
var cl_saved_flc = 0;
if (GINFN(S) == 1) { cl_saved_flc = GFLC(S); }
```

Alternatively, clear the count at each fn's end. That touches every top-level reader of the local table, so measure
it with the differential corpus first. A closure nested in a top-level closure keeps its enclosing captures through
`_cl_ctx_enter`'s extension, which is untouched by either form. Before landing, confirm that nothing at top level
lives in a local slot that a closure must capture. A top-level `for (var k = 0; k < 3; k = k + 1) { var cl = |n| n +
k; ... }` sums to 33 today, which is right.

Gate: the repro and its three variants, plus the in-fn control, on x86_64 and aarch64. Add a mutation that drops the
`GINFN` test.

## Consumer-side workaround

Make the closure inside a fn, or give the global a name no fn above it uses for a local or a parameter.

## Resolution (6.7.9, the critical lane's bite 13)

- **The fix keeps the table restore and empties only the lookup.** `_cl_ctx_enter` (parse_expr.cyr) takes the
  closure's `_fnst_save` block. When that block records that the closure is not inside a fn (`_fnst_was_infn`,
  parse.cyr: the enclosing GINFN, read before the closure enters its own fn), the snapshot it installs is empty, so
  `_cl_prescan_ident` finds no enclosing local and the body reads the global. The proposed form (`cl_saved_flc = 0`
  outside a fn) would also have skipped the save / restore of the local tables around the closure, leaving the
  closure's own slot names in the table at top level in place of the last fn's: a second change, to anything that
  reads the table there. This form changes the capture decision and nothing else. A closure nested in a top-level closure is inside a
  fn (`_fnst_save` sets GINFN for the outer closure's body), so it still captures the outer closure's names (row N).
- **Wider than filed**: a closure in a declaration-zone initializer (compiled after every fn, so the fn BELOW it was
  the stale one), in a top-level `if` block, with a block body, over a struct local of the fn, and in a top-level
  `for (var k ..)` when the fn above has a `k` all captured a dead slot. The filed "33 is right" premise holds only
  with no `k` above the loop. That case is now control K4, and the `k`-named fn above it is row I. cx gave a wrong
  value rather than a crash (7, 14, 103, 126, 8), and PE under wine exited 5.
- **Rows**: `tests/gates/frontend/toplevel_closure_stale_locals.sh` has the repro and its three variants (A–D), the
  wider shapes (E–I), the field-label shape at top level (L) and the nested closure (N). The controls are K1 (renamed parameter), K2 (closure in a fn reading
  the global), K3 (closure in a fn capturing its parameter) and K4 (top-level `for`, no fn above). It runs on host
  x86_64, cx (cxvm) and aarch64 (qemu). Mutations: the in-fn test dropped makes 32 of 45 rows red (row L stays green
  on cx, which copies the needless capture harmlessly). The test inverted makes 35 of 45 red (K3 and N are refused
  `undefined variable` as well).
- **Unchanged**: of 807 tree sources (the four src compilers, every `.tcyr`, programs, benches, fuzz and the filed
  repros), only this repro compiles differently (stdout, stderr and exit code). The 28 gates that exercise closures
  pass.
- **The stale-table class**: the coroutine's slot-0 filing (`2026-10-09-coroutine-slot-zero-keeps-previous-fn-local-name.md`)
  is the in-fn half of the same class and has its own bite. The field-label filing
  (`2026-10-09-closure-prescan-reads-field-names-as-captures.md`) no longer reaches a dead slot at top level: its
  shape below `fn w(y)` crashed (rc 139, row L) or, without `lib/alloc.cyr`, was refused for a heap env, and now
  gives 16 / compiles. Its in-fn shape (a label taken for a capture of an enclosing local) is still that filing's.
