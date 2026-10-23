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
# (issues/archived/2026-10-18-in-sync-refusal-in-assignment-swallows-next-statement.md)
#
# THE FIX. `_refuse_in_sync` (src/frontend/parse/parse.cyr) records the mark `_stmt_resync` reads, called just before each
# such refusal latches: `_arr_sub_addr`'s undefined-base and u128 arms, `_sub_err`, `_psub_err` and `_deref_u128_err`
# (src/frontend/parse/expr/subscript.cyr, expr/deref.cyr). `_stmt_resync` is unchanged: it clears only the latch when the statement ended at
# its own `;` / `}` past the mark, and still skips to the next recovery point when it did not.
#
#   F   the filing's programs verbatim: F1 latch4 (three errors, lines 5 6 7), F2 latch5 (three, lines 5 6 7)
#   B   the class beyond u128, each followed by `y = zz9;` — two errors: B1 an untyped `n[0]`, B2 `g()[0]`, B3 an
#       undefined `qq[0]`, B4 a non-`*T` field `h.f[0]`, B5 `&a[0]`, B6 `a[0][1]`, B7 a `var` initializer, B8 a
#       classic-for step `*pa = 1`, B9 a generic fn at two instances (once each), B10 top level after the first
#       statement (three), B11 three refusals in a row (three), B12 B11 under --syntax-only (what `cyrius lint` runs)
#       B13 / B14 an undefined `.field` base `qq.b` (6.7.17)
#   M   a refusal that leaves the statement mid-way still resyncs to its `;`: M1 `y = pa[0 qq1 qq2;` then `y = 1;` —
#       one error, nothing about qq1 / qq2; M2 the same then `y = zz9;` — two
#   P   control: 6.7.11's pair refusal `y = f();` then `y = zz9;` — two, as before
# Every row on the x86_64, aarch64, cx, PE and Mach-O compilers built from this tree: the exact error lines, rc 1,
# no binary. 6.7.16 (f16) adds the AS (#assert), H (block-head headers), R (a head's missing `{`), U (a top-level
# `var c: S;`) and BB (a fn signature with no body) rows, each section with its own ledger below, and the corpus floor
# at the end.
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
error:<source>:6:9: $Z
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
error:<source>:5:9: $Z"

