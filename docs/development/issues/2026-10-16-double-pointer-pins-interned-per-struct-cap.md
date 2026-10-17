# Pointer-to-pointer pins are interned per pointee struct, so 127 distinct `**S` structs hit "max 126" where one pin served them — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (after `d9aa49ec`, the deref-through bite) on
x86_64: the repro below is refused; the lane base (`f59668ad`, `build/cycc` 2,270,008 B) compiles it (exit 0). 126
structs compile on the lane.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, the review of the 6.7.13 vectors lane
(issues/archived/2026-10-15-vector-deref-through-address-of-or-double-pointer-into-vector-pointer-param.md).
**Severity:** Low — a loud compile error in a large unit with many distinct `**Struct` types, never a miscompile; a
capacity regression against the base (same-size structs used to share a pin).
**Kind:** bug (table capacity).

## Reproduction

Generated: 127 two-word structs, each with a fn taking `**S`:

```sh
awk 'BEGIN{for(i=0;i<127;i++){printf "struct S%d { a; b; }\nfn f%d(pp: **S%d): i64 { return 0; }\n",i,i,i}
     print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}' > d.cyr
cat d.cyr | ./build/cycc > d
```

```
the lane:  error:<source>:254:14: too many pointer-to-pointer pointee types (max 126)   (rc 1)
the base:  compiles, rc 0
the lane, 126 structs: compiles, rc 0
```

## Root cause

src/frontend/parse_types.cyr `_pp_intern(S, v, ent, sid)`: d9aa49ec made a pin carry its pointee `*S`'s struct
(`_pp_sids`, so `take(**pps)` can check the struct), and the intern key became (step word, pool entry, sid). Two
same-size structs used through `**S` share the step word `v` and used to share one pin; each now takes its own. The
table holds 126 pins (`_pp_tab` / `_pp_sids`, alloc'd for 128; pin bits 56-62 of the step word).

## What a fix needs

Either a wider pin (the step word's bits 56-62 cap the index at 127: a pin index elsewhere, or the sid kept outside the
pin — e.g. looked up from the annotation at the dereference) or a larger table with a wider field; a row in the
pointer-to-pointer gate with 127+ distinct `**S` structs compiling.
