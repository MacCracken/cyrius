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
impl Mk for Q { fn tw(self): Q { var r: Q; r.a = 1; r.b = 2; r.c = 3; return r; } }
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
impl Mp for Pt { fn tw(self): Pt { var r: Pt; r.x = 1; r.y = 2; return r; } }
impl Mb for Big { fn tw(self): Big { var r: Big; r.a = 1; return r; } }
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

echo "struct_literal_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ] || exit 1
exit 0
