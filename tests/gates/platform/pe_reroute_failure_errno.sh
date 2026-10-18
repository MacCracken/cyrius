#!/bin/sh
# 6.7.14 — a FAILED ReadFile / WriteFile / SetFilePointerEx / CreateFileW answers a negative errno
# on PE, through ONE GetLastError table (issues/archived/2026-10-15-pe-read-failure-reads-as-eof.md,
# 2026-10-15-pe-open-failure-is-always-minus-one.md, 2026-10-16-pe-lseek-failed-seek-returns-zero.md).
#
# ⛔ WHY: the four kernel32 file reroutes (src/backend/x86/emit.cyr) returned their success answer
# without reading the failure: EREAD_PE / EWRITE_PE the byte count ReadFile / WriteFile zero before
# they fail (a failed read read as END OF FILE, a failed write as 0 bytes written), ELSEEK_PE its
# pre-zeroed output slot (a failed seek read as a seek to 0, and the next write landed at the old
# position), EOPEN_PE CreateFileW's -1 (never -ENOENT, so never IoNotFound). Now each keeps its
# success answer and on failure calls a shared stub that calls GetLastError and maps the Win32
# code; ReadFile's own stub keeps ERROR_BROKEN_PIPE (109) and ERROR_HANDLE_EOF (38) as 0, the end,
# and ERROR_MORE_DATA (234) as the count.
#
# THE AXES
#   axis 1  POSIX ORACLE (always): the four crossos .tcyr — pe_read_write_failure_errno,
#           pe_open_failure_errno, lseek_failed_seek, close_answer (6.7.15) — run natively at 0
#           failed over their floors.
#           Their expected values are Linux's, not a table this gate and the emitter made up.
#   axis 2  EMITTER SHAPE (objdump): a probe with a literal read / write / open / seek / close
#           and a var-held syscall number (EPE_SYSCALL_DYNAMIC's argc-4 switch, which emits all four
#           again, and its argc-2 one, which emits the close) builds for PE. EVERY call through the
#           ReadFile / WriteFile / SetFilePointerEx IAT slot is followed by `test %eax,%eax; mov
#           <answer>; jne +5; call <stub>`, every CreateFileW call by `cmp $-1,%rax; jne +5; call
#           <stub>`, every CloseHandle call by `test %eax,%eax; je; xor %eax,%eax; jmp; call
#           <stub>`; ReadFile's go to the read stub, the other four to the table; at least 2 sites
#           of each (anti-vacuous).
#   axis 3  THE TABLE (objdump, the same build): the table stub aligns (`sub $0x28,%rsp`), calls
#           through GetLastError's IAT slot, and its `mov $errno,%edx` / `cmp $code,%ecx; cmove`
#           rows map EXACTLY the documented Win32 codes (TABLE below), then `neg %rax; ret`; the
#           read stub calls the table and then maps 109 and 38 to 0 and 234 to the count it parked.
#           CI has no wine: this axis is what pins the mapping there.
#   axis 4  BEHAVIOUR under wine (skipped without wine — NOT hardware; the cass cross-OS leg runs
#           the same .tcyr): the four filed repros, verbatim (exit 91; exit 2; `-22 4 -22 4`; the
#           close's exit 91, 6.7.15), and
#           the four .tcyr's PE builds at 0 failed over their floors.
#   axis 5  STATIC, lib/io.cyr: Windows' CREATE_NEW over an existing DIRECTORY answers
#           ERROR_ACCESS_DENIED (-13) on real Windows — wine says ERROR_FILE_EXISTS, so no wine run
#           can see it — and file_create_exclusive's and _io_tmp_taken's CYRIUS_TARGET_WIN arms must
#           classify a -13 by asking the name (`== 0 - 13`), or file_create_exclusive(dir) is -13
#           and an atomic write fails at a planted directory instead of moving on (measured on cass:
#           pe_open_failure_errno and atomic_write_temp_exclusive red).
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-10-16 (6.7.14 platform lane, P1; x86_64 Linux
# + wine 11.19; CYCC=<mutant cycc> for the compiler rows):
#   mutant                                                  result
#   the pre-fix compiler + lib (2600f67f)                   axes 2, 4, 5 FAIL (no GetLastError import,
#                                                           so axis 3 has no stub to read)
#   _pe_w32_read_rows' 109 row dropped                      axis 3 FAIL; axis 4 FAIL (the pipe-drain
#                                                           row: -32, wine answers ERROR_BROKEN_PIPE)
#   the table's 131 (ERROR_NEGATIVE_SEEK) row dropped       axis 3 FAIL; axis 4 FAIL (lseek -1 4 -1 4)
#   EOPEN_PE's `cmp rax,-1` / stub call dropped             axes 2, 4 FAIL
#   main.cyr's EPE_ERRNO_STUBS call dropped                 axes 2, 4 FAIL (every PE build stops:
#                                                           FIXUP's drained assert names the driver)
#   lib/io.cyr's Windows arms back to `== 0 - 1`            axis 5 FAIL (axis 4 PASSES: wine)
# 6.7.15 — CloseHandle joins the class (issues/2026-10-16-pe-close-returns-closehandle-bool.md):
# ECLOSE_PE handed back CloseHandle's BOOL, so a good close answered 1 and a failed one 0 (the
# filed repro exited 110, Linux 91; file_close_r was never Err). It answers 0, or -errno through
# the same table stub. Axis 1 and axis 4 run tests/tcyr/crossos/close_answer.tcyr; axis 2's probe
# has a literal and a var-held close, and every CloseHandle IAT call must be followed by
# `test %eax,%eax; je; xor %eax,%eax; jmp; call <the table stub>`.
#   mutant (2026-10-18, 6.7.15 platform lane, P2)             result
#   the pre-fix compiler (b2e1f4c48: _pe_srw_call_1arg)     axis 2 FAIL (the CloseHandle sites have no
#                                                           failure check); axis 4 FAIL (the close repro
#                                                           exits 110, close_answer 4 passed 9 failed)
#   ECLOSE_PE's `xor eax,eax` dropped (TRUE answers the BOOL 1)  axis 2 FAIL; axis 4 FAIL
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.14] [6.7.15]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: pe_reroute_failure_errno: build/cycc missing"; exit 77; }
IO="$ROOT/lib/io.cyr"
T1="$ROOT/tests/tcyr/crossos/pe_read_write_failure_errno.tcyr"
T2="$ROOT/tests/tcyr/crossos/pe_open_failure_errno.tcyr"
T3="$ROOT/tests/tcyr/crossos/lseek_failed_seek.tcyr"
T4="$ROOT/tests/tcyr/crossos/close_answer.tcyr"
for f in "$IO" "$T1" "$T2" "$T3" "$T4"; do
    [ -f "$f" ] || { echo "FAIL: pe_reroute_failure_errno: $f is missing"; exit 1; }
