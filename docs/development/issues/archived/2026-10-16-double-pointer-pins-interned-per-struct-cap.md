# Pointer-to-pointer pins are interned per pointee struct, so 127 distinct `**S` structs hit "max 126" where one pin served them — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-1, `71aa9a503` (the guide's cap sentence followed in `65e64cb30`): a pinned step word is bit 62 plus a 14-bit pin in bits 48-61 — a `**T`'s word names no vector, so those bits were free; `_ps_vdesc` answers 0 for a pinned word. `_pp_intern`'s cap is 16383, `_pp_tab` / `_pp_sids` grow by doubling, and `_gv_ppn` keeps a global's pin in 16 bits. The intern key keeps the struct, so `take(**ppq)` of another same-size struct stays refused. The filed generator at 127 structs was refused "too many pointer-to-pointer pointee types (max 126)" at 254:14, rc 1, on x86_64, IR=3, aarch64, cx and PE; it now compiles and exits 0 on all five, and so does the generator at 1024 structs / 2048 pins. The 16384th pin is refused "(max 16383)". The fix direction's "a larger table with a wider field" was taken, and no heap / brk region moved. No decision needed (a 6.7.13 capacity regression). Rows: the new `frontend/double_pointer_pin_capacity.sh` on the five legs — C1 the filed generator verbatim; C2 1024 structs; C3 2048 pins; P1 reads past pin 1500 (42); P2 the DRS1 shape past pin 1500, refused once; K1 the 16384th pin refused; K2 the guide states the cap. The brief's 2000-struct row cannot exist: REGSTRUCT's 1024-struct cap. On cass, the PE builds of C3 / P1 run (0 / 42). Mutations M0 – M3 RED (25 / 5 / 9 / 5). Staged beside it: the pin intern is a linear search (Low). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (after `d9aa49ec`, the deref-through bite) on
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
