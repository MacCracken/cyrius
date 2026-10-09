# `CYRIUS_IR=3` drops unrecorded field-access bytes: signed narrow fields read garbage, a field read after a dead store reads the wrong slot — OPEN

**Status:** 🟡 **OPEN** — both reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` under `CYRIUS_IR=3` (the
default pipeline and `CYRIUS_IR=1` are right): (1) `s.a + s.b` over `i8` fields through `s: *S` gives a different
garbage value per run (119 / 199 / 103 where 37 is right — the binary is deterministic, the value is a stack address);
(2) `h.name = 40; h.k = 7; var u = 0; u = h.name; return u + 1;` gives 8, not 41, and SIGSEGVs when the field is a
`Str`. Both also reproduce with the installed 6.6.20, 6.7.0, 6.7.3 and 6.7.5 compilers.
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** (1) the 6.7.5 B8 review ("same on 6.7.4; nondeterministic"); (2) 6.7.6 lane E (the
`struct_value_codegen.sh` S10 shape: `u = h.name` into a `Str`); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — silent wrong values and a SIGSEGV on valid code, but only under the opt-in `CYRIUS_IR=3`
(workaround: do not set it; no release build uses it).
**Affects:** cycc 6.6.20 – 6.7.6 at least (not bisected further), x86_64 `CYRIUS_IR=3` only

## Summary

`CYRIUS_IR=3` runs IR passes (LASE, DBE, dead-store / liveness DCE, const-fold) that patch the emitted x86 code from
the IR record. Bytes emitted WITHOUT an IR record are invisible to those passes, and two field-access emits are such
bytes:

1. **A SIGNED narrow field read through a pointer or a closure capture** — the negative-width `EFIELD_LOAD_W` (a
   `movsx` from `[rcx]`) is not recorded, so under IR=3 the load disappears and the field's ADDRESS is used as its
   value: `s.a + s.b` became `s + s.b` (the result varies with ASLR). 6.6.12 fixed only the array-subscript caller
   (`_arr_sub_load` records the raw emit itself).
2. **A field read right after a dead store** — `var u = 0; u = h.name;`: the `u = 0` store is dead and IR=3 removes
   it, and with it the following `lea rcx, [rbp+disp]` that sets up `h.name`'s address (`EFLADDR_X1` records nothing).
   The load then reads through whatever rcx held — `&h.k` from the previous `h.k = 7` store (u = 7, result 8), or
   `&h.k + 8` for `u = h.k` (past the struct, result 1 where 8 is right). With a `Str` field the stale word is
   dereferenced: SIGSEGV.

## Reproduction

```cyrius
# (1) — prints a different wrong value per run under CYRIUS_IR=3; 37 otherwise
struct S { a: i8; b: i8; }
fn h(s: *S): i64 { return s.a + s.b; }
fn main(): i64 { var x: S; x.a = 30; x.b = 7; return h(&x); }
syscall(60, main());
```

```cyrius
# (2) — 8 under CYRIUS_IR=3; 41 otherwise
struct HS { name; k; }
fn main(): i64 { var h: HS; h.name = 40; h.k = 7; var u = 0; u = h.name; return u + 1; }
syscall(60, main());
```

```sh
cat one.cyr | CYRIUS_IR=3 build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
cat one.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?            # control
```

Measured: (1) 119, 199, 103 (three compiles, md5-identical binaries; three runs of one binary gave 7, 7, 23) vs 37;
the same through a closure capturing `x` (`|d| { return x.a + x.b + d; }`) gives 15 vs 37. (2) 8 vs 41; `u = h.k` →
1 vs 8; without the dead store (`var u = h.name;`, or another statement between) it is right. With `struct HS { name:
Str; k; }`, `h.name = str_from("abc"); … var u: Str = str_from("x"); u = h.name; return str_len(u);` → exit 139 vs 3.

(1)'s x86 under IR=3 — `h`'s body: `mov rax,[rbp-0x30]; push rax; mov rax,[rbp-0x30]; mov rcx,rax; add rcx,1;
movsx rax,BYTE PTR [rcx]; pop rcx; add rax,rcx` — the first operand's `movsx` is gone (the pushed value is the pointer).
(2)'s: `mov [rcx],rax` (h.k = 7) · `xor eax,eax` · `mov rax,[rcx]` — the `mov rbx,rax` (u = 0) and the
`lea rcx,[rbp-0x38]` after it are both gone.

## Root cause

1. `EFIELD_LOAD_W` (`src/backend/x86/emit.cyr:710`) records `IR_RAW_EMIT` only for widths 1 / 2 / 4
   (`if (width == 1 || width == 2 || width == 4)`); a signed field passes -1 / -2 / -4. `_arr_sub_load`
   (`src/frontend/parse_expr.cyr:2411`) adds the record for its own negative widths; the field-read callers do not.
2. `EFLADDR_X1` (`src/backend/x86/emit.cyr:5218`) emits `lea rcx, [rbp+disp32]` with no `_IR_REC` at all. Speculation
   (not traced through the pass): its bytes fall inside the IR node before it — the dead `u = 0` store — and the
   dead-store pass NOPs that node's whole byte range, lea included. (1) is likely the same mechanism with the signed
   load's bytes.

## Proposed fix

Record every field-access emit: move the negative-width `IR_RAW_EMIT` record into `EFIELD_LOAD_W` itself (all widths
that emit a narrow load), and give `EFLADDR_X1` an IR record (an rcx-defining node, so liveness sees rcx written, as
`IR_LOAD_ADDR_G_X1` is for `EVADDR_X1`). Then audit the other x86 emitters for unrecorded bytes the same way (any
`E3` / `EB` sequence not preceded by `_IR_REC*`). Default-pipeline output must stay byte-identical (the records only
add IR nodes). Add both shapes to `tests/tcyr/crossos/struct_value_codegen.tcyr`, which `struct_value_codegen.sh` row
A3 already runs under `CYRIUS_IR=3`.
