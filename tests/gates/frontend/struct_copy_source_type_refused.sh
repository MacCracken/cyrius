#!/bin/sh
# Gate: a struct copy whose SOURCE is a field or a global is type-checked (6.6.12, B03).
#
# THE DEFECTS (measured at 6.6.11, x86_64 Linux; every refusal row below compiled clean there):
#
#   V3  A struct-typed FIELD passed as a by-value (> 8 B, address-passed) struct argument —
#       `take(r.v)` — pushed the field's FIRST WORD and the callee dereferenced it: SIGSEGV on
#       x86 and aarch64, a page fault on PE, 0 on cx. `_push_struct_expr_arg` now arms the
#       whole-field record, and the field is checked against the parameter's struct (recorded
#       per fn, SFPSID — the INSTANCE's for a generic), refused by name when it differs: a free
#       call in a fn and at top level, a generic instance, a method.
#   V4  A TOP-LEVEL copy-init `var B: Pt = A;` / `var G: Pt = BX.v;` stored the source's first
#       word in an 8-byte pointer-mode slot (SIGSEGV on `B.x`). It is an inline byte copy now,
#       and a source of ANOTHER struct type is refused by name — in the leading declaration
#       block (pass 1 + the EMIT_GVAR_INITS replay) and after the first statement (PARSE_VAR),
#       from a named global and from a field, at every width (the 8 B row too).
#       A whole source declared BELOW the destination in the leading block is refused by name:
#       pass 1 cannot see it (a pointer-mode slot) while the replay can (a whole struct), and the
#       value store that disagreement fell back to still put the first word in the slot (139).
#
# Refusal rows are checked on the MESSAGE, that it is the ONLY error, and that no binary was
# written. Acceptance rows are checked against the exit code AND a field-by-field CONTROL.
# The layout / copy half is pinned by tests/tcyr/crossos/struct_field_value_copy.tcyr.
#
# MUTATION LEDGER (6.6.12, each mutant rebuilt from the fixed tree with the one change):
#   base 6.6.11 build/cycc                          -> RED, every refusal row (compiled clean);
#                                                      A1 A2 SIGSEGV (139)
#   `_fla_push_arg` skips its GFPSID test           -> RED R1 R1b R2 R3 R4
#   `_psid_note` records nothing                    -> RED R1 R1b R2 R3 R4
#   `_psid_scan` (pass 1) skips `_psid_note`         -> RED R1b
#   `_gci_init` skips `_AGG_ASSIGN_TYPE_ERR`        -> RED R5 R6 R9
#   `_gci_toplevel` skips `_AGG_ASSIGN_TYPE_ERR`    -> RED R7 R8
#   `_gci_init` returns 0 (value store) instead of  -> RED R10 R11 (compiled clean; the
#     `_gci_below` when pass 1 saw no inline source      binaries SIGSEGV)
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

MA="to a parameter of a different struct type in a call to"
MV="into a variable of a different struct/vector type"
MB="from a global declared below it"
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 expected message  $3 source — the message must be the ONE error
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    nerr=$(grep -c '^error' "$D/r.err" 2>/dev/null || true)
    if grep -q "$2" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-44s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
        elif [ "$nerr" != 1 ]; then
            printf '  FAIL: %-44s refused, then %s more error(s): %s\n' "$1" "$((nerr-1))" \
                "$(grep '^error' "$D/r.err" | sed -n 2p)"
            fail=$((fail+1))
        else
            printf '  ok(refused): %-38s\n' "$1"; pass=$((pass+1))
        fi
    else
        printf '  FAIL: %-44s not refused (rc=%s, first line: %s)\n' \
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
        printf '  FAIL: %-44s CONTROL gave %s, want %s — the expectation is wrong\n' "$1" "$ctl" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$got" = "$3" ]; then
        printf '  ok(accepted): %-37s exit=%s (control %s)\n' "$1" "$got" "$ctl"; pass=$((pass+1))
    else
        printf '  FAIL: %-44s exit=%s, want %s (control %s)\n' "$1" "$got" "$3" "$ctl"
        fail=$((fail+1))
    fi
}

T='struct Pt { x; y; }
struct Q { a; b; c; }
struct RB { v: Pt; n; q: Q; }
struct P8 { x: i32; y: i32; }
struct Q8 { a: i32; b: i32; }
fn take(p: Pt): i64 { return p.x * 10 + p.y; }
fn gen<T>(p: T): i64 { return p.x * 10 + p.y; }
impl Mk for Pt { fn plus(self, q: Pt): i64 { return q.x * 10 + q.y; } }
'

echo "=== a struct-typed field as a by-value argument of another struct type (V3) ==="
refuse "R1 take(r.q) in a fn" "$MA 'take'" \
    "${T}fn go(): i64 { var r: RB; return take(r.q); } syscall(60, go());"
refuse "R1b a callee defined AFTER the call (pass 1)" "$MA 'late'" \
    "${T}fn go(): i64 { var r: RB; return late(r.q); } fn late(p: Pt): i64 { return p.x; } syscall(60, go());"
refuse "R2 take(GR.q) at top level" "$MA 'take'" \
    "${T}var GR = RB { 1, 2, 3, 4, 5, 6 }; var t = take(GR.q); syscall(60, t);"
