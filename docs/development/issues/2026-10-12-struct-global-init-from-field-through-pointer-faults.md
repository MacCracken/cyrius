# A struct global over 8 B initialised from a field reached through a `*T` (`var G: S16 = P.s;`, `= gp().s;`, `= VV.p.s;`) holds the field's first word and SIGSEGVs at the first use — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the merged 6.7.10 tree (9c066967, `build/cycc` 2,106,040 B)
and the cross compilers built from it. The repro compiles with no diagnostic and exits 139 (SIGSEGV) on x86_64 and on
aarch64 (qemu), where 49 is right. On cx it exits 1 ("cxvm: guest address out of range: 4 at pc 56"). `return G;`
gives 4: G's one slot holds the field's first word, and `G.v = 9` writes to address 4. The installed 6.6.20, 6.7.0, 6.7.5
and 6.7.9 compilers give 139 too. 6.6.0 and 6.6.10 refuse the repro's nested literal element (`W { A0, 1 }`:
"unexpected '}'"), so the repro cannot run on them. The same declaration copies correctly in four other spellings:
from an inline global's field (`var G: S16 = A.s;`), inside a fn (`var l: S16 = P.s;`), as a fn-side assignment to an
inline global (`G = P.s;`), and at 8 B or less (`var G: S8 = P.s;`). All give 49.
**Placement:** 6.7.11 — repair 1, the call-arguments / struct operators lanes (roadmap.md § *6.7.11*) — placed
2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.10 B7 lane. B7-1g taught top-level `var G: T = *p;` to copy, and its review met the
field-through-a-pointer form. Re-measured and widened here.
**Severity:** Medium. A crash on every target from a top-level declaration that compiles clean. The fn-side spelling
of the same line works.
**Affects:** cycc 6.6.20 – the 6.7.10 tree (measured 6.6.20, 6.7.0, 6.7.5, 6.7.9 and the tree on x86_64; the tree on
aarch64 and cx; not bisected below 6.6.20, where the repro does not compile). Top-level declarations only, both in
the leading declaration block and after the first statement.

## Summary

Since 6.6.12, a top-level `var G: T = <src>;` with T a struct over 8 B registers G INLINE and byte-copies the source,
when the source is a whole T: a named inline global, or a field chain from one. Any other source leaves G a one-slot
pointer-mode global and stores the source's VALUE in it. For a struct-typed field, that value is the field's first
word. A field chain that starts at a `*T` global (`P.s`), starts at a call (`gp().s`), or passes through a `*T` field
(`VV.p.s`) is not recognised as a whole-struct source. The declaration then compiles, and the first `G.v` reads or
writes through the field's first word.

Measured (x86_64, the tree; `struct S16 { v; w; }`, `struct W { s: S16; n; }`, `var P: *W = &A;`):

