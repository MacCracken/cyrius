# A generic call declared `: *T` (`fn gpg<T>(): *T`) is no struct source: `l = gpg<S>()` stores the pointer's word, `*gpg<S>()` as a value SIGSEGVs (a declaration, an argument, either operand), `gpg<S>().v` is refused — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-4: a generic call declared `: *T` is a struct source, as `fn gp(): *S` is — the instance records T's struct and the chain typer reads the base's return under the call's binding without instantiating; a `*U` instance into an `S` destination is refused by name, naming the call, and a declaration-zone global over 8 B from a generic fn declared below it is refused by name (no decision needed: the non-generic form's 6.7.10 rule). The repro gives 8 / 58 / 58 / 41 / 69 / 5 / 58 (it gave 102 / 139 ×4 / refused / 58) on x86_64, aarch64, cx and PE. The inferred form is covered where the arguments infer T = S (`gpi(p)` with `p: *S`, `gpv(GS)`); `gpi(&GS)` infers T = i64 and runs the base — that inference rule is filed as a decision (issues/2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md), and a fn-local `var h: S = gpg<S>();` handle losing its annotation is filed too (issues/2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md). Rows: `crossos/generic_ptr_struct_source.tcyr` (72, `small_struct_handle_line.sh` R12 on seven legs), `generic_struct_field.sh` P1–P7 (the repro verbatim), PF1–PF3, PR1–PR7, PB. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-13 against `build/cycc` 2,114,376 B (6.7.10, x86_64), a 16 B `S`: `l =
gpg<S>()` leaves `l.v == &GS` and `l.w` untouched; `var q: S = *gpg<S>();` (at the first `q.v`), `take(*gpg<S>())`,
`a - *gpg<S>()` and `*gpg<S>() + a` exit 139; `gpg<S>().v` is refused "cannot take a field of the result of 'gpg': it
does not return a struct". Binding the call first (`var p: *S = gpg<S>(); var l: S = p;`) gives 58. The non-generic
`fn gp(): *S` copies in every one of these positions since 6.7.10 (ops-3, ops-5). The guide lists it as a known defect
(`docs/guides/cyrius-guide.md:1336`); no issue file carried it.
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane (ops-6 wrote the guide's note).
**Severity:** High — SIGSEGVs and a silent wrong value on source that compiles clean (the field form is a loud refusal).
**Affects:** the 6.7.10 tree (measured there only, x86_64); the typing is frontend-only, so every target.

## Summary

6.7.10's struct-source typing (`_hl_psid` / `_hl_pchain`) reads a `*T` name, a `: *T` call or method and a `*T` field
from the tokens, and skips a generic call by design: the instance records T's pointer STEP but not its struct. So a
`gpg<S>()` source is untyped: assigned, it is a word; dereferenced, the declaration binds a handle to the word the
dereference read (decision 1: an untyped `*x` stays a handle) and the argument / operand paths pass that word as the
struct's address.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
H='struct S { v; w; }
var GS = S { 5, 8 };
fn gpg<T>(): *T { return &GS; }
fn take(s: S): i64 { return s.v * 10 + s.w; }
fn S_sub(a: *S, b: *S): S { var r: S; r.v = a.v - b.v; r.w = a.w - b.w; return r; }
fn S_add(a: *S, b: *S): S { var r: S; r.v = a.v + b.v; r.w = a.w + b.w; return r; }'
row() { printf '%s\n%s\nsyscall(60, main());\n' "$H" "$2" > /tmp/gp.cyr
  if build/cycc < /tmp/gp.cyr > /tmp/gp 2>/tmp/gp.err; then chmod +x /tmp/gp; /tmp/gp; echo "$1: exit $?";
  else echo "$1: refused: $(grep -m1 error /tmp/gp.err)"; fi; }
row "l = gpg<S>()        " 'fn main(): i64 { var l: S; l.v = 1; l.w = 2; l = gpg<S>(); return (l.v == &GS) * 100 + l.w; }'
row "var q: S = *gpg<S>()" 'fn main(): i64 { var q: S = *gpg<S>(); return q.v * 10 + q.w; }'
row "take(*gpg<S>())     " 'fn main(): i64 { return take(*gpg<S>()); }'
row "a - *gpg<S>()       " 'fn main(): i64 { var a: S; a.v = 9; a.w = 9; var c: S = a - *gpg<S>(); return c.v * 10 + c.w; }'
row "*gpg<S>() + a       " 'fn main(): i64 { var a: S; a.v = 1; a.w = 1; var c: S = *gpg<S>() + a; return c.v * 10 + c.w; }'
row "gpg<S>().v          " 'fn main(): i64 { return gpg<S>().v; }'
row "ctl via var p: *S   " 'fn main(): i64 { var p: *S = gpg<S>(); var l: S = p; return l.v * 10 + l.w; }'
```

Actual: 102 (`l.v` is `&GS`, `l.w` still 2), 139, 139, 139, 139, refused, 58. Expected: 8 (`l = {5, 8}`: the row
returns `l.w` when `l.v` is no address), 58, 58, 41 (`{4, 1}`), 69 (`{6, 9}`), 5, 58 — what the same rows give with a
non-generic `fn gpg(): *S` (measured).

## Root cause

`_hl_pchain` (`src/frontend/parse_decl.cyr:8160`) returns 0 for a generic call (`:8168`, "`g<..>(`: a generic's
instance is not read here"), so `_hl_psid` (`:8134`) — and through it `_hl_dstar` (`:8098`), the 6.7.10 copy arms and
`_dro_check` — sees no struct. The field read refuses on the base fn's return (`src/frontend/parse_expr.cyr:2491`).
The instance's return is recorded as a pointer step only; its struct (T's sid) is not.

## Proposed fix

Record the struct a generic `: *T` instance points at when it is instantiated (T's sid, beside the step), and let
`_hl_pchain` resolve `g<..>(` to the instance (`_gen_resolve_call`, `src/frontend/parse_fn.cyr:10959`, as `_fsc_call`
does) and read that record; the field-of-result path reads the same. Every arm that types a `: *T` call then covers
the generic form. Rows: the seven above at 8, 16 and 24 B, with an inferred `gpg(x)` form too, in
`tests/tcyr/crossos/`; drop the guide's known-defect note.

## Consumer-side workaround

Bind the call to a `*S` first: `var p: *S = gpg<S>();`, then `l = p`, `*p`, `take(*p)`, `p.v` (58 / 5).