done
# Row floors, as measured at 6.7.14 (each .tcyr runs every row on every target it counts).
F1=10; F2=10; F3=13; F4=13
# Win32 code:errno, sorted by code — the table src/backend/x86/emit.cyr's _pe_w32_errno_rows_a/_b emit.
TABLE="2:2 3:2 5:13 6:9 8:12 14:12 15:2 32:13 33:13 80:17 87:22 109:32 112:28 123:2 131:22 145:39 161:2 183:17 206:36 232:32 267:20"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_reroute_failure_errno: mktemp -d failed"; exit 1; }
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
# "<passed> <failed>" from a run's summary line, or empty.
summary() { tr -d '\r' < "$1" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' | tail -1; }

# axis 1: the POSIX oracle.
mkdir -p "$D/n"
for pair in "$T1:$F1" "$T2:$F2" "$T3:$F3" "$T4:$F4"; do
    t=${pair%:*}; fl=${pair##*:}; b=$(basename "$t" .tcyr)
    ( cd "$ROOT" && "$CC" < "$t" > "$D/n/$b" 2> "$D/n/$b.err" ) || true
    if [ ! -s "$D/n/$b" ]; then
        bad "axis 1: the native build of $b.tcyr produced no binary: $(grep -m2 '^error' "$D/n/$b.err" | tr '\n' ' ')"
        continue
    fi
    chmod +x "$D/n/$b"
    nrc=0; ( cd "$D/n" && ulimit -c 0; "./$b" > "$b.out" 2>&1 ) || nrc=$?
    sum=$(summary "$D/n/$b.out"); np=${sum% *}; nf=${sum#* }
    if [ -z "$sum" ] || [ "$nrc" != 0 ] || [ "$nf" != 0 ] || [ "$np" -lt "$fl" ]; then
        bad "axis 1: $b.tcyr natively: '${sum:-no summary}' (exit $nrc, floor $fl)"
        tr -d '\r' < "$D/n/$b.out" | grep -m4 'FAIL:' | sed 's/^/      /'
    else ok; fi
done

# axis 2 + 3: the emitter shape and the table.
cat > "$D/shape.cyr" <<'EOF'
var buf[16];
fn by_number(nr, a, b, c): i64 { return syscall(nr, a, b, c); }
fn by_number1(nr, a): i64 { return syscall(nr, a); }
fn main(): i64 {
    var r = syscall(0, 0 - 999, &buf, 16);
    r = r + syscall(1, 0 - 999, &buf, 16);
    r = r + syscall(2, "no_such_shape_x", 0, 0);
    r = r + syscall(8, 0 - 999, 0, 0);
    r = r + syscall(3, 0 - 999);
    r = r + by_number(0, 0 - 999, &buf, 16);
    r = r + by_number1(3, 0 - 999);
    return r;
}
var r = main();
syscall(60, r & 255);
EOF
CYRIUS_TARGET_WIN=1 "$CC" < "$D/shape.cyr" > "$D/shape.exe" 2> "$D/shape.err" || true
if [ ! -s "$D/shape.exe" ]; then
    bad "axis 2: the PE build of the shape probe produced no binary: $(grep -m2 'error' "$D/shape.err" | tr '\n' ' ')"
elif ! objdump -p "$D/shape.exe" > "$D/imp" 2>/dev/null || ! grep -q 'DLL Name' "$D/imp"; then
    echo "  SKIP: axes 2 and 3 (no objdump that reads PE)"
else
    objdump -dw "$D/shape.exe" > "$D/dis" 2>/dev/null
    va() { s=$(awk -v n="$1" '$NF == n {print $1; exit}' "$D/imp"); [ -n "$s" ] && printf '0x%x' $((0x140000000 + 0x$s)); }
    RF=$(va ReadFile); WF=$(va WriteFile); SF=$(va SetFilePointerEx); CF=$(va CreateFileW); GL=$(va GetLastError)
    CH=$(va CloseHandle)
    if [ -z "$RF" ] || [ -z "$WF" ] || [ -z "$SF" ] || [ -z "$CF" ] || [ -z "$CH" ]; then
        bad "axis 2: the probe does not import ReadFile / WriteFile / SetFilePointerEx / CreateFileW / CloseHandle ('$RF' '$WF' '$SF' '$CF' '$CH')"
    elif [ -z "$GL" ]; then
        bad "axis 2: the probe does not import GetLastError — no failure reads it"
    else
        # Per IAT call site: "<api> <ok|BAD:why> <stub target>". Instruction text only (after the 2nd tab).
        awk -F'\t' -v rf="$RF" -v wf="$WF" -v sf="$SF" -v cf="$CF" -v ch="$CH" '
            NF >= 3 { n++; t[n] = $3 }
            END {
                for (i = 1; i <= n; i++) {
                    if (t[i] !~ /^call +\*0x[0-9a-f]+\(%rip\)/) continue
                    k = t[i]; sub(/.*# /, "", k)
                    api = ""
                    if (k == rf) api = "ReadFile"; else if (k == wf) api = "WriteFile"
                    else if (k == sf) api = "SetFilePointerEx"; else if (k == cf) api = "CreateFileW"
                    else if (k == ch) api = "CloseHandle"
                    if (api == "") continue
                    why = "ok"; j = i + 1
                    if (api == "CloseHandle") {
                        # test; je .fail; xor eax,eax (TRUE: 0); jmp .done; .fail: call <stub>
                        if (t[j] !~ /^test +%eax,%eax/) why = "BAD:no-test-eax"
                        j++
                        if (t[j] !~ /^je /) why = "BAD:no-je"
                        j++
                        if (t[j] !~ /^xor +%eax,%eax/) why = "BAD:no-xor-eax"
                        j++
                        if (t[j] !~ /^jmp /) why = "BAD:no-jmp"
                        j++
                        s = t[j]
                        if (s !~ /^call +0x[0-9a-f]+/) { why = "BAD:no-stub-call"; s = "-" } else { sub(/^call +/, "", s); sub(/ .*/, "", s) }
                        print api, why, s
                        continue
                    }
                    if (api == "CreateFileW") {
                        if (t[j] !~ /^cmp +\$0xffffffffffffffff,%rax/) why = "BAD:no-cmp-rax-minus-1"
                        j++
                    } else {
                        if (t[j] !~ /^test +%eax,%eax/) why = "BAD:no-test-eax"
                        j++
                        if (t[j] !~ /^mov +0x28\(%rsp\),%(e|r)ax/) why = "BAD:no-answer-load"
                        j++
                    }
                    if (t[j] !~ /^jne /) why = "BAD:no-jne"
                    j++
                    s = t[j]
                    if (s !~ /^call +0x[0-9a-f]+/) { why = "BAD:no-stub-call"; s = "-" } else { sub(/^call +/, "", s); sub(/ .*/, "", s) }
                    print api, why, s
                }
            }' "$D/dis" > "$D/sites"
        for api in ReadFile WriteFile SetFilePointerEx CreateFileW CloseHandle; do
            c=$(awk -v a="$api" '$1 == a' "$D/sites" | wc -l | tr -d ' ')
            b=$(awk -v a="$api" '$1 == a && $2 != "ok" {print $2; exit}' "$D/sites")
            if [ "$c" -lt 2 ]; then bad "axis 2: only $c $api site(s) in the probe (floor 2: the literal and the var-held route)"
            elif [ -n "$b" ]; then bad "axis 2: a $api site is not followed by its failure check and stub call ($b)"
            else ok; fi
        done
        TS=$(awk '$1 != "ReadFile" {print $3}' "$D/sites" | sort -u)
        RS=$(awk '$1 == "ReadFile" {print $3}' "$D/sites" | sort -u)
        if [ "$(printf '%s\n' "$TS" | wc -l | tr -d ' ')" != 1 ] || [ "$(printf '%s\n' "$RS" | wc -l | tr -d ' ')" != 1 ] || [ "$TS" = "$RS" ]; then
            bad "axis 2: the write / seek / open / close sites must share ONE table stub and ReadFile's ONE read stub (table: $(echo $TS), read: $(echo $RS))"
        else
            ok
            # axis 3: the table stub, from its first instruction to its ret.
            awk -F'\t' -v at="$TS" '
                { a = $1; sub(/^ +/, "", a); sub(/:$/, "", a) }
                ("0x" a) == at { on = 1 }
                on && NF >= 3 { print $3 }
                on && $3 ~ /^ret/ { exit }' "$D/dis" > "$D/table"
            awk -F'\t' -v at="$RS" '
                { a = $1; sub(/^ +/, "", a); sub(/:$/, "", a) }
                ("0x" a) == at { on = 1 }
                on && NF >= 3 { print $3 }
                on && $3 ~ /^ret/ { exit }' "$D/dis" > "$D/read"
            head1=$(sed -n 1p "$D/table"); head2=$(sed -n 2p "$D/table")
            case "$head1" in "sub "*'$0x28,%rsp'*) ok ;; *) bad "axis 3: the table stub does not open with sub \$0x28,%rsp (it reads '$head1')" ;; esac
            case "$head2" in *"# $GL") ok ;; *) bad "axis 3: the table stub's first call is not through GetLastError's IAT slot $GL (it reads '$head2')" ;; esac
            # Plain POSIX awk (CI's is mawk: no strtonum), so the hex is decoded by hand.
            got=$(awk '
                function hex(s,   i, v) { v = 0; s = tolower(s); sub(/^\$0x/, "", s); sub(/,.*/, "", s)
                    for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
                    return v }
                /^mov +\$0x[0-9a-f]+,%edx/ { e = hex($2); next }
                /^cmp +\$0x[0-9a-f]+,%ecx/ { c = hex($2); p = 1; next }
                p && /^cmove +%edx,%eax/ { print c ":" e }
                { p = 0 }' "$D/table" | sort -t: -k1,1n | tr '\n' ' ' | sed 's/ $//')
            if [ "$got" = "$TABLE" ]; then ok
            else bad "axis 3: the table maps '$got', want '$TABLE'"; fi
            tail2=$(tail -2 "$D/table" | tr '\n' ';')
            case "$tail2" in "neg "*"%rax;ret"*) ok ;; *) bad "axis 3: the table stub does not end neg %rax; ret ('$tail2')" ;; esac
            rd=$(tr '\n' ';' < "$D/read")
            case "$rd" in
                *"call   $TS"*'cmp    $0x6d,%ecx;cmove  %rdx,%rax;cmp    $0x26,%ecx;cmove  %rdx,%rax;mov    0x20(%rsp),%edx;cmp    $0xea,%ecx;cmove  %rdx,%rax;'*) ok ;;
                *) bad "axis 3: the read stub does not call the table and then map 109 / 38 to 0 and 234 to the count: $(printf '%s' "$rd" | tr -s ' ')" ;;
            esac
            case "$rd" in *'xor    %edx,%edx;cmp    $0x6d'*) ok ;; *) bad "axis 3: the read stub's end-of-file rows do not select 0 (xor %edx,%edx before them)" ;; esac
        fi
    fi
