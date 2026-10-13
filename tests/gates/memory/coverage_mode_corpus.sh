#!/bin/sh
# check: serial — the whole .tcyr corpus compiled twice and run twice, in two codegen modes (~13 min of work on one CPU): it runs its own workers (half the CPUs, at most 8 — the pool's rule), so the parallel check.sh runs it alone, after its pool, not inside it near the 900 s gate deadline (6.7.10)
# tests/gates/memory/coverage_mode_corpus.sh — 6.7.10 (P5B-5)
#
# THE CORPUS RUNS UNCHANGED UNDER THE EXECUTION-COVERAGE MODE. The user's decision (2026-10-12):
# "P5-B depth: per-fn hit counters (one per fn, set after its prologue), dumped when the program
# exits"; "Flag off => byte-identical output". Mode off is the differential's and
# coverage_exec_hits.sh's; this gate is the other half: with the mode ON, a program must still do
# exactly what it does without it (hazard H26) — the bounds-checked mode's C2-10 corpus gate,
# bounds_mode_corpus.sh, is its shape. A row turns red naming the file when the counters or the
# dump change what a program does, or when a run leaves no record the CLI could read.
#
#   A  anti-vacuous — the gate's own detectors, through the same functions the corpus loop uses
#      (`_pair` builds and runs a file both ways, `_judge` grades it, `_dread` reads a dump), on
#      planted inputs: A1 a program that leaves through an `asm` exit_group (the documented residual:
#      no exit the dump can see) is "no coverage record"; A2 one that enters no fn is "a header but
#      no fn record"; A3 one that exits 3 only under the mode (`#ifdef CYRIUS_COVERAGE`) is an exit
#      delta; A4 one that compiles only off the mode is a compile-status delta; A5 a planted dump
#      with a record before its header, a zero count and a truncated record reads malformed, line by
#      line; A6 a clean control (fns entered, `syscall(60, g())`) passes on both legs; A7 a program
#      exiting 5 both ways fails the x86 leg and is compared-only under IR=3
#   X  every tests/tcyr/**/*.tcyr on x86, compiled plain and with CYRIUS_COVERAGE=1 (its own
#      CYRIUS_COVERAGE_FILE) and run in the check driver's .tcyr environment (CYRIUS_TEST_ENV=1, a
#      throwaway HOME holding a copy of the dlopen-helper — programs/checks/selfhost.cyr
#      `_tcyr_envp`; the tree root as cwd; the driver's 120 s deadline): the same compile status
#      (rc 0), the same exit (0), and a dump that is well-formed — every line `# cyrius-coverage 1`,
#      `<count> <file>:<line> <name>` (count >= 1) or `- <file>:<line> <name>` (a `#naked` fn, not
#      instrumented), no record before a header — holding at least one fn count. A forked child
#      appends a block of its own, so a dump may hold more than one
#   I  the same corpus under CYRIUS_IR=3, compiled plain and instrumented: the same compile status
#      and the same exit, both ways. Exit 0 is NOT required (IR=3 has pre-existing failures — B7's
#      struct-field class — named under the I row, never "fixed" here); each run that exits 0
#      must leave a well-formed record, and no dump may hold a malformed line
#   F  floors: the files walked and, on each leg, the runs with a record are at least the corpus
#      floor (tests/tcyr/CORPUS_FLOOR line 1, its only copy) — a compiler that stopped counting
#      would leave every dump header-only and this gate red, not green over nothing
#   CC an instrumented cycc compiles src/main.cyr byte-identical to cycc(src), with the same
#      stderr; its dump (through src/main.cyr's own `syscall(SYS_EXIT, _had_error);`) is ONE block
#      of more than 500 records (coverage_exec_hits.sh CC1, again here beside the corpus)
#
# P5B-4's one-off run (2026-10-12): 562 .tcyr plain vs instrumented, 0 compile-status or exit
# deltas, 0 runs without a record. Some tests leave a forked child holding their binary for a
# while, so every binary here has a name of its own (a reused name reads "Text file busy" — a
# compile failure that is not one).
#
# MUTATION LEDGER (P5B-5, 2026-10-12; MC1-MC3 as CYCC=<the 2-stage mutant cycc>, MP1-MP4 with the
# gate run from a scratch copy of the tree holding the one mutation; "N of M" = the rows RED):
#   MC1  `_cov_hit` emits nothing (every dump header-only)       -> RED 1122 of 1130: X x86 (562) and
#        I IR=3 (555) "a header but no fn record", A6 (both legs), F (0 with a record, both legs), CC2
#   MC2  the exit hook dropped (`_sc_args_done` calls no dump)   -> RED 531 of 539: "exited 0 but left
#        no coverage record" for every file leaving through an exit syscall (x86 264, IR=3 262), A6
#        (both legs), F (298 / 293 with a record), CC2 (no dump)
#   MC3  a closure's hit before its ESUBRSP (a push before the frame exists clobbers parameter slot 0
#        — hazard H1's shape)                                     -> RED 92 of 105: R, exit deltas (wrong
#        results, crashes) in 46 closure-using files on each leg; F and CC stay green (cycc has no
#        closures), as they must
#   MP1  lang/octal_literals.tcyr ends in an `asm` exit_group under the mode -> RED D on both legs (no
#        coverage record)
#   MP2  lang/mulh64.tcyr exits 3 only under the mode            -> RED R on both legs
#   MP3  lang/enums.tcyr fails to compile only under the mode     -> RED C on both legs
#   MP4  tests/tcyr/CORPUS_FLOOR raised to 563 (the corpus + 1)   -> RED F on both legs (the reader is
#        blind)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELF="$ROOT/tests/gates/memory/$(basename "$0")"
CC=${CYCC:-"$ROOT/build/cycc"}
G=coverage_mode_corpus
HDR='# cyrius-coverage 1'
P="${PATH:-/usr/bin:/bin}"

