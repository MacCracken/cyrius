#!/bin/sh
# Gate: a file may DECLARE a global whose name another file has made `private` (6.6.6 bite 19b).
#
# THE DEFECT (measured at 6.6.5):
#
#     lib/a.cyr:  private            lib/b.cyr:  private
#                 var LIMIT = 5;                 var B_CAP = LIMIT * 2;
#                                                var LIMIT = 5;
#
#     error: lib/b.cyr:3:11: 'LIMIT' is private to its file          (rc 1)
#
# Column 11 of line 3 is b.cyr's OWN `var LIMIT = 5;` — its declaration, not a reference — and
# b.cyr never mentions a.cyr's `LIMIT` at all. A legal program could not be compiled.
#
# THE ROOT CAUSE. v6.5.0 put the cross-file `private` check inside FINDVAR on purpose: every
# REFERENCE resolves through it, so one check covers them all (the fn side had shipped with 2
# of at least 13 paths wired). But FOUR callers are not references — PARSE_GVAR_REG's
# `sit_shadow` probe, CHKDUPVAL, CHK_ENUM_SHADOW and PARSE_ENUM_DEF's pass-2 value store all
# look a name up while REGISTERING it. Running the visibility check for a DECLARATION-time
# lookup turned the answer into an accusation. Fix: `_findvar_core` is pure resolution;
# `FINDVAR` is that plus the check; declaration-time lookups call the core
# (src/frontend/parse_types.cyr).
#
# ⚠ THE FIRST CUT OF THIS GATE MISSED TWO OF THE FOUR, AND THE REASON IS IN ITS OWN ROW SET.
# Every accepting row it shipped with declared the name with a `= NUM ;` literal, which is
# exactly the `chk_has == 1` arm that reaches CHKDUPVAL. CHK_ENUM_SHADOW is the OTHER arm —
# `chk_has == 0`, i.e. every initializer that is not an int literal — so an expression, a
# string or a call init stayed REFUSED while the gate read green. Rows I/J/K are that arm: the
# same declaration with `= 2 + 3`, `= "abcd"` and `= f()`. A row set that samples one arm of a
# two-arm dispatch reports a verdict about the arm it did not run. Row L is the fourth lookup
# and needed a different axis again: the other file declares the name as an ENUM CONSTANT, so
# the refusal lands on THAT file's own member line and no row with a `var` on both sides can
# reach it.
#
# ⚠ THE NEGATIVE HALF IS THE POINT OF THE GATE. A one-line "fix" here is to delete the check,
# and every positive row would still pass. Rows D/E/F/G are the enforcement rows: a genuine
# cross-file read, an `&addr`, a fn-body read and an assignment must still be REFUSED, each
# with the message naming the symbol.
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual: every accepting row's value
# comes from arithmetic on b's OWN constant (`B_CAP = LIMIT * 2`), and is compared against a
# CONTROL program in which a.cyr does not declare the name at all — so the row proves b got
# ITS OWN `LIMIT`, not merely that the compile succeeded.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree whose src/ carries the mutation,
# built by build/cycc and run as CYCC=<mutant>):
#   1. the sit_shadow probe put back on FINDVAR      -> RED rows A B C H I J K
#   2. CHKDUPVAL's probe put back on FINDVAR         -> RED rows A B C H
#   3. CHK_ENUM_SHADOW's probe put back on FINDVAR   -> RED rows I J K
#   4. PARSE_ENUM_DEF's pass-2 value store put back
#      on FINDVAR                                    -> RED row L only
#   5. _vis_check_var made a no-op (the "just delete
#      the check" fix)                               -> RED rows D E F G
#   6. real tree                                     -> GREEN (12 rows)
# ⚠ Mutants 1 and 2 redden the SAME `= NUM ;` rows, measured — both probes fire on a literal
#   declaration and either one alone reproduces the defect. That is why the fix had to move
#   both, and why neither mutant is redundant: each proves its own probe is on the core.
#   Mutant 1 additionally reddens I/J/K (sit_shadow runs for every initializer shape), and
#   mutant 3 reddens ONLY I/J/K — which is the row set that did not exist when 19b shipped.
#   Mutant 4 reddens ONLY L, for the same reason: the enum pass-2 store is reached from a
#   DECLARATION in the other file, so no row that declares the name as a `var` on both sides
#   can see it. THE COUNT IN THIS LEDGER HAS BEEN THE BUG TWICE — 19b said two lookups, the
#   first review fix said three, and there are four. Grep the shape (a FINDVAR call reachable
#   from a registration path), do not extend the list.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: private_does_not_block_own_declaration: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

