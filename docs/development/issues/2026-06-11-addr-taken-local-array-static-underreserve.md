# Address-taken fixed local array under-reserves static backing (off-by-one slot)

**Filed:** 2026-06-11 (cyrius-side tracking of a daimon consumer report)
**Severity:** HIGH — silent static-memory corruption (codegen)
**Component:** cycc codegen — static promotion of address-taken fixed-size local arrays
**Reported by:** daimon 1.2.6 (manifested as *every* HTTP route returning 404)
**Upstream repro (immutable):** `daimon/docs/development/issues/2026-06-11-cyrius-addr-taken-local-array-static-overlap.md`
**Roadmap:** v6.2.x (per user 2026-06-11)

## Confirmed on cycc 6.1.41

Minimal repro reproduces on the current compiler (also .39/.40 per daimon):

```cyrius
fn esc(v) {
    var parts[4];
    store64(&parts, v); store64(&parts + 8, v);
    store64(&parts + 16, v); store64(&parts + 24, v);   # 4th slot — in-bounds per the address-taken convention
    return &parts;
}
fn main(): i64 {
    var sp = " ";              # adjacent static string literal
    var before = load8(sp);    # 32 (space)
    var p = esc(1);
    return load8(sp);          # OBSERVED: 1 (corrupted) — should be 32
}
```
`build/cycc` (6.1.41) → **exit 1** (the `" "` literal byte was overwritten with `1`),
confirming the daimon analysis: the address-taken `parts[4]`, promoted to static
storage, is laid out with only `(N-1)*8` = 24 bytes; the next static object (the
literal) sits at `&parts + 24`, so the in-bounds write to slot 3 clobbers it.

## Root cause (to pin during repair)

The pass that promotes an address-taken fixed-size local array to static storage
reserves **`(N-1)*8`** bytes instead of the full **`N*8`**, so the last i64 slot
overlaps the next static datum. The exact site was not pinned during review (the
escape→static placement is subtle and not obvious by grep) — that's the first
repair step. Suspect the slot-count loops that register `nslots - 1` fillers + 1
named slot (parse_decl.cyr ~1162/1412/1504 for the `stack var` paths) have a
sibling in the static-promotion path that advances the static-data pointer by
`nslots - 1` slots, dropping the named slot's byte reservation.

**Convention note for the repair:** a *plain* local `var a[N]` is N BYTES
(rounded to 8) per [[feedback_var_array_byte_sized]], whereas a *global* is N i64
slots. But this address-taken/escaping array is promoted to STATIC and is used as
an N-i64-slot buffer (store64 per slot) — daimon + stdlib (`argv_buf[4]`) rely on
that. The fix must reserve the full slot-based size the static placement already
intends (it gives N-1 slots today, so it's slot-based, just off by one) — i.e.
reserve `N*8`, not change the local-vs-static byte/slot model.

## Fix

In the static-promotion reservation, reserve `N*8` bytes (the full N i64 slots)
before laying out the next static object. Add a regression: an address-taken
`var a[N]` whose slot `N-1` is written, with a sentinel static literal placed
immediately after, asserts the literal is intact.

## Status

OPEN — confirmed on 6.1.41; daimon shipped a workaround (inline octet compute, no
address-taken `var parts[4]`). Any other address-taken `var a[N]` whose last slot
is written remains exposed (layout-sensitive — dormant until the array lands
before a live literal). Roadmapped v6.2.x.
