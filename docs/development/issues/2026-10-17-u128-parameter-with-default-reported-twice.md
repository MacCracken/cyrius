# A `u128` parameter with a default gives two errors — "it takes no default" and the D10 (a) parameter refusal — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b, x86_64; the
frontend, every target). Beside issues/archived/2026-10-08-u128-params-returns-fields-captures.md (fixed in the lane by
8d3f7caf, the user's decision D10 (a), 2026-10-16: a `u128` parameter is one error by name, "`u128` is not supported
as a parameter type yet - pass `*u128`"). The lane's row U6 (default_named_args_checked.sh) covers a default on a
LATER parameter only; a default on the u128 parameter itself was not probed. Met by the 6.7.14 frontend review.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — refused either way; the first error printed is not the decided one, and a second follows.
**Kind:** bug (diagnostic).

## Reproduction

```sh
cd <the tree>
printf 'fn f(a: i64, b: u128 = 3): i64 { return 0; }\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:1:24: parameter 'b' of 'f' is a 128-bit integer: it takes no default
# error:<source>:1:17: `u128` is not supported as a parameter type yet - pass `*u128`
printf 'fn f(b: u128 = 3): i64 { return 0; }\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:1:16: parameter 'b' of 'f' is a 128-bit integer: it takes no default
# error:<source>:1:9: `u128` is not supported as a parameter type yet - pass `*u128`
# control (one error):
printf 'fn f(b: u128): i64 { return 0; }\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:1:9: `u128` is not supported as a parameter type yet - pass `*u128`
```

The slot-open compiler gave only the default refusal (and `fn f(b: u128)` compiled). Out of order too: the 1:24 /
1:16 error prints before the 1:17 / 1:9 one, because the pass-1 default sweep runs first.

Related, and arguably two real mistakes (left to the fix's judgment): `fn f(a: i64 = 1, b: u128): i64` gives "1:18:
parameter 'b' of 'f' needs a default: it follows one that has a default (defaults are trailing)" and the 1:21
u128 refusal.

## Root cause

The pass-1 default sweep (src/frontend/parse_fn.cyr, `_pd_*`: `_pd_tclass` → class -6, `_pd_cname` "a 128-bit
integer", the "it takes no default" report near line 4514) judges the default against the parameter's type class
and refuses it; the parameter reader's `_pty_u128` (D10 (a), 6.7.14) then refuses the type itself. Neither knows the
other reported the same parameter.

## Proposed fix

One error, the decided one: the default sweep stands down for a `u128` parameter (class -6 — the type refusal will
name it), so only "`u128` is not supported as a parameter type yet - pass `*u128`" is printed; or the sweep reports
the u128 refusal itself and `_pty_u128` sees it reported (`_pty_bad` / `_tn_once` at the type token). Rows: both
repros one error at the `u128` token; the control unchanged; `fn f(b: *u128 = 0)` unchanged (a pointer default).
