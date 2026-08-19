# Assignment does not consult the callee's declared return type, so `t = str_new(…)` warns

**Status:** ✅ **RESOLVED** — shipped in **v6.5.28**. See `CHANGELOG.md` [6.5.28].
**Placement:** unpinned — 6.x-line backlog. Direct follow-up to
[`archived/2026-08-13-f64-typed-binding-reassign-warns-as-pointer.md`](archived/2026-08-13-f64-typed-binding-reassign-warns-as-pointer.md),
fixed at v6.5.27 ("the typed-pointer warning tested the wrong SIGN").
**Discovered:** 2026-08-14, abaco 2.4.2 taking the 6.5.21 → 6.5.27 bump
**Severity:** Low — **diagnostic only, values correct** (verified against a run
binary)
**Affects:** cycc 6.5.27
**Repro:** [`repros/2026-08-14-typed-ptr-warn-ignores-declared-return.cyr`](repros/2026-08-14-typed-ptr-warn-ignores-declared-return.cyr)
— stdlib-only, no consumer code and no folded dep involved.

## Summary

The v6.5.27 sign fix is correct and did what it said: abaco's own sources went
from 5 spurious warnings to **zero**, and the workaround that filing described
has been reverted in abaco 2.4.2.

With the check now reaching real typed-pointer locals for the first time, a
second gap is visible behind it. **The assignment path does not consult the
callee's declared return type**, while the declaration path does:

```cyr
var t = str_new("abcdef", 4);   # fine — this is what types `t` as Str
t = str_new("abcdef", 2);       # WARNS: assigning non-pointer to typed pointer
```

`lib/str.cyr` declares `fn str_new(data, len): Str`. Both sides are stdlib. The
RHS is exactly the type the LHS holds.

The declaration path must already resolve `str_new` → `Str`, since that is how
`t` acquires its type in line 1. The assignment path appears to ask only whether
the RHS *expression* is pointer-shaped — and a plain call is not, whatever the
callee declares. Offered as an observation: I have not read the assignment path
the way I read `parse.cyr:1476-1482` for the previous filing.

## Scope — this is a cycc issue, not a folded-dep issue

⚠ **An earlier draft of this file led with `lib/bayan.cyr` and was wrong to.**
Seven warnings do fire there (all inside `bayan_toml_parse`, all
`cur_name = str_new(…)` / `value = str_new(…)`), and a first pass framed the
report around them. That framing pointed at the wrong repo: bayan is its own
project, folded into `lib/`, and this repo's own precedent is to fix such things
**at the source** — *"Fixed at the source (bayan 1.2.1) … folded byte-identical
into `lib/bayan.cyr`"*.

Re-checked before re-filing: the repro above includes **no bayan at all** and
still warns. So

- the defect is entirely in cycc's assignment-time type check;
- **bayan needs no change** — it is written correctly against a `: Str`-declared
  callee, and its seven hits are a symptom;
- there is nothing to file against bayan, and this file makes no ask of it.

The bayan sites are worth keeping only as an impact note: until this is fixed,
any consumer whose `[deps].stdlib` pulls in bayan sees seven warnings on an
otherwise clean build, which they cannot act on.

## Reproduction

```sh
cd <dir with a cyrius.cyml declaring [deps].stdlib>
cyrius build repros/2026-08-14-typed-ptr-warn-ignores-declared-return.cyr out && ./out
```

Observed on cycc 6.5.27, x86_64 Linux:

```
warning:<source>:9:29: assigning non-pointer to typed pointer
4
2
```

- Line 9 is `t = str_new("abcdef", 2);` — **and the line number is correct**,
  which independently confirms the `#@srcline` fix from the same release.
- `init_only` — same callee, same type, declaration instead of assignment —
  does **not** warn.
- Values 4 and 2 are correct. No miscompile.
- Warnings attributed to `lib/bayan.cyr` also appear, because `[deps].stdlib`
  prepends bayan regardless of what the file includes. Same defect, different
  vantage point.

## Worth checking alongside

- Whether `: (Str, Str)` tuple returns behave the same. v6.5.21 made declared
  return types load-bearing and .27's notes flag the f32 tier as the next
  consumer of them, so if the assignment path is short a call site, the tuple
  destructure path may be too. I did not test it.

## Not claimed

- No miscompile — values correct on x86_64 Linux; not checked on
  aarch64 / PE / cx.
- Not a behavioural regression, only a visibility one: these sites presumably
  warranted the warning all along and the inverted sign hid them.
- I have not audited the rest of the stdlib for the same shape.
