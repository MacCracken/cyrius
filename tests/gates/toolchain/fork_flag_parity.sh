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
#   syntax   — `--syntax-only` makes a file whose only fault is an unresolved name compile
#              clean (rc 0), and without it the same file is rc 1 naming the name
#              (anti-vacuous). `cyrius lint`'s pre-pass passes the flag on every host; the
#              aarch64 /proc walkers and the macOS argv scan never read it, so lint refused
#              valid multi-file module files on pi, ecb and ach. (REFACTOR-01) The cx driver
#              (all four of its per-target argv blocks) reads it too, for parity. (REVBE-02)
#   pie      — every aarch64 compiler honours `--pie` and CYRIUS_PIE=1 (ET_DYN that runs) and
#              defaults to ET_EXEC. The native fork read neither and wrote ET_EXEC, rc 0.
#   macho    — the native aarch64 fork, which has no Mach-O emitter, REFUSES CYRIUS_MACHO_ARM=1
#              by name (rc 1, no output). It compiled the program and wrote 0 bytes, rc 0.
#   kernel   — every aarch64 compiler honours CYRIUS_KERNEL=1 (what `cyrius build
#              --target=aarch64-bare-metal-elf` injects) and CYRIUS_KERNEL_BASE: the image's
#              entry is base + 0x78 and it is byte-identical to the cross's. The native fork read
#              neither: asked for a kernel image it wrote a 65 KB userland ELF, rc 0, without a word.
#
# MUTATION LEDGER (6.6.20, scratch copies of src/, never the repo):
#   real tree                                          -> GREEN
#   `var _strict_mode = 0;` re-added to src/main.cyr   -> RED "strict: src/main.cyr declares _strict_mode"
#   the `--sy` arm deleted from main_aarch64.cyr       -> RED "syntax a64_cross" + "syntax aarch64_qemu"
#   the CYRIUS_PIE read deleted from the native fork   -> RED "pie native_qemu env: rc 0, e_type EXEC"
#   the native CYRIUS_MACHO_ARM refusal deleted        -> RED "macho native_qemu: rc 0, 0 bytes out"
#   the `--sy` arms deleted from main_cx.cyr           -> RED "syntax cx" + "syntax cx.exe_wine"
#   the CYRIUS_KERNEL / _BASE reads deleted from the native fork
#                                                      -> RED "kernel native_qemu default" + "kernel native_qemu 0x40200000"
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
    mk cx.exe   src/main_cx.cyr  "$CC" CYRIUS_TARGET_WIN=1
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
cycc.exe_wine|env HOME=$T/whome XDG_CACHE_HOME=$T/whome/.cache wine $T/cycc.exe
cx.exe_wine|env HOME=$T/whome XDG_CACHE_HOME=$T/whome/.cache wine $T/cx.exe"

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

# ── syntax: --syntax-only honoured, its absence still resolves ──────────────────────────
printf 'fn f(): i64 { return not_declared_anywhere; }\nvar r = f();\n' > "$T/u.cyr"
printf '%s\n' "$FORKS" | while IFS='|' read -r l c; do
    a=0; $c --syntax-only < "$T/u.cyr" > "$T/y1" 2> "$T/y1.err" || a=$?
    b=0; $c < "$T/u.cyr" > "$T/y2" 2> "$T/y2.err" || b=$?
    [ "$a" = 0 ] || { echo "  FAIL: fork_flag_parity syntax $l: --syntax-only rc $a: $(grep -m1 error "$T/y1.err")"; echo x >> "$T/red"; }
    { [ "$b" != 0 ] && grep -q not_declared_anywhere "$T/y2.err"; } \
        || { echo "  FAIL: fork_flag_parity syntax $l: without the flag rc $b (want 1, naming the name)"; echo x >> "$T/red"; }
    echo x >> "$T/nrows"
done

