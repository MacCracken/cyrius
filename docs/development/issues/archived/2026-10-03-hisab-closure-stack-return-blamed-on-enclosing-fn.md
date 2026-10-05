# A closure's `return <: stack call>` is booked against the ENCLOSING fn — a false "bind both" error and a misattributed warning — ✅ RESOLVED in 6.6.16

**Status:** ✅ **RESOLVED in 6.6.16** (lane srca, bite srca-1) — both post-parse pair scans skip a closure body,
and the mixed-return warning judges each closure body as its own fn; the filed repro exits 0 against the
6.6.16 tree (D1-D3 clean and running 0, C1-C3 holding). See CHANGELOG [6.6.16].
**Placement:** **6.6.16** (placed 2026-10-04 at the slot open; the user listed the open issues for this release).
**Discovered:** 2026-09-30 from hisab during its 3.3.1 work. hisab's autodiff × optimizer recipe hit it,
and it is tracked as hisab roadmap item D082. hisab's maintainer approved filing on 2026-10-03.
**Severity:** Medium. Correct code is refused with a hard error inside a fn, and the error's own
suggested fix compiles clean and reads an unset `rdx`, which SIGSEGVs when used. A workaround exists.
**Affects:** cycc **6.6.0 – 6.6.14**. Each pin was run from a throwaway project whose `cyrius.cyml` pins
it, and `cyrius build -v` printed `compiler: /home/macro/.cyrius/versions/<v>/bin/cycc` on every row.
First-bad is unknown, and 6.6.0 is only the oldest pin installed here (no 6.5.x is): user-declared
`enum X: stack` exists since 6.5.55, and pair-ness has been tracked through `return` since 6.5.67
(CHANGELOG [6.5.55], [6.5.67]); the row below with a user enum shows the defect does not need `Result`.

## Resolution (6.6.16)

**Root cause confirmed as filed.** `_pair_prescan` (`src/frontend/parse.cyr`) and `_warn_mixed_pair_returns`
skipped a nested body only at a `fn` token; a closure literal has none, so its `return` was scanned as the
enclosing fn's. The in-parse flagging (`PARSE_RETURN`, `?`) was not involved — a closure body parses with
`_cur_fn_ix` set to the closure. Two problems the filing did not name were found by the planning premise
check and are fixed by the same change: a REAL pair fn whose closure says `return 0;` drew a false warning,
and a real mixed-return fn holding a closure was warned at the closure's return (column 28) instead of its
own (column 69).

**Fix.** Both scans skip a `{` that opens a closure body. `_tok_is_closure_body(S, k)`: the `{` is
immediately preceded by `|` (token 35) or `||` (token 54). That is exact for today's grammar — closure params
carry no type and no return annotation, and `{` never begins an expression — and the closure parser
(`parse_expr.cyr`) now carries a comment naming the dependency. `_tok_skip_block(S, k, n)` jumps to the
matching `}`. A brace-less closure needs no skip (an expression holds no `return`).

**The closure is judged as its own fn.** The filing's title is the whole rule — the closure's returns
belong to the CLOSURE — so taking them away from the enclosing fn is only half of it. A first cut stopped
there, and a genuinely mixed closure (`|x| { if (x > 0) { return h(x); } return 0; }`, whose
`var t, v = fncall1(g, 0)` reads a stale rdx) lost the only warning it had, found in review.
`_warn_mixed_pair_returns` now visits every closure body at any depth (`_warn_closure_block`): pair-returning
when its own body, nested closures and fns skipped, says `return f(..)` or `f(..)?` with `f` flagged 256 —
the test that flags a fn — and then its first plain return is warned as *"a closure in `<fn>` returns a
`: stack` pair on another path but a SINGLE value here"*. A mixed closure at top level and a `?`-then-plain
closure are warned for the first time. The filing's side
question ("should the closure's value carry a pair-return mark for a later `var t, v = fncallN(g, ..)`?")
needs no answer: that bind does not read the enclosing fn's flag, and it behaves exactly as before — the
binaries of every previously-buildable row are byte-identical, and `var g = mk(41); var tg, pl =
fncall1(g, 1);` now builds and exits 0.

