#!/bin/sh
# tests/gates/memory/bounds_mode_corpus.sh — 6.7.8 (C2-10)
#
# THE CORPUS RUNS CLEAN UNDER THE BOUNDS-CHECKED MODE. The user's decision (2026-10-10): "The stdlib
# run's trips are FIXED IN 6.7.8". C2-10 ran every .tcyr, programs/, benches/, fuzz/, the stdlib
# modules and sigil's own suite under the mode, plain against checked, and found no trip; this gate
# keeps it that way. A trip is either a REAL out-of-range access (a new test, a lib / fold change)
# or a FALSE POSITIVE of the check (a compiler change) — either one turns a row red, naming the file.
# The mode itself (the switch, the message, every target, the constant rule, @unsafe) is
# tests/gates/frontend/bounds_mode_checked.sh's.
#
#   C  every subscript-using .tcyr (bounds_mode_checked.sh's OFF selection, recursive, floor 30) compiles
#      with CYRIUS_BOUNDS=1: rc 0, and no constant-index diagnostic (`index … is out of range` /
#      `is negative for` — an error under the mode, a warning inside @unsafe; none in the corpus)
#   R  each of them whose checker is REACHED (CYRIUS_DCE_VERBOSE does not list __cyrius_bounds_fail
#      dead — a run-time index exists) runs in the check driver's .tcyr environment (CYRIUS_TEST_ENV=1, a
#      throwaway HOME holding a copy of the dlopen-helper — programs/checks/selfhost.cyr `_tcyr_envp`)
#      and exits 0 with no `bounds: index` line. bounds_mode_violation.tcyr's children trip ON PURPOSE;
#      its parent captures them and exits 0. A file reached by no run-time index is the driver's own
#      default-mode run plus dead code, so it is compiled, not run.
#   F  floors: >= 30 files selected and >= 25 reaching the checker (248 and 29 at 6.7.8) — a compiler that
#      stopped emitting the check would leave every file "unreached" and this gate green without them
#   L  every lib/*.cyr included alone (--allow-undef, Linux) compiles under the mode exactly as with it
#      off: the same exit status and the same diagnostics (the `N unreachable fns` note aside — the
#      checker's six fns are appended); the modules that do not include alone (peers, folds that need
#      their dep chain) fail the same way in both
#   A  anti-vacuous — the gate's own trip detector, through the same functions: a planted u8[5] read at
#      run-time index 5 is reported as a trip (exit 134 + its line), a planted constant `a[5]` as a
#      compile error under the mode, and the same files in range pass
#
# C2-10's one-off run (2026-10-10, not repeated here): 553 .tcyr plain vs CYRIUS_BOUNDS=1 in the driver's
# harness, and `cyrius test --bounds tests/tcyr` through a staged home (553 passed) — 0 trips; the 32
# that reach the checker (3 only through lib/sigil.cyr's slice read) also on aarch64 (qemu), cx (cxvm)
# and PE (wine), each the same plain and checked; 111 programs / cbt / benches / fuzz / templates
# compiled (only the five kernel / EFI programs refused, by name), the 18 benches and 6 fuzz harnesses
# run; 113 lib modules on six targets (stdlib_modules_self_sufficient.sh under the mode); sigil
# 3.13.11's own 87 tests from an isolated copy of its tag.
#
# MUTATION LEDGER (2026-10-10; MC1 as CYCC=<the mutant>, MC2-MC4 with the gate run from a scratch copy
# of the tree holding the one mutation):
#   MC1  `_bck_open` never asks for a site (every subscript unchecked)       -> RED A1 A2, F (0 reached)
#   MC2  typed_array_subscript.tcyr's u8[5] loop runs `i <= 5` (default mode still exits 0)
#                                                                            -> RED R (that file: exit 134,
#        `bounds: index 5 out of [0, 5) at <source>:114`)
#   MC3  its `a8[4]` assert reads the constant `a8[5]`                      -> RED C (that file: the error)
#   MC4  a lib module holding a constant `a[5]` on a u8[5]                   -> RED L (off rc 0, on rc 1)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=bounds_mode_corpus
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT" || exit 1
unset CYRIUS_BOUNDS CYRIUS_DCE
fails=0
rows=0
ok()  { rows=$((rows + 1)); echo "  ok   $1"; }
bad() { rows=$((rows + 1)); echo "  FAIL $1"; fails=$((fails + 1)); }

