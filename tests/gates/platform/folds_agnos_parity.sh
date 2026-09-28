#!/bin/sh
# Gate: every folded stdlib that compiles for Linux must also compile for agnos.
#
# WHY THIS EXISTS. `lib/yukti.cyr` shipped for months with SIX agnos ABI errors —
# `sys_mount` called with 5 arguments against agnos's 0-parameter no-op stub (so yukti
# returned `Ok(mount_result_new(...))` for a mount that never happened), plus three
# length-carrying wrappers called with the bare-pointer POSIX shape. Nothing caught it
# because **no gate ever compiled a folded stdlib for a non-Linux target.** They were
# only ever built for the host. Found at v6.5.1 only because escalating an arity
# mismatch from warning to error made the six fatal instead of silent.
#
# WHY PARITY, not "must compile". The distlib bundles deliberately do NOT carry their
# stdlib dependencies — `cyrius.cyml` documents that the consumer supplies them via
# `[deps] stdlib`. So a bundle failing to build in isolation proves nothing about
# agnos; it usually just means this harness under-included. Comparing the SAME source
# against BOTH targets isolates the real class — target-specific ABI breakage — and is
# immune to include gaps: a dep that fails on both is a harness limitation, and a dep
# that builds on Linux but not agnos is the bug.
#
# COVERAGE IS PARTIAL AND SAID SO OUT LOUD. Deps that cannot be brought up on Linux
# with the preamble below are reported as SKIP with the symbol that stopped them, never
# silently dropped — a gate that hides what it did not check reads as "all clear" when
# it is not. Raising coverage means extending LEAVES until the SKIP list is empty.
#
# MUTATION PROOF (6.6.8 — each fold against its OWN declared deps, see below):
#   * the pre-6.6.8 shared preamble restored (sakshi, sigil, patra, yukti back in LEAVES) ->
#     RED four times ("the shared LEAVES preamble includes the fold …") and on the
#     anti-vacuous row: with patra always in scope, yukti-without-patra borrows invisibly.
#   * yukti dropped from vani's FOLD_DEPS row -> RED, "vani uses 'YUKTI_AUDIO_CAPTURE' from
#     yukti, which vani does not declare" (and, locally, the row disagrees with vani's own
#     cyrius.cyml).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
# v6.6.6: CHECK THE TEMP DIR. Unchecked, a failed mktemp left D empty, every probe path became
# root-absolute (/lin.cyr, /ag.err), each Linux build "failed", all 12 folds were classed SKIP —
# and the gate PASSED "0/12 … (12 skipped)". CHANGELOG [6.6.6]
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: folds-agnos-parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

# ⛔ 6.6.8 — EACH FOLD IS BUILT AGAINST THE STDLIB LEAVES PLUS ITS OWN DECLARED FOLD DEPS,
# AND NOTHING ELSE. This gate used to put ONE preamble — the leaves AND sakshi, sigil, patra,
# yukti — ahead of every fold. So a fold could compile only because ANOTHER fold it never
# declared happened to be in scope, and the gate read green over it: that is exactly how mabda
# and vani built for agnos on yukti's placeholder `SYS_IOCTL = 9001` (yukti 2.3.12 deleted it,
# and both broke), and how sandhi borrowed yukti's `SYS_SOCKET` on PE. The preamble is now
# LEAVES only, each probe adds the fold's declared closure (FOLD_DEPS, below — the fold
# entries of each sibling's `cyrius.cyml` `stdlib = [...]` / `[deps.*]`), and a symbol the
# compiler reports undefined that some OTHER fold defines is a FAIL naming the borrow, on
# Linux as well as agnos. CHANGELOG [6.6.8]
#
# The leaves, dependency-ordered. `tests/gates/platform/pe_reloc_cap_full_stdlib.sh` extracts
# this block (from `LEAVES='` to the `lib/tls.cyr` line) — keep that shape.
LEAVES='include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/result.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/fnptr.cyr"
include "lib/tagged.cyr"
include "lib/mmap.cyr"
include "lib/net.cyr"
include "lib/ws.cyr"
include "lib/math.cyr"
include "lib/chrono.cyr"
include "lib/thread.cyr"
include "lib/thread_local.cyr"
include "lib/process.cyr"
include "lib/dynlib.cyr"
include "lib/fdlopen.cyr"
include "lib/tls.cyr"'
# Leaves two folds declare that the preamble above never carried: sandhi's `async`, and
# niyama's `unicode` normalization tables (it was SKIPped for a missing `NFD` until 6.6.8).
EXTRA_LEAVES='include "lib/async.cyr"
include "lib/unicode/_decode.cyr"
include "lib/unicode/categories.cyr"
include "lib/unicode/_categories_data.cyr"
include "lib/unicode/casefold.cyr"
include "lib/unicode/_casefold_data.cyr"
include "lib/unicode/normalize.cyr"
include "lib/unicode/_normalize_data.cyr"'

