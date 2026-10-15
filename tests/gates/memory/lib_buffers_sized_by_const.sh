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
# 6.7.9 (issues/2026-10-08-lib-literal-bounds-and-writable-public-bounds.md) closed what 6.7.6 left:
# the agnos env blob's 1024 (now `_SPAWN_ENV_MAX`, with the public `SPAWN_ENV_MAX` twin), regex's
# two split tables and their guards (`_RE_MAX_SPLITS`), two top-level arrays declared 8x their
# size (a bare top-level `var x[N]` is N SLOTS: `_fl_heads[72]` was 576 B for 9 heads,
# `_dynlib_registry[256]` 2,048 B for 256 B), the async kill-task ctx words hard-coded after the
# 40-byte kill state (now named from `_PROC_KILL_STATE`), and — axis 6 — the 6.7.6 split's own
# hazard: the public var a const twin initialises still DROVE loops, caps, strides and allocations
# over the const-sized storage (`TLOCAL_MAX_SLOTS`, `TLS_REG_MAX`, `SPAWN_ARGV_MAX`, `KEV_SIZE`),
# so a program that wrote the var ran them off the end. The literal swaps are byte-identical on
# x86, aarch64, x86-Mach-O, arm64-Mach-O, PE, agnos and cx (100 modules / tests per target).
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
#   6  (6.7.9) a public var with a const twin is never READ in cyrius's own lib/ — every loop,
#      cap, stride and allocation reads the const; the var only tells a caller the value. The
#      twin set is DERIVED (every `var X = _X;`). 6.7.12: the TLS stack's twins are held too —
#      their exemption ended with their fix (issues/2026-10-11-tls-public-bound-vars-drive-const-
#      storage.md: every read in lib/tls_native*.cyr and lib/tls.cyr reads `_X`)
#   7  (6.7.9) no literal left beside a named bound: no literal-sized agnos env blob, no literal
#      ctx offset at or past the kill state in the async kill tasks
#
# MUTATION LEDGER (6.7.6, each run in a scratch copy of the tree, each RED):
#   log.cyr one `var buf[_LOG_LINE_MAX + 1]` back to `var buf[512]`          -> axis 1
#   tls_native_hs13.cyr ptbuf back to `[16385]`                               -> axis 1
#   tls_native.cyr `var TLS_RECORD_MAX_PLAINTEXT = 16384;`                    -> axis 3
#   math.cyr `const _F64P_DEC_CAP` back to `var`                              -> axis 2
#   process_agnos.cyr one argv blob back to `var b[1024]`                     -> axis 1
#   keysched's "(array size must be a literal)" comment restored              -> axis 4
# MUTATION LEDGER (6.7.9, each in a scratch copy, each RED naming its site):
#   thread_local.cyr thread_local_alloc back to `s >= TLOCAL_MAX_SLOTS`        -> axis 6
#   thread_agnos.cyr one save loop back to `i < TLOCAL_MAX_SLOTS`              -> axis 6
#   thread_macos.cyr the worker block back to `alloc(TLOCAL_MAX_SLOTS * 8)`    -> axis 6
#   thread_local.cyr one registry scan back to `i < TLS_REG_MAX`               -> axis 6
#   async_agnos.cyr the argv cap back to SPAWN_ARGV_MAX                        -> axis 6
#   async_macos.cyr the kevent stride back to `ei * KEV_SIZE`                  -> axis 6
#   a new `var FOO_MAX = _FOO_MAX;` read in a loop                             -> axis 6 (derived)
#   regression_agnos.cyr one env blob back to `var e[1024]`                    -> axes 1 + 7
#   regex.cyr the second guard back to `sn2 >= 64`                             -> axis 1
#   freelist.cyr back to `var _fl_heads[72];`                                  -> axis 1
#   dynlib.cyr the cap back to `>= 16`                                         -> axis 1
#   async.cyr `_proc_kill_finish(ctx, ctx + 40)`                               -> axis 7
#   async_macos.cyr `alloc_via(load64(rt + 32), 72)`                           -> axes 1 + 7
#   syscalls_x86_64_agnos.cyr sys_spawn_argv's check back to `> SPAWN_ARGV_MAX`  -> axis 6
# MUTATION LEDGER (6.7.12, the TLS twins, each in the tree, each RED naming its site):
#   tls_native_hs12.cyr one seed copy back to `memcpy(&seed, client_random, TLS12_RANDOM_LEN)` -> axis 6
#   tls_native_lowlevel.cyr the clone copy back to `TLS_SHA384_CTX_LEN`                        -> axis 6
#   tls.cyr tls_write's clamp back to `TLS_RECORD_MAX_PLAINTEXT`                                -> axis 6
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
# 6.7.9
need lib/process_agnos.cyr 2 'var e\[_SPAWN_ENV_MAX\];' "agnos env blobs"
need lib/regression_agnos.cyr 3 'var e\[_SPAWN_ENV_MAX\];' "agnos regression env blobs"
need lib/async_agnos.cyr 1 'var e\[_SPAWN_ENV_MAX\];' "agnos async env blob"
need lib/process_agnos.cyr 1 '_agp_put_elem\(b, off, _SPAWN_ENV_MAX, ' "the env vec is capped at the blob it fills"
need lib/regression_agnos.cyr 1 '_agnos_blob_ptrs\(e, 0, _SPAWN_ENV_MAX, envp, 0, 1\)' "the regression envp is capped at its blob"
need lib/async_agnos.cyr 1 '_agnos_blob_ptrs\(&e, 0, _SPAWN_ENV_MAX, envp, 0, 1\)' "the async envp is capped at its blob"
need lib/regex.cyr 2 'var splits2?: i64\[_RE_MAX_SPLITS\];' "the {n,m} split tables"
need lib/regex.cyr 2 'if \(sn2? >= _RE_MAX_SPLITS\)' "the {n,m} guards refuse at the size they index"
need lib/freelist.cyr 1 '^var _fl_heads: i64\[_FL_NCLASSES\];' "one head per size class (was [72] = 72 slots)"
need lib/freelist.cyr 1 'while \(i < _FL_NCLASSES\)' "the head reset walks the classes it sized"
need lib/dynlib.cyr 1 '^var _dynlib_registry: i64\[_DYNLIB_MAX \* 2\];' "the loaded-library registry, 2 words an entry (was [256] = 256 slots)"
need lib/dynlib.cyr 1 '_dynlib_reg_count >= _DYNLIB_MAX' "the registry refuses at the size it holds"
need lib/async.cyr 7 '^const _AK_[A-Z]+ = _PROC_KILL_STATE( \+ [0-9]+)?;' "the epoll kill task's ctx words, named from the kill state's size"
need lib/async.cyr 1 'alloc_via\(a, _AK_SIZE\)' "the epoll kill ctx is allocated at the size it names"
need lib/async_macos.cyr 4 '^const _AKM_[A-Z]+ = _PROC_KILL_STATE( \+ [0-9]+)?;' "the kqueue kill task's ctx words, named from the kill state's size"
need lib/async_macos.cyr 1 'alloc_via\(load64\(rt \+ 32\), _AKM_SIZE\)' "the kqueue kill ctx is allocated at the size it names"

