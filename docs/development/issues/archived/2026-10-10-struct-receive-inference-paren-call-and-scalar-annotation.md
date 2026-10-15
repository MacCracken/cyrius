# A local's struct receive from a call: `var x = (mk());` infers nothing, `var x: u8 = mk();` infers the struct over its annotation — RESOLVED

> ✅ **RESOLVED in v6.7.11** (RET-8, commit 92b690cb: (a) a local's struct receive sees through parentheses around the whole call — repro (a) exits 34 on x86_64, aarch64, cx and PE (it gave 139 / 139 / 1 / 5), a codegen fix; (b) an annotation that names no struct and is no pointer, receiving a struct over 8 B from a free or generic fn call, is refused by name and keeps its annotation — repro (b) gives *cannot initialise 'x: i64' from 'mkp', which returns the struct 'P2' - declare 'x: P2' or bind a field*, the same for `y: u8`, and the follow-on `x.b` on the i64 x (3 errors; it exited 3). The user's decision D24 (2026-10-13, A) for (b). Rows: `struct_receive_inference_checked.sh` (31 rows, four compilers), `tests/tcyr/crossos/struct_receive_paren_call.tcyr`, `bool_checked.sh` W13. Not judged yet, filed: a method or operator call into a scalar annotation, a `*T` annotation, and a wrapped 8 B call. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — both shapes reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f,
`cycc_merged` 2,053,536 B) with the tree's compiler and the cross compilers built from it: repro (a) SIGSEGVs (exit
139) on x86_64 and aarch64 (qemu), exits 1 on cx (cxvm) and 5 on PE (wine), where 34 is right; repro (b) exits 3 on all
four, where 0 is right. The installed 6.7.4 and 6.7.7 compilers give 139 and 3 on x86_64. The 6.7.8 dyn lane refuses
both shapes for a `dyn` (its review commit 7482deb2 and bite D4's row V4d) but leaves every other struct as it was.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *The releases after 6.7.7*; PARSE_VAR's struct receive, a call-path
defect) — placed 2026-10-10 — never 7.x (the fix is the user's call, asked at that release's open: (a) changes what a
compiling program does; (b) either refuses code that compiles or changes its value).
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, reported only — (a) bite D4, (b) the lane's review round
(`~/.cache/c6/dyn_handoff.md` § D4 *Out of scope* and the review's *Out of scope*).
**Severity:** High — a silent wrong value (a `u8` holding 333, a scalar that is really a struct) and a SIGSEGV on source
that compiles with no diagnostic.
**Affects:** cycc 6.7.4 – 6.7.8 measured for both shapes (not bisected further).

## Summary

PARSE_VAR gives a local initialised from a call returning a struct over 8 B the struct's storage and type (the 9–16 B
rax:rdx receive or the > 16 B retptr), inferring the type from the callee when the declaration has none. Its test for
"the initialiser is a call" and for "the declaration has no type" are both too narrow:

- **(a) A parenthesised call is not a call to it.** `var x = (mk());` with `mk` returning a 16 B `Q` infers nothing:
  `x` is an i64 holding the FIRST word (3). `x.a` is refused ("no struct type in scope for 'x'"), and `dq(x)` into a
  by-value `q: Q` parameter passes 3 as the struct's address — SIGSEGV. `var x = mk();` infers `Q` and is right.
- **(b) A scalar annotation counts as "no annotation".** `var x: i64 = mkp();` / `var y: u8 = mkp();` with `mkp`
  returning a 16 B (or > 16 B) `P2` make `x` and `y` a `P2`: `x.b` compiles and reads the second word, and the `u8` `y`
  holds 333. (An 8 B struct is not inferred, so `var x: i64 = mk1();` stays a scalar and `x.a` is refused.)

## Reproduction

(a) `docs/development/issues/repros/2026-10-10-struct-receive-inference-a-parenthesised-call.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mk(): Q { var q: Q; q.a = 3; q.b = 4; return q; }
fn dq(q: Q): i64 { return q.a * 10 + q.b; }
fn main(): i64 {
    var x = (mk());
    return dq(x);
}
var rc = main();
syscall(60, rc);
```

```
expected: exit 34 (as with `var x = mk();`)
actual:   SIGSEGV, exit 139 (x86_64, aarch64); cx exits 1, PE exits 5
```

(b) `docs/development/issues/repros/2026-10-10-struct-receive-inference-b-scalar-annotation.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
fn main(): i64 {
    var x: i64 = mkp();
    var y: u8 = mkp();
    var bad = 0;
    if (y > 255) { bad = bad + 1; }
    if (x.b == 3) { bad = bad + 2; }
    return bad;
}
var rc = main();
syscall(60, rc);
```

```
expected: refused, or the scalars (x = 333, y = 77 — the first word, narrowed): exit 0 either way
actual:   exit 3 on all four targets (y holds 333; `x.b` compiles and reads 3)
```

Run each from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`src/frontend/parse_decl.cyr`, PARSE_VAR's struct receive (merged 6.7.8 tip):

- `:6513` gates the receive on `pscale <= 0` and an `=`, then `:6515` requires the initialiser's FIRST token to be an
  identifier (`_var_rhs_call` / `_call_ends_at` then check `IDENT (` … `;`). `(mk())` starts with `(`, so no receive
  is set up and the call's rax is stored into an 8-byte slot. (6.7.6 made parentheses transparent for a struct
  ARGUMENT, `_sarg_paren`, but not here.)
- `:6558` infers the struct when `pscale + lbool == 0`. A scalar annotation (`: i64`, `: u8`, read at `:6223` into
  `scalar_type` / `scalar_signed` / `lfloat`) leaves `pscale` at 0 — only `lbool` is consulted (6.7.3) — so it is
  treated as no annotation and `pscale` becomes the struct.

## Proposed fix

(a) Step over whole-initialiser parentheses (`_pwrap_k`, as `_sarg_paren` does) before the `IDENT (` test, so
`var x = (mk());` and `var x = ((mk()));` receive exactly as `var x = mk();` does. (b) Infer only when the declaration
has NO annotation: a scalar annotation receiving a struct over 8 B is refused by name ("cannot initialise 'x: i64'
from 'mkp', which returns the struct 'P2' — declare 'x: P2' or bind a field"), as the dyn lane refuses it for a dyn;
the alternative (the first word, narrowed to the annotation) is the user's other option. Rows: both shapes at 9–16 B
and > 16 B, `: i64` / `: u8` / `: f64` / `: bool` annotations, the parenthesised call at fn scope and in a closure, at
the four targets.

Related (the same "a parenthesised struct call is not a struct call" gap at another reader, filed the same day):
[a parenthesised struct-returning call as a nested-struct literal element](2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.md).
