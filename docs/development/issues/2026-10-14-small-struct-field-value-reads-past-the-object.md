# A whole struct-typed FIELD of 3, 5, 6 or 7 bytes used as a value — `take(w.s)`, `return w.s`, `w.s + a`, a top-level `var G: S3 = GW.s;` — is loaded as an 8-byte word: it reads past the object (SIGSEGV when it ends a mapping) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct`, after `cf5838db` and the
assignment-from-dereference bite), x86_64 and aarch64 (a `cycc_aarch64` built from `src/main_aarch64.cyr`, run under
qemu-aarch64): every value row below exits 139, both controls 65.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 struct lane) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S1), while fixing the same over-read for a DEREFERENCE
(issues/archived/2026-10-12-small-struct-dereference-reads-past-the-object.md): the guide's ⚠ note at § *A struct-typed field or
a `*T` dereference is a LEFT operand too* names this case ("a whole field of 3, 5, 6 or 7 bytes is still loaded as an
8-byte word on the way"), but no issue file carried it.
**Severity:** Medium — silent: a SIGSEGV when the object ends a mapping (an `mmap`'d record, a packed array's last
element), otherwise up to 5 foreign bytes in the value's padding. Not a security id: the developer's own source.

## Reproduction

```sh
cat > /tmp/fh.cyr <<'X'
include "lib/syscalls.cyr"
struct S3 { a: i8; b: i8; c: i8; }                    # 3 bytes
struct W { n: i8; s: S3; }                            # 4 bytes: s is the last 3
fn take(s: S3): i64 { return s.a; }
fn S3_add(a: S3, b: S3): S3 { return a; }
fn pe(): *W {                                         # a W whose last byte ends a mapping
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    syscall(SYS_MUNMAP, m + 4096, 4096);
    var w: *W = 0;
    w = m + 4096 - 4;
    w.s.a = 65;
    return w;
}
var GW: *W = 0;
X
row() { { cat /tmp/fh.cyr; printf '%s\n' "$2"; } | build/cycc > /tmp/fh 2>/dev/null \
  && chmod +x /tmp/fh && { /tmp/fh; echo "$1: exit $?"; } }
row "arg      take(w.s)        " 'fn run(): i64 { var w: *W = pe(); return take(w.s); } syscall(SYS_EXIT, run());'
row "return   return w.s       " 'fn rs(w: *W): S3 { return w.s; } fn run(): i64 { var l: S3 = rs(pe()); return l.a; } syscall(SYS_EXIT, run());'
row "operator w.s + w.s        " 'fn run(): i64 { var w: *W = pe(); var l: S3 = w.s + w.s; return l.a; } syscall(SYS_EXIT, run());'
row "global   var G: S3 = GW.s " 'GW = pe(); var G: S3 = GW.s; syscall(SYS_EXIT, G.a);'
row "control  var l: S3 = w.s  " 'fn run(): i64 { var w: *W = pe(); var l: S3 = w.s; return l.a; } syscall(SYS_EXIT, run());'
row "control  l = w.s          " 'fn run(): i64 { var w: *W = pe(); var l: S3 = S3 { 1, 2, 3 }; l = w.s; return l.a; } syscall(SYS_EXIT, run());'
```

Actual (x86_64; aarch64 under qemu the same):

```
arg      take(w.s)        : exit 139
return   return w.s       : exit 139
operator w.s + w.s        : exit 139
global   var G: S3 = GW.s : exit 139
control  var l: S3 = w.s  : exit 65
control  l = w.s          : exit 65
```

Expected: 65 on every row (each reads `'A'`, the field's first byte). The declaration (`_fla_var_receive`) and the
assignment (`_fla_assign`) copy the field byte-exact from its address; every consumer that takes the field's VALUE
reads the word the field load produced.

## Root cause

A whole struct-typed field used as a value is the word `PARSE_FIELD_LOAD`'s leaf load leaves in rax (the struct
"travels as one word" at 8 B or less); for a 3 / 5 / 6 / 7 B struct field that load is 8 bytes from the field's
address — up to 5 bytes past the object. 6.7.11 fixed the same over-read for a DEREFERENCE at the one place it is
loaded (`_deref_read` -> `_deref_small` -> `_hl_pval_ra(S, sid, 1)`: one load at 1 / 2 / 4 B, else a byte copy into
a zeroed temp); the whole-field reads (`_flo_note`'s operand, a by-value argument, `return h.s`, the top-level
`_gci_toplevel` / `_gz_*` value stores of a field source) have no such arm.

## Proposed fix

When the field access is a whole struct-typed field of 3, 5, 6 or 7 bytes used as a value, take its address
(`_flo_addr_ra` / `_fld_addr_ra`) and finish with `_hl_pval_ra(S, sid, 1)` instead of the 8-byte leaf load — as the
dereference does since 6.7.11. Rows: the four above at 3 / 5 / 6 / 7 B (x86_64 + aarch64, a fn and top level), a
padding row (the word's bytes past the field 0), a mutant that restores the word load RED.
