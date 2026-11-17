# A string builder's grow never frees the outgrown buffer, whatever its allocator — open

**Status:** 🟡 **OPEN**, verified on cyrius 6.7.18 (x86_64), 2026-11-13.
**Discovered:** 2026-11-13, by pravash 2.0.1's hardening review (its JSON writers, `pravash/src/json.cyr`).
**Severity:** Low–medium. Nothing is corrupted. A program that writes large texts into fresh builders grows the heap
by about twice each text's size.

## Summary

`_sb_grow_a(a, sb, n)` (lib/str.cyr) allocates the doubled buffer through `a`, copies, and drops the old buffer
without freeing it, even when `a` is a freeing allocator. A builder also doesn't record its allocator, so a writer
handed someone else's builder can't know which allocator its buffer came from, and so can't free it.

## pravash's numbers

One `VofField.to_json` of a 256 × 256 field (262 KB of text) into a new builder took 1.05 MB: every doubling's
buffer, from 64 bytes up. Ten such writes took 10.7 MB. A builder that is cleared and reused stops growing once it
holds the largest text, and pravash documents that meanwhile.

## Asked for

1. **`_sb_grow_a` frees the old buffer through `a`** (or the inline one stays as it is).
2. **A builder records its allocator** (`str_builder_new_a`'s), so a grow uses it without the caller passing it again.

## Also needed: pramana, non-aborting forms for the writers that have none (2026-11-15, cyrius 6.7.18)

Five builder writers end the process when a grow fails: `str_builder_putc`, `str_builder_add`, `str_builder_add_cstr`,
`str_builder_add_int` and `str_builder_add_json_str` (`lib/str.cyr`: each calls `_sb_die`, exit 1, after "str_builder:
alloc failed"). `add`, `add_cstr` and `add_int` have `_a` forms that return −1 instead. `putc` and `add_json_str` have
none, so a library can't escape a JSON string with the stdlib, or call a printer written on `putc`, without risking
its consumer's process. impetus's shortest f64 printer (`src/fmtf.cyr`, which pramana and pravash vendor for
serde_json's text) writes through `putc`, `add_cstr` and `add_int`.

**Asked for:** `str_builder_putc_a(a, sb, ch)` and `str_builder_add_json_str_a(a, sb, s)`, returning −1 on a failed
grow as the other `_a` forms do.

**Meanwhile** pramana's JSON writers (`src/json.cyr`, M1 part d4) reserve the room first with `_sb_grow_a`, which
returns −1:
- 32 bytes before each f64 (serde_json's longest f64 text is 24 bytes, measured over 25,200 doubles);
- the exact escaped length before each string.

Then `fmtf.cyr`'s printer and `str_builder_add_json_str` never grow the builder, so they never reach `_sb_die`. A
reservation that can't be had is `PMN_ERR_OUT_OF_MEMORY`; pramana's tests ask for 2^62 bytes and get it back as a
code. The reservations are marked `UPSTREAM(L14)` and go when the two `_a` forms ship.