# _dread <dump> -> NB (blocks), NR (fn counts), NN ('-' records), NBAD (malformed lines), BADL (the
# first, numbered). No file: all 0.
_dread() {
    NB=0; NR=0; NN=0; NBAD=0; BADL=""
    [ -f "$1" ] || return 0
    awk -v h="$HDR" '
        $0 == h { b++; next }
        b > 0 && /^[1-9][0-9]* [^ ]+:[1-9][0-9]* [^ ]+$/ { r++; next }
        b > 0 && /^- [^ ]+:[1-9][0-9]* [^ ]+$/ { n++; next }
        { bad++; if (first == "") first = NR ": " substr($0, 1, 100) }
        END { printf "%d %d %d %d\n%s\n", b, r, n, bad, first }' "$1" > "$1.rd"
    { read -r NB NR NN NBAD; read -r BADL; } < "$1.rd"
    rm -f "$1.rd"
}
# _run <bin> -> RRC: the check driver's .tcyr environment and cwd (the tree root), its deadline. In a
# subshell (the `exit` keeps it a shell, not an exec of `timeout`) whose stderr is dropped: a crash
# is an exit status here (128 + the signal), not the shell's job message in the gate's log.
_run() {
    chmod +x "$1"
    RRC=0
    (env -i CYRIUS_TEST_ENV=1 HOME="$TH" timeout 120 "$1" < /dev/null > "$1.out" 2>&1; exit $?) 2> /dev/null || RRC=$?
}
# _pair <leg> <id> <src>: <src> compiled plain and instrumented for <leg> (x86 | ir3), each binary
# run; prints `c0 c1 r0 r1 NB NR NN NBAD` (r = '-' when that build did not compile) and BADL.
_pair() {
    leg=$1; id=$2; src=$3
    b="$T/b/$leg.$id"
    if [ "$leg" = ir3 ]; then set -- CYRIUS_IR=3; else set --; fi
    c0=0; env -i PATH="$P" "$@" "$CC" < "$src" > "$b.p" 2> "$b.pe" || c0=$?
    c1=0; env -i PATH="$P" "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$b.cov" "$CC" < "$src" > "$b.i" 2> "$b.ie" || c1=$?
    r0=-; r1=-
    if [ "$c0" = 0 ]; then _run "$b.p"; r0=$RRC; fi
    if [ "$c1" = 0 ]; then _run "$b.i"; r1=$RRC; fi
    _dread "$b.cov"
    printf '%s %s %s %s %s %s %s %s\n%s\n' "$c0" "$c1" "$r0" "$r1" "$NB" "$NR" "$NN" "$NBAD" "$BADL"
    rm -f "$b.p" "$b.pe" "$b.i" "$b.ie" "$b.cov" "$b.p.out" "$b.i.out"
}
# _judge <leg> <label> <result file> -> WHY (empty: clean), REC (1: a well-formed record with a fn
# count), CB / RB (1: IR=3's compile / run failing both ways — compared, not required), and
# JB / JR / JN (its blocks, fn counts, '-' records).
_judge() {
    leg=$1; lab=$2
    { read -r c0 c1 r0 r1 JB JR JN jbad; read -r jbl; } < "$3"
    WHY=""; REC=0; CB=0; RB=0
    if [ "$c0" != "$c1" ]; then WHY="C $leg: $lab compiles rc $c0 plain, rc $c1 under the mode"; return 0; fi
    if [ "$c0" != 0 ]; then
        if [ "$leg" = ir3 ]; then CB=1; return 0; fi
        WHY="C $leg: $lab does not compile (rc $c0, both ways)"; return 0
    fi
    if [ "$r0" != "$r1" ]; then WHY="R $leg: $lab exits $r0 plain, $r1 under the mode"; return 0; fi
    if [ "$jbad" != 0 ]; then WHY="D $leg: $lab: $jbad malformed dump line(s), the first $jbl"; return 0; fi
    if [ "$r1" != 0 ]; then
        if [ "$leg" = ir3 ]; then RB=1; return 0; fi
        WHY="R $leg: $lab exits $r1 (both ways)"; return 0
    fi
    if [ "$JB" = 0 ]; then WHY="D $leg: $lab exited 0 but left no coverage record"; return 0; fi
    if [ "$JR" = 0 ]; then WHY="D $leg: $lab exited 0 with a header but no fn record ($JB block(s), $JN '-')"; return 0; fi
    REC=1
}

