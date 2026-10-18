#!/bin/sh
# Gate: a struct LITERAL is type-checked at its head and at each nested struct field (6.6.12).
#
# THE DEFECTS (measured at 6.6.11, x86_64 Linux):
#
#   R1  A GENERIC struct literal, `Box<Pt> { p, 5 }` / `Box<i64> { 7, 5 }`, failed at every head —
#       PARSE_VAR, PARSE_GVAR_REG's lookahead and the EMIT_GVAR_INITS replay each committed only on
#       `Name {` — with "undefined variable 'Box'". Now `_lit_head` resolves `<args>` to the
#       INSTANCE with `_gen_ann_sid`, the annotation's own resolver, so `var b: Box<Pt> =
#       Box<i64> { .. }` is a mismatch and refused by name, in a fn, in the leading declaration
#       block (which never compared a literal with its annotation at all — `var G: Pt = Q { .. }`
#       compiled) and after the first top-level statement.
#   R1b A nested struct field never took a struct VALUE (`Box { p, 5 }`: "unexpected '}'"). It
#       does now, and a struct value of ANOTHER type is refused by name — a local, a global, a
#       field, a free call, a method — not stored as a word. At top level a 9-16 B call has no frame
#       to land in and is refused by name, like `var G: Pt = mkp();` — and that refusal is the only
#       error: the refused value is the whole nested field, not a leaf the walk descends past.
#
#   D12 (6.7.14, the user's decision D12 (a), 2026-10-16: "No: one named error") A struct literal anywhere but a
#       declaration's whole initializer — an assignment's right side (`G = P { 5 };`, a local, at top level), an
#       argument, an operand, a nested literal element, `return` in every size class, a statement `P { 5 };`,
#       and a generic head `Box<i64> { .. }` in each — was "undefined variable 'P'" (a statement "expected '='")
#       and a cascade of two to five more errors (`return` of a 9-16 B struct: its by-name message, then
#       three). Now ONE error at the name: "a struct literal is an initializer: declare `var t: P = P { .. };`
#       and assign or pass t", the `{ .. }` (and a `.f` / `.m(..)` after it) stepped so nothing cascades, once
#       per token in a generic / #inline replay, under --syntax-only too. And the wrap is transparent:
#       `var q: P = (P { 5, 6 });` (any depth, a fn, either zone) IS the initializer, byte-identical to the
#       unwrapped form; it was "undefined variable 'P'" + "expected ')'" (the run-time values are pinned by
#       tests/tcyr/crossos/struct_literal_wrapped_initializer.tcyr on every target).
#       (issues/archived/2026-10-11-struct-literal-outside-var-initializer-misdiagnosed.md)
#
# Refusal rows are checked on the MESSAGE (and that no binary was written), so a row cannot pass
# on an unrelated syntax error. Acceptance rows are checked against the exit code AND a CONTROL
# that builds the same value field by field.
#
# MUTATION LEDGER (6.6.12, each mutant rebuilt from the fixed tree with the one change):
#   base 6.6.11 build/cycc                          -> RED, 19 of 20: R1-R3/R10 "undefined variable
#                                                      'GBx'", R4-R9 R5c "unexpected '}'", R5b R5d
#                                                      a refusal then "unexpected '}'", R5e
#                                                      "undefined variable 'GBx'", R12 compiled,
#                                                      every acceptance X. (R11, the non-generic
#                                                      head, was already compared by 6.6.5's
#                                                      PARSE_VAR check; it pins the shared helper.)
#   `_lit_ann_check` returns 0                      -> RED R1 R2 R3 R11 R12
#   `_lit_head` returns 0 on `<`                    -> RED R1 R2 R3 R10 A1 A2 A3
#   `_spi_nested` skips its type test (descends)    -> RED R4 R6 R7 R8 R9 R10
#   `_spi_call` never refuses at top level          -> RED R5 R5e
# (6.6.12 review) A top-level refusal was followed by an invented "unexpected '}'": the refused
# value was carried as a scalar LEAF and the walk descended into the nested field, one value short.
#   `_spi_call` returns 2 after a refusal (was 4)   -> RED R5 R5b R5e
#   `_spi_expr`'s `t == -1` returns 2 (was 4)       -> RED R5c
#   `_spi_refused` returns 0                        -> RED R5d
#   6.6.12 B02 as first committed (d00d0d1c)        -> RED R5 R5b R5c R5d R5e
# (The LAYOUT half of the fix — real offsets, recursion — is pinned by the crossos tcyrs
# struct_field_value_copy.tcyr and generic_struct_inference.tcyr, not here.)
#   real tree                                       -> GREEN
# (6.7.14, D12; each mutant built from the fixed tree with the one change)
#   base: the 6.7.14 frontend lane before it        -> RED, 33 of 40 D12 rows: every S row but the two
#     (cb75b8b7)                                       controls S17 S22 (the old "undefined variable 'P'"
#                                                      / "expected '='" + its cascade), W1-W7 ("undefined
#                                                      variable 'P'", "expected ')'"); green: S17 S22, the
#                                                      guide's shapes C1-C3 and X (the tree's own cross
#                                                      compilers)
#   `_slit_stray` returns 0 (the factor's arm off)  -> RED S1-S7 S9-S16 S18-S20 (S8 is `_slit_ret`'s,
#                                                      S21 `_slit_stmt`'s)
#   `_slit_wrap_k` returns 0 (no wrap)              -> RED W1-W7
#   `_refuse_pair_return` without its `_slit_at`    -> RED S6 S12b S20 (the 9-16 B message first)
#   `_slit_ret` returns -1                          -> RED S8 (the > 16 B message + "unexpected ';'")
#   `_slit_tail` returns at once                    -> RED S11 ("expected ';', got '.'" after it)
#   `_slit_err` without `_tn_once`                  -> RED S14 S15 (one error per instance / replay)
#   `_slit_whole` returns 0                         -> RED S5 S5b S5d (the walk carries it as a first leaf:
#                                                      "unexpected '}'")
#   `_slit_open` takes no `<..>` (`P {` only)       -> RED S20 S21 (the generic head: "undefined variable
#                                                      'Box'" + four)
#   `_slit_stmt` returns 0                          -> RED S21 ("expected '=', got '{'" + three)
# (6.7.15, the unclosed wrap; each mutant built from the fixed tree with the one change, measured)
#   `_slit_open_wrap` returns 0 (the 6.7.14 arm)    -> RED WU1-WU6b (the initializer rule first, then the
#                                                      `)`); green: the controls WU7 WU8
#   `_slit_open_wrap` without its `;` test          -> RED WU7 (the operand's literal refusal dropped)
#   `_slit_decl_eq` always 1 (any `=`)              -> RED WU8 (the assignment's literal refusal dropped)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

