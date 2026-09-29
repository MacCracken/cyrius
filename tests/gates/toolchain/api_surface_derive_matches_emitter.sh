#!/bin/sh
# tests/gates/toolchain/api_surface_derive_matches_emitter.sh — 6.6.8 (bite 10)
#
# `cyrius api-surface` lists exactly the public fns the COMPILER emits — the `#derive`
# families by name, arity and visibility, `pub fn`, and signatures that wrap across lines.
#
# THE DEFECT (agnodrm, docs/development/issues/archived/2026-09-22-agnodrm-api-surface-
# derive-serialize-arity.md). programs/cyrius_api_surface.cyr re-implemented the derive
# emission by hand ("Mirrors PP_DERIVE_SERIALIZE") and nothing checked it against
# src/frontend/lex_pp.cyr, so it had drifted on every axis:
#   * `_to_json` listed at arity 1 — the emitter has taken `(ptr, sb)` since v5.9.31 — so a
#     hand-roll → derive migration read as `BREAKING … _to_json/2 removed`;
#   * `_from_json_str` never listed; `#derive(Deserialize)` not recognised at all (and,
#     stacked above `#derive(accessors)`, it dropped the codecs); `public struct` /
#     `pub struct` and `enum` targets not recognised;
#   * the field list was "skip to the next `;`", so a body without separators collapsed;
#   * file-private visibility was ignored: in a `private` file it LISTED a plain struct's
#     fns (which the compiler makes private) and OMITTED a `public struct`'s.
# The same scanner also missed every `pub fn` (322 in lib/yukti.cyr) and every signature
# whose `)` is on a later line (37 in this tree's lib/), invisible to removed_symbol_census.sh.
#
# ⭐ THE ORACLE IS THE COMPILER, in both directions. A fixture project covering every derive
# kind × {plain, public, pub, private-file, enum, `: stack`, stacked in both orders, blank and
# comment lines between, no separators, tabs, typed fields, comments and braces-in-char-
# literals inside the body, an indented directive, a comment that only LOOKS like one} plus
# plain / pub / public / wrapped fns, is compiled with CYRIUS_DCE_VERBOSE=1 (nothing is
# called, so every emitted fn is listed as dead). Then:
#   1. every name the tool lists is one the compiler emitted;
#   2. every emitted name the tool does NOT list is refused as `private to its file` when a
#      caller in another file names it — the omission is visibility, never a miss;
#   3. ONE program calling every listed fn from another file with the listed arity compiles
#      clean — names, visibility and arity at once (the compiler checks all three);
#   4. anti-vacuous: the same program with one arity off by one is refused.
# Plus a literal table of the expected snapshot, and floors on this tree's own snapshot.
# ⚠ 6.6.10 — two rules this gate used to PIN were compiler defects, and the tool mirrored
# them faithfully: `#derive(accessors)` above `#derive(Deserialize)` emitted no codecs (the
# accessors entry tested only the Serialize bit), and `#derive(accessors)` on an ENUM emitted
# per-member "field" accessors (dv_ea / dv_lb / dv_pen in the 6.6.8 table). The compiler now
# emits the codecs in the first case and refuses the build in the second; the tool mirrors
# both (dv_ad's codecs are in the table; axis 7 pins the refusal), and the enum fixtures that
# exercised body shapes (char-literal values, `= -2`, a `'{'` inside the body) derive
# Serialize instead, so that coverage is kept. If the compiler changes, axis 1 goes red here
# — which is the point: the tool must move with it.
#
# The tool under test is BUILT HERE from programs/cyrius_api_surface.cyr (API_SRC=<file>
# builds a different source — how the mutants below were run).
#
# MUTATION PROOF (checks failed; A1-A13 measured at 6.6.8 against 12 checks — A5, A7 and A9
# RE-MEASURED at 6.6.10 against the 18 checks after the enum fixtures moved to Serialize, and
# A14 added. The 6.6.7 tool failed 5 — axes 1, 2, 3, 5, 6. At 6.6.10 the 6.6.9 tool fails 6
# (axes 2, 5, 7) and the 6.6.9 COMPILER fails 5 (axes 1, 3, 7) — each side of the mirror
# is caught moving alone):
#   A1  `_to_json` at arity 1 again                                              3
#   A2  `_from_json_str` not listed                                               4
#   A3  `#derive(Deserialize)` not recognised                                     3
#   A4  a `public` / `pub` declaration prefix not recognised                      3
#   A5  `enum` not a derive target                                                3 (6.6.10: 3)
#   A6  file-private visibility ignored                                           3
#   A7  an accessors entry ignores a stacked Deserialize (the pre-6.6.10 `& 1`)  3
#   A8  the field walk skips to the next `;` (the 6.6.7 walk)                     3
#   A9  braces in a comment / char literal count toward the body's `}`            3 (6.6.10: 3)
#   A10 `pub fn` not stepped over                                                 4
#   A11 a signature must close on its own line (the 6.6.7 rule)                   4
#   A12 a comma inside a `#` comment in a wrapped signature counts                2
#   A13 an enum's `: stack` header not skipped                                    3
#   A14 `#derive(accessors)` on an enum listed again (no -1 refusal)             3
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

