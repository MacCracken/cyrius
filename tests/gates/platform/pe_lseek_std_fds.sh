#!/bin/sh
# 6.7.15 — a seek on fd 0 / 1 / 2 reaches the std stream on PE, as it does on Linux and macOS
# (issues/2026-10-16-pe-lseek-std-fds-pass-raw-handle.md).
#
# ⛔ WHY: ELSEEK_PE (src/backend/x86/emit.cyr) popped the fd straight into rcx and called
# SetFilePointerEx with it, so fd 0 / 1 / 2 reached kernel32 as the HANDLE values 0 / 1 / 2 — not
# handles — and every seek on a redirected stdin / stdout / stderr failed ERROR_INVALID_HANDLE, -9
# (the filed repro printed `-9 -9 -9 1 97` under wine and on real cass; Linux `3 0 0 1 100`).
# Every other fd-taking reroute (EWRITE_PE, EREAD_PE, EFLUSHFB_PE) maps the std fds through
# `_pe_fd_to_handle_rcx` (fd 0 / 1 / 2 -> GetStdHandle(-10 / -11 / -12), any other fd used as the
# handle). ELSEEK_PE now does too: offset and whence are parked at [rsp+0x30] / [rsp+0x38] of a
# 0x40 frame across the GetStdHandle call, the EWRITE_PE shape.
#
# A PIPE OR CONSOLE std handle — measured 2026-10-18 on real cass (Windows 11): SetFilePointerEx
# SUCCEEDS on both and the stream does not move (the filed repro with a piped stdin prints
# `3 0 0 1 97`; with a console stdin / stdout / stderr the seeks answer 3 / 0 / 0). wine 11.19
# fails it ERROR_INVALID_FUNCTION (1), which has no row in the shared GetLastError table: -1
# (`-1 0 0 1 97`). Linux and macOS answer -ESPIPE (-29). The pipe row below pins wine's answer
# and the part both Windows answers share: the std handle is reached (never the old -9), and the
# stream does not move (the next byte read is 'a'). Whether a Windows pipe / console seek should
# answer -29 is filed, not decided here (6.7.15 platform lane staging).
#
# THE AXES
#   axis 1  POSIX ORACLE (always): the filed repro, verbatim, natively: `3 0 0 1 100` with every
#           std stream redirected to / from a file, `-29 0 0 1 97` with a piped stdin.
#   axis 2  EMITTER SHAPE (objdump): a probe with a literal seek and a var-held one
#           (EPE_SYSCALL_DYNAMIC's argc-4 switch) builds for PE. EVERY call through the
#           SetFilePointerEx IAT slot is reached through the std-fd map: `cmp $0x2,%rax` and a call
#           through GetStdHandle's slot before it, offset / whence stored to 0x30 / 0x38(%rsp)
#           before the map and reloaded into rdx / r9 after it, and the frame's `sub` and `add`
#           equal (0x40, or 0x48 at odd depth). At least 2 sites (anti-vacuous). CI has no wine:
#           this axis is what pins the fix there.
#   axis 3  BEHAVIOUR under wine (skipped without wine — NOT hardware; the real-cass run is in
#           the CHANGELOG): the filed repro, verbatim, prints `3 0 0 1 100` with stdin / stdout /
#           stderr redirected to / from files; with a piped stdin `-1 0 0 1 97` (see above).
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-10-18 (6.7.15 platform lane, P2; x86_64 Linux
# + wine 11.19; CYCC=<mutant cycc>):
#   mutant                                                  result
#   the pre-fix compiler (b2e1f4c48)                        axis 2 FAIL (no GetStdHandle before the
#                                                           SetFilePointerEx call); axis 3 FAIL
#                                                           (`-9 -9 -9 1 97`, piped too)
#   ELSEEK_PE's `_pe_fd_to_handle_rcx` back to `mov rcx, rax`  axes 2, 3 FAIL
#   the r9 (whence) reload dropped                          axis 2 FAIL (not reloaded); axis 3
#                                                           PASSES — wine's GetStdHandle leaves r9
#                                                           alone, which Win64 does not promise
#                                                           (r9 is volatile): why axis 2 reads it
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.15]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: pe_lseek_std_fds: build/cycc missing"; exit 77; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_lseek_std_fds: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache. The EXIT teardown stops THIS prefix's wineserver and removes its server
# dir, which `wineserver -k` leaves behind (the pe_last_error_reroute.sh shape). CHANGELOG [6.6.17]
WP="$D/wp"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT INT TERM

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }
# The five printed values on one line, CRs dropped.
line() { tr -d '\r' < "$1" | tr '\n' ' ' | sed 's/ *$//'; }

