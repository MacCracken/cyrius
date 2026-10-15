#!/bin/sh
# Gate: lib/args.cyr's Linux args_init reads the WHOLE command line — past 2 MiB — and a command
# line it cannot read is a negative errno, never 0 (6.7.12).
#
# THE BUG (issues/2026-10-14-args-init-truncates-argv-past-2-mib.md, filed by cmdit's audit).
# args_init allocated 2,097,152 bytes and read /proc/self/cmdline with ONE sys_read. Linux's
# ARG_MAX is not 2 MiB: it follows RLIMIT_STACK / 4 (up to 6 MiB), which an unprivileged
# `ulimit -s unlimited` raises. A longer command line came back as its first 2,097,152 bytes —
# every argument whose end lay past the cut absent, the partly read one dropped whole — and
# nothing told the caller (the filing measured `argc=21 read=2097152` for 32 strings). A failed
# open or alloc returned 0 with argc() 0, the same answer as macOS's success. Now
# `_args_read_all` reads to EOF, doubling the buffer when it fills, and every failure is a
# negative errno (D7, the user 2026-10-15). CHANGELOG [6.7.12]
#
# AXES (Linux only; anything else is a named SKIP, exit 77).
#   A1  x86_64, the FILED repro verbatim (its .cyr; the bash array of its recipe is a POSIX `set
#       --` here), under a raised stack limit: 30 args of 100,000 bytes + LAST -> argc=32, read =
#       the exact byte count (> 2,097,152), last=LAST.
#   A2  the filing's control (`small LAST`) -> argc=3, read = its exact count, last=LAST.
#   A3  40 args of 131,000 bytes (5.2 MB): two doublings (2 -> 4 -> 8 MiB) -> argc=42, last=LAST.
#   A4  D7: the probe uses up every fd (the gate lowers `ulimit -n` to 64 first) and then calls
#       args_init -> "args_init=-24 argc=0" (the open's -EMFILE; 6.7.11 printed 0).
#   B1-B4  the same rows on aarch64 under qemu-aarch64 (a cross compiler built from
#       src/main_aarch64.cyr here; aarch64 Linux shares this arm). No qemu-aarch64 -> those rows
#       are a named SKIP and the gate exits 77, never a PASS.
#   M1-M2  ANTI-VACUOUS, built in: copies of the tree's lib/args.cyr, each differing in exactly
#       ONE line (else the mutation has drifted and the gate is RED): M1 the read loop stops after
#       one read (the 6.7.11 single read) must print `read=2097152` and an argc short of 32;
#       M2 the open failure answering 0 must print `args_init=0`. On x86 and under qemu.
#   The stack limit is raised to unlimited (or the hard limit); if that does not give the ARG_MAX
#   the rows need, the A/B rows are a named SKIP (exit 77).
#
# MUTATION LEDGER (6.7.12, x86_64 Linux + qemu-aarch64, the edit made to the tree's lib/args.cyr,
# gate re-run, restored):
#   args_init back to the 6.7.11 body (one read, 0 on failure) -> 8 rows: M0a M0b A1 A3 A4 B1 B3 B4 RED
#   `while (r > 0)` -> `while (r > 0 && n < 1)` (one read)     -> 5 rows: M0a A1 A3 B1 B3 RED
#   `if (fd < 0) { return fd; }` -> `return 0;`                -> 3 rows: M0b A4 B4 RED
#
# Nothing is written inside the tree: every probe and binary lives in a mktemp -d.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=args_init_long_cmdline
if [ "$(uname -s)" != Linux ]; then echo "SKIP: $G — Linux only (lib/args.cyr's /proc arm)"; exit 77; fi
for t in head tr getconf; do
    command -v "$t" >/dev/null 2>&1 || { echo "SKIP: $G — '$t' not found"; exit 77; }
done
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0
skips=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected '$2', got '$3'"; fails=$((fails + 1)); fi
}

# The stack limit the A/B rows need: ARG_MAX >= 5.5 MB (A3's 5,240,040 bytes + the environment).
NEED=5500000
am=$( (ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -Hs)" 2>/dev/null; getconf ARG_MAX) 2>/dev/null)
case $am in ''|*[!0-9]*) am=0 ;; esac
BIG_OK=1
if [ "$am" -lt "$NEED" ]; then
    echo "  SKIP: A1-A3 B1-B3 M1 — the stack limit cannot be raised far enough (ARG_MAX $am < $NEED; hard limit $(ulimit -Hs))"
    BIG_OK=0
    skips=1