refuse "R3 gen<Pt>(r.q), a generic instance" "$MA" \
    "${T}fn go(): i64 { var r: RB; return gen<Pt>(r.q); } syscall(60, go());"
refuse "R4 p.plus(r.q), a method" "$MA" \
    "${T}fn go(): i64 { var r: RB; var p: Pt; return p.plus(r.q); } syscall(60, go());"

# 6.6.17 (a10 review): the parameter's struct id was recorded only below ordinal 62, so from
# parameter 62 the check was silently skipped (R1c compiled; R1 was refused).
P62='a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39, a40, a41, a42, a43, a44, a45, a46, a47, a48, a49, a50, a51, a52, a53, a54, a55, a56, a57, a58, a59, a60, a61'
A62='0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61'
refuse "R1c take62(.., r.q), the struct at ordinal 62" "$MA 'take62'" \
    "${T}fn take62(${P62}, p: Pt): i64 { return p.x; } fn go(): i64 { var r: RB; return take62(${A62}, r.q); } syscall(60, go());"
refuse "R1d take65(.., r.q), the struct at ordinal 65" "$MA 'take65'" \
    "${T}fn take65(${P62}, b0, b1, b2, p: Pt): i64 { return p.x; } fn go(): i64 { var r: RB; return take65(${A62}, 0, 0, 0, r.q); } syscall(60, go());"

echo "=== a top-level copy-init from a source of another struct type (V4) ==="
refuse "R5 leading block, a named global" "$MV" \
    "${T}var GQ = Q { 1, 2, 3 }; var G: Pt = GQ; syscall(60, G.x);"
refuse "R6 leading block, a global's field" "$MV" \
    "${T}var GR = RB { 1, 2, 3, 4, 5, 6 }; var G: Pt = GR.q; syscall(60, G.x);"
refuse "R7 after a statement, a named global" "$MV" \
    "${T}var GQ = Q { 1, 2, 3 }; syscall(1, 1, \"\", 0); var G: Pt = GQ; syscall(60, G.x);"
refuse "R8 after a statement, a global's field" "$MV" \
    "${T}var GR = RB { 1, 2, 3, 4, 5, 6 }; syscall(1, 1, \"\", 0); var G: Pt = GR.q; syscall(60, G.x);"
refuse "R9 leading block, an 8 B struct" "$MV" \
    "${T}var GQ8 = Q8 { 1, 2 }; var G: P8 = GQ8; syscall(60, G.x);"

echo "=== a leading-block copy-init from a source declared BELOW it (pass 1 cannot see it) ==="
refuse "R10 a named global declared below" "cannot copy-init 'B' $MB (declare the source first): 'A'" \
    "${T}var B: Pt = A; var A = Pt { 3, 4 }; fn go(): i64 { return B.x * 10 + B.y; } syscall(60, go());"
refuse "R11 a field of a global declared below" "cannot copy-init 'G' $MB (declare the source first): 'BX'" \
    "${T}var G: Pt = BX.v; var BX = RB { 3, 4, 9, 0, 0, 0 }; fn go(): i64 { return G.x * 10 + G.y; } syscall(60, go());"

echo "=== the same shapes with the declared type (no false refusal) ==="
accept "A1 take(r.v), gen<Pt>(r.v), p.plus(r.v)" \
    "${T}fn go(): i64 { var r: RB; r.v.x = 3; r.v.y = 4; var p: Pt; return take(r.v) + gen<Pt>(r.v) + p.plus(r.v); } syscall(60, go());" \
    102 \
    "${T}fn go(): i64 { var r: RB; r.v.x = 3; r.v.y = 4; return r.v.x * 30 + r.v.y * 3; } syscall(60, go());"
accept "A2 var G: Pt = A; / = GR.v; (both paths)" \
    "${T}var A = Pt { 3, 4 }; var GR = RB { 5, 6, 0, 0, 0, 0 }; var G: Pt = A; var H: Pt = GR.v; syscall(1, 1, \"\", 0); var J: Pt = A; var K: Pt = GR.v; syscall(60, G.x * 10 + G.y + H.x * 10 + H.y + J.x * 10 + J.y + K.x * 10 + K.y);" \
    180 \
    "${T}var A = Pt { 3, 4 }; var GR = RB { 5, 6, 0, 0, 0, 0 }; syscall(60, (A.x * 10 + A.y + GR.v.x * 10 + GR.v.y) * 2);"

accept "A3 take65(.., r.v), the declared type at ordinal 65" \
    "${T}fn take65(${P62}, b0, b1, b2, p: Pt): i64 { return p.x * 10 + p.y; } fn go(): i64 { var r: RB; r.v.x = 3; r.v.y = 4; return take65(${A62}, 0, 0, 0, r.v); } syscall(60, go());" \
    34 \
    "${T}fn go(): i64 { var r: RB; r.v.x = 3; r.v.y = 4; return r.v.x * 10 + r.v.y; } syscall(60, go());"

echo "  $pass passed, $fail failed ($nrefuse refusal rows, $naccept acceptance rows)"
[ "$fail" -eq 0 ]
