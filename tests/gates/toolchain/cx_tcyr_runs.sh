#!/bin/sh
# A REAL .tcyr compiles for the cx target and RUNS on cxvm.
#
# WHY (v6.6.6): until this release the cx driver predefined no CYRIUS_TARGET_*
# macro at all. Every per-target `#ifdef` arm in the stdlib (lib/alloc.cyr,
# lib/syscalls.cyr, …) therefore matched nothing on cx, so those modules
# compiled to NOTHING and the filed repro
#
#     include "lib/assert.cyr"; assert_eq(1,1,"x"); var r = assert_summary();
#
# failed with `undefined function(s) called (cx backend): alloc, vec_get,
# alloc_reset, sys_exit`. No .tcyr had ever run on cx, so the whole target's
# test coverage was hand-written syscall-only programs — the five existing cx
# gates prove codegen shapes, not that the STDLIB works there. That is the
# "compiles on five targets is not runs on five targets" shape.
#
# Rows:
#   1  the filed repro verbatim — compiles for cx and exits 0 on cxvm.
#   2  tests/tcyr/platform/cx_stdlib_harness.tcyr compiles to a real CYX and
#      runs on cxvm with every assertion passing.
#   3  the same .tcyr passes NATIVELY (build/cycc) — so a cx-only green cannot
#      come from a file that is vacuous everywhere.
#   4  the assertion COUNT the run reports is checked against the count derived
#      from the source by grep — a different way of arriving at the same
#      number, so a harness that silently stopped asserting cannot pass.
#   5  RETURN VALUES on cxvm for every per-target arm this release added, plus
#      a native counter-probe proving those values are the arms and not a
#      coincidence.
#   6  the EMPTY-BODY AXIS — no fn a cx consumer can reach has a body that the
#      preprocessor removes entirely.
#
# WHY ROWS 5 AND 6 EXIST (added at the bite-7 review): rows 1-4 prove the
# module COMPILES and that the assertions in it pass. An EMPTY FUNCTION BODY
# COMPILES FINE. This preprocessor has no `#else`, so a fn written as a chain of
# per-target `#ifdef` arms that does not name cx has its whole body removed on
# cx and RETURNS WHATEVER IS IN THE RETURN REGISTER — no error, no warning, no
# failed compile. signal_ignore/signal_default were caught only because an
# unrelated compile gate went red in the same area; sys_utimensat (same file
# family, same shape) was NOT, and shipped answering 0 — a failed file-time set
# reading as SUCCESS — until it was found by review. lib/sys.cyr had four more
# (sys_uname, sys_sysinfo, sys_gettid and is_root, where the leftover register
# is a coin flip on "are we root"). Rows 5 and 6 are the two ways of not
# repeating that: assert the VALUES, and scan for the SHAPE.
#
# MUTATION LEDGER (v6.6.6, scratch trees only, never the repo):
#   real tree                                                        -> GREEN
#     4 rows, 13 assertions on cx and natively, 2.6 s
#   drop `PP_PREDEFINE(S, "CYRIUS_TARGET_CX")` from src/main_cx.cyr  -> RED
#     "FAIL: the filed repro does not compile for cx" + the four undefined fns
#   keep the predefine, remove the CYRIUS_TARGET_CX arm from
#     lib/alloc.cyr                                                  -> RED
#     same failure (alloc/alloc_reset undefined)
#   keep both, revert lib/assert.cyr's `include "lib/vec.cyr"`       -> RED
#     "undefined function(s) called (cx backend): vec_get"
#   keep all, delete two assertions from the .tcyr                   -> RED
#     "FAIL: only 11 assertions in ...cx_stdlib_harness.tcyr (floor 13)"
#     (the first cut of row 4 compared only run-count vs grep-count, which
#      AGREE when assertions are deleted — that mutant passed until the floor
#      was added. Recorded because it is the mutant that nearly shipped green.)
#
# MUTATION LEDGER for rows 5-6 (v6.6.6 bite-7 review, scratch trees only):
#   real tree                                                          -> GREEN
#     6 rows, 3.8 s (row 6's 104 probe-compiles are ~3 s of that)
#   revert lib/syscalls_linux_common.cyr's default arm (sys_utimensat)  -> RED
#     row 5: "FAIL: utimensat is ENOSYS on cx (got 0, expected -38)"
#     ⚠ ROWS 1-4 STAY GREEN THROUGH THIS MUTANT — that is the whole point.
#     With row 5's utimensat assertion also deleted, row 6 catches it alone:
#     "sys_utimensat (lib/syscalls_linux_common.cyr)".
#   revert lib/sys.cyr's four default arms                              -> RED
#     row 5: "uname is ENOSYS on cx (got 219296, expected -38)" — a HEAP
#     POINTER, and for is_root any non-zero leftover reads as "yes, root".
#     With those four assertions deleted, row 6 names all four alone.
#   revert lib/syscalls.cyr's CYRIUS_TARGET_CX signal arms              -> RED
#     row 5: "signal_ignore is a no-op on cx (got 13, expected 0)" — 13 is
#     SIGPIPE, i.e. the argument register read back as the result.
#   point row 5's native counter-probe at cxvm instead of the host      -> RED
#     "the native counter-probe failed — the cx values above are not
#     distinguishable". The probe that proves the cx values are deliberate
#     cannot itself be run on cx.
#   ⚠ THE MUTANT THAT CAUGHT THE GATE: row 6's first cut asked "does the module
#     the empty fn lives in compile for cx?" and reported anything else as
#     unreachable. lib/syscalls_linux_common.cyr does NOT compile standalone
#     (it carries no syscall numbers), so the reverted sys_utimensat was
#     dismissed as unreachable and row 6 passed GREEN on the mutant. Rewritten
#     to probe-compile every lib module and scan the CLOSURES of the ones that
#     compile. Recorded because a reachability test on the wrong unit is how an
#     axis ends up agreeing with the defect it is supposed to find.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
TCYR=tests/tcyr/platform/cx_stdlib_harness.tcyr
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f src/main_cx.cyr ] || { echo "SKIP: src/main_cx.cyr missing"; exit 0; }
[ -f programs/cxvm.cyr ] || { echo "SKIP: programs/cxvm.cyr missing"; exit 0; }
[ -f "$TCYR" ] || { echo "FAIL: $TCYR missing — the cx row has nothing to run"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cx_tcyr_runs: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

build() {   # $1 = source, $2 = out binary
    if ! cat "$1" | "$CC" > "$2" 2> "$T/b.err"; then
        echo "FAIL: building $1 with build/cycc failed"
        head -3 "$T/b.err" || true
        exit 1
    fi
    sz=$(wc -c < "$2" | tr -d ' ')
    if [ "$sz" -lt 1024 ]; then
        echo "FAIL: $1 produced a $sz-byte binary (empty/truncated)"
        exit 1
    fi
    chmod +x "$2"
}
build src/main_cx.cyr "$T/cycc_cx"
build programs/cxvm.cyr "$T/cxvm"

# ── row 1: the filed repro, verbatim ─────────────────────────────────────
printf 'include "lib/assert.cyr";\nassert_eq(1,1,"x");\nvar r = assert_summary();\n' > "$T/repro.cyr"
if ! "$T/cycc_cx" < "$T/repro.cyr" > "$T/repro.cyx" 2> "$T/repro.err"; then
    echo "FAIL: the filed repro does not compile for cx"
    head -6 "$T/repro.err" || true
    exit 1
fi
rc=0
"$T/cxvm" < "$T/repro.cyx" > "$T/repro.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: the filed repro compiled for cx but exited $rc on cxvm"
    head -5 "$T/repro.out" || true
    exit 1
fi
echo "  repro: include lib/assert.cyr compiles for cx and exits 0 on cxvm"

# ── row 2: a real .tcyr on cxvm ──────────────────────────────────────────
if ! "$T/cycc_cx" < "$TCYR" > "$T/h.cyx" 2> "$T/h.err"; then
    echo "FAIL: $TCYR does not compile for cx"
    head -6 "$T/h.err" || true
    exit 1
fi
magic=$(od -An -N3 -tx1 "$T/h.cyx" | tr -d ' \n')
if [ "$magic" != "435958" ]; then
    echo "FAIL: cx output is not a CYX file (magic $magic)"
    exit 1
fi
rc=0
"$T/cxvm" < "$T/h.cyx" > "$T/h.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: $TCYR exited $rc on cxvm"
    head -8 "$T/h.out" || true
    exit 1
fi
cx_pass=$(awk '/passed,/ {print $1}' < "$T/h.out" | tail -1)
cx_fail=$(awk -F'passed, ' '/passed,/ {print $2}' < "$T/h.out" | awk '{print $1}' | tail -1)
if [ "$cx_fail" != "0" ] || [ -z "$cx_pass" ]; then
    echo "FAIL: cxvm run did not report a clean summary"
    head -8 "$T/h.out" || true
    exit 1
fi
echo "  cxvm: $TCYR -> $cx_pass assertions passed, 0 failed"

# ── row 3: the same file passes natively ─────────────────────────────────
build "$TCYR" "$T/h_native"
rc=0
"$T/h_native" > "$T/n.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: $TCYR exited $rc natively (x86-linux) — a cx-only green would be meaningless"
    head -8 "$T/n.out" || true
    exit 1
fi
nat_pass=$(awk '/passed,/ {print $1}' < "$T/n.out" | tail -1)
if [ "$nat_pass" != "$cx_pass" ]; then
    echo "FAIL: cxvm ran $cx_pass assertions, native ran $nat_pass — the two targets disagree"
    exit 1
fi
echo "  native: same file, same $nat_pass assertions"

# ── row 4: the count, derived from the SOURCE a different way ────────────
# Every assertion in the harness is one `assert*(` call at the start of a line.
want=$(grep -c '^assert' "$TCYR" || true)
# Floor = the count this file carried when the gate landed. Raise it when the
# harness grows; never lower it. Without a floor, DELETING assertions keeps the
# grep count and the run count in agreement and the gate stays green.
if [ "$want" -lt 13 ]; then
    echo "FAIL: only $want assertions in $TCYR (floor 13) — the harness was gutted"
    exit 1
fi
if [ "$cx_pass" != "$want" ]; then
    echo "FAIL: cxvm ran $cx_pass assertions, the source has $want"
    exit 1
fi

# ── row 5: RETURN VALUES on cxvm for every per-target arm ────────────────
# An empty fn body compiles. Only running it tells you what it answers.
cat > "$T/arms.cyr" <<'ARMS'
include "lib/assert.cyr";
include "lib/syscalls.cyr";
include "lib/sys.cyr";
var u[400];
var si[208];
assert_eq(signal_ignore(SIGPIPE), 0, "signal_ignore is a no-op on cx");
assert_eq(signal_default(SIGPIPE), 0, "signal_default is a no-op on cx");
assert_eq(sys_utimensat(AT_FDCWD, "/cyrius-no-such-path", 0, 0), 0 - 38, "utimensat is ENOSYS on cx");
assert_eq(sys_uname(&u), 0 - 38, "uname is ENOSYS on cx");
assert_eq(sys_sysinfo(&si), 0 - 38, "sysinfo is ENOSYS on cx");
assert_eq(sys_gettid(), 0 - 38, "gettid is ENOSYS on cx");
assert_eq(is_root(), 0, "is_root answers not-root on cx");
var r = assert_summary();
ARMS
arms_want=$(grep -c '^assert_eq' "$T/arms.cyr")
if ! "$T/cycc_cx" < "$T/arms.cyr" > "$T/arms.cyx" 2> "$T/arms.err"; then
    echo "FAIL: the per-target-arm probe does not compile for cx"
    head -6 "$T/arms.err" || true
    exit 1
fi
rc=0
"$T/cxvm" < "$T/arms.cyx" > "$T/arms.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: a per-target arm answers the wrong value on cxvm (exit $rc)"
    grep 'FAIL:' "$T/arms.out" | head -8
    exit 1
fi
arms_pass=$(awk '/passed,/ {print $1}' < "$T/arms.out" | tail -1)
if [ "$arms_pass" != "$arms_want" ]; then
    echo "FAIL: arm probe ran $arms_pass of $arms_want assertions on cxvm"
    exit 1
fi
echo "  arms: $arms_pass per-target arms answer their documented value on cxvm"

# The counter-probe. Every cx value above is 0 or -38, which is also what a
# BROKEN fn could return by luck. Running the same wrappers on the HOST, where
# real arms exist, must give different answers — otherwise row 5 proves nothing.
cat > "$T/nat.cyr" <<'NAT'
include "lib/assert.cyr";
include "lib/syscalls.cyr";
include "lib/sys.cyr";
var u[400];
assert_eq(sys_utimensat(AT_FDCWD, "/cyrius-no-such-path", 0, 0), 0 - 2, "utimensat is ENOENT natively");
assert_eq(sys_uname(&u), 0, "uname works natively");
assert_gt(sys_gettid(), 0, "gettid is a real tid natively");
var r = assert_summary();
NAT
build "$T/nat.cyr" "$T/nat"
rc=0
"$T/nat" > "$T/nat.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: the native counter-probe failed — the cx values above are not distinguishable"
    grep 'FAIL:' "$T/nat.out" | head -5
    exit 1
fi
echo "  counter-probe: the same wrappers answer differently on the host"

# ── row 6: the EMPTY-BODY AXIS ───────────────────────────────────────────
# Derived two ways, nothing written down: the cx define set comes from
# src/main_cx.cyr's own unconditional PP_PREDEFINE calls, and the module list
# from lib/*.cyr. Reachability is settled EMPIRICALLY — every lib module is
# probe-compiled for cx, and the ones that compile are the scan roots. The fns
# a cx consumer can reach are exactly the ones in the cx include closure of a
# module that compiles, so scanning from those roots needs no allowlist.
#
# ⚠ THIS IS THE SECOND CUT. The first asked "does the module the empty fn lives
# in compile for cx?" — and mutation showed that answers NO for
# lib/syscalls_linux_common.cyr, which carries no syscall numbers of its own and
# is only ever reached THROUGH lib/syscalls.cyr. So the first cut let the
# reverted sys_utimensat through as "unreachable" while it was in fact the
# module every cx .tcyr pulls in. Reachability is a property of the CLOSURE,
# never of the file in isolation.
CXDEFS=$(grep '^PP_PREDEFINE' src/main_cx.cyr | sed 's/.*"\(.*\)".*/\1/' | tr '\n' ' ')
case "$CXDEFS" in
    *CYRIUS_TARGET_CX*) : ;;
    *) echo "FAIL: no unconditional CYRIUS_TARGET_CX predefine in src/main_cx.cyr"; exit 1 ;;
