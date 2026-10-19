# A declaration-zone `var H: Str = gt;` with gt declared BELOW it is still refused "cannot copy-init", though since 6.7.14 the line binds a handle (no copy) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-5, `395c264e1` — the user's decision D17, 2026-10-18: "Yes: it binds H to gt's header". `_istr_gz` drops its declared-below guard, so the declaration-zone replay stores gt's static address as it does for gt above. The filed repro, refused "4:14: cannot copy-init 'H' from a global declared below it (declare the source first): 'gt'", exits 33 (`H.len = 3` writes gt.len) on x86_64, IR=1, IR=3, DCE, aarch64, cx and PE, and on ecb, ach, pi and cass — as with the two declarations swapped, and as the `*Str` twin already did. Rows: `frontend/inline_str_value.sh` D21c (flipped from the refusal to the repro verbatim, 33, every leg); `crossos/inline_str_value.tcyr` z_below (333); mutation RED 14. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S4) on the lane's tree after the D21 (a)
commit (`6774a66e`), x86_64 / aarch64 / cx / PE compilers alike (tests/gates/frontend/inline_str_value.sh D21c pins it).
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D17 — Yes: it binds H to gt's header.
**Severity:** Low — a refusal (nothing miscompiles), whose reason no longer applies and whose words ("copy-init")
name the wrong operation. Not a security id (the developer's own source).
**Kind:** language (decision) — 6.7.14's D21 (a) (issues/2026-10-15-top-level-str-declaration-from-inline-str-global-
copies.md) makes `var H: Str = gt;` at top level a handle bound to gt's static header. The lane kept the order
refusal of 6.6.12 (`_gci_below`) for a gt declared below H, because accepting it would change what compiles beyond
the decided shape.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var H: Str = gt;
var gt: Str = Str { "abcdefg", 7 };
fn main() { H.len = 3; return f(H) * 10 + gt.len; }
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < sB.cyr > sB; echo $?
error:<source>:4:14: cannot copy-init 'H' from a global declared below it (declare the source first): 'gt'
1
```

With the two declarations swapped it compiles and exits 33 (H.len = 3 writes gt.len — D21 (a)). With the lane's
guard removed (`_istr_gz`'s `_istr_ix > dgv` test, src/frontend/parse_decl.cyr) the repro above compiles and exits
33 too: gt's address is static, so the bind does not need gt's layout in pass 1 — the reason 6.6.12 refuses a COPY
from a source declared below.

## Root cause

`_gci_below` (src/frontend/parse_decl.cyr) refuses a whole struct source pass 1 could not see; 6.7.14's zone arm
(`_istr_gz`) declines a gt registered after H so that refusal still runs.

## The question

Should a zone `var H: Str = gt;` with gt declared below bind (as it would above — the address is static), or stay
refused — and if refused, should the words say "bind" rather than "copy-init"?