fi

# axis 5: static, lib/io.cyr's Windows classification of CREATE_NEW's -EACCES over a directory.
code() { grep -vE '^[[:space:]]*#[^a-z]' "$1"; }
fnbody() { code "$IO" | awk -v n="fn $1(" 'index($0, n) == 1 { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }'; }
warm() { fnbody "$1" | awk '/^[[:space:]]*#ifdef CYRIUS_TARGET_WIN/ { w = 1; next } w == 1 && /^[[:space:]]*#endif/ { exit } w == 1 { print }'; }
case "$(warm file_create_exclusive)" in
    *'if (fd == 0 - 13) {'*'_io_name_exists(path) == 1'*'return 0 - 17;'*) ok ;;
    *) bad "axis 5: file_create_exclusive's CYRIUS_TARGET_WIN arm does not classify -13 (CREATE_NEW over a directory) as -17 by asking the name: $(warm file_create_exclusive | tr -s ' \n' '  ')" ;;
esac
case "$(warm _io_tmp_taken)" in
    *'if (rc == 0 - 13) { return _io_name_exists(tmp); }'*) ok ;;
    *) bad "axis 5: _io_tmp_taken's CYRIUS_TARGET_WIN arm does not classify -13 by asking the name: $(warm _io_tmp_taken | tr -s ' \n' '  ')" ;;
