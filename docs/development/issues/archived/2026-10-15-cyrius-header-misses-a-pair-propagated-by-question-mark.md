# `cyrius header` prints `cyr_val f(..)` for a fn that is pair-returning only through a `?` on a pair call — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-5: `_hdr_body_pair` also takes `NAME(..)?` and `NAME<..>(..)?` on a pair call, in the same fixpoint; this is the compiler's third route to the pair flag. So the filed q2 is refused by name: ``error: cyrius header: 'q2' returns a `: stack` enum's (tag, payload) pair through 'parse(..)?', which its signature does not declare (its `?` returns the Err pair, in rax:rdx, aarch64 x0:x2); …``, rc 1, no q2 prototype, and parse is still `cyr_val2`. It used to print `cyr_val q2(cyr_val x);` at rc 0. A chained `?`, a generic callee, a bare `parse(x)?;` and a `: i64` signature are refused too. A closure's `?` (block or expression body) stays its own, and a method call's `?` is not seen. This is 6.7.12's D23 with D37 (the user, 2026-10-15: its reach kept). cycc's single-bind refusal is the oracle, and it agrees on all 13 shapes. Census: no lib/ header changes. Rows: `header_spellings_and_size.sh` H12 (qm.cyr verbatim, with its `q2(0 - 3)` → 13 oracle; qs.cyr's seven refusals and its word shapes; four mutations RED). Filed beside it, for 6.7.14 (High): a compiler defect, where a fn whose only pair route is a `?` is not a pair to a caller above its definition. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 tools lane (l6712-tools, unit T5, after the D23 bite for
issues/archived/2026-10-14-cyrius-header-stack-enum-return-prints-cyr-val.md), with that lane's `build/cyrius` and `build/cycc`.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Medium — the same wrong-prototype class the D23 bite closed for `return Ok(..)` / `return pairfn(..)`: a C
caller of the printed `cyr_val q2(cyr_val x);` reads rax alone, which on the `?` path is the Err TAG, never the payload.
No memory corruption (a 16-byte register return).
**Affects:** `cyrius header` (cbt/quality.cyr, `_hdr_body_pair`), every version that has it.

## Reproduction

`qm.cyr`:

```cyrius
include "lib/result.cyr"
fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }
fn q2(x) { var v = parse(x)?; return v + 1; }
```

```sh
T=$(mktemp -d); HOME=$T CYRIUS_HOME=$T/.cyrius build/cyrius header qm.cyr | grep '^cyr'; echo "rc=$?"; rm -rf "$T"
# the compiler's own view of q2:
{ cat qm.cyr; echo 'var z = q2(5);'; echo 'syscall(60, z);'; } | build/cycc > /dev/null      # refused: bind both
{ cat qm.cyr; echo 'var t, v = q2(0 - 3);'; echo 'syscall(60, t * 10 + v);'; } | build/cycc > qm3 && chmod +x qm3 && ./qm3; echo $?
```

```
actual:   cyr_val2 parse(cyr_val x);   /* returns Result: the tag in w0, the payload in w1 */
          cyr_val q2(cyr_val x);                                  (rc 0)
          cycc: error:<source>:4:7: a `: stack` enum returns two values — bind both: `var tag, val = f();`
          ./qm3 → 13   (q2(-3) returned the pair (1, 3): Err(3) forwarded by the `?`)
expected: q2 refused by name (stderr, rc 1), as D23 refuses a word signature over a body that returns the pair —
          never `cyr_val`.
```

## Root cause

D23 (the user, 2026-10-15) decided the refusal "when the fn's body returns a stack-enum constructor or a call to a
same-file fn already classed as the pair", and the 6.7.12 bite implements exactly those two `return` shapes
(`_hdr_body_pair`: `return NAME(` / `return NAME<..>(`). The compiler has a third route to GFLG 256: a `?` applied to a
pair call marks the enclosing fn pair-returning (src/frontend/parse.cyr, the `?` desugar's `SFLG(.., | 256)` at the
statement and expression sites; src/frontend/parse_expr.cyr likewise) — its Err path returns the callee's pair. A body
with such a `?` and only plain `return`s is pair-returning, and the scanner does not look for `?`.

## Proposed fix

In `_hdr_body_pair`, also treat `NAME(..)?` / `NAME<..>(..)?` (the call's matching `)` followed by `?`) with NAME in the
pair set as a pair return of the enclosing fn, in the same fixpoint; a row in
tests/gates/toolchain/header_spellings_and_size.sh H12 (q2 refused, and cycc's "bind both" oracle agreeing). A method
call's `?` stays unseen (as a method `return` is).
