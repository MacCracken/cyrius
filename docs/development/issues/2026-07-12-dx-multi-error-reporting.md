# DX diagnostics: multi-error reporting — RESIDUAL ONLY (the recovery core shipped)

**Status:** 🟡 **OPEN — residual only, and much smaller than this file used to claim.** The
recovery core shipped **v6.4.62** and the EOF-cascade half shipped **v6.4.78**. What remains is
**7 inline `SYS_EXIT` error sites in the parser** (re-counted live at the v6.4.82 closeout — this
file said 25, which was the count of *all* `error:` writes in `src/frontend/`, 18 of them in the
lexer, which are pre-parse and stay fatal by design) plus the `_sync_skip` coalescing refinement.
**Placement:** unpinned follow-up, P3. `roadmap.md`'s v6.4.x slot 4 records the arc as **COMPLETE**
with this as the explicit non-blocking follow-up; it rides an adjacent DX/parser release rather than
owning a slot. 6.x line — never 7.x.

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
sh tests/cycc_parser_fuzz.sh` = 0 crashes, 0 hangs); hand-crafted garbage tests missed the hangs
twice. Any future conversion of an inline site is safe by construction because the watchdog cannot
be reintroduced-around.

**v6.4.61** — the prerequisite EOF hardening of the unguarded `while (PEEKT != <term>)` skip loops.
**v6.4.78** — the `PEEKT` EOF clamp: past `GTCNT`, `PEEKT` clamps to EOF, taking a truncated-input
cascade from **166 670 reported lines to 5**. The clamp costs −0.07 % because `PEEKT` already had an
`_had_error` guard and the runaway is post-error only.

## What actually remains

### R1 — 7 inline `SYS_EXIT` error sites in the parser (the whole residual)

These print their own diagnostic and exit rather than routing through the four recovering emitters,
so a semantic error still fails fast while a syntax error multi-reports. Verified live at v6.4.82
(`grep -n 'syscall(SYS_WRITE, 2, "error:", 6)'` restricted to `src/frontend/parse*.cyr`):

| site | message |
|---|---|
| `parse.cyr:732` | `#assert failed` |
| `parse.cyr:1278` | `undefined variable` |
| `parse_types.cyr:742` | `variable '…' shadows an enum constant` (`CHK_ENUM_SHADOW`) |
| `parse_decl.cyr:324` | `undefined variable` |
| `parse_decl.cyr:462` | `undefined variable` |
| `parse_expr.cyr:577` | `undefined variable` |
| `parse_expr.cyr:685` | `undefined variable` |

Five of the seven are the same `undefined variable` diagnostic, which is the common case a user
hits — so converting them is most of the perceived inconsistency for a small, uniform change: print,
set `_had_error` + `_panic`, return, and let the `PARSE_STMT` chokepoint resync.

**The lexer's stay fatal, deliberately — and they are the other 18.** The `grep` this file used to
cite (`syscall(SYS_WRITE, 2, "error:", 6)` over `src/frontend/`) returns 25: **7 in `parse*.cyr`**,
the table above, and **18 in `lex.cyr`**. `lex_pp.cyr` adds 12 more in the single-string form
(`"error: include/#ref filename exceeds 4095 bytes\n"` and friends). All of those run *before*
parsing, so there is no token cursor to resync and no statement boundary to recover to. **They are
not part of this issue** — counting them as residual is what inflated 7 to 25.

### R2 — dense consecutive errors coalesce

`_sync_skip` skips to the next `;`, so statements between two errors that carry no `;` get swallowed
(three dense errors → one report). Bounded recovery is honest behaviour, but stopping at
statement-start keywords as well would report more of them. Refinement, not a defect.

## Not this issue — full arbitrary recovery

Expression-interior recovery needs error-return threading through the **328** live `ERR_EXPECT` call
sites in `src/` (the file previously said 346) plus every parse-chain caller — parse fns return `i64`
but callers ignore it — or exceptions, and that door is closed
(`project_no_try_catch_door_closed`). It is cybs-hostile: it adds call/return references to already
large parse fns that cybs mis-compiles **silently**, which the seed-derive gate exists to catch.
Parked in `roadmap-future`; possibly revisit atop the v6.5.x IR substrate. Codegen/runtime → 6.x
line, never 7.x.

## Acceptance for the residual

A file whose errors are all semantic (e.g. several distinct undefined variables in separate
statements) reports **N** `error:<source>:LINE:COL:` diagnostics with excerpts and exits 1, matching
what the syntax class already does. Valid input stays byte-identical (self-host fixpoint +
seed-derive). `CYCC_FUZZ_ITERS=300 sh tests/cycc_parser_fuzz.sh` stays green. Negative corpus green
on ecb / ach / cass / pi — and note that check.sh's grep summary masks segfaults, so use a per-file
exit-code loop.

**Test caveat (pre-existing):** DCE-dead fn bodies are not syntax-checked — a fn with no reachable
caller compiles despite body errors — so every fn in a negative-corpus test must be reachable.
