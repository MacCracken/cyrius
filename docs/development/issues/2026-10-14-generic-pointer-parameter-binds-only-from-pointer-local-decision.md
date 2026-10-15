# A `*S` LOCAL binds a generic's T to S — through an `x: *T` parameter and, against the guide, an `x: T` one — while `&G`, a `*S` global, field or parameter infer i64 and run the base — DECISION — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct`, `bcca83f9`; the `x: T`
row also on `42a0b63a`), x86_64, `struct S { v; w; x; }` (24 B):
- `fn gsz<T>(x: *T): i64 { return sizeof(T); }`: `gsz(p)` with `var p: *S` gives 24 (T = S, the `gsz$S` instance);
  `gsz(&GS)`, `gsz(GP)` (`var GP: *S`), `gsz(w.p)` (`p: *S` field), `gsz(&l)` and `gsz(q)` inside a fn taking
  `q: *S` all give 8 (T = i64, the base); `gsz<S>(&GS)` gives 24.
- `fn gs<T>(x: T): i64 { return sizeof(T); }`: `gs(q)` with `var q: *S` gives 24 — the guide says a pointer argument
  infers i64 there ("… and so does a `pp: *Pt` pointer parameter (a pointer, like a `var q: *Pt` local)",
  docs/guides/cyrius-guide.md § generics); `gs(pp)` with `pp: *S` a parameter gives 8, as the guide says.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 struct lane) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S2). The brief for
issues/2026-10-13-generic-pointer-returning-call-as-struct-source.md asked for rows in an inferred `gpi(&GS)` form
(`fn gpi<T>(x: *T): *T`); that call runs the i64 base — no instance with T = S exists — so its `: *T` result is a
`*i64`, not a `*S`, and the struct-source fix cannot type it without changing which fn the call runs. S2's rows use
the forms that do infer (`gpi(p)` with a `*S` local, and a by-value `gpv(GS)`).
**Severity:** Medium — silent: which fn runs (the base, T = i64: `sizeof(T)` 8, a `var y: T` one word, a `: *T` result
an untyped pointer; or the instance) depends on how the same pointer is spelled.

## The decision

The guide covers `x: T` (a pointer argument infers i64) but not an `x: *T` parameter, and the `*S`-local case no
longer matches what it says for `x: T`. Which is the rule?

- (a) through an `x: *T` parameter every argument the compiler types `*S` binds T = S — a `*S` local, parameter,
  capture or global, a `*S` field, a `: *S` call, and `&G` / `&l` of a struct `S` — and through an `x: T` parameter
  none does (the guide's rule, restored for a `*S` local);
- (b) as (a), but `&G` / `&l` stay i64 (`&x` is an untyped address under the handle line);
- (c) keep today's behaviour and document it (a `*S` local binds through both, nothing else binds).

(a) and (b) change which fn existing calls run (the base <-> the instance), so they are a language change.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/gz.cyr <<'X'
struct S { v; w; x; }
struct W { p: *S; }
var GS = S { 5, 8, 3 };
var GP: *S = &GS;
fn gsz<T>(x: *T): i64 { return sizeof(T); }
fn gs<T>(x: T): i64 { return sizeof(T); }
fn ma(): i64 { return gsz(&GS); }
fn mb(): i64 { return gsz(GP); }
fn mc(): i64 { var w = W { &GS }; return gsz(w.p); }
fn md(): i64 { var l = S { 1, 2, 3 }; return gsz(&l); }
fn me(q: *S): i64 { return gsz(q); }
fn mf(): i64 { return me(&GS); }
fn mg(): i64 { var p: *S = &GS; return gsz(p); }
fn mh(): i64 { return gsz<S>(&GS); }
fn mi(): i64 { var q: *S = &GS; return gs(q); }
fn mj2(pp: *S): i64 { return gs(pp); }
fn mj(): i64 { return mj2(&GS); }
X
for k in ma mb mc md mf mg mh mi mj; do
  { cat /tmp/gz.cyr; printf 'syscall(60, %s());\n' "$k"; } | build/cycc > /tmp/gz 2>/dev/null && chmod +x /tmp/gz
  /tmp/gz; echo "$k: exit $?"
done
```

Measured: ma 8, mb 8, mc 8, md 8, mf 8, mg 24, mh 24, mi 24 (the guide: 8), mj 8.

## Root cause

`_infer_conc_at_cursor` (`src/frontend/parse_fn.cyr`) — the argument reader `_gen_infer_tp` uses for either parameter
shape — binds a struct from a LOCAL whose slot type is `0 - sid` and refuses only a pointer PARAMETER
(`_is_ptr_param`, 6.6.10). Its comment's premise ("a `var q: *Pt` local (not struct-typed at all) infers i64") went
stale at 6.6.17, when a `*Struct` local took slot type `0 - sid` so `p.val` works (`_sl_ptr_type`,
`src/frontend/parse_types.cyr`): since then a `*S` local reads as a struct argument. A global goes through
`_infer_conc_global`, which reads GVTYPE (a `*S` global's is `0 - step`: i64); a field, a call and `&x` reach no rung
(i64). Nothing tells the reader whether the callee's parameter is `x: T` or `x: *T`.

## Consumer-side workaround

Spell the type argument (`gsz<S>(&GS)`, `gs<i64>(q)`), or bind the pointer to a `*S` local first.
