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
# ⭐ 6.6.19 R3 — EACH FOLD IS INCLUDED ALONE: no hand-supplied stdlib leaves. Until 6.6.18 the
# distlib bundles stripped their stdlib includes and the consumer supplied them, so this gate
# carried a LEAVES preamble (26 modules) ahead of every probe, and a fold its preamble could not
# bring up on Linux was a SKIP ("a harness limitation"). Since 6.6.19 R1 every bundle begins with
# a compile-verified `# Requires` include block, so a probe is the fold's declared FOLD deps (the
# closure below — the bundle does not include another fold it was not built against) plus the
# fold, and NOTHING else. A fold that does not build for Linux that way, or that leaves any
# function undefined, is a FAIL — its requires block (or a declared dep's) is short — not a SKIP:
# there is no harness left to blame. A leaf the old preamble supplied would have hidden exactly
# that, which is why no preamble is allowed back.
#
# WHY PARITY still matters: the same probe built for agnos isolates target-specific ABI breakage
# (the yukti class above) — a fold that builds for Linux but not agnos is the bug.
#
# MUTATION PROOF (6.6.8 — each fold against its OWN declared deps, see below):
#   * the pre-6.6.8 shared preamble restored (sakshi, sigil, patra, yukti back in LEAVES) ->
#     RED four times ("the shared LEAVES preamble includes the fold …") and on the
#     anti-vacuous row: with patra always in scope, yukti-without-patra borrows invisibly.
#   * yukti dropped from vani's FOLD_DEPS row -> RED, "vani uses 'YUKTI_AUDIO_CAPTURE' from
#     yukti, which vani does not declare" (and, locally, the row disagrees with vani's own
#     cyrius.cyml).
# MUTATION PROOF (6.6.19 R3, measured):
#   * `include "lib/random.cyr"` removed from lib/sigil.cyr's requires block -> RED, "sigil
#     leaves 'random_bytes' undefined" (the pre-R3 gate stayed GREEN: its LEAVES preamble
#     supplied random through lib/tls.cyr) — the leaves are not hand-supplied any more.
#   * the include walk blinded (its grep never matches) -> RED on the anti-vacuous row
#     (the walk from lib/sandhi.cyr does not reach lib/sigil.cyr).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
# v6.6.6: CHECK THE TEMP DIR. Unchecked, a failed mktemp left D empty, every probe path became
# root-absolute (/lin.cyr, /ag.err), each Linux build "failed", all 12 folds were classed SKIP —
# and the gate PASSED "0/12 … (12 skipped)". CHANGELOG [6.6.6]
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: folds-agnos-parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

# ⛔ 6.6.8 — EACH FOLD IS BUILT AGAINST ITS OWN DECLARED FOLD DEPS AND NOTHING ELSE. This gate
# used to put ONE preamble — the leaves AND sakshi, sigil, patra, yukti — ahead of every fold. So
# a fold could compile only because ANOTHER fold it never declared happened to be in scope, and
# the gate read green over it: that is exactly how mabda and vani built for agnos on yukti's
# placeholder `SYS_IOCTL = 9001` (yukti 2.3.12 deleted it, and both broke), and how sandhi
# borrowed yukti's `SYS_SOCKET` on PE. Each probe adds the fold's declared closure (FOLD_DEPS,
# below — the fold entries of each sibling's `cyrius.cyml` `stdlib = [...]` / `[deps.*]`), and a
# symbol the compiler reports undefined that some OTHER fold defines is a FAIL naming the borrow,
# on Linux as well as agnos. CHANGELOG [6.6.8]. Since a bundle now INCLUDES what it needs (6.6.19),
# a borrow can also arrive as an include: the walk below follows every include from the fold
# (through first-party modules, e.g. yantra -> lib/ws.cyr -> bayan) and fails on a fold reached
# that the fold does not declare.

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

# The folds an include walk from lib/$1.cyr reaches (other than $1), through first-party
# modules; a fold reached is recorded and not walked (its own deps are its own row).
_folds_reached() {
    _seen=" $1 "; _queue="$1"; _hit=""
    while [ -n "$(echo $_queue)" ]; do
        _nq=""
        for _m in $_queue; do
            for _i in $(grep -hoE '^[[:space:]]*include "lib/[a-z0-9_/]+\.cyr"' "lib/$_m.cyr" 2>/dev/null \
                    | sed -E 's/.*"lib\/([a-z0-9_\/]+)\.cyr"/\1/'); do
                case "$_seen" in *" $_i "*) continue ;; esac
                _seen="$_seen$_i "
                case " $FOLDS " in
                    *" $_i "*) _hit="$_hit $_i" ;;
                    *) _nq="$_nq $_i" ;;
                esac
            done
        done
        _queue=$_nq
    done
    echo $_hit
}

