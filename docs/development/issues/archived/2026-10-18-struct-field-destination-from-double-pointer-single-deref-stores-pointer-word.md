# `o.s = *pp` (a struct-typed FIELD destination, pp a `**S`) stores the pointer word into the field's first word, where `o.s = p` copies the struct — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-1, `8c65e6e99` — no decision needed: 6.7.13's D9 (a) makes `*pp` of a `**S` a `*S`, and 6.7.11 copies the struct a `*S` source points at into a struct-typed field. `_fsc_dstar` asks the `**S` twin `_hl_dstar_x(.., 1)` (6.7.15's `_hl_dpp`), as `_asg_dstar` and `_sci_dexpr` do. The filed repro prints 444 (was 004) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): `o.s = *pp` and `GW.s = *pp` copy the struct, as `c.s = p` does — also through a `*W`, a by-value parameter's field, wrapped, a for step, `*GPP`, `*gpp()`, `*w.pp`, `**ppp`, a capture and at top level, at 3 / 8 / 16 / 24 B (byte-exact). Another struct's `*qq` into a field is refused by name, "cannot copy '*qq' into a struct field of a different struct type: 's'" (it compiled); a `*S` field (`o.ps = *pp`) still takes the pointer. Rows: `tests/tcyr/crossos/double_pointer_struct_value.tcyr` wf_* (17; the file 76 / 76 on every leg and on ecb, ach, pi and cass), `tests/gates/codegen/small_struct_handle_line.sh` R16f (the filed repro verbatim, on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE), `tests/gates/frontend/struct_copy_type_checked.sh` R33 / R34 (the refusal); mutation RED 14 + RED 2. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S2), landing
issues/archived/2026-10-17-whole-source-copy-from-double-pointer-single-deref-stores-pointer-word.md (a local, a global, `*q`
and a declaration from `*pp` copy since that fix). Pre-existing: the same output on the lane base (fd2e325af's
build/cycc) and after the fix, on x86_64, aarch64 (qemu) and cx (cxvm). Not that filing's surface (its table names a
local, a global, `*q` and a declaration), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — silent: the field's first word takes the pointer `*pp` reads, the rest is left stale; no
diagnostic. Not a security id (the developer's own source).
**Kind:** bug — the field-destination twin of the filing above. 6.7.11 made a struct-typed field from a `*S` source
copy the struct (`o.s = GP`, `o.s = gp()`, `o.s = w.p` — `_fsc_psrc`; `o.s = p` — `_fsc_name`; `o.s = *p` —
`_fsc_dstar`), and 6.7.13's D9 (a) / 6.7.14 made `*pp` of a `**S` that `*S`; the field arms do not ask for it.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct P { x; y; }
struct W { a; s: P; }
var GW = W { 0, 0, 0 };
fn main(): i64 {
    var s = P { 3, 4 };
    var p: *P = &s;
    var pp: **P = &p;
    var o = W { 0, 0, 0 };
    var c = W { 0, 0, 0 };
    o.s = *pp;
    GW.s = *pp;
    c.s = p;
    fmt_int(o.s.y); fmt_int(GW.s.y); fmt_int(c.s.y);
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < fd.cyr > fd && ./fd
004         # o.s.y 0 and GW.s.y 0 (the pointer went into .s.x); the `*S`-name twin `c.s = p` copies (4). Want 444.
```

aarch64 (qemu) and cx (cxvm) print the same 004.

## Root cause

The struct-typed field destination's source arms (src/frontend/parse_decl.cyr): `_fsc_dstar` copies a whole `* E`
only through `_hl_dstar_t`, whose `**S` twin (`_hl_dstar_x(.., 1)`, 6.7.15) it does not ask for; `_fsc_psrc` types the
source with `_hl_psrc`, which answers 0 for an expression starting with `*`. So `*pp` falls to `_fsc_expr` and the
word it reads is stored.

## Fix direction

`_fsc_dstar` asks `_hl_dstar_x(S, GTI(S), term, 1)` (the twin: `_hl_dx_src` parses the whole `*pp` and parks the
`*S` it reads), as `_asg_dstar` and `_sci_dexpr` do since 6.7.15; another struct refused by name (`_fsc_type_err`).
Rows beside double_pointer_struct_value.tcyr's w_* rows (a local's field, a global's field, top level, 8 / 16 B).
