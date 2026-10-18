#!/bin/sh
# ts_flags_every_driver.sh — 6.7.15 (platform lane, P5; 6.7.15's D38).
#
# `--lex-ts`, `--parse-ts` and `--emit-js` run the TypeScript front end on EVERY compiler, with
# the answers and output of the x86_64 Linux one.
#
# ⛔ WHAT IT DID BEFORE. Only src/main.cyr included the TS front end and read the three flags.
# Every other driver skipped them like any unknown flag and compiled the TypeScript AS CYRIUS:
#   $ qemu-aarch64 ./cycc-aarch64-native --parse-ts < a.ts      # a.ts: let x: number = 1;
#   error:<source>:1:5: expected '=', got identifier 'x'   ...   a64rc=1
#   $ echo 'var x = 42;' | qemu-aarch64 ./cycc-aarch64-native --parse-ts > out   # rc 0, out an ELF
# so the aarch64 tarball's `ts_test_runner` reported every .ts as failed (`0/1 passed (1 failed)`
# on pi). The four TS driver files (src/frontend/ts/driver_flags.cyr / driver_args.cyr /
# driver_input.cyr / driver.cyr) are now in every driver; src/main.cyr's own include of them
# builds cycc byte-identical (its arms stay inline).
#
#   axis 1  the filed repro VERBATIM on the native aarch64 compiler (qemu): `let x: number = 1;`
#           --parse-ts rc 0 with no output; `var x = 42;` --parse-ts rc 0 and NO binary on stdout.
#   axis 2  every runnable driver — the aarch64 cross compiler and the Windows cross compiler
#           (x86 ELFs, their /proc arms), the aarch64 compilers built from main_aarch64.cyr and
#           main_aarch64_native.cyr (qemu), the PE cycc.exe (wine, a private prefix: its
#           GetCommandLineW split) — over the TS corpus (tests/fixtures/**/*.ts|tsx, floor 40)
#           and crafted lex / parse errors: each of --lex-ts / --parse-ts / --emit-js, from
#           stdin and as `<flag> <file>`, gives x86_64's exit code, stdout bytes and stderr
#           text; a missing file is `error: cannot open '<file>'`, exit 1.
#   axis 3  both Mach-O compilers are built (arm64: cputype 0x0100000c; x86_64: 0x01000007) and
#           carry the TS modes (their diagnostics are in the binary). They run on ecb / ach in
#           the cross-OS legs (scripts/cross-os-selfhost.sh), not here.
#   axis 4  `ts_test_runner` built for aarch64, in an aarch64 install layout ($HOME/.cyrius/bin/
#           cycc, the native compiler through qemu): a clean .ts dir reports `1/1 passed` rc 0,
#           a bad one `0/1 passed (1 failed)` rc 1.
#
# MUTATION LEDGER (measured at 6.7.15: a scratch tree, the drivers swapped for 6.7.14's):
#   M1. every non-main driver back to 6.7.14 (no TS front end)  -> RED: axes 1, 2, 3, 4
#   M2. driver_args.cyr's `--pa` arm removed (parse-ts unread)  -> RED: axes 1, 2, 4
#   M3. the Windows driver's `_ts_args_win()` call removed      -> RED: axis 2 (wine rows only)
#   M4. the drivers' read loop back to fd 0 (the path ignored)  -> RED: axis 2 (the path rows)
#   Real tree -> GREEN.
#
# ⚠ qemu-aarch64 and wine are EMULATORS, not hardware: the same rows ran on real pi, ecb, ach
# and cass for this change (CHANGELOG [6.7.15]); the cross-OS legs keep a --parse-ts row.
# Legs that cannot run (no qemu-aarch64 / no wine) SKIP by name; the whole gate is then 77.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: ts_flags_every_driver: build/cycc missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: ts_flags_every_driver: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache; the EXIT teardown stops THIS prefix's wineserver and removes its server
# dir (the pe_last_error_reroute.sh shape).
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

pass=0; fail=0; skips=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

HAVE_QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && HAVE_QEMU=1
HAVE_WINE=0; command -v wine > /dev/null 2>&1 && HAVE_WINE=1

