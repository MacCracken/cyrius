# `#derive(...)` and `public` cannot be combined

**Status:** 🟡 **OPEN** — reproduced on 6.6.2 with a two-line repro and a control.
**Placement:** unpinned — blocks a consumer's adoption of `private`/`public`, no workaround found.
**Discovered:** 2026-09-11, adopting file visibility across hisab's 35 modules.
**Severity:** Medium — a hard compile error, not wrong code, but it makes the visibility
feature unusable for any file that derives accessors, which in practice is every foundation type.

## Symptom

`#derive(accessors)` immediately above a `public struct` is rejected:

```
error: #derive(...) applies to a struct or an enum; the following declaration is neither
```

The `public` keyword appears to consume the declaration before `#derive` resolves it, so the
attribute no longer sees a struct.

## ⚠ Related, and possibly the same root cause

`2026-09-11-inline-directive-disarms-derive.md` reports the **identical diagnostic** from a
different trigger: an `#inline` earlier in the compile unit disarms every following `#derive`,
and that filing already notes the message "names the `struct`, which is innocent".

These are filed separately because the trigger here is isolated by a **control that differs by
exactly one keyword** in the same file with the same includes: `#derive` + `struct` compiles,
`#derive` + `public struct` does not. If the fix for the `#inline` filing is to make `#derive`
bind to the next *declaration* rather than the next *line*, it may well fix this too — in which
case close both against one change. If not, they are two entries into the same weak spot.

## Repro

```cyrius
# a.cyr  -> ERROR
#derive(accessors)
public struct P { x; y; }
```

```cyrius
# b.cyr  -> OK (control)
#derive(accessors)
struct P2 { x; y; }
```

```
cyrius build a.cyr ./a     # error: #derive(...) applies to a struct or an enum
cyrius build b.cyr ./b     # OK (257152 bytes)
```

⚠ **Neither file contains `private`.** This is not a visibility interaction — it is purely the
parse of `public` in front of a derived declaration. The control differs by exactly one keyword.

## Why it matters

`private` is only useful if the file can still export its API. For a file whose type is used by
other modules, the API *is* the derived accessors:

```cyrius
private
#derive(accessors)
public struct HVec3 { x; y; z; }   # <- rejected
```

Without `public` on the struct, `HVec3_x` / `HVec3_set_x` are file-private, and every other
module that touches an `HVec3` fails. Measured in hisab: privatising the modules produced
**1,436 errors of the form `'HVec3_x' is private to its file`**, from 18 files that derive
accessors. Marking the structs `public` reduced that to a single error — this one.

## What was tried

| form | result |
|---|---|
| `#derive(accessors)` then `public struct P` | **error** (this filing) |
| `public #derive(accessors)` then `struct P` | error — `public` is not an attribute prefix |
| `public struct P` then `#derive(accessors)` | the attribute no longer precedes a declaration |
| `#derive(accessors)` then `struct P` | OK, but the accessors stay file-private |

No ordering exposes a derived accessor from a `private` file.

## Suggested resolutions (either would unblock)

1. Accept `public` on a derived declaration — i.e. let `#derive` see through the keyword.
2. Give `#derive` a way to set the visibility of what it generates, e.g.
   `#derive(accessors, public)`, so the struct itself can stay private while its accessors are
   exported.

## Consumer status

hisab's 3.0.0 "public/private function surface" item is **blocked** on this and recorded as such
on its roadmap, with the visibility change reverted rather than half-applied. The measurements
that item rests on are unaffected and still stand: 939 functions, 296 underscore-prefixed, 148
functions and 25 globals crossing a module boundary, of which 31 are underscore-named.
