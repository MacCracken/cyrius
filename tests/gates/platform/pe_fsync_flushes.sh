#!/bin/sh
# 6.6.7 — fsync/fdatasync must FLUSH on Windows, and the atomic writer's rename must be durable.
#
# THE BUG. Windows has no fsync syscall, and the PE backend had no reroute for the Linux
# numbers 74 (fsync) / 75 (fdatasync): a literal `syscall(74, fd)` degraded to -38. lib/io.cyr's
# `xfsync` covered the gap by returning 0 on CYRIUS_TARGET_WIN — for ANY argument, including a
# handle that did not exist — on the stated grounds that "MoveFileEx-after-close is durable
# enough". It was not: EMOVEFILEEX_PE passed dwFlags = 1 (MOVEFILE_REPLACE_EXISTING) without
# MOVEFILE_WRITE_THROUGH (8), and closing a handle does not flush NTFS data, so
# file_write_atomic was atomic but not durable on Windows. The vendored patra fold calls raw
# `syscall(SYS_FDATASYNC = 75, fd)`, so its WAL failed every page with PATRA_ERR_IO there.
#
# THE FIX. 74/75 at argc 2 → EFLUSHFB_PE → kernel32!FlushFileBuffers (BOOL → 0/-1 through
# `cmp eax,1; sbb rax,rax`); xfsync's PE arm is `syscall(74, fd)`; MoveFileExW gets r8d = 9.
#
# THE AXES.
#   axis 1  POSIX ORACLE (always). tests/tcyr/crossos/fsync_flushes.tcyr runs natively and must
#           pass every row. This fixes the expected values as POSIX's (fsync of a bad fd fails,
#           of a written fd succeeds), not a table this gate and the emitter made up together.
#   axis 2  EMITTER SHAPE (always, needs objdump). The PE build of that .tcyr must (a) import
#           kernel32!FlushFileBuffers (read from the import directory, not a strings scan),
#           (b) carry at least one `cmp $0x1,%eax; sbb %rax,%rax` flush tail per literal
#           74/75 site in the .tcyr, PLUS one per direct `syscall(74|75, fd)` in xfsync's
#           CYRIUS_TARGET_WIN arm in lib/io.cyr (the .tcyr always calls xfsync, so that site
#           is always compiled in), PLUS one per fsync/fdatasync site in
#           lib/syscalls_windows.cyr (lib/assert.cyr pulls the Windows peer into the PE
#           build, so a peer sys_fsync would otherwise pad the count and hide an xfsync
#           revert). xfsync's arm must also call SOME flush (a direct syscall, or the peer's
#           sys_fsync/sys_fdatasync) — an arm with none fails axis 2 by name, with no wine,
#           which is what CI has. And (c) load `mov $0x9,%r8d` after EVERY MoveFileExW
#           argument setup (`lea 0x230(%rsp),%rdx`), at least once. (c) is the ONLY guard on
#           the write-through bit anywhere: no run on wine or on real Windows can observe
#           durability, so the flag's presence in the bytes is what there is to check.
#   axis 3  BEHAVIOUR under wine (SKIPs without it; wine is NOT hardware — the cass leg of the
#           release gate runs the same .tcyr). Same row count as the POSIX oracle.
#
# ANTI-VACUOUS. The expected pass count is derived from the .tcyr source (assert_eq sites,
# comments stripped; every row runs exactly once on every target) and must be ≥ FLOOR, so
# deleting rows fails this gate instead of shrinking it.
#
# ROW FLOOR: 18 assertions (16 measured 2026-09-27 at 6.6.7; +2 at 6.6.9 for the var-held
# 74/75 rows — the runtime switch on PE did not route them).
#
# MUTATION LEDGER — built and run 2026-09-27 at 6.6.7, x86_64 Linux + wine 11.17. Each mutant
# is a one-edit scratch tree rebuilt with build/cycc, with a copy of this gate in it.
#   mutant                                                   axis 1  axis 2   axis 3 (wine)
#   the pre-bite compiler + stdlib (a full revert)           PASS    FAIL     FAIL (6 rows red)
#   drop the _PE_ROUTE_FLUSH call site (74/75 → -38 again)   PASS    FAIL     FAIL (6 rows red)
#   xfsync's PE arm back to `return 0;`                      PASS    FAIL     FAIL (2 rows red:
#                                                                              xfsync(12345),
#                                                                              O_RDONLY)
#   MoveFileExW r8d back to 1 (no WRITE_THROUGH)             PASS    FAIL     PASS <-- the
#                                                                              reason axis 2(c)
#                                                                              exists
#   BOOL tail back to dec+sar                                PASS    FAIL     PASS
#   the Windows peer gains sys_fsync/sys_fdatasync (control) PASS    PASS     PASS (9 tails)
#   peer as above + xfsync delegates to sys_fsync (control)  PASS    PASS     PASS (8 tails)
#   peer as above + xfsync's PE arm `return 0;`              PASS    FAIL     FAIL
# The xfsync rows and the controls were also run with wine hidden from PATH (what CI has): the
# two xfsync mutants are still red on axis 2 alone. The controls are the fold lane's expected
# peer change — they must stay green.
#
# Nothing is written inside the tree: the .tcyr creates CWD-relative files, so both runs happen
# inside a mktemp -d that is removed on exit.

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
SRC="$ROOT/tests/tcyr/crossos/fsync_flushes.tcyr"
FLOOR=18

