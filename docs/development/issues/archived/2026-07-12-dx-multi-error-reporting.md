# DX diagnostics: multi-error reporting — RESIDUAL ONLY (the recovery core shipped)

**Status:** ✅ **CLOSED at v6.5.39.** R1 and R2 both substantially shipped at **v6.5.23** — the slot this filing itself pinned — and nobody closed the file; the excerpt gap was the only real residual and it shipped here, along with a latent silent miscompile found in the same function. Gate: `tests/gates/diagnostics/resolution_excerpt_and_assert_skip.sh` (4 axes, mutation-proven both ways).

⚠ **THREE OF THIS FILING'S CLAIMS WERE AFFIRMATIVELY WRONG, not merely stale.** Recorded so a later sweep does not re-inflate them:
1. **"The residual GREW 7 → 8 — v6.5.19's `_ends_guard` added a site."** False on live code: that site recovers (`_had_error = 1; return 1;`). CHANGELOG v6.5.23 records the conversion as an explicit maintainer decision.
2. **"THE DEPENDENCY IS BACKWARDS — R2 MUST LAND BEFORE R1."** Directly contradicted by the CHANGELOG of the release that shipped both: *"R2 was NOT the enabler, contrary to the re-triage… what works is report-and-continue **without** panic-mode."* The five sites bypass `ERR_IDENT` precisely to dodge the manufactured-`unexpected else` regression.
3. **`CHK_ENUM_SHADOW` is not an open residual** — it is fail-fast by design, per its own source comment.

The live residual count was **1**, not 7 or 8. ⚠ **All seven line numbers in the filing's table had drifted again** (second re-stamp for drift): a hand-maintained table of line numbers is the wrong artifact, which is why the fix is pinned by a gate instead.

⛔ **A NEW LATENT SILENT MISCOMPILE was found in the code the last residual sits in, and fixed here.** The `#assert` skip-loop's comment promised *"consume remaining tokens until `;` or newline change"* and the loop tested only `;` and EOF — there was no newline check at all. A `#assert` with no trailing `;` skipped across the following `fn` header and ate the first statement **and its `;`**. Measured: the gate fixture exits **0** pre-fix where **7** is correct — wrong code, no diagnostic, no crash. Latent rather than live only because nothing in the tree uses `#assert` today (all 12 grep hits are compiler implementation or comments). Duplicated at three sites in three files; all three fixed.
live on cycc 6.5.10, 2026-08-07: still exactly 7, but every line number below had drifted.** The
recovery core shipped **v6.4.62** and the EOF-cascade half shipped **v6.4.78**. What remains is
**7 inline `SYS_EXIT` error sites in the parser** (the file once said 25, which was the count of
*all* `error:` writes in `src/frontend/`, most of them in the lexer, which are pre-parse and stay
fatal by design) plus the `_sync_skip` coalescing refinement.
**Placement:** **v6.5.23 — band B**, the parser diagnostic residual. Owns most of that release.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⛔ TWO CORRECTIONS. (1) **THE DEPENDENCY IS BACKWARDS AS WRITTEN — R2 MUST LAND BEFORE R1.** `src/common/util.cyr:1152-1165` records that converting the fail-fast sites without the `_sync_skip` statement-start-keyword arm regresses the v6.5.19 lint P1 and MANUFACTURES `unexpected else` on well-formed `lib/fs.cyr`. (2) **The residual GREW 7 → 8** — v6.5.19's `_ends_guard` added a site. Owed at slot open: does a CAPACITY limit belong in the same class as `undefined variable`, or is it fail-fast by design? Answer it or a ninth appears next sweep.

**Filed:** 2026-07-12 (at v6.4.60, when DX Release 1 — column + source-excerpt — shipped).
**Severity:** P3 — DX consistency; not a correctness bug, and no consumer is blocked.
**Component:** `src/frontend/parse.cyr`, `parse_types.cyr`, `parse_decl.cyr`, `parse_expr.cyr`.

## What shipped (do not re-scope these as open)