# The filed repro, verbatim.
cat > "$D/stdseek.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var a = xlseek(0, 3, 0);      # stdin redirected from a file: SEEK_SET to 3
var b = xlseek(1, 0, 1);      # stdout redirected to a file: SEEK_CUR
var c = xlseek(2, 0, 2);      # stderr redirected to a file: SEEK_END
var ch[8];
store64(&ch, 0);
var n = file_read(0, &ch, 1); # the byte at stdin's position
fmt_int(a); println("");
fmt_int(b); println("");
fmt_int(c); println("");
fmt_int(n); println("");
fmt_int(load8(&ch)); println("");
EOF
printf 'abcdefgh' > "$D/in.txt"

# axis 1: the POSIX oracle.
mkdir -p "$D/n"
( cd "$ROOT" && "$CC" < "$D/stdseek.cyr" > "$D/n/stdseek" 2> "$D/n/stdseek.err" ) || true
if [ ! -s "$D/n/stdseek" ]; then
    bad "axis 1: the native build of the repro produced no binary: $(grep -m2 '^error' "$D/n/stdseek.err" | tr '\n' ' ')"
else
    chmod +x "$D/n/stdseek"
    ( cd "$D/n" && ulimit -c 0; ./stdseek < "$D/in.txt" > f.out 2> f.err ) || true
    got=$(line "$D/n/f.out")
    if [ "$got" = "3 0 0 1 100" ]; then ok; else bad "axis 1: the repro natively, std streams redirected to / from files, prints '$got' (want '3 0 0 1 100')"; fi
    ( cd "$D/n" && ulimit -c 0; printf 'abcdefgh' | ./stdseek > p.out 2> p.err ) || true
    got=$(line "$D/n/p.out")
    if [ "$got" = "-29 0 0 1 97" ]; then ok; else bad "axis 1: the repro natively with a piped stdin prints '$got' (want '-29 0 0 1 97': -ESPIPE, the pipe unmoved)"; fi
fi

# axis 2: the emitter shape.
cat > "$D/shape.cyr" <<'EOF'
fn by_number(nr, a, b, c): i64 { return syscall(nr, a, b, c); }
fn main(): i64 {
    var r = syscall(8, 0, 3, 0);
    r = r + by_number(8, 1, 0, 1);
    return r;
}
var r = main();
syscall(60, r & 255);
EOF
CYRIUS_TARGET_WIN=1 "$CC" < "$D/shape.cyr" > "$D/shape.exe" 2> "$D/shape.err" || true
if [ ! -s "$D/shape.exe" ]; then
    bad "axis 2: the PE build of the shape probe produced no binary: $(grep -m2 'error' "$D/shape.err" | tr '\n' ' ')"
elif ! objdump -p "$D/shape.exe" > "$D/imp" 2>/dev/null || ! grep -q 'DLL Name' "$D/imp"; then
    echo "  SKIP: axis 2 (no objdump that reads PE)"
