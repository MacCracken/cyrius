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
# of at least 13 paths wired). But two callers are not references — PARSE_GVAR_REG's
# `sit_shadow` probe and CHKDUPVAL both ask "does this name already exist?" while REGISTERING
# a new global. Running the visibility check for a DECLARATION-time probe turned the answer
# into an accusation. Fix: `_findvar_core` is pure resolution; `FINDVAR` is that plus the
# check; declaration-time probes call the core (src/frontend/parse_types.cyr).
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
#   1. the sit_shadow probe put back on FINDVAR      -> RED rows A B C H
#   2. CHKDUPVAL's probe put back on FINDVAR         -> RED rows A B C H
#   3. _vis_check_var made a no-op (the "just delete
#      the check" fix)                               -> RED rows D E F G
#   4. real tree                                     -> GREEN (8 rows)
# ⚠ Mutants 1 and 2 redden the SAME rows, measured — every accepting row here declares with a
#   `= NUM ;` literal, so BOTH probes fire on it and either one alone reproduces the defect.
#   That is why the fix had to move both, and why neither mutant is redundant: each proves its
#   own probe is on the core.
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

# _acc <id> <want> <b.cyr body> <main body>: compile with a.cyr declaring the name and with the
# control a.cyr, and require the SAME value from both.
_acc() {
    NROWS=$((NROWS + 1))
    _id=$1; _want=$2; _b=$3; _m=$4
    printf '%b' "$_b" > "$WORK/p/lib/b.cyr"
    printf '%b' "$_m" > "$WORK/p/main.cyr"
    for _which in priv none; do
        if [ "$_which" = priv ]; then printf '%b' "$A_PRIV" > "$WORK/p/lib/a.cyr"
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
