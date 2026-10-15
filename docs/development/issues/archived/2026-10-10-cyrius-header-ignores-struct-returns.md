# `cyrius header` prints `cyr_val f(..)` for a fn returning a struct (9-16 B: rax:rdx; > 16 B: a hidden pointer) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (TL-11 and its review fix TL-11r: the repro prints `cyr_val2 mkq(..)` and `cyr_val2 mkd(..)` (`/* returns Q, 16 B */`, `/* returns dyn Show, 16 B */`) under `#ifndef _WIN64` with a named comment and no prototype on Win64, `cyr_val3 mkr(cyr_val a);   /* returns R, 24 B */`, `plain` unchanged — a C caller through the header measured right on x86_64 (linked), against cycc's aarch64 code on pi, and the Win64 registers on cass. A two-value return is `cyr_val2` on x86_64 SysV only (aarch64 lands it in x0:x2); what the scanner cannot size from the file (another file's type, a generic instance, a struct holding one, a struct declared twice or with `#ifdef`'d fields, three values) is refused by name, rc 1; field sizes held to cycc's `sizeof`, a bare `Vec` field the file's own `struct Vec` when declared above it. The user's decision D29, 2026-10-13. Rows: `header_spellings_and_size.sh` H7–H11b, `dyn_checked.sh` TT4, `tuple_checked.sh` T1; mutations RED (the annotation ignored 34). Outside the filed struct / dyn surface and filed (6.7.12): a SIMD vector return and a `: stack` enum return still print `cyr_val`; a bare `Vec` field's compiler layout depends on declaration order. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cyrius` (throwaway `HOME` / `CYRIUS_HOME`): for the repro's `fn mkq(a, b): Q` (16 B), `fn mkr(a): R` (24 B) and
`fn mkd(p: *Q): dyn Show` it prints `cyr_val mkq(cyr_val a, cyr_val b);`, `cyr_val mkr(cyr_val a);` and
`cyr_val mkd(cyr_val p);` — the same as for `fn plain(a): i64`. The installed 6.7.7 CLI prints the same four lines.
The ABI each prototype misstates is read from the compiler (`_ret_agg_class`), not run against a C caller.
**Placement:** 6.7.11 — repair 1, the tools lane — a High, from 6.7.12 (pulled in at the open: user, 2026-10-13) — never 7.x. Was: 6.7.12 — repair 2, the CLI lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never
7.x (the fix is the user's call, asked at that release's open: it changes a tool's output).
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D7 (a `dyn` return is a 16-byte {data, vtable}
pair; the header hands a C caller the data word alone). It predates the lane: the tool never reads a return type.
**Severity:** High — a generated C header that is wrong for every struct-returning fn; for a > 16-byte return a C
caller following it passes its first argument where the callee writes the result (memory corruption).
**Affects:** the `cyrius header` verb (`cbt/quality.cyr`), every version that has it — measured 6.7.7 and 6.7.8

## Summary

`cyrius header <file.cyr>` emits a C prototype per public fn, with every parameter and every return typed
`cyr_val` (`int64_t`). That holds for a word, but cycc returns a struct three ways (`_ret_agg_class`,
`src/frontend/parse_fn.cyr:4288`): 8 bytes or less in rax (a word — right), 9-16 bytes in rax:rdx (a `Q`, a `dyn Tr`
— the C caller reads rax alone and loses the second word, for a dyn the vtable), and over 16 bytes through a hidden
result pointer (x86_64: integer argument 0; aarch64: x8) — where the prototype's first `cyr_val` parameter lands in
the callee's result-pointer slot and every real argument is shifted by one.

## Reproduction

`docs/development/issues/repros/2026-10-10-cyrius-header-ignores-struct-returns.cyr` (it builds with `build/cycc`):

```cyrius
struct Q { a; b; }        # 16 B: returned in rax:rdx
struct R { a; b; c; }     # 24 B: returned through a hidden pointer (x86_64: integer argument 0; aarch64: x8)
trait Show { fn show(self): i64; }
impl Show for Q { fn show(self): i64 { return self.a; } }
fn mkq(a, b): Q { var q = Q { a, b }; return q; }
fn mkr(a): R { var r = R { a, a, a }; return r; }
fn mkd(p: *Q): dyn Show { return p; }
fn plain(a): i64 { return a; }
```

```sh
T=$(mktemp -d); HOME=$T CYRIUS_HOME=$T/.cyrius build/cyrius header docs/development/issues/repros/2026-10-10-cyrius-header-ignores-struct-returns.cyr; rm -rf "$T"
```

```
actual:   cyr_val mkq(cyr_val a, cyr_val b);
          cyr_val mkr(cyr_val a);
          cyr_val mkd(cyr_val p);
          cyr_val plain(cyr_val a);
expected: mkq / mkd as a two-word C struct return (`typedef struct { int64_t w0, w1; } cyr_val2;` — rax:rdx is the
          SysV return of a 16-byte INTEGER-class struct); mkr as a by-pointer return the C side can call correctly
          (a 24-byte struct return, which SysV also passes as a hidden first pointer), or the fn left out / refused
          by name; plain unchanged
```

## Root cause

`cmd_header` (`cbt/quality.cyr:876`) finds each public fn, writes `cyr_val <name>(` and walks the parameter list; it
never looks past the parameter list's `)`, so the `: T` return annotation is not read at all. (A by-value struct
PARAMETER over 8 bytes is address-passed, so its `cyr_val` is a pointer — right, but nowhere stated.)

## Proposed fix

Read the return annotation. A struct name (the file's own `struct` declarations, sized by the rules the compiler
uses — the header is a source scanner, so it needs the struct's field widths) or a `dyn Tr`: 9-16 bytes → a
two-word struct typedef emitted once; over 16 bytes → a C struct of the same size returned by value (SysV and AAPCS64
both pass a large struct return through a hidden pointer, which is what cycc does), or, if the tool will not size
structs, refuse that fn by name ("cannot express ... in C") rather than print a wrong prototype. A struct the scanner
cannot size (from another file) is refused by name, never guessed. Rows (the existing gate
`tests/gates/toolchain/header_spellings_and_size.sh`): the repro's four fns; a struct of 8 bytes or less (stays
`cyr_val`); `Str`; a generic struct return.

## Consumer-side workaround

Hand-write the prototype of any struct-returning fn, or wrap it in a cyrius fn that writes the struct through an
out-pointer and returns a word.
