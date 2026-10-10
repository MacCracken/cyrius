# The overload router sends a call to a later-defined `_str` sibling without judging its arity — since 6.7.7's F2 the call is refused, naming a fn the source never called — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B). The repro is refused with `error:<source>:10: 'pr_str' expects 2 arguments, got 1`. The source calls
`pr(s)`, and `pr` takes one argument. The 6.7.6 tag's compiler builds the same file clean, and it exits 161, with
garbage passed for `pr_str`'s `k`. With `pr_str` moved above `main`, both compilers route nothing and exit 11. With
a one-parameter `pr_str` defined below, both route and exit 71. Routing depends on definition order.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
This is a decision-only item, asked at 6.7.10's open: the call-arguments lane owns `_fnc_route` and `_CHECK_ARITY`,
and the fix changes which fn a call reaches.
**Discovered:** 2026-10-09 by the 6.7.7 B6 (default and named arguments) lane, bite 3 (fork F2: every forward call
arity-checked).
**Severity:** Medium — a call that is valid as written is refused, naming a fn the source never called. Workaround:
define the sibling above its first routed call. Before 6.7.7 the same call compiled and passed garbage (a silent
wrong value).
**Affects:** the merged 6.7.7 (the refusal, since F2). The silent garbage pass on 6.5.1 – 6.7.6 (measured on 6.7.0
and the 6.7.6 tag: exit 161 on both), since the v6.5.1 arity gate let a not-yet-defined target through.

## Summary

The v5.10.25 overload router sends `base(arg, ..)` to a `<base>_str` sibling when the first argument is a Str. The
same holds for `<base>_int` when the first argument is an i64-returning call into a `: cstring` base. The v6.5.1 gate
`_OV_ARITY_OK` keeps a redirect only when the sibling accepts the call's argument count. A sibling that is not yet
DEFINED (no emitted body) is let through without that check, "routed as before 6.5.1".

Before 6.7.7 the routed call was not arity-checked either, because forward calls were exempt. So `pr(s)` reached a
`pr_str(s: Str, k)` defined further down and passed whatever was in the register for `k`. 6.7.7's fork F2 checks every
forward call against pass 1's recorded count. The routed call is now refused: "'pr_str' expects 2 arguments, got
1".

So the result depends on where `pr_str` is defined:

| `pr_str` | Defined above the call | Defined below the call |
|---|---|---|
| `(s: Str, k)`, 2 params | not routed: `pr` runs, exit 11 | routed: 6.7.6 exit 161 (garbage `k`); 6.7.7 refused |
| `(s: Str)`, 1 param | routed: exit 71 | routed: exit 71 |

## Reproduction

`docs/development/issues/repros/2026-10-09-overload-router-forward-target-arity.cyr`:

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn main(): i64 { alloc_init(); var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }
fn pr_str(s: Str, k): i64 { return k; }
syscall(60, main());
```

```sh
cat docs/development/issues/repros/2026-10-09-overload-router-forward-target-arity.cyr | build/cycc > /tmp/ov \
  && chmod +x /tmp/ov && /tmp/ov; echo $?
# 6.7.7 tip: error:<source>:10: 'pr_str' expects 2 arguments, got 1   (no binary)
# 6.7.6 tag: compiles clean, exit 161
# expected (routing judged by count, as for a sibling defined above): exit 11
```

The B6 lane measured the corpus and found no program with this shape.

## Root cause

`_OV_ARITY_OK` (`src/frontend/parse_fn.cyr:5583`; merged-tree lines) begins with:

```cyrius
if (L64(_fnt_offsets + fi * 8) < 0) { return 1; }
```

A target with no emitted body is accepted before the count is compared. The comment above it (`:5574`–`:5582`) gives
the reason, "the param count is not yet knowable". That stopped being true once pass 1 began recording every
definition's parameter count (`_prescan_params_scan` / `SFDS`), which is the fact F2 relies on. Its line in
`_CHECK_ARITY` is `:1421`:

```cyrius
if (need_off != 0) { if (L64(_fnt_offsets + fi * 8) < 0) { if (GFDS(S, fi) == 0) { return 0; } } }
```

Both router arms call the gate: the `_str` arm at `:5715` and the `_int` arm at `:5745`, both in `_fnc_route`
(`:5683`). The F2 check then judges the routed target, not the written one.

## Proposed fix

This is the user's decision, because it changes which fn a call reaches. Default: judge a pass-1-recorded target by
its count, as F2 does:

```cyrius
if (L64(_fnt_offsets + fi * 8) < 0) { if (GFDS(S, fi) == 0) { return 1; } }
```

The count line below it then decides: `_fnt_params`, and B6's min (`_pd_min`). Confirm that B6's defaults row is
filled in pass 1 before relying on `_pd_min` for a forward target. A target no definition recorded keeps today's
permissive answer.

The effect: a sibling below the call routes exactly as one above it does. The repro calls `pr` and exits 11. A
one-parameter `pr_str` below still routes (71).

The alternative is to keep routing a forward target and let F2 refuse it, which is today's tip. In that case the
diagnostic should say the call was routed: `'pr(s)' was routed to 'pr_str', which expects 2 arguments`.

Measure the corpus as the B6 lane did, comparing which fn each routed call reaches before and after. Add a gate row
for each table cell above, with a mutation that drops the GFDS half.

## Consumer-side workaround

Define (or include) the `_str` / `_int` sibling above the first call of its base, or give it the base's arity.