esac
cat > "$T/emptyfn.awk" <<'AWK'
BEGIN {
    n = split(defs, da, " "); for (i = 1; i <= n; i++) DEF[da[i]] = 1
    DEPTH = 0; LIVE[0] = 1
    m = split(roots, ra, " ")
    for (i = 1; i <= m; i++) walk(ra[i])
    for (f in EMPTY) printf "%s\t%s\n", EMPTY[f], f
}
# drop string literals and comments so brace counting is honest
function strip(s,   out, i, c, inq, esc) {
    out = ""; inq = 0; esc = 0
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (inq) { if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") inq = 0; continue }
        if (c == "\"") { inq = 1; continue }
        if (c == "#") break
        out = out c
    }
    return out
}
function nbrace(s, ch,   i, k) { k = 0
    for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == ch) k++
    return k
}
function walk(file,   line, t, g, w, bare, sd, fnname, fnlive, fndepth, base) {
    if (file in FILES) return
    FILES[file] = 1
    base = DEPTH; fnname = ""; fndepth = 0
    while ((getline line < file) > 0) {
        t = line; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (substr(t, 1, 7) == "#ifdef " || substr(t, 1, 8) == "#ifndef " || substr(t, 1, 8) == "#ifplat ") {
            split(t, w, /[ \t]+/); g = w[2]; DEPTH++
            if (substr(t, 1, 7) == "#ifdef ")       TAKEN[DEPTH] = (g in DEF)
            else if (substr(t, 1, 8) == "#ifndef ") TAKEN[DEPTH] = !(g in DEF)
            else                                    TAKEN[DEPTH] = (("CYRIUS_ARCH_" g) in DEF)
            LIVE[DEPTH] = LIVE[DEPTH-1] && TAKEN[DEPTH]; SEEN[DEPTH] = TAKEN[DEPTH]
            continue
        }
        if (t == "#else") { TAKEN[DEPTH] = !SEEN[DEPTH]; LIVE[DEPTH] = LIVE[DEPTH-1] && TAKEN[DEPTH]; continue }
        if (t == "#endif" || t == "#endplat") { if (DEPTH > base) DEPTH--; continue }
        if (LIVE[DEPTH] && t ~ /^include[ \t]+"/) {
            g = t; sub(/^include[ \t]+"/, "", g); sub(/".*$/, "", g)
            sd = DEPTH; walk(g); DEPTH = sd; continue
        }
        if (!LIVE[DEPTH] && fnname == "") continue
        bare = strip(line)
        if (fnname == "" && LIVE[DEPTH] && line ~ /^fn[ \t]+[A-Za-z_]/) {
            fnname = line; sub(/^fn[ \t]+/, "", fnname); sub(/[ \t]*\(.*$/, "", fnname)
            fnlive = 0; fndepth = nbrace(bare, "{") - nbrace(bare, "}")
            if (fndepth <= 0) fnname = ""
            continue
        }
        if (fnname != "") {
            fndepth += nbrace(bare, "{") - nbrace(bare, "}")
            if (fndepth <= 0) {
                if (fnlive == 0) EMPTY[fnname] = file
                fnname = ""; continue
            }
            if (LIVE[DEPTH]) {
                sub(/^[ \t]+/, "", bare); sub(/[ \t]+$/, "", bare)
                if (bare != "" && bare != "{" && bare != "}" && bare != "};") fnlive = 1
            }
        }
    }
    close(file)
    DEPTH = base
}
AWK
nlibs=$(ls lib/*.cyr | wc -l | tr -d ' ')
if [ "$nlibs" -lt 90 ]; then
    echo "FAIL: only $nlibs lib/*.cyr modules found (floor 90) — the scan lost its corpus"
    exit 1
fi
: > "$T/roots.txt"
for mod in lib/*.cyr; do
    printf 'include "%s";\nvar _axis_probe = 1;\n' "$mod" > "$T/reach.cyr"
    if "$T/cycc_cx" < "$T/reach.cyr" > "$T/reach.cyx" 2> "$T/reach.err"; then
        printf '%s ' "$mod" >> "$T/roots.txt"
    fi
done
ROOTS=$(cat "$T/roots.txt")
nroots=$(printf '%s' "$ROOTS" | wc -w | tr -d ' ')
# Floor: if cycc_cx regressed so that nothing compiles, the scan would have no
# roots and pass vacuously. 23 modules compile at 6.6.6; never lower this.
if [ "$nroots" -lt 20 ]; then
    echo "FAIL: only $nroots of $nlibs lib modules compile for cx (floor 20) — the axis has no roots"
    exit 1
fi
awk -v roots="$ROOTS" -v defs="$CXDEFS" -f "$T/emptyfn.awk" > "$T/empty.txt" || {
    echo "FAIL: the empty-body scan did not run"; exit 1; }
if [ -s "$T/empty.txt" ]; then
    echo "FAIL: fn(s) a cx consumer can reach have a body the preprocessor removes"
    echo "      entirely — they return whatever is in the return register:"
    while read -r mod fn; do
        [ -n "$mod" ] || continue
        echo "        $fn  ($mod)"
    done < "$T/empty.txt"
    echo "      Give each a default arm (see sys_utimensat in lib/syscalls_linux_common.cyr)."
    exit 1
fi
echo "  axis: $nroots of $nlibs lib modules compile for cx; their closures carry 0 empty bodies"

echo "PASS: cx compiles and runs a real .tcyr ($want assertions) on cxvm"
exit 0