ML="struct literal type does not match the declared type of this variable"
MF="into a struct field of a different struct type"
MT="a struct result needs storage in a fn's frame"
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 expected message  $3 source  [$4 = only: it must be the ONE error]
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    nerr=$(grep -c '^error' "$D/r.err" 2>/dev/null || true)
    if grep -q "$2" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-40s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
        elif [ "${4:-}" = only ] && [ "$nerr" != 1 ]; then
            printf '  FAIL: %-40s refused, then %s invented error(s): %s\n' "$1" "$((nerr-1))" \
                "$(grep '^error' "$D/r.err" | sed -n 2p)"
            fail=$((fail+1))
        else
            printf '  ok(refused): %-34s\n' "$1"; pass=$((pass+1))
        fi
    else
        printf '  FAIL: %-40s not refused (rc=%s, first line: %s)\n' \
            "$1" "$rc" "$(grep -v '^note' "$D/r.err" 2>/dev/null | head -1 || echo '(no output)')"
        fail=$((fail+1))
    fi
}

_run() {  # $1 source-file -> echoes the exit code, or X when nothing was emitted
    cat "$1" | "$CC" > "$D/a.bin" 2>"$D/a.err" || true
    if [ -s "$D/a.bin" ]; then
        chmod +x "$D/a.bin"
        r=0
        ( ulimit -c 0; timeout 60 "$D/a.bin" ) >/dev/null 2>&1 || r=$?
        echo "$r"
    else
        echo "X"
    fi
}

accept() {  # $1 label  $2 source  $3 expected exit  $4 field-by-field control source
    naccept=$((naccept+1))
    printf '%s' "$2" > "$D/a1.cyr"
    got=$(_run "$D/a1.cyr")
    printf '%s' "$4" > "$D/a2.cyr"
    ctl=$(_run "$D/a2.cyr")
    if [ "$ctl" != "$3" ]; then
        printf '  FAIL: %-40s CONTROL gave %s, want %s — the expectation is wrong\n' "$1" "$ctl" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$got" = "$3" ]; then
        printf '  ok(accepted): %-33s exit=%s (control %s)\n' "$1" "$got" "$ctl"; pass=$((pass+1))
    else
        printf '  FAIL: %-40s exit=%s, want %s (control %s)\n' "$1" "$got" "$3" "$ctl"
        fail=$((fail+1))
    fi
}

