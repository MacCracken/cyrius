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
# 6.6.20 (RPD-04): R12-R16 — the same refusals for the STEP of a classic `for`, which compiled clean.
# 6.7.11: R17-R23 — an ASSIGNMENT from a dereference of a `*U` (a local, a field, a `*S`'s pointee, top level,
# a for step) refused by name; A4 / A5 — `l = *p` and `q = *p` of the declared type compile with no warning.
# 6.7.11: R24-R29 — a struct-typed FIELD from a `*U` global, a `: *U` call, a `*U` field, pointer arithmetic on
# one, at top level and in a for step, refused by name; A6 — the declared type copies with no warning.
# 6.7.11: R30-R34 — a top-level copy-init from a field reached through a pointer: a leaf of another struct type
# refused by name (both zones), a `*T` global / holder / fn declared below G refused by name; A7 — the same
# sources of the declared type copy in both zones.
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
#   6.6.20: `_for_step_assign` without `_for_step_aggregate` (the 6.6.19 step)
#                                                   -> RED R12 R13 R14 R15 R16 (compiled clean)
#   real tree                                       -> GREEN
# 6.7.11 (issues/archived/2026-10-13-assignment-from-struct-dereference-copies-one-word.md), the same method:
#   the 6.7.11 tree before it (cf5838db)            -> RED 9: R17-R23 compiled (a warning at most), A4 A5 warned
#   `_asg_dstar` answering 0 (no name arm)          -> RED 7: R17 R19 R20 R21 R22 compiled, A4 A5 warned
#   `_fsc_dstar` answering 0 (no field arm)         -> RED 2: R18 R23 compiled
# 6.7.11 (issues/archived/2026-10-13-struct-field-destination-from-pointer-global-call-or-field.md), the same method:
#   `_fsc_psrc` answering 0 (no pointer-source field arm) -> RED 7: R24-R29 compiled clean, A6 exit 0 (the
#                                                      pointer word in the field)
# 6.7.11 (issues/archived/2026-10-12-struct-global-init-from-field-through-pointer-faults.md), the same method:
#   the tree before it (dce13af1)                   -> RED 6: R30-R34 compiled clean (the value store), A7 SIGSEGV
#   MG1 `_gci_src` without the `*T` global arm     -> RED 4: R30 R31 R33 compiled, A7 SIGSEGV
#   MG2 `_gci_chain` without the `*T` field hop    -> RED 2: R34 compiled, A7 SIGSEGV
#   MG3 `_gci_call` answering 0 (no call base)     -> RED 2: R32 compiled, A7 SIGSEGV
#   MG4 `_gci_below` without the call's message    -> RED 1: R32 refused as "a global declared below it"
#   (struct_field_value_copy.tcyr: MG1-MG3 SIGSEGV at its first through-pointer row, x86 and cxvm)
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
impl Pt { fn plus(self, q: Pt): i64 { return q.x * 10 + q.y; } }
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

echo "=== a top-level copy-init from a field reached through a POINTER (6.7.11) ==="
# issues/archived/2026-10-12-struct-global-init-from-field-through-pointer-faults.md: `var G: Pt = PW.v;`, `= gw().v;`,
# `= VW.p.v;` copy now (tests/tcyr/crossos/struct_field_value_copy.tcyr); a leaf of another struct type is
# refused by name, as from an inline base (R6 / R8), and a source pass 1 cannot type — a `*T` global, a holder
# or a fn declared BELOW G in the leading block — is refused by name, as R10 / R11 are (never the value
# store: through 6.7.10 each row compiled clean, G held the field's first word, and `G.x` SIGSEGV'd).
SP='var GR = RB { 1, 2, 3, 4, 5, 6 };
var PW: *RB = &GR;
struct VW { p: *RB; }
'
refuse "R30 leading block, PW.q (a Q leaf) into a Pt" "cannot copy 'q' $MV: 'G'" \
    "${T}${SP}var G: Pt = PW.q; syscall(60, G.x);"
refuse "R31 after a statement, PW.q into a Pt" "cannot copy 'q' $MV: 'G'" \
    "${T}${SP}syscall(1, 1, \"\", 0); var G: Pt = PW.q; syscall(60, G.x);"
refuse "R32 leading block, gw().v with gw declared below" "cannot copy-init 'G' from a field of a call to a fn declared below it (declare the fn first): 'gw'" \
    "${T}${SP}var G: Pt = gw().v; fn gw(): *RB { return &GR; } fn go(): i64 { return G.x * 10 + G.y; } syscall(60, go());"
refuse "R33 leading block, PB.v with the *RB global declared below" "cannot copy-init 'G' $MB (declare the source first): 'PB'" \
    "${T}${SP}var G: Pt = PB.v; var PB: *RB = &GR; fn go(): i64 { return G.x * 10 + G.y; } syscall(60, go());"
refuse "R34 leading block, VB.p.v with the holder declared below" "cannot copy-init 'G' $MB (declare the source first): 'VB'" \
    "${T}${SP}var G: Pt = VB.p.v; var VB = VW { &GR }; fn go(): i64 { return G.x * 10 + G.y; } syscall(60, go());"

