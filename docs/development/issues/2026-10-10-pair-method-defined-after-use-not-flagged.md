# A `: stack` pair-returning METHOD used above its `impl` is not a pair: `p.div(d)?` SIGSEGVs, `var v = p.div(d);` binds the tag — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: the repro (the `impl` below its caller) compiles clean and dies of SIGSEGV (rc 139); moving the `impl`
above `usediv` gives the right exit, 11. With the impl below, `var q = p.div(d);` (no `?`) compiles and binds the tag
(exit 1), where the impl above refuses it "a `: stack` enum returns two values — bind both". The repro dies the same
way with the installed 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers (6.7.0 is where an inherent `impl Pt {`
starts to parse).
**Placement:** 6.7.11 — repair 1, the return-register lane (roadmap.md § *The releases after 6.7.7*) — placed
2026-10-10 — never 7.x (the fix is the user's call, asked at that release's open: `var v = p.div(3);` above such an
impl, which compiles today, starts being refused with "bind both").
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane (the integration review of bite D6's pair checks; recorded
in the lane's handoff, not filed then).
**Severity:** High — valid `?` code crashes at run time with no diagnostic, and the single bind keeps the tag in
silence (a lossy bind the same program refuses when the impl comes first).
**Affects:** cycc 6.7.0 – 6.7.8, x86_64 measured (the pair flag is shared frontend state)

## Summary

A fn that returns a `: stack` enum (`Result` / `Option` / `Either` and any user `: stack` enum) returns two registers
— the tag in rax, the payload in rdx — and the compiler marks it "pair-returning" (fn flag 256). Every consumer reads
that flag: `?` lowers as a pair (tag test, payload) only when it is set, and otherwise as the BOXED form, which
dereferences rax — the tag, 0 or 1 — as a pointer; `var v = f();` is refused ("bind both") only when it is set.

A fn defined BELOW its use gets the flag from a pre-scan (`_pair_prescan`) that walks top-level `fn` definitions
before pass 2. An `impl` method is skipped there (its registered name is mangled, and the scan runs at brace depth
0 only), so its flag is set only when pass 2 parses its body. A method called before that point — any caller above
the `impl` — is read as single-valued.

## Reproduction

`docs/development/issues/repros/2026-10-10-pair-method-defined-after-use-not-flagged.cyr`:

```cyrius
include "lib/syscalls.cyr"
include "lib/result.cyr"
struct Pt { x; y; }
fn usediv(p: Pt, d): i64 {
    var q = p.div(d)?;                   # the impl is BELOW: `?` treats the result as a box -> SIGSEGV
    return Ok(q + 1);
}
impl Pt { fn div(self, d): i64 { if (d == 0) { return Err(9); } return Ok(self.x / d); } }
fn main(): i64 {
    var p = Pt { 40, 2 };
    var t, v = usediv(p, 4);
    return t * 100 + v;                  # want 11 (Ok(11)); the impl moved above usediv gives 11
}
var rc = main();
syscall(60, rc);
```

```
actual:   compile rc 0; run: Segmentation fault, rc 139
expected: exit 11, as with the impl above `usediv`
```

The second shape: replace `p.div(d)?` with `p.div(d)` — impl below: compiles, exit 1 (q = the tag 0); impl above:
`error: a \`: stack\` enum returns two values — bind both: \`var tag, val = f();\``.

## Root cause

`_pair_prescan` (`src/frontend/parse.cyr:464`) counts brace depth and inspects a `fn` only at depth 0, so methods in
an `impl` block are never visited; `_ensure_pair_flags` runs it once, and `_callee_returns_pair_at` (`:879`) then
reads a method's flag before pass 2 has set it. `_tpair` (the `?` lowering) and `_refuse_lossy_pair` both read that
flag.

## Proposed fix

Visit `impl` methods in `_pair_prescan` (resolving each to its mangled fn-table entry — `Type_method` /
`Type_Trait_method` — through the same lookup the method call uses, never by registering a bare name: the scan must
not mint fn-table entries), and run `_pair_body_scan` over their bodies, so the flag is known before any caller is
parsed. That also makes the single bind above the impl a "bind both" refusal — the user's call. Rows: the repro;
`?` on a method of `impl Tr for Pt` above it; a generic method; a method forwarding another method's pair
(`return self.div(d);`); the single bind (refused); the impl-above order unchanged; a plain i64 method below its use
(no false flag).

## Consumer-side workaround

Put the `impl` block above every fn that calls its pair-returning methods.
