# A `: Str` FIELD into a `*Str` declaration or global warns "assigning non-pointer to typed pointer"; the same into a `*Str` local does not — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64; the
shared front end). Met while fixing issues/2026-10-18-str-call-into-str-pointer-declaration-or-global-warns-typed-pointer.md
(its filed surface is a `: Str` CALL; 478e4f6cd's `_tp_call_pointee` takes calls only, so the field read is outside it).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF4) — never 7.x.
**Severity:** Low — a false warning on valid code that runs right.
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct H { name: Str; n; }
var GZ: *Str = 0;
fn main(): i64 {
    alloc_init();
    var h: H = alloc(16);
    h.name = str_from("nm");
    var f: *Str = h.name;
    GZ = h.name;
    var l: *Str = 0;
    l = h.name;
    return str_len(f) + str_len(GZ) + str_len(l);
}
syscall(60, main());
```

```
warning:<source>:9:25: assigning non-pointer to typed pointer      # var f: *Str = h.name;
warning:<source>:10:16: assigning non-pointer to typed pointer     # GZ = h.name;
```

rc 0, exit 6 (2 + 2 + 2: every read right). `l = h.name;` into a `*Str` local is quiet (6.6.17's `_asg_rhs_sid`: "a
`: Str` field, nested fields walked").

## Root cause

A `: Str` field is a pointer slot (its value is the header's address, what a `*Str` holds). The local assignment arm
exempts it (`_asg_ret_peek` -> `_asg_rhs_steps` returns the field's type), the declaration (`_tp_warn_decl`), the zone
(`_tp_warn_gv`) and the global assignment (`_tp_warn_gasg`) do not: 6.7.16's `_tp_call_pointee` (parse_decl.cyr)
requires the value to end `)` (`_tp_ends_call`). Dropping that requirement for a `: Str` FIELD (keeping it for any other
field type) would give the declaration and the global the local's exemption; rows beside
tests/gates/diagnostics/false_warnings_valid_shapes.sh SP0 / SP1.
