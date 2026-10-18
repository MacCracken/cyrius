#!/bin/sh
# check: serial — the whole .tcyr corpus compiled and run once under CYRIUS_IR=3 + CYRIUS_DCE=1 (~5 min of CPU, ~45 s on 8 workers): it runs its own workers (half the CPUs, at most 8 — the pool's rule), so the parallel check.sh runs it alone, after its pool (6.7.15)
# tests/gates/ir-opt/ir3_dce_corpus.sh — 6.7.15
#
# THE CORPUS RUNS CLEAN UNDER CYRIUS_IR=3 AND CYRIUS_DCE=1 TOGETHER. Each mode has corpus legs of
# its own (scripts/differential.sh's CYRIUS_DCE=1 torture mode; coverage_mode_corpus.sh's IR=3 leg,
# which compares and does not require exit 0), and the combination had none. It is the one that
# matters for a class of defect: the IR=3 seam (src/main.cyr, `wp_compact` before FIXUP) moves code
# that FIXUP's dead-code pass then reads through positions recorded at parse time, and only
# CYRIUS_DCE=1 acts on what that pass concludes. Under IR=3 alone a stale table shows only as a
# changed `N unreachable fns` note, which nothing compares. 6.7.14's stale losing-body ranges (the
# `_wp_fnr_shift` fix) killed crossos/fn_redefinition_last_wins.tcyr with SIGILL under the pair and
# passed every gate and the lane's full check.sh.
#
#   A  anti-vacuous — the worker (`_one`) and the judge (`_judge`) the corpus loop uses, on planted
#      inputs: A1 a planted compiler (a shim over the real one) whose output exits 3 only under the
#      flag pair is RED "exits 3" — the gate hands the compiler BOTH flags and grades the exit (no
#      predefine shows the flags to a source, so the plant is the compiler, not the program); A2 the
#      shim without the flags builds the control and it exits 0 (the delta is the pair's alone); A3
#      the control through the real compiler is clean; A4 a pinned result that passes is RED "now
#      passes, unpin"; A5 a pinned result that still fails is reported, not red; A6 a pin naming no
#      corpus file is RED
#   C  every tests/tcyr/**/*.tcyr compiled with CYRIUS_IR=3 CYRIUS_DCE=1 (rc 0, a non-empty binary)
#      and run in the check driver's .tcyr environment (CYRIUS_TEST_ENV=1, a throwaway HOME holding
#      a copy of the dlopen-helper — programs/checks/selfhost.cyr `_tcyr_envp`; the tree root as
#      cwd; the driver's 120 s deadline): exit 0, unless pinned below
#   F  the floor: the files walked are at least tests/tcyr/CORPUS_FLOOR line 1 (its only copy) — a
#      reader that went blind fails here instead of passing over nothing
#
# PINNED (the expected failures) — one line each, `<path under tests/tcyr> <the issues/ file that
# owns it>`. EMPTY since 6.7.15: derive/derive_enum_inside_ifdef.tcyr (139) was the last, fixed by
# the IR=3 const-fold bite (issues/2026-10-16-ir3-const-fold-over-dead-store-nop-fills-its-
# immediate.md). The list can only shrink: a pinned file that passes is RED until it is unpinned.
#
# MUTATION LEDGER (6.7.15; CYCC=<the 2-stage mutant cycc>):
#   M1  `_wp_fnr_shift(S);` dropped from wp_compact (src/common/ir.cyr) -> RED C:
#       crossos/fn_redefinition_last_wins.tcyr exits 132
#   M2  the IR=3 const-fold fix reverted (`_ir_fold_consume_span` not called) -> RED C:
#       derive/derive_enum_inside_ifdef.tcyr exits 139
#   M3  tests/tcyr/CORPUS_FLOOR raised past the corpus -> RED F (the reader is blind)
#   M4  the worker compiles without CYRIUS_DCE=1 -> RED A1 (the shim's plant never fires)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELF="$ROOT/tests/gates/ir-opt/$(basename "$0")"
CC=${CYCC:-"$ROOT/build/cycc"}
G=ir3_dce_corpus
P="${PATH:-/usr/bin:/bin}"

