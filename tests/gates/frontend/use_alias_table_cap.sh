#!/bin/sh
# Gate: the `use mod.fn;` alias table is bounded — the 65th alias is REFUSED by name, never
# stored (6.6.20, HEAP-02, the use-alias table overflow bug; SECURITY). And a `use` is one line,
# any other shape refused by name (6.7.17, the user's D30: the UL rows below).
#
# THE DEFECT (measured at 6.6.19, x86_64 Linux, no diagnostic): `_tl_use_alias`
# (src/frontend/parse_fn.cyr) stored alias #uc at use_from[uc] / use_to[uc] with no cap. The two
# tables are 64 entries each and ABUT in the heap map (use_from @0x18FFD0, use_to @0x1901D0, the
# count @0x1903D0), so the 65th `use` wrote its source name into use_to[0] — alias #1 then
# resolved to whatever fn carried that bare name, and the program called it silently — and every
# later alias walked on through the parser's state (expr types, include names, the #define table)
# up to gvar_cnt: 66-120 aliases failed loud with a bogus "undefined function", 199-5062 compiled
# rc 0 and called the wrong fn, 5063+ died SIGSEGV. The same unguarded code was inline in 6.5.73.
#
# THE FIX: refuse at uc >= 64 with "too many `use` aliases (max 64)" BEFORE any store (ERR_MSG does
# not exit; the `return 0` is what stops the writes). MUTATION LEDGER (6.6.20):
#   cap removed (6.6.19)                  -> RED rows R65 R200 R5100 (R65 rc 0, exits 99: the bare global)
#   cap at 63                             -> RED row A64
#   the `return 0` dropped (ERR_MSG only) -> RED row R5100 (the stores still run: rc 139)
#
# Every fixture: a GLOBAL fn g64 (exit 99), then `mod m;` with g0..g(K-1) (g0 exits 7), then N
# `use m.gI;` lines, then a call of the bare name g0 — which resolves ONLY through the alias table
# (row C: with no `use`, g0 is undefined).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: use_alias_table_cap: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: use_alias_table_cap: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: use_alias_table_cap: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $D for the UL rows' PE runs (never ~/.wine), torn down with its server dir on exit.
WP="$D/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# fixture <uses> <module fns> <out>
fixture() {
    awk -v n="$1" -v k="$2" 'BEGIN {
        print "fn g64(): i64 { return 99; }"
        print "mod m;"
        print "fn g0(): i64 { return 7; }"
        for (i = 1; i < k; i++) printf "fn g%d(): i64 { return %d; }\n", i, i + 100
        for (i = 0; i < n; i++) printf "use m.g%d;\n", i
        print "var r = g0();"
        print "syscall(60, r);"
    }' > "$3"
}

# A64 — 64 aliases, the table full: g0 is alias #1 and resolves to m's g0 (exit 7)
NROWS=$((NROWS + 1))
fixture 64 65 "$D/a.cyr"
if "$CC" < "$D/a.cyr" > "$D/a.bin" 2> "$D/a.err" && [ -s "$D/a.bin" ]; then
    chmod +x "$D/a.bin"
    set +e; "$D/a.bin" > /dev/null 2>&1; r=$?; set -e
    [ "$r" = "7" ] || bad "row A64: 64 aliases ran with exit $r, want 7 (m's g0)"
else
    bad "row A64: 64 aliases did not compile: $(grep -v '^note' "$D/a.err" | head -c 200)"
fi

# R<N> — N > 64 aliases: refused by name, exit 1 (not a SIGSEGV), no binary that runs
refuse() {
    NROWS=$((NROWS + 1))
    fixture "$1" "$2" "$D/r.cyr"
    set +e; "$CC" < "$D/r.cyr" > "$D/r.bin" 2> "$D/r.err"; rc=$?; set -e
    if [ "$rc" = "0" ]; then
        set +e; chmod +x "$D/r.bin"; "$D/r.bin" > /dev/null 2>&1; r=$?; set -e
        bad "row R$1: $1 aliases COMPILED (rc 0; the program exits $r — 7 is m's g0, 99 the bare global)"
    elif [ "$rc" != "1" ]; then
        bad "row R$1: $1 aliases: the compiler died (rc $rc), want a refusal (rc 1)"
    elif ! grep -q 'too many `use` aliases (max 64)' "$D/r.err"; then
        bad "row R$1: refused without the cap diagnostic: $(grep -v '^note' "$D/r.err" | head -c 200)"
    fi
}
refuse 65 65      # the first entry past the table: re-bound alias #1 to the global g64 (exit 99)
refuse 200 200    # silently miscompiled
refuse 5100 5100  # reached gvar_cnt: SIGSEGV

# C — the premise: with no `use`, the bare g0 is undefined (so A64 / R65 measure the table)
NROWS=$((NROWS + 1))
fixture 0 65 "$D/c.cyr"
if "$CC" < "$D/c.cyr" > "$D/c.bin" 2> "$D/c.err"; then
    bad "row C: g0 resolved with no \`use\` — the fixture no longer measures the alias table"
