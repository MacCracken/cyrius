# Issue: `str_split` ignores its separator — always returns 1 part

**Discovered:** 2026-05-03 (cyrius v5.8.43 absorber slot, while
adding `str_split_a` Allocator-as-first-arg variant — the
deferred-from-v5.8.35 peripheral cleanup pass)
**Component:** `cyrius` stdlib — `lib/str.cyr` `str_split` /
`str_split_a` / `str_split_cstr`
**Severity:** Medium (silent miscompile of a stdlib API; affects
every consumer that expects splitting to actually split)
**Toolchain:** `cyrius 5.7.x` and earlier (predates v5.7.0
sandhi fold; bug has been live for the entire v5.x cycle)

## Summary

`str_split(s, sep)` has the API signature `(s: Str, sep: Str)` —
caller passes a Str/cstr separator. The implementation walks
`s` byte-by-byte and compares each byte against `sep` directly:

```cyrius
fn str_split(s: Str, sep: Str) {
    var parts = vec_new();
    var slen = str_len(s);
    var sd = str_data(s);
    var start = 0;
    var si = 0;
    while (si < slen) {
        if (load8(sd + si) == sep) {     # ← BUG: byte == pointer
            vec_push(parts, str_new(sd + start, si - start));
            start = si + 1;
        }
        si = si + 1;
    }
    if (start <= slen) {
        vec_push(parts, str_new(sd + start, slen - start));
    }
    return parts;
}
```

`load8(...)` returns a byte (0-255). `sep` is a Str pointer (e.g.,
0x101a40 — far above 255). The comparison `load8(...) == sep`
is never true. The split loop never fires. Every call returns a
single-element vec containing the whole input.

## Reproduction

```cyrius
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"

alloc_init();
var parts = str_split(str_from("a,b,c,d"), str_from(","));
fmt_int(vec_len(parts));   # → 1, expected 4
```

## Affected callers

- `lib/process.cyr:214` — `str_split(str_from(cmdline), " ")`
  expects to split a command line on spaces. Always returns the
  whole cmdline as one "argument".
- `lib/str.cyr:521` — `str_split_cstr` does
  `var sep_byte = load8(sep_cstr); return str_split(s, sep_byte);`.
  This wrapper PRE-EXTRACTS the byte and passes it as sep,
  expecting str_split to compare bytes — but str_split has the
  same `load8 == sep` bug, and now sep is a small int (the byte
  value 32 for space). `load8(sd + si) == 32` IS valid for
  splitting on space — so str_split_cstr happens to WORK by
  accident, because str_split's compare-byte-to-pointer bug
  becomes compare-byte-to-byte when sep is itself a byte.

So the practical state:
- `str_split(s, str_from(","))` — broken (always 1 part)
- `str_split_cstr(s, ",")` — works (because sep_byte is a byte)
- `str_split(s, 32)` — works (passing raw byte int)
- `str_split(s, " ")` from process.cyr — broken

The bug is hidden because the working callers happen to dodge it
and the broken callers (process.cyr) silently degrade to "no
split" without crashing.

## Suggested fix

Two options:

1. **Treat sep as a Str/cstr** (matches the `: Str` annotation):
   load `load8(sep)` once at fn entry to get the byte, then
   compare against that. Update str_split_cstr to drop its
   manual `load8`. Affected callers (none currently) that pass
   a raw byte int would break — search for `str_split(s, <int>)`
   calls before fixing.

2. **Change the API** to take a byte explicitly: `fn str_split(s: Str, sep_byte) { ... }`. Update callers
   to pass a byte directly (`str_split(s, 44)` for comma OR
   `str_split(s, load8(","))` for the cstr form). More work but
   the API matches the impl.

Option (1) preferred — matches the existing annotation, fixes
process.cyr without caller changes, str_split_cstr becomes a
trivial alias.

## Scope confirmed

- `str_split(s, str_from(","))` → 1 part ✗
- `str_split(s, ",")` (cstr literal) → 1 part ✗
- `str_split(s, 44)` (raw byte) → 4 parts ✓ (accidentally works)
- `str_split_cstr(s, ",")` → 4 parts ✓ (accidentally works)

## Workaround for v5.8.43 absorber slot

The `str_split_a` variant added in v5.8.43 PRESERVES the existing
broken behavior end-to-end (matches the back-compat semantics
exactly). New code wanting a working split should call
`str_split_cstr(s, sep_cstr)` instead — that path accidentally
works.

## Slot

**Pinned for v5.8.x bug-fix theme** alongside the other
2026-05-03-filed issues (`kernel` reserved-word at v5.8.45,
arithmetic-in-fn-args at v5.8.46). Likely lands as a small
patch in the v5.8.x headroom OR as the first patch of a future
minor since the absorber slots are full. Not blocking — the
str_split_cstr workaround is real and the broken-caller surface
is small (process.cyr command-line parsing, niche).