if [ ! -x "$ROOT/build/cycc" ]; then echo "FAIL: api-surface-derive — build/cycc not built"; exit 1; fi
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: api-surface-derive — mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$ROOT/build/cycc"}
API="$T/api_surface"
if ! "$CC" < "${API_SRC:-$ROOT/programs/cyrius_api_surface.cyr}" > "$API" 2> "$T/build.err"; then
    echo "FAIL: api-surface-derive — programs/cyrius_api_surface.cyr does not build"; sed -n '1,5p' "$T/build.err"; exit 1
fi
if [ "$(wc -c < "$API")" -lt 20000 ]; then echo "FAIL: api-surface-derive — built a $(wc -c < "$API")-byte tool"; exit 1; fi
chmod +x "$API"

P="$T/proj"
mkdir -p "$P/src"
ln -s "$ROOT/lib" "$P/lib"
cat > "$P/src/dv_plain.cyr" <<'EOF'
#derive(accessors)
#derive(Serialize)
struct dv_pt { x; y; }

#derive(Deserialize)
struct dv_de { a: i64; b: i32; }

#derive(Serialize)
public struct dv_pub { c; }

#derive(Serialize)
pub struct dv_pb2 { c2 }

#derive(Serialize)
enum dv_en { EA = 0; EB = 1; }

#derive(Deserialize)
enum dv_en2: stack { FA, FB, FC }

#derive(Deserialize)
#derive(accessors)
struct dv_da { d; e; }

#derive(accessors)
#derive(Deserialize)
struct dv_ad { g; h; }

#derive(accessors)

# a comment between the directives
#derive(Serialize)
struct dv_gap
{
    # a field-looking comment: nope; and a } brace
    k: Vec<i64>   # no separator after it
    m: i32; n
    o;
}

#derive(accessors)
struct dv_ns { u }

#derive(accessors)
struct dv_nosep { p q r }

#derive(Serialize)
enum dv_ea { MA = 1; MB = 'x'; MC = -2, MD }

    #derive(Serialize)
struct dv_ind { w; }

#derive(Serialize)x note - a comment, not a directive
struct dv_cmt { z; }

#derive(Serialize) # a trailing comment
struct dv_trail { v; }

#derive(Serialize)
enum dv_lb { LB = '{'; RB = 2; }

fn dv_plain(a, b) { return 0; }
pub fn dv_pubfn(a) { return 0; }
public fn dv_publicfn() { return 0; }
fn dv_wrapped(a, b,
  c, # a comment, with a comma
  d) { return 0; }
fn _dv_hidden(a) { return 0; }
EOF
printf '#derive(accessors)\nstruct dv_tab\t{\tt1;\tt2 }\n' >> "$P/src/dv_plain.cyr"
cat > "$P/src/dv_priv.cyr" <<'EOF'
private
#derive(accessors)
struct dv_hid { x; }
#derive(Serialize)
public struct dv_shown { y; }
#derive(Serialize)
pub enum dv_pen { PA; PB; }
#derive(Deserialize)
enum dv_hen { HA; HB; }
fn dv_inner() { return 0; }
public fn dv_outer(a) { return 0; }
pub fn dv_outer2(a,
  b) { return 0; }
EOF
HDR='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
include "lib/bayan.cyr"
include "src/dv_plain.cyr"
include "src/dv_priv.cyr"'
printf '%s\nfn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' "$HDR" > "$P/prog.cyr"
check "  (premise: the dv_tab body is written with TABS)" 3 "$(tr -cd '\t' < "$P/src/dv_plain.cyr" | wc -c | tr -d ' ')"

echo "the tool"
arc=0
( cd "$P" && timeout 20 "$API" --update --scope=project --snapshot="$T/A.snap" ) > "$T/api.out" 2>&1 || arc=$?
check "api-surface --update runs (rc 0)" 0 "$arc"
sed 's/.*:://; s|/.*||' "$T/A.snap" | sort > "$T/A.txt"

echo "the compiler"
crc=0
( cd "$P" && CYRIUS_DCE_VERBOSE=1 "$CC" < prog.cyr > "$T/prog" 2> "$T/dce.txt" ) || crc=$?
check "the fixture project compiles (rc 0)" 0 "$crc"
sed -n 's/^  dead: \(dv_[A-Za-z0-9_]*\)$/\1/p' "$T/dce.txt" | sort > "$T/E.txt"
check "  (floor: the compiler emitted >= 78 fixture fns)" yes "$([ "$(wc -l < "$T/E.txt")" -ge 78 ] && echo yes || echo no)"

