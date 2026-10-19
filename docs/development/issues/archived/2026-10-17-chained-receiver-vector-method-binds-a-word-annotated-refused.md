# A vector method on a CHAINED receiver — untyped `var v = w.s.mv();` binds one word (garbage, per target); the annotated `var v: f64v2 = w.s.mv();` is refused "got `w`" — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-4, `a253da41a` — no decision needed: 6.7.13's D29 A and 6.7.14's D37 / D38 / D39 apply to any receiver spelling. `_vmc_open` / `_mch_open` (src/frontend/parse_decl.cyr) recognise a method on a field chain beside a single name: the head, `.field` hops through inline and `*S` fields, then the method. Every vector receive reads them. The filed repro `var v = w.s.mv();` gives 161 on x86_64, IR=3, aarch64, cx and PE; it was garbage, per build. The annotated declaration, the assignment, a value-form or `*V` argument and the return take the vector; they were refused "got `w`". `var x: i64 = w.s.mv();` / `x = w.s.mv();` are refused; they stored a word. Rows: `simd_return_shapes.sh` CR1 (the filed repro verbatim) – CR7 and CRK1 – CRK6, on the five legs; `crossos/simd_value_return_binding.tcyr` group H (17). Mutations: M-CR1 RED 60, M-CR2 RED 5. Not closed here (filed, 6.7.16; outside the filed surface): a receiver whose head is a parenthesised dereference or a call, `(*ps).mv()` or `gw(&w).s.mv()`, still binds a word (2026-10-18-vector-method-on-dereference-or-call-head-receiver-binds-a-word.md). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (its review-fix tree) and on the lane base
c3af6501, x86_64 / x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine). Pre-existing: the lane base binds a
word and refuses the annotated form the same way.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Medium — the untyped row compiles with no diagnostic and reads stack garbage that differs per target and
per build; the annotated row refuses valid code.
**Discovered:** 2026-10-17, the review of the 6.7.14 vectors lane (probes m5 / m6), beyond D37 / D29's filed surface: a
whole method call on a single-name receiver, `s.mv()`
(`issues/archived/2026-10-16-vector-method-result-untyped-scalar-and-return-destinations.md`).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
struct W { s: S; j; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 { var w: W; w.s.k = 1; var v = w.s.mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
```

```
review tree:  x86_64 120   IR=3 168   aarch64 160   cx 98   PE 195     (compile rc 0, no diagnostic)
lane base:    x86_64 120   IR=3 8     aarch64 160   cx 98   PE 195
the review's own run of the lane tree: x86_64 40, IR=3 120, aarch64 128, cx 98, PE 195 — the values move between builds
161 is the vector, (41 * 10 + 7) % 256.
```

The annotated form, `var v: f64v2 = w.s.mv();` in the same fn, is refused on every target (and on the lane base):

```
error:<source>:5:53: a value-form vector local is initialised only from a local of its type, a call declared to return
it (by name, a method, or fncallN / callptr with the callee written `&f`) or a dereference of a pointer to its type
(`*p`) - got `w`
```

Compare: with a single-name receiver, `var v = s.mv();` (D37) and `var v: f64v2 = s.mv();` (6.7.13's D29) are the
f64v2 local, 161 on every target.

## Root cause

The method arms of the vector receives recognise a method call by `_tok_method_open(S, ti)` (src/frontend/parse.cyr),
which matches exactly `name . name (` at the cursor, and resolve the receiver's struct from that one name
(`_pair_callee_at` → `_recv_sid`) — `_vmc_fi` (6.7.13's D29, the annotated receives, src/frontend/parse_decl.cyr) and
`_vmc_whole` (D37's untyped inference) both. `w.s.mv(` is `name . name . name (`, so the untyped declaration takes the scalar path (one word,
the result register's) and the annotated one reaches the by-name refusal, which names the chain's first token.

## The question / fix direction

A whole method call on a field chain (`w.s.mv()`, `pw.s.mv()`, `h.w.s.mv()`) declared to return a vector is that
vector at the receives a single-name receiver's is (untyped and annotated declarations, assignment, return, a value-form
argument), or refused by name where it is not.
