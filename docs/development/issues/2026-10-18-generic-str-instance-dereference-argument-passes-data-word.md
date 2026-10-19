# A `*Str` dereference into a generic's `x: T` with T = `Str` (`gg<Str>(*p)`, inferred `gg(*p)`) passes the header's data word — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S3), measured on the lane's tree after its
`str_len(*p)` fix (issues/2026-10-17-str-pointer-dereference-into-str-parameter-passes-data-word.md) and on the lane
base (c557ee1b1): the same values on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Medium — silent: the callee reads the string's bytes as a `Str` header (`str_len` 0 here; a longer
string gives a wild length and data pointer). Not a security id (the developer's own source).
**Kind:** bug — the twin of the 6.7.15 fix, outside its filed surface (`str_len(*p)`, `f(**pp)`, `str_len(*w.p)`,
`h.eq(*p)` into a `s: Str` parameter): a generic instance's `T` bound to `Str`.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn gg<T>(x: T): i64 { return str_len(x); }
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var h = str_from("abcde");
    var p: *Str = h;
    return f(*p) * 100 + gg<Str>(*p) * 10 + gg(*p);
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < fg.cyr > fg && ./fg; echo $?
244         # 500 mod 256: f(*p) 5 (fixed in 6.7.15), gg<Str>(*p) 0, gg(*p) 0 — 555 (exit 43) is right
```

`gg<Str>(h)` (a handle), `gg<Str>(p)` and `gg<Str>(t)` (an inline `Str`) give 5 / 5 / 7; `var s: Str = *p;
gg<Str>(s)` gives 5. Only the dereference argument is wrong.

## Root cause

The instance `gg<Str>`'s `x: T` is address-passed as a 16-byte struct (its struct-mask bit set), so the argument
takes `_try_push_struct_addr_arg`'s dereference arm (`_sarg_deref` -> `_push_struct_expr_arg`, src/frontend/
parse_fn.cyr), which parks a dereference only of a plain struct: `_dlo_park` (src/frontend/parse_expr.cyr) returns 0
for `sid == _STR_SID(S)`. The `*p` is then parsed as a word read and its data word pushed as the address. The 6.7.15
arm (`_sarg_istr_dx`) sits in `_sarg_byval_small`, which a struct-mask parameter never reaches. The inferred `gg(*p)`
binds no T from a dereference of a `*Str` (it runs the i64 base, whose `str_len(x)` reads the word).

## Fix direction

Let the address-passed dereference arm take a `*Str` operand as `_sarg_istr_dx` does (pass E's value, the header's
address) when the parameter's bound type is `Str`; decide whether `gg(*p)` infers T = Str from a `*Str` dereference as
`gg(t)` does from an inline `Str`. Rows beside tests/tcyr/crossos/inline_str_value.tcyr's sd_* rows.
