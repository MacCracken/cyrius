#!/bin/sh
# darwin_syscall_literals_routed.sh — v6.6.8: every syscall a macOS build can reach is one the
# Mach-O translation ROUTES, on BOTH Macs. The Darwin axis raw_syscall_literals_routed.sh (the
# ELF-aarch64 axis) explicitly does not claim.
#
# ⛔ WHY IT EXISTS. On arm64-macOS an unrouted number used to re-run the PREVIOUS syscall out of a
# stale x16, silently (6.6.8 made ESYSXLAT's chain head default x16 to an invalid number, so it
# now SIGSYSes, as x86-macOS always has). Either way the only compile-time signal is cycc's
# "syscall N not routed" warning, and nothing turned that warning into a failure: the class
# shipped at least eight times, each found at run time on a Mac and fixed one row at a time.
#
# ⚠ THIS GATE ASKS THE COMPILER, IT DOES NOT DECODE A TABLE. A first attempt at this axis re-ran
# raw_syscall_literals_routed.sh with its routed set swapped for the `_msx` rows and reported
# "22 arch-neutral sites unrouted on Darwin" — a scan artifact, for two reasons: it reused the
# ELF reach table, whose CYRIUS_TARGET_MACOS / CYRIUS_TARGET_LINUX sides mean the OPPOSITE on
# Darwin, and it ignored the parse-time reroutes (228, 35, 1700), which have no table row at all.
# So the verdict here comes from the Mach-O compilers' own diagnostic (`_macho_warn_unrouted` in
# src/frontend/parse_expr.cyr, which replays each backend's rows), and each probe is compiled at
# the site's REAL argument count: the reroutes fire at one arity only, and until 6.6.8 the
# diagnostic was blind to that, so `syscall(228, id)` built clean on both Macs and faulted.
#
# Two axes, because each sees what the other cannot:
#   1. LITERAL SITES. Every `syscall(<literal>, …)` in lib/ cbt/ programs/ and
#      tests/tcyr/crossos/ that a macOS build compiles — decided per backend by a Darwin reach
#      table over the #ifdef frames (x86-macOS reaches CYRIUS_ARCH_X86 and not _AARCH64, arm64
#      the reverse; both reach CYRIUS_TARGET_MACOS and neither reaches _LINUX/_WIN/_AGNOS/_CX)
#      and per file (each macOS target resolves ONE syscall peer). The distinct (number, argc)
#      pairs are compiled as probes with CYRIUS_MACHO=1 / CYRIUS_MACHO_ARM=1; a warned pair
#      reports its sites. Unlike the ELF gate the PEERS ARE SCANNED — the aarch64 peer's raw 232
#      in sys_epoll_wait went unrouted on arm64-macOS precisely because both existing gates skip
#      peers (macho_route_parity reads only `syscall(SYS_*` names).
#   2. THE BUILDS. Every programs/*.cyr, cbt/cyrius.cyr and tests/tcyr/crossos/*.tcyr compiled
#      for each Mac must print ZERO "not routed" warnings. This is what sees a NAMED constant
#      (cyrius-init's `syscall(SYS_GETCWD, …)`, unrouted on both Macs and invisible to any
#      literal scan) and a vendored fold's private number (yukti's `SYS_PPOLL = 271`) — and it
#      is the "builds that pull in sigil or yukti warn" report from the 6.6.7 review, pinned.
#
# Exemptions carry a reason; an unexplained one is how this rots:
#   programs/checks/            the check.sh driver runs on the Linux build host only
#   darwin_unrouted_syscall_faults.tcyr:4001   that test issues an unrouted number ON PURPOSE
#   lib/*_win.cyr, *_windows.cyr, *_agnos.cyr, syscalls_x86_64_linux.cyr  included only under
#                               their own target's #ifdef — never on Darwin (the Windows reroute
#                               band 0xF0xx in lib/sync_windows.cyr is what an unscoped scan hits)
#   lib/syscalls_macos.cyr / syscalls_aarch64_linux.cyr  scanned for the ONE Mac that resolves each
#
# Anti-vacuous: file / site / reached-site floors per backend, and every run first proves the
# probe machinery against CONTROLS — a known-unrouted number must warn on both backends, a
# routed one must not, and `syscall(228, id)` (argc 2) must warn while `syscall(228, id, &ts)`
# must not. A scanner that reached nothing, or a compiler that stopped warning, fails here
# before it can report "all routed".
#
# MUTATION LEDGER (each measured RED, then restored):
#   * drop the aarch64 peer's #ifdef CYRIUS_TARGET_MACOS decline in sys_epoll_wait   → axis 1: arm 232, axis 2
#   * drop dynlib_bootstrap_tls's #ifndef CYRIUS_TARGET_MACOS around the raw 158      → axis 1: x86 158
#   * delete ESYSXLAT's `_esx_arm(S, 16, 54)` row                                      → axis 1: arm 16 (ioctl test)
#   * revert cyrius-init's Darwin _cwd_path arm                                        → axis 2: x86 79, arm 17
#   * revert parse_expr's arity check (_macho_reroute_argc)                            → control: 228 argc 2
#   * restore yukti's un-declined _yk_ppoll                                            → axis 2: x86 271, arm 1073
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: darwin_syscall_literals_routed: $CC missing"; exit 1; }
TMP=$(mktemp -d) && [ -d "$TMP" ] || { echo "FAIL: darwin_syscall_literals_routed: mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT INT TERM

# ⚠ The arm64 cross compiler is BUILT FROM THIS TREE, never taken from build/cycc_aarch64: that
# artifact is gitignored and routinely stale, and a stale one answers with last release's rows.
"$CC" < src/main_aarch64.cyr > "$TMP/cc_a64" 2>/dev/null || true
chmod +x "$TMP/cc_a64" 2>/dev/null || true
[ -s "$TMP/cc_a64" ] || { echo "FAIL: darwin_syscall_literals_routed: could not build the aarch64 cross compiler from src/main_aarch64.cyr"; exit 1; }

# macho_compile <x86|arm> <src> <errfile>
macho_compile() {
    if [ "$1" = x86 ]; then env CYRIUS_MACHO=1 "$CC" < "$2" > "$TMP/_bin.$$" 2> "$3" || true
    else env CYRIUS_MACHO_ARM=1 "$TMP/cc_a64" < "$2" > "$TMP/_bin.$$" 2> "$3" || true; fi
}
# warned_numbers <errfile>  →  the syscall numbers the Mach-O diagnostic named, one per line
warned_numbers() { sed -n 's/^warning: syscall \([0-9][0-9]*\) not routed.*/\1/p' "$1" | sort -n -u; }

fail=0

# ── controls: prove the probe machinery before trusting a quiet answer ──────────────
for T in x86 arm; do
    printf 'var ts[16];\nsyscall(4001, 0, 0, 0);\nsyscall(3, 0);\nsyscall(228, 4);\nsyscall(228, 4, &ts);\n' > "$TMP/ctl.cyr"
    macho_compile "$T" "$TMP/ctl.cyr" "$TMP/ctl.$T.err"
    got=$(warned_numbers "$TMP/ctl.$T.err" | tr '\n' ' ')
    n228=$(grep -c '^warning: syscall 228 not routed' "$TMP/ctl.$T.err" || true)
    if [ "$got" != "228 4001 " ] || [ "$n228" != 1 ]; then
        echo "FAIL: darwin_syscall_literals_routed: $T control — want exactly 4001 and ONE 228 (the argc-2 call) warned, got '$got' ($n228 x 228)"
        echo "      (4001 unwarned: the diagnostic is dead; 3 warned: it cries wolf; 228 twice or never: the arity check is gone)"
        exit 1
    fi
done
echo "  controls: both Mach-O compilers warn on 4001 and on syscall(228, id), and not on close or syscall(228, id, &ts)"

# ── axis 1: literal sites ────────────────────────────────────────────────────────────
files=$(find lib cbt programs tests/tcyr/crossos \( -name '*.cyr' -o -name '*.tcyr' \) \
  | grep -v -E '^programs/checks/|_win\.cyr$|_windows\.cyr$|_agnos\.cyr$|^lib/syscalls_x86_64_linux\.cyr$' | sort)
nfiles=$(echo "$files" | wc -l)
[ "$nfiles" -ge 250 ] || { echo "FAIL: darwin_syscall_literals_routed: scanned only $nfiles files (want >= 250)"; exit 1; }

cat > "$TMP/scan.awk" <<'AWK'
# Emits "<num> <argc> <file>:<line>" for each literal site target T reaches.
# Directive spellings mirror src/frontend/lex_pp.cyr exactly (one space after #ifdef/#ifndef/
# #ifplat/#if; a non-identifier byte after #else/#elif/#endif/#endplat; any other # line is a
# comment) — the same rules raw_syscall_literals_routed.sh documents.
function reach(sym, negated,   ifs, els) {
    # ifs/els: 1 = that side reaches T, 0 = it does not, -1 = unrelated symbol (inherit)
    if (sym == "CYRIUS_TARGET_MACOS") { ifs = 1; els = 0 }
    else if (sym == "CYRIUS_TARGET_LINUX" || sym == "CYRIUS_TARGET_WIN" || sym == "CYRIUS_TARGET_AGNOS" \
          || sym == "CYRIUS_TARGET_CX" || sym == "CYRIUS_ARCH_RISCV" || sym == "CYRIUS_TARGET_RISCV") { ifs = 0; els = 1 }
    else if (sym == "CYRIUS_ARCH_X86") { if (T == "x86") { ifs = 1; els = 0 } else { ifs = 0; els = 1 } }
    else if (sym == "CYRIUS_ARCH_AARCH64") { if (T == "arm") { ifs = 1; els = 0 } else { ifs = 0; els = 1 } }
    else { ifs = -1; els = -1 }
    if (negated) { RIF = els; REL = ifs } else { RIF = ifs; REL = els }
}
function push(sym, negated,   up) {
    depth++; reach(sym, negated)
    up = (depth > 1) ? on[depth-1] : 1
    onif[depth] = up && (RIF != 0); onel[depth] = up && (REL != 0); on[depth] = onif[depth]
}
function mask(line,   code, inq, k, c) {
    code = ""; inq = 0
    for (k = 1; k <= length(line); k++) {
        c = substr(line, k, 1)
        if (inq) { if (c == "\\") { k++; continue } if (c == "\"") { inq = 0; code = code c } continue }
        if (c == "\"") { inq = 1; code = code c; continue }
        if (c == "#") break
        code = code c
    }
    return code
}
function argc_of(rest,   d, k, c, n) {    # rest = text after "syscall("; <0 when unclosed
    d = 1; n = 1
    for (k = 1; k <= length(rest); k++) {
        c = substr(rest, k, 1)
        if (c == "(" || c == "[" || c == "{") d++
        else if (c == ")" || c == "]" || c == "}") { d--; if (d == 0) return n }
        else if (c == "," && d == 1) n++
    }
    return -1
}
FNR == 1 { depth = 0; on[0] = 1 }
{
    line = $0; sub(/^[ \t]+/, "", line)
    if (substr(line, 1, 7) == "#ifdef ")  { s = substr(line, 8); sub(/[^A-Za-z_0-9].*$/, "", s); push(s, 0); next }
    if (substr(line, 1, 8) == "#ifndef ") { s = substr(line, 9); sub(/[^A-Za-z_0-9].*$/, "", s); push(s, 1); next }
    if (substr(line, 1, 8) == "#ifplat ") { s = substr(line, 9); sub(/[^A-Za-z_0-9].*$/, "", s); push("CYRIUS_ARCH_" toupper(s), 0); next }
    if (substr(line, 1, 4) == "#if ")     { push("", 0); next }
    if (line ~ /^#else([^A-Za-z_0-9]|$)/ || line ~ /^#elif([^A-Za-z_0-9]|$)/) { if (depth > 0) on[depth] = onel[depth]; next }
    if (line ~ /^#endif([^A-Za-z_0-9]|$)/ || line ~ /^#endplat([^A-Za-z_0-9]|$)/) { if (depth > 0) depth--; next }
    if (line ~ /^#/) next
    code = mask(line); ln = FNR
    while (match(code, /syscall\([ \t]*(0x[0-9A-Fa-f]+|[0-9]+)[ \t]*[,)]/)) {
        num = substr(code, RSTART + 8); sub(/^[ \t]*/, "", num); sub(/[ \t]*[,)].*$/, "", num)
        rest = substr(code, RSTART + 8)
        extra = 0
        while ((a = argc_of(rest)) < 0 && extra < 8 && (getline nxt) > 0) { rest = rest " " mask(nxt); extra++ }
        code = substr(code, RSTART + RLENGTH)
        v = (num ~ /^0x/) ? strtonum(num) : num + 0
        SITES++
        if (depth > 0 && !on[depth]) continue
        if (a < 0) { printf "UNPARSED %s:%d\n", FILENAME, ln; continue }
        REACHED++
        printf "%d %d %s:%d\n", v, a, FILENAME, ln
    }
}
END { printf "TOTAL %d %d\n", SITES, REACHED }
AWK

for T in x86 arm; do
    if [ "$T" = x86 ]; then tfiles=$(echo "$files" | grep -v '^lib/syscalls_aarch64_linux\.cyr$')
    else tfiles=$(echo "$files" | grep -v '^lib/syscalls_macos\.cyr$'); fi
    # shellcheck disable=SC2086
    awk -v T="$T" -f "$TMP/scan.awk" $tfiles > "$TMP/sites.$T"
    total=$(sed -n 's/^TOTAL \([0-9]*\) .*/\1/p' "$TMP/sites.$T"); reached=$(sed -n 's/^TOTAL [0-9]* \([0-9]*\)$/\1/p' "$TMP/sites.$T")
    if grep -q '^UNPARSED' "$TMP/sites.$T"; then
        echo "FAIL: darwin_syscall_literals_routed: $T — could not find the end of a syscall( call:"; grep '^UNPARSED' "$TMP/sites.$T"; exit 1
    fi
    [ "${total:-0}" -ge 150 ] || { echo "FAIL: darwin_syscall_literals_routed: $T found only ${total:-0} literal sites (want >= 150) — the scan matched nothing"; exit 1; }
    [ "${reached:-0}" -ge 60 ] || { echo "FAIL: darwin_syscall_literals_routed: $T reached only ${reached:-0} sites (want >= 60) — the reach table excludes everything"; exit 1; }
    grep -v '^TOTAL' "$TMP/sites.$T" | awk '{print $1, $2}' | sort -u > "$TMP/pairs.$T"
    : > "$TMP/unrouted.$T"
    for A in $(awk '{print $2}' "$TMP/pairs.$T" | sort -n -u); do
        awk -v A="$A" '$2 == A { s = "syscall(" $1; for (i = 1; i < A; i++) s = s ", 0"; print s ");" }' "$TMP/pairs.$T" > "$TMP/probe.$T.$A.cyr"
        macho_compile "$T" "$TMP/probe.$T.$A.cyr" "$TMP/probe.$T.$A.err"
        warned_numbers "$TMP/probe.$T.$A.err" | awk -v A="$A" '{print $1, A}' >> "$TMP/unrouted.$T"
    done
    nprobe=$(wc -l < "$TMP/pairs.$T" | tr -d ' ')
    bad=$(grep -v '^TOTAL' "$TMP/sites.$T" | awk -v T="$T" -v U="$TMP/unrouted.$T" '
        BEGIN { while ((getline l < U) > 0) { split(l, f, " "); u[f[1] " " f[2]] = 1 } }
        ($1 " " $2) in u {
            if ($3 ~ /^tests\/tcyr\/crossos\/darwin_unrouted_syscall_faults\.tcyr:/ && $1 == 4001) next
            printf "    UNROUTED on %s-macOS  %s  syscall(%s, …) with %d argument(s) incl. the number\n", T, $3, $1, $2
        }')
    if [ -n "$bad" ]; then echo "$bad"; fail=$((fail + $(echo "$bad" | wc -l))); fi
    echo "  axis 1 ($T-macOS): $reached of $total literal sites reached, $nprobe (number, argc) probes compiled"
done

# ── axis 2: the builds ───────────────────────────────────────────────────────────────
builds=$(find programs -maxdepth 1 -name '*.cyr' | sort; echo cbt/cyrius.cyr; find tests/tcyr/crossos -name '*.tcyr' | sort)
nbuilds=$(echo "$builds" | wc -l)
[ "$nbuilds" -ge 120 ] || { echo "FAIL: darwin_syscall_literals_routed: only $nbuilds builds to check (want >= 120)"; exit 1; }
for T in x86 arm; do
    nw=0
    for f in $builds; do
        macho_compile "$T" "$f" "$TMP/b.err"
        for n in $(warned_numbers "$TMP/b.err"); do
            case "$f:$n" in tests/tcyr/crossos/darwin_unrouted_syscall_faults.tcyr:4001) continue ;; esac
            echo "    WARNS on $T-macOS  $f  syscall $n not routed"
            nw=$((nw + 1))
        done
    done
    fail=$((fail + nw))
    echo "  axis 2 ($T-macOS): $nbuilds builds, $nw unexpected 'not routed' warning(s)"
done

if [ "$fail" -ne 0 ]; then
    echo "FAIL: darwin_syscall_literals_routed: $fail syscall(s) a macOS build reaches are not routed by the Mach-O translation."
    echo "      Route the number (an ESYSXLAT / EMACHO_SYSXLAT row), decline it under #ifdef CYRIUS_TARGET_MACOS, or spell the stdlib wrapper."
    exit 1
fi
echo "PASS darwin_syscall_literals_routed: every literal site and every shipped build a macOS target compiles is routed on both Macs"