else
    objdump -dw "$D/shape.exe" > "$D/dis" 2>/dev/null
    va() { s=$(awk -v n="$1" '$NF == n {print $1; exit}' "$D/imp"); [ -n "$s" ] && printf '0x%x' $((0x140000000 + 0x$s)); }
    SF=$(va SetFilePointerEx); GS=$(va GetStdHandle)
    if [ -z "$SF" ] || [ -z "$GS" ]; then
        bad "axis 2: the probe does not import SetFilePointerEx and GetStdHandle ('$SF' '$GS')"
    else
        # Per SetFilePointerEx IAT call site: "<ok|BAD:why>". Instruction text only (after the 2nd tab).
        awk -F'\t' -v sf="$SF" -v gs="$GS" '
            NF >= 3 { n++; t[n] = $3 }
            function slot(x,   k) { k = x; if (k !~ /^call +\*0x[0-9a-f]+\(%rip\)/) return ""; sub(/.*# /, "", k); return k }
            function imm(x,   k) { k = x; sub(/^[a-z]+ +\$/, "", k); sub(/,.*/, "", k); return k }
            END {
                for (i = 1; i <= n; i++) {
                    if (slot(t[i]) != sf) continue
                    why = "ok"
                    # The nearest IAT call before this one must be the std-fd map'"'"'s GetStdHandle.
                    g = 0
                    for (k = i - 1; k >= 1 && k >= i - 20; k--) if (slot(t[k]) != "") { g = k; break }
                    if (g == 0 || slot(t[g]) != gs) { print "BAD:no-GetStdHandle-call-before-it"; continue }
                    rd = 0; r9 = 0
                    for (k = g + 1; k < i; k++) {
                        if (t[k] ~ /^mov +0x30\(%rsp\),%rdx/) rd = 1
                        if (t[k] ~ /^mov +0x38\(%rsp\),%r9/) r9 = 1
                    }
                    cm = 0; sd = 0; s9 = 0; sb = 0
                    for (k = g - 1; k >= 1 && k >= g - 12; k--) {
                        if (t[k] ~ /^cmp +\$0x2,%rax/) cm = 1
                        if (t[k] ~ /^mov +%rdx,0x30\(%rsp\)/) sd = 1
                        if (t[k] ~ /^mov +%r9,0x38\(%rsp\)/) s9 = 1
                        if (sb == 0 && t[k] ~ /^sub +\$0x[0-9a-f]+,%rsp/) sb = k
                    }
                    ad = 0
                    for (k = i + 1; k <= n && k <= i + 6; k++) if (t[k] ~ /^add +\$0x[0-9a-f]+,%rsp/) { ad = k; break }
                    if (cm == 0) why = "BAD:no-std-fd-test(cmp $0x2,%rax)"
                    else if (sd == 0 || s9 == 0) why = "BAD:offset-whence-not-parked-before-GetStdHandle"
                    else if (rd == 0 || r9 == 0) why = "BAD:offset-whence-not-reloaded-after-GetStdHandle"
                    else if (sb == 0 || ad == 0 || imm(t[sb]) != imm(t[ad]) || imm(t[sb]) !~ /^0x4[08]$/) why = "BAD:frame-sub-add(" t[sb] " / " t[ad] ")"
                    print why
                }
            }' "$D/dis" > "$D/sites"
        c=$(wc -l < "$D/sites" | tr -d ' ')
        b=$(grep -v '^ok$' "$D/sites" | head -1 || true)
        if [ "$c" -lt 2 ]; then bad "axis 2: only $c SetFilePointerEx site(s) in the probe (floor 2: the literal and the var-held route)"
        elif [ -n "$b" ]; then bad "axis 2: a SetFilePointerEx site is not reached through the std-fd map ($b)"
        else ok; fi
    fi
fi

# axis 3: behaviour under wine.
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: axis 3 (wine absent — the real-cass run is recorded in the CHANGELOG)"
else
    mkdir -p "$D/w"
    _wine() {  # $1 = exe name inside $D/w, $2 / $3 = stdout / stderr captures; stdin is the caller's
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine "$1" > "$2" 2> "$3" )
    }
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/stdseek.cyr" > "$D/w/stdseek.exe" 2> "$D/w.err" ) || true
    if [ ! -s "$D/w/stdseek.exe" ]; then
        bad "axis 3: the PE build of the repro produced no binary: $(grep -m2 '^error' "$D/w.err" | tr '\n' ' ')"
    else
        # Warm the prefix first: its creation writes to stderr, and the repro's stderr row seeks
        # SEEK_END on the file stderr goes to.
        _wine stdseek.exe /dev/null /dev/null < "$D/in.txt" || true
        _wine stdseek.exe "$D/w/f.out" "$D/w/f.err" < "$D/in.txt" || true
        got=$(line "$D/w/f.out")
        if [ "$got" = "3 0 0 1 100" ]; then ok; else bad "axis 3: the repro under wine, std streams redirected to / from files, prints '$got' (want '3 0 0 1 100'; '-9 -9 -9 1 97' is the old raw-handle answer)"; fi
        printf 'abcdefgh' | _wine stdseek.exe "$D/w/p.out" "$D/w/p.err" || true
        got=$(line "$D/w/p.out")
        if [ "$got" = "-1 0 0 1 97" ]; then ok; else bad "axis 3: the repro under wine with a piped stdin prints '$got' (want '-1 0 0 1 97': wine's ERROR_INVALID_FUNCTION, the pipe unmoved; real cass '3 0 0 1 97'; '-9 -9 -9 1 97' is the old raw-handle answer)"; fi
    fi
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 2 ] || { echo "FAIL: pe_lseek_std_fds: only $pass rows ran (floor 2)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_lseek_std_fds"; exit 1; fi
echo "PASS: pe_lseek_std_fds — a seek on fd 0 / 1 / 2 reaches the std stream on PE (GetStdHandle), as on Linux"
