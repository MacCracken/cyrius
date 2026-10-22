# `var p: *Str = str_from(..);` and `GP = str_from(..);` warn "assigning non-pointer to typed pointer"; `q = str_from(..);` into a `*Str` local does not — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-18, `478e4f6cd` — no decision needed (the `*Str` local's exemption since 6.5.28 given to the declaration and global sites). `_tp_call_pointee` (src/frontend/parse_decl.cyr) exempts a value that is one call — a free fn or a method through nested struct fields — whose declared return is the destination's pointee, when that pointee is `Str`; `_tp_warn_decl`, the zone's `_tp_warn_gv` and the new `_tp_warn_gasg` (the global assignment arm) consult it. The filed repro now compiles with no warning (it warned at 6:36 and 7:25) and still exits 20, binaries byte-identical, on x86_64, qemu-aarch64, cxvm and wine (Mach-O compiles with none); the method forms, the zone and after the first statement too. Narrowed from the triage's any-struct test to `Str`, as the filing's direction names: an 8-byte `: P1` call into a `*P1` is the struct's word and keeps its warning, and a `: Q1` call into a `*Str` keeps it too. Rows: `tests/gates/diagnostics/false_warnings_valid_shapes.sh` SP0 (the repro verbatim), SP1; `tests/gates/diagnostics/typed_pointer_warn_sign.sh` axis 16 SC1 – SC4 (still warn); mutations: answering 0 RED SP0 / SP1, no `Str` test RED SC2 and axis 12 z_8b, no whole-value test RED SC4. Filed beside it (placed IN 6.7.16): a `: Str` FIELD into a `*Str` declaration / global, and a `: Str` call into another struct's pointer local. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S3) while measuring D16's `*Str`
assignment, on the lane base (c557ee1b1) and the lane's tree alike: x86_64, aarch64, cx and PE compilers (one front end).
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a false warning; the values are right. Not a security id (the developer's own source).
**Kind:** bug (diagnostics) — a call declared `: Str` returns a header's address, which is what a `*Str` holds
(`str_len(p)` reads it correctly); the same value assigned into a `*Str` LOCAL is quiet, so three sites disagree.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
var GP: *Str = 0;
fn main(): i64 {
    alloc_init();
    var p: *Str = str_from("abcde");
    GP = str_from("xyz");
    var q: *Str = 0;
    q = str_from("ab");
    return str_len(p) * 100 + str_len(GP) * 10 + str_len(q);
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < fw.cyr > fw; echo $?
warning:<source>:6:36: assigning non-pointer to typed pointer      # var p: *Str = str_from(..)
warning:<source>:7:25: assigning non-pointer to typed pointer      # GP = str_from(..)
0
$ ./fw; echo $?
20          # 532 mod 256: 5 / 3 / 2, all right; `q = str_from(..)` (a local) gave no warning
```

## Root cause

The assignment arm for a LOCAL skips the warning when the callee's declared return sid is a struct (`_asg_ret_sid`,
v6.5.28: "a call whose DECLARED return sid is a struct IS a typed pointer"); the global arm (`_tp_warn_g`, parse.cyr's
`_PARSE_STMT_IMPL`) and the `*T` declaration (`_tp_warn_decl`) do not take that exemption for a `: Str` call into a
`*Str`.

## Fix direction

Give the declaration and the global assignment the local's exemption when the call returns exactly the pointee
struct (a `: Str` call into a `*Str`); a `: Q` call into a `*Str` keeps the warning. Rows in a typed-pointer warning gate.