T='struct Pt { x; y; }
struct Q { a; b; c; }
struct Box { v: Pt; n; }
struct Big { a; b; c; }
struct BB { k; w: Big; }
struct BQ { k; q: Q; }
struct GBx<T> { v: T; n; }
fn mkpt(a): Pt { var p: Pt; p.x = a; p.y = a + 1; return p; }
fn mkq(a): Q { var p: Q; p.a = a; p.b = a; p.c = a; return p; }
impl Q { fn tw(self): Q { var r: Q; r.a = 1; r.b = 2; r.c = 3; return r; } }
'

# ── R1: the literal head against its annotation ──────────────────────────────────────────────────
refuse "R1 fn: GBx<Pt> = GBx<i64>{..}" "$ML" "$T"'fn f(): i64 { var r: GBx<Pt> = GBx<i64> { 1, 2 }; return r.n; }
syscall(60, f());
'
refuse "R2 lead: GBx<Pt> = GBx<i64>{..}" "$ML" "$T"'var G: GBx<Pt> = GBx<i64> { 1, 2 };
syscall(60, G.n);
'
refuse "R3 after a stmt: GBx<Pt> = GBx<i64>{..}" "$ML" "$T"'var z = 1;
syscall(60, z - 1);
var G: GBx<Pt> = GBx<i64> { 1, 2 };
syscall(60, G.n);
'
refuse "R11 fn: GBx<Pt> = GBx{..} (the base)" "$ML" "$T"'fn f(): i64 { var r: GBx<Pt> = GBx { 1, 2, 3 }; return r.n; }
syscall(60, f());
'
refuse "R12 lead: var G: Pt = Q{..}" "$ML" "$T"'var G: Pt = Q { 1, 2, 3 };
syscall(60, G.x);
'

# ── R1b: a struct value of another type for a nested struct field ─────────────────────────────────
refuse "R4 a local Q into Box.v" "$MF" "$T"'fn f(): i64 { var q: Q; q.a = 1; var b = Box { q, 5 }; return b.n; }
syscall(60, f());
'
refuse "R6 a global Q into Box.v" "$MF" "$T"'var GQ = Q { 1, 2, 3 };
var G = Box { GQ, 5 };
syscall(60, G.n);
'
refuse "R7 a method's Q into Box.v" "$MF" "$T"'fn f(): i64 { var q: Q; var b = Box { q.tw(), 5 }; return b.n; }
syscall(60, f());
'
refuse "R8 a Q field into Box.v" "$MF" "$T"'fn f(): i64 { var bq: BQ; bq.k = 1; var b = Box { bq.q, 5 }; return b.n; }
syscall(60, f());
'
refuse "R9 a call's Q into Box.v" "$MF" "$T"'fn f(): i64 { var b = Box { mkq(1), 5 }; return b.n; }
syscall(60, f());
'
refuse "R10 a generic literal: GBx<Pt>{q, 1}" "$MF" "$T"'fn f(): i64 { var q: Q; var b = GBx<Pt> { q, 1 }; return b.n; }
syscall(60, f());
'
# The top-level refusal is the ONLY error: the refused value is taken as the whole nested field, not
# descended into (which reported the values it was then short as "unexpected '}'").
T5="$T"'fn mkbig(a): Big { var p: Big; p.a = a; p.b = a + 1; p.c = a + 2; return p; }
impl Pt { fn tw(self): Pt { var r: Pt; r.x = 1; r.y = 2; return r; } }
impl Big { fn tw(self): Big { var r: Big; r.a = 1; return r; } }
var P0 = Pt { 1, 2 };
var B0 = Big { 1, 2, 3 };
'
refuse "R5 top level: Box { mkpt(1), 5 }" "$MT" "$T5"'var G = Box { mkpt(1), 5 };
syscall(60, G.n);
' only
refuse "R5b top level, > 16 B: BB { 9, mkbig(1) }" "$MT" "$T5"'var G = BB { 9, mkbig(1) };
syscall(60, G.k);
' only
refuse "R5c top level, a method: Box { P0.tw(), 5 }" "$MT" "$T5"'var G = Box { P0.tw(), 5 };
syscall(60, G.n);
' only
refuse "R5d top level, > 16 B method: BB { 9, B0.tw() }" "$MT" "$T5"'var G = BB { 9, B0.tw() };
syscall(60, G.k);
' only
refuse "R5e after a stmt: GBx<Pt> { mkpt(1), 5 }" "$MT" "$T5"'var z = 1;
syscall(60, z - 1);
var G = GBx<Pt> { mkpt(1), 5 };
syscall(60, G.n);
' only

