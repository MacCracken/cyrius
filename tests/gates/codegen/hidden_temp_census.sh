#!/bin/sh
# hidden_temp_census.sh — 6.6.5. A CENSUS, so the next hidden global cannot slip back in.
#
# ⛔ WHY A CENSUS AND NOT JUST A BEHAVIOUR TEST. The defect was not one bad lowering, it was a
# HABIT: five constructs (`switch`, `match`, both `?` desugars, `for ... in`) each open-coded
# the same four lines — `GVCNT`, two `S64` writes, `SVCNT` — to get a scratch word, and each
# passed name offset 0 because "it has no name". Name offset 0 is the FIRST LEXED WORD of the
# program, and FINDVAR is a flat last-match table, so every one of them was reachable as an
# ordinary identifier; they were also shared across recursion, threads and files. A behaviour
# test pins the five that exist. This pins the SHAPE, so the sixth is caught at the source.
#
# ⛔ AND "THE SHAPE" MEANT ONLY NAME 0 UNTIL REVIEW ROUND 2. Axes 1 and 2 pin the NAME; the
# defect this bite actually repaired was a global registered with a REAL NAME from inside a fn
# (`PARSE_STRUCT_INIT` running with GINFN == 1), which neither of them can see — 12 of the 13
# live `_varn_base` sites were outside their scan. Axis 5 attributes every global registration
# to its enclosing fn and pins that table. A census that only counts one column is not a census.
#
# ⛔ AXIS 3 WAS A FLOOR AND THE FLOOR WAS BELOW THE FLOOR. It read `[ "$uses" -lt 9 ]` against
# ELEVEN live `_HTEMP` call sites, so deleting one — the exact mutant its own ledger claimed
# to have measured — left 10 and the gate printed `ok` and exited 0. A tolerance wider than
# the defect is not a gate. Axis 3 now counts PER LOWERING (each construct's own fn must keep
# its scratch slots) and asserts the exact total, so losing any one call site is named, not
# absorbed. Found by the 6.6.5 bite-4 review. The per-construct table below is the spec: a
# NEW lowering that needs a scratch word adds a row, and that is the point of a census.
#
# ⚠ ANTI-VACUOUS ON EVERY AXIS. A grep that matches nothing reports nothing wrong and would
# PASS; each axis therefore asserts a positive floor on what it scanned before it judges.
#
# MUTATION LEDGER (each applied to this tree and measured):
#   * restore one open-coded `S64(_varn_base + x * 8, 0);` hidden global -> axis 1 names it.
#   * restore a frame slot registered with name 0                        -> axis 2 names it.
#   * delete ONE `_HTEMP` call from PARSE_SWITCH (parse.cyr:1223)        -> axis 3 FAILs,
#     naming `PARSE_SWITCH want 1 got 0` and the total 11 -> 10. (Re-measured this round;
#     the same mutant left the previous floor-of-9 form GREEN.)
#   * delete one of PARSE_FOR's three                                    -> axis 3 FAILs on
#     `PARSE_FOR want 3 got 2`.
#   * re-add a `S64(_varn_base + vc * 8, noff);` inside a NEW helper fn  -> axis 5 names the
#     fn and the total (the shape the bite actually repaired: a real NAME, registered in a fn).
#   * write axis 1's shape without spaces, `S64(_varn_base + zz*8, 0);`  -> axis 1 names it.
#     ⛔ Before review round 2 this spelling PASSED — the regex spelled its spaces literally,
#     and the un-spaced style already exists in parse_fn.cyr / util.cyr / parse.cyr with
#     nothing enforcing cyrfmt over src/. A gate defeated by whitespace is not a gate.
#   * write axis 2's name as `0 - 0` instead of `0`                      -> axis 2 names it.
#     (Same round, same cause.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
SRC="src/frontend src/common src/backend"
fail=0

# ── axis 1 — no construct registers a GLOBAL slot under name offset 0 ─────────────────────
# The ONE legal site is `_HTEMP`'s own top-level arm in src/frontend/parse.cyr, which marks
# the slot dead so FINDVAR skips it. Anything else is a hidden global with a real name.
scanned=$(grep -rn 'S64(_varn_base' $SRC | wc -l)
if [ "$scanned" -lt 10 ]; then
    echo "FAIL hidden_temp_census axis 1: only $scanned '_varn_base' registrations found — the scan is broken, not the tree"
    exit 1
