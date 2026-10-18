# `&(x)` reports "expected identifier, got '('" and then a false "undefined variable 'fn'" naming the program's first word — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane's review (unit S3, beside
issues/archived/2026-10-15-return-address-of-handle-or-pointer-in-struct-fn.md), measured on the lane's tree and at the lane base
f133fb2f (the same output on both), x86_64. Frontend: every target alike. Pre-existing.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs review, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — diagnostics only: the statement is refused, at the right place; a second error follows that names a
token which is not in the statement.
**Kind:** bug (diagnostic cascade). `&(x)` is not valid syntax (the `&` factor takes a name); this filing does not ask
for it to compile — only for the one error.

## Reproduction

```cyrius
fn main(): i64 { var x = 5; var p = &(x); return load64(p); }
syscall(60, main());
```

```
$ build/cycc < amp.cyr > amp; echo $?
error:<source>:1:38: expected identifier, got '('
    fn main(): i64 { var x = 5; var p = &(x); return load64(p); }
                                         ^
error:<source>:1:39: undefined variable 'fn'
    fn main(): i64 { var x = 5; var p = &(x); return load64(p); }
                                          ^
1
```

In a fn returning a struct:

```cyrius
struct Q { v; }
fn mk(q: *Q): Q { return &(q); }
fn main(): i64 { var s = Q { 1 }; var r = mk(&s); return r.v; }
syscall(60, main());
```

```
error:<source>:2:27: expected identifier, got '('
error:<source>:2:28: undefined variable 'struct'
```

The name in the second error is always the program's FIRST word (`fn`, `struct`, `enum` …), whatever the statement.
Expected: the first error only.

## Root cause

The `&` factor in PARSE_FACTOR (src/frontend/parse_expr.cyr, `if (typ == 27)`): `if (PEEKT(S) != 2) { ERR_EXPECT(S,
2); }` records the error but does not return, so the arm goes on to `var anoff = PEEKV(S);` — the `(` token's value, 0
— and resolves name offset 0 (the name table's first entry: the source's first word) as a local, a global and a fn,
none of which it is: "undefined variable 'fn'".

## Fix direction

After the `ERR_EXPECT`, leave the factor as the other refusals do (`EMOVI(S, 0); return 0;`), skipping a balanced
`( .. )` so the parse stays in step. A row in a frontend gate asserting ONE error line for `var p = &(x);` and for
`return &(q);` in a struct fn.
