#!/bin/sh
# tests/gates/toolchain/cyrlint_overrun_and_write_length.sh — 6.7.11
#
# cyrlint warns on a bare local array's constant-offset OVERRUN and on a write whose LENGTH is not
# its literal's.
#
# THE FILED GAP (docs/development/issues/archived/2026-10-08-cyrlint-array-overrun-and-write-length-checks.md).
# cyrlint had neither of its two planned checks, and the filed repro linted `0 warnings`:
#   * a bare `var a[N]` in a fn is N BYTES (rounded up to 8), not N slots, and since 6.6.12 the
#     compiler refuses `a[i]` on it, so the overrun left is the explicit offset —
#     `var a[16]; store64(&a + 16, 3);` writes past the array with no diagnostic;
#   * `syscall(SYS_WRITE, fd, "lit", LEN)` / `sys_write(fd, "lit", LEN)` / `_aw_write(fd, "lit",
#     LEN)` with LEN != the literal's byte length truncates or over-reads, silently. The tree had
#     one live: tests/tcyr/platform/shadow_pam.tcyr:55 wrote 56 bytes of a 58-byte SKIP line (its
#     em dash counted as one character), so the line lost its `s\n`.
# The census of the new rules found two more in the tree, fixed in the same commit: the check
# driver's programs/checks/cx.cyr declared `var vals[5]` (8 bytes) and stored four slots into it,
# at +0..+24 (three stores past it), and tests/fixtures/lint_lexical/brace_rawstr.cyr wrote 31
# bytes of a 29-byte literal (in a branch that never runs).
#
# THE RULES. Per fn body, each local `var` is recorded and scoped to its block: a bare one with a
# literal N by its byte size, any other (typed, scalar, a non-literal N) as unknown, so it shadows
# an outer array of the same name. A `load8/16/32/64(&a + K)` / `store8/16/32/64(&a + K, ..)`
# with an integer-literal K (or no `+ K`) warns when K + width > size; `# lint: offset-ok` on
# the line of the call's name marks an intended offset (that trailer does NOT silence a write).
# A write's literal counts RAW BYTES — a UTF-8 em dash is 3 — and each escape as the bytes the
# lexer stores for it (`\n` 1, `\xHH` 1, `\u` its code point's UTF-8 length). ⚠ The trap the
# filing names: decoding the literal first (a `unicode_escape` round trip) made 23 false hits at
# v6.5.33.
#
# 6.7.12 (docs/development/issues/archived/2026-10-13-cyrlint-overrun-rule-literal-size-and-locals-only.md):
# N was read only as one integer literal, and only fn locals were recorded, so `var a[BUF]`,
# `var b[Sz.SMALL]`, `var c[4 + 4]` and a top-level `var g[2]` were never checked (the filed
# gap.cyr: 0 warnings). A pre-scan now records `const NAME = <literal>;` and each enum member
# with a literal value (bare and `E.X`; a name defined twice with two values is unknown), N is
# `+ - *` over those (`*` first), and a top-level bare `var g[N]` is N * 8 bytes, seen by every
# fn whose local or parameter does not shadow it. Axes K (the filed repro + sizes) and G (top
# level and shadowing); axis C's `var k[BUF]` row now warns.
#
# ORACLES. The repro and the escape program are COMPILED AND RUN: the binary's own output is the
# proof that each warned line truncates / over-reads, and that the byte count the lint uses is
# what the compiler stores. Every other expected value is typed into the fixture (`# WO` = the
# overrun warning on that line, `# WL` = the write-length one; no other line may draw either),
# with a literal count per fixture so a marker that went missing cannot pass.
#
# MUTATION PROOF (each built from a scratch copy of the tree and run through THIS gate; all RED,
# "checks failed + hard failures"; GREEN 27/27 on the real source):
#   m0  the 6.7.10 cyrlint (no rule at all: the fix reverted)                       13+0
#   m1  overrun compare off by one: `k + w < size` is inside (an exact fit warns)    6+0
#       (the tree census alone then reads 691 hits: it is not vacuous)
#   m2  overrun compare off by one: `k + w <= size + 1` (the first byte past is      1+0
#       silent — every loud shape here is exactly one byte over)
#   m3  the em dash counted as ONE character (continuation bytes not counted)         5+0
#       (61 census hits)
#   m4  `\xHH` counted as a two-character escape                                     2+0
#   m5  N not rounded up to 8 (130 census hits)                                      2+0
#   m6  no block scoping (an inner block's array outlives its `}`)                   1+0
#   m7  `# lint: offset-ok` silences a write-length warning too                      1+0
#   m8  the argument walk stops at a newline (a wrapped call is never read)          2+0
#   m9  shadow_pam.tcyr:55 back to LEN 56                                            3+0
# 6.7.12 (GREEN 37/37 on the real source; each RED):
#   m10 the 6.7.11 cyrlint                                          C, K x4, sizes, tops: 7+0
#   m11 `const` not recorded                                           C, K x3, sizes, tops: 6+0
#   m12 enum members not recorded                                             K x3, sizes: 4+0
#   m13 N read as one operand (no `+ - *`)                                    K x3, sizes: 4+0
#   m14 `+ - *` left to right (`2 + 3 * 2` read as 10)                              sizes: 1+0
#   m15 top-level arrays not recorded                                          K x3, tops: 4+0
#   m16 a top-level array sized as a local (N bytes, rounded)    C, K, tops, census 11 hits: 4+0
#   m17 parameters not recorded (a parameter no longer shadows)                      tops: 1+0
#   m18 a constant defined twice keeps its last value                               sizes: 1+0
#   m19 a top-level name declared twice keeps its first size                          tops: 1+0
set -u
G=cyrlint_overrun_and_write_length
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0

