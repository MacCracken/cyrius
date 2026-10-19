#!/bin/sh
# tests/gates/diagnostics/in_sync_refusal_next_statement.sh — 6.7.16
#
# A REFUSAL MADE IN SYNC — the statement then parses on to its own `;` — CLEARS ONLY ITS LATCH: THE NEXT
# STATEMENT IS PARSED, ITS OWN ERROR REPORTED.
#
# THE DEFECT (measured 6.7.15, x86_64; the frontend, every target). The subscript and `*p` refusals latch the panic
# flag and parse the brackets / the operand on, so the statement ends at its own `;`. PARSE_STMT then saw the latch
# and resynced with `_sync_skip`, which — the cursor already past the `;` — consumed the NEXT statement to its `;`
# (unless it began with a statement keyword): `y = pa[0]; y = zz9;` through a `*u128` reported only the subscript,
# never "undefined variable 'zz9'"; `*pa = 1;` after `y = *pa;` was not reported at all. The same for an untyped
# `n[0]`, `g()[0]` (a call not returning `*T`), a field that is not a `*T`, `&a[i]`, `a[i][j]` and an undefined base
# `qq[0]`. Only 6.7.11's pair refusal (`_pair_sync_ti`) and 6.7.14's const ones recorded that they were in sync.
# (issues/2026-10-18-in-sync-refusal-in-assignment-swallows-next-statement.md)
#
# THE FIX. `_refuse_in_sync` (src/frontend/parse.cyr) records the mark `_stmt_resync` reads, called just before each
# such refusal latches: `_arr_sub_addr`'s undefined-base and u128 arms, `_sub_err`, `_psub_err` and `_deref_u128_err`
# (src/frontend/parse_expr.cyr). `_stmt_resync` is unchanged: it clears only the latch when the statement ended at
# its own `;` / `}` past the mark, and still skips to the next recovery point when it did not.
#
#   F   the filing's programs verbatim: F1 latch4 (three errors, lines 5 6 7), F2 latch5 (three, lines 5 6 7)
#   B   the class beyond u128, each followed by `y = zz9;` — two errors: B1 an untyped `n[0]`, B2 `g()[0]`, B3 an
#       undefined `qq[0]`, B4 a non-`*T` field `h.f[0]`, B5 `&a[0]`, B6 `a[0][1]`, B7 a `var` initializer, B8 a
#       classic-for step `*pa = 1`, B9 a generic fn at two instances (once each), B10 top level after the first
#       statement (three), B11 three refusals in a row (three), B12 B11 under --syntax-only (what `cyrius lint` runs)
#   M   a refusal that leaves the statement mid-way still resyncs to its `;`: M1 `y = pa[0 qq1 qq2;` then `y = 1;` —
#       one error, nothing about qq1 / qq2; M2 the same then `y = zz9;` — two
#   P   control: 6.7.11's pair refusal `y = f();` then `y = zz9;` — two, as before
# Every row on the x86_64, aarch64, cx, PE and Mach-O compilers built from this tree: the exact error lines, rc 1,
# no binary.
#
# MUTATION LEDGER (2026-10-19; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run from
# that copy with CYCC= it, so every leg's compiler carries the mutant):
#   `_refuse_in_sync` returns at once (6.7.15's behaviour)  -> RED 70 of 85: F1 F2 B1-B12 on every leg (the next
#                                                                statement's error missing); M1 M2 P green
#   `_sub_err` without its `_refuse_in_sync`                -> RED B1 (5 legs)
#   `_psub_err` without its `_refuse_in_sync`               -> RED B2 B4 B5 B6 (20)
#   `_arr_sub_addr`'s u128 arm without it                   -> RED F1 B7 B9 B10 B11 B12 (30)
#   `_arr_sub_addr`'s undefined arm without it              -> RED B3 (5)
#   `_deref_u128_err` without its `_refuse_in_sync`         -> RED F2 B8 (10)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=in_sync_refusal_next_statement
[ -x "$CC" ] || { echo "SKIP: $G: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: $G: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

# The aarch64 and cx compilers, built from this tree's src (the frontend is shared; a refusal needs no run).
A64=""; CXCC=""
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"; A64="$D/cc_a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ]; then
    chmod +x "$D/cc_cx"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr did not build"; fi
LEGS="x86 pe macho"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"

# comp <leg> <src> <out> [cc-arg]: compile; rc in CRC
comp() {
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$A64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$CXCC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# row <id> <what> <source> <want-lines> [cc-arg]: refused on every leg (rc != 0, no binary), its `error` /
# `warning` lines exactly <want-lines>
row() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp "$leg" "$D/$1.cyr" "$o" "${5:-}"
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0 — want the refusal"
        elif ! cmp -s "$o.got" "$D/$1.want"; then
            bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 $leg: $2: refused, but a binary was written"
        else ok "$1 $leg: $2"; fi
    done
}

U="': a u128 element does not fit one register - use load64/store64 on its two halves"
Z="undefined variable 'zz9' (missing include or enum?)"
PA='fn main(): i64 {
    var a: u128 = 0;
    var pa: *u128 = &a;
    var y = 0;