# ── acceptance: the same shapes with the right types ─────────────────────────────────────────────
accept "A1 fn: var b: GBx<Pt> = GBx<Pt>{p, 5}" "$T"'fn f(): i64 { var p: Pt; p.x = 1; p.y = 2; var b: GBx<Pt> = GBx<Pt> { p, 5 }; return b.n + b.v.x * 10 + b.v.y * 100; }
syscall(60, f());
' 215 "$T"'fn f(): i64 { var b: GBx<Pt>; b.v.x = 1; b.v.y = 2; b.n = 5; return b.n + b.v.x * 10 + b.v.y * 100; }
syscall(60, f());
'
accept "A2 lead: var G: GBx<Pt> = GBx<Pt>{1, 2, 5}" "$T"'var G: GBx<Pt> = GBx<Pt> { 1, 2, 5 };
syscall(60, G.n + G.v.x * 10 + G.v.y * 100);
' 215 "$T"'fn f(): i64 { var b: GBx<Pt>; b.v.x = 1; b.v.y = 2; b.n = 5; return b.n + b.v.x * 10 + b.v.y * 100; }
syscall(60, f());
'
accept "A3 after a stmt: GBx<i64>{7, 5}" "$T"'var z = 0;
syscall(1, 1, "", z);
var G = GBx<i64> { 7, 5 };
syscall(60, G.v + G.n * 10);
' 57 "$T"'fn f(): i64 { var b: GBx<i64>; b.v = 7; b.n = 5; return b.v + b.n * 10; }
syscall(60, f());
'
accept "A4 fn: Box { mkpt(2), 5 }" "$T"'fn f(): i64 { var b = Box { mkpt(2), 5 }; return b.n + b.v.x * 10 + b.v.y * 20; }
syscall(60, f());
' 85 "$T"'fn f(): i64 { var b: Box; b.v.x = 2; b.v.y = 3; b.n = 5; return b.n + b.v.x * 10 + b.v.y * 20; }
syscall(60, f());
'

# ── D12 (6.7.14): a struct literal outside an initializer is ONE named error ────────────────────────
# exact1 LABEL SOURCE EXPECTED-ERROR-LINES [compiler-args]: the compile refuses (no binary) and its `error`
# lines are EXACTLY the expected ones (a `warning` line counts too: none may be added).
MS='a struct literal is an initializer: declare `var t: P = P { .. };` and assign or pass t'
exact1() {
    printf '%s' "$2" > "$D/e.cyr"
    rc=0
    cat "$D/e.cyr" | "$CC" ${4:-} > "$D/e.bin" 2>"$D/e.err" || rc=$?
    nrefuse=$((nrefuse+1))
    grep -E '^(error|warning)' "$D/e.err" > "$D/e.got" || true
    printf '%s\n' "$3" > "$D/e.want"
    if [ "$rc" = 0 ] && [ -s "$D/e.bin" ] && [ "${4:-}" != --syntax-only ]; then
        printf '  FAIL: %-40s compiled (rc 0)\n' "$1"; fail=$((fail+1))
    elif [ "$rc" = 0 ]; then
        printf '  FAIL: %-40s rc 0\n' "$1"; fail=$((fail+1))
    elif cmp -s "$D/e.got" "$D/e.want"; then
        printf '  ok(one error): %-32s\n' "$1"; pass=$((pass+1))
    else
        printf '  FAIL: %-40s got:\n' "$1"; sed 's/^/        /' "$D/e.got"
        printf '        want:\n'; sed 's/^/        /' "$D/e.want"
        fail=$((fail+1))
    fi
}
# same LABEL SRC-A SRC-B: both compile and the binaries are byte-identical (the wrap is transparent).
same() {
    naccept=$((naccept+1))
    printf '%s' "$2" > "$D/s1.cyr"; printf '%s' "$3" > "$D/s2.cyr"
    r1=0; cat "$D/s1.cyr" | "$CC" > "$D/s1.bin" 2>"$D/s1.err" || r1=$?
    r2=0; cat "$D/s2.cyr" | "$CC" > "$D/s2.bin" 2>"$D/s2.err" || r2=$?
    if [ "$r1" != 0 ] || [ "$r2" != 0 ] || [ ! -s "$D/s1.bin" ]; then
        printf '  FAIL: %-40s compile rc %s / %s: %s\n' "$1" "$r1" "$r2" "$(grep -m1 '^error' "$D/s1.err" "$D/s2.err" | head -1)"
        fail=$((fail+1))
    elif cmp -s "$D/s1.bin" "$D/s2.bin"; then
        printf '  ok(identical): %-32s\n' "$1"; pass=$((pass+1))
    else
        printf '  FAIL: %-40s binaries differ\n' "$1"; fail=$((fail+1))
    fi
}

