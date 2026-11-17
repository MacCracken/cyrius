# `f()?;` on a `#must_use` function warns that the result is discarded, though `?` consumes it — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-16. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-16, by rasayan's Rust → Cyrius port (M1 part 1, `src/guard.cyr`;
`rasayan/docs/development/port-parity.md` §4a).
**Reporter:** rasayan 2.0.0 port.
**Severity:** **Low–Medium.** A false positive on correct code. It matters because consumers keep `cyrius test`
warning-free: the warning forces the propagation to be written out by hand, so the one-token form of Rust's `?`, which
the value-form Result's own header documents (`f()?  # propagates BOTH halves (v6.5.74)`), cannot be used on any
`#must_use` fallible function, which is every fallible function a library marks.
**Affects:** cycc 6.7.18 (the #must_use check; every target).

## Summary

`lib/result.cyr` documents `f()?` as the propagation of a value-form Result: on Err it returns the tag and the payload
to the caller; on Ok it continues. It works. But when `f` is `#must_use`, the statement `f()?;` also draws
`warning: #must_use result of 'f' is discarded`. The result is not discarded: `?` reads the tag, returns it with the
payload on Err, and that is the whole point of the statement. The check treats `f()?;` like `f();`.

rasayan's guard layer is Rust's `guard::finite(name, value)?;` four times over, and every `validate()` from its next
milestone on is a list of such lines, so each is written out instead:

```
var t, v = _ry_guard_finite(name, value);
if (is_err_result(t) == 1) { return Err(v); }
```

## Reproduction

Filed in cyrius as `docs/development/issues/repros/2026-11-16-must-use-warns-on-question-mark-propagation.sh`. It builds
a 20-line program (a `#must_use` `check(x): Result`, an `outer` that does `check(x)?;` then `Ok(x + 1)`), counts the
warning, and runs it to prove the propagation is right (Err 7 for a negative x, Ok 4 for 3). From the cyrius root:

```sh
bash docs/development/issues/repros/2026-11-16-must-use-warns-on-question-mark-propagation.sh; echo $?
# warnings on check(x)?: 1; propagation correct at run time: yes
# repro: DEFECT PRESENT (the ? consumes the #must_use result, and the build still says it is discarded)
# 1
```

## Proposed fix

In the #must_use check, count a call that is the operand of a postfix `?` as used: `?` consumes the result whether the
statement keeps the Ok value or not. `var x = f()?;` is not warned today (the value is bound); `f()?;` should not be
either. A bare `f();` keeps its warning.

## Consumer-side workaround

Write the propagation out: `var t, v = f(); if (is_err_result(t) == 1) { return Err(v); }` (rasayan's
`src/guard.cyr`). It costs a line per check and nothing at run time.