fi

# $1 = the include line for args.cyr. The filed repro, verbatim but for that line.
mkrepro() {
    cat <<EOF
# args_repro.cyr — prints argc(), the bytes args_init read, and the start of the last argument
include "$1"
include "lib/string.cyr"
include "lib/fmt.cyr"

fn main(): i64 {
    args_init();
    var n = argc();
    syscall(1, 1, "argc=", 5); fmt_int(n);
    syscall(1, 1, " read=", 6); fmt_int(_args_len);
    var last = argv(n - 1);
    var len = strlen(last);
    if (len > 16) { len = 16; }
    syscall(1, 1, " last=", 6); syscall(1, 1, last, len);
    syscall(1, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(60, r);
EOF
}
# A4: no fd left, then args_init (its return and argc()).
mknofd() {
    cat <<EOF
include "$1"
include "lib/string.cyr"
include "lib/fmt.cyr"

fn main(): i64 {
    var k = 0;
    while (k < 100000) {
        if (sys_open("/dev/null", 0, 0) < 0) { k = 100000; }
        k = k + 1;
    }
    var r = args_init();
    syscall(1, 1, "args_init=", 10); fmt_int(r);
    syscall(1, 1, " argc=", 6); fmt_int(argc());
    syscall(1, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(60, r);
EOF
}

# The mutants: one line each of the tree's lib/args.cyr.
sed 's/^    while (r > 0) {$/    while (r > 0 \&\& n < 1) {/' lib/args.cyr > "$D/args_m1.cyr"
sed 's/^    if (fd < 0) { return fd; }$/    if (fd < 0) { return 0; }/' lib/args.cyr > "$D/args_m2.cyr"
check "M0a mutant 1 (one read) differs in exactly one line" 1 \
    "$(diff lib/args.cyr "$D/args_m1.cyr" | grep -c '^>' | tr -d ' ')"
check "M0b mutant 2 (open failure -> 0) differs in exactly one line" 1 \
    "$(diff lib/args.cyr "$D/args_m2.cyr" | grep -c '^>' | tr -d ' ')"
mkrepro "lib/args.cyr" > "$D/r.cyr"
mkrepro "$D/args_m1.cyr" > "$D/rm1.cyr"
mknofd "lib/args.cyr" > "$D/f.cyr"
mknofd "$D/args_m2.cyr" > "$D/fm2.cyr"

build() {   # $1 compiler, $2 source, $3 output
    rc=0
    CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1 "$1" < "$2" > "$3" 2> "$3.err" || rc=$?
    chmod +x "$3" 2>/dev/null
    [ "$rc" = 0 ] && [ -s "$3" ] && echo yes || echo "no (rc $rc: $(grep -v 'unreachable fns' "$3.err" | head -2))"
}
BIG=$(head -c 100000 /dev/zero | tr '\0' a)
HUGE=$(head -c 131000 /dev/zero | tr '\0' b)
# $1 = arg count, $2 = the arg, $3 = the last arg, $4.. = the command. Raises the stack limit,
# runs the command with that argv, prints its one line (or rc=N).
run_big() {
    nargs=$1; arg=$2; lastarg=$3; shift 3
    (
        ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -Hs)" 2>/dev/null
        cmd=$*
        set --
        i=0
        while [ "$i" -lt "$nargs" ]; do set -- "$@" "$arg"; i=$((i + 1)); done
        rc=0
        out=$($cmd "$@" "$lastarg" 2>&1) || rc=$?
        if [ "$rc" != 0 ]; then echo "rc=$rc $(printf '%s' "$out" | head -c 200)"; else printf '%s' "$out"; fi
    )
}
run_nofd() {
    ( ulimit -n 64 2>/dev/null; rc=0; out=$("$@" 2>&1) || rc=$?
      if [ "$rc" != 0 ]; then echo "rc=$rc $out"; else printf '%s' "$out"; fi )
}
# The exact cmdline bytes: argv[0] (the path as exec'd) + NUL, then each arg + NUL.
want_len() {   # $1 = argv0, $2 = count, $3 = arg length, $4 = last arg
    echo $(( ${#1} + 1 + $2 * ($3 + 1) + ${#4} + 1 ))
}

# $1 = label prefix (A|B), $2 = probe, $3 = mutant probe, $4 = no-fd probe, $5 = no-fd mutant,
# $6 = runner prefix ("" or qemu-aarch64)
rows() {
    L=$1; p=$2; pm=$3; f=$4; fm=$5; q=$6
    if [ "$BIG_OK" = 1 ]; then
        check "${L}1 the filed repro: 32 strings, 3 MB, read whole" \
            "argc=32 read=$(want_len "$p" 30 100000 LAST) last=LAST" "$(run_big 30 "$BIG" LAST $q "$p")"
        check "${L}3 5.2 MB: two doublings, every arg" \
            "argc=42 read=$(want_len "$p" 40 131000 LAST) last=LAST" "$(run_big 40 "$HUGE" LAST $q "$p")"
        mout=$(run_big 30 "$BIG" LAST $q "$pm")
        mread=$(printf '%s' "$mout" | sed -n 's/.* read=\([0-9]*\) .*/\1/p')
        margc=$(printf '%s' "$mout" | sed -n 's/^argc=\([0-9]*\) .*/\1/p')
        check "M1 (${L}) the one-read mutant stops at 2,097,152 bytes (what ${L}1 guards)" 2097152 "$mread"
        check "M1 (${L}) and its argc is short of 32" yes "$( [ -n "$margc" ] && [ "$margc" -lt 32 ] && echo yes || echo "no ($mout)")"
    fi
    sp=$( (cmd="$q $p"; $cmd small LAST) 2>&1)
    check "${L}2 the control: small LAST" "argc=3 read=$(want_len "$p" 1 5 LAST) last=LAST" "$sp"
    check "${L}4 no fd left: args_init is the open's -EMFILE, argc() 0 (D7)" "args_init=-24 argc=0" "$(run_nofd $q "$f")"
    check "M2 (${L}) the open-failure-answers-0 mutant prints 0 (what ${L}4 guards)" "args_init=0 argc=0" "$(run_nofd $q "$fm")"
}

echo "x86_64"
check "repro builds (tree lib/args.cyr)" yes "$(build "$CC" "$D/r.cyr" "$D/r")"
check "repro builds (mutant 1)" yes "$(build "$CC" "$D/rm1.cyr" "$D/rm1")"
check "no-fd probe builds (tree)" yes "$(build "$CC" "$D/f.cyr" "$D/f")"
check "no-fd probe builds (mutant 2)" yes "$(build "$CC" "$D/fm2.cyr" "$D/fm2")"
rows A "$D/r" "$D/rm1" "$D/f" "$D/fm2" ""

echo "aarch64 (qemu)"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    rc=0; "$CC" < src/main_aarch64.cyr > "$D/cca" 2> "$D/cca.err" || rc=$?
    chmod +x "$D/cca"
    check "cycc_aarch64 cross-built from src" yes "$( [ "$rc" = 0 ] && [ -s "$D/cca" ] && echo yes || echo "no (rc $rc)")"
    check "repro builds (tree lib/args.cyr)" yes "$(build "$D/cca" "$D/r.cyr" "$D/ra")"
    check "repro builds (mutant 1)" yes "$(build "$D/cca" "$D/rm1.cyr" "$D/rm1a")"
    check "no-fd probe builds (tree)" yes "$(build "$D/cca" "$D/f.cyr" "$D/fa")"
    check "no-fd probe builds (mutant 2)" yes "$(build "$D/cca" "$D/fm2.cyr" "$D/fm2a")"
    rows B "$D/ra" "$D/rm1a" "$D/fa" "$D/fm2a" qemu-aarch64
else
    echo "  SKIP: B1-B4 — qemu-aarch64 not found (the x86 axes ran)"
    skips=1
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails row(s))"; exit 1; fi
if [ "$skips" -ne 0 ]; then
    echo "SKIP: $G — some rows could not run (named above); every row that ran passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS: $G — args_init reads a command line past 2 MiB whole and answers a failed open with -errno; both mutants are caught"
exit 0