fi
# ⚠ WHITESPACE-TOLERANT, and it has to be: the first cut spelled the spaces literally, so
# `S64(_varn_base + zz*8, 0);` — a spelling that ALREADY EXISTS elsewhere in src/ and that
# nothing enforces cyrfmt over — walked straight past it and the gate printed ok. Found by
# review round 2. `0 - 0` is covered too; an arbitrary zero-valued EXPRESSION is not
# grep-detectable and axis 3 is what pins the behaviour.
bad1=$(grep -rEn 'S64\(_varn_base \+ [A-Za-z_][A-Za-z0-9_]*[[:space:]]*\*[[:space:]]*8,[[:space:]]*0[[:space:]]*(-[[:space:]]*0[[:space:]]*)?\);' $SRC | grep -vE '_hvi[[:space:]]*\*[[:space:]]*8,[[:space:]]*0' || true)
if [ -n "$bad1" ]; then
    echo "FAIL hidden_temp_census axis 1: a global slot is registered under NAME OFFSET 0 (= the first lexed word of the program):"
    echo "$bad1" | sed 's/^/    /'
    echo "    Use _HTEMP(S) / _HTSTORE / _HTLOAD (src/frontend/parse.cyr) — inside a fn it is an"
    echo "    anonymous FRAME slot (per call, per thread); at top level it is marked dead so FINDVAR skips it."
    fail=$((fail+1))
else
    echo "  ok: axis 1 — $scanned global registrations scanned, none under name offset 0 outside _HTEMP"
fi

# ── axis 2 — no FRAME slot is registered under name 0 either ──────────────────────────────
# FINDLOCAL matches any slot whose stored name is `>= 0`, so a frame slot named 0 aliases the
# first lexed word through the LOCAL table. Anonymous frame slots carry -1.
scanned2=$(grep -rn 'S64(S + 0x5D9D000' $SRC | wc -l)
if [ "$scanned2" -lt 20 ]; then
    echo "FAIL hidden_temp_census axis 2: only $scanned2 frame-slot registrations found — the scan is broken"
    exit 1
fi
bad2=$(grep -rEn 'S64\(S \+ 0x5D9D000 \+ [^,]*,[[:space:]]*0[[:space:]]*(-[[:space:]]*0[[:space:]]*)?\);' $SRC || true)
if [ -n "$bad2" ]; then
    echo "FAIL hidden_temp_census axis 2: a FRAME slot is registered under NAME 0 (FINDLOCAL matches sn >= 0):"
    echo "$bad2" | sed 's/^/    /'
    echo "    An anonymous frame slot must be written as 0 - 1."
    fail=$((fail+1))
else
    echo "  ok: axis 2 — $scanned2 frame-slot registrations scanned, none named 0"
fi

