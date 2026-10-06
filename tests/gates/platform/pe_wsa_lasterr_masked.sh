#!/bin/sh
# 6.6.16 — every WSAGetLastError and every `int`-returning ws2_32 result in lib/ is read MASKED
# to 32 bits on Windows.
#
# ⛔ WHY: WSAGetLastError (0xF024) and the ws2_32 calls that return a C `int` (closesocket,
# bind, getsockopt, WSAIoctl, connect, WSARecv, WSASend, getaddrinfo, setsockopt, listen,
# getpeername, getsockname — 0xF023 / 0xF025-0xF02B / 0xF032 / 0xF033 / 0xF036 / 0xF037) reach
# their PE emitters (src/backend/x86/emit.cyr EWSALASTERR_PE … EGETSOCKNAME_PE) with NO extension
# of the result: only eax is defined and rax[63:32] is whatever the callee left. (The 0xF045-0xF04A
# band is sign-extended by the emitter, 0xF04B GetLastError zero-extended; neither is scanned.)
# Until 6.6.16 lib/syscalls_windows.cyr's fd_wait_ready returned `0 - syscall(61476)` and its
# sys_getpeername / sys_getsockname / sys_listen tested `r == 0` on the raw int, and
# lib/async_win.cyr compared `syscall(0xF024) != 997` — so dirty upper bits would have turned a
# WSAE* code into a huge non-errno, a successful listen into a failure, and WSA_IO_PENDING into a
# synchronous failure that fails the async task. lib/net.cyr (_net_wsa_err / _net_wsa_rc) and
# lib/tls_native_conn.cyr (_tn_win_sockerr) already masked. The defect is ABI-LATENT: the
# Windows build measured on cass zero-extends, so no runtime row can turn red — which is why this
# gate is STATIC. The exact values are pinned on cass by tests/tcyr/crossos/fd_wait_ready.tcyr
# (-10038 from fd_wait_ready and sys_listen on a bogus socket) and getpeername_xlat.tcyr.
#
# THE AXES (static, lib/**/*.cyr; comments and string contents are stripped first)
#   axis 1  every `0xF024` / `61476` token is the first argument of a `syscall(...)` whose
#           closing paren is followed by `& 0xFFFFFFFF`. Any other spelling — `0 - syscall(61476)`,
#           `syscall(0xF024) != 997`, an alias (`var WSA_LAST = 0xF024;`) — is RED.
#   axis 2  every `syscall(N, ...)` with N in the int-returning set above is one of:
#             - a discarded statement (`syscall(0xF023, s);` at line start or after `{` / `;`);
#             - wrapped whole by `_net_wsa_rc(` (lib/net.cyr's masking helper);
#             - followed by `& 0xFFFFFFFF` (`(syscall(0xF027, ...) & 0xFFFFFFFF) != 0`);
#             - `var X = syscall(...);` where every later use of X in that fn is `X & 0xFFFFFFFF`
#               or `_net_wsa_rc(X`.
#           Anything else (`return syscall(0xF033, ...)`, `if (syscall(...) == 0)`) is RED.
#   axis 3  lib/async_win.cyr: every `var X = callptr(...)` (the ConnectEx / AcceptEx BOOLs) is
#           used only as `X & 0xFFFFFFFF`.
#   axis 4  each never-zero error helper (_sw_wsa_err, _net_wsa_err, _tn_win_sockerr and, 6.6.17,
#           lib/async_win.cyr's _asw_wsa_err) masks and maps an error of 0 to -1, so a failure can
#           never read as success.
#   axis 5  (6.6.17) lib/async_win.cyr: the kernel32 BOOLs — SetWaitableTimer (0xF02F),
#           RegisterWaitForSingleObject (0xF02D), CreateProcessW (0xF005 / 61445) — follow the axis 2
#           rules (their emitters ESETTIMER_PE / EREGWAIT_PE / ECREATEPROC_PE do not extend eax
#           either: the interval and process tasks tested `== 0` raw), and the connect task's bind
#           (0xF025) is never DISCARDED (it was: a failed bind surfaced as a ConnectEx error). The
#           Windows build measured on cass zero-extends these too, so this axis is static as well.
#   self    the scanner is run on a CLEAN fixture (must pass) and on one mutant per rule (each
#           must fail) before it scans lib/, so a scanner that went blind cannot read GREEN.
#   floors  >= 7 WSAGetLastError sites, >= 25 int-reroute sites, >= 2 callptr sites, >= 3 files,
#           >= 6 async_win kernel32 BOOL sites.
#
# MUTATION LEDGER — built and run 2026-10-04 (lane net, bite net-3; x86_64 Linux), each mutant
# applied to a scratch copy of the tree and the gate run from that copy:
#   mutant                                                              result
#   fd_wait_ready back to `return 0 - syscall(61476);`                   axis 1 FAIL
#   async_win :WSARecv back to `syscall(0xF024) != 997`                  axis 1 FAIL
#   sys_listen back to `if (r == 0) { return 0; }`                       axis 2 FAIL
#   sys_getpeername back to `if (r == 0)`                                axis 2 FAIL
#   async_win WSAIoctl back to `if (syscall(0xF027, ...) != 0)`          axis 2 FAIL
#   async_win ConnectEx back to `if (cr == 0)`                           axis 3 FAIL
#   _sw_wsa_err without the `e == 0` → -1 line                           axis 4 FAIL
#   (6.6.17) _asw_wsa_err without its `e == 0` → -1 line, or unmasked    axis 4 FAIL (each)
#   _net_wsa_err's `& 0xFFFFFFFF` dropped                                axes 1 and 4 FAIL
#   async_win WSARecv back to `if (rc != 0)`                             axis 2 FAIL
#   async_win getaddrinfo back to `if (syscall(0xF02B, ...) != 0)`       axis 2 FAIL
#   the whole slot-open lib/ (0bf9b773)                                  19 rows FAIL (axes 1-4)
#   (6.6.17, lane lib l5) the 4a37046b lib/async_win.cyr                  axis 5 FAIL: 6 rows (the
#     interval task's two raw `== 0`, the process task's, CreateProcessW's `ok` twice, the bind)
# No compiler and no wine: the gate cds to its ROOT and passes from any cwd.
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.6.16]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd) || { echo "FAIL: pe_wsa_lasterr_masked: cannot resolve ROOT"; exit 1; }
cd "$ROOT" || { echo "FAIL: pe_wsa_lasterr_masked: cannot cd to $ROOT"; exit 1; }
[ -d lib ] || { echo "FAIL: pe_wsa_lasterr_masked: $ROOT/lib is missing"; exit 1; }
command -v awk > /dev/null 2>&1 || { echo "SKIP: pe_wsa_lasterr_masked: no awk"; exit 77; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_wsa_lasterr_masked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM

# scan FILE... — prints one `BAD <axis> <file>:<line>: <why>` per violation, then
# `COUNT <wsa> <int> <callptr> <helpers-ok>` (POSIX awk: no gawk extensions, so it runs on mawk).
scan() {
    awk '
    function strip(s,   out, i, c, q) {      # drop string contents and the trailing comment
        out = ""; q = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (q) { if (c == "\\") { i++; continue } if (c == "\"") { q = 0; out = out c } continue }
            if (c == "\"") { q = 1; out = out c; continue }
            if (c == "#") break
            out = out c
        }
        return out
    }
    function hexval(t,   i, c, v) {
        v = 0; t = tolower(t)
        for (i = 3; i <= length(t); i++) { c = index("0123456789abcdef", substr(t, i, 1)); v = v * 16 + c - 1 }
        return v
    }
    function numval(t) {
        if (t ~ /^0[xX][0-9a-fA-F]+$/) return hexval(t)
        if (t ~ /^[0-9]+$/) return t + 0
        return -1
    }
    function closeparen(s, p,   d, i, c) {    # p = index of the "(" ; returns index of its ")"
        d = 0
        for (i = p; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "(") d++
            else if (c == ")") { d--; if (d == 0) return i }
        }
        return 0
    }
    function masked(rest) { return rest ~ /^[ \t]*&[ \t]*0[xX][fF][fF][fF][fF][fF][fF][fF][fF]([^0-9a-zA-Z_]|$)/ }
    function bad(ax, why) { printf "BAD %s %s:%d: %s\n", ax, FILENAME, FNR, why }
    function isword(c) { return c ~ /[A-Za-z0-9_]/ }
    BEGIN {
        split("61475 61477 61478 61479 61480 61481 61482 61483 61490 61491 61494 61495", a, " ")
        for (k in a) INTSET[a[k]] = 1
        split("61485 61487 61445", bb, " ")         # async_win kernel32 BOOLs (axis 5)
        for (k in bb) BOOLSET[bb[k]] = 1
        nw = 0; ni = 0; nc = 0; nh = 0; nb = 0
    }
    FNR == 1 { nv = 0; infn = ""; nfiles++ }
    {
        line = strip($0)
        if (line ~ /^fn[ \t]/) { nv = 0; infn = line; sub(/^fn[ \t]+/, "", infn); sub(/\(.*/, "", infn) }
        # axis 4: the never-zero helpers
        if (infn == "_sw_wsa_err" || infn == "_net_wsa_err" || infn == "_tn_win_sockerr" || infn == "_asw_wsa_err") {
            if (line ~ /^fn[ \t]/) { H[infn, "m"] = 0; H[infn, "z"] = 0; HS[infn] = FILENAME }
            if (line ~ /syscall\([ \t]*(0[xX][fF]024|61476)[ \t]*\)[ \t]*&[ \t]*0[xX][fF][fF][fF][fF][fF][fF][fF][fF]/) H[infn, "m"] = 1
            if (line ~ /if[ \t]*\([ \t]*e[ \t]*==[ \t]*0[ \t]*\)[ \t]*\{[ \t]*return[ \t]+0[ \t]*-[ \t]*1[ \t]*;/) H[infn, "z"] = 1
        }
        # axis 1: every 0xF024 / 61476 token
        s = line; off = 0
        while (match(s, /(0[xX][fF]024|61476)/)) {
            st = RSTART; ln = RLENGTH
            pre = substr(s, 1, st - 1); post = substr(s, st + ln)
            okw = 0
            if ((st == 1 || !isword(substr(s, st - 1, 1))) && !isword(substr(post, 1, 1))) {
                if (pre ~ /syscall\([ \t]*$/ && post ~ /^[ \t]*\)/) {
                    rest = post; sub(/^[ \t]*\)/, "", rest)
                    if (masked(rest)) okw = 1
                    else bad("axis1", "WSAGetLastError (0xF024) read without `& 0xFFFFFFFF` — only eax is defined")
                } else bad("axis1", "0xF024 / 61476 used other than as `syscall(0xF024) & 0xFFFFFFFF` (alias or raw use)")
                nw++
            }
            s = post
        }
        # axes 2/3: tracked vars — every later use must be masked
        for (v = 1; v <= nv; v++) {
            name = VN[v]; s = line
            while (match(s, "[A-Za-z0-9_]*" name "[A-Za-z0-9_]*")) {
                tok = substr(s, RSTART, RLENGTH); pre = substr(s, 1, RSTART - 1); post = substr(s, RSTART + RLENGTH)
                if (tok == name) {
                    if (!(masked(post) || pre ~ /_net_wsa_rc\([ \t]*$/))
                        bad(VA[v], "`" name "` (an int from " VW[v] ") used without `& 0xFFFFFFFF`")
                }
                s = post
            }
        }
        # axis 2: int-returning reroutes
        s = line; base = 0
        while (match(s, /syscall\(/)) {
            st = RSTART; p = st + 7
            cp = closeparen(s, p)
            argtxt = substr(s, p + 1); sub(/[,)].*/, "", argtxt); gsub(/[ \t]/, "", argtxt)
            nvv = numval(argtxt)
            if (FILENAME ~ /async_win\.cyr$/ && (nvv "") in BOOLSET) {
                nb++
                pre = substr(s, 1, st - 1)
                if (cp == 0) { bad("axis5", "syscall(" argtxt ", ...) spans lines — the scanner cannot verify it") }
                else {
                    post = substr(s, cp + 1)
                    if (pre ~ /(^|[{;])[ \t]*$/ && post ~ /^[ \t]*;/) { }                   # discarded
                    else if (masked(post)) { }                                               # masked in place
                    else if (pre ~ /(^|[{;])[ \t]*var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*$/ && post ~ /^[ \t]*;/) {
                        vn = pre; sub(/^.*var[ \t]+/, "", vn); sub(/[ \t]*=.*$/, "", vn)
                        nv++; VN[nv] = vn; VA[nv] = "axis5"; VW[nv] = "syscall(" argtxt ") (a BOOL)"
                    }
                    else bad("axis5", "kernel32 BOOL from syscall(" argtxt ", ...) tested or returned unmasked — only eax is defined")
                }
            }
            if (FILENAME ~ /async_win\.cyr$/ && nvv == 61477 && cp != 0) {
                pre = substr(s, 1, st - 1); post = substr(s, cp + 1)
                if (pre ~ /(^|[{;])[ \t]*$/ && post ~ /^[ \t]*;/) bad("axis5", "the bind (0xF025) result is discarded — a failed bind must fail the task")
            }
            if ((nvv "") in INTSET) {
                ni++
                pre = substr(s, 1, st - 1)
                if (cp == 0) { bad("axis2", "syscall(" argtxt ", ...) spans lines — the scanner cannot verify it") }
                else {
                    post = substr(s, cp + 1)
                    if (pre ~ /(^|[{;])[ \t]*$/ && post ~ /^[ \t]*;/) { }                   # discarded
                    else if (pre ~ /_net_wsa_rc\([ \t]*$/) { }                              # helper-wrapped
                    else if (masked(post)) { }                                               # masked in place
                    else if (pre ~ /(^|[{;])[ \t]*var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*$/ && post ~ /^[ \t]*;/) {
                        vn = pre; sub(/^.*var[ \t]+/, "", vn); sub(/[ \t]*=.*$/, "", vn)
                        nv++; VN[nv] = vn; VA[nv] = "axis2"; VW[nv] = "syscall(" argtxt ")"
                    }
                    else bad("axis2", "int result of syscall(" argtxt ", ...) tested or returned unmasked — only eax is defined")
                }
            }
            s = substr(s, st + 8)
        }
        # axis 3: callptr BOOLs in async_win.cyr
        if (FILENAME ~ /async_win\.cyr$/ && line ~ /var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*callptr\(/) {
            vn = line; sub(/^.*var[ \t]+/, "", vn); sub(/[ \t]*=.*$/, "", vn)
            nv++; VN[nv] = vn; VA[nv] = "axis3"; VW[nv] = "callptr (a BOOL)"; nc++
        }
    }
    END {
        for (h in HS) {
            if (!H[h, "m"]) printf "BAD axis4 %s: %s does not read `syscall(0xF024) & 0xFFFFFFFF`\n", HS[h], h
            else if (!H[h, "z"]) printf "BAD axis4 %s: %s does not map an error of 0 to -1 (`if (e == 0) { return 0 - 1; }`)\n", HS[h], h
            else nh++
        }
        printf "COUNT %d %d %d %d %d\n", nw, ni, nc, nh, nb
    }' "$@"
}

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# ── self-test: a clean fixture passes, each mutant fails on its axis ───────────────────────────
mkdir -p "$D/fx"
cat > "$D/fx/clean.cyr" <<'EOF'
fn _sw_wsa_err(): i64 {
    var e = syscall(61476) & 0xFFFFFFFF;   # WSAGetLastError
    if (e == 0) { return 0 - 1; }
    return 0 - e;
}
fn ls(fd, b): i64 {
    var r = syscall(0xF033, fd, b);
    if ((r & 0xFFFFFFFF) == 0) { return 0; }
    return _sw_wsa_err();
}
fn s1(x): i64 {
    syscall(0xF023, x);
    if ((syscall(0xF027, x, 0, 0, 0, 0, 0, 0, 0, 0) & 0xFFFFFFFF) != 0) { syscall(0xF023, x); return 0 - 1; }
    if ((syscall(0xF024) & 0xFFFFFFFF) != 997) { return 0 - 1; }
    var s = "syscall(0xF024) != 997";
    return _net_wsa_rc(syscall(0xF025, x, 0, 16));
}
EOF
cp "$D/fx/clean.cyr" "$D/fx/async_win.cyr"
printf 'fn c(f): i64 {\n    var cr = callptr(f, 0);\n    if ((cr & 0xFFFFFFFF) == 0) { return 1; }\n    return 0;\n}\n' >> "$D/fx/async_win.cyr"
cat >> "$D/fx/async_win.cyr" <<'EOF'
fn t(x, d): i64 {
    if ((syscall(0xF02F, x, d, 0, 0, 0, 0) & 0xFFFFFFFF) == 0) { return 0 - 1; }
    syscall(0xF02D, d, x, 0, 0, 0, 8);
    var ok = syscall(61445, d);
    if ((ok & 0xFFFFFFFF) == 0) { return 0; }
    if ((syscall(0xF025, x, d, 16) & 0xFFFFFFFF) != 0) { return 0 - 1; }
    return 1;
}
EOF
out=$(scan "$D/fx/async_win.cyr")
if printf '%s\n' "$out" | grep -q '^BAD'; then bad "self: the clean fixture is flagged: $(printf '%s' "$out" | grep '^BAD' | head -3 | tr '\n' ' ')"
elif ! printf '%s\n' "$out" | grep -q '^COUNT 2 6 1 1 3$'; then bad "self: the clean fixture counts read '$(printf '%s' "$out" | tail -1)', want 'COUNT 2 6 1 1 3'"
else ok; fi

mutant() {  # $1 = expected axis, $2 = sed expression, $3 = label
    sed "$2" "$D/fx/async_win.cyr" > "$D/fx/m/async_win.cyr"
    if cmp -s "$D/fx/async_win.cyr" "$D/fx/m/async_win.cyr"; then bad "self: mutant '$3' did not apply"; return; fi
    if scan "$D/fx/m/async_win.cyr" | grep -q "^BAD $1 "; then ok
    else bad "self: mutant '$3' is not caught on $1"; fi
}
mkdir -p "$D/fx/m"
mutant axis1 's/return 0 - e;/return 0 - syscall(61476);/'                        "raw negated WSAGetLastError"
mutant axis1 's/if ((syscall(0xF024) \& 0xFFFFFFFF) != 997)/if (syscall(0xF024) != 997)/' "unmasked != 997"
mutant axis1 's/^fn ls(fd, b): i64 {/var WSA_LAST = 0xF024;\nfn ls(fd, b): i64 {/'  "aliased 0xF024"
mutant axis2 's/if ((r \& 0xFFFFFFFF) == 0)/if (r == 0)/'                          "var tested unmasked"
mutant axis2 's/if ((syscall(0xF027, \(.*\)) \& 0xFFFFFFFF) != 0)/if (syscall(0xF027, \1) != 0)/' "inline unmasked"
mutant axis2 's/return _net_wsa_rc(syscall(0xF025, x, 0, 16));/return syscall(0xF025, x, 0, 16);/' "returned raw"
mutant axis3 's/if ((cr \& 0xFFFFFFFF) == 0)/if (cr == 0)/'                        "callptr BOOL unmasked"
mutant axis4 '/if (e == 0) { return 0 - 1; }/d'                                   "helper may return 0"
mutant axis5 's/if ((syscall(0xF02F, x, d, 0, 0, 0, 0) \& 0xFFFFFFFF) == 0)/if (syscall(0xF02F, x, d, 0, 0, 0, 0) == 0)/' "SetWaitableTimer BOOL unmasked"
mutant axis5 's/if ((ok \& 0xFFFFFFFF) == 0) { return 0; }/if (ok == 0) { return 0; }/' "CreateProcessW BOOL var unmasked"
mutant axis5 's/if ((syscall(0xF025, x, d, 16) \& 0xFFFFFFFF) != 0) { return 0 - 1; }/syscall(0xF025, x, d, 16);/' "bind discarded"

# ── the tree ───────────────────────────────────────────────────────────────────────────────────
FILES=$(find lib -name '*.cyr' | LC_ALL=C sort)
[ -n "$FILES" ] || { echo "FAIL: pe_wsa_lasterr_masked: no lib/**/*.cyr found"; exit 1; }
# shellcheck disable=SC2086
out=$(scan $FILES)
bads=$(printf '%s\n' "$out" | grep '^BAD' || true)
if [ -n "$bads" ]; then
    printf '%s\n' "$bads" | while IFS= read -r l; do printf '  FAIL: %s\n' "${l#BAD }"; done
    fail=$((fail + $(printf '%s\n' "$bads" | wc -l)))
else ok; fi
set -- $(printf '%s\n' "$out" | grep '^COUNT' | tail -1)
nw=${2:-0}; ni=${3:-0}; nc=${4:-0}; nh=${5:-0}; nb=${6:-0}
nfiles=$(grep -l -e '0xF024' -e '61476' $FILES 2>/dev/null | wc -l)
[ "$nw" -ge 7 ]  && ok || bad "floor: $nw WSAGetLastError sites in lib/ (want >= 7) — the scan went blind or a site moved"
[ "$ni" -ge 25 ] && ok || bad "floor: $ni int-reroute sites in lib/ (want >= 25)"
[ "$nc" -ge 2 ]  && ok || bad "floor: $nc async_win callptr sites (want >= 2: ConnectEx, AcceptEx)"
[ "$nh" -eq 4 ]  && ok || bad "axis 4: $nh of the 4 never-zero helpers (_sw_wsa_err, _net_wsa_err, _tn_win_sockerr, _asw_wsa_err) found and correct"
[ "$nfiles" -ge 3 ] && ok || bad "floor: $nfiles files carry WSAGetLastError (want >= 3)"
[ "$nb" -ge 6 ]  && ok || bad "floor: $nb async_win kernel32 BOOL sites (want >= 6: two SetWaitableTimer, three RegisterWait, CreateProcessW)"

if [ "$fail" -ne 0 ]; then
    echo "FAIL: pe_wsa_lasterr_masked: $fail failed, $pass passed"
    exit 1
fi
echo "PASS: pe_wsa_lasterr_masked ($pass checks; $nw WSAGetLastError sites, $ni int-reroute sites, $nc callptr BOOLs, $nh helpers, $nb kernel32 BOOLs)"
exit 0