echo "=== a classic-for STEP refuses what the statement refuses (6.6.20, RPD-04) ==="
# The step `for (..; ..; a = q)` skipped the statement's whole-aggregate dispatch and stored ONE
# word: every row below compiled clean (rc 0, no diagnostic) where the statement form is refused.
# The values half (the step copies every word) is tests/tcyr/crossos/for_step_struct_assign.tcyr.
SQ='fn mkq(): Q { var r: Q = Q { 1, 2, 3 }; return r; }
fn mk4(): f64v4 { var r: f64v4; return r; }
var GQ = Q { 1, 2, 3 }; var G: Pt = Pt { 0, 0 };
'
refuse "R12 step a = q, a local of another type" "$MV" \
    "${T}${SQ}fn go(): i64 { var a: Pt; var q: Q; var i = 0; for (i = 0; i < 1; a = q) { i = i + 1; } return a.x; } syscall(60, go());"
refuse "R13 step a = r.q, a field of another type" "$MV" \
    "${T}${SQ}fn go(): i64 { var a: Pt; var r: RB; var i = 0; for (i = 0; i < 1; a = r.q) { i = i + 1; } return a.x; } syscall(60, go());"
refuse "R14 step a = mkq(), a call returning another" "$MV" \
    "${T}${SQ}fn go(): i64 { var a: Pt; var i = 0; for (i = 0; i < 1; a = mkq()) { i = i + 1; } return a.x; } syscall(60, go());"
refuse "R15 step G = GQ, a global of another type" "$MV" \
    "${T}${SQ}fn go(): i64 { var i = 0; for (i = 0; i < 1; G = GQ) { i = i + 1; } return G.x; } syscall(60, go());"
refuse "R16 step v = mk4(), another vector width" "vector return type does not match the assigned variable" \
    "${T}${SQ}fn go(): i64 { var v: f64v2; var i = 0; for (i = 0; i < 1; v = mk4()) { i = i + 1; } return 0; } syscall(60, go());"

echo "=== an assignment from a dereference of a *U of another struct type (6.7.11) ==="
# issues/archived/2026-10-13-assignment-from-struct-dereference-copies-one-word.md: `l = *p` / `o.s = *p` copy the
# struct now (tests/tcyr/crossos/struct_deref_assign_copy.tcyr); a `*U` of another struct is refused by name,
# as the declaration `var l: Pt = *pu;` is. Through 6.7.10 each row compiled (a warning at most) and stored
# U's first word.
SU='var GQ = Q { 1, 2, 3 }; var PU: *Q = &GQ; fn gu(): *Q { return PU; }
'
refuse "R17 l = *pu, a local" "cannot copy 'pu' $MV: 'l'" \
    "${T}fn go(): i64 { var q = Q { 1, 2, 3 }; var pu: *Q = &q; var l = Pt { 0, 0 }; l = *pu; return l.x; } syscall(60, go());"
refuse "R18 o.s = *pu, a struct-typed field" "cannot copy 'pu' into a struct field of a different struct type: 'v'" \
    "${T}fn go(): i64 { var q = Q { 1, 2, 3 }; var pu: *Q = &q; var r: RB; r.v = *pu; return r.v.x; } syscall(60, go());"
refuse "R19 G = (*PU) at top level" "cannot copy 'PU' $MV: 'G'" \
    "${T}${SU}var G = Pt { 0, 0 }; G = (*PU); syscall(60, G.x);"
refuse "R20 l = *gu(), a : *Q call" "cannot copy 'gu' $MV: 'l'" \
    "${T}${SU}fn go(): i64 { var l = Pt { 0, 0 }; l = *gu(); return l.x; } syscall(60, go());"
refuse "R21 q = *pu into a *Pt's pointee" "cannot copy 'pu' $MV: 'q'" \
    "${T}fn go(): i64 { var u = Q { 1, 2, 3 }; var pu: *Q = &u; var t = Pt { 0, 0 }; var q: *Pt = &t; q = *pu; return t.x; } syscall(60, go());"
refuse "R22 step a = *pu, 8 B" "cannot copy 'pu' $MV: 'a'" \
    "${T}fn go(): i64 { var u = Q8 { 1, 2 }; var pu: *Q8 = &u; var a = P8 { 0, 0 }; var i = 0; for (i = 0; i < 1; a = *pu) { i = i + 1; } return a.x; } syscall(60, go());"
refuse "R23 step r.v = (*pu), a field" "cannot copy 'pu' into a struct field of a different struct type: 'v'" \
    "${T}fn go(): i64 { var u = Q { 1, 2, 3 }; var pu: *Q = &u; var r: RB; var i = 0; for (i = 0; i < 1; r.v = (*pu)) { i = i + 1; } return 0; } syscall(60, go());"

