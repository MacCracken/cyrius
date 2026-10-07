#!/bin/sh
# FORK FLAG PARITY — every compiler fork honours the same command-line flags.
#
# WHY (6.6.20): each src/main*.cyr fork hand-copies its argv walker, and the copies drifted.
# fork_version_parity.sh holds `--version`; this gate holds the rest, row by row, on every fork
# that can execute here: x86 directly, the aarch64 cross (an x86 binary), the aarch64 and native
# aarch64 compilers under qemu-aarch64, the cx driver, the PE host stage directly and cycc.exe
# under wine. The two Mach-O drivers cannot execute on Linux — their argv arms are run on ecb/ach
# by scripts/cross-os-selfhost.sh. qemu and wine are emulation, not hardware: pi and cass run the
# real thing at the release gate.
#
# Rows:
#   strict   — `--strict` is ACCEPTED and does NOTHING (output byte-identical to no flag) on
#              every runnable fork, and no fork declares `_strict_mode` again: the global was
#              written by six argv walkers and read by nothing since v6.3.2. (DEAD-07)
#
# MUTATION LEDGER (6.6.20, scratch copies of src/, never the repo):
#   real tree                                          -> GREEN
#   `var _strict_mode = 0;` re-added to src/main.cyr   -> RED "strict: src/main.cyr declares _strict_mode"
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: fork_flag_parity: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: fork_flag_parity: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: fork_flag_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix (and wine's own HOME / XDG_CACHE_HOME) under $T; the EXIT teardown stops
# THIS prefix's wineserver and removes its server dir, which `wineserver -k` leaves behind.
WP="$T/wine"; mkdir -p "$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: fork_flag_parity $1"; fail=$((fail + 1)); }

# ── static: no fork declares the retired global ─────────────────────────────────────────
for f in src/main*.cyr; do
    rows=$((rows + 1))
    if sed 's/#.*//' "$f" | grep -qE '(^|[^_A-Za-z0-9])_strict_mode([^_A-Za-z0-9]|$)'; then
        bad "strict: $f declares _strict_mode (write-only since v6.3.2; removed 6.6.20)"
    fi
done

# ── build the runnable forks ────────────────────────────────────────────────────────────
mk() {   # $1 = out, $2 = source, $3 = compiler, $4.. = env
    o=$1; s=$2; c=$3; shift 3
    if ! cat "$s" | env "$@" $c > "$T/$o" 2> "$T/$o.err" || [ "$(wc -c < "$T/$o" | tr -d ' ')" -lt 1024 ]; then
        echo "FAIL: fork_flag_parity: building $o from $s failed: $(grep -m1 -i error "$T/$o.err")"; exit 1
    fi
    chmod +x "$T/$o"
}
mk a64x  src/main_aarch64.cyr        "$CC"
mk cx    src/main_cx.cyr             "$CC"
mk xwin  src/main_win.cyr            "$CC"
HAVE_QEMU=0; command -v qemu-aarch64 >/dev/null 2>&1 && HAVE_QEMU=1
HAVE_WINE=0; command -v wine >/dev/null 2>&1 && HAVE_WINE=1
if [ "$HAVE_QEMU" = 1 ]; then
    mk a64  src/main_aarch64.cyr        "$T/a64x"
    mk a64n src/main_aarch64_native.cyr "$T/a64x"
else
    echo "  SKIP (named): aarch64 / native rows — qemu-aarch64 is not installed"
fi
if [ "$HAVE_WINE" = 1 ]; then
    mk cycc.exe src/main_win.cyr "$T/xwin"
    export WINEPREFIX="$WP" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
else
    echo "  SKIP (named): cycc.exe row — wine is not installed"
fi
# Each runnable fork as "<label>|<command>". wine gets its own HOME, but only for that row.
FORKS="x86|$CC
a64_cross|$T/a64x
cx|$T/cx
win_host|$T/xwin"
[ "$HAVE_QEMU" = 1 ] && FORKS="$FORKS
aarch64_qemu|qemu-aarch64 $T/a64
native_qemu|qemu-aarch64 $T/a64n"
[ "$HAVE_WINE" = 1 ] && FORKS="$FORKS
cycc.exe_wine|env HOME=$T/whome XDG_CACHE_HOME=$T/whome/.cache wine $T/cycc.exe"

# ── strict: accepted, and a no-op ───────────────────────────────────────────────────────
printf 'fn add(a, b): i64 { return a + b; }\nvar r = add(40, 2);\nsyscall(60, r);\n' > "$T/p.cyr"
printf '%s\n' "$FORKS" | while IFS='|' read -r l c; do
    a=0; $c < "$T/p.cyr" > "$T/s0" 2> "$T/s0.err" || a=$?
    b=0; $c --strict < "$T/p.cyr" > "$T/s1" 2> "$T/s1.err" || b=$?
    if [ "$a" != 0 ] || [ "$b" != 0 ]; then
        echo "  FAIL: fork_flag_parity strict $l: rc $a without --strict, $b with it"; echo x >> "$T/red"
    elif ! cmp -s "$T/s0" "$T/s1"; then
        echo "  FAIL: fork_flag_parity strict $l: --strict changed the output (it is a no-op since 6.6.20)"; echo x >> "$T/red"
    fi
    echo x >> "$T/nrows"
done
[ -f "$T/nrows" ] && rows=$((rows + $(wc -l < "$T/nrows")))
[ -f "$T/red" ] && fail=$((fail + $(wc -l < "$T/red")))

if [ "$fail" -ne 0 ]; then echo "FAIL fork_flag_parity: $fail of $rows row(s) red"; exit 1; fi
echo "PASS fork_flag_parity: $rows rows — --strict accepted as a no-op on every runnable fork, _strict_mode gone"
exit 0
