# `*p = f()` with `f` a multi-value fn and `p: *S` stores the FIRST value as the struct's word, where `G = f()` into a struct is refused by name — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (what `*p = f()` means when `f` returns several values and `p`
points at a struct). Measured 2026-10-14 on the 6.7.11 struct lane (`l6711-struct`, unit S4), x86_64.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 struct lane) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S4), implementing
issues/2026-10-11-deref-store-through-struct-pointer-decision.md (decision (a): `*p = v` copies what `G = v` copies —
"a local, parameter, global, field, call, method or operator result, handle or `*q`"; "an untyped value is stored as
the struct's word at sizeof(S) bytes"). A multi-value call is none of the listed `S` values, and the decision does not
say whether it is "an untyped value": the S4 implementation leaves it the word store it was (now at `sizeof(S)` bytes,
at most 8 — the dereference store's untyped arm), and files the question.
**Severity:** Low — silent: the struct receives the first value as its first word (the second value is dropped); the
named destination refuses the same statement.
**Affects:** every compiler measured (6.7.10's tree and the lane's); every target (frontend).

## Reproduction

```sh
cat > /tmp/mv.cyr <<'X'
struct P2 { x; y; }
var GT2 = P2 { 0, 0 };
fn mv(): (i64, i64) { return (5, 6); }
fn main(): i64 { var p: *P2 = &GT2; *p = mv(); return GT2.x * 10 + GT2.y; }
syscall(60, main());
X
build/cycc < /tmp/mv.cyr > /tmp/mv && chmod +x /tmp/mv && /tmp/mv; echo $?     # 50: x = 5 (the first value), y = 0
```

| statement (`f` returns `(i64, i64)`, `P2` 16 B) | result |
|---|---|
| `*p = mv();` with `p: *P2` | compiles silently; GT2 = {5, 0} (exit 50) |
| `GT2 = mv();` (a named struct value) | refused: *a multi-value call 'mv' is not assigned to struct 'P2' - bind it first: `var a, b = mv(..);`* |
| `q = mv();` with `q: *P2` (a pointer rebind) | compiles with "assigning non-pointer to typed pointer"; q = 5 |

## Root cause

`_mv_asg_src` (parse_fn.cyr) refuses a whole multi-value call into a destination NAME that `_mv_dst_sid` types as a
named struct value or handle. The `*p = v` destination has no name: `_dst_struct` (parse.cyr) runs the assignment
arms with the operand's last name as a placeholder and `_mv_dst_sid` answers 0 under the override (`_agc_ovr_is`), so
the call's first value reaches `_dst_word` as an untyped value.

## Options

- **(a) Refuse by name, as `G = f()` is** — `_mv_dst_sid` answers the override's struct (`0 - _agc_ovr_t`) when
  `_mv_named`. Stops such programs compiling (they stored the first value).
- **(b) Keep it an untyped value** (the S4 behaviour), documented in the guide's *A store through a `*S` copies the
  struct*.

Rows either way: 3 / 8 / 16 / 24 B, a free call and a method returning several values, wrapped, a for step, top level.
