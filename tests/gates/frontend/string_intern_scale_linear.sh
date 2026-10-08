#!/bin/sh
# check: serial — a timing/scaling measurement; the parallel check.sh runs it alone, after its pool (6.7.0)
# string_intern_scale_linear.sh — 6.6.19 B0b. String-literal interning is LINEAR in the literal
# count, and a big literal early in the pool costs every later literal nothing.
#
# THE DEFECT (measured at 6.6.18/6.6.19-open). LEX interned each new literal by scanning the WHOLE
# string pool, byte by byte, so N literals cost N x pool bytes:
#
#     3,000 small literals              573 ms      (3,000 integer globals: 18 ms)
#     9,000 small literals            4,983 ms
#     1.9 MB literal AFTER  3,000 small   919 ms
#     1.9 MB literal BEFORE 3,000 small 11,412 ms   (every small literal scanned the 1.9 MB)
#
# The second shape is what `[embed]` produces (cbt puts the embed in the prelude, ahead of every
# other literal). Fixed with an alloc'd FNV-1a index of the pool's NUL-delimited segments
# (src/frontend/lex.cyr, `_lex_intern*` / `_lex_ix_*`), synced lazily; a literal holding a NUL
# keeps the 6.6.15 scan verbatim. The output is byte-identical (the first segment equal to a
# NUL-free literal is the scan's first match) — proven by the self-host fixpoint and an old-vs-new
# compile of every tests/tcyr file, not by this gate.
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND (the globals_scale_linear.sh rule): best of
# 3 each, and timings are DATA — no `set -e`.
#   [count]  N vs 2N distinct small literals: 2N must cost under 3x N (linear ~2x, quadratic ~4x).
#   [blob]   a 1.9 MB literal (with NULs) before 3,000 small literals vs after them: before must
#            cost under 2x after (the old scan: ~12x).
# SEMANTIC ROWS (green on the old compiler too — the index must not change WHICH bytes a literal
# shares): identical literals share an address; `"b"` after `"a\0b"` is X+2 (segments that start
# after a NUL are indexed); the 6.6.15 B0a repro (`"a"`, `"a\0a"`, `"zzzz"`: X+2 reads 'a'); a
# `#deprecated` message wound out of the pool does not disturb sharing; and both blob programs
# exit 42 (the blob's FNV-1a round-trips and the small literals sum right).
#
# MUTATION PROOF (6.6.19): `_lex_intern` routed every literal to `_lex_intern_scan` (the old
# scan) -> RED on both ratio rows: [count] 3.7x (728 ms -> 2746 ms), [blob] 11.6x (829 ms ->
# 9647 ms). The 6.6.19-open compiler: [count] 3.8x (855 -> 3255 ms), [blob] 13.8x (817 ->
# 11281 ms). The tree: [count] 1.8x (81 -> 153 ms), [blob] 1.0x (380 -> 388 ms). Every semantic
# row is green on all three. (N = 4000 and ~50-byte literals keep the quadratic's ratio above
# 3.5x; at 3k short literals the fixed cost pulls it toward 3.6x.)
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: string_intern_scale_linear: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: string_intern_scale_linear: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
N=4000          # [count] row: N vs 2N
NS=3000         # [blob] row: small literals beside the blob
BL=1900000      # [blob] row: blob bytes

# Small literals, 1000 per fn: c<k>() sums the first byte ('q' = 113) of each. `sum` names the
# call that adds them all.
small() {  # small n
    awk -v n="$1" 'BEGIN{
        nf = int((n + 999) / 1000)
        for (k = 0; k < nf; k++) {
            printf "fn c%d(): i64 {\n    var s = 0;\n", k
            for (i = k * 1000; i < n && i < (k + 1) * 1000; i++) printf "    s = s + load8(\"q%d_this_literal_is_interned_by_its_content_pad\");\n", i
            print "    return s;\n}"
        }
        printf "fn sum(): i64 { return 0"
        for (k = 0; k < nf; k++) printf " + c%d()", k
        print "; }"
    }'
}
# The blob: byte i = (i*131 + (i/251)*17 + 7) & 255 (NULs included), printable bytes raw and the
# rest as \xHH escapes.
blob() {  # blob n
    LC_ALL=C awk -v n="$1" 'BEGIN{
        for (c = 0; c < 256; c++) {
            if (c >= 32 && c <= 126 && c != 34 && c != 92) e[c] = sprintf("%c", c)
            else e[c] = sprintf("\\x%02x", c)
        }
        printf "fn the_blob(): i64 { return \""
        for (i = 0; i < n; i++) printf "%s", e[(i * 131 + int(i / 251) * 17 + 7) % 256]
        print "\"; }"
    }'
}
verify() {  # verify n_small blob_len — exit 42 iff the blob round-trips and the sum is right
    cat <<EOF
fn fnv_got(p, n): i64 {
    var h = 0xcbf29ce484222325;
    var i = 0;
    while (i < n) { h = h ^ load8(p + i); h = h * 0x100000001b3; i = i + 1; }
    return h;
}
fn fnv_want(n): i64 {
    var h = 0xcbf29ce484222325;
    var i = 0;
    while (i < n) { h = h ^ ((i * 131 + (i / 251) * 17 + 7) & 255); h = h * 0x100000001b3; i = i + 1; }
    return h;
}
var ok = 1;
if (fnv_got(the_blob(), $2) != fnv_want($2)) { ok = 0; }
if (sum() != 113 * $1) { ok = 0; }
if (ok == 1) { syscall(60, 42); }
syscall(60, 1);
EOF
}
best() {  # best-of-3 wall ms for compiling $1 (-1 if any compile fails)
    b=99999999
    for _ in 1 2 3; do
        s=$(date +%s%N)
        "$CC" < "$1" > "$1.bin" 2> "$1.err" || { echo -1; return; }
        e=$(( ($(date +%s%N) - s) / 1000000 ))
        [ "$e" -lt "$b" ] && b=$e
    done
    echo "$b"
}
runs42() {  # runs42 file.bin — 0 iff the program exits 42
    chmod +x "$1"
    rc=0; "$1" || rc=$?
    [ "$rc" = 42 ]
}

