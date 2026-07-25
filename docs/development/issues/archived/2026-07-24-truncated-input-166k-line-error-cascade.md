# Truncated / unclosed input produces a 166,670-line error cascade — RESOLVED

> **✅ RESOLVED in v6.4.78** (`src/backend/common/tokens.cyr`; CHANGELOG [6.4.78]).
>
> Root cause confirmed exactly as filed. `PEEKT` now clamps to `12` (EOF) once
> `GTI(S) >= GTCNT(S)`. Measured: trailing-intrinsic-at-EOF **166,670 → 5** lines, unclosed `fn`
> 166,669 → 3, EOF mid-expression 166,670 → 5, EOF mid-arg-list 166,670 → 5.
>
> **The reason this was filed rather than bundled turned out not to apply to the fix that landed.**
> The concern was that `PEEKT` is the parser's hottest fn. But it ALREADY has an
> `if (_had_error == 1)` guard for the v6.4.62 watchdog, and the runaway is exclusively
> **post-error**: LEX unconditionally appends an EOF token (`lex.cyr:1730`) and every parse loop stops
> on type 12, so a well-formed parse never advances past it. Putting the clamp INSIDE that existing
> guard costs nothing on a clean compile — **−0.07 %** on interleaved same-box medians (672.8 vs
> 673.3 ms), size-neutral, 251/251 tcyr byte-identical. Clamping `TOKTYP` unconditionally (the other
> option this doc raised) would work but taxes every lookahead for no benefit, so it was not taken.
>
> **The watchdog is KEPT** (this doc asked for a recommendation): it bounds any future desync the
> clamp does not anticipate, and it is what broke the VR-02 fuzz wall that stopped two prior attempts
> at multi-error recovery. Zero clean-path cost, so defence in depth is free.
>
> **Gate:** `tests/dx_multi_error.sh` extended with 4 truncated shapes (`<=200` lines, no hang, no
> SIGSEGV, no output, and **the watchdog firing is itself a failure** now). Mutation-proven. Plus 60
> deterministic random truncations of `lib/str.cyr`: worst case 166,680 → 18 lines, 0 hangs.
>
> The `TOKVAL`/`PEEKV` audit this doc suggested: they remain unchecked, but are only read after a
> `PEEKT` that has already established the token exists, so no path reaches them past the end. Left
> alone deliberately rather than clamped speculatively.

**Discovered:** 2026-07-24, while fixing the reserved-intrinsic diagnostic
(`2026-07-17-iv-simd-intrinsic-shadows-var-name`). **Not** caused by that fix — reproduces identically
on 6.4.76 and on the patched build (166,670 lines both).
**Severity:** **Medium** — no wrong code ships (the compile fails, correctly), and the v6.4.62 watchdog
guarantees termination, so this is *not* a hang. But the output is unusable and it buries the real
error under six figures of spam.
**Affects:** cycc **≤ 6.4.77**.

## Reproduction

The trigger is **input that ends mid-construct** — a truncated file, an unclosed `fn`, a heredoc that
lost its tail, or anything a fuzzer/pipe produces. Two minimal cases (note: NO trailing newline, NO
closing `;`/`}`):

```sh
printf 'include "lib/syscalls.cyr"\nvar x = f64_sqrt' | build/cycc >/dev/null
#   -> 166,670 stderr lines, exit 1

printf 'include "lib/syscalls.cyr"\nfn f() { var a = iv_add;\n' | build/cycc >/dev/null
#   -> 166,669 stderr lines, exit 1
```

The tail of the output is the v6.4.62 watchdog firing:

```
error:0:1: unexpected unknown
error: parser recovery aborted (desync — too many errors)
```

Well-formed input with the same reserved names is fine (5 lines) — this is specifically about EOF
arriving inside an unfinished construct.

## Root cause (from an adversarial audit; verify at pickup)

`src/backend/common/tokens.cyr`:

```cyrius
fn TOKTYP(S, i): i64 { return L64(S + 0x2D7C000 + i * 8); }   # :11 — unchecked
fn PEEKT(S): i64 { return TOKTYP(S, GTI(S)); }                # :13 — unchecked
```

Neither bounds-checks `i` against `GTCNT(S)`. Past the end they read **zeroed heap**, which yields
token type `0` — never `12` (EOF). So every `t == 12` EOF test in `_sync_skip` (`src/common/util.cyr`)
and in the block loops **silently fails**, and panic-mode recovery can never terminate normally:
`ERR` prints → `_panic = 1` → `_sync_skip` no-ops at the phantom non-EOF → clears `_panic` → repeat.
The `PARSE_STMT` forced-progress guard (`src/frontend/parse.cyr` ~:675) is also disarmed, because it
only advances when `GTI(S) < GTCNT(S)` — exactly the condition that is false here.

The spin is bounded **only** by the v6.4.62 `PEEKT` watchdog (500,000 stalled reads), which is why
this presents as spam-then-abort rather than a hang. That watchdog is doing exactly its job; this
issue is about the 166K lines it takes to get there.

A contributing factor on the way in: intrinsic dispatch sites report and keep consuming without an
early return, e.g. `src/frontend/parse_expr.cyr` ~:2249
`if (PEEKT(S) != 10) { ERR_EXPECT(S, 10); } STI(S, GTI(S) + 1); PCMPE(S); ...` — the audit counted
**52 unguarded `ERR_EXPECT(S, 10)` sites in that file**. Those are what walk `GTI` past the end in the
first place.

## Proposed fix

A one-line clamp in `PEEKT` (return `12` = EOF once `GTI(S) >= GTCNT(S)`) reportedly collapses the
cascade from 166,670 lines to **4**, with self-host fixpoint held, seed-derive passing, and 251/251
tcyr byte-identical.

**Why this was NOT bundled into v6.4.77** (which fixed the reserved-intrinsic diagnostic in the same
session): it is not a prerequisite — the diagnostic fix is complete and verified without it — and
`PEEKT` is *the* hottest function in the parser, called on essentially every parse step. Adding a
compare + branch there is a hot-path change that deserves its own slot with its own bench delta
recorded, not a ride-along on a diagnostics patch. Do the fix, then measure `self_compile` on a quiet
box before/after.

Consider also fixing `TOKTYP` itself rather than only `PEEKT`, and auditing whether the other token
accessors (`TOKVAL`, `PEEKV`, the `tok_lines` reader) share the unchecked-read shape.

## Secondary finding

The watchdog's own message prints `error:0:1: unexpected unknown` — token type `0` has no `TOKNAME`
entry. Once the bounds clamp lands this becomes unreachable, so it is not worth a separate `TOKNAME`
entry; noted only so the next reader does not chase it as a third bug. (v6.4.77 eliminated "unknown"
for all 67 *real* reserved tokens; this residual `unknown` is the past-the-end sentinel, a different
thing.)

## Related

- `2026-07-12-dx-multi-error-reporting.md` — the DX arc that shipped panic-mode recovery + the
  watchdog at v6.4.62. Its open follow-up already names "dense consecutive errors COALESCE
  (`_sync_skip` skips to the next `;`)"; this issue is the EOF-side failure of the same machinery and
  should probably be picked up with it.
- CLAUDE.md's VR-02 fuzz gate is the natural acceptance bar: hostile/truncated stdin must not only
  avoid hanging (already true) but also avoid six-figure output.
