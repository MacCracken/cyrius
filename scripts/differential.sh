#!/bin/sh
# scripts/differential.sh — the logic-preserving DIFFERENTIAL CORPUS gate (VR-03).
#
# Prove a codegen change is LOGIC-PRESERVING: an OLD cycc and the NEW (working-
# tree) cycc must emit BYTE-IDENTICAL output for every input in a broad, pinned
# corpus. This is the ONLY guard between a backend refactor (regalloc / copy-prop
# / cross-BB DSE / float peephole — the pulled-in v6.3.2x perf arc) and a SILENT
# miscompile: a refactor may legitimately change HOW cycc works internally, but
# must not change WHAT bytes it emits for existing programs.
# (VR-03, docs/development/issues/2026-06-10-verification-coverage-gaps.md.)
#
# Historically this was muscle memory — a ~338-input old-vs-new corpus + DCE
# torture re-assembled by hand each refactor (v6.1.5/.6/.8). Now it is code, so
# it cannot be skipped or mis-remembered.
#
# CONTRACT
#   OLD cycc = the COMMITTED build/cycc at OLD_REF (git show OLD_REF:build/cycc).
#              build/cycc is a tracked binary, so no rebuild is needed — the exact
#              shipped compiler is compared against.
#   NEW cycc = the current working-tree build/cycc. REBUILD IT from your refactored
#              src FIRST (the standard self-host step, e.g.
#                cat src/main.cyr | build/cycc > /tmp/cc && chmod +x /tmp/cc && cp /tmp/cc build/cycc)
#              or the comparison is meaningless (you'd diff OLD against itself).
#
# Each corpus input is compiled by BOTH compilers (raw `cycc < INPUT`, the
# seed-derive convention — cycc resolves `include`s from the repo root) in two
# modes: default and CYRIUS_DCE=1 (dead-code-elimination torture). Exit code +
# stdout bytes are compared:
#   IDENTICAL    both compiled, byte-identical output    -> pass
#   CODEGEN DIFF both compiled (rc 0), output DIFFERS     -> FAIL (the danger case)
#   STATUS DIFF  one compiled, the other did not          -> FAIL (new feature / new bug)
#   both-fail    neither compiled (same non-zero rc)      -> skipped (no binary to diff)
#
# A pure refactor must produce ZERO diffs. A feature-adding change WILL show
# STATUS DIFFs on inputs exercising the new feature — that is EXPECTED; this gate
# is for REFACTORS. Run it, read the diff list, and judge. Manual-trigger: it is
# NOT in check.sh (it needs an OLD_REF and takes minutes).
#
# Usage:
#   sh scripts/differential.sh [OLD_REF]           full gate (OLD_REF default HEAD)
#   sh scripts/differential.sh --quick [OLD_REF]   default mode only (skip DCE torture)
#
# Self-check: with a clean tree and OLD_REF=HEAD, OLD == NEW, so EVERY input must
# be IDENTICAL — a green run then proves the harness itself is sound.

set -u
cd "$(dirname "$0")/.." || exit 2

QUICK=0
SMOKE=0
while [ $# -gt 0 ]; do
    case "${1:-}" in
        --quick) QUICK=1; shift ;;
        --smoke) SMOKE=1; shift ;;   # tiny corpus, asserts the HARNESS works (check.sh rot-guard)
        --*)     echo "ERROR: unknown flag $1"; exit 2 ;;
        *)       break ;;
    esac
done
OLD_REF="${1:-HEAD}"

