# A top-level untyped `var G = B.mk1();` / `= A + C;` / `= fncall0(&mk1);` with a struct result binds no struct — 8 B: `G.a` is "no struct type in scope for 'G'"; 9-16 B: G silently holds the first word — where 6.7.14's D29 / D30 bind (8 B) or refuse (9-16 B) the free call `var G = mk1();` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives at ed1e01b1, unit R4, after the
D29 / D30 bite), x86_64 (`build/cycc` the lane's fixpoint); the frontend is shared, so every target is the same.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D34 — (a) yes, it binds the struct.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D35 — (a) refused by name, once.
**Severity:** Medium — the 9-16 B rows are silent: an untyped top-level global initialised from a whole method,
operator or known `&f` result over 8 B holds the struct's first word with no diagnostic, where the free call of the
same struct is refused (D30 (a)); the 8 B rows refuse valid code at its first `.field` (Low half).
**Discovered:** 2026-10-17, the receives lane (unit R4), while repairing
`issues/archived/2026-10-16-top-level-untyped-struct-call-receive-infers-nothing.md`. That issue's filed surface and its decisions
(D29 / D30: "an untyped `var x = mk1(30);` (or `= (mk1(30));`)") are a whole FREE call; the other whole struct results
at top level were left as found, here. Its gate pins one of them (struct_receive_inference_checked.sh SATK2: `var G2 =
B.mk();`, 16 B, "keeps the word").

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct P1 { a; }
struct P2 { a; b; }
impl P1 { fn mk1(self): P1 { var q: P1; q.a = 33; return q; } }
impl P2 { fn mk(self): P2 { var q: P2; q.a = 33; q.b = 4; return q; } }
fn P1_add(l: P1, r: P1): P1 { var q: P1; q.a = l.a + r.a; return q; }
fn P2_add(l: P2, r: P2): P2 { var q: P2; q.a = l.a + r.a; q.b = 1; return q; }
fn mk1(): P1 { var p: P1; p.a = 33; return p; }
fn mk2(): P2 { var p: P2; p.a = 33; p.b = 4; return p; }
var B1 = P1 { 1 };
var B2 = P2 { 1, 2 };
var G = B1.mk1();
syscall(60, G.a);
```

```
error:<source>:14:16: no struct type in scope for 'G'; a '.field' access needs its struct declaration (missing include?)
```

The same for `var G = B1 + B1;` and `var G = fncall0(&mk1);`, in the declaration zone and after a first statement
(`var Z = 0; Z = 1;`). Over 8 B, `var G = B2.mk(); syscall(60, G);` builds and exits 33 (the first word),
`var G = B2 + B2;` exits 2, `var G = callptr(&mk2);` exits 33 — zone and after alike — where `var G = mk2();` is
refused "'mk2' returns a struct by value, and a struct result needs storage in a fn's frame" (D30 (a)) and
`var G: P2 = B2.mk();` is refused by name (6.7.9's `_sc_global_pair`).

## Root cause

D29 / D30's typing reads only a whole free call (`_gu_sid` / `_gu_call`, src/frontend/parse_decl.cyr: `_rcv_iscall`).
A method / operator / known-callee result has no call token to read; its struct comes from the parse's `_sc_*` record
(`_sc_whole`: -3 for 8 B or less, -1 for 9-16 B at top level) or `_icall_sid_at`, which PARSE_VAR's global arm and the
zone replay do not consult for an untyped declaration (`_sc_global_receive`: "Untyped `var g = ..` keeps the first
word"). In the zone the global would also have to be typed before pass 2 compiles fn bodies (the sweep reads tokens:
`_gz_ty` types a method / operator / `&f` result already).

## The question

Decision 12 (6.7.10, extended 6.7.11) binds every whole struct result at every size, and D29 / D30 took it to the
free call at top level. Should the untyped top-level declaration bind a whole method / operator / known `&f` result of
8 B or less (`G.a` compiles), and refuse one of 9-16 B as the annotated `var G: P2 = B2.mk();` is? The 9-16 B half makes
compiling code stop compiling (SATK2's row changes). Rows: 8 / 16 / 24 B x {method, operator, `fncall0(&f)`,
`callptr(&f)`} x {zone, after a first statement}, wrapped and not.
