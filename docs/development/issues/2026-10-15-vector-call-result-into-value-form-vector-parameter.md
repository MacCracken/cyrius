# A vector call result passed to a value-form vector parameter (`lanes(mkv(4, 2))`) is refused on x86_64 / aarch64 / cx with a cascade ("IDENT not found as a local" then "expected ';'"), and compiles to a page fault on PE — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1, after
`2026-10-13-pe-discarded-vector-call-result-no-hidden-pointer.md`'s fix, which gives the call its hidden result pointer
but leaves the argument's value its first lane) and on the slot-open compiler (`7f57e532`) alike.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; filed from the 6.7.12 fixfirst lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-15, the fixfirst lane, probing the PE discarded-vector fix's neighbours.
**Severity:** Medium — PE compiles valid-looking source to a crash with no diagnostic; the other targets refuse it
with a misleading first line and a cascaded second error. Workaround: bind the result to a vector local first.
**Affects:** every target (the refusal's wording and cascade), PE (the crash); every value-form vector parameter
(`v: f64v2`, `f64v2_add(a, ..)`'s value form, ...).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    return lanes(mkv(4, 2));
}
syscall(60, run());
```

```
x86_64 / IR=3 / aarch64 / cx:
error:<source>:4:21: value-form SIMD arg: IDENT not found as a local
error:<source>:4:22: expected ';', got number 4
PE (wine): compiles, exit 5 (a page fault)
```

The same with `f64v2_add(a, mkv(3, 4))` (lib/simd.cyr's value form): `error:<source>:5:36: value-form SIMD arg: IDENT
not found as a local` + `expected ';', got number 3` on x86_64 / aarch64 / cx; PE exit 5.

## Root cause

SysV / AAPCS64 / cx route a value-form vector argument through the SIMD second pass, which takes only a vector LOCAL
by name and refuses anything else with the inline-path's internal wording, then loses the token stream (the second
error). Win64 passes a value-form vector parameter BY ADDRESS (struct mask), so the argument reaches
`_try_push_struct_addr_arg` → the value push: the call's value (since 6.7.12 the first lane of its temp; before it,
whatever the callee left after writing through its first argument) is passed as the address the callee copies from.

## The question

A vector call result is a vector value: pass it (a temp's address on Win64; on SysV / AAPCS64 / cx the registers it
returns in, or a temp the second pass loads from), as D27 (6.7.12) passes one to a `*V` parameter — or refuse it by
name on every target, PE included, with one line ("a value-form vector argument is a local of its type — bind the
call first")?