# ── pie / macho: the aarch64 compilers ──────────────────────────────────────────────────
etype() { od -An -j16 -N2 -tx1 "$1" | tr -d ' \n'; }   # 0200 = ET_EXEC, 0300 = ET_DYN
printf 'fn main(): i64 { return 42; }\n' > "$T/m.cyr"
AFORKS="a64_cross|$T/a64x"
[ "$HAVE_QEMU" = 1 ] && AFORKS="$AFORKS
aarch64_qemu|qemu-aarch64 $T/a64
native_qemu|qemu-aarch64 $T/a64n"
printf '%s\n' "$AFORKS" | while IFS='|' read -r l c; do
    for how in none env flag; do
        rc=0
        case $how in
            none) $c < "$T/m.cyr" > "$T/pie" 2> "$T/pie.err" || rc=$? ;;
            env)  env CYRIUS_PIE=1 $c < "$T/m.cyr" > "$T/pie" 2> "$T/pie.err" || rc=$? ;;
            flag) $c --pie < "$T/m.cyr" > "$T/pie" 2> "$T/pie.err" || rc=$? ;;
        esac
        want=0300; [ $how = none ] && want=0200
        got=$(etype "$T/pie")
        echo x >> "$T/nrows"
        if [ "$rc" != 0 ] || [ "$got" != "$want" ]; then
            nm=EXEC; [ "$got" = 0300 ] && nm=DYN
            echo "  FAIL: fork_flag_parity pie $l $how: rc $rc, e_type $nm ($got, want $want)"; echo x >> "$T/red"; continue
        fi
        if [ "$HAVE_QEMU" = 1 ]; then
            chmod +x "$T/pie"; r=0; qemu-aarch64 "$T/pie" || r=$?
            [ "$r" = 42 ] || { echo "  FAIL: fork_flag_parity pie $l $how: the binary exited $r (want 42)"; echo x >> "$T/red"; }
        fi
    done
done
if [ "$HAVE_QEMU" = 1 ]; then
    rc=0; env CYRIUS_MACHO_ARM=1 qemu-aarch64 "$T/a64n" < "$T/m.cyr" > "$T/mo" 2> "$T/mo.err" || rc=$?
    rows=$((rows + 1))
    if [ "$rc" = 0 ] || [ -s "$T/mo" ] || ! grep -q CYRIUS_MACHO_ARM "$T/mo.err"; then
        bad "macho native_qemu: rc $rc, $(wc -c < "$T/mo" | tr -d ' ') bytes out (want a refusal naming CYRIUS_MACHO_ARM, rc 1, no output)"
    fi
fi

# ── kernel: CYRIUS_KERNEL / CYRIUS_KERNEL_BASE on the aarch64 compilers ─────────────────
entry() { od -An -j24 -N8 -tx8 "$1" | tr -d ' \n'; }
printf 'var x = 1;\n' > "$T/k.cyr"
printf '%s\n' "$AFORKS" | while IFS='|' read -r l c; do
    for base in default 0x40200000; do
        rc=0
        if [ "$base" = default ]; then
            want=0000000040000078
            env CYRIUS_KERNEL=1 $c < "$T/k.cyr" > "$T/kimg" 2> "$T/kimg.err" || rc=$?
        else
            want=0000000040200078
            env CYRIUS_KERNEL=1 CYRIUS_KERNEL_BASE=$base $c < "$T/k.cyr" > "$T/kimg" 2> "$T/kimg.err" || rc=$?
        fi
        echo x >> "$T/nrows"
        got=$(entry "$T/kimg")
        if [ "$rc" != 0 ] || [ "$got" != "$want" ]; then
            echo "  FAIL: fork_flag_parity kernel $l $base: rc $rc, entry ${got:-none}, $(wc -c < "$T/kimg" | tr -d ' ') bytes (want rc 0, a kernel image at entry $want)"
            echo x >> "$T/red"; continue
        fi
        if [ "$l" = a64_cross ]; then cp "$T/kimg" "$T/kref_$base"
        elif ! cmp -s "$T/kimg" "$T/kref_$base"; then
            echo "  FAIL: fork_flag_parity kernel $l $base: the image differs from the cross's"; echo x >> "$T/red"
        fi
    done
done

[ -f "$T/nrows" ] && rows=$((rows + $(wc -l < "$T/nrows")))
[ -f "$T/red" ] && fail=$((fail + $(wc -l < "$T/red")))

if [ "$fail" -ne 0 ]; then echo "FAIL fork_flag_parity: $fail of $rows row(s) red"; exit 1; fi
echo "PASS fork_flag_parity: $rows rows — --strict a no-op and --syntax-only honoured on every runnable fork; aarch64 --pie / CYRIUS_PIE / CYRIUS_KERNEL(_BASE); native refuses CYRIUS_MACHO_ARM"
exit 0