# ── the compilers ────────────────────────────────────────────────────────────────────
_build() {   # _build OUT ENV COMPILER SOURCE
    _o=$1; _e=$2; _c=$3; _s=$4
    rc=0; env $_e "$_c" < "$_s" > "$D/$_o" 2> "$D/$_o.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$D/$_o" ]; then
        bad "build: $_s ($_o) did not build (rc $rc)"; sed -n 1,5p "$D/$_o.err" | sed 's/^/      /'
        return 1
    fi
    chmod +x "$D/$_o"
    return 0
}
_build a64x "" "$CC" src/main_aarch64.cyr || { echo "FAIL ts_flags_every_driver"; exit 1; }
_build winx "" "$CC" src/main_win.cyr || true
_build a64  "" "$D/a64x" src/main_aarch64.cyr || true
_build nat  "" "$D/a64x" src/main_aarch64_native.cyr || true
_build exe  "" "$D/winx" src/main_win.cyr || true
_build m    "CYRIUS_MACHO_ARM=1" "$D/a64x" src/main_aarch64_macho.cyr || true
_build mx   "CYRIUS_MACHO=1" "$CC" src/main_x86_macho.cyr || true

# ── the corpus: the TS fixtures + crafted errors, flat in $D/c ───────────────────────
mkdir -p "$D/c"
n=0
for f in $(find tests/fixtures -name '*.ts' -o -name '*.tsx' | LC_ALL=C sort); do
    n=$((n + 1))
    cp "$f" "$D/c/f$(printf %03d $n).${f##*.}"
done
if [ "$n" -lt 40 ]; then bad "corpus: $n TS fixtures under tests/fixtures (floor 40)"; fi
printf 'let s = "abc\n' > "$D/c/e_unterminated.ts"         # lex error 4
printf 'const t = `abc ${\n' > "$D/c/e_template.ts"           # lex error 9
printf '/* never closed\nlet x = 1;\n' > "$D/c/e_comment.ts"  # lex error 10 (two digits)
printf 'let x: number = ;\n' > "$D/c/e_parse.ts"
printf 'function f( { return 1; }\n' > "$D/c/e_parse2.ts"
FILES=$(cd "$D/c" && ls | LC_ALL=C sort)

# _table RUNNER COMPILER OUT — one line per (file, flag, form): rc, stdout cksum, stderr cksum
# (CRs stripped from stderr: cmd / wine may add them). Run from $D/c, so a path is relative.
_table() {
    _r=$1; _c=$2; _out=$3
    : > "$_out"
    for f in $FILES; do
        for m in --lex-ts --parse-ts --emit-js; do
            rc=0; ( cd "$D/c" && $_r "$_c" $m < "$f" > "$D/o.out" 2> "$D/o.err" ) || rc=$?
            echo "$f $m stdin rc=$rc out=$(cksum < "$D/o.out" | tr -s ' ' | cut -d' ' -f1-2) err=$(tr -d '\r' < "$D/o.err" | cksum | tr -s ' ' | cut -d' ' -f1-2)" >> "$_out"
            rc=0; ( cd "$D/c" && $_r "$_c" $m "$f" < /dev/null > "$D/o.out" 2> "$D/o.err" ) || rc=$?
            echo "$f $m path rc=$rc out=$(cksum < "$D/o.out" | tr -s ' ' | cut -d' ' -f1-2) err=$(tr -d '\r' < "$D/o.err" | cksum | tr -s ' ' | cut -d' ' -f1-2)" >> "$_out"
        done
    done
    rc=0; ( cd "$D/c" && $_r "$_c" --parse-ts no_such_file.ts < /dev/null > "$D/o.out" 2> "$D/o.err" ) || rc=$?
    echo "missing rc=$rc err=$(tr -d '\r' < "$D/o.err")" >> "$_out"
}
_table "" "$CC" "$D/t_x86"
nrows=$(grep -c . "$D/t_x86" || true)
nfail=$(grep -c 'rc=1' "$D/t_x86" || true)
if [ "$nrows" -lt 271 ] || [ "$nfail" -lt 20 ]; then
    bad "oracle: x86_64's table has $nrows rows, $nfail failing (floors 271 / 20) — the corpus or the errors went missing"