# The driver's .tcyr environment: CYRIUS_TEST_ENV=1 and a throwaway HOME with a COPY of the helper
# the toolchain under test would use (read, never written).
TH="$T/tcyr_home"
mkdir -p "$TH/.cyrius"
for _h in "${CYRIUS_HOME:-}/dlopen-helper" "${HOME:-}/.cyrius/dlopen-helper"; do
    if [ -f "$_h" ]; then cp "$_h" "$TH/.cyrius/dlopen-helper" 2>/dev/null && break; fi
done

# _compile <src> <out> -> sets crc, cerr (the stderr file); the mode on, the dead list printed.
_compile() {
    cerr="$2.err"
    crc=0
    env -i PATH="${PATH:-/usr/bin:/bin}" CYRIUS_BOUNDS=1 CYRIUS_DCE_VERBOSE=1 "$CC" < "$1" > "$2" 2> "$cerr" || crc=$?
}
# _reached: the checker is called from somewhere (a run-time index exists) iff its fail fn is live.
_reached() { ! grep -qx '  dead: __cyrius_bounds_fail' "$cerr"; }
# _constdiag: the constant rule spoke (an error under the mode; a warning inside @unsafe).
_constdiag() { grep -E "index -?[0-9]+ is (out of range|negative for)" "$cerr" | head -1 || true; }
# _run <bin> -> sets rrc, rout; the driver's environment, the driver's cwd (the tree root).
_run() {
    rout="$1.out"
    chmod +x "$1"
    rrc=0
    env -i CYRIUS_TEST_ENV=1 HOME="$TH" timeout 300 "$1" > "$rout" 2>&1 || rrc=$?
}
# _trip <label> -> 0 when the run tripped (non-zero exit or a `bounds:` line), printing why.
_trip() {
    if [ "$rrc" -ne 0 ] || grep -q 'bounds: index' "$rout"; then
        why=$(grep -m1 'bounds: index' "$rout" || true)
        echo "         $1: exit $rrc${why:+ — $why}"
        return 0
    fi
    return 1
}

# ── A: the detector itself (planted trips through the same functions) ────────────────────────────
printf 'var a: u8[5];\nfn rd(i): i64 { return a[i]; }\nfn main(): i64 { return rd(I); }\nsyscall(60, main());\n' > "$T/a.tpl"
sed 's/rd(I)/rd(5)/' "$T/a.tpl" > "$T/a1.cyr"
sed 's/rd(I)/rd(4)/' "$T/a.tpl" > "$T/a2.cyr"
_compile "$T/a1.cyr" "$T/a1.bin"
if [ "$crc" -ne 0 ] || ! _reached; then bad "A1: the planted run-time index did not compile / reach the checker (rc $crc)"
else
    _run "$T/a1.bin"
    if _trip "A1" > /dev/null && [ "$rrc" -eq 134 ] && grep -qx 'bounds: index 5 out of \[0, 5) at <source>:2' "$rout"; then
        ok "A1 a planted u8[5] read at run-time index 5 is a trip (exit 134, its line)"
    else bad "A1: the planted trip was not detected: exit $rrc, $(head -1 "$rout")"; fi