row B2 "g()[0], g not returning *T" 'fn g(): i64 { return 0; }
fn main(): i64 {
    var y = 0;
    y = g()[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:12: cannot subscript the result of 'g': it does not return a *T
error:<source>:5:9: $Z"

row B3 "an undefined base qq[0]" 'fn main(): i64 {
    var y = 0;
    y = qq[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:3:9: undefined variable 'qq' (missing include or enum?)
error:<source>:4:9: $Z"

# B13 / B14 (6.7.17, met in FD1) — an undefined `.field` base read latched with no mark: `y = qq.b; y = zz9;` lost
# zz9's error, `var y = qq.b; zy.c = 1;` zy's (`_refuse_in_sync` in PARSE_FIELD_LOAD's undefined-base arm).
row B13 "an undefined .field base qq.b" 'fn main(): i64 {
    var y = 0;
    y = qq.b;
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:3:9: undefined variable 'qq'
error:<source>:4:9: $Z"
row B14 "an undefined .field base in a var initializer, then a field store" 'fn main(): i64 {
    var y = qq.b;
    zy.c = 1;
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:2:13: undefined variable 'qq'
error:<source>:3:5: undefined variable 'zy'
error:<source>:4:9: $Z"

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
error:<source>:6:9: $Z"

row B5 "&a[0]" 'fn main(): i64 {
    var a: i64[4];
    var y = 0;
    y = &a[0];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:11: &a[i] is not supported - write &a + i * sizeof(T) (or p + i)
error:<source>:5:9: $Z"

row B6 "a[0][1]" 'fn main(): i64 {
    var a: i64[4];
    var y = 0;
    y = a[0][1];
    y = zz9;
    return 0;
}
syscall(60, main());
' "error:<source>:4:13: a subscript's result is an element, not an array - a second [..] is not supported
error:<source>:5:9: $Z"

row B7 "a var initializer var z = pa[0];" "${PA}    var z = pa[0];
    y = zz9;
${TAIL}" "error:<source>:5:15: cannot subscript 'pa$U
error:<source>:6:9: $Z"

row B8 "a classic-for step *pa = 1" "${PA}    for (var i = 0; i < 2; *pa = 1) { y = 1; }
    y = zz9;
${TAIL}" "error:<source>:5:28: cannot dereference 'pa$U
error:<source>:6:9: $Z"

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
error:<source>:6:9: $Z"

row B10 "top level, after the first statement" 'var a: u128 = 0;
var pa: *u128 = &a;
var y = 0;
y = 1;
y = pa[0];
y = zz9;
pa[0] = 1;
syscall(60, 0);
' "error:<source>:5:7: cannot subscript 'pa$U
error:<source>:6:5: $Z
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
error:<source>:6:9: $Z"

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
error:<source>:6:9: $Z"

# okrow <id> <what> <source> <exit>: compiles on every leg (rc 0, no error / warning line, a binary), runs <exit> on x86
okrow() {
    printf '%s' "$3" > "$D/$1.cyr"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp "$leg" "$D/$1.cyr" "$o"
        if [ "$CRC" -ne 0 ]; then bad "$1 $leg: $2: rc $CRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
        elif grep -qE '^(error|warning)' "$o.err"; then bad "$1 $leg: $2: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
        elif [ ! -s "$o" ]; then bad "$1 $leg: $2: no binary"
        elif [ "$leg" = x86 ]; then
            chmod +x "$o"; XRC=0; timeout 60 "$o" > /dev/null 2>&1 || XRC=$?
            if [ "$XRC" -eq "$4" ]; then ok "$1 $leg: $2 (exit $4)"; else bad "$1 $leg: $2: exit $XRC, want $4"; fi
        else ok "$1 $leg: $2"; fi
    done
}

# AS — 6.7.16 (issues/archived/2026-10-19-refused-assert-after-first-statement-swallows-next-statement.md): AN #assert IS
# LINE-TERMINATED, SO A REFUSED ONE ENDS IN SYNC AT ITS LINE, not only at its `;`. `_assert_end` (src/frontend/
# parse.cyr) put the caller's latch back only when the tail ended at a `;`: `#assert zz9 == 1` with no `;` kept it,
# and the statement on the next line was skipped by the resync with its own error (after the first top-level
# statement and in a fn body; the declaration zone's resync stops at the next declaration keyword). The refused
# expression is now stepped to its grammar's end (`_ce_extent`, what pass 1 skips) when that is a well-bracketed
# stretch with no `;`, and the tail ends the directive there. AS1 is the filing's program verbatim. AS12 (control):
# an unclosed `(` is no such stretch — it resyncs as before, one error, nothing invented.
# And (met in passing, the brief's same-family item) IN A BLOCK the tail stops at the `}` on its line that closes
# the block: it ate it, so `{ #assert 1 == 1 }` added "expected '}', got end of file" to its one refusal (AS13), and
# `{ #assert 1 == 1, "m" }` was that invented error alone — now "#assert: expected `;` or a line break before `}`"
# (AS14), in a fn's block, a top-level block (AS16), an impl body (AS17, AS18) and a switch arm (AS19). At module
# scope a `}` on the line closes nothing; the tail took it through 6.7.16 (ASV3 pinned that), and since 6.7.17 it is
# refused as any token after the message is (the user's D28, 2026-10-22: AS21; the rows of that decision are
# resolution_excerpt_and_assert_skip.sh's axis 8).
# MUTATION LEDGER (2026-10-20, f16; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from that copy with CYCC= it, so every leg's compiler carries the mutant):
#   `_asrt_synced` back to the `;`-only rule (6.7.15's)  -> RED AS1 AS2 AS4 AS6 AS7 AS8 AS9 AS11 on every leg, 40 (the
#                                                           next statement's error missing); AS3 and the rest green
#   `_asrt_ext` not stepping to the extent               -> RED AS7 AS8, 10 (the wrapped expression's next line parsed
#                                                           as a statement, or the next statement swallowed)
#   `_asrt_in_blk` returning 0 (the tail eats the `}`)   -> RED AS13-AS20, 40 (the invented "expected '}'", or it alone)
A9="unknown name 'zz9' in a const context"
ZZ="undefined variable 'zz' (missing include or enum?)"
AB="#assert: expected \`;\` or a line break before \`}\`"
row AS1 "the filing's program verbatim: a refused #assert, no ';', then a statement" 'var a = 1;
a = 2;
#assert zz9 == 1
syscall(60, zz);
' "error:<source>:3:9: $A9
error:<source>:4:13: $ZZ"

row AS2 "in a fn body" 'fn f(): i64 {
    var y = 0;
    #assert zz9 == 1
    y = zz;
    return y;
}
syscall(60, f());
' "error:<source>:3:13: $A9
error:<source>:4:9: $ZZ"

row AS3 "with its ';' (unchanged)" 'var a = 1;
a = 2;
#assert zz9 == 1;
syscall(60, zz);
' "error:<source>:3:9: $A9
error:<source>:4:13: $ZZ"

row AS4 "two refused #asserts on consecutive lines, then a statement" 'var a = 1;
a = 2;
#assert zz9 == 1
#assert zz8 == 1
syscall(60, zz);
' "error:<source>:3:9: $A9
error:<source>:4:9: unknown name 'zz8' in a const context
error:<source>:5:13: $ZZ"

row AS5 "a refused #assert as the last line, after a statement's error" 'var a = 1;
a = 2;
syscall(60, zz);
#assert zz9 == 1
' "error:<source>:3:13: $ZZ
error:<source>:4:9: $A9"

row AS6 "junk after the expression, no ';'" 'fn f(): i64 {
    var y = 0;
    #assert 1 == 1 junk
    y = zz;
    return y;
}
syscall(60, f());
' "error:<source>:3:20: #assert: expected \`,\` or \`;\` after the expression
error:<source>:4:9: $ZZ"

