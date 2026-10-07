#!/bin/sh
# 6.6.9 — O_NOFOLLOW, O_DIRECTORY and O_CREAT|O_EXCL mean on Windows what they mean on Linux.
#
# THE BUG. EOPEN_PE (src/backend/x86/emit.cyr) passed CreateFileW a FIXED dwFlagsAndAttributes
# of 0x80, and `_pe_open_flags` never read O_NOFOLLOW (0x20000) or O_DIRECTORY (0x10000).
# CreateFileW resolves a final reparse point for EVERY disposition, so on real cass:
#   · `file_open(link, O_WRONLY|O_TRUNC|O_NOFOLLOW)` returned a handle and truncated the
#     link's TARGET (patra's filing, row N2);
#   · `O_CREAT|O_EXCL` over a DANGLING link created the link's target, with or without
#     O_NOFOLLOW — file_create_exclusive, sigil's keyfile, the cbt temp creates;
#   · `O_DIRECTORY` could not open a directory (-1) and DID open a file;
#   · `is_symlink` was 0 for everything, so dir_walk descended junctions and the CLI's
#     symlinked-lib refusal was blind on Windows.
#
# THE FIX. `_pe_open_attr_flags` derives the attribute word (O_NOFOLLOW and CREATE_NEW →
# FILE_FLAG_OPEN_REPARSE_POINT, O_DIRECTORY → FILE_FLAG_BACKUP_SEMANTICS, never unconditional),
# and the Windows peer's `sys_open` asks the OPENED handle (GetFileInformationByHandleEx,
# reroute 0xF03D) whether it is a name-surrogate reparse point (-ELOOP) or a non-directory
# under O_DIRECTORY (-ENOTDIR), truncating an O_NOFOLLOW|O_TRUNC open only after that check
# (SetEndOfFile, 0xF03F). `is_symlink` reads the reparse tag.
#
# THE AXES.
#   axis 1  POSIX ORACLE (always). tests/tcyr/crossos/open_flags_per_target.tcyr runs natively;
#           every row must hold against the Linux kernel, so the expected values are POSIX's.
#   axis 2  EMITTER SHAPE (always, needs objdump). The PE build must not store the fixed 0x80
#           (`movq $0x80,0x28(%rsp)`), and per EOPEN_PE site (counted by its `mov %r8,0x28(%rsp)`)
#           it must start from `mov $0x80,%r8d` (nothing unconditional) and carry TWO
#           `or $0x200000,%r8d` (O_NOFOLLOW + CREATE_NEW) and ONE `or $0x2000000,%r8d` (O_DIRECTORY). It must also IMPORT GetFileInformationByHandleEx
#           (the peer's handle check) — read from the import directory, not a strings scan.
#   axis 3  BEHAVIOUR under wine (SKIPs without it — wine is NOT hardware; the cass cross-OS leg
#           of the release gate runs the same .tcyr). The symlink rows are NOT wine-blind: the
#           fixtures are made by CreateSymbolicLinkW (xsymlink's PE arm), whose links wine sees.
#           It is Unix-made links that wine presents as plain files.
#
# ANTI-VACUOUS. The expected pass count of EACH build is derived statically from the .tcyr
# (assert_* call sites, comments stripped, split by the CYRIUS_TARGET_WIN guards; every row
# runs exactly once) and must be at least the FLOOR, so deleting rows fails the gate.
# ROW FLOOR: 44 native rows (40 measured 2026-09-28 at 6.6.9; +4 after the bite-5 review — the
# directory-link -ELOOP rows, the directory -EISDIR row and the is_symlink allocation row).
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-09-28 at 6.6.9 (x86_64 Linux + wine 11.17).
# Each is one edit in a scratch copy of lib/src/tests, rebuilt with build/cycc, with this gate
# copied in so $ROOT resolves to the mutant. Axis 1 passes every one (it tests Linux, by design).
#   mutant                                                   axis 2  axis 3 (wine)
#   drop the O_NOFOLLOW `or` in _pe_open_attr_flags          FAIL    FAIL, 8 rows (targets truncated)
#   drop the CREATE_NEW `or` in _pe_open_attr_flags          FAIL    FAIL, 4 rows (the target IS created)
#   drop the O_DIRECTORY `or`                                FAIL    FAIL, 4 rows
#   BACKUP_SEMANTICS in the base word (set unconditionally)  FAIL    FAIL, 1 row (the plain-dir row)
#   sys_open without the handle check (raw syscall only)     PASS    FAIL, 8 rows
#   O_TRUNC not deferred past the check (tr = 0)             PASS    FAIL, 1 row (the append row)
#   is_symlink's PE arm back to `return 0`                   PASS    FAIL, 3 rows
# Added after the bite-5 review (same day, same method; cass rows measured on real hardware):
#   no directory-object probe (the first cut: a failed        PASS    FAIL, 5 rows (dir link and
#     O_NOFOLLOW open handed back CreateFileW's bare -1)               junction -40, dir -21;
#                                                                      cass: the same 5)
#   `_win_same_file` always 0 (a truncation via the second    PASS    FAIL, 2 rows (O_RDONLY;
#     handle is never trusted)                                         cass: 4, O_APPEND too —
#                                                                      wine does not enforce
#                                                                      FILE_WRITE_DATA there)
#   is_symlink's PE arm back to the bump-allocated buffers     PASS    FAIL, 1 row (40448 B over
#                                                                      64 calls)
# The lib-only mutants pass axis 2 by construction (it reads the emitter), so on a box without
# wine this gate catches an emitter revert and NOT a peer revert — the cass leg is the
# hardware check for both. ⚠ The first draft of this ledger PREDICTED wine would miss the
# CREATE_NEW mutant; measured, wine creates the target just as cass did. Predictions are not
# ledger rows.
#
# 6.6.11 — THE PATH IS OPENED UNDER ITS OWN NAME (items I1/I2). EOPEN_PE and the other six
# narrow-path reroutes (ECREATEDIR_PE, EDELETEF_PE x2 — 0xF035 shares it since 6.6.20 —, EREMOVEDIRW_PE, and
# EMOVEFILEEX_PE's two paths) widened UTF-8 one BYTE per UTF-16 unit and stopped at 260 units with
# a forced NUL: `café.txt` failed to open, and a 288-byte relative O_CREAT open returned a VALID
# handle for the name cut to 260 units (wine, measured at 6.6.10) — a silent write to the wrong
# file. They now share ONE sequence (`_pe_widen_path`): MultiByteToWideChar(CP_UTF8,
# MB_ERR_INVALID_CHARS) — refuse, never guess — then GetFullPathNameW + a `\\?\` prefix at 248+
# units, in a probed frame. The stdlib's own widens (`_win_widen_n`) decode the same way and are
# bounded by the Str's length. Two more axes:
#   axis 2b PATH-ENCODING SHAPE (always, needs objdump), on the PE build of
#           tests/tcyr/crossos/pe_path_utf8_long.tcyr, which reaches all seven emitters. Every
#           call through the IAT slot of CreateFileW / CreateDirectoryW / DeleteFileW /
#           RemoveDirectoryW (and TWICE per MoveFileExW call) — and, since 6.6.12, of
#           GetFileAttributesW / FindFirstFileW (0xF019 / 0xF016 take a NARROW path now; they took
#           a stdlib-widened, unprefixed one and so still hit MAX_PATH) — must be fed by one
#           widen, and every
#           widen must carry the three things that ARE the fix: CP_UTF8 (`mov $0xfde9,%ecx`)
#           followed by MB_ERR_INVALID_CHARS (`mov $0x8,%edx`), and the long-path branch
#           (`cmp $0xf8,%eax`); each path frame carries its page probe (`test %rsp,(%rsp)`), and
#           the truncating loop (`mov %ax,(%rdi,%rcx,2)`, `cmp $0x104,%ecx`) is GONE.
#   axis 4  BEHAVIOUR of that .tcyr — natively (POSIX is the oracle: Linux takes a 300-byte path
#           and a UTF-8 name as they are) and under wine with a UTF-8 locale (wine maps a WCHAR
#           name to a Unix name through the locale; under LANG=C it cannot store `é` at all,
#           which is wine's limit, not the emitter's). Floor 33 native rows.
#
# MUTATION LEDGER, 6.6.11 — every mutant BUILT AND RUN 2026-09-29 (x86_64 Linux + wine 11.17,
# the gate run with CYCC=<mutant cycc>; the cass column is pe_path_utf8_long.exe on real Windows):
#   mutant                                              axis 2b  axis 4 (wine)       cass
#   MB_ERR_INVALID_CHARS dropped (edx = 0)              FAIL     FAIL, 4 rows        -
#   the long-path branch dropped (threshold 32768)      FAIL     PASS                FAIL, 7 rows
#   the page probe dropped (one bare sub rsp,size)      FAIL     PASS                CRASH 0xC0000005
#   the 6.6.10 compiler (the cut-at-260 byte loop)      FAIL     FAIL, 12 rows       FAIL, 17 rows (6.6.10 stdlib too)
#   the 6.6.10 stdlib widens, new emitter               PASS     FAIL, 2 rows        -
# 6.6.12 (lane P, bite B08), BUILT AND RUN 2026-09-30, same method (axis 3 also reddens: its
# is_symlink rows go through the same two reroutes):
#   EGETFATTR_PE back to the wide-input 1-arg call      FAIL     FAIL, 4 rows        -
#   EFINDFIRST_PE back to the wide-input 2-arg call     FAIL     FAIL, 10 rows       -
#   the 6.6.11 compiler + stdlib (pe_path_utf8_long.exe) -       -                   FAIL, 6 rows
# wine enforces no MAX_PATH and commits the whole stack, so the long-path branch and the probe are
# invisible to it: for those two, axis 2b is the only LOCAL guard and cass the hardware one.
#
# Nothing is written inside the tree: the .tcyr's native build names /tmp/<name>.<pid> and the
# PE build names cwd-relative files; both runs happen inside a mktemp -d removed on exit.

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
SRC="$ROOT/tests/tcyr/crossos/open_flags_per_target.tcyr"
FLOOR=44
PSRC="$ROOT/tests/tcyr/crossos/pe_path_utf8_long.tcyr"
PFLOOR=33

