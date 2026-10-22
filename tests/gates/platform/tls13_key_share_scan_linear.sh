#!/bin/sh
# check: serial — a timing ratio (an adversarial ClientHello vs a control of the same framing), each fixture reporting its own CPU time
# tls13_key_share_scan_linear.sh — 6.7.17: the native TLS 1.3 server's key_share loop costs
# O(shares), not shares x groups (CYRIUS-2026-0037).
#
# issues/2026-10-21-tls13-server-key-share-scan-quadratic-in-peer-count.md. RFC 8446 §4.2.8 refuses
# a key_share for a group the client did not list in supported_groups; _tn_parse_client_hello
# answered it by calling _tn_sg_has — a re-validation and a walk of the whole list — once per
# share. Both counts are the peer's: one 16 KB ClientHello of 1,610 one-byte shares on the last of
# 4,025 groups cost the server ~21 ms of CPU (x86_64) before refusing it, where a control of the
# same framing with one share cost ~0.1 ms. Now the list is validated once and a list of more than
# 32 groups answers membership from a one-pass 8 KB bitmap (_tn_sg_set / _tn_sg_member).
#
# Two fixtures, built from one source: `adv` (the 16,166-byte hello above) and `ctl` (the same
# 4,025 groups, 1 share). Each makes 1,000 fresh servers and times ONLY the
# tls_native_server_respond_hello calls by CLOCK_PROCESS_CPUTIME_ID, summed in µs (the wall clock
# counts waiting for a CPU — simd_valueform_no_avx_transition.sh's 6.7.16 lesson), checks every
# call refused the hello with handshake_failure (no shared group; exit 2/3 otherwise — a fixture
# that does not run its path is a loud FAIL), and prints the total. best of 5; adv / ctl must
# read at most 500 %, re-measured up to 3 rounds while it reads over (the axis fails only when every
# round is over). A control under 50,000 µs FAILS by name (too-fast: a ratio of short runs is
# noise). A fixture run over 10 s of wall time is killed and FAILS (the quadratic scan: ~21 s
# per adv run).
# Measured 2026-10-22, x86_64, load ~4-7: fixed 121-122 % (adv 138-209 ms, ctl 113-171 ms); the
# per-share _tn_sg_has restored (the 6.7.16 loop) — the adv run killed at 10 s (RED); a membership
# test that still scans 150 entries per share — 941-948 % on every round (RED). ⛔ x86_64 Linux
# only (the fixtures read the clock by raw syscall 228); elsewhere exit 77, by name.
# CHANGELOG [6.7.17]
set -u
G=tls13_key_share_scan_linear
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL $G: cannot cd to $R"; exit 1; }
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) ;;
  *) echo "SKIP $G: x86_64 Linux only (the fixtures read CLOCK_PROCESS_CPUTIME_ID by syscall 228); this is $(uname -s)/$(uname -m)"; exit 77 ;;
