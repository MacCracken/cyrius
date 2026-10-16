# A local `const k: i64 = 3;` is refused, and every later read of `k` adds "undefined variable 'k'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F3: the lane's compiler
before the unit, 2,189,840 B, and after it, 2,194,096 B).
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F3, probing a typed local const in a closure body for
`issues/archived/2026-10-11-closure-prescan-reads-declared-names-as-captures.md`. Outside that issue's scope (a diagnostic
cascade in every fn, not a capture).
**Severity:** Low — a second, misleading error after a correct refusal; nothing compiles that should not.
**Affects:** cycc 6.7.2 (local `const`) through the 6.7.11 genfe lane tree. Every target (the shared frontend).

## Reproduction

```cyrius
fn f(): i64 { const k: i64 = 3; return k; }
syscall(60, f());
```

```
error:<source>:1:22: a const takes no type annotation: its type is its value's
error:<source>:1:41: undefined variable 'k' (missing include or enum?)
```

Expected: the first line only — the const is still bound (its value is `3`).

The same in a closure body whose enclosing fn has a local `k`
(`fn f(): i64 { var k = 5; var cl = |n| { const k: i64 = 3; return k + n; }; .. }`): before unit F3 the second line was
"a capturing closure needs include "lib/alloc.cyr" for its heap env" (the pre-scan took `k` for a capture); after F3
it is the plain-fn cascade above.

## Root cause

`_cst_stmt` (src/frontend/parse_fn.cyr) returns at the `:` after `ERR_MSG`, before `_lc_push`, so the name is never
bound; the statement is then skipped to its `;` and each read of `k` is an unknown name.

## Proposed fix

After the refusal, step over the annotation to the depth-0 `=` and go on (evaluate the value, `_lc_push` the name), so
the read resolves. Check the top-level const's annotation refusal (`_ce_bad`, the same message) for the same cascade.
Row: the repro refused with exactly one error; the closure form likewise.

## Consumer-side workaround

Drop the annotation: a const's type is its value's.
