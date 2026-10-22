# The declaration zone's last latched error swallows the program's first statement's error — `var p = g(1 2); syscall(60 0);` reports 2:13 only — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-22, `dad22cf95` (with SS-20 `95b5497c6` and SS-21 `f44cf8af5`, two PE syscall warnings met) — no decision needed. The fix direction as filed: EMIT_GVAR_INITS ends with the panic latch as it found it (`p_in`), so only an entry's latch is released for PARSE_PROG and pass 2's silent re-read keeps `const X;` to one error. The filed repro reports 2:13, 3:12 and 4:12 (3:12 was missing) on x86_64, aarch64, cx and PE; `const X;` and `enum E { A 5 }` behind a zone entry stay one error; a destructure last still lets the first statement report. In a `kernel;` build the three errors print out of order — the separate, still-open zone-replay-error-printed-after-later-pass-one-refusal issue. Rows: `dx_multi_error.sh` Z9 (the repro, exactly 2:13 3:12 4:12), Z10 – Z12 (four legs), Z13 (kernel); `const_checked.sh` M1 and `enum_member_separator.sh` S8 unchanged. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at ffca00c1e, unit Z3, x86_64; the shared
front end, every target alike); pre-existing (7965f3685's compiler the same). Met beside
issues/archived/2026-10-18-zone-replay-reports-only-first-latched-error.md, whose fix (7a4f9ecdf) releases the panic latch at
each replayed zone entry; this is the latch the replay ENDS with.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ1) — never 7.x.
**Severity:** Low — the build is refused (rc 1); the first statement's mistake is reported only after the zone's is
fixed.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
fn g(): i64 { return 1; }
var p = g(1 2);
syscall(60 0);
syscall(60 1);
```

```
error:<source>:2:13: expected ')', got number 2
error:<source>:4:12: expected ')', got number 1
```

`3:12: expected ')', got number 0` is missing: the zone replay (EMIT_GVAR_INITS, src/frontend/parse_decl.cyr) runs
before PARSE_PROG and its last entry's latch holds into the first statement, which is swallowed and resynced (the
second statement reports). A destructure as the last entry releases its own zone-check latch (`edz`), so `var a, b =
h();` (h returning one value) last lets the first statement report.

## Why the obvious fix is wrong

Clearing `_panic` when the replay ends (tried as 5d2c35caf, reverted in ffca00c1e) also clears a latch the replay did not
set: a declaration pass 2 re-reads re-latches it silently (`_err_once`'s duplicate path), and PARSE_PROG then meets that
declaration again with the latch set, which is what keeps it from re-reporting the same mistake. With the clear:

```cyrius
const X;
syscall(60, 1);
```

```
error:<source>:1:8: expected '=', got ';'
error:<source>:1:8: unexpected ';'
```

(an invented second error; tests/gates/frontend/const_checked.sh M1), and `enum E { A 5 }` + `syscall(60, E.A);` adds
"2:16: no struct type in scope for 'E'" (tests/gates/frontend/enum_member_separator.sh S8). Through the replay the
latch can come from three places — its entries, pass 2's re-reads, and the end-of-replay walks (`_warn_mixed_pair_returns`)
— and only the entries' should be released for the first statement.

## Fix direction

Release, at the replay's end, only a latch an entry set: remember `_panic` as the replay found it (and as the walks after
the loop leave it) and clear only when the last entry latched it; rows: the repro (3 errors), `const X;` and the enum
rows stay one error, on x86_64 / aarch64 / cx / PE.