row AS7 "a wrapped expression refused on its first line" 'fn f(): i64 {
    var y = 0;
    #assert (zz9 +
        1) == 1
    y = zz;
    return y;
}
syscall(60, f());
' "error:<source>:3:14: $A9
error:<source>:5:9: $ZZ"

row AS8 "a wrapped message" 'fn f(): i64 {
    var y = 0;
    #assert zz9 == 1,
        "m"
    y = zz;
    return y;
}
syscall(60, f());
' "error:<source>:3:13: $A9
error:<source>:5:9: $ZZ"

row AS9 "with a message, no ';'" 'fn f(): i64 {
    var y = 0;
    #assert zz9 == 1, "m"
    y = zz;
    return y;
}
syscall(60, f());
' "error:<source>:3:13: $A9
error:<source>:4:9: $ZZ"

row AS10 "the last line alone" 'var a = 1;
a = 2;
#assert zz9 == 1
' "error:<source>:3:9: $A9"

row AS11 "a refused #assert in a generic fn at two instances (once)" 'fn g<T>(x: T): i64 {
    var y = 0;
    #assert zz9 == 1
    y = zz;
    return y;
}
syscall(60, g(1) + g<i32>(2));
' "error:<source>:3:13: $A9
error:<source>:4:9: $ZZ"

row AS12 "control: an unclosed ( still resyncs, nothing invented" 'fn f(x): i64 {
    var y = 0;
    #assert (zz9 + 1 == 1
    y = zz;
    return y;
}
syscall(60, f(1));
' "error:<source>:3:14: $A9"

row AS13 "a block's } on the #assert's line: its refusal alone" 'fn f(x): i64 { if (x == 1) { #assert 1 == 1 } return 7; }
syscall(60, f(1));
' "error:<source>:1:45: #assert: expected \`,\` or \`;\` after the expression"

row AS14 "a block's } after the message" 'fn f(x): i64 { if (x == 1) { #assert 1 == 1, "m" } return 7; }
syscall(60, f(1));
' "error:<source>:1:50: $AB"

row AS15 "a refused #assert before a block's }" 'fn f(x): i64 { if (x == 1) { #assert zz9 == 1 } return zz; }
syscall(60, f(1));
' "error:<source>:1:38: $A9
error:<source>:1:56: $ZZ"