# _run <bin> -> RRC: the check driver's .tcyr environment and cwd (the tree root), its deadline. In a
# subshell (the `exit` keeps it a shell, not an exec of `timeout`) whose stderr is dropped: a crash
# is an exit status here (128 + the signal), not the shell's job message in the gate's log.
_run() {
    chmod +x "$1"
    RRC=0
    (env -i CYRIUS_TEST_ENV=1 HOME="$TH" timeout 120 "$1" < /dev/null > "$1.out" 2>&1; exit $?) 2> /dev/null || RRC=$?
}
# _one <cc> <id> <src>: <src> compiled by <cc> under the flag pair and run; prints `<crc> <rrc>` —
# crc the compile status (`E` when it left an empty binary), rrc the exit ('-' when not run).
_one() {
    b="$T/b/$2"
    crc=0; env -i PATH="$P" CYRIUS_IR=3 CYRIUS_DCE=1 "$1" < "$3" > "$b" 2> "$b.err" || crc=$?
    rrc=-
    if [ "$crc" = 0 ]; then
        if [ -s "$b" ]; then _run "$b"; rrc=$RRC; else crc=E; fi
    fi
    printf '%s %s\n' "$crc" "$rrc"
    rm -f "$b" "$b.err" "$b.out"
}
# _judge <label> <result file> <pin: the owning issue, or empty> -> WHY (empty: clean or an expected
# failure), PINF (1: pinned and still failing, as expected), FWHY (the failure, empty when it passed).
_judge() {
    jc=""; jr=""; read -r jc jr < "$2" || true
    FWHY=""; WHY=""; PINF=0
    if [ "$jc" = E ]; then FWHY="compiles to an empty binary"
    elif [ "$jc" != 0 ]; then FWHY="does not compile (rc $jc)"
    elif [ "$jr" = 124 ]; then FWHY="did not finish in 120 s"
    elif [ "$jr" != 0 ]; then FWHY="exits $jr"; fi
    if [ -n "$3" ]; then
        if [ -n "$FWHY" ]; then PINF=1
        else WHY="P $1 is pinned ($3) but now passes under CYRIUS_IR=3 CYRIUS_DCE=1 — unpin it"; fi
    elif [ -n "$FWHY" ]; then
        WHY="C $1 $FWHY under CYRIUS_IR=3 CYRIUS_DCE=1"
    fi
}
# _pins_unmatched <pin file> <corpus list>: each pinned path that names no corpus file, one a line.
_pins_unmatched() {
    while read -r pp pi; do
        case "$pp" in ''|'#'*) continue ;; esac
        if ! grep -qxF "tests/tcyr/$pp" "$2"; then echo "$pp"; fi
    done < "$1"
}

# ── a worker: one corpus file (`xargs` below runs this script as `--one <id> <src>`) ─────────────
if [ "${1:-}" = "--one" ]; then
    T=${IR3DCE_T:?}; TH=${IR3DCE_HOME:?}
    cd "$ROOT" || exit 1
    _one "$CC" "$2" "$3" > "$T/r/$2"
    exit 0
fi

[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT" || exit 1
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS CYRIUS_DCE CYRIUS_IR
mkdir -p "$T/b" "$T/r" "$T/p"
fails=0
rows=0
ok()  { rows=$((rows + 1)); echo "  ok   $1"; }
bad() { rows=$((rows + 1)); echo "  FAIL $1"; fails=$((fails + 1)); }

# The pinned expected failures (see the header). Empty: every corpus file must exit 0.
cat > "$T/pinned" <<'EOF'
# <path under tests/tcyr> <issues/ file>
EOF

# The driver's .tcyr environment: a throwaway HOME with a COPY of the helper the toolchain under
# test would use (read, never written).
TH="$T/tcyr_home"
mkdir -p "$TH/.cyrius"
for _h in "${CYRIUS_HOME:-}/dlopen-helper" "${HOME:-}/.cyrius/dlopen-helper"; do
    if [ -f "$_h" ]; then cp "$_h" "$TH/.cyrius/dlopen-helper" 2>/dev/null && break; fi
done
# The workers: half the online CPUs, at most 8 (check.sh's pool rule).
J=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
case "$J" in ''|*[!0-9]*) J=2 ;; esac
J=$((J / 2)); [ "$J" -gt 8 ] && J=8; [ "$J" -lt 1 ] && J=1
FL=$(sed -n 1p tests/tcyr/CORPUS_FLOOR 2>/dev/null || true)
case "$FL" in ''|*[!0-9]*) echo "FAIL: $G: tests/tcyr/CORPUS_FLOOR line 1 is '$FL', not a number"; exit 1 ;; esac

# ── A: the worker and the judge on planted inputs ────────────────────────────────────────────────
printf 'fn f(): i64 { return 0; }\nsyscall(60, f());\n' > "$T/p/ctl.cyr"
printf 'syscall(60, 3);\n' > "$T/p/three.cyr"
cat > "$T/p/shim" <<EOF
#!/bin/sh
# planted: under exactly the flag pair this "compiler" builds a program that exits 3
if [ "\${CYRIUS_IR:-}" = 3 ] && [ "\${CYRIUS_DCE:-}" = 1 ]; then exec "$CC" < "$T/p/three.cyr"; fi
exec "$CC"
EOF
chmod +x "$T/p/shim"
_one "$T/p/shim" a1 "$T/p/ctl.cyr" > "$T/r/a1"
_judge ctl.cyr "$T/r/a1" ""
case "$WHY" in
    "C ctl.cyr exits 3 under"*) ok "A1 a planted compiler whose output exits 3 only under the flag pair: '$WHY'" ;;
    *) bad "A1 the planted pair-only exit 3: judged '${WHY:-clean}' (want 'C ctl.cyr exits 3 ...') — does the worker pass BOTH flags?" ;;