# ── a worker: one file, one leg (`xargs` below runs this script as `--one <leg> <id> <src>`) ─────
if [ "${1:-}" = "--one" ]; then
    T=${COVCORPUS_T:?}; TH=${COVCORPUS_HOME:?}
    cd "$ROOT" || exit 1
    _pair "$2" "$3" "$4" > "$T/r/$2.$3"
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

# ── A: the detectors themselves, on planted inputs ───────────────────────────────────────────────
# pl <row> <leg> <id> <file> <want: a WHY prefix, or `clean`> <what>
pl() {
    _pair "$2" "$3" "$4" > "$T/r/$2.$3"
    _judge "$2" "$4" "$T/r/$2.$3"
    if [ "$5" = clean ]; then
        if [ -z "$WHY" ] && [ "$REC" = 1 ]; then ok "$1 $6 (clean: $JR fn record(s))"
        else bad "$1 $6: want clean, judged '${WHY:-no record}'"; fi
    else
        case "$WHY" in "$5"*) ok "$1 $6: '$WHY'" ;; *) bad "$1 $6: want '$5...', judged '${WHY:-clean}'" ;; esac
    fi
}
printf 'fn f(x): i64 { return x + 1; }\nfn bye() {\n    asm { 0xB8; 0xE7; 0x00; 0x00; 0x00; 0x48; 0x31; 0xFF; 0x0F; 0x05; }\n}\nvar a = f(1);\nbye();\nsyscall(60, 9);\n' > "$T/p/a1.cyr"
pl A1 x86 a1 "$T/p/a1.cyr" "D x86: $T/p/a1.cyr exited 0 but left no coverage record" "an asm exit_group (no exit the dump sees)"
printf 'var x = 1;\nvar y = x - 1;\n' > "$T/p/a2.cyr"
pl A2 x86 a2 "$T/p/a2.cyr" "D x86: $T/p/a2.cyr exited 0 with a header but no fn record" "a program that enters no fn"
printf 'fn f(): i64 { return 0; }\nvar r = f();\n#ifdef CYRIUS_COVERAGE\nr = 3;\n#endif\nsyscall(60, r);\n' > "$T/p/a3.cyr"
pl A3 x86 a3 "$T/p/a3.cyr" "R x86: $T/p/a3.cyr exits 0 plain, 3 under the mode" "an exit that moves under the mode"
printf 'fn f(): i64 { return 0; }\n#ifdef CYRIUS_COVERAGE\nfn g( {\n#endif\nsyscall(60, f());\n' > "$T/p/a4.cyr"
pl A4 x86 a4 "$T/p/a4.cyr" "C x86: $T/p/a4.cyr compiles rc 0 plain, rc 1 under the mode" "a compile status that moves under the mode"
printf '1 <source>:1 f\n%s\n2 <source>:2 g\n0 <source>:3 h\n3 <source>:4\n- <source>:5 nk\n' "$HDR" > "$T/p/a5.cov"
_dread "$T/p/a5.cov"
if [ "$NB" = 1 ] && [ "$NR" = 1 ] && [ "$NN" = 1 ] && [ "$NBAD" = 3 ] && [ "$BADL" = "1: 1 <source>:1 f" ]; then
    ok "A5 a planted dump: a record before its header, a zero count and a truncated record read malformed (3; the first '$BADL'), the rest well-formed"