NFAIL=0
ratio_row() {  # ratio_row name fileA fileB limit10 what
    T1=$(best "$2"); T2=$(best "$3")
    if [ "$T1" -lt 0 ] || [ "$T2" -lt 0 ]; then
        echo "  FAIL: [$1] the compile failed: $(grep -h -m1 -i error "$2.err" "$3.err" 2>/dev/null | head -1)"
        NFAIL=$((NFAIL + 1)); return
    fi
    for b in "$2.bin" "$3.bin"; do
        if ! runs42 "$b"; then
            echo "  FAIL: [$1] $(basename "$b") exited $rc, want 42 — the fast path is not the RIGHT path"
            NFAIL=$((NFAIL + 1)); return
        fi
    done
    [ "$T1" -lt 1 ] && T1=1
    R10=$(( T2 * 10 / T1 ))
    if [ "$R10" -gt "$4" ]; then
        echo "  FAIL: [$1] $5 costs ${R10}/10x (${T1}ms -> ${T2}ms, limit $(($4 / 10)).$(($4 % 10))x) — interning is scanning the whole string pool again"
        NFAIL=$((NFAIL + 1))
    else
        echo "  ok: [$1] $5: ${T1}ms -> ${T2}ms — ratio ${R10}/10 (limit $(($4 / 10)).$(($4 % 10)))"
    fi
}

# [count] N vs 2N small literals
for n in "$N" $((N * 2)); do
    { small "$n"; printf 'if (sum() == 113 * %d) { syscall(60, 42); }\nsyscall(60, 1);\n' "$n"; } > "$D/count.$n.cyr"
done
ratio_row count "$D/count.$N.cyr" "$D/count.$((N * 2)).cyr" 30 "${N} -> $((N * 2)) literals"

# [blob] the 1.9 MB literal after vs before NS small literals (the 2nd file is the costly order)
blob "$BL" > "$D/blob.part"
small "$NS" > "$D/small.part"
verify "$NS" "$BL" > "$D/verify.part"
cat "$D/small.part" "$D/blob.part" "$D/verify.part" > "$D/blob.after.cyr"
cat "$D/blob.part" "$D/small.part" "$D/verify.part" > "$D/blob.before.cyr"
ratio_row blob "$D/blob.after.cyr" "$D/blob.before.cyr" 20 "${BL}-byte literal after -> before ${NS} literals"

# Semantic rows: each program exits 42.
sem() {  # sem name — program on stdin
    cat > "$D/sem.$1.cyr"
    rc=0; "$CC" < "$D/sem.$1.cyr" > "$D/sem.$1.bin" 2> "$D/sem.$1.err" || rc=$?
    if [ "$rc" != 0 ]; then
        echo "  FAIL: [$1] the compile failed (rc $rc): $(head -1 "$D/sem.$1.err")"
        NFAIL=$((NFAIL + 1)); return
    fi
    if runs42 "$D/sem.$1.bin"; then echo "  ok: [$1]"
    else echo "  FAIL: [$1] exited $rc, want 42"; NFAIL=$((NFAIL + 1)); fi
}
sem same_address <<'EOF'
fn a(): i64 { return "~same~"; }
fn b(): i64 { return "~same~"; }
fn c(): i64 { return "~other~"; }
if (a() == b()) { if (a() != c()) { syscall(60, 42); } }
syscall(60, 1);
EOF
sem after_embedded_nul <<'EOF'
var X = "a\0b";
var Y = "b";
if (Y == X + 2) { syscall(60, 42); }
syscall(60, 1);
EOF
sem b0a_repro <<'EOF'
var A = "a"; var X = "a\0a"; var B = "zzzz";
if (load8(X + 2) == 97) { if (load8(X) == 97) { if (load8(B) == 122) { syscall(60, 42); } } }
syscall(60, 1);
EOF
sem deprecated_message_wound_back <<'EOF'
fn a(): i64 { return "~p~"; }
#deprecated("~q~")
fn old_f(): i64 { return 0; }
fn b(): i64 { return "~q~"; }
fn c(): i64 { return "~p~"; }
fn d(): i64 { return "~q~"; }
if (a() == c()) { if (b() == d()) { if (load8(b() + 1) == 113) { if (b() != a()) { syscall(60, 42); } } } }
syscall(60, 1);
EOF

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: string_intern_scale_linear: $NFAIL rows"
    exit 1
fi
echo "PASS string_intern_scale_linear (interning cost linear in the literal count; a big early literal costs later literals nothing; sharing unchanged)"
exit 0
