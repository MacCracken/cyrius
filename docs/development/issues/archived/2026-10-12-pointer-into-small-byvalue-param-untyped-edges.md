# A pointer into a by-value struct parameter of 8 B or less is still passed as the pointer word when the pointer typing calls it no pointer: an if-expression of two different steps, an integer on the LEFT of the pointer — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ARG-8, per the user's decision of 2026-10-13 (D37, '(a) Yes, extend 1(b) in `_add_word`'): `n + pb` with a one-byte struct pointer is that pointer everywhere, and an if-expression whose every branch is a pointer passes the struct it points at. pe1 and pe2 exit 111 on x86_64, aarch64, cx and PE (11 / 1); every table row gives 5; the 8 B `S1` form is right; `(1 + pb) - q32` is refused 'pointer difference of pointers with different element sizes', as item 3 said it would be. The if-expression is fixed by a side record, not a new merge word, so its step word, its 'assigning non-pointer to typed pointer' warning and `(if ..) - q` are unchanged. A nonzero narrow `n` in `n + pb2` scales by the element with the narrow-scalar fix of the same release (6.7.11, D15). Rows: `tests/tcyr/crossos/small_struct_pointer_arg.tcyr` (79, the `e_` rows; `small_struct_handle_line.sh` R3 on seven legs and on pi / ecb / ach / cass), `pointer_subscript_checked.sh` DXs1–DXs5. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-12 against the merged 6.7.10 tree (9c066967, `build/cycc` 2,106,040 B)
and the aarch64 / cx cross compilers built from it. 6.7.10's B7-1b (the user's decision 7) passes the struct a pointer
points at into such a parameter. Two shapes get no such copy, and the callee reads the address's bits as the struct.
The first repro below exits 11 where 111 is right, and the second exits 1 where 111 is right. Both give the same
result on x86_64, aarch64 (qemu) and cx (cxvm). With an 8 B struct (`struct S1 { u; }`), the 6.7.9 compiler gets
every row wrong (exit 0): before B7-1b every pointer argument here passed the address. The tree fixes the plain
pointer and leaves these two.
**Placement:** 6.7.11 — repair 1, the call-arguments / struct operators lanes (roadmap.md § *6.7.11*) — placed
2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.10 B7 lane (bite 1b's review, which named both edges); re-measured and widened
here.
**Severity:** Low. A silent wrong value, but only in two uncommon spellings. The plain spellings are right since B7-1b:
`t7(py)`, `t7(&s)`, `t1(pb + n)`, and an if-expression whose branches share a step.
**Affects:** the 6.7.10 tree (B7-1b's tail); every target (frontend state). Before 6.7.10 every pointer here was
passed as the address
([`2026-10-11-typed-pointer-into-small-byvalue-struct-param.md`](2026-10-11-typed-pointer-into-small-byvalue-struct-param.md),
fixed by B7-1b and still in `issues/` until slot close). The one-byte struct pointer (`*B1`) exists only since 6.7.10's
packed narrow fields: a `struct B1 { a: u8; }` was 8 B on 6.7.9.

## Summary

B7-1b decides after the argument's parse, from its pointer-step word (GPSC), whether the argument is a pointer.
Shapes whose word is 0, or whose step-1 word reads as a narrow integer, keep the old behaviour and pass the address as
the struct's bytes.

1. **An if-expression whose branches are pointers of DIFFERENT steps.** The branch words merge to 0 ("no step"). This
   includes two pointers to the SAME struct: `if (c == 1) { py } else { &s }` with `py: *B7` (step 7) and `&s`
   (step 1, an address).
2. **An integer on the left of the pointer.** `+` keeps the LEFT operand's word.
   - With a step-1 struct pointer (`pb: *B1`), ANY integer on the left loses it: an `i64`, a literal `0`, an
     `i32`, a `u8`. 6.7.9's decision 1(b) keeps a one-byte `*T`'s word only when it carries an element kind
     (`*u8` / `*i8`), and a one-byte STRUCT pointer carries none.
   - With a wider pointer (`*B2`, step 2), an `i64` on the left is right (`_int_plus_ptr`). A narrow `i8` / `i16` /
     `i32` / `u8` local on the left still loses it: the local loads with step 1, that step wins, and the step-1 tie
     breaker reads the leftmost term as a narrow integer.

The same `_add_word` gap shows outside arguments: with `pb: *B1` and `q32: *u32`, `(1 + pb) - q32` compiles as a byte
difference. `(pb + 1) - q32` and `(1 + p8) - q32` (`p8: *u8`) are refused "pointer difference of pointers with
different element sizes".

Measured: x86_64, the tree (`t7(b: B7)` reads `b.a`; 5 is right; any other value is address bits).

| argument | result |
|---|---|
| `t7(py)` / `t7(if (c == 1) { py } else { py })` | 5 / 5 |
| `t7(if (c == 1) { py } else { &s })` | **168** |
| `t7(if (c == 1) { &s } else { py })` | **56** |
| `t7(if (c == 1) { py } else { &x })` (`x` an i64) | **152** |
| `t7(if (c == 1) { py } else { pz })` (`pz: *B4`) | **136** |
| `var z: B7 = if (c == 1) { py } else { &s }; z.a` (the receive) | 5 |
| `t1(pb + n)` (`n: i32`) | 5 |
| `t1(m + pb)` (`m` an i64) / `t1(0 + pb)` | **80** / **96** |
| `t1(n + pb)` (`n: i32`) / (`n: u8`) | **16** / **208** |
| `t2(m + pb2)` (`pb2: *B2`) / `t2(n + pb2)` (`n: i32`) | 5 / **112** |

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/pe1.cyr <<'EOF'
struct B7 { a: u32; b: u16; c: u8; }
fn t7(b: B7): i64 { return b.a; }
fn go(c): i64 {
    var s: B7; s.a = 5; s.b = 0; s.c = 0;
    var x = 9;
    var py: *B7 = &s;
    var r = 0;
    if (t7(py) == 5) { r = r + 1; }                                  # control: B7-1b copies through py
    if (t7(if (c == 1) { py } else { py }) == 5) { r = r + 10; }     # same-step branches: copied
    if (t7(if (c == 1) { py } else { &x }) == 5) { r = r + 100; }    # different steps: the address word
    return r;
}
syscall(60, go(1));
EOF
cat /tmp/pe1.cyr | build/cycc > /tmp/pe1 && chmod +x /tmp/pe1 && /tmp/pe1; echo $?    # 11 (111 is right)
cat > /tmp/pe2.cyr <<'EOF'
struct B1 { a: u8; }
fn t1(b: B1): i64 { return b.a; }
fn go(): i64 {
    var s: B1; s.a = 5;
    var pb: *B1 = &s;
    var n: i32 = 0;
    var m = 0;
    var r = 0;
    if (t1(pb + n) == 5) { r = r + 1; }      # pointer on the left: copied through
    if (t1(m + pb) == 5) { r = r + 10; }     # an i64 on the left: the address's low byte
    if (t1(n + pb) == 5) { r = r + 100; }    # an i32 on the left: the address's low byte
    return r;
}
syscall(60, go());
EOF
cat /tmp/pe2.cyr | build/cycc > /tmp/pe2 && chmod +x /tmp/pe2 && /tmp/pe2; echo $?    # 1 (111 is right)
```

aarch64 (`src/main_aarch64.cyr` cross compiler, qemu-aarch64) and cx (`src/main_cx.cyr`, cxvm) give 11 and 1 too.
The 8 B form, which predates 6.7.10, uses `struct S1 { u; }` and `fn bs1(b: S1)`:
`bs1(sp)`, `bs1(if (c == 1) { sp } else { &x })` and `bs1(n + sp)` give 1 on the tree and 0 on 6.7.9.

## Root cause

- The by-value tail is `_hl_byval_arg` (`src/frontend/parse_decl.cyr:7383`). It is reached from
  `_sarg_byval_small` (`src/frontend/parse_fn.cyr:1795`) and from an operator's right operand (`_op_rhs`,
  `parse_fn.cyr:5061`). It asks `_hl_parg` (`parse_decl.cyr:7393`): a word `<= 0` is no pointer; a step `> 1` is a
  pointer; step 1 inside a fn is decided by `_hl_p1` (`:7402`).
- **Edge 1.** An if-expression's step word is the merge of its branches' words, `_ps_merge`
  (`src/frontend/parse_types.cyr:2529`, called at `src/frontend/parse_ctrl.cyr:470`). Two different steps give 0. `&s`
  is step 1 with no kind (v6.5.29), `py` is step 7, so `py`-or-`&s` is "no step" and the address is passed.
- **Edge 2.** `_ptr_add` (`src/frontend/parse_expr.cyr:6802`) writes the result word through `_add_word` (`:6817`).
  The left word wins whenever it is non-zero. A right step-1 word is kept only when its element-kind byte is set,
  which a one-byte struct pointer's is not. So `m + pb` / `0 + pb` (`pb: *B1`) have word 0.
- A narrow local loads with step 1 (`SPSC(S, 1)`, v6.3.34; see
  [`2026-10-11-narrow-scalar-local-and-address-of-carry-byte-pointer-step.md`](2026-10-11-narrow-scalar-local-and-address-of-carry-byte-pointer-step.md),
  6.7.11). So `n + pb` keeps n's step 1, and `_hl_p1` recurses to the leftmost term of the `+` chain (`_hl_addop`).
  It finds `n` there, a narrow local (`_hl_narrow_at`, `:7429`), and answers "a value".
- The pointer-difference case is the same `_add_word` test: `1 + pb` has no step, so `(1 + pb) - q32` is a byte
  difference.

## Proposed fix

1. **The if-expression.** Two branch words that are BOTH pointers (`> 0`) with different steps merge to an address
   word (step 1, no kind, as `&x` is) instead of 0, so `_hl_parg` sees a pointer. `_hl_p1` must then judge the
   branches' values, not the whole token range: today it would read an `i32` condition (`if (c == 1)` with `c: i32`)
   as the narrow term. The alternative is to decide at the merge, per branch. Measure the blast radius of the new
   merge word over `lib/`, `programs/`, `cbt/` and the corpus. It changes the "assigning non-pointer to typed pointer"
   warning and the step checks for `var r: *T = if .. { p } else { &x };` and `(if ..) - q`.
2. **The integer on the left.** `_add_word` keeps a right step-1 word for any typed `*T` of one byte, a one-byte
   struct included. That is decision 1(b)'s rule ("`n + p` with a one-byte `*T` is that pointer"), which predates
   one-byte structs. `_hl_p1` judges the operand that carries the step, not the leftmost term, so a narrow local
   beside a typed pointer no longer decides it. The narrow-scalar issue's fix (a narrow local loads step 0) removes
   the step-1 ambiguity at its source. Do it in the same lane, and `_hl_p1` may then collapse.
3. ⚠ Item 2 makes `(1 + pb) - q32` refused by name, as `(1 + p8) - q32` already is. Say so at 6.7.11's open; it is
   an extension of decision 1(b), not a new rule.
4. Rows:
   - each table row above in `tests/tcyr/crossos/small_struct_pointer_arg.tcyr` (B7-1b's file), on every leg, plus the
     8 B `S1` form;
   - the `(1 + pb) - q32` refusal in `tests/gates/frontend/pointer_subscript_checked.sh`, beside DXc4.

## Consumer-side workaround

Put the pointer on the left (`t1(pb + n)`). For an if-expression, give both branches the same pointer type
(`var ps: *B7 = &s;` and use `ps`), or receive it first: `var z: B7 = if (c == 1) { py } else { &s }; t7(z)` copies.