row AS16 "a top-level block's }" 'var c = 1;
if (c == 1) { #assert 1 == 1, "m" }
syscall(60, zz);
' "error:<source>:2:35: $AB
error:<source>:3:13: $ZZ"

row AS17 "an impl body's }" 'struct S { a; }
impl S { #assert 1 == 1 }
syscall(60, zz);
' "error:<source>:2:25: #assert: expected \`,\` or \`;\` after the expression
error:<source>:3:13: $ZZ"

row AS18 "an impl body's } after the message" 'struct S { a; }
impl S { #assert 1 == 1, "m" }
syscall(60, zz);
' "error:<source>:2:30: $AB
error:<source>:3:13: $ZZ"

row AS19 "a switch arm's }" 'fn f(x): i64 { switch (x) { case 1: #assert 1 == 1, "m" } return 7; }
syscall(60, f(1));
' "error:<source>:1:57: $AB"

row AS20 "AS13 under --syntax-only" 'fn f(x): i64 { if (x == 1) { #assert 1 == 1 } return 7; }
syscall(60, f(1));
' "error:<source>:1:45: #assert: expected \`,\` or \`;\` after the expression" --syntax-only

okrow ASV1 "control: a block's #assert with its ';', and on its own line" 'fn f(x): i64 { if (x == 1) { #assert 1 == 1; } if (x == 1) { #assert 2 == 2, "m";
} if (x == 1) { #assert 3 == 3
} return 7; }
syscall(60, f(1));
' 7

okrow ASV2 "control: an impl body's and a top-level block's #assert" 'struct S { a; }
impl S {
    #assert 1 == 1
    fn m(self): i64 { return 5; }
}
impl S { #assert 1 == 1, "m"; fn n(self): i64 { return 4; } }
var c = 1;
if (c == 1) { #assert 1 == 1; }
fn main(): i64 { var s = S { 1 }; return s.m() + s.n(); }
syscall(60, main());
' 9

okrow ASV3 "control: a message holding braces" 'fn f(x): i64 {
    #assert 1 == 1, "a { b }"
    return 7;
}
syscall(60, f(1));
' 7

row AS21 "6.7.17 (D28): a } at module scope after the message is refused, as any token there" 'fn f(x): i64 { return 7; }
#assert 1 == 1, "m" }
syscall(60, f(zz));
' "error:<source>:2:21: #assert: expected \`;\` or the end of the line after the message
error:<source>:3:15: $ZZ"

# H — 6.7.16 (issues/archived/2026-10-19-refusal-in-compound-statement-header-swallows-blocks-second-statement.md): A REFUSAL
# LATCHED IN A BLOCK HEAD'S HEADER IS THE HEADER'S, CLEARED AT ITS `{`. The header of an `if` / `elif` / `while` /
# classic `for` / `for .. in` / `switch` / `match` that refused left the latch set for the block: its first
# statement ended latched, PARSE_STMT's resync skipped the SECOND statement, and that statement's error was never
# reported. `_blk_open` (src/frontend/parse/ctrl.cyr) clears the latch when it was clear as the head began and the
# cursor's `{` is exactly the header's end. H1 is the filing's program verbatim. Controls: H9 a header left mid-way
# (`if (y b) {`) keeps the latch; H10 a header inside a closure argument parsed under a statement's own latch keeps it.
# MUTATION (2026-10-20, f16, the scratch-copy procedure above): `_blk_open` never clearing -> RED H1-H8 and H11-H16 on
# every leg (70); H9 H10 green.
row H1 "the filing's program verbatim: an if header's u128 subscript" "${PA}    if (pa[0] == 1) {
        y = 1;
        y = zz8;
        y = zz7;
    }
${TAIL}" "error:<source>:5:11: cannot subscript 'pa$U
error:<source>:7:13: undefined variable 'zz8' (missing include or enum?)
error:<source>:8:13: undefined variable 'zz7' (missing include or enum?)"

row H2 "while (qq[0] == 1)" "${PA}    while (qq[0] == 1) { y = 1; y = zz8; }
${TAIL}" "error:<source>:5:12: undefined variable 'qq' (missing include or enum?)
error:<source>:5:37: undefined variable 'zz8' (missing include or enum?)"

row H3 "a syntax error in the header: if (y == 0 +)" "${PA}    if (y == 0 +) { y = 1; y = zz8; }
${TAIL}" "error:<source>:5:17: unexpected ')'
error:<source>:5:32: undefined variable 'zz8' (missing include or enum?)"

row H4 "elif (qq[0] == 1)" "${PA}    if (y == 1) { y = 2; } elif (qq[0] == 1) { y = 1; y = zz8; }
${TAIL}" "error:<source>:5:34: undefined variable 'qq' (missing include or enum?)
error:<source>:5:59: undefined variable 'zz8' (missing include or enum?)"

row H5 "a classic for's condition" "${PA}    for (var i = 0; i < qq[0]; i = i + 1) { y = 1; y = zz8; }
${TAIL}" "error:<source>:5:25: undefined variable 'qq' (missing include or enum?)
error:<source>:5:56: undefined variable 'zz8' (missing include or enum?)"

row H6 "for i in 0..qq[0]" "${PA}    for i in 0..qq[0] { y = 1; y = zz8; }
${TAIL}" "error:<source>:5:17: undefined variable 'qq' (missing include or enum?)
error:<source>:5:36: undefined variable 'zz8' (missing include or enum?)"

row H7 "switch (qq[0])" "${PA}    switch (qq[0]) { case 1: y = 1; y = zz8; }
${TAIL}" "error:<source>:5:13: undefined variable 'qq' (missing include or enum?)
error:<source>:5:41: undefined variable 'zz8' (missing include or enum?)"

row H8 "a top-level if after the first statement" 'var y = 0;
y = 1;
if (qq[0] == 1) { y = 1; y = zz8; }
syscall(60, 0);
' "error:<source>:3:5: undefined variable 'qq' (missing include or enum?)
error:<source>:3:30: undefined variable 'zz8' (missing include or enum?)"

row H9 "control: a header left mid-way keeps the latch" "${PA}    if (y b) { y = 1; y = zz8; }
${TAIL}" "error:<source>:5:11: expected ')', got identifier 'b'"

row H10 "control: a header in a closure parsed under the statement's latch" 'fn g(f): i64 { return 0; }
fn main(): i64 {
    var a: u128 = 0;
    var pa: *u128 = &a;
    var y = pa[0] + g(|x| { if (qq[0] == 1) { var w = 1; w = zz8; } return x; });
    y = zz7;
    return 0;
}
syscall(60, main());
' "error:<source>:5:15: cannot subscript 'pa$U
error:<source>:6:9: undefined variable 'zz7' (missing include or enum?)"

row H11 "match (qq[0])" "${PA}    match (qq[0]) { 1 => { y = 1; y = zz8; } _ => { y = 2; } }
${TAIL}" "error:<source>:5:12: undefined variable 'qq' (missing include or enum?)
error:<source>:5:39: undefined variable 'zz8' (missing include or enum?)"

row H12 "a collection for x in qq[0]" 'include "lib/vec.cyr"
fn main(): i64 {
    var y = 0;
    for x in qq[0] { y = 1; y = zz8; }
    return 0;
}
syscall(60, main());
' "error:<source>:4:14: undefined variable 'qq' (missing include or enum?)
error:<source>:4:33: undefined variable 'zz8' (missing include or enum?)"

row H13 "nested heads, each its own" 'fn main(): i64 {
    var y = 0;
    if (qq[0] == 1) { if (pp[0] == 1) { y = 1; y = zz8; } y = zz7; }
    return 0;
}
syscall(60, main());
' "error:<source>:3:9: undefined variable 'qq' (missing include or enum?)
error:<source>:3:27: undefined variable 'pp' (missing include or enum?)
error:<source>:3:52: undefined variable 'zz8' (missing include or enum?)
error:<source>:3:63: undefined variable 'zz7' (missing include or enum?)"

