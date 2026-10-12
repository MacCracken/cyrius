# A value-form vector receive from `callptr` / `fncallN` (or any source but a by-name vector call) compiles with no diagnostic and reads wrong lanes, and faults on PE — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc` 2,057,744 B)
and the cross compilers built from it: `var v: f64v2 = callptr(fp, 41, 7);` with `fp = &mkv` (`fn mkv(a, b): f64v2`)
compiles with no diagnostic and `load64(&v) + load64(&v + 8)` exits 181 on x86_64, 180 on aarch64 (qemu) and 45 on cx
(cxvm), where 48 is right. PE (wine) faults: "page fault on write access to 0x0000000000000029". The callee takes 41
as its hidden result pointer. Calling `mkv(41, 7)` by name is right on all four. The installed 6.6.0, 6.6.10, 6.7.0 and
6.7.9 compilers give 181 on x86_64. The guide has said since the 6.7.9 doc sweep that "there is **no** working
spelling for a vector-returning `callptr` today" and that it "compiles with no diagnostic". No issue tracked it.
**Placement:** 6.7.11 — repair 1, the call-arguments lane (roadmap.md § *6.7.11*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the guide's *Returning a struct by value* re-verification: its
earlier text said "Reported for a later bite", and nothing in `docs/development/issues/` held it).
**Severity:** High. Silent wrong values on x86_64, aarch64 and cx, and a crash on PE, from source that compiles
clean.
**Affects:** cycc 6.6.0 – the 6.7.10 tree (measured at 6.6.0, 6.6.10, 6.7.0 and 6.7.9 on x86_64; the guide records 6.6.5
and 6.6.6 too). Every 16 B and 32 B vector type, on every target.

## Summary

A value-form vector local gets its 16 / 32 bytes and the vector receive (the register pair, or on Win64 the hidden
result pointer) only when its initialiser or assigned value is `IDENT (` naming a fn declared to return that vector.
Every other source falls to the one-word path: the local is one 8-byte slot, and its high lane(s) are whatever the
neighbouring frame slot holds. The item reported is the call through a fn pointer. The same fall-through takes every
other non-vector source, and the fix is one fix:

- `var v: f64v2 = callptr(fp, 41, 7);`, `callptr(&mkv, 41, 7)` (the callee is known), `fncall2(fp, ..)` and
  `fncall2(&mkv, ..)`: wrong lanes on x86_64 / aarch64 / cx. On PE nothing passes the hidden pointer, so the callee
  writes through its first argument.
- The assignment `var v: f64v2; v = callptr(fp, 41, 7);`: wrong (both lanes read 0 on x86_64 and aarch64), PE faults.
- **A parenthesised by-name call**, `var v: f64v2 = (mkv(41, 7));` and `v = (mkv(41, 7));`: wrong lanes, and PE
  faults, because the parenthesised call is emitted without the hidden pointer.
- A word source, `var v: f64v2 = 5;`, `= load64(&w)`, `= &w`, and the assignment `v = 5`: one word stored. It is
  neither a vector nor a handle: `lanes(v)` reads the word and a stale slot.
- `f64v4` likewise: `var v: f64v4 = callptr(fp, 5);` sums to 106 / 28 / 17 on x86_64 / aarch64 / cx (want 26), and PE
  faults.