echo "=== a struct-typed FIELD from a *U global, a : *U call, a *U field (6.7.11) ==="
# issues/archived/2026-10-13-struct-field-destination-from-pointer-global-call-or-field.md: `o.s = GP` / `gp()` / `w.p`
# copy the struct now (tests/tcyr/crossos/struct_pointer_source_copy.tcyr); a `*U` of another struct is refused
# by name, as `o.s = u` and `l = GU` are. Through 6.7.10 each row compiled clean and stored the pointer word.
SW='struct WU { n; pu: *Q; }
'
refuse "R24 r.v = PU, a *Q global" "cannot copy 'PU' into a struct field of a different struct type: 'v'" \
    "${T}${SU}fn go(): i64 { var r: RB; r.v = PU; return r.v.x; } syscall(60, go());"
refuse "R25 r.v = gu(), a : *Q call" "cannot copy 'gu' into a struct field of a different struct type: 'v'" \
    "${T}${SU}fn go(): i64 { var r: RB; r.v = gu(); return r.v.x; } syscall(60, go());"
refuse "R26 r.v = w.pu, a *Q field" "cannot copy 'pu' into a struct field of a different struct type: 'v'" \
    "${T}${SU}${SW}fn go(): i64 { var w = WU { 0, PU }; var r: RB; r.v = w.pu; return r.v.x; } syscall(60, go());"
refuse "R27 r.v = (PU + 0), pointer arithmetic" "cannot copy 'PU' into a struct field of a different struct type: 'v'" \
    "${T}${SU}fn go(): i64 { var r: RB; r.v = (PU + 0); return r.v.x; } syscall(60, go());"
refuse "R28 GR.v = PU at top level" "cannot copy 'PU' into a struct field of a different struct type: 'v'" \
    "${T}${SU}var GR = RB { 1, 2, 3, 4, 5, 6 }; GR.v = PU; syscall(60, GR.v.x);"
refuse "R29 step r.v = gu()" "cannot copy 'gu' into a struct field of a different struct type: 'v'" \
    "${T}${SU}fn go(): i64 { var r: RB; var i = 0; for (i = 0; i < 1; r.v = gu()) { i = i + 1; } return 0; } syscall(60, go());"

# ... and the same type compiles with NO warning (6.7.11: `l = *p` and `q = *p` warned "assigning non-pointer
# to typed pointer", the dereference's pointer step being 0) and runs the copy.
quiet() {  # $1 label  $2 source  $3 expected exit — no 'warning' line, the exit right
    naccept=$((naccept+1))
    printf '%s' "$2" > "$D/q.cyr"
    got=$(_run "$D/q.cyr")
    if grep -q 'warning' "$D/a.err" 2>/dev/null; then
        printf '  FAIL: %-44s warned: %s\n' "$1" "$(grep 'warning' "$D/a.err" | head -1)"; fail=$((fail+1))
    elif [ "$got" != "$3" ]; then
        printf '  FAIL: %-44s exit=%s, want %s\n' "$1" "$got" "$3"; fail=$((fail+1))
    else
        printf '  ok(quiet): %-40s exit=%s\n' "$1" "$got"; pass=$((pass+1))
    fi
}
quiet "A4 l = *p, no warning" \
    "${T}fn go(): i64 { var s = Pt { 5, 8 }; var p: *Pt = &s; var l = Pt { 0, 0 }; l = *p; return l.x * 10 + l.y; } syscall(60, go());" \
    58
quiet "A5 q = *p (q: *Pt), no warning" \
    "${T}fn go(): i64 { var s = Pt { 5, 8 }; var p: *Pt = &s; var t = Pt { 0, 0 }; var q: *Pt = &t; q = *p; return t.x * 10 + t.y; } syscall(60, go());" \
    58

quiet "A6 r.v = GP / gp() / w.p (the declared type), no warning" \
    "${T}var GS = Pt { 5, 8 }; var GP: *Pt = &GS; fn gp(): *Pt { return GP; } struct WP { n; p: *Pt; }
fn go(): i64 { var w = WP { 0, GP }; var r: RB; var o: RB; var u: RB; r.v = GP; o.v = gp(); u.v = w.p; GS.x = 0; return r.v.x * 10 + o.v.y + u.v.x * 20; } syscall(60, go());" \
    158

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

accept "A7 var G: Pt = PW.v / gw().v / VW.p.v, both zones" \
    "${T}${SP}fn gw(): *RB { return &GR; }
var VV = VW { &GR }; var G1: Pt = PW.v; var G2: Pt = gw().v; var G3: Pt = VV.p.v; syscall(1, 1, \"\", 0); var G4: Pt = (PW.v); var G5: Pt = gw().v; var G6: Pt = VV.p.v; GR.v.x = 0; syscall(60, G1.x * 10 + G1.y + G2.x + G3.y + G4.x * 10 + G4.y + G5.x + G6.y);" \
    30 \
    "syscall(60, 12 + 1 + 2 + 12 + 1 + 2);"

echo "  $pass passed, $fail failed ($nrefuse refusal rows, $naccept acceptance rows)"
[ "$fail" -eq 0 ]