[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f "$SRC" ] || { echo "  FAIL: $SRC is missing — the cross-OS companion for this gate is gone"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0

want=$(grep -v '^[[:space:]]*#' "$SRC" | grep -cE 'assert_eq\(')
nsites=$(grep -v '^[[:space:]]*#' "$SRC" | grep -oE 'syscall\(7[45],' | wc -l | tr -d ' ')
if [ "$want" -lt "$FLOOR" ]; then
    echo "  FAIL floor: the .tcyr carries only $want assertions, floor is $FLOOR — rows were deleted"
    fail=1
else
    echo "  ok floor: $want assertions in the .tcyr (floor $FLOOR), $nsites literal 74/75 sites"
fi

ran_count() {   # $1 = output file -> the "N passed" number when 0 failed, else -1
    sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' "$1" | while read -r p f; do
        if [ "$f" = "0" ]; then echo "$p"; else echo "-1"; fi
    done
}

# --- axis 1: the POSIX oracle ---
cd "$ROOT" || exit 1
"$CC" < "$SRC" > "$D/ff_elf" 2> "$D/elf.err" || true
if [ ! -s "$D/ff_elf" ]; then
    echo "  FAIL axis 1: the ELF build of the .tcyr produced no binary"
    grep -m3 "^error" "$D/elf.err" | sed 's/^/      /'
    fail=1
else
    chmod +x "$D/ff_elf"
    ( cd "$D" && ulimit -c 0; ./ff_elf > "$D/elf.out" 2>&1 ); rc=$?
    got=$(ran_count "$D/elf.out")
    if [ "$rc" != "0" ] || [ "$got" != "$want" ]; then
        echo "  FAIL axis 1 (POSIX oracle): native run exited $rc, reported '$got' of $want rows"
        grep -hm5 "FAIL:" "$D/elf.out" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 1: $got of $want rows hold against the Linux kernel"
    fi
fi

# --- axis 2: the emitter shape ---
CYRIUS_TARGET_WIN=1 "$CC" < "$SRC" > "$D/ff.exe" 2> "$D/pe.err" || true
if [ ! -s "$D/ff.exe" ]; then
    echo "  FAIL axis 2: the PE build of the .tcyr produced no binary"
    grep -m3 "^error" "$D/pe.err" | sed 's/^/      /'
    fail=1
elif ! command -v objdump > /dev/null 2>&1; then
    echo "  SKIP axis 2: objdump not available — the write-through bit then has NO local guard"
else
    objdump -x "$D/ff.exe" 2>/dev/null | sed -n '/DLL Name/,$p' > "$D/imp"
    objdump -dw "$D/ff.exe" > "$D/dis" 2>/dev/null
    # xfsync's PE arm (lib/io.cyr, `fn xfsync` ... its `#ifdef CYRIUS_TARGET_WIN` block): it must
    # flush — either a direct `syscall(74|75, fd)` (counted into the tail floor below) or a call to
    # the Windows peer's sys_fsync/sys_fdatasync (whose own site is counted in npeer).
    xf_arm() {
        awk '/^fn xfsync\(/ {f=1} f && /^}/ {f=0} f && /#ifdef CYRIUS_TARGET_WIN/ {w=1; next}
             f && w && /#endif/ {w=0} f && w && !/^[[:space:]]*#/ {print}' "$ROOT/lib/io.cyr"
    }
    nxf=$(xf_arm | grep -oE 'syscall\(7[45],' | wc -l | tr -d ' ')
    xfany=$(xf_arm | grep -cE 'syscall\((7[45]|SYS_F(DATA)?SYNC),|sys_f(data)?sync\(')
    npeer=$(grep -v '^[[:space:]]*#' "$ROOT/lib/syscalls_windows.cyr" | grep -oE 'syscall\((7[45]|SYS_F(DATA)?SYNC),' | wc -l | tr -d ' ')
    need=$((nsites + nxf + npeer))
    ncf=$(grep -c 'CreateFileW' "$D/imp")
    nfb=$(grep -c 'FlushFileBuffers' "$D/imp")
    ntail=$(awk '/cmp[[:space:]]+\$0x1,%eax/ {p=1; next} p && /sbb[[:space:]]+%rax,%rax/ {n++} {p=0} END {print n+0}' "$D/dis")
    nmv=$(grep -cE 'lea[[:space:]]+0x230\(%rsp\),%rdx' "$D/dis")
    nwt=$(awk '/lea[[:space:]]+0x230\(%rsp\),%rdx/ {p=1; next} p && /mov[[:space:]]+\$0x9,%r8d/ {n++} {p=0} END {print n+0}' "$D/dis")
    if [ "$xfany" -lt 1 ]; then
        echo "  FAIL axis 2 (xfsync): lib/io.cyr's xfsync has no fsync/fdatasync call in its CYRIUS_TARGET_WIN arm — it does not flush on Windows"
        fail=1
    elif [ "$ncf" -lt 1 ]; then
        echo "  FAIL axis 2 (anti-vacuous): the import directory could not be read (CreateFileW is missing too)"
        fail=1
    elif [ "$nfb" -lt 1 ]; then
        echo "  FAIL axis 2: the PE build does not import FlushFileBuffers — fsync/fdatasync are not routed"
        fail=1
    elif [ "$ntail" -lt "$need" ]; then
        echo "  FAIL axis 2: $ntail flush tail(s) (cmp \$1,eax; sbb rax,rax) for $need site(s) ($nsites literal 74/75 in the .tcyr + $nxf in xfsync + $npeer in the Windows peer)"
        fail=1
    elif [ "$nmv" -lt 1 ]; then
        echo "  FAIL axis 2 (anti-vacuous): no MoveFileExW argument setup in the PE build — file_rename is gone"
        fail=1
    elif [ "$nwt" != "$nmv" ]; then
        echo "  FAIL axis 2: $nmv MoveFileExW call(s) but $nwt pass dwFlags = 9 — MOVEFILE_WRITE_THROUGH is missing (the rename is not durable, and nothing else can see that)"
        fail=1
    else
        echo "  ok axis 2: FlushFileBuffers imported, $ntail flush tail(s) for $need site(s), $nwt of $nmv MoveFileExW call(s) write-through"
    fi
fi

# --- axis 3: behaviour, under wine. NOT hardware — the cass leg of the release gate is. ---
if [ ! -s "$D/ff.exe" ]; then
    :
elif ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP axis 3: wine absent — the PE behaviour of these rows is covered only by the cass leg"
else
    mkdir -p "$D/w" && cp "$D/ff.exe" "$D/w/ff.exe"
    ( cd "$D/w" && ulimit -c 0; WINEPREFIX="$D/wp" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
        wine ff.exe > "$D/pe.out" 2> "$D/pe.err" ); rc=$?
    got=$(ran_count "$D/pe.out")
    if [ "$rc" != "0" ] || [ "$got" != "$want" ]; then
        echo "  FAIL axis 3 (wine): PE run exited $rc, reported '$got' of $want rows"
        grep -hm6 "FAIL:" "$D/pe.err" "$D/pe.out" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 3: $got of $want rows hold on PE under wine (hardware: the cass cross-OS leg)"
    fi
    rm -rf "$D/wp"
fi

if [ "$fail" = "0" ]; then
    echo "PASS: fsync/fdatasync flush on PE and file_rename is write-through ($want rows)"
    exit 0
fi
echo "FAIL: PE fsync / durable rename"
exit 1