**Verified.** The repro, VERBATIM, against the tree through a throwaway HOME + CYRIUS_HOME (each `compiler:`
line the staged tree cycc): exit 0. At the slot open (0bf9b773): exit 3. The extra shapes in the filing's
second table — the forwarding wrapper, the `?` closure body — build clean and run 0. Differential over all
439 `tests/tcyr` files on x86 and aarch64 (against the slot open): 0 byte, 0 diagnostic and 0 build-status
differences; the same over `programs/`, the CLI, benches and fuzz (110 files) and the 133 sibling `dist/*.cyr`
bundles. The pinned gate is `tests/gates/frontend/stack_enum_closure_return_scope.sh` (41 rows, with a
mutation ledger: removing either scan's skip, the closure-unit check, its nested-closure skip or its `?` test
each turns rows red; the slot open is 33 red).

**hisab.** Nothing to change in-tree (its closure binds both halves since 3.3.1). Its autodiff recipe may
return `ad_grad_into(...)` from the closure again once it pins ≥ 6.6.16 (D082) — adopting it is hisab's
job; the note goes in hisab's own issue file
(`hisab/docs/development/issues/2026-10-03-cyrius-closure-stack-return-blamed-on-enclosing-fn.md`, see
`drafts/srca-1/filings.md`).

## Summary

Take a closure whose body ends `return f(...)`, where `f` returns a `: stack` enum such as `Result`.
cycc treats that `return` as one of the **enclosing fn's** own returns. The enclosing fn is
flagged pair-returning (fn flag 256), although it returns one value: the closure, or whatever its
own `return` says. Then:

- the enclosing fn's own plain `return` draws **a warning aimed at that fn**:
  `` `mk` returns a `: stack` pair on another path but a SINGLE value here ``;
- **every `var g = mk(...)` inside a fn is refused with an error**:
  `` a `: stack` enum returns two values — bind both: `var tag, val = f();` ``;
- at top level the same bind draws only the warning, because the single-variable refusal runs
  only inside fns (`parse_decl.cyr:4064`, `if (GINFN(S) == 1)`);
- the flag **propagates through forwarding wrappers**. With `fn fwd(b) { return mk(b); }`,
  `var g = fwd(1)` inside a fn is refused too, at a call site that never sees a closure;
- **following the error's hint is wrong code.** `var t, v = mk(41);` compiles with only the
  warning. `t` is the closure, and `v` is whatever `rdx` held. `fncall1(v, 1)` exits **139**, and
  `fncall1(t, 1)` works.

Any `return` of a flagged callee in the closure body counts, including `return Ok(r)`, so the
closure need not forward a call. A closure body `{ var r = h(x + b)?; return Ok(r); }` is booked
the same way. A user-declared `enum R: stack { A(v); B(e); }` in place of `Result` gives the same diagnostics
on every pin from 6.6.0 to 6.6.14, so this is not specific to `Result`.

## Reproduction

`docs/development/issues/repros/2026-10-03-hisab-closure-stack-return-blamed-on-enclosing-fn.sh <pin>`
is self-proving. It builds three defect rows and three controls in a throwaway project pinned to
`<pin>`. Its exit code is the number of defect rows that drew a `: stack` diagnostic, failed to
build or failed to run, so **0 means fixed**. Exit 99 means a control failed: the `: stack` checks
themselves changed, so it cannot give a verdict. Its header documents each row.

The minimal form, with `[deps] stdlib` including `result` and `fnptr`:

```cyrius
fn h(x) { return Ok(x); }
fn mk(b) { var g = |x| { return h(x + b); }; return g; }   # mk returns ONE value
fn main() { var g = mk(41); return 0; }                    # <- error: "bind both"
var r = main();
sys_exit_group(r);
```

6.6.14 output, trimmed:

```
error:<source>:3:19: a `: stack` enum returns two values — bind both: `var tag, val = f();`
    fn main() { var g = mk(41); return 0; }                    # <- error: "bind both"
                      ^
warning:<source>:2:46: `mk` returns a `: stack` pair on another path but a SINGLE value here — …
```

| row | shape | 6.6.0 – 6.6.14 | expected |
|---|---|---|---|
| D1 | closure built in helper `mk`, `var g = mk(41)` inside a fn | **error** + warning on `mk` | clean, exit 0 |
| D2 | the same helper, `var g = mk(41)` at top level | **warning** on `mk` | clean |
| D3 | closure built inline in `fn run(b)`, which returns 0 | **warning** on `run` | clean |
| C1 | `fn bad(x) { if (x > 0) { return h(x); } return 0; }`: a real mixed return | warning on `bad` | warning (control) |
| C2 | `var t = h(1);` inside a fn: a real lossy bind | error | error (control) |
| C3 | the closure binds both halves and returns 0 | clean, exit 0 | clean (control) |

