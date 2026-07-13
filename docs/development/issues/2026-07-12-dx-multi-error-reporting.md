# DX diagnostics: multi-error reporting (Release 2 of the DX arc)

> **★ RECOVERY CORE SHIPPED — v6.4.62 (3rd attempt; the fuzz wall is broken).** The panic-mode
> mechanism landed: 4 emitters print-and-return + `_panic` + `_sync_skip` + a `PARSE_STMT` wrapper
> (guaranteed-progress guard) + the all-fork output gate (2 `EMITELF` fns + cx + all-fork
> `exit=_had_error` + `_had_error` shared in util.cyr). **THE KEY THAT UNBLOCKED IT: a
> `_had_error`-gated watchdog in `PEEKT`** — after the first error, if `GTI` stalls >500 000 reads
> (far above any legal descent depth → never false-fires on valid code) cycc aborts cleanly. This
> universally bounds ANY desync spin the per-loop guards miss — the piece the 2 prior attempts
> lacked. VERIFIED: valid self-compile byte-identical + seed-derive + all 6 forks; **VR-02 heavy
> fuzz `CYCC_FUZZ_ITERS=300` (1500 runs) = 0 crashes/0 hangs**; check.sh 146/0. Covers the
> `ERR_EXPECT` (346) + `ERR`/`ERR_MSG`/`ERRDUPVAR` syntax class.
>
> **STILL OPEN (the follow-up — a smaller, distinct scope):** (a) the **25 inline `SYS_EXIT`
> errors** (undefined-variable @parse_expr etc. + the lexer errors, which are pre-parse and stay
> fatal) — convert the *parser* inline ones to print-and-return + `_panic` so semantic errors
> multi-report too; (b) dense consecutive errors COALESCE (`_sync_skip` skips to the next `;`,
> swallowing no-`;` statements) — a smarter sync (stop at statement-start keywords) is the
> refinement. Neither blocks the shipped syntax-class multi-error. The watchdog makes any future
> inline conversion safe by construction (it can't reintroduce a hang).

> **PROGRESS (v6.4.61):** the EOF-hardening prerequisite is DONE — the 3 unguarded
> `while(PEEKT!=<term>)` skip-loops (`parse_types.cyr:316`, `parse_decl.cyr:585`,
> `parse_fn.cyr:2254`) now break on EOF (byte-identical; bounds the desync crash surface).
>
> **PROTOTYPE PROVEN (v6.4.62 attempt, reverted — mechanism validated, completion scoped):**
> Built + tested the recovery mechanism: `_panic` global; `_sync_skip(S)` (GTCNT-bounded skip
> to `;`/`}`/EOF, consume `;`, clear `_panic`); the 4 central emitters (ERR/ERR_EXPECT/ERR_MSG/
> ERRDUPVAR) print-if-`!_panic` → set `_had_error`+`_panic` → return; a **PARSE_STMT wrapper**
> (rename body → `_PARSE_STMT_IMPL`, wrapper `_sync_skip`s on `_panic`) as the single recovery
> chokepoint covering all 6 call sites + the recursion; x86-ELF output gated on `_had_error`.
> RESULTS: **valid input byte-identical** (self-host fixpoint held — recovery is never-taken on
> valid input); **SAFE — garbage/past-EOF input does NOT crash** (the EOF guards + bounded
> `_sync_skip` held); **2 reachable functions with missing-`;` errors → BOTH reported** (`:3:5:`
> + `:7:5:`), exit 1, no output. So the mechanism WORKS + is safe for the ERR_EXPECT (346-site)
> syntax class.
>
> **COMPLETION SCOPE (why it wasn't shipped — bigger than one clean deliverable):**
> 1. **Output gate in ALL forks, not just x86-ELF.** With the emitters returning, every fork
>    recovers, but only main.cyr gated the write → the other forks (main_win / main_aarch64{,_macho,_native}
>    / main_x86_macho / main_cx) would emit GARBAGE on error (a regression). Cleanest: gate inside
>    the 2 `EMITELF` fns (`x86/fixup.cyr:2057`, `aarch64/fixup.cyr:653` — set the output length
>    `S+0x1903F8`=0 + return on `_had_error`, covering the 5 ELF/PE/macho forks) + the cx write path
>    (`main_cx.cyr:494-518`).
> 2. **The 25 inline ad-hoc errors still `SYS_EXIT` (fail-fast)** — incl. the very common
>    `undefined variable` (parse_expr). They aren't the 4 converted emitters, so multi-error is
>    inconsistent until they route through a print-and-return + `_panic` path too. (grep:
>    `syscall(SYS_WRITE, 2, "error:", 6)` in src/frontend = 25 sites.)
> 3. **Dense consecutive broken statements COALESCE** — `_sync_skip` skips to the next `;`, so
>    intervening no-`;` statements get swallowed (test: 3 dense errors → 1 report). Acceptable
>    "bounded recovery" but worth a smarter sync (stop at statement-start keywords).
> 4. **DCE-dead fn bodies aren't syntax-checked** (pre-existing: a fn with no reachable caller
>    compiles despite body errors) — so the negative corpus must make every test fn reachable.
>
> Recommended: complete (1)+(2) as v6.4.62 in a focused session (the mechanism is proven +
> reverted-clean; re-apply from this scope). (3) is a follow-on refinement; (4) is a test caveat.
> Scheduled complete-in-one — user's call 2026-07-12 to keep it off the marathon tail.
>
> **SECOND ATTEMPT (v6.4.62, reverted again — the FUZZ WALL, the real blocker):** re-applied the
> mechanism + completed (1) the all-fork output gate — gated inside the 2 `EMITELF` fns
> (`x86/fixup.cyr` + `aarch64/fixup.cyr`: `if (_had_error==1) { S64(S+0x1903F8, 0); return 0; }`)
> + the cx write path + changed all 6 forks' final `SYS_EXIT 0` → `SYS_EXIT _had_error` + moved
> `_had_error` to util.cyr (shared, so every fork's gate/exit sees it). ALL of that WORKED: valid
> input byte-identical, seed-derive green, all 7 forks build, **2 separated syntax errors → both
> reported, 0 output bytes, exit 1**. BUT the **VR-02 parser-fuzz gate FAILED** — byte-mutated
> hostile input drove cycc into an **infinite loop (100% CPU hang / TIMEOUT)**. Added a
> guaranteed-progress guard to the PARSE_STMT wrapper (`before=GTI; …; if (GTI==before) STI+1`) —
> that fixed the LIGHT fuzz (75 runs) AND kept valid byte-identical, but the **HEAVY fuzz (300
> iters) found ANOTHER hang** (a `build/cycc` spinning at 100% CPU). So the desync goes DEEPER than
> the single PARSE_STMT chokepoint: other parse loops (the top-level PROG loop, the
> `while(PEEKT!=14)` block loops, expression/decl inner loops) also fail to guarantee progress on
> mutated input.
>
> **THE REAL COMPLETION REQUIREMENT (do this before re-attempting):** a *systematic* progress +
> no-crash invariant across EVERY parse loop that can run under desync — not one wrapper. Likely:
> audit each parse loop for a `GTI`-advance-or-break guard (the 8 EOF-guarded skip-loops are a
> start but insufficient), or reconsider whether error-return threading (rejected as cybs-hostile)
> is actually the safer path. **The VR-02 fuzz gate is the acceptance bar** — a re-attempt only
> lands when `CYCC_FUZZ_ITERS=300 sh tests/cycc_parser_fuzz.sh` is GREEN (0 crashes, 0 hangs) AND
> the self-host stays byte-identical. This is a DEDICATED arc, not a bite: THREE attempts have now
> hit the wall (scope → crash → residual hang), confirming safe bounded multi-error is bigger than
> one release. A compiler that hangs/crashes on hostile stdin is a DoS regression that must NEVER
> ship — hence the reverts. The `_had_error`-out-put-gate + all-fork-exit + EMITELF-gate design
> (parts 1) IS proven and can be re-applied verbatim; only the parse-loop progress-hardening is open.

**Filed:** 2026-07-12 (at v6.4.60, when DX Release 1 — column + source-excerpt — shipped).
**Severity:** P2 — DX quality; not a correctness bug.
**Component:** `src/frontend/parse*.cyr`, `src/common/util.cyr` (the emitters), `src/main.cyr`
(the pass-2 driver + the dead `_had_error` exit hook).

## Context

v6.4.60 shipped DX Release 1: every error now prints `error:<source>:LINE:COL:` + a source-excerpt
with a caret. Release 2 is **multi-error reporting** — report several errors per compile instead of
fail-fast on the first. Today every emitter (`ERR`/`ERR_EXPECT`/`ERR_MSG`/`ERRDUPVAR`) ends in
`syscall(SYS_EXIT, 1)`; the parser stops at the first error.

## Scope — BOUNDED statement/decl-boundary panic-mode (the viable version)

The clean-path saving grace: recovery branches are **never taken on valid input**, and cycc's own
source never errors, so the self-compile output is unchanged → the byte-identical fixpoint +
seed-derive hold *provided every edit is a never-taken branch that doesn't reorder the clean path*.
Mechanism (must land COMPLETE in one release — no slicing):

1. `ERR*`/`ERR_MSG`/`ERRDUPVAR` **print-and-return** (mirror `WARN`, the existing template) instead
   of `SYS_EXIT`; set the (already-present but dead) `_had_error = 1` (main.cyr:560 →
   `syscall(SYS_EXIT, _had_error)` @ main.cyr:2119); set a new `_panic = 1` and go **silent** while
   `_panic` (one error per statement).
2. A small standalone `_sync_skip(S)` advances to the next `;`(5) / `}`(14) / `fn`(32) / decl-keyword
   / EOF(12) with a **hard EOF guard**, called from `PARSE_STMT` (parse.cyr) and the pass-2 driver
   loop (main.cyr ~1452) when `_panic`, then clears `_panic`.
3. Gate the single output write (main.cyr ~2083) on `_had_error == 0`.

## Risk (be honest — riskier than a normal slot)

Between the error and the sync point the desynced cursor keeps parsing/emitting through expression
interior. `PEEKT`/`TOKTYP` are unchecked `L64` reads; an unbounded skip past EOF or a
`while(PEEKT!=X)` loop lacking an EOF guard → SIGSEGV; continued garbage emission grows the fixup
table (cap 32768) / fn table (8192). **8 `while(PEEKT!=...)` skip loops** need an EOF-guard hardening
audit: parse.cyr:379/446/686/730, parse_types.cyr:316, parse_decl.cyr:585, parse_expr.cyr:174,
parse_fn.cyr:2254. Ship with a negative-input corpus (missing `;`, unclosed `(`, garbage token,
garbage-past-EOF) → `tests/dx_multi_error.sh` asserting `grep -c '^error:' == N` + exit 1, run cross-OS
(desync-driven table growth is target-agnostic; check.sh's grep summary masks segfaults — use a
per-file exit-code loop).

## Deferred FURTHER (backlog, not this arc): full arbitrary recovery

Full expression-interior recovery needs error-return threading through the 346+ `ERR_EXPECT`
fall-through sites + every parse-chain caller (parse fns return i64 but callers ignore it) OR
exceptions (door closed — `project_no_try_catch_door_closed`). That is cybs-hostile (adds call/return
refs to already-large parse fns that cybs mis-compiles silently) and is NOT a 1-2 release arc. Pin to
`roadmap-future`; possibly revisit atop the v6.5.x IR substrate. Codegen/runtime → 6.x line or the
roadmap "potential backlog", NEVER parked to 7.x.

## Acceptance

`cyrius build` of a file with N independent statement-level errors prints N `error:…:L:C:` diagnostics
(each with its excerpt) and exits 1; valid input is byte-identical (self-host fixpoint + seed-derive);
malformed/garbage/past-EOF input never crashes (negative corpus green on ecb/ach/cass/pi).