elif ! grep -q "undefined function 'g0'" "$D/c.err"; then
    bad "row C: refused, but not as an undefined g0: $(grep -v '^note' "$D/c.err" | head -c 200)"
fi

# ── UL: A `use` IS ONE LINE (6.7.17) ─────────────────────────────────────────────────────────────────────────────────
# issues/2026-10-21-directive-line-tails-unread-use-without-path-late-private.md (row 4) and the user's D30 (2026-10-22,
# "Refuse it by name"). Pass 1 read `use IDENT . IDENT [;]` and pass 2 stepped to the next `;`, so `use m.f` with no `;`
# dropped the next line (exit 0, not 3), and `use 5;`, `use m.;`, `use m;`, `use m.f g;` compiled binding nothing. Now
# one reader (`_use_step`, src/frontend/parse_fn_def.cyr) in every position: the form, then its `;` or its line's end;
# any other line is "expected `use module.name;`" once, at its first wrong token, the line stepped whole. Four legs:
# x86_64, aarch64 (the tree's cross compiler, run under qemu-aarch64), cx (main_cx, run under the tree's cxvm) and PE
# (CYRIUS_TARGET_WIN=1, run under wine in a private prefix) — a refusal by its exact error lines and no binary, a run
# by its exit code.
#   UL1-UL4  D30's four lines: one error each, at the first wrong token
#   UL5      `use m.f` with no `;`: the next line runs (exit 3; 0 before — the line was dropped)
#   UL6      `use 5` with no `;`: its error, and the next line's own `zz`
#   UL7      `use m` (its line ends before the name): the error at the `use`
#   UL8      a `;`-less use after the first statement and in a fn body: the refusal and the next line's `zz` (lost
#            before: the refusal stepped to the next `;`)
#   UL9      a `;`-less use in a fn body, then a block's refused `struct Q` an earlier fn names: no "type 'Q' is declared
#            after its use" (the pre-walk held the use's header open to the next `;`, so the block read as the use's)
#   UL10     a refused use releases the latch it set: the next declaration's own error (`struct Q { a: Foo; }`) is
#            reported
#   UL11     a refused `;`-less use after the first statement: a call of the name it binds adds no "undefined function"
#            (`_dl_quiet` read the name two tokens before the `;`)
#   UC1-UC2  controls: `use m.f;` binds (exit 4); `pub use m.f` with no `;` binds, the next line runs
# MUTATION LEDGER (2026-10-22, lane fea FA1; a scratch copy of the tree with the one change, its 2-stage cycc run as
# CYCC=, so every leg's compiler carries the mutant):
#   pass 2's `_tl_skip_use` back to its walk to the next `;`  -> RED UL5 UL6, 8 row-legs (UL5 exit 0: the line dropped)
#   `_use_step` without its ERR_MSG (D30 not reported)         -> RED UL1-UL4 UL6 UL7 UL10, 28 (rc 0: bound nothing)
#   `_use_step` without its latch release                      -> RED UL10, 4 (the struct's error swallowed)
#   `_dl_skip_at` without `_dl_skip_use` (to the next `;`)     -> RED UL8, 4 (both `zz` lost)
#   `_dl_inner_fill` holding a `use` header open again         -> RED UL9, 4 ("type 'Q' is declared after its use")
#   `_dl_quiet` reading the name two tokens before the end     -> RED UL11, 4 ("undefined function 'f'")
UL_LEGS="x86 pe"
ULN=0
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; UL_LEGS="$UL_LEGS a64"
else bad "UL: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then chmod +x "$D/cc_cx" "$D/cxvm"; UL_LEGS="$UL_LEGS cx"
else bad "UL: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
UL_QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && UL_QEMU=1
UL_WINE=0; command -v wine > /dev/null 2>&1 && UL_WINE=1
[ "$UL_QEMU" = 1 ] || echo "  SKIP: the UL rows' aarch64 RUNS (qemu-aarch64 not installed; the compiles still run)"
[ "$UL_WINE" = 1 ] || echo "  SKIP: the UL rows' PE RUNS (wine not installed; the compiles still run)"
ul_comp() {   # <leg> <src> <out>: PRC = the compiler's rc
    PRC=0
    case "$1" in
        x86) timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
        pe)  CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
        a64) timeout 60 "$D/cc_a64" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
        cx)  timeout 60 "$D/cc_cx" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
    esac
}
ul_exec() {   # <leg> <binary>: XRC = its exit code; 1 = no runner on this box (skipped by name above)
    XRC=0
    case "$1" in
        x86) chmod +x "$2"; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64) [ "$UL_QEMU" = 1 ] || return 1; chmod +x "$2"; timeout 300 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$? ;;
        cx)  timeout 300 "$D/cxvm" < "$2" > /dev/null 2>&1 || XRC=$? ;;
        pe)  [ "$UL_WINE" = 1 ] || return 1
             cp "$2" "$2.exe"
             (cd "$D" && WINEPREFIX="$WP" HOME="$D/whome" XDG_CACHE_HOME="$D/whome/.cache" WINEDEBUG=-all \
                 WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$2.exe" > /dev/null 2>&1) || XRC=$? ;;
    esac
    return 0
}
# ulrefuse <id> <what> <source> <want>: refused on every leg (rc != 0, no binary), its error / warning lines exactly <want>
ulrefuse() {
    printf '%s\n' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $UL_LEGS; do
        o="$D/$1_$leg"
        ul_comp "$leg" "$D/$1.cyr" "$o"
        ULN=$((ULN + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$PRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0 - want the refusal"
        elif ! cmp -s "$o.got" "$D/$1.want"; then bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 $leg: $2: refused, but a binary was written"
        else echo "  ok $1 $leg: $2"; fi
    done
}
# ulrun <id> <what> <source> <exit>: compiles clean on every leg (no error / warning line), and runs to <exit>
ulrun() {
    printf '%s\n' "$3" > "$D/$1.cyr"
    for leg in $UL_LEGS; do
        o="$D/$1_$leg"
        ul_comp "$leg" "$D/$1.cyr" "$o"
        ULN=$((ULN + 1))
        if [ "$PRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            bad "$1 $leg: $2: rc $PRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
        elif ! ul_exec "$leg" "$o"; then echo "  ok $1 $leg: $2 (compiled; its run skipped above)"
        elif [ "$XRC" = "$4" ]; then echo "  ok $1 $leg: $2 (exit $4)"
        else bad "$1 $leg: $2: exit $XRC, want $4"; fi
    done
}
UM='expected `use module.name;`'
ZZ="undefined variable 'zz' (missing include or enum?)"
ulrefuse UL1 "D30: use 5;" 'use 5;
syscall(60, 3);' "error:<source>:1:5: $UM"
ulrefuse UL2 "D30: use m.;" 'use m.;
syscall(60, 3);' "error:<source>:1:7: $UM"
ulrefuse UL3 "D30: use m;" 'use m;
syscall(60, 3);' "error:<source>:1:6: $UM"
ulrefuse UL4 "D30: use m.f g;" 'use m.f g;
syscall(60, 3);' "error:<source>:1:9: $UM"
ulrun UL5 "use m.f with no ';': the next line runs" 'use m.f
syscall(60, 3);' 3
ulrefuse UL6 "use 5 with no ';': its error and the next line's" 'use 5
syscall(60, zz);' "error:<source>:1:5: $UM
error:<source>:2:15: $ZZ"
ulrefuse UL7 "use m: the line ends before the name" 'use m
syscall(60, 3);' "error:<source>:1:1: $UM"
ulrefuse UL8 "a ';'-less use after the first statement and in a fn body: the next line's zz too" 'var a = 1;
a = 2;
use m.f
a = a + zz;
fn f(): i64 { use m.g
return zz; }
syscall(60, f());' "error:<source>:3:1: a \`use\` declaration must come before the first top-level statement (line 2)
error:<source>:4:11: $ZZ
error:<source>:5:15: a \`use\` declaration belongs to the declaration section at top level, not inside a fn body
error:<source>:6:10: $ZZ"
ulrefuse UL9 "a ';'-less use in a body, then a block's refused struct used above it" 'fn h(q: *Q): i64 { return q.y; }
fn f(): i64 {
    use m.f
    if (1 == 1) { struct Q { y; } var q = Q { 5 }; return q.y + h(&q); }
    return 0;
}
syscall(60, f());' "error:<source>:3:5: a \`use\` declaration belongs to the declaration section at top level, not inside a fn body
error:<source>:4:19: a \`struct\` declaration belongs to the declaration section at top level, not inside a fn body"
ulrefuse UL10 "a refused use releases the latch it set: the next declaration's error too" 'use 5;
struct Q { a: Foo; }
syscall(60, 3);' "error:<source>:1:5: $UM
error:<source>:2:15: unknown type 'Foo' for struct field 'a'"
ulrefuse UL11 "a refused ';'-less use: a call of the name it binds adds nothing" 'var a = 1;
a = 2;
use m.f
syscall(60, f());' "error:<source>:3:1: a \`use\` declaration must come before the first top-level statement (line 2)"
ulrun UC1 "control: use m.f; binds" 'mod m;
fn f(): i64 { return 4; }
use m.f;
syscall(60, f());' 4
ulrun UC2 "control: pub use m.f with no ';' binds, the next line runs" 'mod m;
fn f(): i64 { return 6; }
pub use m.f
var r = f();
syscall(60, r);' 6
# The corpus floor: 13 rows on four legs. A row or a leg lost reads RED, never green.
[ "$ULN" -ge 52 ] || bad "UL floor: $ULN row-legs ran (floor 52) - rows or legs were lost"

[ "$NROWS" -eq 5 ] || bad "floor: $NROWS rows ran, want 5"
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: use_alias_table_cap: $NFAIL check(s) failed"
    exit 1
fi
echo "PASS: the use-alias table refuses its 65th entry by name and stores nothing past 64 ($NROWS rows) (6.6.20); a \`use\` is one line, any other shape refused by name ($ULN row-legs on $UL_LEGS) (6.7.17)"
exit 0
