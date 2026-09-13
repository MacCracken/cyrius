# A file-private fn is reachable from another file via `&name` and runs through `callptr` / `fncallN` — OPEN

**Status:** 🟡 **OPEN** — filed by hisab while building its public-surface gate for 3.1.0. Repro
`repros/2026-09-13-hisab-private-fn-reachable-via-address-of.cyr` **proves itself** (exit 42 while the
bug is present; the build is refused when fixed).
**Placement:** unpinned — reproduced on **6.6.2 and 6.6.3**; older than both (the visibility check
has not changed shape since 6.5.38).
**Discovered:** 2026-09-13, designing a consumer-reachability gate that took `&name` of every public
fn — the negative control (`&_private`) was supposed to be refused and was not.
**Severity:** High — **the boundary the guide promises is bypassable in one token.** The guide says
referencing a private item from another file is "a hard error, not a warning" and that private fns
are omitted from the exported symbol table. Both are true for a direct call; neither holds for
address-of, and the pointer obtained is fully callable.

## Summary

```cyrius
# lib_priv.cyr
private
fn _helper(v) { return v * 2; }
public fn api(v) { return _helper(v); }
```

```cyrius
# main.cyr
include "lib_priv.cyr"
fn main() { return _helper(21); }                       # REFUSED: '_helper' is private to its file
fn main() { var f = &_helper; return callptr(f, 21); }  # builds; exit 42
fn main() { return fncall1(&_helper, 21); }             # builds; exit 42
```

Measured on 6.6.3 and 6.6.2, same source, same lib: the direct call is refused at compile time; both
address-of forms build (`OK (93184 bytes)`) and return **42**. A private **var** read from another
file IS refused (`'_g_hidden' is private to its file`), so the check runs on identifier reads and on
call sites — and not on the `&ident` path.

## Why it matters

- Any consumer can reach any "private" helper by writing `&` — so `private` documents intent but
  does not enforce it, which is the pre-6.5.0 state the feature was added to end.
- The 6.5.38 guarantee that a private fn cannot be captured by another file's same-named fn is
  presumably intact, but a *pointer* to it can be handed anywhere.
- It silently invalidates the natural way to write a **reachability gate**: "take `&name` of every
  public fn from a consumer file" compiles for private fns too, so it proves nothing in either
  direction. hisab's gate therefore emits **calls** (arity read from the declaration, zero
  arguments, compile-only) for both the positive and the negative half.

## Proposed fix

Run the same visibility check at the address-of site that runs at a call site — the identifier is
resolved either way, and the fn's `private` flag is already known there. Gate: the repro file (build
must be refused; `no binary` is the pass) plus the direct-call control (must stay refused) and a
`&public_fn` control (must stay accepted). Mutation: skipping the check at the `&` path reddens the
first; applying it unconditionally reddens the third.

## Consumer stopgap (what hisab does)

`scripts/check-public-surface.sh` never uses `&name` as evidence; it generates direct calls and
counts `is private to its file` diagnostics in both directions (every public item reachable, every
non-public item refused). Documented in the script header with a pointer to this filing.