check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

[ -x "$ROOT/build/cycc" ] || { echo "FAIL: $G — build/cycc not built"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $G — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# THIS tree's cyrlint — never build/cyrlint, the store or PATH. cycc on empty stdin exits 0 and
# emits a runnable binary, so a tiny output is a failed build, not a tool.
if ! "$ROOT/build/cycc" < "$ROOT/programs/cyrlint.cyr" > "$T/cyrlint" 2> "$T/build.err"; then
    echo "FAIL: $G — programs/cyrlint.cyr does not build"; sed -n '1,5p' "$T/build.err"; exit 1
fi
if [ "$(wc -c < "$T/cyrlint")" -lt 20000 ]; then
    echo "FAIL: $G — programs/cyrlint.cyr built a $(wc -c < "$T/cyrlint")-byte binary"; exit 1
fi
chmod +x "$T/cyrlint"
L="$T/cyrlint"

# Every cyrlint run: stdout -> $T/lo, stderr (the warnings) -> $T/le, under a 10 s timeout. A
# timeout, a signal death or no "<n> warnings" trailer is a HARD failure (an HARD:… value that no
# expected value equals, logged to $T/hard). LRC = the exit code.
: > "$T/hard"
lint_run() {
    if grep -q '^TIMEOUT' "$T/hard"; then LHARD="HARD:after-timeout"; LRC=x; return 1; fi
    LRC=0
    timeout 10 "$L" "$@" > "$T/lo" 2> "$T/le" || LRC=$?
    LHARD=""
    if [ "$LRC" -eq 124 ]; then LHARD="HARD:timeout"; echo "TIMEOUT cyrlint $*" >> "$T/hard"
    elif [ "$LRC" -ge 128 ]; then LHARD="HARD:signal-rc=$LRC"; echo "CRASH rc=$LRC cyrlint $*" >> "$T/hard"
    elif ! tail -n 1 "$T/lo" | grep -Eq '^[0-9]+ warnings( total)?$'; then
        LHARD="HARD:no-trailer-rc=$LRC"; echo "NO TRAILER rc=$LRC cyrlint $*" >> "$T/hard"
    fi
    [ -z "$LHARD" ]
}
OV='(load|store)(8|16|32|64)\(&[A-Za-z_][A-Za-z0-9_]* \+ [0-9]+\) reaches bytes [0-9]+\.\.[0-9]+ of (local|top-level)'
WL='write length [0-9]+, but its literal is [0-9]+ bytes'
warned() {   # $1 file, $2 ERE of one rule's message -> the line numbers it warned, space-separated
    lint_run "$1" || { echo "$LHARD"; return; }
    grep -E "^  warn line [0-9]+: $2" "$T/le" | sed -E 's/^  warn line ([0-9]+):.*/\1/' | paste -sd' ' - || :
}
marked() {   # $1 file, $2 marker -> the line numbers that END in `# <marker>`
    grep -nE "# $2\$" "$1" | cut -d: -f1 | paste -sd' ' - || :
}
count() { if [ -z "$1" ]; then echo 0; else echo "$1" | wc -w | tr -d ' '; fi; }
# compile + run with build/cycc under a 10 s timeout; stdout -> $T/po, stderr -> $T/pe.
run_prog() {
    PRC=0
    if ! "$ROOT/build/cycc" < "$1" > "$T/prog" 2> "$T/prog.err"; then PRC=nocompile; return; fi
    chmod +x "$T/prog"
    timeout 10 "$T/prog" > "$T/po" 2> "$T/pe" || PRC=$?
}

echo "axis R — ⭐ the filed repro, verbatim (docs/development/issues/repros/)"
REPRO="$ROOT/docs/development/issues/repros/2026-10-08-cyrlint-array-overrun-and-write-length-checks.cyr"
if [ ! -f "$REPRO" ]; then
    check "the filed repro is present" yes no
else
    check "overrun warnings: lines 11 and 12 (BAD), and 13's load64(&a + 24) reads the same bytes" "11 12 13" "$(warned "$REPRO" "$OV")"
    check "write-length warnings: lines 18 and 19 (BAD)" "18 19" "$(warned "$REPRO" "$WL")"
    lint_run "$REPRO" || :
    nbad=0; nmiss=0
    for ln in $(grep -n 'BAD' "$REPRO" | grep -v '^[0-9]*:#' | cut -d: -f1); do
        nbad=$((nbad + 1))
        grep -q "^  warn line $ln: " "$T/le" || { echo "    BAD line $ln drew no warning"; nmiss=$((nmiss + 1)); }
    done
    check "every BAD line of the repro warns (4 of them)" "4 0" "$nbad $nmiss"
    check "the exact warnings: '5 warnings', rc 0 by default" "5 warnings 0" "$(tail -n 1 "$T/lo") $LRC"
    lint_run --strict "$REPRO" || :
    check "--strict exits 2" 2 "$LRC"
    lint_run --exit-with-count "$REPRO" || :
    check "--exit-with-count exits 5" 5 "$LRC"
    # the program's own output proves both write lines wrong: 5 of "hello\n", and 7 bytes where
    # "abc\n" is 4 — the line-19 write reads 3 bytes past the literal.
    run_prog "$REPRO"
    check "runtime: the repro builds and exits 0" 0 "$PRC"
    check "runtime: line 18 writes 'hello' with no newline (5 bytes)" "hello 5" "$(cat "$T/po") $(wc -c < "$T/po" | tr -d ' ')"
    check "runtime: line 19 writes 7 bytes, 3 past 'abc\\n'" "7 abc" "$(wc -c < "$T/pe" | tr -d ' ') $(head -c 3 "$T/pe")"
fi

echo "axis S — shapes: every # WO / # WL line warns, no other line"
cat > "$T/shapes.cyr" <<'EOF'
# a line ending `# WO` must draw the overrun warning, `# WL` the write-length one; no other line.
var SYS_WRITE = 1;
fn silent(h): i64 {
    var a[16];
    store64(&a, 1);
    store64(&a + 8, 2);
    load8(&a + 15);
    store32(&a + 12, 3);
    store16(&a + 0x0e, 4);
    load64(&a+8);
    var b[12];
    store64(&b + 8, 5);
    stack var c[9];
    store64(&c + 8, 6);
    store64(&a + 8 * 2, 7);
    store64(&a + i_of(16), 8);
    syscall(1, 1, "hello\n", 6);
    syscall(SYS_WRITE, 2, "abc", 3);
    sys_write(2, "x\ty\\z\"", 6);
    _aw_write(h, "\x1b[0m", 4);
    sys_write(1, "é\u{1F600}", 6);
    sys_write(1, "a — b\n", 8);
    syscall(SYS_WRITE, 1, "  SKIP: unix_chkpwd not installed — skipping auth tests\n", 58);
    sys_write(1, "abc", n_of(3));
    syscall(2, 1, "abc", 9);
    sys_write(1, buf_of(), 9);
    x.sys_write(1, "abc", 9);
    return 0;
}
fn loud(h): i64 {
    var a[16];
    store32(&a + 13, 1);  # WO
    store16(&a + 15, 2);  # WO
    load16(&a + 0x0f);  # WO
    store8(&a + 16, 3);  # WO
    load64(&a);
    var b[12];
    load64(&b + 9);  # WO
    stack var c[9];
    store64(&c + 16, 6);  # WO
    store64(  # WO
        &a + 16, 4);
    sys_write(1,  # WL
        "abc", 7);
    syscall(SYS_WRITE, 1, "  SKIP: unix_chkpwd not installed — skipping auth tests\n", 56);  # WL
    _aw_write(h, "\x1b[0m", 6);  # WL
    sys_write(1, "a — b\n", 6);  # WL
    syscall(1, 2, "hello\n", 5);  # WL
    return 0;
}
EOF
SO=$(marked "$T/shapes.cyr" WO); SL=$(marked "$T/shapes.cyr" WL)
check "  (the fixture marks 7 overrun lines and 5 write lines)" "7 5" "$(count "$SO") $(count "$SL")"
check "overrun warnings == the # WO lines" "$SO" "$(warned "$T/shapes.cyr" "$OV")"
check "write-length warnings == the # WL lines" "$SL" "$(warned "$T/shapes.cyr" "$WL")"

echo "axis C — scope: a block, a fn, a shadowing local, the two exemptions, top-level code"
# 6.7.12: `var k[BUF]` with `const BUF = 8` is 8 bytes, so `&k + 8` warns (it was unread before).
cat > "$T/scopes.cyr" <<'EOF'
# a local array is scoped to its block and its fn; a typed, scalar or unread-N local shadows it.
const BUF = 8;
var g[2];
fn scopes(): i64 {
    var a[32];
    if (1 == 1) {
        var a[8];
        store64(&a + 8, 1);  # WO
    }
    store64(&a + 24, 2);
    if (1 == 1) {
        var a: i64[8];
        store64(&a + 40, 3);
    }
    if (1 == 1) {
        var a = 0;
        store64(&a + 40, 3);
    }
    store64(&a + 32, 4);  # WO
    var k[BUF];
    store64(&k + 8, 5);  # WO
    return 0;
}
fn other(): i64 {
    store64(&g + 8, 1);
    store64(&a + 40, 1);
    return 0;
}
fn exempt(): i64 {
    var a[8];
    store64(&a + 8, 1);  # lint: offset-ok
    store64(&a + 16, 1);  #skip-lint
    sys_write(1, "abc", 9);  #skip-lint
    sys_write(1, "abc", 7);  # lint: offset-ok  # WL
    return 0;
}
impl P {
    fn m(self): i64 {
        var a[8];
        store64(&a + 8, 1);  # WO
        return 0;
    }
}
var t = 1;
if (t == 1) {
    var top[8];
    store64(&top + 8, 1);
    syscall(SYS_WRITE, 1, "top level\n", 3);  # WL
}
EOF
CO=$(marked "$T/scopes.cyr" WO); CL=$(marked "$T/scopes.cyr" WL)
check "  (the fixture marks 4 overrun lines and 2 write lines)" "4 2" "$(count "$CO") $(count "$CL")"
check "overrun warnings == the # WO lines" "$CO" "$(warned "$T/scopes.cyr" "$OV")"
check "write-length warnings == the # WL lines" "$CL" "$(warned "$T/scopes.cyr" "$WL")"

echo "axis K — 6.7.12: N as a const expression; the filed gap.cyr (issues/archived/2026-10-13-cyrlint-overrun-rule-literal-size-and-locals-only.md)"
cat > "$T/gap.cyr" <<'EOF'
const BUF = 8;
enum Sz { SMALL = 8; }
var g[2];
fn f(): i64 {
    var a[BUF];
    var b[Sz.SMALL];
    var c[4 + 4];
    store64(&a + 8, 1);
    store64(&b + 8, 2);
    store64(&c + 8, 3);
    store64(&g + 16, 4);
    return load64(&a + 8) + load64(&b + 8) + load64(&c + 8);
}
var r = f();
syscall(60, 0);
EOF
# Every access is the first byte past its array: a/b/c are 8 bytes (N = 8 in all three spellings),
# g 2 slots = 16. That is SEVEN accesses — the filing says "six warnings", which is the count of
# its a/b/c accesses (the literal spelling below draws exactly those six); g's store is the
# seventh by the filing's own reasoning.
check "the filed gap.cyr: every access warns (8 9 10 11 and line 12's three loads)" "8 9 10 11 12 12 12" "$(warned "$T/gap.cyr" "$OV")"
lint_run "$T/gap.cyr" || :
check "  …the trailer reads '7 warnings', rc 0" "7 warnings 0" "$(tail -n 1 "$T/lo") $LRC"
has_le() { if grep -qF -- "$1" "$T/le"; then echo yes; else echo no; fi; }
check "  …the const, enum and arithmetic warnings name the spelling and N" "yes yes yes" \
    "$(has_le 'of local `var a[BUF]` (N = 8), which is 8 bytes') $(has_le 'of local `var b[Sz.SMALL]` (N = 8), which is 8 bytes') $(has_le 'of local `var c[4 + 4]` (N = 8), which is 8 bytes')"
check "  …and g's names the top-level rule" yes "$(has_le 'of top-level `var g[2]`, which is 16 bytes (a bare top-level array is N i64 slots')"
sed -e 's/var a\[BUF\]/var a[8]/' -e 's/var b\[Sz.SMALL\]/var b[8]/' -e 's/var c\[4 + 4\]/var c[8]/' -e '/store64(&g + 16, 4);/d' \
    "$T/gap.cyr" > "$T/gap_lit.cyr"
check "  …the literal spelling of a/b/c (g's store dropped) draws the same six" "8 9 10 11 11 11" "$(warned "$T/gap_lit.cyr" "$OV")"
run_prog "$T/gap.cyr"
check "runtime: gap.cyr builds and exits 0 (nothing else says a word)" 0 "$PRC"

cat > "$T/sizes.cyr" <<'EOF'
# a line ending `# WO` must draw the overrun warning; no other line.
const B16 = 16;
const HX = 0x10;
const DUP = 8;
const DUP = 64;
const K2 = B16 * 2;
const NEG = -8;
enum E { S = 16; T = 8; }
enum A1 { X = 8; }
enum B1 { X = 64; }
enum C1 { P; Q; }
enum U { U1 = 8 U2 = 16 }
enum R: stack { Ok(v); Err(e); W = 8; }
fn f16(n): i64 { return n; }
fn sizes(): i64 {
    var a[B16];
    store64(&a + 8, 1);
    store64(&a + 16, 1);  # WO
    var h[HX];
    store64(&h + 8, 1);
    load8(&h + 16);  # WO
    var b[E.S];
    store64(&b + 8, 1);
    store64(&b + 9, 1);  # WO
    var bt[T];
    store64(&bt + 8, 1);  # WO
    var c[2 + 3 * 2];
    store64(&c + 8, 1);  # WO
    var d[20 - 4];
    store64(&d + 8, 1);
    store64(&d + 16, 1);  # WO
    var m[2 * B16 - E.S];
    store64(&m + 8, 1);
    store32(&m + 13, 1);  # WO
    var x1[X];
    store64(&x1 + 64, 1);
    var x2[A1.X];
    store64(&x2 + 8, 1);  # WO
    var x3[B1.X];
    store64(&x3 + 56, 1);
    var q[Q];
    store64(&q + 64, 1);
    var u[U.U2];
    store64(&u + 8, 1);
    store64(&u + 16, 1);  # WO
    var u1[U1];
    store64(&u1 + 8, 1);  # WO
    var w[R.W];
    store64(&w + 8, 1);  # WO
    var k[K2];
    store64(&k + 64, 1);
    var dp[DUP];
    store64(&dp + 64, 1);
    var ng[NEG];
    store64(&ng + 64, 1);
    var s1[sizeof(i64)];
    store64(&s1 + 64, 1);
    var s2[f16(4)];
    store64(&s2 + 64, 1);
    var s3[(4 + 4)];
    store64(&s3 + 64, 1);
    var s4[UNDEF];
    store64(&s4 + 64, 1);
    var s5[B16 + LATER];
    store64(&s5 + 16, 1);
    store64(&s5 + 24, 1);  # WO
    return 0;
}
const LATER = 8;
EOF
KO=$(marked "$T/sizes.cyr" WO)
check "  (the sizes fixture marks 12 overrun lines)" 12 "$(count "$KO")"
check "sizes: const, hex const, E.X, bare enum, * before + -, a const below, an unseparated enum, a stack enum's literal member warn exactly on # WO; in-bounds rows, a const defined twice, a non-literal const, a negative, an implicit member, two enums' bare X, sizeof / a call / parentheses / an undefined name stay silent" "$KO" "$(warned "$T/sizes.cyr" "$OV")"

echo "axis G — 6.7.12: a top-level bare array is N i64 slots, seen by every fn that does not shadow it"
cat > "$T/tops.cyr" <<'EOF'
# a line ending `# WO` must draw the overrun warning; no other line.
const TN = 2;
var g[2];
var gc[TN];
var t: i64[2];
var sc = 0;
var dd[2];
var dd[4];
var e2[f(2)];
fn uses(): i64 {
    store64(&g + 8, 1);
    store64(&g + 16, 1);  # WO
    load64(&g);
    store8(&gc + 15, 1);
    store8(&gc + 16, 1);  # WO
    store64(&t + 64, 1);
    store64(&sc + 64, 1);
    store64(&dd + 64, 1);
    store64(&e2 + 64, 1);
    store64(&late + 24, 1);
    store64(&late + 32, 1);  # WO
    store64(&blk + 64, 1);
    store64(&g + 16, 1);  # lint: offset-ok
    return 0;
}
fn shadow_local(): i64 {
    var g[4];
    store64(&g + 8, 1);  # WO
    if (1 == 1) {
        var g: i64[8];
        store64(&g + 56, 1);
    }
    store64(&g + 8, 1);  # WO
    return 0;
}
fn shadow_param(g, x: i64, gc = 3): i64 {
    store64(&g + 16, 1);
    store64(&gc + 16, 1);
    return 0;
}
fn shadow_block(): i64 {
    if (1 == 1) {
        var g = 0;
        store64(&g + 16, 1);
    }
    store64(&g + 16, 1);  # WO
    return 0;
}
fn gen<T>(g: T, p: Pair<i64, Pair<i64, i64>>, gc): i64 {
    store64(&g + 16, 1);
    store64(&gc + 16, 1);
    return 0;
}
impl P {
    fn m(self, g): i64 {
        store64(&g + 16, 1);
        store64(&gc + 16, 1);  # WO
        return 0;
    }
}
var late[4];
if (sc == 0) {
    var blk[1];
    store64(&g + 64, 1);
}
store64(&g + 64, 1);
EOF
GO=$(marked "$T/tops.cyr" WO)
check "  (the top-level fixture marks 7 overrun lines)" 7 "$(count "$GO")"
check "tops: g / gc (a const N) / an array declared below warn past N * 8; a typed or scalar global, an #ifdef pair of two sizes, an unread N, a top-level block's array, top-level code and offset-ok stay silent; a local shadow uses ITS size (8 bytes), a typed local, a block's scalar and every parameter (generic, defaulted, a method's) shadow" "$GO" "$(warned "$T/tops.cyr" "$OV")"

echo "axis E — the byte count IS what the compiler stores (raw UTF-8, \\x, \\u)"
printf 'syscall(1, 1, "a — b\\n\\x1b[0m\\u00e9\\u{1F600}", 18);\nsyscall(60, 0);\n' > "$T/esc.cyr"
printf 'a \342\200\224 b\n\033[0m\303\251\360\237\230\200' > "$T/esc.want"
run_prog "$T/esc.cyr"
check "runtime: the 18-byte write is exactly the literal" "0 same" "$PRC $(cmp -s "$T/po" "$T/esc.want" && echo same || echo differs)"
check "  …and cyrlint counts 18 too (silent)" "" "$(warned "$T/esc.cyr" "$WL")"
sed 's/, 18);/, 17);/' "$T/esc.cyr" > "$T/esc17.cyr"
check "  …17 warns" 1 "$(warned "$T/esc17.cyr" "$WL")"
sed 's/, 18);/, 12);/' "$T/esc.cyr" > "$T/esc12.cyr"
check "  …12 (every character one byte) warns" 1 "$(warned "$T/esc12.cyr" "$WL")"

echo "axis P — shadow_pam.tcyr: 58 is clean, the 6.7.10 56 warns"
PAM="$ROOT/tests/tcyr/platform/shadow_pam.tcyr"
check "  (premise: the SKIP line is 58 bytes)" 58 "$(printf '  SKIP: unix_chkpwd not installed \342\200\224 skipping auth tests\n' | wc -c | tr -d ' ')"
check "the real file draws neither warning" "|" "$(warned "$PAM" "$OV")|$(warned "$PAM" "$WL")"
sed '55s/skipping auth tests\\n", 58);/skipping auth tests\\n", 56);/' "$PAM" > "$T/pam56.tcyr"
check "  (premise: the copy differs on line 55 only)" "55c55" "$(diff "$PAM" "$T/pam56.tcyr" | head -1)"
check "its 6.7.10 line 55 (LEN 56) warns" 55 "$(warned "$T/pam56.tcyr" "$WL")"

echo "axis T — tree census: neither rule fires over src cbt programs lib tests"
find src cbt programs lib tests -type f \( -name '*.cyr' -o -name '*.tcyr' -o -name '*.bcyr' -o -name '*.fcyr' \) \
    | sort > "$T/census.list"
nfiles=$(wc -l < "$T/census.list" | tr -d ' ')
check "  (floor: >= 900 source files)" yes "$([ "$nfiles" -ge 900 ] && echo yes || echo no)"
# cyrlint reads at most 1028 KB, so a larger file (lib/mabda.cyr, lib/sigil.cyr — two folds) is
# linted in pieces cut at a column-0 `fn` / `pub fn` line, where no local, call or string is open.
mkdir -p "$T/pieces"
: > "$T/census.files"
while IFS= read -r f; do
    if [ "$(wc -c < "$f")" -lt 1000000 ]; then echo "$f" >> "$T/census.files"; continue; fi
    b=$(echo "$f" | tr '/' '_')
    awk -v out="$T/pieces/$b" '
        BEGIN { n = 0; sz = 0; fn = out "." n ".cyr" }
        sz > 700000 && /^(pub )?fn / { close(fn); n++; sz = 0; fn = out "." n ".cyr" }
        { print > fn; sz += length($0) + 1 }' "$f"
    ls "$T/pieces/$b".*.cyr >> "$T/census.files"
    echo "    (linted in $(ls "$T/pieces/$b".*.cyr | wc -l | tr -d ' ') pieces: $f)"
done < "$T/census.list"
: > "$T/census.out"; : > "$T/census.err"; crash=0
while IFS= read -r f; do
    rc=0; timeout 10 "$L" "$f" >> "$T/census.out" 2>> "$T/census.err" || rc=$?
    if [ "$rc" -ne 0 ]; then echo "    cyrlint rc=$rc on $f"; crash=$((crash + 1)); fi
done < "$T/census.files"
check "cyrlint finished every file (rc 0, none refused)" 0 "$crash"
check "  …and linted each one" "$(wc -l < "$T/census.files" | tr -d ' ')" "$(grep -c '^=== cyrlint: ' "$T/census.out")"
hits=$(grep -cE "^  warn line [0-9]+: ($OV|$WL)" "$T/census.err" || :)
if [ "$hits" -ne 0 ]; then
    awk '/^=== cyrlint: /{f=$3} /reaches bytes|write length/{print "    " f ": " $0}' "$T/census.out" "$T/census.err" | head -20
    grep -E "^  warn line [0-9]+: ($OV|$WL)" "$T/census.err" | head -20 | sed 's/^/    /'
fi
check "unannotated hits of either rule" 0 "$hits"
echo "    ($(cat "$T/census.list" | { xargs grep -hE '(load|store)(8|16|32|64)[^#]*# lint: offset-ok' || :; } | wc -l | tr -d ' ') access(es) carry a '# lint: offset-ok' trailer)"

echo ""
nhard=$(wc -l < "$T/hard" | tr -d ' ')
if [ "$nhard" -gt 0 ]; then
    echo "  hard failures (cyrlint crashed, hung or printed no trailer):"
    sed 's/^/    /' "$T/hard"
fi
if [ "$fails" -gt 0 ] || [ "$nhard" -gt 0 ]; then
    echo "FAIL: $G — $fails of $checks checks failed, $nhard hard failures"
    exit 1
fi
echo "PASS: $G — $checks checks"
exit 0
