# One mistake, more errors or the wrong one: an explicit generic call whose type-argument list is refused cascades into the receive / argument checks, a declaration whose initializer is refused leaves its name untyped, and an untypable chain's destructure says "needs a call" — OPEN

**Status:** 🟡 **OPEN** — two repairs of a day or more (rows 1, 2) and a diagnostics policy each needs first (row 2's
`var y = QQ;`, row 3's choice of error); the s16 and s16b lanes stopped on them.
**Placement:** 6.7.17 — the cleanup of the remaining issues (fec lane, wave 2, unit FC1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Discovered:** the s16 lane, unit SZ2 (its blocked B1 and B3); the s16b lane's fix step (row 3: "not fixed, still in
base").
**Severity:** Low — refused programs' diagnostics; nothing that compiles changes.
**Kind:** repair (rows 1, 2), with a diagnostics-policy decision (rows 2, 3).

## Summary

Each program below is refused for one mistake, and the compiler either adds errors that follow from its own recovery
(a refused list leaves the call reaching the generic's base; a refused initializer leaves the variable untyped) or
reports the destructure's generic refusal instead of the chain's own error.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B), x86_64
(the shared frontend). The B1 programs are the s16 lane's own probes.

**1. A refused type-argument list in an explicit generic call (B1).** Common head:

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct G2<T> { v: T; w: T; }
struct G3<T> { v: T; w: T; u: T; }
struct Pt { a; }
fn stb<T>(v: T): G2<T> { var g: G2<T>; g.v = v; g.w = v; var q = v.a; return g; }
fn stb1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; var q = v.a; return g; }
fn stb3<T>(v: T): G3<T> { var g: G3<T>; g.v = v; var q = v.a; return g; }
fn take2(g: G2<Pt>): i64 { return 0; }
```

| line 10 | errors |
|---|---|
| `fn f(): i64 { var x = stb<*Pt>(33); return 0; }` | 10:27 "a type argument is a type name, got '*'", then 10:31 "generic 'stb' has no i64 (or other scalar) instance: …" + its note |
| `fn f(): i64 { return take2(stb<*Pt>(33)); }` | 10:32 the list's refusal, then 10:28 "cannot pass 'stb' to a parameter of a different struct type in a call to 'take2'" |
| `fn f(): i64 { var x: G2<Pt>; x = stb<*Pt>(33); return 0; }` | 10:38 the list's refusal, 10:34 "cannot copy 'stb' into a variable of a different struct/vector type: 'x'", and warning 10:46 "assigning non-pointer to typed pointer" |
| `fn f(): i64 { var x = (stb<*Pt>(33)); return 0; }` | 10:28 the list's refusal alone (the control: one error) |

And with a non-generic `Pt` given type arguments:

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct Pt { a; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
fn f(): i64 { var x = mkg1<Pt<i32>>(33); return x.v + 1; }
syscall(60, f());
```

```
error:<source>:5:28: 'Pt' is not a generic struct: it takes no type arguments
warning: undefined function 'Pt_add'
warning: undefined function 'Pt_add' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

— x was typed by the lookahead's instance (`G1<Pt>`) while the call reached the base. `var x = (mkg2<Pt<i32>>(33));`
adds "fn return struct-id differs from declared var type" the same way.

**2. A refused initializer leaves its variable untyped (B3):**

```cyrius
struct P { a; b; }
struct W { p: P; n; }
fn mkw(): W { var w: W; w.p.a = 1; return w; }
var y = mkw().p;
syscall(60, y.a);
```

```
error:<source>:4:12: 'mkw' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
error:<source>:5:16: no struct type in scope for 'y'; a '.field' access needs its struct declaration (missing include?)
```

```cyrius
struct Q { a; b; }
fn f(): i64 { var y = QQ; return y.a; }
syscall(60, f());
```

```
error:<source>:2:25: undefined variable 'QQ' (missing include or enum?)
error:<source>:2:37: no struct type in scope for 'y'; a '.field' access needs its struct declaration (missing include?)
```

(The lane's third shape, `var y = idf(QQ); return y.a;`, now gives the one error.)

**3. An untypable chain as a destructure source:**

```cyrius
struct P { k; }
impl P { fn one(self): i64 { return 34; } fn m2(self): (i64, i64) { return (3, 4); } }
fn r(): i64 { var q = P { 1 }; var a, b = q.one().m2(); return a + b; }
syscall(60, r());
```

`error:<source>:3:43: multi-value destructure needs a call on the right-hand side` — the chain's own mistake (`.m2()` on
`one()`'s i64 result) is not what is reported. (The double-error form was fixed by the s16b lane's bfec3e0d4.)

## Repair plan and the policy each needs

1. **B1** — the lookahead `_gen_resolve_call` (29 callers), the emitting receives (asv / asp, `_struct_call_into`,
   `_vcall_enter`), the struct-copy check and the by-value argument check each judge the call independently; a refused
   list and a valid list the lookahead cannot read share `_targs_resolvable == 0`, and 6.7.15's D6 reads `Pt<..>` as Pt
   while `_explicit_generic_call` routes it to the base. Give the refused list a state of its own that every judge
   stands down on (and type x from what the call reaches). A day or more (the s16 lane's estimate).
2. **B3** — prior lanes stood down one shape each (a refused if-expression branch, an undeclared literal). The general
   stand-down — a declaration whose initializer was refused marks its name, and a `.field` / method use of a marked name
   is silent — spans every refusal kind × the fn / zone / after-the-first-statement forms and the zone sweep's twin. The
   policy first: is `var y = QQ; y.a` (and `var y = QQ + 1; y.a`) a cascade to silence or y's own error to keep
   (the zone gate's TI17 keeps an integer's own `g.a`)?
3. **The chain destructure** — which error to report when the destructure source is a chain the lookahead cannot type:
   the destructure's (today) or the chain's own (the method on a non-struct result).

Rows: each repro reports its one mistake once on x86_64, aarch64, cx and PE.