row H14 "a generic fn at two instances (once)" 'fn gg<T>(x: T): i64 {
    var y = 0;
    while (qq[0] == 1) { y = 1; y = zz8; }
    return 0;
}
fn main(): i64 { gg<i64>(1); gg<i32>(2); return 0; }
syscall(60, main());
' "error:<source>:3:12: undefined variable 'qq' (missing include or enum?)
error:<source>:3:37: undefined variable 'zz8' (missing include or enum?)"

row H15 "a syntax error in the header and the block, --syntax-only" 'fn main(): i64 {
    var y = 0;
    if (y == 0 +) { y = 1; y = 2 +; }
    return 0;
}
syscall(60, main());
' "error:<source>:3:17: unexpected ')'
error:<source>:3:35: unexpected ';'" --syntax-only

row H16 "a top-level while after the first statement, u128 subscript" 'var a: u128 = 0;
var pa: *u128 = &a;
var y = 0;
y = 1;
while (pa[0] == 1) { y = 1; y = zz8; }
syscall(60, 0);
' "error:<source>:5:10: cannot subscript 'pa$U
error:<source>:5:33: undefined variable 'zz8' (missing include or enum?)"

# R — 6.7.16 (met with H, the same `{` step): A HEAD WHOSE `{` IS NOT WHERE THE PARSER STANDS KEEPS ITS BRACES. The
# `{` check stepped one token whatever it was, so the block's `}` closed the enclosing body and "expected '}', got end
# of file" was invented at the end of the file — after a header left mid-way (H9 printed it, R1) and after a body
# written without braces (R2-R8), with the next statement's own error lost or a stray "unexpected else" (R3). Now a
# mid-way header is stepped to its end (its `{` opens the block, the latch kept), a brace-less body is that one
# statement (refused once, "expected '{', got ..."), and a `switch` / `match` with no `{` is refused and skipped to
# its statement's end (R9, R10; `match y 1 => ..` said "expected '>', got number 2" and two invented lines).
# MUTATION (2026-10-20, f16, the scratch-copy procedure above): `_blk_open`'s mid-way step dropped -> RED H9 R1 R11
# on every leg (15: the invented "expected '}'", or the block parsed as one statement); its no-`{` arm stepping one
# token again (the old recovery) -> RED R2-R8 R10 R13-R15 (55); R9 and R12 hold under either (the switch's / the
# match's skip reaches the same end).
row R1 "a mid-way header, then a statement" "${PA}    if (y b) { y = 1; }
    y = zz8;
