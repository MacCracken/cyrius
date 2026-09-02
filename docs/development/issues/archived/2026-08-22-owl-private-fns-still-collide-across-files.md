# `private` fns still collide across files — a private helper is silently replaced by any same-named fn, and the override bypasses the arity check

**Status:** ✅ **FIXED at v6.5.38 — CLOSED.** `private` now scopes at symbol INSERTION, which is the fix this filing proposed. When a definition is private and a same-named definition exists in a DIFFERENT file, the two SPLIT into separate symbols instead of the second overwriting the first; resolution then prefers the caller's own private definition, then the first non-private one, then falls through so `_vis_check` still produces the precise "is private to its file" error rather than "undefined function". §1, §2 and §3 all behave as the guide documents. The filed repro now exits **10**, not 0. Gate: `tests/gates/frontend/private_scoped_at_insertion.sh` (7 axes, MULTI-FILE — a concatenated probe gets one file id and exercises nothing, which is why the v6.5.37 gate could not have caught this; mutation-proven four ways). §3's arity half shipped earlier at v6.5.37.
⚠ Unchanged on purpose, and the gate pins both: duplicates between two NON-private definitions still only warn (`_sk_emit_err` collides between `lib/vani.cyr` and `lib/mabda.cyr` at the same arity today), and a same-FILE redefinition is still a duplicate rather than a split.
**Placement:** unpinned — 6.x-line backlog, but see §Why this is worse than a normal collision.
**Discovered:** 2026-08-22 during owl 1.4.7, auditing a `duplicate fn '_stream_grow'` warning
raised by co-linking `vyakarana` and `sankoch`.
**Severity:** High
**Affects:** cycc 6.5.0 (where `private` landed) through 6.5.37. **Fixed in 6.5.38.**

## Summary

`docs/guides/cyrius-guide.md` §Visibility promises file-level encapsulation:

> `public`/`private` control **visibility, not linkage**: private fns are also omitted from the
> exported symbol table, so they no longer appear in `.dynstr` / `nm` output or in
> `cyrius api-surface`. That is the point — the API surface a consumer sees becomes the API
> surface you declared.

Half of that holds. Referencing a private fn from another file **is** a hard error. But a private
fn still participates in global `duplicate fn … last definition wins` resolution, so:

1. Another file defining the same name **silently replaces** it — including for the private
   file's **own internal calls**.
2. Declaring `private` in **both** files does not help.
3. The replacement **bypasses the arity check**. Calling a 1-arg fn with 3 args is normally a
   hard error; routed through a duplicate, it compiles and runs.

So `private` currently protects a file's internals from being *called* elsewhere, but not from
being *replaced* elsewhere — which is the direction that silently changes behaviour.

## Reproduction

Minimal, no downstream repo needed. `cyrius.cyml` with
`stdlib = ["syscalls", "alloc", "io", "str", "fmt"]`, entry `main.cyr`.

### 1. A private helper is replaced, and the private file's own call is rebound

```
# a.cyr
private
fn _helper(s, needed) { return 1; }
public fn a_entry(s) { return _helper(s, 4096); }
```
```
# b.cyr  — unrelated file, no privacy, same helper name
fn _helper(ctx) { return 0; }
fn b_entry(ctx) { return _helper(ctx); }
```
```
# main.cyr
include "a.cyr"
include "b.cyr"
fn main() { syscall(60, a_entry(0) * 10 + b_entry(0)); return 0; }
```

```
$ cyrius build main.cyr out
warning:b.cyr:1:1: duplicate fn '_helper' (last definition wins; first defined in a.cyr)
OK
$ ./out; echo $?
0
```

**Expected** `10` — `a_entry` calls the `_helper` that `a.cyr` declared private to itself
(returns 1), `b_entry` calls its own (returns 0).
**Actual** `0` — `a_entry` was rebound to `b.cyr`'s function.

### 2. Declaring `private` in both files does not help

Add `private` + `public` to `b.cyr` as well. Same warning, same `0`.

### 3. The override bypasses the arity check

```
# a.cyr
private
fn _helper(a, b, c) { return 100 + a + b + c; }
public fn a_entry() { return _helper(1, 2, 3); }
```
```
# b.cyr
private
fn _helper(x) { return 200 + x; }
public fn b_entry() { return _helper(7); }
```