echo "axis 1 — every listed fn is one the compiler emitted"
check "listed but not emitted" "" "$(comm -23 "$T/A.txt" "$T/E.txt" | paste -sd' ' -)"

echo "axis 2 — every emitted fn the tool omits is PRIVATE to its file"
notpriv=""
nomit=0
for f in $(comm -13 "$T/A.txt" "$T/E.txt"); do
    nomit=$((nomit + 1))
    printf '%s\nfn dv_probe(): i64 { return %s(); }\nsyscall(60, 0);\n' "$HDR" "$f" > "$P/c.cyr"
    ( cd "$P" && "$CC" < c.cyr > /dev/null 2> "$T/c.err" ) || :
    grep -q "'$f' is private to its file" "$T/c.err" || notpriv="$notpriv $f"
done
check "omitted fns that are NOT private (a miss)" "" "$notpriv"
check "  (the private file's 5 non-public fns are the ones omitted)" 5 "$nomit"

echo "axis 3 — one caller naming every listed fn with its listed arity compiles clean"
{
    printf '%s\nfn dv_calls(): i64 {\n' "$HDR"
    while IFS= read -r e; do
        n=${e##*/}; nm=${e#*::}; nm=${nm%/*}
        args=""; i=0
        while [ "$i" -lt "$n" ]; do if [ -z "$args" ]; then args=0; else args="$args, 0"; fi; i=$((i + 1)); done
        printf '    %s(%s);\n' "$nm" "$args"
    done < "$T/A.snap"
    printf '    return 0;\n}\nsyscall(60, 0);\n'
} > "$P/calls.cyr"
krc=0
( cd "$P" && "$CC" < calls.cyr > /dev/null 2> "$T/calls.err" ) || krc=$?
check "rc 0, and no arity / visibility / undefined diagnostic" "0|" "$krc|$(grep -E "expects|private to its file|undefined function 'dv_" "$T/calls.err" | head -3 | paste -sd' ' -)"
check "  (the caller names every listed fn)" "$(wc -l < "$T/A.snap" | tr -d ' ')" "$(grep -c '^    dv_' "$P/calls.cyr")"
sed 's/^    dv_pt_to_json(0, 0);$/    dv_pt_to_json(0, 0, 0);/' "$P/calls.cyr" > "$P/calls_bad.cyr"
brc=0
( cd "$P" && "$CC" < calls_bad.cyr > /dev/null 2> "$T/bad.err" ) || brc=$?
check "axis 4 — anti-vacuous: one arity off by one is refused" "nonzero 1" "$([ "$brc" -ne 0 ] && echo nonzero || echo zero) $(grep -c "'dv_pt_to_json' expects 2 arguments" "$T/bad.err")"

echo "axis 5 — the literal table"
cat > "$T/expect.snap" <<'EOF'
dv_plain::dv_ad_from_json/1
dv_plain::dv_ad_from_json_str/1
dv_plain::dv_ad_g/1
dv_plain::dv_ad_h/1
dv_plain::dv_ad_set_g/2
dv_plain::dv_ad_set_h/2
dv_plain::dv_ad_to_json/2
dv_plain::dv_da_d/1
dv_plain::dv_da_e/1
dv_plain::dv_da_from_json/1
dv_plain::dv_da_from_json_str/1
dv_plain::dv_da_set_d/2
dv_plain::dv_da_set_e/2
dv_plain::dv_da_to_json/2
dv_plain::dv_de_from_json/1
dv_plain::dv_de_from_json_str/1
dv_plain::dv_de_to_json/2
dv_plain::dv_ea_from_json_str/1
dv_plain::dv_ea_to_json/2
dv_plain::dv_en2_from_json_str/1
dv_plain::dv_en2_to_json/2
dv_plain::dv_en_from_json_str/1
dv_plain::dv_en_to_json/2
dv_plain::dv_gap_from_json/1
dv_plain::dv_gap_from_json_str/1
dv_plain::dv_gap_k/1
dv_plain::dv_gap_m/1
dv_plain::dv_gap_n/1
dv_plain::dv_gap_o/1
dv_plain::dv_gap_set_k/2
dv_plain::dv_gap_set_m/2
dv_plain::dv_gap_set_n/2
dv_plain::dv_gap_set_o/2
dv_plain::dv_gap_to_json/2
dv_plain::dv_ind_from_json/1
dv_plain::dv_ind_from_json_str/1
dv_plain::dv_ind_to_json/2
dv_plain::dv_lb_from_json_str/1
dv_plain::dv_lb_to_json/2
dv_plain::dv_nosep_p/1
dv_plain::dv_nosep_q/1
dv_plain::dv_nosep_r/1
dv_plain::dv_nosep_set_p/2
dv_plain::dv_nosep_set_q/2
dv_plain::dv_nosep_set_r/2
dv_plain::dv_ns_set_u/2
dv_plain::dv_ns_u/1
dv_plain::dv_pb2_from_json/1
dv_plain::dv_pb2_from_json_str/1
dv_plain::dv_pb2_to_json/2
dv_plain::dv_plain/2
dv_plain::dv_pt_from_json/1
dv_plain::dv_pt_from_json_str/1
dv_plain::dv_pt_set_x/2
dv_plain::dv_pt_set_y/2
dv_plain::dv_pt_to_json/2
dv_plain::dv_pt_x/1
dv_plain::dv_pt_y/1
dv_plain::dv_pub_from_json/1
dv_plain::dv_pub_from_json_str/1
dv_plain::dv_pub_to_json/2
dv_plain::dv_pubfn/1
dv_plain::dv_publicfn/0
dv_plain::dv_tab_set_t1/2
dv_plain::dv_tab_set_t2/2
dv_plain::dv_tab_t1/1
dv_plain::dv_tab_t2/1
dv_plain::dv_trail_from_json/1
dv_plain::dv_trail_from_json_str/1
dv_plain::dv_trail_to_json/2
dv_plain::dv_wrapped/4
dv_priv::dv_outer/1
dv_priv::dv_outer2/2
dv_priv::dv_pen_from_json_str/1
dv_priv::dv_pen_to_json/2
dv_priv::dv_shown_from_json/1
dv_priv::dv_shown_from_json_str/1
dv_priv::dv_shown_to_json/2
EOF
check "the fixture snapshot equals the literal table (diff lines)" 0 "$(diff "$T/expect.snap" "$T/A.snap" | grep -c '^[<>]')"

echo "axis 7 — #derive(accessors) on an ENUM refuses the build, and the tool lists nothing for it"
# Every route into the accessors body: the accessors entry, and accessors stacked below a
# Serialize / Deserialize entry. The compiler must refuse each by name (6.6.9 compiled all
# three clean into per-member load/store "fields"), and the tool must not list the enum's
# fns — while still listing the ordinary fn beside it (anti-vacuous: the file WAS scanned).
for order in acc ser_acc de_acc; do
    case $order in
        acc)     dirs='#derive(accessors)' ;;
        ser_acc) dirs='#derive(Serialize)