**v6.4.62 — the panic-mode recovery core.** `_had_error` / `_panic` / `_sync_skip` live in
`src/common/util.cyr` (shared, so every fork's output gate and exit sees them); the four central
emitters (`ERR` / `ERR_EXPECT` / `ERR_MSG` / `ERRDUPVAR`) print-and-return instead of exiting; a
`PARSE_STMT` wrapper is the single recovery chokepoint; output is gated inside the 2 `EMITELF` fns
plus the cx write path, so no fork emits a binary after an error; all six forks exit `_had_error`.

**The key that broke the fuzz wall — keep this, it is the durable lesson.** Two prior attempts were
reverted because byte-mutated hostile input drove cycc into an infinite loop, and per-loop progress
guards kept missing one. The mechanism that works is a `_had_error`-gated watchdog *inside* `PEEKT`
(`_wd_tick`, `util.cyr`): if `GTI` stalls for >500 000 reads — far above any legal recursive-descent
depth, so it never false-fires on valid code — cycc aborts cleanly. That universally bounds **any**
desync spin rather than enumerating loops. It is inert until the first error, so valid input stays
byte-identical. **The VR-02 fuzz gate is the acceptance bar** (`CYCC_FUZZ_ITERS=300
sh tests/gates/diagnostics/cycc_parser_fuzz.sh` = 0 crashes, 0 hangs); hand-crafted garbage tests missed the hangs
twice. Any future conversion of an inline site is safe by construction because the watchdog cannot
be reintroduced-around.

**v6.4.61** — the prerequisite EOF hardening of the unguarded `while (PEEKT != <term>)` skip loops.
**v6.4.78** — the `PEEKT` EOF clamp: past `GTCNT`, `PEEKT` clamps to EOF, taking a truncated-input
cascade from **166 670 reported lines to 5**. The clamp costs −0.07 % because `PEEKT` already had an
`_had_error` guard and the runaway is post-error only.

## What actually remains

### R1 — 7 inline `SYS_EXIT` error sites in the parser (the whole residual)

These print their own diagnostic and exit rather than routing through the four recovering emitters,
so a semantic error still fails fast while a syntax error multi-reports. **Re-derived live on
6.5.10, 2026-08-07** — the command, so the next sweep can re-run it rather than trust the table:

```sh
grep -n 'syscall(SYS_WRITE, 2, "error:", 6)' src/frontend/parse*.cyr   # → 11 hits
# then read each: 7 end in syscall(SYS_EXIT, 1) — those are the residual;
#                 4 end in `_had_error = 1;` + return — those already recover.
```

| site | message | *(as filed / v6.4.82)* |
|---|---|---|
| `parse.cyr:809` | `#assert failed` | was `:732` |
| `parse.cyr:1355` | `undefined variable` | was `:1278` |
| `parse_types.cyr:772` | `variable '…' shadows an enum constant` (`CHK_ENUM_SHADOW`) | was `:742` |
| `parse_decl.cyr:324` | `undefined variable` | unchanged |
| `parse_decl.cyr:462` | `undefined variable` | unchanged |
| `parse_expr.cyr:587` | `undefined variable` | was `:577` |
| `parse_expr.cyr:695` | `undefined variable` | was `:685` |

Five of the seven are the same `undefined variable` diagnostic, which is the common case a user
hits — so converting them is most of the perceived inconsistency for a small, uniform change: print,
set `_had_error` + `_panic`, return, and let the `PARSE_STMT` chokepoint resync.

**Four MORE `error:` printers now live in `parse*.cyr` and are NOT residual — they already
recover.** The raw grep count in `parse*.cyr` rose 7 → 11 since this was filed, but the four
additions all set `_had_error = 1` and return instead of exiting, so the residual is unchanged at
7. They are listed so a future sweep does not re-inflate the number by counting hits instead of
reading them:

| site | message | behaviour |
|---|---|---|
| `parse_types.cyr:688` | `'…' is private to its file` (v6.5.0 `private`) | `_had_error = 1; return 1;` |
| `parse_fn.cyr:1043` | `'…' expects N argument(s), got M` (arity check) | `_had_error = 1; return 0;` |
| `parse_fn.cyr:1127` | `'…' is private to its file` | `_had_error = 1; return 1;` |
| `parse_fn.cyr:1604` | `passing integer literal … which expects a cstring` | `_had_error = 1;` |

**The lexer's stay fatal, deliberately.** The same `grep` over all of `src/frontend/` returns
**29** at 6.5.10 (was 25): 11 in `parse*.cyr` (above) and **18 in `lex.cyr`**. `lex_pp.cyr` adds
more in the single-string form (`"error: include/#ref filename exceeds 4095 bytes\n"` and friends).
All of those run *before* parsing, so there is no token cursor to resync and no statement boundary
to recover to. **They are not part of this issue** — counting them as residual is what inflated 7
to 25 the first time.

### R2 — dense consecutive errors coalesce

`_sync_skip` skips to the next `;`, so statements between two errors that carry no `;` get swallowed
(three dense errors → one report). Bounded recovery is honest behaviour, but stopping at
statement-start keywords as well would report more of them. Refinement, not a defect.

**Still open, re-read live 2026-08-07:** `_sync_skip` (`src/common/util.cyr:1188-1200`) stops on
exactly three things — `;` (tok 5, consumed), `}` (tok 14) and EOF (tok 12). There is no
statement-start-keyword arm.

## Not this issue — full arbitrary recovery

Expression-interior recovery needs error-return threading through the **329** live `ERR_EXPECT` call
sites in `src/` (`grep -rn "ERR_EXPECT(" src/ | wc -l`, run 2026-08-07 on 6.5.10; this file has said
346, then 328) plus every parse-chain caller — parse fns return `i64`
but callers ignore it — or exceptions, and that door is closed
(`project_no_try_catch_door_closed`). It is cybs-hostile: it adds call/return references to already
large parse fns that cybs mis-compiles **silently**, which the seed-derive gate exists to catch.
Parked in `roadmap-future`; possibly revisit atop the v6.5.x IR substrate. Codegen/runtime → 6.x
line, never 7.x.

## Acceptance for the residual

A file whose errors are all semantic (e.g. several distinct undefined variables in separate
statements) reports **N** `error:<source>:LINE:COL:` diagnostics with excerpts and exits 1, matching
what the syntax class already does. Valid input stays byte-identical (self-host fixpoint +
seed-derive). `CYCC_FUZZ_ITERS=300 sh tests/gates/diagnostics/cycc_parser_fuzz.sh` stays green. Negative corpus green
on ecb / ach / cass / pi — and note that check.sh's grep summary masks segfaults, so use a per-file
exit-code loop.

**Test caveat (pre-existing):** DCE-dead fn bodies are not syntax-checked — a fn with no reachable
caller compiles despite body errors — so every fn in a negative-corpus test must be reachable.