# S1 — the filed repro, verbatim.
exact1 "S1 filed repro: G = P { 5 };" 'struct P { a; }
var G: P = P { 1 };
fn run(): i64 { G = P { 5 }; return 0; }
var r = run();
syscall(60, G.a);
' "error:<source>:3:21: $MS"
P2='struct P { a; b; }
struct W { p: P; }
struct W2 { p: P; n; }
struct B3 { a; b; c; }
fn f(p: P): i64 { return p.a; }
fn g(x): i64 { return x; }
'
exact1 "S2 a local: l = P { 5, 6 };" "$P2"'fn run(): i64 { var l: P = P { 1, 2 }; l = P { 5, 6 }; return l.a; }
syscall(60, run());
' "error:<source>:7:44: $MS"
exact1 "S3 a by-value argument: f(P { 5, 6 })" "$P2"'fn run(): i64 { return f(P { 5, 6 }); }
syscall(60, run());
' "error:<source>:7:26: $MS"
exact1 "S3b an untyped argument: g(P { 5, 6 })" "$P2"'fn run(): i64 { return g(P { 5, 6 }); }
syscall(60, run());
' "error:<source>:7:26: $MS"
exact1 "S4 top level, after a statement" "$P2"'var G: P = P { 1, 2 };
var z = 1;
z = 2;
G = P { 5, 6 };
syscall(60, G.a + z);
' "error:<source>:10:5: $MS"
exact1 "S4b top level, the first statement" "$P2"'var G: P = P { 1, 2 };
G = P { 5, 6 };
syscall(60, G.a);
' "error:<source>:8:5: $MS"
exact1 "S5 a nested literal element: W { P { 2 } }" "$P2"'fn run(): i64 { var w: W = W { P { 2, 3 } }; return w.p.a; }
syscall(60, run());
' "error:<source>:7:32: $MS"
exact1 "S5c a scalar leaf's element: B3 { P { 1, 2 }, 3, 4 }" "$P2"'fn run(): i64 { var b: B3 = B3 { P { 1, 2 }, 3, 4 }; return b.b; }
syscall(60, run());
' "error:<source>:7:34: $MS"
exact1 "S5d a wrapped nested element: W { (P { 2, 3 }) }" "$P2"'fn run(): i64 { var w: W = W { (P { 2, 3 }) }; return w.p.a; }
syscall(60, run());
' "error:<source>:7:33: $MS"
exact1 "S5b a nested element, then a leaf" "$P2"'fn run(): i64 { var w: W2 = W2 { P { 2, 3 }, 4 }; return w.n; }
syscall(60, run());
' "error:<source>:7:34: $MS"
exact1 "S6 return, a 9-16 B struct" "$P2"'fn mk(): P { return P { 5, 6 }; }
fn run(): i64 { var q: P = mk(); return q.a; }
syscall(60, run());
' "error:<source>:7:21: $MS"
exact1 "S7 return, an 8 B struct" 'struct P { a; }
fn mk(): P { return P { 5 }; }
fn run(): i64 { var q: P = mk(); return q.a; }
syscall(60, run());
' "error:<source>:2:21: $MS"
exact1 "S8 return, a > 16 B struct" 'struct P { a; b; c; }
fn mk(): P { return P { 5, 6, 7 }; }
fn run(): i64 { var q: P = mk(); return q.a; }
syscall(60, run());
' "error:<source>:2:21: $MS"
exact1 "S9 an operand: 1 + P { .. }" "$P2"'fn run(): i64 { var x = 1 + P { 5, 6 }; return x; }
syscall(60, run());
' "error:<source>:7:29: $MS"
exact1 "S10 an operand in a condition" "$P2"'fn run(): i64 { if (P { 1, 2 } == 0) { return 1; } return 2; }
syscall(60, run());
' "error:<source>:7:21: $MS"
exact1 "S11 a selector after it: P { 5 }.a" "$P2"'fn run(): i64 { var y = 0; y = P { 5, 6 }.a; return y; }
syscall(60, run());
' "error:<source>:7:32: $MS"
exact1 "S12 a wrap is no initializer here: l = (..)" "$P2"'fn run(): i64 { var l: P = P { 1, 2 }; l = (P { 5, 6 }); return l.a; }
syscall(60, run());
' "error:<source>:7:45: $MS"
exact1 "S12b f((P { .. })), return (P { .. })" "$P2"'fn mk(): P { return (P { 5, 6 }); }
fn run(): i64 { return f((P { 5, 6 })); }
syscall(60, run());
' "error:<source>:7:22: $MS
error:<source>:8:27: $MS"
exact1 "S13 two statements: each its own error" "$P2"'fn run(): i64 { var l: P = P { 1, 2 }; l = P { 5, 6 }; var m: P = P { 3, 4 }; m = P { 7, 8 }; return l.a; }
syscall(60, run());
' "error:<source>:7:44: $MS
error:<source>:7:83: $MS"
exact1 "S14 a generic body: once, 3 instances" "$P2"'var G: P = P { 1, 2 };
fn gg<T>(x: T): i64 { G = P { 5, 6 }; return 0; }
fn run(): i64 { gg<i32>(1); gg<i64>(2); gg(3); return 0; }
syscall(60, run());
' "error:<source>:8:27: $MS"
exact1 "S15 an #inline body: once, 2 calls" "$P2"'var G: P = P { 1, 2 };
#inline
fn il(x): i64 { G = P { 5, 6 }; return x; }
fn run(): i64 { il(1); il(2); return 0; }
syscall(60, run());
' "error:<source>:9:21: $MS"
exact1 "S16 --syntax-only: the filed repro" 'struct P { a; }
var G: P = P { 1 };
fn run(): i64 { G = P { 5 }; return 0; }
var r = run();
syscall(60, G.a);
' "error:<source>:3:21: $MS" --syntax-only
# S17 — a name that is no struct keeps its own error (the arm needs a declared struct).
refuse "S17 control: an undefined name before {" "error:<source>:1:34: undefined variable 'Q'" 'fn run(): i64 { var x = 0; x = Q { 5 }; return x; }
syscall(60, run());
'
# S18 — the struct's own name is printed.
exact1 "S18 another struct's name: Rect" 'struct Rect { x; y; }
fn run(): i64 { var r: Rect = Rect { 1, 2 }; r = Rect { 3, 4 }; return r.x; }
syscall(60, run());
' 'error:<source>:2:50: a struct literal is an initializer: declare `var t: Rect = Rect { .. };` and assign or pass t'
# S19 — an argument of a builtin.
exact1 "S19 a builtin argument: syscall(60, P{..})" "$P2"'syscall(60, P { 5, 6 });
' "error:<source>:7:13: $MS"