| declaration | result |
|---|---|
| `var G: S16 = P.s;` | **139** |
| `var G: S16 = (P.s);` | **139** |
| `var G: S16 = gp().s;` (`fn gp(): *W`) | **139** |
| `var G: S16 = VV.p.s;` (`struct V { p: *W; }`, `var VV = V { &A };`) | **139** |
| `var G: S16 = P.s;` after `syscall(39);`, or after a fn definition | **139** / **139** |
| `var G: S24 = P.s;` (a 24 B field) | **139** |
| control: `var G: S16 = A.s;` | 49 |
| control: `var Q: *S16 = &A0; var G: S16 = *Q;` (B7-1g) | 49 |
| control: in a fn, `var l: S16 = P.s;` | 49 |
| control: in a fn, `G = P.s;` with `var G = S16 { 0, 0 };` | 49 |
| control: `var G: S8 = P.s;` (8 B, one word by value) | 49 |

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/gfp.cyr <<'EOF'
struct S16 { v; w; }
struct W { s: S16; n; }
var A0 = S16 { 4, 0 };
var A = W { A0, 1 };
var P: *W = &A;
var G: S16 = P.s;
fn f(): i64 { G.v = 9; return A.s.v * 10 + G.v; }
syscall(60, f());
EOF
cat /tmp/gfp.cyr | build/cycc > /tmp/gfp && chmod +x /tmp/gfp && /tmp/gfp; echo $?    # 139 (49 is right)
cat src/main_cx.cyr | build/cycc > /tmp/cc_cx && chmod +x /tmp/cc_cx
cat programs/cxvm.cyr | build/cycc > /tmp/cxvm && chmod +x /tmp/cxvm
cat /tmp/gfp.cyr | /tmp/cc_cx > /tmp/gfp.cyx && /tmp/cxvm < /tmp/gfp.cyx; echo $?
# cxvm: guest address out of range: 4 at pc 56 — exit 1
```

The `gp()` form: replace line 6 with `fn gp(): *W { return &A; }` and `var G: S16 = gp().s;`, which also gives 139.

## Root cause

- **The source classifier.** `_gci_src` (`src/frontend/parse_decl.cyr:5566`) is the one predicate that pass 1 and both
  init paths ask. It requires the source's first token to be a global with `GVTYPE > 0` and a recorded layout
  (`GVPM != 0`).
  - A `*W` global's GVTYPE is `0 - step` (`_gv_ptr_type`, `src/frontend/parse_types.cyr:2439`). Its pointee struct
    lives in a side table (`_gv_ptr_sid`, `:2473`) that `_gci_src` never reads, so `P.s` is 0.
  - A call is no global, so `gp().s` is 0.
  - `_gci_chain` (`:5589`) walks only inline struct fields. GETFTYPE of a `*W` field is no struct id; the pointee is
    `_fld_ptr_sid` (`parse_types.cyr:2738`). So `VV.p.s` is 0 at the `p` hop.
- **The declaration block.** Pass 1 (`_gci_inline`, `:5612`, called from PARSE_GVAR_REG at `:4822`) does not register
  G inline, so G is one 8-byte pointer-mode slot. The replay (`_gci_init`, `:5695`, called from EMIT_GVAR_INITS at
  `:5443`) gets 0 from `_gci_src`. `_gz_star_init` (`:7996`) takes only `*p`, so it returns 0 too, and the replay
  falls back to the value store. The value of `P.s` is its first word (4), and that word goes into G's slot.
- **After the first statement.** `_gci_toplevel` (`:5718`) asks the same `_gci_src`. Its fallback `_gci_dx_top`
  (`:5766`) takes only a dereference, `*E`, so the arm's value store does the same.
- **Why the fn-side spelling works.** Inside a fn, `_try_struct_copy_init` (`:5774`) arms the field-source record
  (`_fla_arm` → `_fla_take`, `:1334`). The record follows a `*T` base and a `*T` field hop (`_ptr_hop` /
  `_ptr_park`), so `var l: S16 = P.s;` copies.

## Proposed fix

1. `_gci_src`: a leading global whose GVTYPE is a `*T` step and whose `_gv_ptr_sid` is a struct starts the field
   chain from that struct when `.` follows. `_gci_chain` steps through a `*T` field with `_fld_ptr_sid` when `.`
   follows. A bare `P` (no field) stays as today: the pointer copy, or B7-1g's `*P` for the struct.
2. The copy: `_gci_take_in` already arms `_fla_arm` and parses the chain with PCMPE. At top level a hop parks the
   pointer in a hidden pointer-mode global (`_ptr_park`'s `_HTEMP`). Confirm that `_fsc_src_x1` copies through it,
   byte-exact, for `P.s` and `VV.p.s` alike. If it does not, record the hop the way B7-1g's `_hl_dx_src` parks `*E`.
3. A call base (`gp().s`): pass 1 cannot judge a callee declared below. Classify a call whose fn is already declared
   with a `*T` return, and refuse by name ("… from a call's field at top level: copy it inside a fn") whenever pass 1
   and the replay disagree, as `_gci_below` does for a source declared below. Never fall back to the value store.
4. No language question: 6.6.12 already defines this declaration as a copy ("a field chain whose leaf is that
   struct"), and B7's decision 6 makes struct copies size-independent. This makes the top-level spelling agree with
   the fn-side one.
5. Rows: each 139 row of the table (49 on every leg) beside the 6.6.12 global copy-init rows in
   `tests/tcyr/crossos/struct_field_value_copy.tcyr`, and in `tests/gates/codegen/cx_crossos_rows_run.sh`'s cx leg.

## Consumer-side workaround

Initialise G from an inline source (`var G: S16 = A.s;`). Or declare it with a literal (`var G = S16 { 0, 0 };`) and
assign it inside a fn (`G = P.s;`), which copies.
