# Ecosystem migration note — 6.6.13: `f64_le`, `f64_ge`, `f64_trunc` become builtins

> **Created 2026-10-01** for cyrius 6.6.13, bite I5
> (`issues/2026-09-30-f64-le-ge-trunc-are-calls.md`). Every figure below was derived from
> `~/Repos` on that date. Re-derive before acting on any of them: this file is the census that
> `docs/retired-symbols.allow` points at, and a figure nobody re-derived is how v6.6.0 shipped a
> deletion against a live consumer.

## What changed

`f64_le(a, b)`, `f64_ge(a, b)` and `f64_trunc(x)` were `lib/math.cyr` fns. `f64_le` / `f64_ge`
called two builtins (`f64_lt(a, b) == 1`, then `f64_eq`), and `f64_trunc` branched to `f64_ceil`
or `f64_floor`. Each cost a call frame: 2-3× the builtins they wrap. In 6.6.13 they are compiler
builtins, like `f64_lt` and `f64_floor`:

- `f64_le` / `f64_ge` lower through the `<=` / `>=` compare (x86 `setbe` with the parity fold /
  `setae`, aarch64 `cset ls` / `cset ge`, cx `fle` / `fge`). Both are 0 when either side is NaN,
  exactly as before.
- `f64_trunc` lowers to x86 `roundsd imm 3`, aarch64 `frintz`, and the new cx opcode `0x6E ftrunc`
  (a cxvm older than 6.6.13 faults on it by name, rather than running it as a no-op).
- `f64_trunc`'s result carries the float-builtin result mark, as `f64_floor`'s does, so
  `f64_trunc(x) * 2.0` and `-f64_trunc(x)` are float operations.
- No include is needed for any of the three any more.

Results are bit-for-bit the retired bodies' over a 24-value special set (both NaN signs, sNaN,
both zeros, both infinities, halves, 2^52 and its neighbours, both min subnormals, max finite,
1 - ulp): `tests/tcyr/crossos/f64_le_ge_trunc_builtins.tcyr`.

## What breaks, and when

**The three names are now RESERVED.** Nothing may declare them as a fn, var, field or parameter.
The only definitions anywhere under `~/Repos` are the vendored copies of `lib/math.cyr`:

- **72 repos** carry a `lib/math.cyr` that defines them: cyrius itself (retired in this release)
  and **71 siblings** (49 git-tracked copies, 23 gitignored ones). Every copy is a historical
  cyrius `lib/math.cyr`, byte for byte.
- No `src/`, `tests/`, `programs/` or `dist/` file in any repo defines them, and no repo takes
  their address, declares a var or field with those names, or uses one as a bare identifier.
- The 71 siblings pin cyrius **6.6.2 … 6.6.12** (34 on 6.6.2, 10 on 6.6.3, 12 on 6.6.6, 2 on 6.6.9,
  4 on 6.6.10, 3 on 6.6.11, 6 on 6.6.12). The `cyrius` CLI re-execs the PINNED toolchain
  (`cbt/cyrius.cyr`, `_try_redirect_to_pinned`), so **nothing breaks under the current pins.**

**At the pin bump to ≥ 6.6.13**, a repo must re-vendor `lib/math.cyr` in the same commit
(`cyrius deps` does it). A repo that bumps without re-vendoring gets a loud, located error, never a
silent change:

```
error:lib/math.cyr:771:4: expected identifier, got reserved keyword 'f64_le' ...
```

(the line number depends on the vendored vintage: 771, 458, 437 or 267), plus the existing
stale-lib warning (`cbt/commands.cyr`, `_check_lib_freshness`).

## Call sites: no change

**1,040 repo-owned calls in 26 repos** (prakash 264, goonj 191, naad 124, dhvani 78, hisab 68,
mneme 59, prani 41, ranga 33, svara 28, prajna 22, sankhya 20, cyrius 18, nidhi 16, garjan 12,
ganita 12, avatara 11, ghurni 10, abaco 10, agnosai 9, thoth 5, shabdakosh 3, attn11 2, and 1 each
in szal, shabda, jalwa, anukulana), plus the calls inside vendored `lib/` and `dist/` bundles. All
are `name(...)` calls with unchanged arity and results; they keep compiling and get faster.

abaco 2.4.9 (whose benchmarking found the issue) inlined the builtin forms in its hot paths as a
workaround (`src/dsp.cyr`). It may return to `f64_trunc` / `f64_ge` after its pin bump.

## Worklist for the sweep

For each repo, at its next cyrius pin bump to ≥ 6.6.13:

1. Bump the `cyrius` pin in `cyrius.cyml`.
2. `cyrius deps` — re-vendors `lib/math.cyr` without the three fns. (Never hand-copy the file, and
   never stage anything into `~/.cyrius/deps`.)
3. If the repo ships a `dist/` bundle that embeds `lib/math.cyr`, regenerate it the way that repo's
   release process does.
4. Build and run the repo's full CI. A `reserved keyword 'f64_le'` (or `'f64_ge'` / `'f64_trunc'`)
   error means step 2 did not run.