echo "axis 2 — each private bound is a const:"
for row in "lib/log.cyr:_LOG_LINE_MAX" "lib/math.cyr:_F64P_DEC_CAP" "lib/process.cyr:_PROC_KILL_STATE" \
           "lib/thread_win.cyr:_chan_wp_cap" "lib/process_win.cyr:_WIN_JOB_SLOTS" "lib/async_macos.cyr:_KEV_BATCH" \
           "lib/tls_native_hs12.cyr:_TLS12_SEED_LEN" "lib/regex.cyr:_RE_MAX_SPLITS" "lib/freelist.cyr:_FL_NCLASSES" \
           "lib/dynlib.cyr:_DYNLIB_MAX"; do
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
           "lib/thread_local.cyr:TLS_REG_MAX" "lib/syscalls_x86_64_agnos.cyr:SPAWN_ARGV_MAX" \
           "lib/syscalls_x86_64_agnos.cyr:SPAWN_ENV_MAX" "lib/thread_local.cyr:TLOCAL_MAX_SLOTS"; do
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

echo "axis 6 — a public bound's var is never read in cyrius's own lib/ (the const bounds everything):"
# 6.7.12: no exemption. The TLS stack read its twins at ~190 sites until then (TLS12_RANDOM_LEN as the
# PRF seed's memcpy length over the const-sized seed — a raised var smashed the stack); every read is
# the const now, and TLS_RECORD_MAX_PLAINTEXT is the protocol constant (the user's decision D17,
# 2026-10-15). CHANGELOG [6.7.12]
# "file twin" for every `var X = _X;` in cyrius's own lib/
TWINS=$(grep -oE '^var [A-Za-z0-9_]+ *= *_[A-Za-z0-9_]+;' $OWN | sed -E 's/^([^:]+):var ([A-Za-z0-9_]+) *= *_([A-Za-z0-9_]+);/\1 \2 \3/' | awk '$2 == $3 { print $1 ":" $2 }' | sort -u)
NTW=0; NCHK=0
for row in $TWINS; do
    f=${row%%:*}; v=${row#*:}
    NTW=$((NTW + 1))
    # every line naming the var, comments stripped, that is not its own `var X = _X;` declaration
    READS=$(grep -nwE "$v" $OWN | sed -E 's/^([^:]+:[0-9]+:)([^#]*).*/\1\2/' | grep -wE "$v" | grep -vE "^[^:]+:[0-9]+:var $v *= *_$v;" || true)
    NCHK=$((NCHK + 1))
    if [ -z "$READS" ]; then _ok "$v: read nowhere in lib/ but its declaration"; continue; fi
    _fail "$v: read inside lib/ — a write to the public var then drives storage the const sized; read _$v: $(echo "$READS" | tr '\n' ' ')"
done
if [ "$NTW" -ge 14 ] && [ "$NCHK" -eq "$NTW" ]; then _ok "$NTW twins derived, all $NCHK held to the rule (floor 14)"
else _fail "only $NTW twins derived / $NCHK held to the rule (floor 14, every twin held) — the derivation is reading nothing"; fi

echo "axis 7 — no literal left beside a named bound:"
LITENV=$(grep -nE 'var e\[[0-9]+\];|_blob_ptrs\([^,]+, 0, [0-9]+, envp|_put_elem\(b, off, [0-9]+, ' lib/process_agnos.cyr lib/regression_agnos.cyr lib/async_agnos.cyr || true)
if [ -z "$LITENV" ]; then _ok "no literal-sized or literal-capped agnos env blob"
else _fail "a literal env bound is back — size and cap it by _SPAWN_ENV_MAX: $LITENV"; fi
for f in lib/async.cyr lib/async_macos.cyr; do
    KB=$(awk '/^fn _async_kill_task\(|^fn _async_kill_close\(|^fn _async_process_end\(/ { p = 1 } p { print FILENAME ":" FNR ": " $0 } p && /^}/ { p = 0 }' "$f")
    [ -n "$KB" ] || { _fail "$f: no kill-task fns found — the gate is reading nothing"; continue; }
    LIT=$(printf '%s\n' "$KB" | sed -E 's/#.*//' | grep -E '[^p]ctx \+ (4[0-9]|[5-9][0-9]|[1-9][0-9]{2,})\b|alloc_via\([^)]*\), (72|88)\)|alloc_via\(a, (72|88)\)' || true)
    if [ -z "$LIT" ]; then _ok "$f: no literal ctx offset at or past the kill state"
    else _fail "$f: a literal offset past the kill state is back — name it from _PROC_KILL_STATE: $LIT"; fi
done

if [ "$FAILS" -ne 0 ]; then echo "FAIL: $NAME ($FAILS)"; exit 1; fi
echo "PASS: $NAME ($MATCHED buffer declarations sized by their bound)"