These rows were also checked on 6.6.3, 6.6.12, 6.6.13 and 6.6.14 from scratch programs. Each pin
gave the same result:

| shape | build | run |
|---|---|---|
| `fn fwd(b) { return mk(b); }`, then `var g = fwd(1)` inside a fn | **error** + warning on `mk` | — |
| closure body `{ var r = h(x + b)?; return Ok(r); }`, then `var g = mk(1)` inside a fn | **error** + warning | — |
| `var t, v = mk(41); return fncall1(v, 1);` (the hint, followed) | warning only | **139** |
| `var t, v = mk(41);` then `var tg, pl = fncall1(t, 1); return tg;` | warning only | 0 |

Verdict paths of the script were exercised. With the D rows' closure bodies rewritten to the C3 form
(standing in for a fixed compiler) it exits 0 on 6.6.14. With C1's plain `return 0` changed to
`return Err(0)` (standing in for a "fix" that deleted the check) it exits 99.

## Root cause (read from the source; the behaviour above matches it)

`_pair_prescan` (`src/frontend/parse.cyr:104`) propagates flag 256 to any top-level fn that has a
`return IDENT (` whose callee is already flagged. Its header (`parse.cyr:93-96`) states the intent
exactly:

> ⚠ NESTED fn BODIES ARE SKIPPED. A closure defined inside the body has its own `return`, and
> counting it would flag the OUTER fn as pair-returning — over-flagging is worse than
> under-flagging here, because it routes a non-pair call into the two-register receive and reads
> a garbage rdx.

The skip keys on the `fn` token (`elif (t == 32)`, `parse.cyr:158`). **A closure literal
`|x| { … }` has no `fn` token**, so its body is scanned as the enclosing fn's and its `return h(…)`
flags the outer fn. That is the over-flagging the comment names, and the garbage `rdx` it predicts
is the 139 row above. `_warn_mixed_pair_returns` (`parse.cyr:257`) has the same skip
(`parse.cyr:295`) and the same gap. That is why the warning lands on the enclosing fn's own
`return g;` (the column in the output above is `mk`'s `return`).

A nested *named* `fn` with the same `return h(x)` body draws no `: stack` diagnostic on 6.6.14. That
fits a skip keyed on the `fn` token. This filing checked that program at compile time only.

## Proposed fix

Speculative. In both scans, skip a closure literal's body the way a nested `fn` body is skipped:
on the `|…|` parameter list that opens one, skip the following `{ … }` block, or the expression for
a brace-less closure. The closure's own returns then belong to the closure. Whether the closure's
value should carry a pair-return mark for a later `var t, v = fncallN(g, …)` is a separate design
question that this filing does not ask.

## Consumer-side workaround

Inside the closure, bind both halves and return a plain value:

```cyrius
var grad = |x, out| {
    ...
    var gt, gv = ad_grad_into(tape, root, ids, 2, out);   # not `return ad_grad_into(...)`
    return 0;
};
```

This builds clean on every pin from 6.6.0 to 6.6.14 (row C3). hisab has shipped this form since
3.3.1.

## hisab's exposure

**Nil in-tree since 3.3.1.** hisab builds exactly one closure (`tests/modules.tcyr`,
`_ot_make_closure_grad`), and its body binds both halves. The autodiff recipe in
`src/autodiff.cyr` is written the same way. Through 3.3.0 the recipe ended
`return ad_grad_into(...)`, the D1 shape, which is how this was found. Built against the 3.3.4
bundle with a helper fn on 6.6.3, 6.6.12, 6.6.13 and 6.6.14:

| recipe form | helper's result bound inside a fn | bound at top level |
|---|---|---|
| through 3.3.0 (`return ad_grad_into(...)`) | **build fails**: error + warning | warning; `opt_lbfgs` converges (exit 0) |
| 3.3.1 onward (bind both, `return 0`) | clean; converges (exit 0) | clean; converges (exit 0) |

A consumer on hisab 3.3.0 or older got the error wherever the recipe's closure sat: built by a
helper fn, or built inline in fn A, a single-variable bind of that fn's result inside another fn is
refused (probe: `fn run(b) { var g = |x| { return h(x + b); }; return 0; }` with
`var r = run(41);` inside `main` gives the error plus a warning on `run`, on 6.6.14). hisab records its
exposure as `hisab/docs/development/issues/2026-10-03-cyrius-closure-stack-return-blamed-on-enclosing-fn.md`.