# The fold set is DERIVED from docs/ecosystem.md's fold table (the same rows
# fold_table_matches_vendored.sh reads), never listed here.
FOLDS=$(grep -oE '^\| `lib/[a-z0-9_]+\.cyr` \|' "$ROOT/docs/ecosystem.md" \
    | sed -E 's/^\| `lib\/([a-z0-9_]+)\.cyr`.*/\1/' | tr '\n' ' ')
NFOLDS=$(echo $FOLDS | wc -w)

# Each fold's DECLARED fold dependencies — the fold names in its sibling repo's `cyrius.cyml`
# (`stdlib = [...]` and `[deps.*]`) at the folded version. A fold missing from this table is a
# FAIL (say what it depends on); the table is checked against the sibling manifests below
# whenever the checkout is at the folded version.
fold_deps() {
    case "$1" in
        sigil)  echo "bayan sakshi" ;;
        patra)  echo "sakshi" ;;
        mabda)  echo "sakshi sankoch" ;;
        yantra) echo "bayan sakshi sigil sandhi" ;;
        vani)   echo "sakshi patra yukti" ;;
        sandhi) echo "sakshi sigil" ;;
        yukti)  echo "sakshi patra" ;;
        sankoch|sakshi|bayan|ganita|niyama) echo "" ;;
        *) echo "UNDECLARED" ;;
    esac
}

# The transitive closure of a fold's declared deps, dependencies FIRST. Iterative on purpose:
# POSIX sh has no `local`, so a recursive walk's loop variable is clobbered by the call it
# makes (the first cut of this lost yukti from vani's closure exactly that way).
closure_of() {
    _set=$(fold_deps "$1")
    while :; do
        _new="$_set"
        for _c in $_set; do _new="$_new $(fold_deps "$_c")"; done
        _new=$(echo $_new | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
        [ "$_new" = "$(echo $_set | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')" ] && break
        _set=$_new
    done
    _set=$(echo $_set | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
    # Emit in dependency order: a fold once all of its own deps are out.
    _out=""
    _left="$_set"
    while [ -n "$(echo $_left)" ]; do
        _next=""
        _prog=0
        for _c in $_left; do
            _ready=1
            for _dp in $(fold_deps "$_c"); do
                case " $_out " in *" $_dp "*) ;; *) _ready=0 ;; esac
            done
            if [ "$_ready" = "1" ]; then _out="$_out $_c"; _prog=1; else _next="$_next $_c"; fi
        done
        [ "$_prog" = "1" ] || { _out="$_out $_next"; break; }   # a cycle: emit the rest as-is
        _left=$_next
    done
    echo $_out
}

# Which fold (other than those allowed) defines `sym`? Empty when none does.
_definer() {  # $1 sym, $2 allowed fold names
    for _f in $FOLDS; do
        case " $2 " in *" $_f "*) continue ;; esac
        if grep -qE "^[[:space:]]*(pub[[:space:]]+|public[[:space:]]+)?(fn|var)[[:space:]]+$1([^A-Za-z0-9_]|\$)|^[[:space:]]*$1[[:space:]]*=[[:space:]]*[-0-9]" "lib/$_f.cyr" 2>/dev/null; then
            echo "$_f"; return 0
        fi
    done
    return 0
}

