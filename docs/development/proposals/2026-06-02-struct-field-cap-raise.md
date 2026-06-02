# Raise the struct field cap (currently 32)

**Filed:** 2026-06-02 during avatara 2.5.0 (Architecture Modernization — porting `ArchetypeProfile` from a manual offset blob to a native `struct` + `#derive(accessors)`).
**Severity:** Language limitation — blocks modeling any record with more than 32 fields as a native struct. Forces either a manual `alloc` + `store64(p + OFFSET, …)` layout (error-prone — see avatara's 2.4.5 `PROF_SPIRIT` offset-collision bug, the exact failure a named struct prevents) or an artificial split into nested sub-structs.
**Affects:** `lex_pp.cyr` (the diagnostic points at `S+0x194600`). Applies to both plain structs and `#derive(accessors)`.

## Symptom

Two caps, both 32, hit by a 39-field struct:

```
# plain struct
error: too many struct fields (max 32)

# with #derive(accessors)
error: #derive struct field cap exceeded (max 32 — raise in lex_pp.cyr / S+0x194600 …)
```

## Concrete case

avatara's `ArchetypeProfile` is a single 312-byte record with **39 fields**:
3 string pointers (name, tradition, desc) + 15 f64 personality traits + 14 f64
module-emphasis values + 5 enum classifications + 2 string pointers (soul,
spirit text). It is genuinely one flat record — every field is a peer attribute
of one archetype; there is no natural sub-grouping that isn't arbitrary.

Today avatara hand-rolls the layout: an offset `enum` (`PROF_WARMTH = 24`, …)
plus `store64(p + PROF_X, v)` / `load64(p + PROF_X)` at ~10k call sites, plus
~39 hand-written accessor functions. The 2.5.0 goal is to replace that with:

```cyrius
#derive(accessors)
struct Profile { name; tradition; desc; warmth; humor; /* … 39 total … */ spirit_text; }
```

so the compiler owns the offsets and `Profile_set_warmth(p, v)` / `Profile_warmth(p)`
replace the manual arithmetic. The 32-field cap blocks this.

## Why this is more than cosmetic

The manual-offset workaround is exactly what produced avatara's 2.4.5 bug: an
offset constant (`PROF_SPIRIT`) was accidentally defined twice (176 and 304),
"last definition wins" silently sent every archetype's spirit-emphasis write to
the wrong slot, and it shipped undetected because nothing names the field. A
native struct makes that class of bug a compile error (duplicate field name).
Wide records — profiles, config blocks, register/descriptor layouts, protocol
headers — are precisely where manual offsets are most error-prone and a named
struct helps most, yet the 32-cap excludes them.

## Ask

Raise the cap to a comfortably higher bound (64 or 128) for both the plain
struct path and the `#derive(accessors)` path. If there's a codegen reason for
32 (e.g. a fixed-size field table), bumping the table size or making it dynamic
would suffice — the diagnostic itself notes the knob is in `lex_pp.cyr`.

## Workaround until landed

avatara keeps its manual offset-enum + `store64`/`load64` layout (it works and,
post-2.4.5, is correct). The struct migration is parked on this cap — same
pattern as the 2026-06-02 `f64_le`/`f64_ge` proposal: avatara flips to the
native struct once the cap is raised. Marked here so future-claude doing the
cap bump knows the first real consumer is waiting.