# ── axis 3 — the five constructs actually GO THROUGH the helper, each with its own count ──
# Axes 1 and 2 are satisfied by deleting the lowering entirely, so this counts the helper's
# real users — PER ENCLOSING FN, which is what makes losing ONE of them visible. The count is
# attributed by walking `fn <name>` headers, i.e. computed from the source's own structure and
# not from the number this file would like to see.
#   PARSE_SWITCH 1 | PARSE_MATCH 1 | _PARSE_STMT_IMPL 3 (`?` as a statement, pair + scalar)
#   _PARSE_TERM_IMPL 3 (`?` in an expression) | PARSE_FOR 3 (collection, length, range end)
#   _gv_target 1 (6.6.6: the dead sink a superseded global initializer stores into; the
#   replay runs at top level, so it is always the dead-global arm)
HT_SPEC="PARSE_SWITCH:1 PARSE_MATCH:1 _PARSE_STMT_IMPL:3 _PARSE_TERM_IMPL:3 PARSE_FOR:3 _gv_target:1"
ht_attr=$(for f in $(find src/frontend src/common src/backend -name '*.cyr'); do
    awk '/^fn /{fn=$2; sub(/\(.*/,"",fn)} /_HTEMP\(S\)/{ if ($0 !~ /fn _HTEMP/) print fn }' "$f"
done | sort | uniq -c | awk '{print $2":"$1}')
uses=$(echo "$ht_attr" | grep -c ':' || true)
want_total=0
for row in $HT_SPEC; do want_total=$((want_total + ${row#*:})); done
got_total=0
bad3=""
for row in $HT_SPEC; do
    wfn=${row%%:*}; wn=${row#*:}
    gn=$(echo "$ht_attr" | sed -n "s/^${wfn}:\\([0-9]*\\)\$/\\1/p")
    [ -z "$gn" ] && gn=0
    got_total=$((got_total + gn))
    if [ "$gn" -ne "$wn" ]; then bad3="$bad3 $wfn want $wn got $gn;"; fi
done
all_total=$(grep -rn '_HTEMP(S)' $SRC | grep -v 'fn _HTEMP' | wc -l)
if [ -n "$bad3" ] || [ "$all_total" -ne "$want_total" ]; then
    echo "FAIL hidden_temp_census axis 3: a lowering lost (or gained) its scratch slot:$bad3 total want $want_total got $all_total"
    echo "    attribution:"; echo "$ht_attr" | sed 's/^/      /'
    fail=$((fail+1))
else
    echo "  ok: axis 3 — $all_total _HTEMP call sites, attributed exactly ($HT_SPEC)"
fi

# ── axis 5 — WHERE a global slot may be registered at all ────────────────────────────────
# ⛔ Axes 1 and 2 only pin the NAME (offset 0). The defect this bite repaired was a global
# registered with a REAL NAME from inside a fn body — `PARSE_STRUCT_INIT` running with
# GINFN == 1 — which is invisible to both of them; 12 of the 13 live `_varn_base` sites are
# outside their scan. Review round 2. "Reachable with GINFN == 1" is not decidable by grep, so
# this attributes every registration to its ENCLOSING FN and pins that table: a new one lands
# either as a new fn (a new row) or as a bump to an existing count, and either way it is NAMED
# at the source with the reviewer asked to say which arm it is on.
#
# 6.6.6: `_gv_reg8` is the pass-1 destructure's per-name registration (moved out of
# PARSE_GVAR_REG, which was 4 and is now 1) — declaration zone only, never inside a fn.
#
# The ONE arm that legitimately runs inside a fn is PARSE_ARRAY's static-array fallback (an
# array over the per-fn frame budget, or any array under CYRIUS_STACK_ARRAYS=0). It is safe
# because `_fs_push` (parse.cyr) scopes the NAME to the block — that scoping is what
# `tests/gates/codegen/fn_local_storage_class.sh` axes 2/3/4/9 assert behaviourally, which is
# the other, non-textual half of this axis.
VN_SPEC="PARSE_VAR:4 PARSE_GVAR_REG:1 _gv_reg8:1 PARSE_STRUCT_INIT:1 PARSE_GVAR_ARR:1 PARSE_ENUM_DEF:1 PARSE_ARRAY:1 _HTEMP:1"
vn_attr=$(for f in $(find src/frontend src/common src/backend -name '*.cyr'); do
    awk '/^fn /{fn=$2; sub(/\(.*/,"",fn)} /S64\(_varn_base/{print fn}' "$f"
done | sort | uniq -c | awk '{print $2":"$1}')
vn_want=0
for row in $VN_SPEC; do vn_want=$((vn_want + ${row#*:})); done
vn_bad=""
vn_got=0
for row in $VN_SPEC; do
    wfn=${row%%:*}; wn=${row#*:}
    gn=$(echo "$vn_attr" | sed -n "s/^${wfn}:\\([0-9]*\\)\$/\\1/p")
    [ -z "$gn" ] && gn=0
    vn_got=$((vn_got + gn))
    if [ "$gn" -ne "$wn" ]; then vn_bad="$vn_bad $wfn want $wn got $gn;"; fi
done
# the total is counted a DIFFERENT way (a flat grep, not the awk attribution), so a site in a
# fn the spec does not name — or in no fn at all — cannot be absorbed by the per-fn sums.
if [ -n "$vn_bad" ] || [ "$scanned" -ne "$vn_want" ] || [ "$vn_got" -ne "$vn_want" ]; then
    echo "FAIL hidden_temp_census axis 5: a GLOBAL slot is registered somewhere new:$vn_bad total want $vn_want, flat grep $scanned, attributed $vn_got"
    echo "    attribution:"; echo "$vn_attr" | sed 's/^/      /'
    echo "    A registration inside a fn body is a per-program global shared by recursion, threads"
    echo "    and every later file. If the new site is genuinely top-level-only, add its fn here."
    echo "    The only in-fn arm allowed today is PARSE_ARRAY's static-array fallback, whose NAME"
    echo "    is scoped by _fs_push (src/frontend/parse.cyr)."
    fail=$((fail+1))
else
    echo "  ok: axis 5 — $scanned global registrations attributed exactly ($VN_SPEC)"
fi

# ── axis 4 — FINDVAR still skips dead slots ──────────────────────────────────────────────
# The top-level arm of _HTEMP relies on it; without the skip, a top-level `switch` puts a
# name-0 global back in the lookup table and axis 1 would pass while the defect is live.
if grep -q 'GVDEAD(S, vi)' src/frontend/parse_types.cyr; then
    echo "  ok: axis 4 — FINDVAR consults GVDEAD"
else
    echo "FAIL hidden_temp_census axis 4: FINDVAR no longer skips dead global slots (GVDEAD)"
    fail=$((fail+1))
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "PASS hidden_temp_census ($scanned global + $scanned2 frame registrations scanned; none under name 0 in any spelling; every global registration attributed to a declaration parser; $all_total _HTEMP users attributed across $uses fns; FINDVAR skips dead slots)"