#derive(accessors)' ;;
        de_acc)  dirs='#derive(Deserialize)
#derive(accessors)' ;;
    esac
    R="$T/rx_$order"
    mkdir -p "$R/src"
    ln -s "$ROOT/lib" "$R/lib"
    printf '%s\nenum dv_rx { RA = 5; RB = 9; RC; }\nfn dv_rx_beside(a) { return a; }\n' "$dirs" > "$R/src/dv_rx.cyr"
    printf '%s\ninclude "src/dv_rx.cyr"\nsyscall(60, 0);\n' "$(printf '%s\n' "$HDR" | grep -v 'src/dv_')" > "$R/prog.cyr"
    rrc=0
    ( cd "$R" && "$CC" < prog.cyr > /dev/null 2> "$R/err" ) || rrc=$?
    check "$order: the compiler refuses it" "1 1" "$rrc $(grep -c 'error: #derive(accessors) applies to a struct; dv_rx is an enum' "$R/err")"
    ( cd "$R" && timeout 20 "$API" --update --scope=project --snapshot="$R/snap" ) > /dev/null 2>&1 || :
    check "$order: the tool lists only the fn beside it" "dv_rx::dv_rx_beside/1" "$(paste -sd' ' - < "$R/snap")"
done

echo "axis 6 — this tree's own surface (floors; the snapshot itself is gated by check.sh)"
( cd "$ROOT" && timeout 30 "$API" --update --snapshot="$T/tree.snap" ) > /dev/null 2>&1 || :
t_ok=""
[ "$(grep -c '^yukti::' "$T/tree.snap")" -ge 300 ] || t_ok="$t_ok yukti-pub-fn"
grep -qx 'sandhi::sandhi_h2_request_send/8' "$T/tree.snap" || t_ok="$t_ok wrapped-signature"
grep -qx 'sigil::ima_status_to_json/2' "$T/tree.snap" || t_ok="$t_ok derived-to_json-arity"
grep -qx 'sigil::ima_status_from_json_str/1' "$T/tree.snap" || t_ok="$t_ok derived-from_json_str"
check "yukti's pub fns, sandhi_h2_request_send/8, sigil ima_status_to_json/2 + _from_json_str/1 all listed" "" "$t_ok"

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: api-surface-derive — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: api-surface-derive — $checks checks"
exit 0