esac

# axis 4: behaviour under wine.
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: axis 4 (wine absent — the cass cross-OS leg runs the same .tcyr on real Windows)"
else
    mkdir -p "$D/w"
    _wine() {  # $1 = exe name inside $D/w, $2 = stdout capture
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine "$1" > "$2" 2>&1 )
    }
    # The four filed repros, verbatim.
    cat > "$D/rd.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var buf[16];
var n = file_read(0 - 999, &buf, 16);        # not a descriptor / handle
syscall(SYS_EXIT, 100 + n);                  # Linux 91 (-EBADF); Windows 100 (0, "EOF")
EOF
    cat > "$D/op.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("no_such_file_w1.txt", O_RDONLY, 0);
syscall(SYS_EXIT, 0 - fd);                   # Linux 2 (-ENOENT); Windows 1 (-1)
EOF
    cat > "$D/sk.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("lseek_neg.tmp", O_RDWR | O_CREAT | O_TRUNC, 420);
file_write(fd, "abcdefgh", 8);
var r1 = xlseek(fd, 0 - 1, 0);      # SEEK_SET to -1: must fail
var r2 = xlseek(fd, 4, 0);
var r3 = xlseek(fd, 0 - 100, 1);    # SEEK_CUR to 4 - 100: must fail
var r4 = xlseek(fd, 0, 1);
fmt_int(r1); println("");
fmt_int(r2); println("");
fmt_int(r3); println("");
fmt_int(r4); println("");
file_close(fd);
xunlink("lseek_neg.tmp");
EOF
    # 6.7.15: the close repro (issues/2026-10-16-pe-close-returns-closehandle-bool.md), verbatim.
    cat > "$D/cl.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("cl_probe.tmp", O_WRONLY | O_CREAT | O_TRUNC, 420);
