# A refused enum member ("expected identifier") swallows every later pass-1 declaration error: `struct Q { a: Foo; }` and the next enum's are not reported — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-12, `3adc7ae7b`, with FF-11 `c27ab795f`, FF-13 `6b80792df`, FF-14 `befee5bc0`, FF-18 `d9102c0a0`, FF-19 `746548d92`, FF-20 `54f7790b4` and the review fix FF-12r `a31410709` — no decision needed (diagnostics). Pass 1's enum arm (`_tl_decl1` / `_tl_decl_end`, src/frontend/parse_fn_def.cyr) releases a refusal's latch at the enum's own `}` when the declaration ended in sync; D12's separator release is the same step. The filed repro reports all three errors, "1:12: expected identifier, got number 5", "2:15: unknown type 'Foo' for struct field 'a'" (2:18 before FF-35's column fix) and "3:12: expected identifier, got number 6"; `{ A, , B }`, a payload's parameter, the enum's name, `: stack` and `{` likewise. The same step covers a struct's and a union's refusal (FF-13), pass 2 and the enum-init walk (FF-14), a fn / impl signature over an empty body (FF-20) and a trait header (FF-12r); a refused member registers nothing (FF-11); the two check.sh reds it exposed (the struct cap repeated per struct; a stray `)` at top level read as "unmatched '}'") are FF-18 and FF-19. Rows: tests/gates/frontend/enum_member_separator.sh P1 (the filed repro verbatim) – P9, G1 – G3, PS1 – PS6, PSC1, Q1 – Q8, PT1 – PT7; dx_multi_error.sh D1 – D11; cap_errors_stop_storing.sh; each with mutants RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64), the
same on the lane's compiler before F5 (11dfa7bff). Met while implementing 6.7.16's D12 (the enum member separator,
whose new error releases its own latch at the enum's `}` — `_enum_sep_end` — so a second enum's missing separator is
its own error; the loop's older "expected identifier" does not).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF3) — never 7.x.
**Severity:** Low — every such input is still refused (rc 1); the later errors appear one compile at a time.
**Kind:** bug (diagnostics). Same class as issues/archived/2026-10-18-later-bound-contract-refusals-swallowed-in-pass-one.md
(pass 1 has no statement resync: a refusal's panic latch holds until pass 2) — a different reporter.

## Reproduction

```cyrius
enum E { A 5 }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
```

```
error:<source>:1:12: expected identifier, got number 5
```

rc 1. Nothing for `Foo` or for line 3's `6`: with line 1 valid (`enum E { A, B }`) both print —
`error:<source>:2:18: unknown type 'Foo' for struct field 'a'` and `error:<source>:3:12: expected identifier, got number 6`. `enum E { A, , B }` ("expected identifier, got ','") swallows them the same way.

## Root cause

PARSE_ENUM_DEF's member loop (src/frontend/parse_types.cyr) reports a non-name with ERR_EXPECT, which sets the panic
latch; pass 1 (`_tl_pass1`, src/frontend/parse_fn_def.cyr) clears it only after the whole top-level walk, so every later
pass-1 report is swallowed. The enum's `}` is a sync point: releasing the latch there when this enum set it (as
`_enum_sep_end` does for D12's error) would report each declaration's own error.