esac
a2=0; env -i PATH="$P" "$T/p/shim" < "$T/p/ctl.cyr" > "$T/b/a2" 2> /dev/null || a2=$?
a2r=-; if [ "$a2" = 0 ] && [ -s "$T/b/a2" ]; then _run "$T/b/a2"; a2r=$RRC; fi
if [ "$a2r" = 0 ]; then ok "A2 the same shim without the flags builds the control, which exits 0 (the delta is the pair's alone)"
else bad "A2 the shim without the flags: compile rc $a2, exit $a2r (want 0)"; fi
_one "$CC" a3 "$T/p/ctl.cyr" > "$T/r/a3"
_judge ctl.cyr "$T/r/a3" ""
if [ -z "$WHY" ] && [ -z "$FWHY" ]; then ok "A3 the control through the real compiler under the pair is clean"
else bad "A3 the control under the pair: judged '${WHY:-$FWHY}' (want clean)"; fi
printf '0 0\n' > "$T/r/a4"
_judge planted.tcyr "$T/r/a4" "issues/planted.md"
case "$WHY" in
    "P planted.tcyr is pinned (issues/planted.md) but now passes"*) ok "A4 a pinned file that passes: '$WHY'" ;;
    *) bad "A4 a pinned file that passes: judged '${WHY:-clean}' (want 'P ... now passes — unpin it')" ;;
esac
printf '0 139\n' > "$T/r/a5"
_judge planted.tcyr "$T/r/a5" "issues/planted.md"
if [ -z "$WHY" ] && [ "$PINF" = 1 ]; then ok "A5 a pinned file that still fails ($FWHY) is an expected failure, reported, not red"
else bad "A5 a pinned file that still fails: judged '${WHY:-clean}', PINF $PINF (want an expected failure)"; fi
printf 'tests/tcyr/lang/x.tcyr\n' > "$T/p/a6.list"
printf '# a comment\nlang/x.tcyr issues/a.md\nlang/gone.tcyr issues/b.md\n' > "$T/p/a6.pins"
a6=$(_pins_unmatched "$T/p/a6.pins" "$T/p/a6.list" | tr '\n' ' ')
if [ "$a6" = "lang/gone.tcyr " ]; then ok "A6 a pin naming no corpus file is found ('lang/gone.tcyr'); a pin naming one is not"
else bad "A6 the unmatched pins read '$a6' (want 'lang/gone.tcyr ')"; fi

# ── C / F: the corpus, through the workers ───────────────────────────────────────────────────────
find tests/tcyr -name '*.tcyr' | LC_ALL=C sort > "$T/list"
NF=$(grep -c . "$T/list" || true)
if grep -q '[[:space:]]' "$T/list"; then bad "C: a .tcyr path holds whitespace (the worker list splits on it): $(grep -m1 '[[:space:]]' "$T/list")"; fi
awk '{ print NR, $0 }' "$T/list" > "$T/jobs"
t0=$(date +%s)
IR3DCE_T="$T" IR3DCE_HOME="$TH" CYCC="$CC" xargs -P "$J" -n 2 sh "$SELF" --one < "$T/jobs"
t1=$(date +%s)
n=0; npass=0; nbad=0; nmiss=0; pinned_f=""
while read -r f; do
    n=$((n + 1))
    if [ ! -f "$T/r/$n" ]; then nmiss=$((nmiss + 1)); bad "C $f: the worker left no result"; continue; fi
    rel=${f#tests/tcyr/}
    pin=$(awk -v p="$rel" '$1 == p { print $2; exit }' "$T/pinned")
    _judge "$f" "$T/r/$n" "$pin"
    if [ -n "$WHY" ]; then nbad=$((nbad + 1)); bad "$WHY"
    elif [ "$PINF" = 1 ]; then pinned_f="$pinned_f $rel ($FWHY; $pin)"
    else npass=$((npass + 1)); fi
done < "$T/list"
for pp in $(_pins_unmatched "$T/pinned" "$T/list"); do
    bad "P the pin $pp names no corpus file — remove it"
done
if [ "$nbad" = 0 ] && [ "$nmiss" = 0 ]; then
    ok "C $n .tcyr compile and exit 0 under CYRIUS_IR=3 CYRIUS_DCE=1 ($npass pass)"
    if [ -n "$pinned_f" ]; then echo "         pinned, still failing (expected):$pinned_f"; fi
fi
if [ "$n" -lt "$FL" ]; then bad "F $n .tcyr walked (the corpus floor is $FL) — the reader is blind"
else ok "F $n walked (floor $FL)"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS: $G ($rows rows: $NF .tcyr under CYRIUS_IR=3 CYRIUS_DCE=1 in $((t1 - t0)) s on $J workers — every one compiles and exits 0; the detectors catch a planted pair-only exit and a stale pin)"
exit 0
