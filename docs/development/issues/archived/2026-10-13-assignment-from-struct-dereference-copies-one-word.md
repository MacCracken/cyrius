# An ASSIGNMENT from a struct dereference (`l = *p`, `G = *p`, `o.s = *p`, `q = *p` into a `*S`) stores one word at every size, with a false "assigning non-pointer to typed pointer" warning — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-2: an assignment from a struct dereference copies the struct, as the declaration does — `l = *p`, `G = *p`, `o.s = *p` (through a `*O` too) and `q = *p` into the pointee of a `*S` or a handle, in every spelling, at top level and in a for step, with no warning; a `*U` of another struct is refused by name (no decision needed: 6.7.10's decision 6). The repro gives 58 on every row with no warning (it gave 50 / 50 / 50 / 100 with two warnings) on x86_64, aarch64, cx and PE; a `*S` global destination (`GP = *p`) copies into its pointee too (ST-8). Rows: `crossos/struct_deref_assign_copy.tcyr` (76, `small_struct_handle_line.sh` R11 on seven legs), `struct_copy_source_type_refused.sh` R17–R23, A4 / A5. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-13 against `build/cycc` 2,114,376 B (6.7.10, x86_64): with `s = {5, 8}` and
`p: *S = &s`, `l = *p;` leaves `l = {5, 0}` (exit 50 where 58 is right), and so do `G = *p;` and `o.s = *p;`;
`q = *p;` with `q: *S` rebinds `q` to the word 5 (its pointee untouched). `l = *p` and `q = *p` also warn "assigning
non-pointer to typed pointer". The declaration `var d: S = *p;` copies (58), and `q = l` copies `l` into `q`'s
pointee (58). Same at 24 B (`l = *p` gives `{5, 0, 0}`).
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** High — a silent wrong value on source that compiles clean (the only diagnostic is a misleading warning,
and two of the four shapes have none).
**Affects:** the 6.7.10 tree (measured there only, x86_64); the assignment arms are frontend-only, so every target.
The under-8 B over-read of the same source is a separate staged issue,
[`2026-10-12-small-struct-dereference-reads-past-the-object.md`](2026-10-12-small-struct-dereference-reads-past-the-object.md).

## Summary

6.7.10's B7-1d made a dereference of a `*S` a struct VALUE in every spelling, and the declaration copies it
(`_sci_dexpr`). The assignment forms do not: the source is parsed as an expression and its first word stored.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
H='struct S { a; b; }
struct O { s: S; }
var G = S { 0, 0 };'
row() { printf '%s\n%s\nsyscall(60, main());\n' "$H" "$2" > /tmp/dr.cyr
  build/cycc < /tmp/dr.cyr > /tmp/dr 2>/tmp/dr.err && chmod +x /tmp/dr && { /tmp/dr; echo "$1: exit $?"; grep -h warning /tmp/dr.err; true; }; }
row "l = *p           " 'fn main(): i64 { var s: S; s.a = 5; s.b = 8; var p: *S = &s; var l: S; l.a = 0; l.b = 0; l = *p; return l.a * 10 + l.b; }'
row "G = *p           " 'fn main(): i64 { var s: S; s.a = 5; s.b = 8; var p: *S = &s; G = *p; return G.a * 10 + G.b; }'
row "o.s = *p         " 'fn main(): i64 { var s: S; s.a = 5; s.b = 8; var p: *S = &s; var o: O; o.s.a = 0; o.s.b = 0; o.s = *p; return o.s.a * 10 + o.s.b; }'
row "q = *p (q: *S)   " 'fn main(): i64 { var s: S; s.a = 5; s.b = 8; var p: *S = &s; var t: S; t.a = 0; t.b = 0; var q: *S = &t; q = *p; return t.a * 10 + t.b + (q == 5) * 100; }'
row "ctl q = l        " 'fn main(): i64 { var t: S; t.a = 0; t.b = 0; var q: *S = &t; var l: S; l.a = 5; l.b = 8; q = l; return t.a * 10 + t.b; }'
row "ctl var d: S = *p" 'fn main(): i64 { var s: S; s.a = 5; s.b = 8; var p: *S = &s; var d: S = *p; return d.a * 10 + d.b; }'
```

Actual: 50 (+ the warning), 50, 50, 100 (+ the warning: `q` is now 5), 58, 58. Expected: 58 on every row, no warning
(the `q` row: `t` receives the struct, as `q = l` gives it).

## Root cause

- A name destination: `_try_aggregate_copy_assign` (`src/frontend/parse.cyr:3733`) takes only an identifier source
  (`PEEKT == 2`), so `*p` falls to `_pcmpe_struct_assign` (`:3548`), whose PCMPE reads the dereference as one word
  (`_deref_read`, `ELOAD64`) and the plain store writes it. The 6.7.10 pointer-source copy (`_hl_psrc_copy`, `:3022`)
  types `*T` names, calls, fields and pointer arithmetic, not a dereference. The warning is the local arm at `:4968`
  (`lt < 0 && _asg_ret_sid <= 0`, the dereference's pointer-scale 0) reading a struct local as a typed pointer.
- A struct-typed field destination: `_fsc_src` (`src/frontend/parse_decl.cyr:1151`) sends `*p` to `_fsc_expr`
  (`:1101`), whose value in rax is stored as one word.

## Proposed fix

Give the assignment the declaration's dereference arm: when the whole source is a dereference that `_hl_dstar` types
as a struct (`parse_decl.cyr:8098`), park the pointer and copy `STRUCTSZ` bytes into a struct-value destination (local,
global, struct-typed field), and into the pointee of a `*S` / handle destination, as `q = l` does; a `*U` of another
struct refused by name, as the declaration refuses it. No warning on a struct destination. Rows: the six above at 8,
16 and 24 B in `tests/tcyr/crossos/` (the copy is per-target codegen), a mutant RED per arm.

## Consumer-side workaround

Copy through a declaration first: `var t: S = *p; l = t;` (or `G = t;`, `o.s = t;`, `q = t;`) — 58 on every row.