# Build fold $1 with closure $2 for Linux and agnos — the closure's folds, then the fold, and
# nothing else. Prints findings; returns 0 ok, 1 FAIL.
probe() {
    _d=$1; _cl=$2
    { for _x in $_cl; do printf 'include "lib/%s.cyr"\n' "$_x"; done
      printf 'include "lib/%s.cyr"\nfn main(): i64 { return 0; }\n' "$_d"; } > "$D/p.cyr"
    "$CC" < "$D/p.cyr" > /dev/null 2>"$D/lin.err"; _lrc=$?
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$D/p.cyr" > /dev/null 2>"$D/ag.err"; _arc=$?
    # A symbol undefined on either target that an UNDECLARED fold defines is a borrow —
    # whether it stopped the build (a variable) or became a trap stub (a function: only a
    # warning, so the build "succeeds").
    # Any other undefined symbol is the bundle's own: with no hand-supplied leaves, its requires
    # block (or a declared dep's) is short. An undefined FUNCTION is a ud2 trap stub, not a link
    # error, so it fails here even when the build "succeeds".
    _bad=0
    for _sym in $(cat "$D/lin.err" "$D/ag.err" | grep -oE "undefined (variable|function) '[A-Za-z_0-9]+'" \
            | sed "s/.*'\(.*\)'/\1/" | sort -u); do
        _by=$(_definer "$_sym" "$_d $_cl")
        if [ -n "$_by" ]; then
            echo "  FAIL: $_d uses '$_sym' from $_by, which $_d does not declare (declared: ${_cl:-none}) — cross-fold borrowing"
        else
            echo "  FAIL: $_d leaves '$_sym' undefined with only its declared fold deps (${_cl:-none}) in scope — its # Requires block is short; a bundle must compile alone"
        fi
        _bad=1
    done
    [ "$_bad" = "1" ] && return 1
    # A fold reached through an include that the fold does not declare is a borrow too.
    for _r in $(_folds_reached "$_d"); do
        case " $_cl " in
            *" $_r "*) : ;;
            *) echo "  FAIL: $_d reaches lib/$_r.cyr through its includes without declaring it (declared: ${_cl:-none}) — cross-fold borrowing"; _bad=1 ;;
        esac
    done
    [ "$_bad" = "1" ] && return 1
    if [ "$_lrc" != "0" ]; then
        echo "  FAIL: $_d does not build for Linux with only its declared fold deps (${_cl:-none}) in scope:"
        grep -E "^error" "$D/lin.err" | head -4 | sed 's/^/      /'
        return 1
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
fails=0

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
    checked=$((checked + 1))
    [ "$rc" = 0 ] || fails=$((fails + 1))
done

# ANTI-VACUOUS: the borrow detectors must fire. yukti uses patra's constants (it declares
# patra); built WITHOUT patra it has to be reported as borrowing from patra. And sandhi's
# bundle includes sigil (a declared dep), so the include walk from sandhi has to reach it — a
# walk that reaches nothing would pass every fold's include check while checking nothing.
if [ -f lib/yukti.cyr ] && [ -f lib/patra.cyr ]; then
    rc=0
    probe yukti "sakshi" > "$D/anti.out" 2>&1 || rc=$?
    if [ "$rc" != "1" ] || ! grep -q "from patra, which yukti does not declare" "$D/anti.out"; then
        echo "  FAIL: anti-vacuous — yukti built WITHOUT its declared patra was not reported as a borrow (rc $rc)"
        sed 's/^/      /' "$D/anti.out" | head -4
        fails=$((fails + 1))
    fi
fi

case " $(_folds_reached sandhi) " in
    *" sigil "*) : ;;
    *) echo "  FAIL: anti-vacuous — the include walk from lib/sandhi.cyr did not reach lib/sigil.cyr (sandhi's requires block includes it): the walk is blind"
       fails=$((fails + 1)) ;;
esac

# v6.6.6: a FLOOR on what was actually checked — a run that checked (nearly) nothing must not
# read as PASS. Since 6.6.19 there is no SKIP: every fold in the table is checked (12 of 12).
# Mutation (6.6.6): build/cycc replaced by `exit 1` in a scratch copy -> this gate FAILs "0/12
# checked"; the 6.6.5 gate PASSed the same run. TMPDIR=/nonexistent and a chmod-555 TMPDIR -> FAIL.
if [ "$checked" -lt 10 ]; then
    echo "FAIL: folds-agnos-parity — only $checked/$NFOLDS folds were checked (floor 10) — the harness, not the folds, is broken"
    exit 1
fi

if [ "$fails" = "0" ]; then
    echo "PASS: folds-agnos-parity — $checked/$NFOLDS folded stdlibs build for BOTH Linux and agnos ALONE (no stdlib leaves supplied), each with only its OWN declared fold deps in scope, no undefined symbol and no undeclared fold reached"
    exit 0
fi
echo "FAIL: folds-agnos-parity — $fails of $checked checked folds fail above (an agnos ABI break, a short requires block, or a cross-fold borrow)"
exit 1