${TAIL}" "error:<source>:5:11: expected ')', got identifier 'b'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R2 "if (c) y = 1; with no braces" "${PA}    if (y == 1) y = 1;
    y = zz8;
${TAIL}" "error:<source>:5:17: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R3 "if and else with no braces" "${PA}    if (y == 1) y = 1; else y = 2;
    y = zz8;
${TAIL}" "error:<source>:5:17: expected '{', got identifier 'y'
error:<source>:5:29: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R4 "an elif with no braces" "${PA}    if (y == 1) { y = 1; } elif (y == 2) y = 3;
    y = zz8;
${TAIL}" "error:<source>:5:42: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R5 "a while with no braces" "${PA}    while (y == 1) y = 1;
    y = zz8;
${TAIL}" "error:<source>:5:20: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R6 "a classic for with no braces" "${PA}    for (var i = 0; i < 3; i = i + 1) y = i;
    y = zz8;
${TAIL}" "error:<source>:5:39: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R7 "a for .. in with no braces" "${PA}    for i in 0..3 y = i;
    y = zz8;
${TAIL}" "error:<source>:5:19: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R8 "a do with no braces" "${PA}    do y = 2; while (y == 1);
    y = zz8;
${TAIL}" "error:<source>:5:8: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R9 "a switch with no {" "${PA}    switch (y) case 1: y = 2;
    y = zz8;
${TAIL}" "error:<source>:5:16: expected '{', got case
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R10 "a match with no {" "${PA}    match y 1 => { y = 2; }
    y = zz8;
${TAIL}" "error:<source>:5:13: expected '{', got number 1
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R11 "a for .. in range with junk before its {" "${PA}    for i in 0..3 junk { y = 1; }
    y = zz8;
${TAIL}" "error:<source>:5:19: expected '{', got identifier 'junk'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R12 "a match subject with junk before its {" "${PA}    match y junk { 1 => { y = 2; } }
    y = zz8;
${TAIL}" "error:<source>:5:13: expected '{', got identifier 'junk'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R13 "nested ifs with no braces" "${PA}    if (y == 1) if (y == 2) y = 1;
    y = zz8;
${TAIL}" "error:<source>:5:17: expected '{', got if
error:<source>:5:29: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