else bad "A5 the planted dump read NB $NB NR $NR NN $NN NBAD $NBAD, the first '$BADL' (want 1 1 1 3, '1: 1 <source>:1 f')"; fi
printf 'fn f(x): i64 { return x + 1; }\nfn g(): i64 { return f(1) - 2; }\nsyscall(60, g());\n' > "$T/p/a6.cyr"
pl A6 x86 a6 "$T/p/a6.cyr" clean "the control (fns entered, syscall(60, g()))"
pl A6 ir3 a6 "$T/p/a6.cyr" clean "the control under IR=3"
printf 'fn f(): i64 { return 5; }\nsyscall(60, f());\n' > "$T/p/a7.cyr"
pl A7 x86 a7 "$T/p/a7.cyr" "R x86: $T/p/a7.cyr exits 5 (both ways)" "exit 5 both ways fails the x86 leg"
_pair ir3 a7 "$T/p/a7.cyr" > "$T/r/ir3.a7"; _judge ir3 a7 "$T/r/ir3.a7"
if [ -z "$WHY" ] && [ "$RB" = 1 ]; then ok "A7 the same under IR=3 is compared only (exit 5 both ways, counted as failing both ways)"
else bad "A7 under IR=3: judged '${WHY:-clean}', RB $RB (want compared-only)"; fi