fi
_compile "$T/a2.cyr" "$T/a2.bin"
_run "$T/a2.bin"
if [ "$crc" -eq 0 ] && _reached && ! _trip "A2" > /dev/null; then ok "A2 the same read at index 4 passes (reached, exit 0, no line)"
else bad "A2: the in-range control: rc $crc, exit $rrc, $(head -1 "$rout")"; fi
printf 'fn main(): i64 {\n    var a: u8[5];\n    a[5] = 1;\n    return 0;\n}\nsyscall(60, main());\n' > "$T/a3.cyr"
_compile "$T/a3.cyr" "$T/a3.bin"
if [ "$crc" -ne 0 ] && [ -n "$(_constdiag)" ]; then ok "A3 a planted constant a[5] on u8[5] is a compile error under the mode"
else bad "A3: rc $crc, diagnostic '$(_constdiag)'"; fi

# ── C / R / F: the subscript-using corpus ────────────────────────────────────────────────────────
nsel=0
nreach=0
ncbad=0
nrbad=0
for f in $(grep -rlE '[A-Za-z0-9_)]\[[^]]' tests/tcyr --include='*.tcyr' | sort); do
    nsel=$((nsel + 1))
    b="$T/t.bin"
    _compile "$f" "$b"
    d=$(_constdiag)
    if [ "$crc" -ne 0 ]; then
        ncbad=$((ncbad + 1))
        bad "C: $f does not compile under the mode (rc $crc): $(grep -m1 '^error' "$cerr" || true)"
        continue
    fi
    if [ -n "$d" ]; then ncbad=$((ncbad + 1)); bad "C: $f: the constant rule spoke under the mode: $d"; fi
    if _reached; then
        nreach=$((nreach + 1))
        _run "$b"
        if _trip "$f"; then nrbad=$((nrbad + 1)); bad "R: $f trips under the mode"; fi
    fi
    rm -f "$b" "$b.err" "$b.out"
done
if [ "$nsel" -lt 30 ]; then bad "F: only $nsel subscript-using .tcyr found (floor 30)"
elif [ "$ncbad" -eq 0 ]; then ok "C: $nsel subscript-using .tcyr compile under the mode, no constant-index diagnostic"; fi
if [ "$nreach" -lt 25 ]; then bad "F: only $nreach of them reach the checker (floor 25; 29 at 6.7.8) — is the check still emitted?"
elif [ "$nrbad" -eq 0 ]; then ok "R: $nreach reach the checker and run clean (exit 0, no bounds: line)"; fi

# ── L: every lib module, included alone, compiles under the mode as it does without it ──────────
nlib=0
nlok=0
for m in lib/*.cyr; do
    nlib=$((nlib + 1))
    printf 'include "%s";\nsyscall(60, 0);\n' "$m" > "$T/lm.cyr"
    r0=0; env -i PATH="${PATH:-/usr/bin:/bin}" "$CC" --allow-undef < "$T/lm.cyr" > "$T/lm0.bin" 2> "$T/lm0.err" || r0=$?
    r1=0; env -i PATH="${PATH:-/usr/bin:/bin}" CYRIUS_BOUNDS=1 "$CC" --allow-undef < "$T/lm.cyr" > "$T/lm1.bin" 2> "$T/lm1.err" || r1=$?
    grep -v 'unreachable fns' "$T/lm0.err" > "$T/lm0.d" || true
    grep -v 'unreachable fns' "$T/lm1.err" > "$T/lm1.d" || true
    if [ "$r0" -ne "$r1" ] || ! cmp -s "$T/lm0.d" "$T/lm1.d"; then
        bad "L: $m: off rc $r0, on rc $r1; the mode's diagnostics differ: $(diff "$T/lm0.d" "$T/lm1.d" | grep '^>' | head -1 || true)"
    elif [ "$r0" -eq 0 ]; then nlok=$((nlok + 1)); fi
done
if [ "$nlib" -lt 100 ] || [ "$nlok" -lt 90 ]; then bad "L: $nlib lib modules, $nlok compile alone (floors 100 / 90)"
else ok "L: $nlib lib modules: the mode changes no module's verdict or diagnostics ($nlok compile alone)"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS: $G ($rows rows: $nsel subscript-using .tcyr compile under the bounds-checked mode, the $nreach that reach the checker run clean; $nlib lib modules unchanged by the mode; the detector catches a planted trip)"
exit 0