# Build fold $1 with closure $2 for Linux and agnos. Prints findings; returns 0 ok, 1 FAIL,
# 2 SKIP (not buildable on Linux for a reason no fold explains — a harness leaf gap).
probe() {
    _d=$1; _cl=$2
    { printf '%s\n%s\n' "$LEAVES" "$EXTRA_LEAVES"
      for _x in $_cl; do printf 'include "lib/%s.cyr"\n' "$_x"; done
      printf 'include "lib/%s.cyr"\nfn main(): i64 { return 0; }\n' "$_d"; } > "$D/p.cyr"
    "$CC" < "$D/p.cyr" > /dev/null 2>"$D/lin.err"; _lrc=$?
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$D/p.cyr" > /dev/null 2>"$D/ag.err"; _arc=$?
    # A symbol undefined on either target that an UNDECLARED fold defines is a borrow —
    # whether it stopped the build (a variable) or became a trap stub (a function: only a
    # warning, so the build "succeeds").
    _borrow=0
    for _sym in $(cat "$D/lin.err" "$D/ag.err" | grep -oE "undefined (variable|function) '[A-Za-z_0-9]+'" \
            | sed "s/.*'\(.*\)'/\1/" | sort -u); do
        _by=$(_definer "$_sym" "$_d $_cl")
        if [ -n "$_by" ]; then
            echo "  FAIL: $_d uses '$_sym' from $_by, which $_d does not declare (declared: ${_cl:-none}) — cross-fold borrowing"
            _borrow=1
        fi
    done
    [ "$_borrow" = "1" ] && return 1
    if [ "$_lrc" != "0" ]; then
        _sym=$(grep -m1 -oE "undefined (variable|function) '[A-Za-z_0-9]+'" "$D/lin.err" || true)
        LAST_SKIP="${_sym:-see stderr}"
        return 2
    fi
    if [ "$_arc" != "0" ]; then
        # Attribute to the file the compiler names: with declared closures a break in a DEP
        # still shows up under every fold that declares it.
        culprit=$(grep -m1 -oE "^error:lib/[a-z_0-9/]+\.cyr" "$D/ag.err" | sed 's/^error://' || true)
        if [ -n "$culprit" ] && [ "$culprit" != "lib/$_d.cyr" ]; then
            echo "  FAIL: probe '$_d' builds for Linux but NOT for agnos — break is in $culprit (a declared dep or a leaf, not $_d itself):"
        else
            echo "  FAIL: $_d builds for Linux but NOT for agnos — target-specific ABI break:"
        fi
        grep -E "^error" "$D/ag.err" | head -6 | sed 's/^/      /'
        return 1
    fi
    return 0
}

checked=0
skipped=0
fails=0
skiplist=""

# The preamble itself carries no fold — the whole point.
for _f in $FOLDS; do
    if printf '%s\n%s\n' "$LEAVES" "$EXTRA_LEAVES" | grep -q "lib/$_f\.cyr"; then
        echo "  FAIL: the shared LEAVES preamble includes the fold lib/$_f.cyr — every probe would borrow from it"
        fails=$((fails + 1))
    fi
done