fi
grep -qxF "missing rc=1 err=error: cannot open 'no_such_file.ts'" "$D/t_x86" \
    || bad "oracle: x86_64 on a missing file: '$(tail -1 "$D/t_x86")'"

_cmp_table() {   # _cmp_table LABEL RUNNER COMPILER
    _l=$1
    [ -x "$3" ] || { bad "axis 2 $_l: no compiler"; return 0; }
    _table "$2" "$3" "$D/t_$_l"
    if cmp -s "$D/t_x86" "$D/t_$_l"; then ok
    else
        bad "axis 2 $_l: $(diff "$D/t_x86" "$D/t_$_l" | grep -c '^>' || true) of $nrows rows differ from x86_64's:"
        diff "$D/t_x86" "$D/t_$_l" | head -6 | sed 's/^/      /'
    fi
}
_wine() { LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all timeout 120 wine "$@"; }

# ── axis 1 — the filed repro, verbatim, on the native aarch64 compiler ────────────────
if [ "$HAVE_QEMU" -eq 1 ] && [ -x "$D/nat" ]; then
    printf 'let x: number = 1;\n' > "$D/a.ts"
    rc=0; qemu-aarch64 "$D/nat" --parse-ts < "$D/a.ts" > "$D/r1.out" 2> "$D/r1.err" || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$D/r1.out" ] && [ ! -s "$D/r1.err" ]; then ok
    else bad "axis 1: --parse-ts on 'let x: number = 1;' rc $rc, $(wc -c < "$D/r1.out") B out, stderr '$(head -1 "$D/r1.err")' (want rc 0, nothing; 6.7.14: rc 1, expected '='...)"; fi
    rc=0; echo 'var x = 42;' | qemu-aarch64 "$D/nat" --parse-ts > "$D/r2.out" 2> "$D/r2.err" || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$D/r2.out" ]; then ok
    else bad "axis 1: 'var x = 42;' --parse-ts rc $rc and $(wc -c < "$D/r2.out") B on stdout (want rc 0 and none; 6.7.14 wrote an ELF)"; fi
else
    echo "  SKIP: axis 1 (qemu-aarch64 absent)"; skips=$((skips + 1))
fi

# ── axis 2 — every runnable driver gives x86_64's table ───────────────────────────────
_cmp_table a64x "" "$D/a64x"
_cmp_table winx "" "$D/winx"
if [ "$HAVE_QEMU" -eq 1 ]; then
    _cmp_table a64 qemu-aarch64 "$D/a64"
    _cmp_table nat qemu-aarch64 "$D/nat"
else
    echo "  SKIP: axis 2 a64 / nat (qemu-aarch64 absent)"; skips=$((skips + 1))
fi
if [ "$HAVE_WINE" -eq 1 ] && [ -s "$D/exe" ]; then
    mkdir -p "$WHM"
    cp "$D/exe" "$D/cycc.exe"
    # The first wine run creates the prefix and says so on stderr: warm it up off the table.
    _wine "$D/cycc.exe" --version < /dev/null > /dev/null 2>&1 || true
    _cmp_table exe _wine "$D/cycc.exe"
    # GetCommandLineW is split as CommandLineToArgvW splits it: a quoted path with a space, a
    # path after another flag, a non-ASCII name (UTF-16 -> UTF-8 -> the PE open's widen).
    mkdir -p "$D/c/d sp"
    cp "$D/c/f001.ts" "$D/c/d sp/a b.ts"; cp "$D/c/e_parse.ts" "$D/c/d sp/bad.ts"; cp "$D/c/f001.ts" "$D/c/é中.ts"
    "$CC" --emit-js < "$D/c/f001.ts" > "$D/q.want" 2> /dev/null || true
    rc=0; ( cd "$D/c" && _wine "$D/cycc.exe" --parse-ts "d sp\\a b.ts" < /dev/null > /dev/null 2>&1 ) || rc=$?
    [ "$rc" -eq 0 ] && ok || bad "axis 2 exe: --parse-ts \"d sp\\a b.ts\" rc $rc (want 0)"
    rc=0; ( cd "$D/c" && _wine "$D/cycc.exe" --parse-ts "d sp\\bad.ts" < /dev/null > /dev/null 2>&1 ) || rc=$?
    [ "$rc" -eq 1 ] && ok || bad "axis 2 exe: --parse-ts \"d sp\\bad.ts\" rc $rc (want 1)"
    rc=0; ( cd "$D/c" && _wine "$D/cycc.exe" --emit-js --allow-undef "é中.ts" < /dev/null > "$D/q.out" 2> /dev/null ) || rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$D/q.want" "$D/q.out"; then ok
    else bad "axis 2 exe: --emit-js --allow-undef é中.ts rc $rc, output $(cmp -s "$D/q.want" "$D/q.out" && echo equal || echo differs) (want 0, x86_64's JS)"; fi
    rm -rf "$D/c/d sp" "$D/c/é中.ts"