[ -x build/cycc ] || { echo "ERROR: build/cycc missing — run bootstrap first"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT INT TERM

# --- OLD cycc: the committed binary at OLD_REF -------------------------------
git rev-parse --verify "$OLD_REF" >/dev/null 2>&1 || { echo "ERROR: '$OLD_REF' is not a valid git ref"; exit 2; }
git cat-file -e "$OLD_REF:build/cycc" 2>/dev/null || { echo "ERROR: $OLD_REF has no committed build/cycc to diff against"; exit 2; }
git show "$OLD_REF:build/cycc" > "$T/old_cycc" || { echo "ERROR: could not extract build/cycc from $OLD_REF"; exit 2; }
chmod +x "$T/old_cycc"
OLD="$T/old_cycc"
NEW="build/cycc"
chmod +x "$NEW" 2>/dev/null

OLD_SHA=$(git rev-parse --short "$OLD_REF")
echo "differential corpus gate"
echo "  OLD cycc: $OLD_REF ($OLD_SHA:build/cycc, $(wc -c < "$OLD") B)"
echo "  NEW cycc: working-tree build/cycc ($(wc -c < "$NEW") B)"
if cmp -s "$OLD" "$NEW"; then
    echo "  NOTE: OLD == NEW (identical binaries). This run SELF-CHECKS the harness"
    echo "        (every input must be IDENTICAL). Rebuild build/cycc from your"
    echo "        refactored src for a real differential."
fi

# --- corpus: deterministic, broad, pinned -----------------------------------
CORPUS="$T/corpus.list"
{
    echo src/main.cyr
    echo src/main_aarch64.cyr
    find tests/tcyr -name '*.tcyr'
    find programs -maxdepth 1 -name '*.cyr'
    find benches -name '*.bcyr'
    find fuzz -name '*.fcyr'
} 2>/dev/null | sort -u > "$CORPUS"
N=$(grep -c '' "$CORPUS")
if [ "$SMOKE" -eq 1 ]; then
    head -n 4 "$CORPUS" > "$CORPUS.s" && mv "$CORPUS.s" "$CORPUS"
    N=$(grep -c '' "$CORPUS")
    echo "  corpus:   $N inputs (SMOKE — harness rot-guard, not a real gate)"
else
    echo "  corpus:   $N inputs (src compilers + tcyr + programs + benches + fuzz)"
fi

# --- compare one input in one mode ------------------------------------------
# echoes: IDENTICAL | CODEGEN | STATUS | BOTHFAIL
diff_one() {
    env ${2:+"$2"} "$OLD" < "$1" > "$T/o.out" 2>/dev/null; _orc=$?
    env ${2:+"$2"} "$NEW" < "$1" > "$T/n.out" 2>/dev/null; _nrc=$?
    if [ "$_orc" -ne "$_nrc" ]; then echo STATUS; return; fi
    if [ "$_orc" -ne 0 ]; then echo BOTHFAIL; return; fi
    if cmp -s "$T/o.out" "$T/n.out"; then echo IDENTICAL; else echo CODEGEN; fi
}

# --- run every corpus input in one mode -------------------------------------
run_mode() {
    _name="$1"; _env="$2"
    _id=0; _cg=0; _st=0; _bf=0; _i=0
    : > "$T/diffs_$_name"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        _i=$((_i + 1))
        case "$(diff_one "$f" "$_env")" in
            IDENTICAL) _id=$((_id + 1)) ;;
            CODEGEN)   _cg=$((_cg + 1)); echo "CODEGEN DIFF  $f" >> "$T/diffs_$_name" ;;
            STATUS)    _st=$((_st + 1)); echo "STATUS  DIFF  $f" >> "$T/diffs_$_name" ;;
            BOTHFAIL)  _bf=$((_bf + 1)) ;;
        esac
        [ $((_i % 25)) -eq 0 ] && printf '.'
    done < "$CORPUS"
    printf '\n'
    echo "  [$_name] identical=$_id  codegen-diff=$_cg  status-diff=$_st  both-fail=$_bf  (of $N)"
    if [ -s "$T/diffs_$_name" ]; then
        echo "  --- diffs ($_name) ---"
        sed 's/^/    /' "$T/diffs_$_name" | head -40
        return 1
    fi
    return 0
}

RC=0
echo ""
echo "=== [1/2] default mode ==="
run_mode default "" || RC=1
if [ "$QUICK" -eq 0 ]; then
    echo ""
    echo "=== [2/2] CYRIUS_DCE=1 torture mode ==="
    run_mode dce "CYRIUS_DCE=1" || RC=1
else
    echo ""
    echo "(--quick: skipped the CYRIUS_DCE=1 torture mode — NOT a full gate)"
fi

if [ "$SMOKE" -eq 1 ]; then
    echo ""
    echo "SMOKE OK: differential harness ran end-to-end (git-extract OLD + corpus"
    echo "glob + compile both + cmp + report, default & DCE modes). In --smoke, any"
    echo "codegen diffs are informational — this asserts only that the harness works."
    exit 0
fi

echo ""
echo "================================================================"
if [ "$RC" -eq 0 ]; then
    echo "DIFFERENTIAL: GREEN — OLD ($OLD_SHA) and NEW emit byte-identical output"
    echo "across all $N corpus inputs. The change is logic-preserving."
else
    echo "DIFFERENTIAL: RED — codegen/status diffs found (listed above)."
    echo "A refactor MUST be byte-identical. Investigate each:"
    echo "  D=<input>; \"$OLD\" < \"\$D\" > /tmp/o; build/cycc < \"\$D\" > /tmp/n; cmp /tmp/o /tmp/n"
fi
echo "================================================================"
exit $RC
