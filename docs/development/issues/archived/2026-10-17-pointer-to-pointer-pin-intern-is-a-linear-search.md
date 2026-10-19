# The pointer-to-pointer pin intern is a linear search: compile time grows quadratically in distinct `**T` pointees — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-3, `92d388ad5` — no decision needed: compile time only. `_pp_intern` probes `_pp_hix`, an open-addressing index over (step word, field entry, struct), `alloc()`'d at twice `_pp_cap` and rebuilt by `_pp_grow`. Pins keep their first-come numbers, so every output is byte-identical. On x86_64 the filed generator at K=15 (15360 pins) compiles in 1,333 ms, where it took 4,543 ms, and K=4 → K=15 is 3.7x, where it was 10.4x. Rows: the new `tests/gates/frontend/double_pointer_pin_scale_linear.sh` (`# check: serial`). S1 runs the filed generator at K=4 and K=15 and requires a ratio under 6.0x; S2 requires the K=15 program to compile clean and exit 0. Mutation (the tree before): RED S1 at 10.4x. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V1, after `71aa9a503`, the bite that
widened the pin to 14 bits) on x86_64.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Discovered:** 2026-10-17, the 6.7.14 vectors lane, unit V1 (issues/archived/2026-10-16-double-pointer-pins-interned-per-struct-cap.md):
the new gate's cap row (K1, 16384 pins) takes ~5 s on x86_64.
**Severity:** Low — compile time only (no wrong output, no refusal); reachable only by a unit with thousands of distinct
`**T` pointees (the struct table holds 1024 structs, so it takes deep `***..T` nesting or many `**Self` fields).
**Kind:** bug (scaling).

## Reproduction

1024 structs, each taken through `**S` .. `**..*S` (K + 1 stars), so the unit holds 1024 × K distinct pins:

```sh
for K in 2 4 8 15; do
  awk -v K=$K 'BEGIN{for(i=0;i<1024;i++){printf "struct S%d { a; b; }\n",i; st="*"; for(d=2;d<=K+1;d++){st=st "*";
       printf "fn f%d_%d(pp: %sS%d): i64 { return 0; }\n",i,d,st,i}}
       print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}' > sc$K.cyr
  /usr/bin/time -f "K=$K %e s" ./build/cycc < sc$K.cyr > sc$K
done
```

```
K=2 0.21 s     (2048 pins)
K=4 0.45 s     (4096 pins)
K=8 1.23 s     (8192 pins)
K=15 4.43 s    (15360 pins)
control (the same number of plain `fn fN(): i64` and no `**T`): 2048 fns 0.04 s, 4096 0.06 s, 8192 0.12 s
```

## Root cause

src/frontend/parse_types.cyr `_pp_intern(S, v, ent, sid)` finds an existing pin by scanning every pin interned so far
(`while (i <= _pp_n)` comparing the step word, the field entry and the struct), and every `**T` annotation interns one
pin per pointer level on every pass that reads it. Through 6.7.13 the table held 126 pins, so the scan was bounded; 6.7.14
raised the cap to 16383 (bit 62 plus a 14-bit pin) and the scan is now up to 16383 entries per intern.

## What a fix needs

A hashed index over (step word, field entry, struct) beside `_pp_tab` / `_pp_sids` (alloc()'d, grown with them, no heap
region), and a scaling row in tests/gates/frontend/double_pointer_pin_capacity.sh (or a `# check: serial` gate beside
globals_scale_linear.sh / string_intern_scale_linear.sh) that measures the ratio between two pin counts.
