# A refused enum member ("expected identifier") swallows every later pass-1 declaration error: `struct Q { a: Foo; }` and the next enum's are not reported — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64), the
same on the lane's compiler before F5 (11dfa7bff). Met while implementing 6.7.16's D12 (the enum member separator,
whose new error releases its own latch at the enum's `}` — `_enum_sep_end` — so a second enum's missing separator is
its own error; the loop's older "expected identifier" does not).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — every such input is still refused (rc 1); the later errors appear one compile at a time.
**Kind:** bug (diagnostics). Same class as issues/2026-10-18-later-bound-contract-refusals-swallowed-in-pass-one.md
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
