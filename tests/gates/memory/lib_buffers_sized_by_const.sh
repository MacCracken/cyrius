#!/bin/sh
# tests/gates/memory/lib_buffers_sized_by_const.sh — 6.7.6 (Break 1, lane H)
#
# EVERY FIXED BUFFER IN CYRIUS'S OWN lib/ THAT A NAMED BOUND GOVERNS IS SIZED BY THAT BOUND.
#
# THE SHAPE. Until 6.7.2 an array size had to be a literal, so a buffer and the bound that
# governs what is written into it were two copies of one number: `_LOG_LINE_MAX = 511` beside
# `var buf[512]` (the CYRIUS-2026-0013 site), `TLS_RECORD_MAX_PLAINTEXT` beside `ptbuf[16385]`
# (whose comment said "array size must be a literal"), `TLS_HKDF_LABEL_BUF_LEN` beside
# `infobuf[512]`. A hand-kept copy drifts, and a buffer that drifts below its bound is a stack
# overflow. 6.7.2 made an array size a const context, so since 6.7.6 each of these buffers is
# sized BY its bound: a private bound is a `const`; a public one keeps its `var` for the API
# and is initialised from a `const _NAME` twin (`const _X = N; var X = _X;`), which sizes the
# buffer. (The TLOCAL_MAX_SLOTS family is pinned by tls_window_matches_max_slots.sh.)
#
# Proven at the change: with each public var kept literal and each private const kept a var
# (a control copy of lib/), the probe build of every touched module was BYTE-IDENTICAL to
# 6.7.5's on x86, x86-Mach-O, arm64-Mach-O, PE, agnos, aarch64 and cx — every size is the same
# number it was, now written once.
#
# AXES
#   1  every row's declaration is present the stated number of times (a literal-sized copy,
#      a renamed buffer or a dropped const reads RED by name)
#   2  every private bound is a `const` and no `var` of its name is left
#   3  every public bound's var is initialised from its `const _NAME` twin, not a literal
#   4  no cyrius-own lib file still says an array size "must be a literal" (the stale claim
#      that kept these copies alive)
#   5  anti-vacuous floor: the rows above matched >= 40 declarations
#
# MUTATION LEDGER (6.7.6, each run in a scratch copy of the tree, each RED):
#   log.cyr one `var buf[_LOG_LINE_MAX + 1]` back to `var buf[512]`          -> axis 1
#   tls_native_hs13.cyr ptbuf back to `[16385]`                               -> axis 1
#   tls_native.cyr `var TLS_RECORD_MAX_PLAINTEXT = 16384;`                    -> axis 3
#   math.cyr `const _F64P_DEC_CAP` back to `var`                              -> axis 2
#   process_agnos.cyr one argv blob back to `var b[1024]`                     -> axis 1
#   keysched's "(array size must be a literal)" comment restored              -> axis 4
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=lib_buffers_sized_by_const
FAILS=0
MATCHED=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
_ok() { echo "  ok: $1"; }

# need FILE COUNT ERE WHAT — the ERE must match exactly COUNT lines of FILE.
need() {
    [ -f "$1" ] || { _fail "$1: missing — the gate is blind, not the code clean"; return; }
    n=$(grep -cE "$3" "$1")
    if [ "$n" -eq "$2" ]; then MATCHED=$((MATCHED + n)); _ok "$1: $4 ($n)"
    else _fail "$1: $4 — expected $2 line(s) matching /$3/, found $n"; fi
}

echo "axis 1 — each buffer is sized by its bound:"
need lib/log.cyr 2 'var buf\[_LOG_LINE_MAX \+ 1\];' "the two line scratches hold _LOG_LINE_MAX + NUL"
need lib/math.cyr 1 'var dg\[_F64P_DEC_CAP\];' "the exact-decimal digits"
need lib/math.cyr 1 'var tmp\[_F64P_DEC_CAP \+ 32\];' "the decimal shift scratch"
need lib/process.cyr 1 'var ks\[_PROC_KILL_STATE\];' "the blocking kill's state"
need lib/thread_win.cyr 1 '^var _chan_wp_keep: i64\[_chan_wp_cap\];' "the idle wait-port pool"
need lib/process_win.cyr 1 '^var _win_job_tab\[_WIN_JOB_SLOTS \* 2\];' "the job table: two words a slot"
need lib/async_macos.cyr 2 'var (ch|ev)\[_KEV_SIZE\];' "one-kevent buffers"
need lib/async_macos.cyr 1 'var evb\[_KEV_BATCH \* _KEV_SIZE\];' "the poll's event batch"
need lib/async_macos.cyr 1 'sys_kevent\(load64\(rt\), 0, 0, &evb, _KEV_BATCH, tsp\);' "the poll asks for the batch it sized"
need lib/tls_native_hs13.cyr 1 'var ptbuf\[_TLS_RECORD_MAX_PLAINTEXT \+ 1\];' "the TLS 1.3 seal's plaintext + inner type"
need lib/tls_native_keysched.cyr 1 'var infobuf\[_TLS_HKDF_LABEL_BUF_LEN\];' "the HkdfLabel scratch"
need lib/tls_native_keysched.cyr 1 'var thbuf\[_TLS_MAX_DIGEST_LEN\];' "Derive-Secret's transcript hash"
need lib/tls_native_hs12.cyr 1 'var shbuf\[_TLS_MAX_DIGEST_LEN\];' "the EMS session hash"
need lib/tls_native_hs13.cyr 1 'var dg\[_TLS_MAX_DIGEST_LEN\];' "the TLS 1.2 ECDSA digest"
need lib/tls_native_hs13.cyr 1 'var mh\[_TLS_HANDSHAKE_HEADER_LEN \+ _TLS_MAX_DIGEST_LEN\];' "the HRR message_hash"
need lib/tls_native_lowlevel.cyr 1 'var clone\[_TLS_SHA384_CTX_LEN\];' "the transcript ctx clone"
need lib/tls_native_hs12.cyr 2 'var nonce\[_TLS_AEAD_NONCE_LEN\];' "TLS 1.2 record nonces"
need lib/tls_native_hs13.cyr 2 'var nonce\[_TLS_AEAD_NONCE_LEN\];' "TLS 1.3 record nonces"
need lib/tls_native_hs12.cyr 1 'var expected\[_TLS12_VERIFY_DATA_LEN\];' "the expected verify_data"
need lib/tls_native_hs12.cyr 2 'var seed\[_TLS12_SEED_LEN\];' "the PRF seeds"
need lib/tls_native_hs12.cyr 2 '&seed, _TLS12_SEED_LEN, ' "the PRF reads the seed length it sized"
need lib/tls_native_hs13.cyr 1 'var hrr\[_TLS_RANDOM_LEN\];' "the HRR sentinel random"
need lib/process_agnos.cyr 10 'var b\[_SPAWN_ARGV_MAX\];' "agnos argv blobs"
need lib/async_agnos.cyr 1 'var b\[_SPAWN_ARGV_MAX\];' "agnos async argv blob"
need lib/regression_agnos.cyr 3 'var b\[_SPAWN_ARGV_MAX\];' "agnos regression argv blobs"

