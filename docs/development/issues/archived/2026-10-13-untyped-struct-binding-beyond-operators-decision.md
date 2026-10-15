# An untyped binding takes a struct-returning OPERATOR's type at every size (decision 12), but not a method chain or an if-expression of 8 B or less, nor a parenthesised 9–16 B operator / method result — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-18, the user's decision D42 (2026-10-13, (a)): decision 12 reaches every whole struct result — an untyped binding of a method chain or an if-expression of 8 B or less, and of a parenthesised 9–16 B operator / method result, is the struct, as the annotated form is; a chain ending in an integer method stays an integer, a scalar annotation keeps the word, an untyped global keeps the word, a whole dyn result in the wrap keeps its refusal. u1 / u2 / u3 give 20 / 7 / 41 (each was refused) on x86_64, aarch64, cx and PE. Rows: `crossos/struct_operator_result_binding.tcyr` (80, `small_struct_handle_line.sh` R8 on seven legs), `small_struct_handle_line.sh` B3 (the three repros verbatim). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN — a decision for the user** (does decision 12 reach these three shapes?). Verified 2026-10-13
against `build/cycc` 2,114,376 B (6.7.10, x86_64): each untyped binding below is refused at its first `.field`
("no struct type in scope for 'c'"), while the same initialiser with an annotation, or at another size, compiles and
gives the right value.
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** Low — loud: valid-looking source is refused by name; no wrong value.
**Affects:** the 6.7.10 tree (measured there only); the inference is frontend-only, so every target.

## Summary

6.7.10's decision 12 (user, 2026-10-12): `var c = a + b;` whose operator returns a struct takes that struct's type at
every size. Three neighbouring untyped initialisers still bind an untyped word:

| initialiser | 8 B or less | 9–16 B | over 16 B |
|---|---|---|---|
| a method chain `a.d().d()` | **refused** (`a.d()` alone: typed) | typed (20) | — |
| an if-expression `if (k == 1) { mk(7) } else { mk(9) }` | **refused** (`var c: S8 = …` gives 7) | refused by rule: a branch over 8 B cannot be a struct value | same |
| a parenthesised operator `(a + b)` / method `(s.m())` | typed (`(a + b)`: 13) | **refused** (`var c: S16 = (a + b);` gives 37) | typed (`(a + b)`: 37) |

The parenthesised free-call twin (`var x = (mk());` at 16 B) is
[`2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md`](2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md) (a).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/u1.cyr <<'EOF'
struct S8 { v; }
fn S8_d(self: *S8): S8 { var r: S8; r.v = self.v * 2; return r; }
fn main(): i64 { var a: S8; a.v = 5; var c = a.d().d(); return c.v; }
syscall(60, main());
EOF
cat > /tmp/u2.cyr <<'EOF'
struct S8 { v; }
fn mk(n): S8 { var r: S8; r.v = n; return r; }
fn main(): i64 { var k = 1; var c = if (k == 1) { mk(7) } else { mk(9) }; return c.v; }
syscall(60, main());
EOF
cat > /tmp/u3.cyr <<'EOF'
struct S16 { v; w; }
fn S16_add(a: *S16, b: *S16): S16 { var r: S16; r.v = a.v + b.v; r.w = a.w + b.w; return r; }
fn S16_m(self: *S16): S16 { var r: S16; r.v = self.v + 1; r.w = 2; return r; }
fn main(): i64 { var a: S16; a.v = 3; a.w = 4; var b: S16; b.v = 10; b.w = 20;
    var c = (a + b); var e = (a.m()); return c.v + c.w + e.v; }
syscall(60, main());
EOF
for f in u1 u2 u3; do build/cycc < /tmp/$f.cyr > /tmp/$f; echo "$f rc=$?"; done
# u1, u2, u3: rc=1 — error: ... no struct type in scope for 'c'; a '.field' access needs its struct declaration
```

Expected, if the type is taken: u1 exits 20, u2 7, u3 41.

## Root cause

`_var_rhs_post` (`src/frontend/parse_decl.cyr:858`) gives an untyped local the struct of `_sc_op_whole` (`:875`), which
answers only for one OPERATOR dispatch spanning the whole initialiser ("A method's or an if-expression's result is not
an operator's", its comment); a single method at 8 B or less is typed through the leading-call `sid0`, a chain is not.
Over 8 B the result's temporary becomes `c` (`_sc_var_receive`, `src/frontend/parse_fn.cyr:4853`), which a whole-initialiser `(` wrap does not reach at
9–16 B (the rax:rdx receive), as the paren-call issue above records for a free call.

## Proposed fix

The user's call, one of:

- **(a) Extend decision 12** to all three: a method chain and an if-expression of 8 B or less, and a wrapped 9–16 B
  operator / method result, take the struct's type as the annotated form does. Untyped bindings that compile today
  do not change; refused ones start compiling.
- **(b) Extend it to some** (e.g. only the parenthesised 9–16 B case, where 6.7.6 made a whole-source wrap
  transparent elsewhere), and refuse the rest by a message that names the missing annotation.
- **(c) Leave them**: an annotation is required; the guide states which untyped initialisers infer a struct.

Rows either way: one per shape and size in a `.tcyr` (typed or refused-by-name), with a mutant RED.

## Consumer-side workaround

Annotate the binding: `var c: S8 = a.d().d();`, `var c: S8 = if (..) { .. } else { .. };`, `var c: S16 = (a + b);`.