var ok = sys_close(fd);                      # a real descriptor: 0 on Linux
var bad = sys_close(0 - 999);                # not a descriptor / handle: -9 on Linux
xunlink("cl_probe.tmp");
syscall(SYS_EXIT, 100 + ok * 10 + bad);      # Linux 91; Windows 110 (TRUE 1, FALSE 0)
EOF
    for p in rd op sk cl; do
        ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/$p.cyr" > "$D/w/$p.exe" 2> "$D/$p.err" ) || true
    done
    if [ ! -s "$D/w/rd.exe" ]; then bad "axis 4: the PE build of the read repro produced no binary"
    else xrc=0; _wine rd.exe "$D/rd.out" || xrc=$?
        if [ "$xrc" = 91 ]; then ok; else bad "axis 4: the read repro exits $xrc under wine (want 91: file_read(-999) -> -9; 100 is the old 0, end of file)"; fi
    fi
    if [ ! -s "$D/w/op.exe" ]; then bad "axis 4: the PE build of the open repro produced no binary"
    else xrc=0; _wine op.exe "$D/op.out" || xrc=$?
        if [ "$xrc" = 2 ]; then ok; else bad "axis 4: the open repro exits $xrc under wine (want 2: -ENOENT; 1 is the old -1)"; fi
    fi
    if [ ! -s "$D/w/sk.exe" ]; then bad "axis 4: the PE build of the seek probe produced no binary"
    else xrc=0; _wine sk.exe "$D/sk.out" || xrc=$?
        sk=$(tr -d '\r' < "$D/sk.out" | tr '\n' ' ' | sed 's/ *$//')
        if [ "$sk" = "-22 4 -22 4" ]; then ok; else bad "axis 4: the seek probe prints '$sk' under wine (want '-22 4 -22 4'; '0 4 0 4' is the old answer)"; fi
    fi
    if [ ! -s "$D/w/cl.exe" ]; then bad "axis 4: the PE build of the close repro produced no binary"
    else xrc=0; _wine cl.exe "$D/cl.out" || xrc=$?
        if [ "$xrc" = 91 ]; then ok; else bad "axis 4: the close repro exits $xrc under wine (want 91: a good close 0, close(-999) -9; 110 is the old BOOL answer)"; fi
    fi
    for pair in "$T1:$F1" "$T2:$F2" "$T3:$F3" "$T4:$F4"; do
        t=${pair%:*}; fl=${pair##*:}; b=$(basename "$t" .tcyr)
        ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$t" > "$D/w/$b.exe" 2> "$D/$b.werr" ) || true
        if [ ! -s "$D/w/$b.exe" ]; then
            bad "axis 4: the PE build of $b.tcyr produced no binary: $(grep -m2 '^error' "$D/$b.werr" | tr '\n' ' ')"
            continue
        fi
        wrc=0; _wine "$b.exe" "$D/$b.wout" || wrc=$?
        sum=$(summary "$D/$b.wout"); np=${sum% *}; nf=${sum#* }
        if [ -z "$sum" ] || [ "$wrc" != 0 ] || [ "$nf" != 0 ] || [ "$np" -lt "$fl" ]; then
            bad "axis 4: $b.tcyr under wine: '${sum:-no summary}' (exit $wrc, floor $fl)"
            tr -d '\r' < "$D/$b.wout" | grep -m6 'FAIL:' | sed 's/^/      /'
        else ok; fi
    done
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 9 ] || { echo "FAIL: pe_reroute_failure_errno: only $pass rows ran (floor 9)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_reroute_failure_errno"; exit 1; fi
echo "PASS: pe_reroute_failure_errno — a failed ReadFile / WriteFile / SetFilePointerEx / CreateFileW / CloseHandle answers -errno through one GetLastError table (a good close 0); a drained pipe still reads 0"
