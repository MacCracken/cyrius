# A call ABOVE a fn whose `: *S` / `: **S` / `: *Box<S>` / `: **Box<S>` RETURN names a struct declared BELOW that fn reads pass 1's record, which has no pointee struct: `var t: Later = *mk();` and `take(*mk())` fault (139) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G2), fixing
issues/2026-10-16-double-pointer-generic-return-read-in-pass-one.md (which makes `fn mk(): **Box<Later>` with Later declared
below compile, so its forward callers now meet this gap too, as the `*Later`, `**Later` and 6.7.14's `*Box<Later>` ones
already did). Identical on the slot-open compiler (b2e1f4c48's build/cycc) for fc1 / fc2 / fc3 / fc5, and on the lane
tree after G2.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x. (The pointer-RETURN
twin of issues/2026-10-17-forward-call-struct-return-of-struct-declared-below-fn.md, placed 6.7.15 structs lane wave 2
unit S1, whose fix direction — register every struct before the pass-1 signature prescan — would cover these too; that
filing enumerates by-value returns only.)
**Severity:** Medium — valid source compiles clean and faults (x86_64 and aarch64 measured), no diagnostic.
**Kind:** bug.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn main(): i64 { var t: Later = *mk(); return t.x; }
fn mk(): *Later { var b: *Later = alloc(64); b.x = 2; b.y = 5; return b; }
struct Later { x; y; }
syscall(60, main());
```

```
$ build/cycc < fc1.cyr > fc1 && ./fc1; echo $?
139          (aarch64 under qemu: 139)          want 2
```

The same shape through each pointer return (the caller above `mk`, `Later` declared below `mk`):

| return | caller | got | want |
|---|---|---|---|
| `: *Later` | `var t: Later = *mk(); return t.x;` | 139 | 2 |
| `: *Later` | `return take(*mk());` with `fn take(v: Later)` declared below `struct Later` | 139 | 2 |
| `: **Later` | `var t: Later = **mk(); return t.x;` | 139 | 2 |
| `: *Box<Later>` | `var t: Box<Later> = *mk(); return t.n;` | 139 | 2 |
| `: **Box<Later>` | `var t: Box<Later> = **mk(); return t.n;` | 139 (refused "unknown type 'Later'" before G2) | 2 |
| `: *Later` | `return mk().x;` | "cannot take a field of the result of 'mk': it does not return a struct" | 2 |

Controls: the same caller placed BELOW `mk` (`fn main(): i64 { var t: Later = *mk(); return t.x + mk().x * 10; }`) exits
22; a typed local first (`var p: *Later = mk(); return p.x;`, `var q: **Box<Later> = mk(); var t: Box<Later> = **q;`)
reads through the local's own annotation and is right above `mk` too (`var p: *Later = mk(); return take(*p);` exits 2).

## Root cause

The pass-1 signature prescan (`_prescan_ret_type` -> `_ret_ptr_annot` -> `_ret_ptr_record`, src/frontend/parse_types.cyr)
records a `: *T` / `: **T` return's pointee struct (`_fn_rpsid`) and a `**T`'s pin (`_ek_pin`) when it meets the fn;
a struct declared below the fn is not registered yet, so the record has no struct (`*Later`: `FINDSTRUCT` fails;
`*Box<Later>` / `**Box<Later>`: pass 1 skips the read while the list does not resolve, `_ret_ptr_unres`). Pass 2
re-records it at the definition, but a caller parsed in pass 2 BEFORE the definition reads pass 1's record: `*mk()` /
`**mk()` is then a plain word, and the struct copy / by-value argument reads that word as the struct's address.

## Fix direction

The by-value twin's: register every struct before the pass-1 signature prescan reads a return type (or re-record the
pointer returns once pass 1 has seen every struct), so a caller above the fn sees the definition's record. Rows: the
table above on x86_64 / aarch64 / cx / PE; the callers below `mk` and through a typed local (unchanged).
