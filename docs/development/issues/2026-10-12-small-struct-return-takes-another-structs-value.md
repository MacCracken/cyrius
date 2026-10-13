# A fn returning a struct of 8 B or less returns a local of ANOTHER struct type (its word) with no refusal, and a `*T` local or a `*U` parameter as its ADDRESS — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the merged 6.7.10 tree (`build/cycc` 2,106,040 B, built at the
67b9ef93 merge; HEAD 9c066967 is comment-only) and the aarch64 / cx cross compilers built from it.
`fn f(): S8 { var u: U8; u.u = 3; return u; }` compiles with no diagnostic and returns u's word: exit 3 on x86_64,
aarch64 (qemu) and cx (cxvm). The 9–16 B form is refused by name ("a fn returning the 9-16 byte struct `H` is returned
in two registers, so `return` takes a local of that struct or a call returning it — got `k`"), and so is the >16 B form
("struct-return: identifier type != fn ret_sid"). The installed 6.6.0, 6.6.10, 6.7.0, 6.7.5 and 6.7.9 compilers all
give exit 3. Two more shapes take the same unchecked path. They return the POINTER, not a struct:
`return p;` with `p: *S8` a LOCAL of the fn's own struct, and `return q;` with `q: *U8` a parameter. On x86_64 the
first gives exit 192 (6.7.9: 192, 6.6.17: 112), aarch64 248 and cx 160. These are address bytes, and they vary with
the build. A `q: *S8` PARAMETER copies, as it has since 6.6.17.
**Placement:** 6.7.11 — repair 1, the call-arguments / struct operators lanes (roadmap.md § *6.7.11*) — placed
2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.10 B7 lane. Its `return` arm for the handle line (`_ret_small_ptrp`) records in
its own comment that "this class never compared the type". Re-measured here.
**Severity:** Medium. The source compiles clean on every target. Another struct's local gives a missed refusal: the
caller reads that struct's bytes as the declared one's. The pointer shapes give a silent wrong value: the caller's
`s.v` reads a stack address.
**Affects:** cycc 6.6.0 – the 6.7.10 tree. The other-struct local was measured at 6.6.0, 6.6.10, 6.7.0, 6.7.5, 6.7.9 and
the tree. The `*S8` local was measured at 6.6.17, 6.7.9 and the tree. x86_64, aarch64 (qemu) and cx; the check is
frontend-only (PE not measured).

## Summary

A struct return has three classes. Over 16 B, the struct is copied into a hidden result buffer. 9–16 B is returned in
rax:rdx. 8 B or less is one word in rax. The two wider classes compare the returned value's struct with the fn's.
`return k;` with `k` a local of another struct is refused by name, and so are a call returning another struct, a
by-value parameter of another struct and a `*K` pointer. The 8 B-or-less class has one `return IDENT;` arm (6.6.17's
`*T` parameter, 6.7.10's handle). Every other shape falls to the scalar tail, and the scalar tail loads whatever word
the expression has. Nothing asks which struct that word belongs to.

Measured: x86_64, the tree. `struct S8 { v; }`, `struct U8 { u; }`, `fn f(): S8 { .. }`, read back with
`var s: S8 = f(); return s.v;`.

| `return` in `f` | the tree | the 9–16 B twin (`: H`) |
|---|---|---|
| `var u: U8; u.u = 3; return u;` | **3**, no diagnostic | refused by name |
| `return (u);` | **7** (u.u = 7), no diagnostic | refused by name |
| `fn f(p: U8): S8 { return p; }` (a by-value parameter) | **4**, no diagnostic | refused by name |
| `return GU;` (`var GU = U8 { 0 };`, GU.u = 5) | **5**, no diagnostic | refused by name |
| `return mk();` with `fn mk(): U8` (taken as a tail call) | **6**, no diagnostic | refused by name |
| `var u: U8 = alloc(8); u.u = 9; return u;` (a handle) | 9: U8's bytes, by design (B7-1) | refused by name |
| `var p: *U8 = &u; return p;` | **208**: the address | refused by name |
| `fn f(q: *U8): S8 { return q; }` | **240**: the address | refused by name |
| `var p: *S8 = &u; return p;` (the fn's OWN struct) | **192**: the address | 3: copied through p |
| control: `fn f(q: *S8): S8 { return q; }` | 12: copied (6.6.17) | 3 |
| control: `var u: S8; u.v = 10; return u;` | 10 | — |

An untyped scalar (`var x = 3; return x;`) returns the struct's word. That is consistent with B7's rule for a by-value
argument ("an untyped value is not a pointer here: it is the struct's word"), and it is not part of this issue.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/r8.cyr <<'EOF'
struct S8 { v; }
struct U8 { u; }
fn f(): S8 { var u: U8; u.u = 3; return u; }
fn g(): i64 { var s: S8 = f(); return s.v; }
syscall(60, g());
EOF
cat /tmp/r8.cyr | build/cycc > /tmp/r8 && chmod +x /tmp/r8 && /tmp/r8; echo $?      # 3, no diagnostic
cat > /tmp/r16.cyr <<'EOF'
struct H { a; b; }
struct K { c; d; }
fn f(): H { var k: K; k.c = 3; k.d = 4; return k; }
fn g(): i64 { var s: H = f(); return s.a; }
syscall(60, g());
EOF
cat /tmp/r16.cyr | build/cycc > /tmp/r16; echo $?
# 1: error:<source>:3:48: a fn returning the 9-16 byte struct `H` is returned in two registers, so `return`
#    takes a local of that struct or a call returning it — got `k`
cat > /tmp/rp.cyr <<'EOF'
struct S8 { v; }
fn f(): S8 { var u: S8; u.v = 8; var p: *S8 = &u; return p; }
fn g(): i64 { var s: S8 = f(); return s.v; }
syscall(60, g());
EOF
cat /tmp/rp.cyr | build/cycc > /tmp/rp && chmod +x /tmp/rp && /tmp/rp; echo $?      # an address byte (192), not 8
```

Expected: `/tmp/r8.cyr` refused by name, as `/tmp/r16.cyr` is. `/tmp/rp.cyr` exits 8: the struct `p` points at, as a
`p: *S8` parameter returns it. The cross legs: `cat src/main_aarch64.cyr | build/cycc > /tmp/cc_a64` and run under
`qemu-aarch64`; `cat src/main_cx.cyr | build/cycc > /tmp/cc_cx` and `cat programs/cxvm.cyr | build/cycc > /tmp/cxvm`,
then `/tmp/cxvm < prog.cyx`. They give 3 / 3 for `/tmp/r8.cyr` and 248 / 160 for `/tmp/rp.cyr`.

## Root cause

PARSE_RETURN (`src/frontend/parse_fn.cyr:910`) runs the struct classes in order:

- **Over 16 B:** `_ret_struct_big` (`:1127` → `:1987`) compares the local's struct with the fn's
  (`(0 - srn_lt) != _cur_fn_ret_sid`, `:2009`) and refuses.
- **9–16 B:** `_ret_struct_pair` (`:1138` → `:2085`) takes only a local of that struct, a same-struct method or
  operator, or a call returning it (`_pair_ret_call_ok`, `:5155`). Everything else is refused by `_refuse_pair_return`
  (`:2128` → `:5247`).
- **8 B or less:** the only struct arm is `_ret_small_ptrp` (`:2145`, reached through `_ret_var_forms`, `:1139` →
  `:2181`). It takes `return IDENT;` for a `*T` PARAMETER (`_is_ptr_param`, `:10100`, which answers only for
  `li < _cur_fn_pslots`) or a handle (`_small_hdl`, `src/frontend/parse_decl.cyr:7248`). `_small_hdl` excludes a
  `*T` local (`GLPTRP == 1` → 0). Then, at `:2157`, a struct other than the fn's goes on unless the name is a handle.
  Every shape this arm does not take reaches the scalar tail `_bx_pcmpe_ret` (`src/frontend/parse_expr.cyr:1701`,
  called at `parse_fn.cyr:1345`). That tail is a plain PCMPE plus 6.7.3's bool check. `return mk();` takes the
  tail-call arm before any of them.

So another struct's local, parameter, global, parenthesised name or call loads its word. A `*S8` local is neither a
pointer parameter nor a handle, so PCMPE loads the pointer. A `*U8` parameter passes the pointer-parameter test, but the
type gate at `:2157` sends it to PCMPE, which loads the pointer too.

The argument side has the check this side lacks. Since 6.7.3, `_sarg_byval_small` (`parse_fn.cyr:1789`) reads a
by-value argument of 8 B or less through `_expr_struct_sid`. `_sarg_type_err` (`:1498`) then refuses another struct by
name: `bs1(t)` with `t: T1` into `b: S1`.

## Proposed fix

In the 8 B-or-less class (`_cur_fn_ret_sid > 0`, no stash, not the pair class, `STRUCTSZ <= 8`):

1. **Another struct's value is refused by name**, as the two wider classes and the 6.7.3 argument check refuse it. Read
   the value's static struct with `_expr_struct_sid`, the reader the argument side already uses. Compare it with
   `_cur_fn_ret_sid`. Name the size class in the message ("a fn returning the struct `S8` of 8 bytes or less … takes a
   value of that struct — got `u` (a `U8`)"). The tail-call arm needs the same comparison, `GFRS(callee)` against
   `_cur_fn_ret_sid`, because `return mk();` is diverted before the struct classes.
2. **A `*T` local of the fn's own struct copies through it**, as a `*T` parameter does (`_sptr_param_temp`, 6.6.17).
   That is B7's decision 6: struct copies are size-independent, and `l = p` already copies through a `*T` local.
   `_ret_small_ptrp`'s first gate becomes "a `*T` slot", meaning `GLPTRP(S, li) == 1` for a local or a parameter.
3. **A `*U` pointer to another struct is refused by name**, as `return p;` with `p: *K` is refused in a 9–16 B fn.
4. An untyped scalar stays the struct's word (out of scope, as above).

⚠ Items 1 and 3 make code that compiles today stop compiling, and item 2 changes a value. Ask the user one line at
6.7.11's open; the 6.7.3 argument refusal is the precedent. Also ask whether B7-1's deliberate "a handle of another
struct returns its own struct's bytes" falls under 1. Rows:

- a refusal gate under `tests/gates/frontend/`, beside `struct_arg_type_refused.sh`: each refused shape in the table,
  mutation-proven;
- a `tests/tcyr/crossos/` row for item 2 (`return p;` with `p: *S8` a local gives the struct) on every leg;
- a control row for the `q: *S8` parameter and for the same-struct local.

## Consumer-side workaround

Return a value of the declared struct. Build or copy a `var s: S8;` and `return s;`. For a pointer, copy through it
first: `var c: S8 = p; return c;`. That gives 8 on the tree.