row R14 "a top-level if with no braces, after the first statement" 'var y = 0;
y = 1;
if (y == 1) y = 2;
syscall(60, zz8);
' "error:<source>:3:13: expected '{', got identifier 'y'
error:<source>:4:13: undefined variable 'zz8' (missing include or enum?)"

row R15 "a refused header and no braces" "${PA}    if (qq[0] == 1) y = 1;
    y = zz8;
${TAIL}" "error:<source>:5:9: undefined variable 'qq' (missing include or enum?)
error:<source>:5:21: expected '{', got identifier 'y'
error:<source>:6:9: undefined variable 'zz8' (missing include or enum?)"

# U — 6.7.16 (issues/archived/2026-10-19-top-level-uninitialized-struct-refusal-leaves-name-unregistered.md): `var c: S;` AT
# TOP LEVEL after the first statement (an uninitialized struct or vector, which only a fn's frame holds) IS REFUSED
# IN SYNC AND DECLARES `c` AS REPORTED. PARSE_VAR's arm latched with no mark — the resync skipped the next statement
# — and registered a fn-local slot no top-level use reads, so each use of `c` added "undefined variable 'c'".
# `_usl_top` (src/frontend/parse/decl/gvar.cyr) marks it in sync, steps its `;`, and enters `c` in the refused variables
# (`_dl_var_refd_add`, parse/fn/def.cyr) that `_undef_var_report`, the subscript's undefined base and a multi-value
# target stand down at (`_dl_name_refd`; U6: the subscript's arm missed a refused late enum's member as well). U1 is
# the filing's program verbatim. Controls: U5 the declaration in a fn compiles and runs; U7 a type annotation
# spelled `c` is still "unknown type 'c'" (a variable's mark, not a type's).
# MUTATION (2026-10-20, f16, the scratch-copy procedure above): `_usl_top` without `_refuse_in_sync` -> RED U4 U8 on
# every leg (10: the next statement swallowed with its error); without `_dl_var_refd_add` -> RED U1 U2 U3 (15: the
# uses' "undefined variable 'c'").
row U1 "the filing's program verbatim" 'struct Str { p; n; }
var q = 0;
q = 1;
var c: Str;
var d = 9;
c = 4;
syscall(60, zz);
' "error:<source>:4:11: uninitialized struct locals only allowed inside a function
error:<source>:7:13: undefined variable 'zz' (missing include or enum?)"

row U2 "c = 4; directly after the declaration" 'struct Str { p; n; }
var q = 0;
q = 1;
var c: Str;
c = 4;
syscall(60, zz);
' "error:<source>:4:11: uninitialized struct locals only allowed inside a function
error:<source>:6:13: undefined variable 'zz' (missing include or enum?)"

row U3 "every use of c stands down" 'struct Str { p; n; }
impl Str { fn m(self): i64 { return 1; } }
fn g(x): i64 { return 0; }
fn two(): (i64, i64) { return (1, 2); }
var q = 0;
q = 1;
var c: Str;
c.p = 4;
q = c.p + c.m() + g(c) + g(&c);
c += 1;
c.n += 1;
c[0] = 1;
q = c[1];
q, c = two();
fn h(): i64 { var w: Str = c; return w.p + c.n; }
syscall(60, zz);
' "error:<source>:7:11: uninitialized struct locals only allowed inside a function
error:<source>:16:13: undefined variable 'zz' (missing include or enum?)"

row U4 "a vector type at top level" 'var q = 0;
q = 1;
var c: f64v2;
syscall(60, zz);
' "error:<source>:3:13: uninitialized struct locals only allowed inside a function
error:<source>:4:13: undefined variable 'zz' (missing include or enum?)"

row U8 "the next statement's own error, directly after" 'struct Str { p; n; }
var q = 0;
q = 1;
var c: Str;
q = zz5;
syscall(60, 0);
' "error:<source>:4:11: uninitialized struct locals only allowed inside a function
error:<source>:5:5: undefined variable 'zz5' (missing include or enum?)"

okrow U5 "control: the declaration in a fn compiles and runs" 'struct Str { p; n; }
fn f(): i64 { var c: Str; c.p = 3; c.n = 4; return c.p + c.n; }
var q = 0;
q = 1;
syscall(60, f());
' 7

row U6 "a refused late enum's member as a subscript base" 'enum E { A; B; }
var y = 1;
y = 2;
enum F { C; }
y = C[0];
syscall(60, zz);
' "error:<source>:4:1: an \`enum\` declaration must come before the first top-level statement (line 3)
error:<source>:6:13: undefined variable 'zz' (missing include or enum?)"

row U7 "control: a type annotation spelled c is still refused" 'struct Str { p; n; }
var q = 0;
q = 1;
var c: Str;
var x: c = 5;
syscall(60, zz);
' "error:<source>:4:11: uninitialized struct locals only allowed inside a function
error:<source>:5:8: unknown type 'c' for variable 'x'
error:<source>:6:13: undefined variable 'zz' (missing include or enum?)"

# BB — 6.7.16 (f16 FG2, met with issues/archived/2026-10-20-fn-pointer-return-type-refused-as-reserved-keyword-identifier.md):
# A FN SIGNATURE WITH NO BODY (`fn h(): i64;`, a trait member's shape) IS ONE ERROR, "expected '{', got ';'". PARSE_FN_DEF
# took the `;` for the `{`, so the declarations after it were read as the body ("fn 'main' is defined inside fn 'h'",
# "expected '}', got end of file"), and pass 1's `_prescan_skip_fn` ran on to the next fn's `}`, leaving it
# unregistered. The `;` now stands for an empty body (`_fn_body_open`, `_fn_has_body`), and pass 1 stops at it.
#   BB1 a fn, then main's own error; BB2 an inherent impl's method, then the next method's own error; BB3 a generic one
#   (its call is replayed inline: it read the next fn as the body); BB4 one below its caller, a fn after it called from
#   the top level; BB4b a forward call to a fn after it reads that fn's pass-1 facts (a struct return); BB5 no return type, and parameters — each its own line (the latch is
#   released at the `;`); BB6 BB1 under --syntax-only; BB7 control: a body whose first token is `;` is a body (refused
#   "unexpected ';'" as before); BB8 control: a fn, an impl method and a generic with bodies build (x86_64: exit 3); BB9
#   a bounded generic whose i64 base is a stub (`_b3_skip`: its skip ran on into main's body).
# Mutants (2026-10-21, a scratch copy of src/ with the one change, its cycc, this gate run with CYCC= it — the x86_64,
# PE and Mach-O legs; the aarch64 / cx compilers are built from the tree): the lane before it (817768e2f) -> RED 24:
# BB1-BB6 BB9 on the three legs ("fn 'main' is defined inside fn 'h'", "expected '}'", BB4b mk's invented line);
# `_cov_body` reading the `;` as a body -> RED 24, the same; `_prescan_skip_fn` not stopping at the `;` -> RED 3: BB4b
# (the fn after it unregistered in pass 1); `_fn_body_close` keeping the latch -> RED 3: BB5 (j's line swallowed); the
# stub skip of a bounded generic's i64 base left on (`_b3_skip = 1`) -> RED 3: BB9
row BB1 "a fn with no body, then main's own error" 'fn h(): i64;
fn main(): i64 { return 3 + zz; }
syscall(60, main());
' "error:<source>:1:12: expected '{', got ';'
error:<source>:2:29: undefined variable 'zz' (missing include or enum?)"

row BB2 "an impl method with no body, then the next method's own error" 'struct P { x; }
impl P { fn h(self): i64; fn k(self): i64 { return 1 + yy; } }
fn main(): i64 { var p = P { 1 }; return p.k(); }
syscall(60, main());
' "error:<source>:2:25: expected '{', got ';'
error:<source>:2:56: undefined variable 'yy' (missing include or enum?)"

row BB3 "a generic with no body, called (replayed inline)" 'fn g<T>(x: T): T;
fn main(): i64 { return g(3) + zz; }
syscall(60, main());
' "error:<source>:1:17: expected '{', got ';'
error:<source>:2:32: undefined variable 'zz' (missing include or enum?)"

row BB4 "below its caller; the fn after it registered in pass 1" 'fn main(): i64 { return h() + zz; }
fn h(): i64;
fn k(): i64 { return 2; }
syscall(60, main() + k());
' "error:<source>:1:31: undefined variable 'zz' (missing include or enum?)
error:<source>:2:12: expected '{', got ';'"

row BB4b "a forward call past it reads pass 1's facts (mk's struct return: no \"no struct type in scope for 'p'\")" 'struct Pt { x; y; z; }
fn main(): i64 { var p = mk(); return p.z; }
fn h(): i64;
fn mk(): Pt { var p: Pt; p.z = 3; return p; }
syscall(60, main() + zz);
' "error:<source>:3:12: expected '{', got ';'
error:<source>:5:22: undefined variable 'zz' (missing include or enum?)"

row BB5 "no return type, and parameters" 'fn h();
fn j(a, b);
fn main(): i64 { return zz; }
syscall(60, main());
' "error:<source>:1:7: expected '{', got ';'
error:<source>:2:11: expected '{', got ';'
error:<source>:3:25: undefined variable 'zz' (missing include or enum?)"

row BB6 "BB1 under --syntax-only" 'fn h(): i64;
fn main(): i64 { return 3 + zz; }
syscall(60, main());
' "error:<source>:1:12: expected '{', got ';'" --syntax-only

row BB7 "control: a body whose first token is a \`;\` is read as a body (refused as before)" 'fn h(): i64 { ; return 3; }
fn main(): i64 { return h() + zz; }
syscall(60, main());
' "error:<source>:1:15: unexpected ';'
error:<source>:2:31: undefined variable 'zz' (missing include or enum?)"

row BB9 "a bounded generic with no body (its i64 base a skipped stub: the skip ran into main's body)" 'trait Show { fn show(self): i64; }
fn g<T: Show>(x: T): i64;
fn main(): i64 { return 3 + zz; }
syscall(60, main());
' "error:<source>:2:25: expected '{', got ';'
error:<source>:3:29: undefined variable 'zz' (missing include or enum?)"

okrow BB8 "control: the shapes beside it build — a one-statement fn, an impl method, a generic" 'struct P { x; }
impl P { fn k(self): i64 { return self.x; } }
fn h(): i64 { return 1; }
fn g<T>(x: T): T { return x; }
fn main(): i64 { var p = P { 1 }; return h() + p.k() + g(1); }
syscall(60, main());
' 3

# The corpus floor (6.7.16): 89 rows on five legs, 90 with 6.7.17's AS21. The gate had none, so a row lost from the
# list, or a leg that stopped running, read green.
FLOOR=450
if [ $((pass + fail)) -lt "$FLOOR" ]; then bad "$G ran $((pass + fail)) row-legs (floor $FLOOR) - rows or legs were lost"; fi
echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
