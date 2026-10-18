# A wrapped vector call — by name or a method — into an untyped or a scalar declaration binds a word, and a method's `s.mv() + 1` into `: i64` is not refused — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V4, after the D37 / D38 bite that makes an
untyped `var v = s.mv();` the vector and refuses `var x: i64 = s.mv();` / `x = s.mv();`, each a WHOLE method call as
filed). The neighbouring shapes below are pre-existing — the by-name rows behave the same on the lane base — and were
not in the filing. Frontend: every target.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D28 — A: transparent.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D29 — A: refused.
**Severity:** Medium — rows 4 and 5 compile clean and read the wrong lanes, silently, on every target; rows 1-3 store a
word whose value differs per target, where the unwrapped by-name call is refused.
**Kind:** language (decision) — the guide's § Parentheses (6.7.6) makes parentheses around a whole struct source
transparent, and 6.7.11 made them transparent for the annotated vector local (`var v: f64v2 = (mkv(..));`), but not
for the untyped declaration nor for a scalar annotation. Row 3 is a method's spelling of a shape the by-name call
refuses (PARSE_VAR's check tests the call that STARTS the initialiser; the D38 bite tests a whole method call, as filed).

## Reproduction

```cyrius
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
fn r(): i64 { var x: i64 = (mk2(41, 7)); return x; }                                                   # row 1
syscall(60, r() % 256);
```

The same header with `fn r()` replaced by each row:

```
row 1  var x: i64 = (mk2(41, 7)); return x;                                          x86_64 / IR=3 / aarch64 0, cx 41, PE 41
row 2  var s: Mv = Mv { 1 }; var x: i64 = (s.m2()); return x;                         x86_64 / IR=3 / aarch64 0, cx 41, PE 41
row 3  var s: Mv = Mv { 1 }; var x: i64 = s.m2() + 1; return x;                       x86_64 / IR=3 / aarch64 1, cx 42, PE 42
row 4  var x = (mk2(41, 7)); return load64(&x) * 10 + load64(&x + 8);                 x86_64 / IR=3 / aarch64 0, cx 154, PE 195
row 5  var s: Mv = Mv { 1 }; var x = (s.m2()); return load64(&x) * 10 + load64(&x + 8);  x86_64 / IR=3 / aarch64 1, cx 155, PE 195
(every row compiles with no diagnostic; 161 is the vector in rows 4 and 5)
```

The assignment the same (x86_64, compiles, no diagnostic): `var x = 0; x = (mk2(1, 2));` and `var x = 0; x = (s.m2());`,
where the unwrapped `x = mk2(1, 2);` / (D38) `x = s.m2();` are refused "vector return type does not match the assigned
variable".

Compare, refused since 6.7.11 (by name) and 6.7.14 (the method, D38): `var x: i64 = mk2(41, 7);`, `var x: i64 = mk2(41,
7) + 1;`, `var x: i64 = s.m2();` — "vector return type does not match the declared type"; and the untyped `var x =
mk2(41, 7);` / (D37) `var x = s.m2();` are the f64v2 local (161).

## Root cause

PARSE_VAR's vector inference and declared-type check (src/frontend/parse_decl.cyr, the `vin` block: `_vcall_fi(S,
GTI(S) + 1)`) and the untyped receive's `_vrcv_ity` (`callptr` / `fncallN`, and since D37 a whole method,
`_vmc_whole`) read the token after `=` — a `(` is none of them; the scalar path then stores the first word. The D38
method check (`_vrcv_mscal` / `_vasg_mscal`) asks for a whole call, so `s.m2() + 1` reaches the scalar path.

## The question

Are parentheses around a whole vector call transparent at the untyped and scalar declarations — rows 4 / 5 the vector
(161), rows 1 / 2 refused as the unwrapped call is — and is a method that starts a scalar initialiser (row 3) refused as
the by-name call that starts one is?