# S20 — a generic literal `Box<i64> { .. }` is a struct literal too: named as written.
exact1 "S20 generic: return, assign, argument" 'struct Box<T> { v: T; w; }
fn f(b: Box<i64>): i64 { return b.v; }
fn mk(): Box<i64> { return Box<i64> { 1, 2 }; }
fn run(): i64 { var q = Box<i64> { 1, 2 }; q = Box<i64> { 3, 4 }; return f(Box<Vec<i64>> { 5, 6 }); }
syscall(60, run());
' 'error:<source>:3:28: a struct literal is an initializer: declare `var t: Box<i64> = Box<i64> { .. };` and assign or pass t
error:<source>:4:48: a struct literal is an initializer: declare `var t: Box<i64> = Box<i64> { .. };` and assign or pass t
error:<source>:4:76: a struct literal is an initializer: declare `var t: Box<Vec<i64>> = Box<Vec<i64>> { .. };` and assign or pass t'
# S21 — a statement `P { .. };` (a fn, top level, a generic head): one error each, in sync.
exact1 "S21 a statement: P { 5 }; Box<i64> { 1, 2 };" 'struct P { a; }
struct Box<T> { v: T; w; }
fn run(): i64 { P { 5 }; Box<i64> { 1, 2 }; return 0; }
P { 6 };
syscall(60, run());
' "error:<source>:3:17: $MS
"'error:<source>:3:26: a struct literal is an initializer: declare `var t: Box<i64> = Box<i64> { .. };` and assign or pass t'"
error:<source>:4:1: $MS"
# S22 — a local named like the struct keeps its statement's syntax error.
exact1 "S22 control: a local P, then P { 5 };" 'struct P { a; }
fn run(): i64 { var P = 3; P { 5 }; return 0; }
syscall(60, run());
' "error:<source>:2:30: expected '=', got '{'"

# W — the wrap is transparent: `( .. )` around the whole literal initializer IS the initializer.
WH='struct P { a; b; }
struct Bx<T> { v: T; w; }
'
same "W1 fn: var q: P = (P { 5, 6 });" "$WH"'fn run(): i64 { var q: P = (P { 5, 6 }); return q.a; }
syscall(60, run());
' "$WH"'fn run(): i64 { var q: P = P { 5, 6 }; return q.a; }
syscall(60, run());
'
same "W2 the declaration zone" "$WH"'var G: P = (P { 5, 6 });
syscall(60, G.a + G.b);
' "$WH"'var G: P = P { 5, 6 };
syscall(60, G.a + G.b);
'
same "W3 after a statement" "$WH"'var z = 1;
z = 2;
var G: P = (P { 5, 6 });
syscall(60, G.b + z);
' "$WH"'var z = 1;
z = 2;
var G: P = P { 5, 6 };
syscall(60, G.b + z);
'
same "W4 a double wrap, unannotated" "$WH"'fn run(): i64 { var q = ((P { 5, 6 })); return q.b; }
syscall(60, run());
' "$WH"'fn run(): i64 { var q = P { 5, 6 }; return q.b; }
syscall(60, run());
'
same "W5 a generic literal" "$WH"'var G = (Bx<i64> { 7, 8 });
fn run(): i64 { var h = (Bx<i64> { 1, 2 }); return h.w + G.v; }
syscall(60, run());
' "$WH"'var G = Bx<i64> { 7, 8 };
fn run(): i64 { var h = Bx<i64> { 1, 2 }; return h.w + G.v; }
syscall(60, run());
'
same "W6 a named literal" "$WH"'var G: P = (P { b: 6, a: 5 });
fn run(): i64 { var q = ((P { b: 2, a: 1 })); return q.b + G.a; }
syscall(60, run());
' "$WH"'var G: P = P { b: 6, a: 5 };
fn run(): i64 { var q = P { b: 2, a: 1 }; return q.b + G.a; }
syscall(60, run());
'
same "W7 a kernel build (the baked image)" "$WH"'kernel;
var G: P = (P { 5, 6 });
fn kmain(): i64 { return G.a; }
var r = kmain();
' "$WH"'kernel;
var G: P = P { 5, 6 };
fn kmain(): i64 { return G.a; }
var r = kmain();
'

# WU (6.7.15) — an UNCLOSED wrap around a declaration's whole literal initializer (`var t: P = (P { 5, 6 };`) is ONE
# error, the missing `)`: the literal is the initializer the wrap was meant to hold, so the initializer rule is not
# reported first. It was "a struct literal is an initializer: ..." at the name, then "expected ')', got ';'"
# (issues/2026-10-17-unclosed-wrap-around-struct-literal-initializer-names-the-literal-rule.md). Keyed on the
# declaration's `= (` and the `;` after the literal: an operand (WU7) and an assignment (WU8) keep both errors.
exact1 "WU1 filed repro: var t: P = (P { 5, 6 };" 'struct P { a; b; }
fn run(): i64 { var t: P = (P { 5, 6 }; return t.a; }
syscall(60, run());
' "error:<source>:2:39: expected ')', got ';'"
exact1 "WU2 the declaration zone" "$WH"'var G: P = (P { 5, 6 };
syscall(60, G.a);
' "error:<source>:3:23: expected ')', got ';'"
exact1 "WU3 after a statement" "$WH"'var z = 1;
z = 2;
var G: P = (P { 5, 6 };
syscall(60, G.b + z);
' "error:<source>:5:23: expected ')', got ';'"
exact1 "WU4 a double wrap, one ) short, unannotated" "$WH"'fn run(): i64 { var q = ((P { 5, 6 }); return q.b; }
syscall(60, run());
' "error:<source>:3:38: expected ')', got ';'"
exact1 "WU5 a generic literal" "$WH"'fn run(): i64 { var h: Bx<i64> = (Bx<i64> { 1, 2 }; return h.w; }
syscall(60, run());
' "error:<source>:3:51: expected ')', got ';'"
exact1 "WU6 a named literal, the zone" "$WH"'var G: P = (P { b: 6, a: 5 };
syscall(60, G.a);
' "error:<source>:3:29: expected ')', got ';'"
exact1 "WU6b --syntax-only: the filed repro" 'struct P { a; b; }
fn run(): i64 { var t: P = (P { 5, 6 }; return t.a; }
syscall(60, run());
' "error:<source>:2:39: expected ')', got ';'" --syntax-only
exact1 "WU7 control: an operand (P { .. } + 1" "$WH"'fn run(): i64 { var t = (P { 5, 6 } + 1; return 0; }
syscall(60, run());
' "error:<source>:3:26: $MS
error:<source>:3:40: expected ')', got ';'"
exact1 "WU8 control: an assignment t = (P { .. };" "$WH"'fn run(): i64 { var t: P = P { 1, 2 }; t = (P { 5, 6 }; return t.a; }
syscall(60, run());
' "error:<source>:3:45: $MS
error:<source>:3:55: expected ')', got ';'"

