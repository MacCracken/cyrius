# A field name inside a closure body is taken as a capture of the enclosing local of that name — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 14, l679-crit; CHANGELOG [6.7.9]) The capture pre-scan skips a field name after `.` (not a range's `..`) and a struct literal's `IDENT :` label (`_cl_is_field_name`, `_cl_is_lit_label`): the repro compiles without lib/alloc.cyr and exits 16 on x86_64, aarch64 (qemu) and cx. Gate `frontend/closure_field_names_not_captured.sh` (15 rows on host, cx and aarch64, plus the repro file; mutation-proven). Of 948 tree sources, two compile differently: the repro, and a `.tcyr` whose closure loses a needless env.

**Status:** ✅ **RESOLVED in v6.7.9**. See the banner above and *Resolution* below. It was reproduced on the 6.7.9 lane tip
@ 4f591437 before the fix, refused twice. As filed: 🟡 OPEN — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B), on x86_64 and aarch64 (a cross compiler built from the merged tree). The repro is refused twice with
`a capturing closure needs include "lib/alloc.cyr" for its heap env`. Neither closure reads the enclosing `y`. With
the enclosing local renamed (`var yy = 5;`) the file compiles and exits 16, which is right. With `lib/alloc.cyr`
included it compiles and computes the right value, but each closure becomes a capturing one, with a heap env holding
a copy of `y` it never reads. Same refusal on the 6.7.6 tag, 6.7.0, 6.6.10, 6.6.5 and 6.6.0.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-09 by the 6.7.7 B6 (default and named arguments) review
(`scratchpad/review-b6-spec/repros/preexisting_struct_literal_field_capture.cyr`, the literal-label shape). The `.y`
shape was found while verifying this filing. It predates B6.
**Severity:** Medium — valid source is refused, with a workaround (include `lib/alloc.cyr`, or rename the local).
Beyond that, the closure gets a needless heap env: an allocation per closure value and a by-value copy of the
enclosing local. No wrong value was observed.
**Affects:** cycc ≤ 6.7.6 and the merged 6.7.7 (measured 6.6.0, 6.6.5, 6.6.10, 6.7.0, the 6.7.6 tag, the 6.7.7 tip).

## Summary

Before a closure body is compiled, `_cl_prescan_captures` walks it and records every identifier that names an
enclosing local and is not shadowed. That identifier becomes a capture, which makes the closure "capturing": it needs
`lib/alloc.cyr` and is built with a heap env. The walk already skips three kinds of name: a call name (`IDENT (`),
the contextual `loop`, and a named-argument label (`w3(1, c: n)`, 6.7.7). It does not skip two other identifiers that
are not variable reads:

1. **A struct literal's field label**: `y` in `Pt { x: n, y: 2 }`.
2. **A field name after `.`**: `y` in `p.y`.

Either one, matching an enclosing local's name, is captured.

## Reproduction

`docs/development/issues/repros/2026-10-09-closure-prescan-reads-field-names-as-captures.cyr`:

```cyrius
include "lib/fnptr.cyr"
struct Pt { x; y; }
fn lit(): i64 { var y = 5; var cl = |n| { var p = Pt { x: n, y: 2 }; return p.x + 2; }; return fncall1(cl, 7); }
fn acc(): i64 { var y = 5; var cl = |n| { var p = Pt { n, 2 }; return p.y + 5; }; return fncall1(cl, 7); }
syscall(60, lit() + acc());
```

```sh
cat docs/development/issues/repros/2026-10-09-closure-prescan-reads-field-names-as-captures.cyr | build/cycc > /tmp/fc \
  && chmod +x /tmp/fc && /tmp/fc; echo $?
# actual:   error:<source>:3:87: a capturing closure needs include "lib/alloc.cyr" for its heap env
#           error:<source>:4:81: (the same)
# expected: compiles, exit 16 (9 + 7) — what the file gives with `var yy = 5;` in both fns
```

## Root cause

`_cl_prescan_ident` (`src/frontend/parse_expr.cyr:412`; merged-tree lines), called for every identifier the body walk
(`_cl_prescan_body`, `:326`) meets outside a `var` name:

```cyrius
if (TOKTYP(S, GTI(S) + 1) == 10) { return 0; }   # a call name
if (_TOK_IS_LOOP_AT(S, GTI(S)) == 1) { return 0; }
if (_cl_is_arg_label(S, GTI(S)) == 1) { return 0; }   # 6.7.7: `w3(1, c: n)`'s `c`
if (FINDLOCAL(S, noff) >= 0) { return 0; }
if (_cl_shadow_find(S, noff) >= 0) { return 0; }
var esl = _cl_snap_find(S, noff);
if (esl >= 0) { _cl_cap_add(S, esl); }
```

Nothing tests the token before the name (a `.`), or whether the name is a label inside a struct literal's braces.
The refusal itself is at `:4520`.

## Proposed fix

Two more exemptions in `_cl_prescan_ident`:

- the previous token is `.`, a field access. A method name is already a call name.
- the name is followed by `:` inside a struct literal's `{ }`, the way `_cl_is_arg_label` recognises a label inside
  a call's parentheses.

The label test must not exempt an `IDENT :` that is not a struct-literal label. A type annotation's name already
follows `var` and is shadowed. A `switch` `case` value is the other `IDENT :` spelling, and it stays a read.

Measure with the differential corpus. Every closure that captured only through a field name loses a needless env, so
bytes change by design. The rest should be byte-identical.

Gate: both shapes, a nested-closure form, and a control that really captures `y` and still does. Add a mutation per
exemption.

## Consumer-side workaround

Include `lib/alloc.cyr` and call `alloc_init()` (the result is right, at the cost of an env), or rename the
enclosing local.

## Resolution (6.7.9, the critical lane's bite 14)

- **Two more exemptions in `_cl_prescan_ident`** (parse_expr.cyr), as proposed:
  - `_cl_is_field_name`: the token before the name is a `.` and the one before that is not. A range's `..` lexes as
    two DOT tokens, so `for i in 0..y` still reads `y` (rows K5 and K6). `0..p.y` reads `p` and not `y` (row F).
  - `_cl_is_lit_label`: an `IDENT :` right after a `{` or a `,` whose innermost open bracket is a `{` opened right
    after a struct name (`FINDSTRUCT`) or a generic struct's closing `>` / `>>` / `>>>` (`Box<i64> { v: n, w: 2 }`,
    row G). The innermost-open-bracket walk is now `_cl_open_brk`, shared with 6.7.7's `_cl_is_arg_label`, whose
    behaviour is unchanged.
  - A `case` value follows `case`, and cyrius has no ternary, so no other `IDENT :` stands after a `{` or `,`. The value
    after a label stays a read: `Pt { x: n, y: y }` still captures `y` (rows K1 and K2).
- **Rows**: `tests/gates/frontend/closure_field_names_not_captured.sh` covers the repro (R, plus the file itself), the
  label alone (L), `.y` alone (D), an expression body (E), a field chain `l.a.y` (C), a generic literal (G), a nested
  closure (N) and a range bounded by a field (F). Each row compiles without lib/alloc.cyr. The controls are K1–K7:
  a real capture is still refused without lib/alloc.cyr, and with it the capture is by value (K2 and K4 set `y = 50`
  after the closure is made), a range's bound is the captured local and not a global of that name (K6 gives 21, not
  63), and a captured struct's fields are read alongside a captured `y` (K7). The gate runs on host x86_64, cx (cxvm)
  and aarch64 (qemu). Mutation-proven from scratch trees: the pre-fix src makes 25 of 46 checks red, and so does the
  `.` test dropped. Dropping the label test makes 13 red, dropping the `..` guard 6 (K5 and K6), and dropping the
  generic head 3 (G).
- **Differential**: 948 tree sources were compiled with the pre-fix and the fixed stage-1 compilers: the src
  compilers, every `.tcyr`, programs, benches, fuzz and the filed repros. Two of them differ in stdout, stderr or
  exit code. One is the repro (refused before). The other is `tests/tcyr/crossos/struct_value_codegen.tcyr`, whose
  closure `|x| { var t: P3 = mk3(x); return t.z; }` sat beside a local `z` (a 4-word struct). It no longer copies
  `z` into a heap env, so the binary's bytes change by design. It still passes 146 / 146 on x86_64 and on aarch64 (qemu).
- **Not this filing**: a name the closure body DECLARES without a `var` right before it is still taken as a capture of
  the enclosing local. That covers a `for i in` variable, a local `const k`, and the `b` of `var a, b = two();`. It is
  filed as `2026-10-11-closure-prescan-reads-declared-names-as-captures.md`.