else
    echo "  SKIP: axis 2 exe (wine absent)"; skips=$((skips + 1))
fi

# ── axis 3 — the Mach-O compilers: built, the right arch, the TS modes in them ───────
_macho() {   # _macho LABEL FILE CPUTYPE-LE-HEX
    _f=$2
    [ -s "$_f" ] || { bad "axis 3 $1: not built"; return 0; }
    hdr=$(od -An -tx1 -N8 "$_f" | tr -d ' \n')
    if [ "$hdr" != "cffaedfe$3" ]; then bad "axis 3 $1: header $hdr (want cffaedfe$3)"; return 0; fi
    if grep -q 'ts parse error: code=' "$_f" && grep -q 'ts lex error before emit' "$_f"; then ok
    else bad "axis 3 $1: the TS modes' diagnostics are not in the binary — the modes are not linked in"; fi
}
_macho arm64 "$D/m" 0c000001
_macho x86_64 "$D/mx" 07000001

# ── axis 4 — ts_test_runner in an aarch64 install layout ──────────────────────────────
if [ "$HAVE_QEMU" -eq 1 ] && [ -x "$D/nat" ]; then
    if _build ttr "" "$D/a64x" programs/ts_test_runner.cyr; then
        mkdir -p "$D/h/.cyrius/bin" "$D/tsok" "$D/tsbad"
        printf '#!/bin/sh\nexec qemu-aarch64 "%s" "$@"\n' "$D/nat" > "$D/h/.cyrius/bin/cycc"
        chmod +x "$D/h/.cyrius/bin/cycc"
        printf 'let x: number = 1;\n' > "$D/tsok/a.ts"
        printf 'let x: number = ;\n' > "$D/tsbad/a.ts"
        rc=0; ( cd "$D" && HOME="$D/h" timeout 300 qemu-aarch64 "$D/ttr" tsok < /dev/null > "$D/ttr1.out" 2>&1 ) || rc=$?
        if [ "$rc" -eq 0 ] && grep -qx '1/1 passed' "$D/ttr1.out"; then ok
        else bad "axis 4: ts_test_runner on a clean .ts rc $rc: '$(tail -1 "$D/ttr1.out")' (want rc 0, '1/1 passed'; 6.7.14: '0/1 passed (1 failed)')"; fi
        rc=0; ( cd "$D" && HOME="$D/h" timeout 300 qemu-aarch64 "$D/ttr" tsbad < /dev/null > "$D/ttr2.out" 2>&1 ) || rc=$?
        if [ "$rc" -eq 1 ] && grep -qx '0/1 passed (1 failed)' "$D/ttr2.out"; then ok
        else bad "axis 4: ts_test_runner on a bad .ts rc $rc: '$(tail -1 "$D/ttr2.out")' (want rc 1, '0/1 passed (1 failed)')"; fi
    fi
else
    echo "  SKIP: axis 4 (qemu-aarch64 absent)"; skips=$((skips + 1))
fi

if [ "$fail" -ne 0 ]; then echo "FAIL ts_flags_every_driver ($fail failed, $pass passed)"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: ts_flags_every_driver — $skips leg(s) could not run; every one that ran passed ($pass) (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS ts_flags_every_driver: $pass rows — the filed repro, $nrows-row TS table on 5 drivers (qemu / wine, not hardware), both Mach-O builds, ts_test_runner 1/1 on aarch64"
exit 0