mkdir -p "$WORK/p/lib"
# a.cyr: a `private` file that owns the name.
A_PRIV='private\nvar PDB_LIMIT = 5;\npublic fn pdb_a(): i64 { return 1; }\n'
# ...and a control a.cyr that does NOT declare the name, so an accepting row's value proves b
# resolved its OWN declaration rather than merely compiling.
A_NONE='private\nvar PDB_OTHER = 99;\npublic fn pdb_a(): i64 { return 1; }\n'

# _acc <id> <want> <b.cyr body> <main body> [a.cyr body]: compile with a.cyr declaring the name
# and with the control a.cyr, and require the SAME value from both. The 5th argument overrides
# the declaring a.cyr (row L needs one that declares the name as an ENUM constant).
_acc() {
    NROWS=$((NROWS + 1))
    _id=$1; _want=$2; _b=$3; _m=$4; _a=${5:-$A_PRIV}
    printf '%b' "$_b" > "$WORK/p/lib/b.cyr"
    printf '%b' "$_m" > "$WORK/p/main.cyr"
    for _which in priv none; do
        if [ "$_which" = priv ]; then printf '%b' "$_a" > "$WORK/p/lib/a.cyr"
        else printf '%b' "$A_NONE" > "$WORK/p/lib/a.cyr"; fi
        rm -f "$WORK/o.bin"
        if ( cd "$WORK/p" && "$CC" < main.cyr > "$WORK/o.bin" 2> "$WORK/o.err" ) && [ -s "$WORK/o.bin" ]; then
            chmod +x "$WORK/o.bin"
            set +e; "$WORK/o.bin" > /dev/null 2>&1; _r=$?; set -e
        else
            _r="CCFAIL($(grep -m1 -o "is private to its file" "$WORK/o.err" 2>/dev/null || echo other))"
        fi
        [ "$_r" = "$_want" ] || bad "row $_id [$_which]: gave $_r, want $_want"
    done
}

# A — the filed repro verbatim: b declares its own LIMIT AFTER using it, in a private file.
_acc A 10 \
  'private\nvar PDB_CAP = PDB_LIMIT * 2;\nvar PDB_LIMIT = 5;\npublic fn pdb_cap(): i64 { return PDB_CAP; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'
# B — the declaration BEFORE any use, with a SAME-VALUE literal: CHKDUPVAL still runs its
#     probe here (it only stays quiet about the value), so this row covers the shape where
#     nothing is reported and the refusal came purely from the lookup.
_acc B 15 \
  'private\nvar PDB_LIMIT = 5;\nvar PDB_CAP = PDB_LIMIT * 3;\npublic fn pdb_cap(): i64 { return PDB_CAP; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'
# C — a CONFLICTING literal: this is the CHKDUPVAL path specifically. The value is b's.
_acc C 14 \
  'private\nvar PDB_LIMIT = 7;\npublic fn pdb_cap(): i64 { return PDB_LIMIT * 2; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'
# H — a PUBLIC file (no `private` line) declaring the same name is accepted too, and gets its
#     own value; the fold means the LAST declaration wins for everyone who is allowed to see it.
_acc H 22 \
  'var PDB_LIMIT = 11;\npublic fn pdb_cap(): i64 { return PDB_LIMIT * 2; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'

# ── the CHK_ENUM_SHADOW arm: initializers that are NOT an int literal ──────────────────
# Rows A/B/C/H all declare with `= NUM ;` (`chk_has == 1`), which routes through CHKDUPVAL.
# Everything else routes through CHK_ENUM_SHADOW instead, and that probe was still on FINDVAR
# after 19b. Each row's value is deliberately DIFFERENT from a.cyr's 5, so resolving a's slot
# by mistake would give a different answer rather than an accidental match.
# I — an EXPRESSION initializer. b's own 6, times 3.
_acc I 18 \
  'private\nvar PDB_LIMIT = 2 + 4;\npublic fn pdb_cap(): i64 { return PDB_LIMIT * 3; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'