'
TAIL='    return 0;
}
syscall(60, main());
'

row F1 "latch4 verbatim: y = pa[0]; y = zz9; pa[0] = 1;" "${PA}    y = pa[0];
    y = zz9;
    pa[0] = 1;
${TAIL}" "error:<source>:5:11: cannot subscript 'pa$U
error:<source>:6:12: $Z
error:<source>:7:7: cannot subscript 'pa$U"

row F2 "latch5 verbatim: y = *pa; *pa = 1; y = *pa;" "${PA}    y = *pa;
    *pa = 1;
    y = *pa;
${TAIL}" "error:<source>:5:9: cannot dereference 'pa$U
error:<source>:6:5: cannot dereference 'pa$U
error:<source>:7:9: cannot dereference 'pa$U"

row B1 "an untyped n[0]" 'fn main(): i64 {
    var n = 0;
    var y = 0;
    y = n[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:10: cannot subscript 'n': it is not a typed array, a *T or a slice local - declare \`var a: T[N]\` or \`p: *T\` (T an integer, f64, f32 or bool), or load / store at an explicit byte offset
error:<source>:5:12: $Z"

row B2 "g()[0], g not returning *T" 'fn g(): i64 { return 0; }
fn main(): i64 {
    var y = 0;
    y = g()[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:12: cannot subscript the result of 'g': it does not return a *T
error:<source>:5:12: $Z"

row B3 "an undefined base qq[0]" 'fn main(): i64 {
    var y = 0;
    y = qq[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:3:11: undefined variable 'qq' (missing include or enum?)
error:<source>:4:12: $Z"

row B4 "a field that is not a *T" 'struct H { f; }
fn main(): i64 {
    var h = H { 0 };
    var y = 0;
    y = h.f[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:5:12: cannot subscript field 'f': it is not a *T field
error:<source>:6:12: $Z"

row B5 "&a[0]" 'fn main(): i64 {
    var a: i64[4];
    var y = 0;
    y = &a[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:11: &a[i] is not supported - write &a + i * sizeof(T) (or p + i)
error:<source>:5:12: $Z"

row B6 "a[0][1]" 'fn main(): i64 {
    var a: i64[4];
    var y = 0;
    y = a[0][1];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:13: a subscript's result is an element, not an array - a second [..] is not supported
error:<source>:5:12: $Z"

row B7 "a var initializer var z = pa[0];" "${PA}    var z = pa[0];
    y = zz9;
${TAIL}" "error:<source>:5:15: cannot subscript 'pa$U
error:<source>:6:12: $Z"

row B8 "a classic-for step *pa = 1" "${PA}    for (var i = 0; i < 2; *pa = 1) { y = 1; }
    y = zz9;
${TAIL}" "error:<source>:5:28: cannot dereference 'pa$U
error:<source>:6:12: $Z"

row B9 "a generic fn at two instances" 'fn gg<T>(x: T): i64 {
    var a: u128 = 0;
    var pa: *u128 = &a;
    var y = 0;
    y = pa[0];
    y = zz9;
    return 0;
}
fn main(): i64 { gg<i64>(1); gg<i32>(2); return 0; }
syscall(60, main());
' "error:<source>:5:11: cannot subscript 'pa$U
error:<source>:6:12: $Z"

row B10 "top level, after the first statement" 'var a: u128 = 0;
var pa: *u128 = &a;
var y = 0;
y = 1;
y = pa[0];
y = zz9;
pa[0] = 1;
syscall(60, 0);
' "error:<source>:5:7: cannot subscript 'pa$U
error:<source>:6:8: $Z
error:<source>:7:3: cannot subscript 'pa$U"

B11="${PA}    y = pa[0];
    pa[0] = 1;
    y = pa[0];
${TAIL}"
B11W="error:<source>:5:11: cannot subscript 'pa$U
error:<source>:6:7: cannot subscript 'pa$U
error:<source>:7:11: cannot subscript 'pa$U"
row B11 "three refusals in a row" "$B11" "$B11W"
row B12 "three in a row, --syntax-only" "$B11" "$B11W" --syntax-only

row M1 "mid-statement: y = pa[0 qq1 qq2; then y = 1;" "${PA}    y = pa[0 qq1 qq2;
    y = 1;
${TAIL}" "error:<source>:5:11: cannot subscript 'pa$U"

row M2 "mid-statement, then y = zz9;" "${PA}    y = pa[0 qq1 qq2;
    y = zz9;
${TAIL}" "error:<source>:5:11: cannot subscript 'pa$U
error:<source>:6:12: $Z"

row P "control: the pair refusal y = f(); then y = zz9;" 'enum R: stack { ROk(v); RErr(e); }
fn f() { return ROk(7); }
fn main(): i64 {
    var y = 0;
    y = f();
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:5:9: a \`: stack\` enum returns two values — bind both: \`var tag, val = f();\`
error:<source>:6:12: $Z"

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
