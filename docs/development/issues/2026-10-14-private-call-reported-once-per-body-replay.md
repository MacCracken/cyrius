# One call of another file's `private` fn inside an `#inline` or generic body is reported once per replay of the body — three identical errors — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F2, before and after its
const-context fix) and on the installed 6.7.2 and 6.7.9 compilers: identical everywhere.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F2 (checking that the const-context visibility refusal of
`issues/archived/2026-10-09-const-context-calls-private-const-fn.md` is reported once), outside that issue's scope.
**Severity:** Low — the program is refused correctly; the same error is printed once per replay of the body (its
definition, then each `#inline` expansion or generic instance), so one violation reads as several.
**Affects:** cycc 6.5.0 (`private`) through the 6.7.11 genfe lane tree (measured: 6.7.2, 6.7.9, the lane tree).

## Reproduction

`priv.cyr`:

```cyrius
private
const fn pk(): i64 { return 3; }
```

`in2.cyr` (beside it):

```cyrius
include "priv.cyr"
#inline
fn w(): i64 { return pk(); }
fn main(): i64 { return w() + w(); }
syscall(60, main());
```

```
$ build/cycc < in2.cyr > /dev/null
error:<source>:3:25: 'pk' is private to its file
error:<source>:3:25: 'pk' is private to its file
error:<source>:3:25: 'pk' is private to its file
```

Expected: one error at 3:25.

| body | calls | errors at the one site |
|---|---|---|
| `#inline fn w(): i64 { return pk(); }` | `w() + w()` | 3 |
| `fn gg<T>(x: T): i64 { return pk(); }` | `gg(1) + gg(a)` (`a: i32`) | 3 |
| `#inline fn w(): i64 { const L = pk(); return L; }` (6.7.11: a const context checks its call) | `w() + w()` | 3 (plus the local-const issue staged beside this one) |

A `#deprecated` callee in the same bodies warns once per site.

## Root cause

`src/frontend/parse_fn.cyr` at the lane tree (after unit F2): `_DEPRECATED_WARN` (:6015) has said its warning once per
call site since 6.6.16 — a re-parse names the same token for the same callee, so `_dep_seen` (:6040) keeps a
(token, callee) list and returns early on a repeat. `_vis_check` (:6159), called beside it from `_callee_site_checks`
(:6081), has no such list: every re-parse of the body (the definition, each inline replay, each generic instance)
reports the site again.

## Proposed fix

Give `_vis_check`'s report the same per-site memory (`(ti, fi)` seen → set `_had_error`, return 1, print nothing), so
the verdict is unchanged and the line is printed once. Rows: the table above, one error each; two different call sites
of one private callee still give two errors; the deferred (forward-reference) report path keeps its one line.