# C — the shapes the guide teaches are unchanged: a positional run of a nested struct's leaves and a nested
# struct VALUE element.
CR='struct Pt { x; y; }
struct Rect { o: Pt; w; h; }
'
accept "C1 Rect { 0, 0, 10, 5 } (nested leaves)" "$CR"'fn f(): i64 { var r = Rect { 1, 2, 10, 5 }; return r.o.x + r.o.y * 10 + r.w + r.h; }
syscall(60, f());
' 36 "$CR"'fn f(): i64 { var r: Rect; r.o.x = 1; r.o.y = 2; r.w = 10; r.h = 5; return r.o.x + r.o.y * 10 + r.w + r.h; }
syscall(60, f());
'
accept "C2 Rect { a, 10, 5 } (a struct value)" "$CR"'fn f(): i64 { var a: Pt = Pt { 3, 4 }; var r = Rect { a, 10, 5 }; return r.o.x + r.o.y * 10 + r.w + r.h; }
syscall(60, f());
' 58 "$CR"'fn f(): i64 { var r: Rect; r.o.x = 3; r.o.y = 4; r.w = 10; r.h = 5; return r.o.x + r.o.y * 10 + r.w + r.h; }
syscall(60, f());
'
accept "C3 the zone: Rect { 1, 2, 10, 5 }" "$CR"'var G = Rect { 1, 2, 10, 5 };
syscall(60, G.o.x + G.o.y * 10 + G.w + G.h);
' 36 "$CR"'fn f(): i64 { var r: Rect; r.o.x = 1; r.o.y = 2; r.w = 10; r.h = 5; return r.o.x + r.o.y * 10 + r.w + r.h; }
syscall(60, f());
'

