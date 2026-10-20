# A struct global of 8 B or less declared from a pointer global declared BELOW it compiles and faults at startup (`var A: P8 = *GP8;`, `= GP8;`, `= *GPP8;`) — over 8 B the same line is refused by name — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at 6b6b1b149, unit Z4, x86_64; the
shared front end, every target alike). Pre-existing for `*GP8` / `(*GP8)` / `*GPP8` (b73e8d5fe's compiler: exit 139);
6.7.16's D17 (a) / D18 (a) (a top-level `var G: S = *GPP;` and `var G: S = P;` are copies at every size, commits
cb004c8c8 / 62ba267ac) put the name `GP8` in the same class — through 6.7.15 it held the pointer word GP8 had at that
moment (0) and exited 0, silently wrong (A.v 0 where 6 is right). Met while landing
issues/2026-10-18-top-level-declaration-from-double-pointer-single-deref-binds-handle.md; not that filing's surface (its
repro declares every source above the global), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ3) — never 7.x.
**Severity:** Low — a source declared below the global it initialises is an ordering mistake the compiler already refuses
over 8 B; at 8 B or less the program faults at startup (SIGSEGV), before its first statement, instead of being told.
**Kind:** bug (a missing refusal).

## Reproduction

```cyrius
struct P8 { v; }
var A: P8 = *GP8;          # or: = GP8;  = *GPP8;  = (*GP8);
var GS8 = P8 { 6 };
var GP8: *P8 = &GS8;
var GPP8: **P8 = &GP8;
syscall(60, A.v);
```

```
                     b73e8d5fe (lane base)   6b6b1b149 (this lane)
var A: P8 = *GP8;    exit 139                exit 139
var A: P8 = (*GP8);  exit 139                exit 139
var A: P8 = *GPP8;   exit 139                exit 139
var A: P8 = GP8;     exit 0 (A.v = 0)        exit 139
```

Over 8 B each is refused by name (tests/gates/codegen/small_struct_handle_line.sh GC3, GC9, GC10):

```cyrius
struct H { v; w; }
var G: H = *P;
var A = H { 4, 0 };
var P: *H = &A;
syscall(60, G.v);
```
```
error:<source>:2:13: cannot copy-init 'G' from a global declared below it (declare the source first): 'P'
```

## Root cause

Over 8 B pass 1 (PARSE_GVAR_REG, `_gci_inline`) decides the global's layout when it registers it, with only the globals
above it registered: a `*T` source it cannot see leaves G a handle, and the replay refuses that disagreement by name
(`_gci_below` / `_gz_dx_init` / `_gz_pn_init`, src/frontend/parse_decl.cyr). At 8 B or less the layout is judged at the
end of pass 1 (`_gz_sweep` -> `_gz_sval`), when every global is registered, so the below-declared source is seen, G stays
inline and the replay (EMIT_GVAR_INITS, in declaration order) copies through a pointer global whose own initialiser has
not run yet: its slot is 0 and the copy reads address 0. Nothing asks whether the source's replay entry comes after G's.

## Fix direction

Refuse it at 8 B or less as over 8 B: in the replay, a dereference or `*T` name source whose global's initialiser is a
later replay entry than G's (it is not yet stored) gets the same "declared below it" refusal. A source whose value is in
the image from program start (a baked constant) is no ordering problem and could stay accepted.
