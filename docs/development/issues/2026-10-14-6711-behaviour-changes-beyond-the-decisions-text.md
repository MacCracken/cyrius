# 6.7.11 changes that stop existing programs compiling (or change a result) without a decision naming them — confirm each, or restore it — OPEN

**Status:** 🟡 **OPEN** — a confirmation for the user. Collected 2026-10-14 by the 6.7.11 release-docs pass (the lane
drafts re-measured on the merged tree, main 0601aff4, `build/cycc` 2,223,320 B, against the 6.7.10 compiler
`~/.cyrius/versions/6.7.10/bin/cycc`). The user, 2026-10-14: "file and fix them in 6.7.12". Each item below shipped in
6.7.11 and is listed in CHANGELOG [6.7.11] / ecosystem-migration § 6.7.11; each either follows an existing rule or was
decided on a premise that turned out narrower than the change.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 integration) — never 7.x. ⚠ Language semantics are the user's
call (CLAUDE.md *Execution integrity*): for each item, keep (and the item closes) or restore the 6.7.10 behaviour.
**Severity:** Medium — programs that compiled on 6.7.10 stop compiling; none of the new refusals miscomputes.

## 1. D10's flip side: a program's own `struct slice` takes a fn-local `slice<u8>` (GF-8, 69024633 / 2044d729)

D10 (user, 2026-10-13) was recorded as "a declared `struct slice` wins in locals; nothing is newly refused". The lane's
review found the flip side: with a `struct slice` declared, a fn-local `slice<u8>` used as the built-in slice stops
compiling.

```cyrius
include "lib/syscalls.cyr"
struct slice { a; }
fn f(): i64 { var s: slice<u8> = "abc"; return s.len; }
syscall(60, f());
```

```
6.7.10: compiles, exits 105
6.7.11: error:<source>:3:53: unknown field 'len' on struct 'slice'
```

Respelling the built-in `[u8]` compiles on both. Confirm D10 with this flip side, or keep the built-in for a `slice<T>`
spelling (a generic argument the user struct does not take).

## 2. A top-level struct-by-value call into a `*S` global is refused (ST-8, f79e310b; follows D2)

```cyrius
include "lib/syscalls.cyr"
struct S { a; b; }
fn mk2(x, y): S { var s = S { x, y }; return s; }
var GS = S { 1, 2 };
var GP: *S = &GS;
GP = mk2(7, 8);
syscall(60, GS.a + GS.b);
```

```
6.7.10: compiles, exits 3 (GP held a wild pointer, with a warning; GS unchanged)
6.7.11: error:<source>:7:6: 'mk2' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
```

D2 (copy into `*GP`) plus the value global's no-frame rule; D2's text names neither the refusal nor top level.

## 3. A destructure binding FEWER names than an undeclared fn returns is refused (RET-2, a1ec0eb5; D17)

```cyrius
include "lib/syscalls.cyr"
fn h3(x) { return (x, x + 1, x + 2); }
fn main(): i64 { var q, r = h3(5); return q + r; }
syscall(60, main());
```

```
6.7.10: compiles, exits 11 (right)
6.7.11: error:<source>:3:29: multi-value destructure binds 2 names, but 'h3' returns 3 values - bind 3 names: `var a, b, c = f(..);`
```

D17's line names the over-count; the issue proposed "a different name count", which the declared form already refused.

## 4. A wrapped one-leaf call of ANOTHER struct as a nested literal element is refused (ST-20, daecb518; D44)

`H { 7, (mko(5)), 8 }` with `struct H { a; q: Q; c; }` and `mko` returning another one-leaf struct `O` of 8 B or less
compiled through 6.7.10 (taking O's word as Q's leaf) and is now refused by name ("cannot copy 'mko' into a struct field
of a different struct type: 'q'"), as the unwrapped `H { 7, mko(5), 8 }` is. D44 names only the newly accepted
shapes; the refusal follows the guide's § Parentheses rule (a wrap is transparent).

## 5. Three changes the briefs marked "no decision needed" (from existing rules)

- **GF-12** (db81972b): a const context's call of another file's `private` const fn is refused, and a `#deprecated`
  const fn warns there — the guide's visibility boundary ("covers every way of reaching a fn"), enforced for a const
  READ since 6.7.2.
- **GF-16** (149eac24): the value of `await f` is an untyped word — `(await f) + n` with `f: *T` no longer scales `n`
  (6.7.9 decision 1(a), "the pointer step resets after every operator that does not produce a pointer").
- **GF-2** (2c7f3875): `p.bm(h)` on a bounded generic method runs its f64 impl (it ran the i64 base and returned 0) — the
  guide's 6.7.9 f64-bound rule.

## 6. D4's untyped store writes at most 8 bytes

D4 (user, 2026-10-13) reads "an untyped value is stored as the struct's word at sizeof(S) bytes"; it shipped as
min(sizeof(S), 8): `*p = 7` into a 16 B S leaves bytes 8..15 untouched. Filed separately as
[the untyped store through a struct pointer over 8 bytes](2026-10-14-untyped-store-through-struct-pointer-over-8-bytes-reading.md).