esac
command -v timeout > /dev/null 2>&1 || { echo "SKIP $G: no timeout(1) — the quadratic scan would run unbounded"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC="${CYCC:-$R/build/cycc}"
[ -x "$CC" ] || { echo "FAIL $G: no build/cycc"; exit 1; }

# The fixture; NSHARES is set per build. The servers are made outside the timed calls.
cat > "$T/fix.cyr" <<'EOF'
include "lib/str.cyr"
include "lib/chrono.cyr"
include "lib/random.cyr"
include "lib/tls_native.cyr"

var CERT23 = "3082017d30820123a0030201020214561cee528775ffec8d05834b308f1ad80d7e7dbe300a06082a8648ce3d04030230143112301006035504030c096c6f63616c686f7374301e170d3236303630313138343930365a170d3336303532393138343930365a30143112301006035504030c096c6f63616c686f73743059301306072a8648ce3d020106082a8648ce3d030107034200049167a2981f570fdbd8d94bf20fb4f5c89d77aa5b58cf4ed416bafa0256a2561a04f1e71d57537fc532fc87ca980eb8ba1f8f8704fc7f6a793ba6598b97bb3275a3533051301d0603551d0e04160414e6e9022c5ba23153aa7b2a0004574c417dfbf42e301f0603551d23041830168014e6e9022c5ba23153aa7b2a0004574c417dfbf42e300f0603551d130101ff040530030101ff300a06082a8648ce3d04030203480030450220274b9132990767c26d383d8712024a2c8cdb63e38af642893d1a59ab44a29758022100a57e61df420d2425c712ad284d0ad53ef9c8cdbfd07ba65c952eaead0dc13729";
var KEY23 = "308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420b19108bb3950b49995a9c770e12613b12d96dc2409a464fdc43c63a41b1d4668a144034200049167a2981f570fdbd8d94bf20fb4f5c89d77aa5b58cf4ed416bafa0256a2561a04f1e71d57537fc532fc87ca980eb8ba1f8f8704fc7f6a793ba6598b97bb3275";

# This process's CPU time in µs (clock_gettime(CLOCK_PROCESS_CPUTIME_ID = 2), x86_64 228).
fn _cpu_us(): i64 {
    var ts[16];
    syscall(228, 2, &ts);
    return load64(&ts) * 1000000 + load64(&ts + 8) / 1000;
}

# A 1.3 ClientHello in `buf`: groups 0x1000 + i (i < ng, none of the server's) and `ns` one-byte
# shares on the last `ns` of them. Its length, header included.
fn _hello(buf, ng, ns): i64 {
    var p = buf + 4;
    _tn_be16_w(p, 0x0303);
    memset(p + 2, 0x5A, 32);
    store8(p + 34, 0);
    _tn_be16_w(p + 35, 2);
    _tn_be16_w(p + 37, TLS_AES_256_GCM_SHA384);
    store8(p + 39, 1);
    store8(p + 40, 0);
    var et = p + 41;
    p = p + 43;
    var e0 = p;
    _tn_be16_w(p, TLS_EXT_SUPPORTED_VERSIONS);
    _tn_be16_w(p + 2, 3);
    store8(p + 4, 2);
    _tn_be16_w(p + 5, 0x0304);
    p = p + 7;
    _tn_be16_w(p, TLS_EXT_SUPPORTED_GROUPS);
    _tn_be16_w(p + 2, 2 + 2 * ng);
    _tn_be16_w(p + 4, 2 * ng);
    p = p + 6;
    var i = 0;
    while (i < ng) { _tn_be16_w(p, 0x1000 + i); p = p + 2; i = i + 1; }
    _tn_be16_w(p, TLS_EXT_KEY_SHARE);
    _tn_be16_w(p + 2, 2 + 5 * ns);
    _tn_be16_w(p + 4, 5 * ns);
    p = p + 6;
    i = 0;
    while (i < ns) {
        _tn_be16_w(p, 0x1000 + ng - ns + i);
        _tn_be16_w(p + 2, 1);
        store8(p + 4, 0x42);
        p = p + 5;
        i = i + 1;
    }
    _tn_be16_w(et, p - e0);
    var n = p - buf;
    tls_native_handshake_write_header(buf, TLS_HS_CLIENT_HELLO, n - 4);
    return n;
}

fn _print_num(v): i64 {
    var buf[32];
    var p = 31;
    store8(&buf + p, 10);
    p = p - 1;
    if (v == 0) { store8(&buf + p, 48); p = p - 1; }
    while (v > 0) { store8(&buf + p, 48 + v % 10); v = v / 10; p = p - 1; }
    syscall(1, 1, &buf + p + 1, 31 - p);
    return 0;
}

fn main(): i64 {
    alloc_init();
    var buf = alloc(17000);
    var n = _hello(buf, 4025, NSHARES);
    var sh = alloc(1024);
    var cert = hex_decode(CERT23, strlen(CERT23));
    var key = hex_decode(KEY23, strlen(KEY23));
    var tot = 0;
    var i = 0;
    while (i < 1000) {
        var srv = tls_native_new_server(cert, strlen(CERT23) / 2, key, strlen(KEY23) / 2);
        tls_native_server_load_creds(srv);
        var t0 = _cpu_us();
        var r = tls_native_server_respond_hello(srv, buf, n, sh, 1024);
        tot = tot + _cpu_us() - t0;
        if (r != TLS_ERR_HANDSHAKE_FAILED) { syscall(60, 2); }
        if (load64(srv + TLS_CTX_OFF_HS_ALERT) != TLS_AD_HANDSHAKE_FAILURE) { syscall(60, 3); }
        i = i + 1;
    }
    _print_num(tot);
    syscall(60, 0);
    return 0;
}
EOF
build() {  # build <name> <shares>
  sed "s/NSHARES/$2/" "$T/fix.cyr" | "$CC" > "$T/$1" 2> "$T/$1.err" || { echo "FAIL $G: the $1 fixture did not compile:"; sed 's/^/    /' "$T/$1.err"; exit 1; }
  chmod +x "$T/$1"
}
build adv 1610
build ctl 1
# best of 5 of the CPU time the fixture reports, in µs; `t` when a run hit the timeout, `x` when a
# run failed or printed none.
best_cpu() {
  b=999999999; r=0
  while [ $r -lt 5 ]; do
    rc=0; m=$(timeout 10 "$1" 2>/dev/null) || rc=$?
    [ "$rc" = 124 ] && { echo t; return 0; }
    [ "$rc" = 0 ] || { echo x; return 0; }
    case "$m" in ''|*[!0-9]*) echo x; return 0 ;; esac
    [ "$m" -lt "$b" ] && b=$m
    r=$((r + 1))
  done
  echo $b
}
need_cpu() {  # need_cpu <fixture> <value>
  case "$2" in
    t) echo "FAIL $G: the $1 fixture ran over 10 s of wall time and was killed — the key_share loop scans supported_groups per share again (CYRIUS-2026-0037: ~21 ms of CPU per 16 KB hello)"; exit 1 ;;
    ''|*[!0-9]*) echo "FAIL $G: the $1 fixture failed or printed no CPU time (exit 2: a hello not refused; 3: not handshake_failure) — fixture broken, nothing to compare"; exit 1 ;;
  esac
}
RN=0; RLOG=""
while [ "$RN" -lt 3 ]; do
  RA=$(best_cpu "$T/adv"); need_cpu adv "$RA"
  RB=$(best_cpu "$T/ctl"); need_cpu ctl "$RB"
  RN=$((RN + 1))
  [ "$RB" -ge 50000 ] || { echo "FAIL $G: too-fast — the control ran in ${RB}us, under 50,000 (a ratio of short runs is noise; lengthen the fixtures, or the fixture is broken)"; exit 1; }
  RR=$(( RA * 100 / RB ))
  RLOG="$RLOG ${RA}us/${RB}us ${RR}%;"
  [ "$RR" -le 500 ] && break
done
if [ "$RR" -gt 500 ]; then
  echo "FAIL $G: the 16 KB hello (1,610 shares on the last of 4,025 groups) vs one share, CPU time of respond_hello, bound 500%, every round over it:${RLOG}"
  echo "  The key_share loop's membership check is no longer O(1) per share (CYRIUS-2026-0037)."
  exit 1
fi
echo "PASS $G: 1,610 shares ${RA}us vs 1 share ${RB}us of respond_hello CPU over 1,000 hellos (${RR}%, bound 500%, round ${RN})"
exit 0
