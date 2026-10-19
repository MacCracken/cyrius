# A method declared to return a vector, on a receiver whose head is a parenthesised dereference or a call (`(*ps).mv()`, `(*pw).s.mv()`, `gw(&w).s.mv()`), binds one word of garbage at an untyped declaration and stores a word into `: i64` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (its review-fix tree, 2e8b3d14f), x86_64 /
x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine). Pre-existing: the lane base (8b4d44602's build/cycc)
compiles every row too (x86_64 144 / 72 / 232 for rows 1-3, 0 for row 4).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 vectors review, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Medium — compiles with no diagnostic; the untyped local holds one word plus a stack word, a value that
differs per target, and an integer destination takes the result's word silently.
**Discovered:** 2026-10-18, the review of the 6.7.15 vectors lane — outside the filed surface of
`issues/2026-10-17-chained-receiver-vector-method-binds-a-word-annotated-refused.md` (a253da41a: a name-headed field
chain, `w.s.mv()`, `pw.s.mv()`, `h.w.s.mv()`).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
struct W { s: S; j; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn gw(p: *W): *W { return p; }
fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var v = (*ps).mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
```

The same header with `fn run()` replaced by each row (161 is right for rows 1-3):

```
row 1 (above)  var v = (*ps).mv();                 x86_64 64   IR=3 128  aarch64 168  cx 106  PE 195
row 2          var w: W; w.s.k = 1; var pw: *W = &w; var v = (*pw).s.mv();
                                                   x86_64 56   IR=3 136  aarch64 160  cx 98   PE 195
row 3          var w: W; w.s.k = 1; var v = gw(&w).s.mv();
                                                   x86_64 24   IR=3 136  aarch64 160  cx 98   PE 195
row 4          var x: i64 = (*ps).mv(); return x;  x86_64 0    IR=3 0    aarch64 0    cx 41   PE 41
(every row compiles with rc 0 and no diagnostic)
row 5          var v: f64v2 = (*ps).mv();          refused on all five: "a value-form vector local is initialised
               only from a local of its type, a call declared to return it (..) - got `(...)`"
```

Controls on the same tree: `var v = pw.s.mv();` (a name head, a253da41a) gives 161 on all five; `var x: i64 = s.mv();`
is refused (6.7.14's D38).

## Root cause

`_vmc_open` (src/frontend/parse_decl.cyr) recognises a method call on a single name (`_mcall_open`) or on a field chain
whose head is a NAME (`_mch_open`: `TOKTYP(S, ti) != 2` returns -1). A receiver whose head is `(` (a parenthesised
dereference) or a call (`gw(&w)`) is no method call to it, so `_vcall_vt` / `_vmc_fi` / `_svc_rs` see none: the untyped
declaration and the integer destination take the scalar path (one word), and the annotated vector declaration meets the
generic receive refusal.

## Fix direction

Recognise the method on a parenthesised-dereference head and on a call head (as the method-call arm itself types them —
`(*ps)` a struct value, `gw(..)` a call declared `: *W`) wherever `_vmc_open` is read, so rows 1-3 are the f64v2 local
(161), row 4 is refused as `var x: i64 = s.mv();` is, and row 5 compiles (161).