# 77 = SKIP: this gate could not run at all (never 0, which would read as a pass).
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
[ -f "$SRC" ] || { echo "  FAIL: $SRC is missing — the cross-OS companion for this fix is gone"; exit 1; }
[ -f "$PSRC" ] || { echo "  FAIL: $PSRC is missing — the cross-OS companion for the path-encoding fix is gone"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache (a fresh prefix writes $HOME/.cache: mesa shader caches). The EXIT
# teardown stops THIS prefix's wineserver and removes its server dir
# (/tmp/.wine-<uid>/server-<dev>-<ino>), which `wineserver -k` leaves behind. CHANGELOG [6.6.17]
WP="$D/wp"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
fail=0

# Static expectation: assert_* sites outside any CYRIUS_TARGET_WIN guard count for both builds;
# those under `#ifdef CYRIUS_TARGET_WIN` count for PE only, `#ifndef` for native only.
static_counts() {   # $1 = .tcyr -> "<native rows> <PE rows>"
grep -vE '^[[:space:]]*#([^a-z]|$)' "$1" | awk '
    /^[[:space:]]*#ifdef CYRIUS_TARGET_WIN/  { st[++n] = "w"; next }
    /^[[:space:]]*#ifndef CYRIUS_TARGET_WIN/ { st[++n] = "n"; next }
    /^[[:space:]]*#ifn?def /                 { st[++n] = "o"; next }
    /^[[:space:]]*#endif/                    { if (n > 0) n--; next }
    /assert_(eq|neq|lt|gt|lte|gte)\(/ {
        k = "c"; for (i = 1; i <= n; i++) if (st[i] != "o") k = st[i]
        c[k]++
    }
    END { printf "%d %d\n", c["c"] + c["n"], c["c"] + c["w"] }'
}
counts=$(static_counts "$SRC")
want_elf=${counts% *}
want_pe=${counts#* }
if [ "$want_elf" -lt "$FLOOR" ]; then
    echo "  FAIL floor: the .tcyr carries only $want_elf native assertions, floor is $FLOOR — rows were deleted"
    fail=1
else
    echo "  ok floor: $want_elf native / $want_pe PE assertions in the .tcyr (floor $FLOOR)"
fi

ran_count() {   # $1 = output file -> the "N passed" number, or -1
    sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' "$1" | while read -r p f; do
        if [ "$f" = "0" ]; then echo "$p"; else echo "-1"; fi
    done
}

# --- axis 1: the POSIX oracle ---
cd "$ROOT" || exit 1
"$CC" < "$SRC" > "$D/elf" 2> "$D/elf.err" || true
if [ ! -s "$D/elf" ]; then
    echo "  FAIL axis 1: the ELF build of the .tcyr produced no binary"
    grep -m3 "^error" "$D/elf.err" | sed 's/^/      /'
    fail=1
else
    chmod +x "$D/elf"
    mkdir -p "$D/n"
    rc=0; ( cd "$D/n" && ulimit -c 0; ../elf > "$D/elf.out" 2>&1 ) || rc=$?
    got=$(ran_count "$D/elf.out")
    if [ "$rc" != "0" ] || [ "$got" != "$want_elf" ]; then
        echo "  FAIL axis 1 (POSIX oracle): native run exited $rc, reported '$got' of $want_elf rows"
        grep -hm5 "FAIL:" "$D/elf.out" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 1: $got of $want_elf rows hold against the Linux kernel"
    fi
fi

# --- axis 2: the emitter shape ---
CYRIUS_TARGET_WIN=1 "$CC" < "$SRC" > "$D/t.exe" 2> "$D/pe.err" || true
if [ ! -s "$D/t.exe" ]; then
    echo "  FAIL axis 2: the PE build of the .tcyr produced no binary"
    grep -m3 "^error" "$D/pe.err" | sed 's/^/      /'
    fail=1
elif ! command -v objdump > /dev/null 2>&1; then
    echo "  SKIP axis 2: objdump not available"
else
    objdump -d "$D/t.exe" > "$D/dis" 2>/dev/null
    fixed=$(grep -cE 'movq?[[:space:]]+\$0x80,0x28\(%rsp\)' "$D/dis" || true)
    sites=$(grep -cE 'mov[[:space:]]+%r8,0x28\(%rsp\)' "$D/dis" || true)
    base=$(grep -cE 'mov[[:space:]]+\$0x80,%r8d' "$D/dis" || true)
    rp=$(grep -cE 'or[[:space:]]+\$0x200000,%r8d' "$D/dis" || true)
    bs=$(grep -cE 'or[[:space:]]+\$0x2000000,%r8d' "$D/dis" || true)
    imp=$(objdump -p "$D/t.exe" 2>/dev/null | grep -cE '[[:space:]]GetFileInformationByHandleEx$' || true)
    if [ "$fixed" != "0" ]; then
        echo "  FAIL axis 2: $fixed open site(s) still pass the FIXED dwFlagsAndAttributes 0x80 — O_NOFOLLOW/O_DIRECTORY are ignored again"
        fail=1
    elif [ "$sites" -lt 1 ]; then
        echo "  FAIL axis 2 (anti-vacuous): the PE build has no open reroute storing a derived attribute word"
        fail=1
    elif [ "$base" != "$sites" ]; then
        echo "  FAIL axis 2: $sites open site(s) but $base start from FILE_ATTRIBUTE_NORMAL alone (mov \$0x80,%r8d) — a flag is being set unconditionally"
        fail=1
    elif [ "$rp" != "$((sites * 2))" ]; then
        echo "  FAIL axis 2: $sites open site(s) but $rp FILE_FLAG_OPEN_REPARSE_POINT arm(s), want $((sites * 2)) (O_NOFOLLOW + CREATE_NEW each)"
        fail=1
    elif [ "$bs" != "$sites" ]; then
        echo "  FAIL axis 2: $sites open site(s) but $bs FILE_FLAG_BACKUP_SEMANTICS arm(s) — the O_DIRECTORY map is missing, or set outside it"
        fail=1
    elif [ "$imp" -lt 1 ]; then
        echo "  FAIL axis 2: GetFileInformationByHandleEx is not imported — sys_open's handle check is gone"
        fail=1
    else
        echo "  ok axis 2: $sites open site(s), each deriving the attribute word (2 reparse arms + 1 backup arm), handle check imported"
    fi
fi

# --- axis 3: behaviour under wine. NOT hardware — the cass cross-OS leg is. ---
if [ ! -s "$D/t.exe" ]; then
    :
elif ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP axis 3: wine absent — the PE behaviour of these rows is covered only by the cass leg"
else
    mkdir -p "$D/w" && cp "$D/t.exe" "$D/w/t.exe"
    rc=0; ( cd "$D/w" && ulimit -c 0; WINEPREFIX="$D/wp" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
        wine t.exe > "$D/pe.out" 2> "$D/pe.err2" ) || rc=$?
    got=$(ran_count "$D/pe.out")
    if [ "$rc" != "0" ] || [ "$got" != "$want_pe" ]; then
        echo "  FAIL axis 3 (wine): PE run exited $rc, reported '$got' of $want_pe rows"
        grep -hm8 "FAIL:" "$D/pe.out" "$D/pe.err2" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 3: $got of $want_pe rows hold on PE under wine (hardware: the cass cross-OS leg)"
    fi
    # The junction rows spawn `cmd /c mklink /J`, which leaves this prefix's wineserver (and
    # its services) running past `wine`'s exit. Ended inline, scoped to OUR prefix — never a
    # bare `wineserver -k` (see cbt_fork_sites_have_pe_arm.sh: that kills other lanes' wine).
    WINEPREFIX="$D/wp" wineserver -k > /dev/null 2>&1 || true
    _wine_down; rm -rf "$D/wp"
fi

# --- axis 2b: the path-encoding shape (6.6.11) ---
CYRIUS_TARGET_WIN=1 "$CC" < "$PSRC" > "$D/p.exe" 2> "$D/p.err" || true
if [ ! -s "$D/p.exe" ]; then
    echo "  FAIL axis 2b: the PE build of pe_path_utf8_long.tcyr produced no binary"
    grep -m3 "^error" "$D/p.err" | sed 's/^/      /'
    fail=1
elif ! command -v objdump > /dev/null 2>&1; then
    echo "  SKIP axis 2b: objdump not available"
else
    objdump -d "$D/p.exe" > "$D/pdis" 2>/dev/null
    objdump -p "$D/p.exe" > "$D/pimp" 2>/dev/null
    calls_to() {   # $1 = kernel32 import name -> call sites through its IAT slot
        slot=$(awk -v n="$1" '$NF == n {print $1; exit}' "$D/pimp" || true)
        [ -n "$slot" ] || { echo 0; return; }
        va=$(printf '0x%x' $((0x140000000 + 0x$slot)))
        grep -cE "call[[:space:]]+\*0x[0-9a-f]+\(%rip\)[[:space:]]+# $va\$" "$D/pdis"
    }
    ncf=$(calls_to CreateFileW); ncd=$(calls_to CreateDirectoryW); ndf=$(calls_to DeleteFileW)
    nrd=$(calls_to RemoveDirectoryW); nmv=$(calls_to MoveFileExW)
    nga=$(calls_to GetFileAttributesW); nff=$(calls_to FindFirstFileW)   # narrow since 6.6.12
    want_w=$((ncf + ncd + ndf + nrd + nga + nff + 2 * nmv))
    frames=$((ncf + ncd + ndf + nrd + nga + nff + nmv))
    nw=$(grep -cE 'mov[[:space:]]+\$0xfde9,%ecx' "$D/pdis" || true)
    n8=$(awk '/mov[[:space:]]+\$0xfde9,%ecx/ {p=1; next} p && /mov[[:space:]]+\$0x8,%edx/ {n++} {p=0} END {print n+0}' "$D/pdis" || true)
    nlong=$(grep -cE 'cmp[[:space:]]+\$0xf8,%eax' "$D/pdis" || true)
    nprobe=$(grep -cE 'test[[:space:]]+%rsp,\(%rsp\)' "$D/pdis" || true)
    nloop=$(grep -cE 'mov[[:space:]]+%ax,\(%rdi,%rcx,2\)|cmp[[:space:]]+\$0x104,%ecx' "$D/pdis" || true)
    nimp=$(grep -cE '[[:space:]](MultiByteToWideChar|GetFullPathNameW)$' "$D/pimp" || true)
    if [ "$ncf" -lt 1 ] || [ "$ncd" -lt 1 ] || [ "$ndf" -lt 1 ] || [ "$nrd" -lt 1 ] || [ "$nmv" -lt 1 ] || [ "$nga" -lt 1 ] || [ "$nff" -lt 1 ]; then
        echo "  FAIL axis 2b (anti-vacuous): the PE build does not reach every narrow-path reroute (CreateFileW $ncf, CreateDirectoryW $ncd, DeleteFileW $ndf, RemoveDirectoryW $nrd, MoveFileExW $nmv, GetFileAttributesW $nga, FindFirstFileW $nff call site(s))"
        fail=1
    elif [ "$nimp" != "2" ]; then
        echo "  FAIL axis 2b: MultiByteToWideChar / GetFullPathNameW are not both imported ($nimp of 2)"
        fail=1
    elif [ "$nloop" != "0" ]; then
        echo "  FAIL axis 2b: $nloop instruction(s) of the byte-per-unit, cut-at-260 widen loop are back"
        fail=1
    elif [ "$nw" != "$want_w" ]; then
        echo "  FAIL axis 2b: $want_w narrow path(s) handed to kernel32 but $nw CP_UTF8 widen(s) — a reroute bypasses the shared sequence"
        fail=1
    elif [ "$n8" != "$nw" ]; then
        echo "  FAIL axis 2b: $nw widen(s) but $n8 pass MB_ERR_INVALID_CHARS — invalid UTF-8 would be GUESSED at, not refused"
        fail=1
    elif [ "$nlong" != "$nw" ]; then
        echo "  FAIL axis 2b: $nw widen(s) but $nlong long-path (248-unit) branch(es) — a long path would hit MAX_PATH again"
        fail=1
    elif [ "$nprobe" != "$frames" ]; then
        echo "  FAIL axis 2b: $frames path frame(s) but $nprobe page probe(s) — a ~128 KB frame skipping the stack guard page faults on real Windows"
        fail=1
    else
        echo "  ok axis 2b: $want_w narrow path(s) over $frames frame(s), each through CP_UTF8 + MB_ERR_INVALID_CHARS + the long-path branch, every frame probed, no cut-at-260 loop"
    fi
fi

# --- axis 4: the path-encoding rows — POSIX oracle natively, then PE under wine ---
pcounts=$(static_counts "$PSRC")
pwant_elf=${pcounts% *}
pwant_pe=${pcounts#* }
if [ "$pwant_elf" -lt "$PFLOOR" ]; then
    echo "  FAIL axis 4 floor: pe_path_utf8_long.tcyr carries only $pwant_elf native assertions, floor is $PFLOOR"
    fail=1
fi
"$CC" < "$PSRC" > "$D/pelf" 2> "$D/pelf.err" || true
if [ ! -s "$D/pelf" ]; then
    echo "  FAIL axis 4: the ELF build of pe_path_utf8_long.tcyr produced no binary"
    fail=1
else
    chmod +x "$D/pelf"
    mkdir -p "$D/pn"
    rc=0; ( cd "$D/pn" && ulimit -c 0; ../pelf > "$D/pelf.out" 2>&1 ) || rc=$?
    got=$(ran_count "$D/pelf.out")
    if [ "$rc" != "0" ] || [ "$got" != "$pwant_elf" ]; then
        echo "  FAIL axis 4 (POSIX oracle): native run exited $rc, reported '$got' of $pwant_elf rows"
        grep -hm5 "FAIL:" "$D/pelf.out" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 4: $got of $pwant_elf path rows hold against the Linux kernel"
    fi
fi
if [ ! -s "$D/p.exe" ]; then
    :
elif ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP axis 4 (wine): wine absent — the PE rows are covered only by the cass leg"
else
    mkdir -p "$D/pw" && cp "$D/p.exe" "$D/pw/p.exe"
    rc=0; ( cd "$D/pw" && ulimit -c 0; LANG=C.UTF-8 LC_ALL=C.UTF-8 WINEPREFIX="$D/wp" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
        wine p.exe > "$D/p.out" 2> "$D/p.err2" ) || rc=$?
    got=$(ran_count "$D/p.out")
    if [ "$rc" != "0" ] || [ "$got" != "$pwant_pe" ]; then
        echo "  FAIL axis 4 (wine): PE run exited $rc, reported '$got' of $pwant_pe path rows"
        grep -hm8 "FAIL:" "$D/p.out" "$D/p.err2" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 4: $got of $pwant_pe path rows hold on PE under wine (hardware: the cass cross-OS leg)"
    fi
    WINEPREFIX="$D/wp" wineserver -k > /dev/null 2>&1 || true
    _wine_down; rm -rf "$D/wp"
fi

if [ "$fail" = "0" ]; then
    echo "PASS: O_NOFOLLOW / O_DIRECTORY / O_CREAT|O_EXCL have their POSIX meaning on PE ($want_elf native / $want_pe PE rows), and a path is used under its own UTF-8 name at any length ($pwant_elf / $pwant_pe rows)"
    exit 0
fi
echo "FAIL: PE open POSIX semantics"
exit 1