# X — the tree's aarch64 and cx compilers (frontend shared): the filed repro is the one error there too.
X1SRC='struct P { a; }
var G: P = P { 1 };
fn run(): i64 { G = P { 5 }; return 0; }
var r = run();
syscall(60, G.a);
'
for xl in aarch64 cx; do
    if cat "src/main_$xl.cyr" | "$CC" > "$D/cycc_$xl" 2>/dev/null && [ -s "$D/cycc_$xl" ]; then
        chmod +x "$D/cycc_$xl"
        printf '%s' "$X1SRC" > "$D/x.cyr"
        xr=0; cat "$D/x.cyr" | "$D/cycc_$xl" > "$D/x.bin" 2>"$D/x.err" || xr=$?
        if [ "$xr" != 0 ] && [ "$(grep -E '^(error|warning)' "$D/x.err")" = "error:<source>:3:21: $MS" ]; then
            printf '  ok(one error): X %-30s\n' "$xl"; pass=$((pass+1))
        else
            printf '  FAIL: X %-38s rc %s: %s\n' "$xl" "$xr" "$(grep -E '^(error|warning)' "$D/x.err" | tr '\n' '|')"; fail=$((fail+1))
        fi
    else
        printf '  FAIL: X %-38s could not build src/main_%s.cyr\n' "$xl" "$xl"; fail=$((fail+1))
    fi
done

echo "struct_literal_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ] || exit 1
exit 0