```
$ ./out4; echo $?
201            # b's 1-arg _helper won: 200 + 1. Args 2 and 3 dropped silently.
```

Contrast — the identical mismatch with **no** duplicate present is a hard error:

```
# c.cyr
fn only_one(x) { return x; }
fn c_entry() { return only_one(1, 2, 3); }
```
```
$ cyrius build main.cyr out5
error:c.cyr:2: 'only_one' expects 1 argument, got 3
FAIL
```

So the duplicate path routes *around* a check cycc otherwise enforces. That check has been a hard
error since 6.5.1; this is the one way to defeat it.

## Root cause (speculation — flag as such)

Visibility appears to be applied as a *reference-site* check (does this name resolve to something
private to another file?) layered on top of an unchanged single global symbol table, rather than
as a scoping rule during symbol insertion. If a `private` fn were inserted into a per-file scope —
or mangled with a file-unique prefix at insertion — both the collision and the arity bypass would
disappear, and the guide's "omitted from the exported symbol table" claim would become literally
true.

## Why this is worse than a normal collision

The `duplicate fn` warning is easy to read as benign shadowing, and usually is. It is not benign
when the two definitions disagree about **arity, struct layout, or return-value polarity** — and
nothing in the warning tells you which case you are in.

The instance that surfaced this: `vyakarana` and `sankoch` each define a private-by-convention
`_stream_grow`, and they disagree about all three:

| | vyakarana | sankoch |
|---|---|---|
| signature | `_stream_grow(s, needed)` | `_stream_grow(ctx)` |
| buffer / len / cap offsets | `+0` / `+8` / `+16` | `+24` / `+40` / `+32` |
| success return | non-zero (`0` means failure) | `0` means success |

Neither library is doing anything wrong: each wrote an underscore-prefixed private helper in its
own repo. They only collide because a consumer (owl) links both. Note the return polarity in
particular — a wrong binding here would not fault, it would quietly report every successful buffer
grow as a failure, inside a tokenizer, on file content.

owl verified the current binding is inert for its call graph (call sites in `lib/vyakarana.cyr`
bind to vyakarana's own definition; sankoch's caller is dead in owl's DCE map), so this is not an
outage report. It is a report that the language's own encapsulation feature does not prevent the
class.

## Proposed fix — ✅ TAKEN

Scope private symbols at insertion, not just at reference. Either a per-file symbol table for
private items, or file-unique mangling of private names before insertion. Both make §1–§3 above
behave as the guide already documents.

Failing that, a much cheaper mitigation with most of the value: **make `duplicate fn` with a
differing arity a hard error rather than a warning.** Same-arity duplicates are usually intentional
shadowing; differing arity never is, and it is exactly the case that currently defeats the arity
check. That alone would have caught `_stream_grow` at the first co-link.

## Consumer-side workaround (if any)

⚠ Historical — **none is needed from 6.5.38 on**; pin forward instead. What follows is what
consumers on 6.5.0–6.5.37 had to do.

None that works today. The obvious one — "declare the file `private`" — **does not help**, per
§1 and §2. The only actual workaround is renaming one of the two helpers upstream, which is what
`patra` did for the `TK_*` enum collision owl reported at its 1.4.0 (`TK_*` → `SQLT_*`); see
[`2026-06-14-stdlib-constant-value-collisions.md`](2026-06-14-stdlib-constant-value-collisions.md),
which is the constant-valued sibling of this bug.

Worth knowing when weighing priority: **0 of 292** first-party source files across `vyakarana`,
`sankoch`, `sigil`, `patra`, `sakshi`, `sit` and `owl` currently declare `private`. Adoption is
zero, and until this is fixed adopting it would not buy collision safety anyway — so the fix and
the adoption push want to land together.

**The fix has now landed (6.5.38), so the adoption half is what remains.** Nothing in this repo
forces it: `private` is opt-in per file and inert until declared, so those 292 files behave
exactly as before. The pitch to consumers is now truthful in a way it was not before — declaring
a file `private` genuinely prevents another library from replacing its helpers.