# ── X / I / F: the corpus, both legs, through the workers ────────────────────────────────────────
find tests/tcyr -name '*.tcyr' | LC_ALL=C sort > "$T/list"
NF=$(grep -c . "$T/list" || true)
if grep -q '[[:space:]]' "$T/list"; then bad "X: a .tcyr path holds whitespace (the worker list splits on it): $(grep -m1 '[[:space:]]' "$T/list")"; fi
awk '{ print "x86", NR, $0 }' "$T/list" > "$T/jobs"
awk '{ print "ir3", NR, $0 }' "$T/list" >> "$T/jobs"
t0=$(date +%s)
COVCORPUS_T="$T" COVCORPUS_HOME="$TH" CYCC="$CC" xargs -P "$J" -n 3 sh "$SELF" --one < "$T/jobs"
t1=$(date +%s)
for leg in x86 ir3; do
    n=0; nrec=0; nrecs=0; nnk=0; nblk=0; nbad=0; cboth=""; rboth=""; nmiss=0
    while read -r f; do
        n=$((n + 1))
        if [ ! -f "$T/r/$leg.$n" ]; then nmiss=$((nmiss + 1)); bad "X $leg: $f: the worker left no result"; continue; fi
        _judge "$leg" "$f" "$T/r/$leg.$n"
        if [ -n "$WHY" ]; then nbad=$((nbad + 1)); bad "$WHY"; fi
        [ "$CB" = 1 ] && cboth="$cboth ${f#tests/tcyr/}"
        [ "$RB" = 1 ] && rboth="$rboth ${f#tests/tcyr/}(exit $r1)"
        if [ "$REC" = 1 ]; then nrec=$((nrec + 1)); nrecs=$((nrecs + JR)); nnk=$((nnk + JN)); nblk=$((nblk + JB)); fi
    done < "$T/list"
    if [ "$leg" = x86 ]; then
        if [ "$nbad" = 0 ] && [ "$nmiss" = 0 ]; then ok "X x86: $n .tcyr compile and exit 0 alike plain and instrumented; each leaves a well-formed record ($nblk blocks, $nrecs fn counts, $nnk '-' in all)"; fi
    else
        if [ "$nbad" = 0 ] && [ "$nmiss" = 0 ]; then
            ok "I IR=3: $n .tcyr: the compile status and the exit are the same plain and instrumented; $nrec exit 0 with a well-formed record"
            [ -n "$cboth$rboth" ] && echo "         IR=3 fails both ways (pre-existing, compared only):${cboth:+ does not compile:$cboth}${rboth:+ exits nonzero:$rboth}"
        fi
    fi
    if [ "$n" -lt "$FL" ]; then bad "F $leg: $n .tcyr walked (the corpus floor is $FL) — the reader is blind"
    elif [ "$nrec" -lt "$FL" ]; then bad "F $leg: $nrec of $n runs left a record (floor $FL) — is the mode still counting?"
    else ok "F $leg: $n walked, $nrec with a record (floor $FL)"; fi
done

# ── CC: an instrumented cycc reproduces cycc from src ────────────────────────────────────────────
if [ "$(tail -1 src/main.cyr)" != 'syscall(SYS_EXIT, _had_error);' ]; then bad "CC: src/main.cyr no longer ends in 'syscall(SYS_EXIT, _had_error);' — re-derive the row"
else
    D="$T/cc.cov"
    rc=0; env -i PATH="$P" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < src/main.cyr > "$T/cc.bin" 2> /dev/null || rc=$?
    env -i PATH="$P" "$CC" < src/main.cyr > "$T/cc.ref" 2> "$T/cc.ref.err" || true
    if [ "$rc" != 0 ] || [ ! -s "$T/cc.bin" ]; then bad "CC: the instrumented cycc did not compile (rc $rc)"
    else
        chmod +x "$T/cc.bin"; got=0; env -i PATH="$P" "$T/cc.bin" < src/main.cyr > "$T/cc.out" 2> "$T/cc.err" || got=$?
        if [ "$got" = 0 ] && [ -s "$T/cc.ref" ] && cmp -s "$T/cc.out" "$T/cc.ref" && cmp -s "$T/cc.err" "$T/cc.ref.err"; then
            ok "CC1 the instrumented cycc compiles src/main.cyr byte-identical to cycc(src), the same stderr"
        else bad "CC1 the instrumented cycc: exit $got; its output $(wc -c < "$T/cc.out") B against cycc(src)'s $(wc -c < "$T/cc.ref") B; stderr $(cmp -s "$T/cc.err" "$T/cc.ref.err" && echo same || echo differs)"; fi
        _dread "$D"
        if [ "$NB" = 1 ] && [ "$NR" -gt 500 ] && [ "$NBAD" = 0 ]; then ok "CC2 its dump: ONE block of $NR fn counts (> 500), well-formed"
        else bad "CC2 its dump: $NB block(s) (want 1), $NR fn counts (want > 500), $NBAD malformed ($BADL)"; fi
    fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS: $G ($rows rows: $NF .tcyr plain vs instrumented on x86 and under IR=3 in $((t1 - t0)) s on $J workers — the same compile status and exit, a well-formed record from every run that exits 0; an instrumented cycc reproduces cycc; the detectors catch planted no-record, exit and compile deltas and malformed dumps)"
exit 0
