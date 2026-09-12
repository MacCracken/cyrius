# `#inline` disarms every `#derive` that follows it in the same compile unit

**Status:** ✅ **FIXED in v6.6.3** — pass 1 now CONSUMES token 163 (`#inline`), in
`main.cyr` and all six per-target forks. Gated by
`tests/tcyr/derive/inline_before_derive.tcyr`, mutation-proven.
— five of them have no local fix because they are poisoned only through a vendored bundle.
**Discovered:** 2026-09-11, migrating naad (pin 6.5.35 → 6.6.2) during the ecosystem sweep.
**Severity:** High — **a hard error with a misleading message**, in a construct the compiler
itself generates. The diagnostic names the `struct`, which is innocent; the cause is a
`#inline` hundreds of lines earlier, in a different module of a bundled fold.

## Repro

```cyrius
#inline
fn helper(a) { return a + 1; }

#derive(accessors)
struct Thing { alpha; beta; }

fn main() { return 0; }
```

```
$ cd ~/.cyrius/versions/6.6.2/lib && cat repro.cyr | .../bin/cycc > /dev/null
error:<source>:5:1: unexpected struct        (4 errors)
```

**Delete the `#inline` line and it compiles with 0 errors.** That is the whole difference.

## It is ORDER-dependent, and it is every subsequent derive

| arrangement | result |
|---|---|
| `#derive` … then `#inline` | **0 errors** |
| `#inline` … then `#derive` | `unexpected struct` |
| `#derive`, `#inline`, `#derive` | the **second** derive fails |

So `#inline` disarms the derive machinery from its own position onward. A single `#inline`
early in a large fold silently breaks every `#derive` in every module after it.

## Why it looks like nothing is wrong until 6.6.x

`#inline` did not exist as a directive until **v6.5.63** — `#` opens a comment, so before
that release the marker was inert. naad pins **6.5.35** and carries **167 `#inline`
markers across 34 source files**, none of which have ever done anything. They activate on
the 6.6.2 bump and take all **79** of naad's `#derive` structs with them.

## Mechanism (suspected, not proven)

`src/common/util.cyr:320-327` already documents this exact failure text for the *generated*
case, and explains why `#inline` is passed by side channel rather than emitted as text:

> derive bodies are FLATTENED ONTO A SINGLE LINE to keep the user's line numbering honest,
> and `#` opens a COMMENT — so the `#` comments out the rest of that line … Measured: a
> two-struct fixture gives exit 10 normally and `error: unexpected struct` with the emit
> added, because the second derive never fires.

The same fact appears to bite for a **source-level** `#inline`: once the preprocessor is in
the inline-marker path, the following `#derive` never fires and the raw `struct` keyword
reaches the parser. `_pp_inl_base` / `_pp_inl_n` / `_pp_inl_bloom` (util.cyr:331-333) and
the `#derive` table at `lex_pp.cyr:759` are the two pieces to look at. **Not a cap:** naad
has 79 derives against a documented cap of 512, and the repro has one.

## Consumer impact — REMEASURED 2026-09-11, it is a 10-repo cluster, not two repos

This section originally named naad and svara. A sweep of every `.cyr`/`.tcyr`/`.bcyr`/`.fcyr`
file under `src/ lib/ dist/ tests/ programs/ benches/ fuzz/` across all ~130 sibling repos,
counting files where a `#inline` line PRECEDES a `#derive(` line in the same unit, measures:

**60 poisoned files across 10 repos** — the whole audio/DSP cluster.

| repo | poisoned files | 6.6.2 errors (build / test) | how it is reached |
|---|---|---|---|
| naad | 16 (15 src + `dist/naad.cyr`) | 14 / — | own source; `src/main.cyr` includes its own bundle |
| svara | 3 | — | own source + vendored `lib/naad.cyr` |
| dhvani | 18 | 17 / — | own source **and** 6 vendored bundles |
| nidhi | 8 | 14 / — | own source + `lib/naad.cyr` |
| garjan | 3 | 14 / 462 | `src/modal.cyr` + `lib/naad.cyr` |
| jalwa | 3 | 13 / — | own source + `lib/dhvani.cyr` |
| ghurni | 2 | 14 / 140 | vendored only |
| prani | 3 | 7 / — | vendored only |
| shabda | 2 | 7 / 70 | vendored only |
| shabdakosh | 2 | 7 / 182 | vendored only |

⛔ **The PUBLISHED BUNDLES carry the defect.** `dist/naad.cyr`, `dist/svara.cyr`,
`dist/garjan.cyr`, `dist/ghurni.cyr`, `dist/nidhi.cyr`, `dist/prani.cyr` and
`dist/dhvani.cyr` each contain an early `#inline` followed by 16–90 `#derive` structs. Five
of the ten repos are poisoned *only* through a vendored bundle — they have no `#inline` of
their own and nothing they can fix locally. `lib/naad.cyr` alone (`#inline`@98, 79 later
derives) blocks six consumers. So this is not "naad and whoever vendors naad": **fixing the
compiler is the only unblock for half the cluster**, short of every publisher stripping
markers and re-releasing in dependency order.

- Any repo that adopted `#inline` while pinned below 6.5.63 has the same latent break.

### Isolation refined

`#must_use` does **not** trigger it — measured. Only `#inline` does:

| fixture | result |
|---|---|
| `#inline` + fn, then `#derive` + struct | `unexpected struct` |
| `#must_use` + fn, then `#derive` + struct | **compiles** |
| `#inline` + `#must_use` + fn, then `#derive` + struct | `unexpected struct` |
| fn with no directive, then `#derive` + struct | **compiles** |
| `#derive` + struct FIRST, then `#inline` + fn | **compiles** |

Bisected out of `dist/naad.cyr` by binary search on the starting line: the largest prefix cut
that still reproduces begins at **line 245**, which is the file's first `#inline`. The
`struct` the error names is at line 1165 — **920 lines away**.

Verified workaround, if a consumer needs to move before this is fixed: strip the `#inline`
markers. Measured in a sandbox — 34 files, build goes 14 errors → **0**. For a repo pinned
below 6.5.63 this is behaviour-preserving, because the markers were never active there. It
does forfeit the inlining once the defect is fixed, which is the reason to fix it rather
than let consumers strip.

## Acceptance

- The repro above compiles with 0 errors.
- A `#derive` following any number of `#inline` markers still fires.
- naad builds at 6.6.2 with its 167 `#inline` markers intact.

---

## Root cause (v6.6.3) — a two-pass directive taught only one pass

`#inline` became a real directive at **v6.5.63**, which added token 163 to PASS 2:
`src/frontend/parse.cyr:2287` arms `_inline_pending` and advances. PASS 1 — the
declaration-collection scan that runs first — was never taught to consume it.

An unconsumed token there does not warn. It falls through to the catchall `else`, which
**terminates the pass-1 scan**, so every declaration after the first `#inline` is
unregistered by the time pass 2 runs. The `struct` then arrives at the parser as an
unknown top-level token and `ERR()` reports `unexpected struct` — naming the innocent
construct, 920 lines from the trigger in naad's case.

That also explains every observed property: strictly positional (a `#derive` *before* the
first `#inline` is registered before the scan dies), and `#must_use` does not trigger it
(token 122 has been in the consume list since v5.8.20).

⭐ **It is a recurrence, and the evidence was already in the file.** The comment directly
above the pass-1 consume list documents the original: v5.8.20 added
`#must_use`/`#pure`/`#io`/`#alloc` to pass 2 only, which "caused the pass-1 scanner to
fall into the catchall else and terminate, leaving subsequent enum / fn defs unregistered
for pass 2", dropping check.sh to 48/64. Same file, same mechanism, same shape.

**The durable rule: a new directive token needs BOTH halves — pass 1 consumes, pass 2
arms.** Adding only the arming half is silent until someone writes the two constructs in
the wrong order; adding only the consuming half is silent until someone measures whether
the directive still does anything. Both failure modes shipped: v6.5.63 shipped the first,
and the initial cut of THIS fix shipped the second for about ten minutes before
`tests/gates/codegen/inline_directive.sh` reddened. That gate exists because v6.5.63
found `#inline` had been a no-op — it earned its keep twice.

### Fix — BOTH halves, and they are not the same edit

⛔ **The first attempt at this fix broke `#inline` outright, and the `inline_directive`
gate caught it** (`calls 100→100` where it had been `100→92`). Adding token 163 to every
site that listed 127/133 looked uniform and is not: most forks have TWO such sites and
they do different jobs.

- **pass 1 — CONSUME.** Without it the declaration scan terminates. This is the half that
  every fork needs.
- **pass 2 — ARM the right flag.** `main.cyr` carries its own directive dispatch (it
  handles 125/126/127/133), and there 163 must set `_inline_pending`. Adding it to the
  condition alone dropped it into the trailing `else`, which sets `_alloc_pending` — so
  `#inline` armed the WRONG flag and silently stopped inlining.

⚠ **The six other forks need ONLY the consume half.** They arm just `_naked_pending` and
delegate the rest to `parse.cyr`'s dispatcher, which has handled 163 since v6.5.63. That
asymmetry is precisely why a blanket edit was wrong, and why "apply to all forks" has to
mean "apply the right half to each fork" rather than "paste the same line everywhere".

The consume half (`… || PEEKT(S) == 163`) at every pass-1 site:
`main.cyr`, `main_aarch64.cyr`, `main_aarch64_macho.cyr`, `main_aarch64_native.cyr`,
`main_cx.cyr`, `main_win.cyr`, `main_x86_macho.cyr`. ⚠ Most forks have **two** pass-1
dispatch regions and `main_win.cyr` needed both — a fix to `main.cyr` alone would have
left six targets broken, which is the failure shape CLAUDE.md's "parse_expr calls in ALL
forks" note exists to prevent.

### Verification

- 7-line reproducer: `unexpected struct` → compiles, rc=0.
- `dist/naad.cyr` (167 `#inline`, 79 `#derive`): **2** `unexpected struct` with the old
  compiler, **0** with the fix. (Its remaining errors are missing-stdlib — a bundle omits
  the stdlib by design — and are identical either way.)
- Self-host fixpoint byte-identical; **seed-derive OK** from the 29,024-byte seed.
- Mutation: reverting the one-line change reddens the new test with 2 `unexpected struct`.

### Consumers unblocked

naad, svara, dhvani, nidhi, garjan, jalwa, ghurni, prani, shabda, shabdakosh — 60 files.
Five were poisoned only through a vendored bundle and had no local fix; they need only a
re-vendor once the publishers rebuild on 6.6.3. **No marker-stripping is required** — the
workaround recorded above is now unnecessary, and `#inline` keeps doing its job.
