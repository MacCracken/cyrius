# A vector call's result as a LATER operand of an integer source, or as a compound assignment's right side, compiles and uses its first word — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 by the 6.7.16 receives review fix step (l6716-receives at 6c7ecca74; the
same before the lane, at 41ca7d41c).
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 receives lane; placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; s16 lane, wave 4, unit SZ6) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D100 — Refuse it, wherever it sits in the source (D24–D26's words); `rd(mk2(41, 7) + 1)` into a `*f64v2`, which crashes (139 / cx 221 / PE 5), is refused with it.
**Severity:** Medium — a silent wrong value, a different one per target (no diagnostic).
**Kind:** frontend / the user's decision — refusing these changes what compiles. 6.7.16's D24-D26, 6.7.15's D29 and
6.7.14's D38 cover only a declaration or assignment that a vector call IS or STARTS (`var x: i64 = mk2(41, 7) + 1;`,
`x = (mk2(41, 7) + 1) * 2;` are refused); a vector call in any other operand position, or on the right of `+=`, is not
judged.
**Discovered:** by the 6.7.16 receives review (its `file_as_issue`), while checking D24 / D26's class.

## Reproduction

```sh
cat > /tmp/later.cyr <<'EOF'
include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
fn r(): i64 { var x: i64 = 1 + mk2(41, 7); return x; }
syscall(60, r() % 256);
EOF
build/cycc < /tmp/later.cyr > /tmp/later && chmod +x /tmp/later && /tmp/later; echo $?
# rc 0, no diagnostic; exit 1 on x86_64 / IR=3 / aarch64 (qemu), 42 on cx (cxvm) and PE (wine)
```

Each of these `r` bodies, in the same file, measured on the lane compiler (x86_64 / cx):

| `r`'s body | x86_64, IR=3, aarch64 | cx | PE |
|---|---|---|---|
| `var x: i64 = 1 + mk2(41, 7); return x;` | 1 | 42 | 42 |
| `var x = 0; x = 1 + mk2(41, 7); return x;` | 1 | 42 | |
| `var w = 1 + mk2(41, 7); return w;` (untyped) | 1 | 42 | |
| `var x = 0; x += mk2(41, 7); return x;` | 0 | 41 | 41 |
| `var s: Mv = Mv { 1 }; var x = 0; x += s.m2(); return x;` | 0 | 41 | |
| `var x = 0; x += callptr(&mk2, 41, 7); x += (mk2(41, 7)); return x;` | 0 | 82 | |
| `return take(mk2(41, 7) + 1);` with `fn take(t): i64` (an untyped parameter) | 1 | 42 | |
| `return mk2(41, 7);` from `fn r(): i64`, and `takei(mk2(41, 7))` into `n: i64` | 0 | 82 (both) | |

The vector's lane-0 word (or nothing at all: x86_64's rax after an f64v2 return) is added as an integer; the other
lane is dropped. The same lines with the call FIRST — `var x: i64 = mk2(41, 7) + 1;`, `x = mk2(41, 7) + 1;`, `var w =
mk2(41, 7) + 1;` — are refused ("vector return type does not match the declared type / the assigned variable", the
value-form refusal).

## Root cause

The integer receives judge a vector call only where `_vcall_vt` (`start` 1, src/frontend/parse_decl.cyr) finds it: the
whole source, or its first operand behind any leading parentheses (`_vcv_wpeel`). A call further right in the
expression, the right side of a compound assignment, an argument to an untyped or `i64` parameter and a `: i64` fn's
`return` reach the scalar expression path, which reads the call's result register as an integer.

## The decision needed

Whether a vector call in these positions is refused by name (as D24-D26 refuse the starting call: "there is no
vector `+`", guide § vector returns), and with which words. Refusing changes what compiles; until decided, nothing
is changed.
