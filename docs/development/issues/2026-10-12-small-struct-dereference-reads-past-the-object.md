# A dereference `*p` of a struct under 8 bytes is read as a whole word: a global initialised or assigned from it, a local assigned from it, a by-value argument and a `return *p` read past the object (SIGSEGV when it ends a mapping); only a local declaration copies byte-exact — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the merged 6.7.10 tree (`9c066967`, `build/cycc` 2,106,040 B)
on x86_64, and the global row on aarch64 (a `cycc_aarch64` built from `src/main_aarch64.cyr`, run under qemu-aarch64:
the same SIGSEGV). An `S3` (3 bytes) whose last byte ends a mapping, copied through `P: *S3`: every shape below exits
139 except the local declaration `var l: S3 = *P;` (65, byte-exact since 6.7.10). Every size from 1 to 7 bytes faults
in the global initialiser (`*P`, `(*P)`, `*gp()`, in the declaration zone and after it); 8 bytes does not. The
installed 6.7.9 compiler (`~/.cyrius/versions/6.7.9/bin/cycc`) faults on EVERY row, the local declaration included,
and 6.7.0 faults on the global-initialiser and local-declaration rows — this predates 6.7.10 (6.7.10 fixed the local
declaration only).
**Placement:** 6.7.11 — repair 1, the call-arguments / struct operators lanes (roadmap.md § *6.7.11*) — placed
2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, 6.7.10's B7 lane: B7-1d made a dereference of a `*T` a struct value in every spelling, and
copies it byte-exact for a local (`_sci_dexpr`) and for a global over 8 B (`_gci_dx_top`, `_gz_dx_init`), while a
global of 8 B or less is left to the value store, which reads the word `*p` loads.
**Severity:** Medium — silent: no diagnostic; a SIGSEGV when the object ends a mapping (an `mmap`'d record, a packed
array's last element, a page-end buffer), otherwise the bytes after the object are copied into the destination's
padding (visible to `load64(&G)`, a `memeq` / hash over the cell, an 8-byte copy of it). Not a security id: the
developer's own source.
**Affects:** cycc 6.7.0 – 6.7.9 (every shape below on 6.7.9; the global and local-declaration rows on 6.7.0) and the
6.7.10 tree (every shape but the local declaration); measured on x86_64 (every row) and aarch64 (the global row).

## Summary

Since B7-1d the guide's handle line says a dereference of a `*T` — `*p`, `(*p)`, `*(p + 1)`, `*h.p`, `*gp()` — is a
struct VALUE, "copied through the pointer". For a struct over 8 bytes every consumer copies `STRUCTSZ` bytes through
the parked pointer. For one of 8 bytes or less a struct value travels as one word, and that word is whatever
`_deref_read` loaded: 8 bytes from `p`, whatever the struct's size. Only the local declaration was given its own
byte-exact copy (`_sci_dexpr`). Every other consumer of a < 8 B `*p` reads up to 7 bytes past the object:

- a global's initialiser, in the declaration zone and after the first statement, every spelling;
- `G = *p;` into an inline global, `l = *p;` into an inline local;
- `f(*p)` into a by-value `s: S3` parameter; `return *p;` from a fn declared `: S3`.

The compiler already has the byte-exact read for exactly this size class: `_hl_pval_ra` (one 1 / 2 / 4 / 8-byte
load, else a byte copy into a temp — "no byte past the object is read"), used since 6.7.10 for a by-value `self`
(B7-1r, f4d3e430, the same mapping-end SIGSEGV) and, as `_hg_val_ra`, for a small handle global.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/ov_head.cyr <<'X'
include "lib/syscalls.cyr"
struct S3 { a: i8; b: i8; c: i8; }                   # 3 bytes
fn page_end(): *S3 {                                  # an S3 whose last byte ends a mapping
    var m = syscall(9, 0, 8192, 3, 0x22, 0 - 1, 0);  # mmap 2 RW pages (x86_64 numbers)
    syscall(11, m + 4096, 4096);                     # munmap the second
    var p = m + 4096 - 3;
    store8(p, 65); store8(p + 1, 66); store8(p + 2, 67);
    return p;
}
var P: *S3 = 0;
fn gp(): *S3 { return P; }
X
row() { { cat /tmp/ov_head.cyr; printf '%s\n' "$2"; } | build/cycc > /tmp/ov 2>/dev/null \
  && chmod +x /tmp/ov && { /tmp/ov; echo "$1: exit $?"; } }
row "zone    var G: S3 = *Q"     'var Q: *S3 = page_end(); var G: S3 = *Q; syscall(60, G.a);'
row "late    var G: S3 = *P"     'P = page_end(); var G: S3 = *P; syscall(60, G.a);'
row "late    var G: S3 = (*P)"   'P = page_end(); var G: S3 = (*P); syscall(60, G.a);'
row "late    var G: S3 = *gp()"  'P = page_end(); var G: S3 = *gp(); syscall(60, G.a);'
row "late    var G: S3 = *(P+0)" 'P = page_end(); var G: S3 = *(P + 0); syscall(60, G.a);'
row "global  G = *P"             'P = page_end(); var G: S3 = S3 { 1, 2, 3 }; G = *P; syscall(60, G.a);'
row "local   l = *P"             'fn run(): i64 { var l: S3 = S3 { 1, 2, 3 }; l = *P; return l.a; } P = page_end(); syscall(60, run());'
row "arg     f(*P)"              'fn f(s: S3): i64 { return s.a; } P = page_end(); syscall(60, f(*P));'
row "return  return *P"          'fn g(): S3 { return *P; } fn run(): i64 { var l: S3 = g(); return l.a; } P = page_end(); syscall(60, run());'
row "control var l: S3 = *P"     'fn run(): i64 { var l: S3 = *P; return l.a; } P = page_end(); syscall(60, run());'
row "padding load8(&G + 3)"      'var buf[2]; store64(&buf, 0x4847464544434241); P = &buf; var G: S3 = *P; syscall(60, load8(&G + 3));'
```

Actual (6.7.10 tree): exit 139 on the first nine rows, 65 on the control, 68 (`'D'`, the byte after the object) on
the padding row. Expected: 65 on the first ten (each reads `'A'`, the struct's first byte) and 0 on the padding row.
On 6.7.9 the control row is 139 too. With `struct S` of 1, 2, 4, 5, 6 or 7 `i8` fields the global rows fault the same
way; with 8 they exit 65.

## Root cause

`_deref_read` (`src/frontend/parse_expr.cyr:3743-3751`): `_deref_ed` (`:3731`) gives an element only for a NARROW
scalar `*T` (`*u8`..`*u32`, `*i8`..`*i32`, `*f32`); any other operand, a struct pointer included, is `ELOAD64` — 8
bytes. A < 8 B struct value is that word everywhere it is used as a value:

- after the first statement, `_gci_toplevel` (`src/frontend/parse_decl.cyr:5718`, `:5735`) and `_gci_dx_top`
  (`:5766`, `:5770`) return 0 at 8 B or less, so PARSE_VAR's arm stores the word;
- in the declaration zone, `_gz_star_init` (`:7996`, `:8004`) and `_gz_dx_init` (`:8186`, `:8191`) do the same;
- `G = *p` / `l = *p`: `_try_aggregate_copy_assign` (`src/frontend/parse.cyr:3675`) takes only a name source
  (`:3679`), and `_pcmpe_struct_assign` (`:3493`) returns at one slot (`:3520`), so the plain store writes the word;
- `f(*p)` and `return *p` pass the ≤ 8 B struct as its word, the same one.

The local declaration is byte-exact because `_sci_dexpr` (`parse_decl.cyr:5933`) parks the pointer and copies
`STRUCTSZ` bytes (`_agc_copy_bytes`) — the one consumer that never asks `_deref_read` for the value.

## Proposed fix

At the source, once: when `_deref_read`'s operand is a `*T` with T a struct of 8 bytes or less (typed as `_hl_dstar`
types it — `_hl_psid` over the operand's tokens — or from the pointer word if it carries the struct), leave the address
in rax and finish with `_hl_pval_ra(S, sid)` (`parse_decl.cyr:7443`) instead of `ELOAD64`: one zero-extending load at
1 / 2 / 4 / 8 bytes, a byte copy into a temp at 3 / 5 / 6 / 7. Every consumer above then receives a word with no
foreign bytes, and the ≤ 8 B arms of `_gci_toplevel` / `_gz_*_init` can stay value stores. The one visible change
besides the over-read: a < 8 B struct dereference used as an integer (`*p + a`, which the guide says adds the first
words without dispatch; `*p == x`) sees a zero-padded word instead of the bytes after the object — those bytes were
never the struct's. Rows: the eleven above at sizes 1..7 (x86_64 + aarch64, in a fn and at top level, both zones), as
`small_struct_handle_line.sh`'s PS row does for `self`, with a mutant that restores `ELOAD64` RED.

## Consumer-side workaround

Copy through a local declaration first — `var l: S3 = *p;` reads exactly 3 bytes on 6.7.10 — then assign `l` (`G = l;`,
`f(l)`, `return l;` — each measured 65 at the mapping end). On 6.7.9 and earlier no spelling of the dereference is
safe at a mapping end; copy field by field (`G.a = p.a; ...`) or `memcpy(&G, p, sizeof(S3))` (`lib/string.cyr`),
both measured 65 on 6.7.9.
