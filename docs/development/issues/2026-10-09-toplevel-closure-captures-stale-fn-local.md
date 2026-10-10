# A top-level closure captures a global from the previous fn's dead locals when the names match — SIGSEGV — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B). The repro compiles with no diagnostic and exits 139 on x86_64. It exits 139 on aarch64 too (a cross
compiler built from the merged tree, run under qemu-aarch64). 12 is right, and it is what the same file gives when
`w`'s parameter is renamed. It fails the same way when the name is one of `w`'s locals rather than a parameter, or
its second parameter. A closure inside a fn reading the same global is right. Same results on the 6.7.6 tag, 6.7.0,
6.6.10, 6.6.5 and 6.6.0.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
It is a parser / codegen bug in the closure literal's snapshot of the enclosing locals. It is the same stale-table
class as
[the coroutine's slot-0 name](2026-10-09-coroutine-slot-zero-keeps-previous-fn-local-name.md) (6.7.12), so whichever
lane lands first should check the other site.
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