for d in $FOLDS; do
    dd=$(fold_deps "$d")
    if [ "$dd" = "UNDECLARED" ]; then
        echo "  FAIL: fold '$d' (docs/ecosystem.md) has no FOLD_DEPS row — declare its fold dependencies in this gate"
        fails=$((fails + 1))
        continue
    fi
    # Where the sibling checkout is AT the folded version, its manifest must agree with the
    # table. (Not reachable in CI, and a checkout ahead of the fold is not the fold — both are
    # said, never silently skipped.)
    sib="$HOME/Repos/$d"
    folded=$(sed -nE "s/^\| \`lib\/${d}\.cyr\` \|[^|]*\| ${d} ([0-9][0-9.]*) \|.*/\1/p" "$ROOT/docs/ecosystem.md" | head -1)
    if [ -f "$sib/cyrius.cyml" ] && [ -f "$sib/VERSION" ] && [ "$(tr -d '[:space:]' < "$sib/VERSION")" = "$folded" ]; then
        man=$( { awk '/^stdlib[[:space:]]*=[[:space:]]*\[/{on=1} on{print} on && /\]/{exit}' "$sib/cyrius.cyml" \
                   | sed 's/#.*//' | tr -d '[]",=' | tr ' ' '\n'
                 grep -oE '^\[deps\.[a-z_]+\]' "$sib/cyrius.cyml" | sed -E 's/^\[deps\.([a-z_]+)\]/\1/'; } \
               | grep -xE "$(echo $FOLDS | tr ' ' '|')" | grep -vx "$d" | sort -u | tr '\n' ' ')
        tab=$(echo $dd | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
        if [ "$man" != "$tab" ]; then
            echo "  FAIL: $d's FOLD_DEPS row [${tab% }] disagrees with ~/Repos/$d/cyrius.cyml at $folded [${man% }]"
            fails=$((fails + 1))
        fi
    fi
    rc=0
    probe "$d" "$(closure_of "$d")" || rc=$?
    case "$rc" in
        0) checked=$((checked + 1)) ;;
        1) checked=$((checked + 1)); fails=$((fails + 1)) ;;
        2) skipped=$((skipped + 1))
           skiplist="$skiplist
    SKIP: $d — not buildable in this harness on Linux either ($LAST_SKIP); extend LEAVES to cover it" ;;
    esac
done

# ANTI-VACUOUS: the borrow detector must fire. yukti uses patra's constants (it declares
# patra); built WITHOUT patra it has to be reported as borrowing from patra.
if [ -f lib/yukti.cyr ] && [ -f lib/patra.cyr ]; then
    rc=0
    probe yukti "sakshi" > "$D/anti.out" 2>&1 || rc=$?
    if [ "$rc" != "1" ] || ! grep -q "from patra, which yukti does not declare" "$D/anti.out"; then
        echo "  FAIL: anti-vacuous — yukti built WITHOUT its declared patra was not reported as a borrow (rc $rc)"
        sed 's/^/      /' "$D/anti.out" | head -4
        fails=$((fails + 1))
    fi
fi

# Never silent about what was not covered.
if [ "$skipped" != "0" ]; then
    printf '%s\n' "  $skipped of $NFOLDS folds NOT checked (reported, not hidden):$skiplist"
fi

# v6.6.6: a FLOOR on what was actually checked. Skips are reported, not hidden — but a run in
# which (nearly) every fold was skipped has checked nothing and must not read as PASS. Since
# 6.6.8 a normal run checks 12 of 12 (niyama gained its unicode leaves); the floor is 10, so a
# fold falling out of the harness is tolerated and a broken harness is not.
# Mutation (6.6.6): build/cycc replaced by `exit 1` in a scratch copy -> this gate FAILs "0/12
# checked"; the 6.6.5 gate PASSed the same run. TMPDIR=/nonexistent and a chmod-555 TMPDIR -> FAIL.
if [ "$checked" -lt 10 ]; then
    echo "FAIL: folds-agnos-parity — only $checked/$NFOLDS folds were checked (floor 10; $skipped skipped) — the harness, not the folds, is broken"
    exit 1
fi

if [ "$fails" = "0" ]; then
    echo "PASS: folds-agnos-parity — $checked/$NFOLDS folded stdlibs build for BOTH Linux and agnos, each against the leaves plus its OWN declared fold deps only ($skipped skipped)"
    exit 0
fi
echo "FAIL: folds-agnos-parity — $fails of $checked checked folds break on agnos"
exit 1