# J — a STRING initializer: the shape from the patra/SecureYeoman miscompile this probe exists
#     for. The value is the 4th byte of b's own literal ('d' = 100) — a's PDB_LIMIT is the
#     integer 5, so a wrong resolution cannot produce it.
_acc J 100 \
  'private\nvar PDB_LIMIT = "abcd";\npublic fn pdb_cap(): i64 { return load8(PDB_LIMIT + 3); }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'
# K — a CALL initializer (a deferred global), doubled: 13 * 2.
_acc K 26 \
  'private\nfn pdb_src(): i64 { return 13; }\nvar PDB_LIMIT = pdb_src();\npublic fn pdb_cap(): i64 { return PDB_LIMIT * 2; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n'

# L — THE FOURTH LOOKUP: the other file declares the name as an ENUM CONSTANT. PARSE_ENUM_DEF
#     runs a SECOND pass over its members to store their values, and that pass resolves each
#     member by name — its own declaration's second half, not a reference anything spells. It
#     was on FINDVAR too, so a.cyr was refused AT ITS OWN `enum PA { PDB_LIMIT = 3; }` LINE
#     (`error: lib/a.cyr:2:24: 'PDB_LIMIT' is private to its file`, rc 1, no binary) merely
#     because b.cyr declared a var of that name. Neither file mentions the other's symbol.
#     Measured: pre-fix compiler CCFAIL, fixed compiler 18 — and the control, where a.cyr does
#     not declare the name at all, gives 18 on both.
_acc L 18 \
  'private\nvar PDB_LIMIT = 9;\npublic fn pdb_cap(): i64 { return PDB_LIMIT * 2; }\n' \
  'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_cap();\nsyscall(60, r);\n' \
  'private\nenum PA { PDB_LIMIT = 3; }\npublic fn pdb_a(): i64 { return 1; }\n'

# ── the enforcement half: a genuine cross-file ACCESS is still refused ─────────────────
_ref() {
    NROWS=$((NROWS + 1))
    _id=$1; _b=$2; _m=$3
    printf '%b' "$A_PRIV" > "$WORK/p/lib/a.cyr"
    printf '%b' "$_b" > "$WORK/p/lib/b.cyr"
    printf '%b' "$_m" > "$WORK/p/main.cyr"
    rm -f "$WORK/r.bin"
    set +e; ( cd "$WORK/p" && "$CC" < main.cyr > "$WORK/r.bin" 2> "$WORK/r.err" ); _rc=$?; set -e
    [ "$_rc" = "1" ] || bad "row $_id: compiler exited $_rc, want 1 (a cross-file private read must be refused)"
    [ -s "$WORK/r.bin" ] && bad "row $_id: a binary was emitted for a refused program"
    grep -q "'PDB_LIMIT' is private to its file" "$WORK/r.err" \
        || bad "row $_id: the refusal does not name PDB_LIMIT"
}
# D — a top-level read in another file
_ref D 'public fn pdb_r(): i64 { return 1; }\n' \
       'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = PDB_LIMIT;\nsyscall(60, r);\n'
# E — an `&addr` in another file
_ref E 'public fn pdb_r(): i64 { return 1; }\n' \
       'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar p = &PDB_LIMIT;\nsyscall(60, 0);\n'
# F — a fn BODY in another file
_ref F 'public fn pdb_r(): i64 { return PDB_LIMIT; }\n' \
       'include "lib/a.cyr"\ninclude "lib/b.cyr"\nvar r = pdb_r();\nsyscall(60, r);\n'
# G — an ASSIGNMENT from another file (the statement layer's resolver, a third path)
_ref G 'public fn pdb_r(): i64 { return 1; }\n' \
       'include "lib/a.cyr"\ninclude "lib/b.cyr"\nPDB_LIMIT = 9;\nsyscall(60, 0);\n'

# Anti-vacuity: the floor is DERIVED from this file's own row calls.
WANT=$(grep -cE '^_acc [A-Z] |^_ref [A-Z] ' "$0")
[ "$NROWS" -eq "$WANT" ] || bad "only $NROWS rows ran; this file spells $WANT"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: private_does_not_block_own_declaration: $NFAIL of $NROWS rows"
    exit 1
fi
echo "PASS: a file may declare a name another file made private, and a real cross-file read is still refused ($NROWS rows)"
exit 0