What does compile right: `var v: f64v2 = mkv(41, 7);`, `v = mkv(41, 7);`, `var v: f64v2 = w;` from another `f64v2`
local. A vector global as a source or destination is already refused by name (6.6.17).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 {
    var fp = &mkv;
    var v: f64v2 = callptr(fp, 41, 7);
    return load64(&v) + load64(&v + 8);
}
syscall(60, run());
```

```sh
cd /home/macro/Repos/cyrius
cat /tmp/vcp.cyr | build/cycc > /tmp/vcp && chmod +x /tmp/vcp && /tmp/vcp; echo $?     # 181, want 48
cat src/main_win.cyr | build/cycc > /tmp/cc_win && chmod +x /tmp/cc_win
cat /tmp/vcp.cyr | /tmp/cc_win > /tmp/vcp.exe && wine /tmp/vcp.exe; echo $?          # page fault at 0x29, exit 5
```

The lanes read through a value-form parameter, `fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }`
(want 417 % 256 = 161), measured on x86_64 / aarch64 (qemu) / cx (cxvm) / PE (wine). Each row compiles with no
diagnostic:

| source of `v` | x86_64 | aarch64 | cx | PE |
|---|---|---|---|---|
| `var v: f64v2 = mkv(41, 7);` (control) | 161 | 161 | 161 | 161 |
| `var v: f64v2 = callptr(fp, 41, 7);` | 128 | 64 | 146 | 5 (fault) |
| `var v: f64v2 = callptr(&mkv, 41, 7);` | 128 | 64 | 146 | 5 |
| `var v: f64v2 = fncall2(fp, 41, 7);` | 128 | 64 | 146 | 5 |
| `var v: f64v2 = (mkv(41, 7));` | 128 | 64 | 146 | 5 |
| `var v: f64v2; v = callptr(fp, 41, 7);` | 0 | 0 | 154 | 5 |
| `var v: f64v2; v = (mkv(41, 7));` | 0 | 0 | 154 | 5 |

(The wrong values are stale frame words and move with the frame. The table is one build of each row.)

## Root cause

- `PARSE_VAR`'s vector receives, `src/frontend/parse_decl.cyr:6397` (`_is_simd128`) and `:6467` (`_is_simd256`),
  look ahead for exactly `IDENT (` whose fn's `GFRS` equals the declared vector. `_try_vector_call_assign` (`:5879`)
  does the same for `v = f(..)`. `callptr` is a builtin token, `fncall2` names `lib/fnptr.cyr`'s untyped fn, and `(`
  is not an IDENT, so each source misses the receive. It then takes the generic path: `_sl_ptr_type`
  (`src/frontend/parse_types.cyr:2349`) records the vector descriptor as the SLTYPE of ONE slot, and `EFLSTORE` stores
  `rax` into it. Neither the pair's second register nor the Win64 result pointer is involved.
- For an indirect call, `_PINDIRECT_CALL_IN` (`src/frontend/parse_expr.cyr:821`) knows the callee when it is written
  `&mkv` (`_icall_callee`, `:804`), but types only an f64 result (`_icall_result`, `:812`). Through a variable nothing
  is known.

## Proposed fix

1. **A vector receive accepts every source that IS the vector**: a parenthesised by-name call (unwrap the parentheses
   to the receive), and `callptr(&f, ..)` / `fncallN(&f, ..)` with a known `f` declared `: <that vector>`. Those take
   the pair store, or on PE the hidden pointer pushed as int arg 0, as `mkv(..)` does today.
2. **Every other source into a value-form vector local is refused by name**, at the declaration and at the
   assignment, as a vector global already is (`_vecg_refuse`). The one-line questions for the user:
   - *Should `var v: f64v2 = callptr(fp, ..)` through an unknown callee be refused, or should the annotation be taken
     as the callee's return type (the pair / the PE result pointer)?*
   - *Should a word source (`= 5`, `= load64(..)`, `= &w`) be refused, or bind as a pointer as a struct does?*

   Both refusals make code stop compiling that compiles today, with wrong values.
3. **Rows**, mutation-proven, on x86_64, aarch64 (qemu, then pi), cx (cxvm) and PE (wine, then cass), in
   `tests/gates/codegen/simd_return_shapes.sh` beside X13: the table above for `f64v2`, `f32v4`, `i32v4` and `f64v4`,
   each value read back lane by lane through a value-form parameter. Keep the guide's two verified workarounds GREEN.
   The guide's "there is **no** working spelling" paragraph moves to the CHANGELOG. `PARSE_VAR` sits near cybs's
   per-fn reference ceiling, so the new arms go in small fns and every bite runs the seed-derive gate.

## Consumer-side workaround

Call the vector-returning fn by name, unparenthesised (`var v: f64v2 = mkv(41, 7);`). When the target must be indirect,
give it an out-pointer and have it store the lanes:
`fn mkvp(out, a, b): i64 { store64(out, a); store64(out + 8, b); return 0; }`, then
`var v: f64v2; var ig = callptr(fp, &v, 41, 7);`. This gives 161 through `lanes(v)` on all four targets.