echo "axis 2 — each private bound is a const:"
for row in "lib/log.cyr:_LOG_LINE_MAX" "lib/math.cyr:_F64P_DEC_CAP" "lib/process.cyr:_PROC_KILL_STATE" \
           "lib/thread_win.cyr:_chan_wp_cap" "lib/process_win.cyr:_WIN_JOB_SLOTS" "lib/async_macos.cyr:_KEV_BATCH" \
           "lib/tls_native_hs12.cyr:_TLS12_SEED_LEN"; do
    f=${row%%:*}; c=${row#*:}
    if grep -qE "^const $c *= " "$f" && ! grep -qE "^var $c\b" "$f"; then _ok "$f: $c is a const"
    else _fail "$f: $c is not a top-level const (or a var of its name is back) — a var cannot size a buffer, so the buffer and its bound split into two copies again"; fi
done

echo "axis 3 — each public bound is initialised from its const twin:"
for row in "lib/tls_native.cyr:TLS_RECORD_MAX_PLAINTEXT" "lib/tls_native.cyr:TLS_AEAD_NONCE_LEN" \
           "lib/tls_native_lowlevel.cyr:TLS_HANDSHAKE_HEADER_LEN" "lib/tls_native_lowlevel.cyr:TLS_SHA384_CTX_LEN" \
           "lib/tls_native_keysched.cyr:TLS_HKDF_LABEL_BUF_LEN" "lib/tls_native_keysched.cyr:TLS_MAX_DIGEST_LEN" \
           "lib/tls_native_hs12.cyr:TLS12_VERIFY_DATA_LEN" "lib/tls_native_hs12.cyr:TLS12_RANDOM_LEN" \
           "lib/tls_native_hs13.cyr:TLS_RANDOM_LEN" "lib/async_macos.cyr:KEV_SIZE" \
           "lib/thread_local.cyr:TLS_REG_MAX" "lib/syscalls_x86_64_agnos.cyr:SPAWN_ARGV_MAX"; do
    f=${row%%:*}; v=${row#*:}
    if grep -qE "^const _$v *= *[^;]+;" "$f" && grep -qE "^var $v *= *_$v;" "$f"; then _ok "$f: $v = _$v"
    else _fail "$f: expected 'const _$v = N;' and 'var $v = _$v;' — a literal in the var is a second copy of the bound its buffers are sized by"; fi
done
need lib/thread_local.cyr 2 '^var _tls_(key|blk)\[_TLS_REG_MAX\];' "the arm64-macOS thread registry"

echo "axis 4 — no stale 'array size must be a literal' claim in cyrius's own lib/:"
OWN=$(ls lib/*.cyr | grep -vE '^lib/(bayan|ganita|mabda|niyama|patra|sakshi|sandhi|sankoch|sigil|vani|yantra|yukti)\.cyr$')
STALE=$(grep -nE 'must be a (LITERAL|literal)' $OWN 2>/dev/null || true)
if [ -z "$STALE" ]; then _ok "none"
else _fail "an array size has been a const context since 6.7.2; size the buffer by its bound: $STALE"; fi

echo "axis 5 — anti-vacuous floor:"
if [ "$MATCHED" -ge 40 ]; then _ok "$MATCHED declarations matched (floor 40)"
else _fail "only $MATCHED declarations matched (floor 40) — the rows are reading nothing"; fi

if [ "$FAILS" -ne 0 ]; then echo "FAIL: $NAME ($FAILS)"; exit 1; fi
echo "PASS: $NAME ($MATCHED buffer declarations sized by their bound)"
