#!/bin/sh
# Gate: overload-suffix dispatch must be ARITY-AWARE and POSITION-CONSISTENT.
#
# Covers the three v6.5.1 fixes. Each axis fails on the v6.5.0 compiler, so this
# gate is non-vacuous — see the mutation notes on each block.
#
# Background. cyrius auto-routes `base(a, ...)` to a sibling `base_str` / `base_int`
# when argument 1's type matches. Two defects had ridden along since the mechanism
# landed (v5.10.25):
#
#   1. The redirect never checked the TARGET's parameter count, so a 1-argument call
#      could be rewritten into a call to a 2-argument function — surplus parameter
#      bound to garbage, reported as a mere *warning*, binary emitted anyway. This
#      silently broke `bayan_json_v_parse(someStr)` across the whole ecosystem and
#      cost bayan a breaking public-API rename (1.3.0) to escape.
#   2. `PARSE_RETURN`'s tail-call fast path emits epilogue+jmp itself and never
#      consulted the overload tables at all, so `return f(s)` called the BASE while
#      `var r = f(s)` correctly routed to `f_str`. A `return` of an overloaded call
#      ran the wrong function, with no diagnostic.
#
# The corpus had ZERO coverage of either shape (fix 1 changes 0 of 253 .tcyr), which
# is exactly why both survived so long. Hence this gate.
#
# 6.7.9 — axis 7: the arity gate judges a sibling defined BELOW the call as it judges
# one above it. CYCC overrides the compiler (a candidate built from a patched src).
# 6.7.11 — axis 8: a sibling with NO definition never takes the call (the user's decision (b)).
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: overload_arity_dispatch: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $D for axis 8's PE row (never ~/.wine), torn down with its server dir on
# exit — the defer_every_return_path.sh helper.
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
fails=0

# Compile $1 (source text; $2 an optional compiler flag) and echo the run exit code, or NOEMIT if no binary.
run() {
    printf '%s' "$1" > "$D/p.cyr"
    ( cd "$ROOT" && cat "$D/p.cyr" | "$CC" ${2:-} > "$D/p.bin" 2>"$D/p.err" ) || true
    if [ ! -s "$D/p.bin" ]; then echo "NOEMIT"; return; fi
    chmod +x "$D/p.bin"
    "$D/p.bin" >/dev/null 2>&1 && echo 0 || echo $?
}

check() { # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  ok: $1 ($3)"
    else
        echo "  FAIL: $1 — expected $2, got $3"
        fails=$((fails + 1))
    fi
}

HDR='include "lib/result.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
'
# str_new(data, len) — pass BOTH args. A 1-arg str_new is itself an arity error now.
MKSTR='var s: Str = str_new("x", 1);'

# ---------------------------------------------------------------------------
# AXIS 1 — SAME ARITY must redirect, in all three call positions.
# Mutation: revert the PARSE_RETURN divert (the _fnt_ovstr/_fnt_ovint block in
# parse_fn.cyr) and the `return/tail` line drops to 11 — that WAS v6.5.0.
# ---------------------------------------------------------------------------
SAME='fn f(a): i64 { return 11; }
fn f_str(a): i64 { return 22; }
fn id(x): i64 { return x; }
'
echo "axis 1 — same arity redirects (want 22 in every position):"
check "same-arity assign"      22 "$(run "$HDR$SAME"'fn main(): i64 { '"$MKSTR"' var r = f(s); return r; }')"
check "same-arity return/tail" 22 "$(run "$HDR$SAME"'fn main(): i64 { '"$MKSTR"' return f(s); }')"
check "same-arity nested arg"  22 "$(run "$HDR$SAME"'fn main(): i64 { '"$MKSTR"' var r = id(f(s)); return r; }')"

# ---------------------------------------------------------------------------
# AXIS 2 — MISMATCHED ARITY must NOT redirect; the base is the correct callee.
# Mutation: drop the _OV_ARITY_OK guard from either dispatch arm and the assign
# and nested lines become 22 (the hijack) — that WAS v6.5.0.
# ---------------------------------------------------------------------------
MISM='fn g(a): i64 { return 11; }
fn g_str(buf, len): i64 { return 22; }
fn id(x): i64 { return x; }
'
echo "axis 2 — mismatched arity does NOT redirect (want 11 in every position):"
check "mismatch assign"      11 "$(run "$HDR$MISM"'fn main(): i64 { '"$MKSTR"' var r = g(s); return r; }')"
check "mismatch return/tail" 11 "$(run "$HDR$MISM"'fn main(): i64 { '"$MKSTR"' return g(s); }')"
check "mismatch nested arg"  11 "$(run "$HDR$MISM"'fn main(): i64 { '"$MKSTR"' var r = id(g(s)); return r; }')"

# ---------------------------------------------------------------------------
# AXIS 3 — a wrong argument count is an ERROR and withholds the binary.
# Mutation: change the `error:` back to `warning:` and drop `_had_error = 1` in
# _CHECK_ARITY; NOEMIT becomes an exit code and the binary ships with a garbage
# parameter — that WAS every release up to v6.5.0.
# ---------------------------------------------------------------------------
echo "axis 3 — wrong arg count is fatal:"
check "arity mismatch withholds binary" NOEMIT \
    "$(run 'fn two(a, b): i64 { return a + b; }
fn main(): i64 { return two(7); }')"

# Every bad call site is reported in ONE compile: _CHECK_ARITY must NOT set _panic
# (an arity mismatch is not a token-stream desync). Mutation: add `_panic = 1` and
# this collapses to 1.
printf 'fn two(a, b): i64 { return a + b; }\nfn main(): i64 { var x = two(1); var y = two(2); var z = two(3); return x; }\n' > "$D/m.cyr"
( cd "$ROOT" && cat "$D/m.cyr" | "$CC" > /dev/null 2>"$D/m.err" ) || true
check "all 3 bad sites reported in one compile" 3 "$(grep -c '^error:' "$D/m.err" || true)"

# ---------------------------------------------------------------------------
# AXIS 4 — the legitimate cstr+len / Str pair still works. This is the shape the
# whole mechanism exists for and the one a naive "just stop redirecting" fix breaks:
# base takes (buf, len), the _str sibling takes (s), and a 1-arg call with a Str
# must reach the sibling.
# ---------------------------------------------------------------------------
echo "axis 4 — the cstr+len / Str pair the mechanism exists for:"
PAIR='fn w(buf, len): i64 { return 11; }
fn w_str(s): i64 { return 22; }
'
check "1-arg Str call reaches _str sibling" 22 \
    "$(run "$HDR$PAIR"'fn main(): i64 { '"$MKSTR"' var r = w(s); return r; }')"
check "2-arg cstr+len call stays on base"  11 \
    "$(run "$HDR$PAIR"'fn main(): i64 { var r = w(0, 0); return r; }')"

# ---------------------------------------------------------------------------
# AXIS 5 — the `_int` route must fire ONLY when the base's param 0 is explicitly
# annotated `: cstring`. That annotation IS the condition the route was guessing at:
# "this param wants a POINTER, so convert the number for it". Without the gate, ANY
# base declaring an i64 return got its calls rerouted to a `_int` sibling whenever
# argument 1 was a bare fn call — so a plain user pair silently ran the wrong body
# (`take(make())` executed `take_int`), while `take(v)` and `take(42)` did not. The
# same value, routed differently depending on whether it passed through a variable.
# Mutation: drop the `& 1` cstrmask test from the _int arm in parse_fn.cyr → 22.
echo "axis 5 — the _int route requires an explicit ': cstring' param 0:"
UNANN='fn take(a): i64 { return 11; }
fn take_int(a): i64 { return 22; }
fn mk(): i64 { return 7; }
'
check "unannotated user pair stays on base" 11 \
    "$(run "$UNANN"'fn main(): i64 { var r = take(mk()); return r; }')"
ANN='fn emit(a: cstring): i64 { return 11; }
fn emit_int(a): i64 { return 22; }
fn mk(): i64 { return 7; }
'
check "cstring-annotated base still routes"  22 \
    "$(run "$ANN"'fn main(): i64 { var r = emit(mk()); return r; }')"

# ---------------------------------------------------------------------------
# AXIS 6 — an integer LITERAL passed to a `: cstring` param is a hard error.
# It used to compile with NO diagnostic and SIGSEGV, because the callee dereferences
# the number as a char*: `println(42)` printed nothing and died on signal 11. A literal
# is the one case cyrius CAN judge — an i64 variable or a fn-call result is genuinely
# indistinguishable from a pointer under ADR-002, but a literal is known at parse time
# to be a number. `0` stays legal: it is the idiomatic NULL.
# Mutation: revert `_had_error = 1` to a `warning:` prefix → an exit code, not NOEMIT.
echo "axis 6 — integer literal to a ': cstring' param is fatal:"
LIT='fn want(a: cstring): i64 { return 11; }
'
check "literal 42 to cstring param"  NOEMIT "$(run "$LIT"'fn main(): i64 { return want(42); }')"
check "literal 0 (NULL) still legal" 11     "$(run "$LIT"'fn main(): i64 { return want(0); }')"

# ---------------------------------------------------------------------------
# AXIS 7 — a sibling defined BELOW the call is judged as one defined ABOVE it (6.7.9).
# Pass 1 records every definition's count, defaults row and variadic flag before pass 2
# parses a call, yet `_OV_ARITY_OK` let a not-yet-emitted sibling through unjudged: `h(s)`
# reached a 2-parameter `h_str` defined below it — garbage for the second parameter on
# 6.5.1 – 6.7.6, refused naming `h_str` since 6.7.7 (F2 checks every forward call) — while
# the same sibling above the call was judged and `h` ran. Routing hung on definition order.
# One row per cell of the filing's table (2- / 1-parameter sibling, above / below), the
# _int arm, both count bounds, a defaulted and a variadic sibling, and the filed repro
# verbatim (docs/development/issues/2026-10-09-overload-router-forward-target-arity-unjudged.md).
# Mutation: put back `if (L64(_fnt_offsets + fi * 8) < 0) { return 1; }` (the GFDS half
# dropped) and every "below, not routed" row goes NOEMIT; judge the count without
# `_pd_min` (min = the parameter count) and both defaulted rows drop to 11; move the
# variadic test below the count and the variadic row drops to 11.
# ---------------------------------------------------------------------------
echo "axis 7 — a sibling defined below the call is judged as one above it:"
H1='fn h(a): i64 { return 11; }
'
H_STR2='fn h_str(s: Str, k): i64 { return 22 + k; }
'
H_STR1='fn h_str(s: Str): i64 { return 22; }
'
H_MAIN='fn main(): i64 { '"$MKSTR"' var r = h(s); return r; }
'
check "2-param _str sibling above: not routed"   11 "$(run "$HDR$H1$H_STR2$H_MAIN")"
check "2-param _str sibling below: not routed"   11 "$(run "$HDR$H1$H_MAIN$H_STR2")"
check "2-param below, return/tail: not routed"   11 \
    "$(run "$HDR$H1"'fn main(): i64 { '"$MKSTR"' return h(s); }
'"$H_STR2")"
check "1-param _str sibling above: routed"       22 "$(run "$HDR$H1$H_STR1$H_MAIN")"
check "1-param _str sibling below: routed"       22 "$(run "$HDR$H1$H_MAIN$H_STR1")"
# The upper bound: a 2-argument call, a 1-parameter sibling (argc > max).
T2='fn t2(a, b): i64 { return 11; }
'
T2_STR='fn t2_str(s: Str): i64 { return 22; }
'
T2_MAIN='fn main(): i64 { '"$MKSTR"' var r = t2(s, 7); return r; }
'
check "2-arg call, 1-param sibling above: not routed" 11 "$(run "$HDR$T2$T2_STR$T2_MAIN")"
check "2-arg call, 1-param sibling below: not routed" 11 "$(run "$HDR$T2$T2_MAIN$T2_STR")"
# A defaulted forward sibling: its min (pass 1's defaults row) admits the 1-argument call,
# which reaches it with the default filled (20 + 5).
D1='fn d(a): i64 { return 11; }
'
D_STR='fn d_str(s: Str, k = 5): i64 { return 20 + k; }
'
D_MAIN='fn main(): i64 { '"$MKSTR"' var r = d(s); return r; }
'
check "defaulted sibling above: routed, default filled" 25 "$(run "$HDR$D1$D_STR$D_MAIN")"
check "defaulted sibling below: routed, default filled" 25 "$(run "$HDR$D1$D_MAIN$D_STR")"
# A variadic forward sibling takes any tail: a 3-argument call to its one named
# parameter is routed.
check "variadic _str sibling below, 3 args: routed" 22 \
    "$(run "$HDR"'fn v(a, b, c): i64 { return 11; }
fn main(): i64 { '"$MKSTR"' var r = v(s, 1, 2); return r; }
fn v_str(s: Str, ...): i64 { return 22; }
')"
# The _int arm runs the same gate.
E1='fn em(a: cstring): i64 { return 11; }
fn mk(): i64 { return 7; }
fn main(): i64 { var r = em(mk()); return r; }
'
check "_int arm, 2-param sibling below: not routed" 11 \
    "$(run "$E1"'fn em_int(a, k): i64 { return 22 + k; }
')"
check "_int arm, 1-param sibling below: routed"     22 \
    "$(run "$E1"'fn em_int(a): i64 { return 22; }
')"
# The filed repro, verbatim: `pr` runs for both calls (1 * 10 + 1).
check "filed repro: pr(s) reaches pr, exit 11" 11 \
    "$(run 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn main(): i64 { alloc_init(); var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }
fn pr_str(s: Str, k): i64 { return k; }
syscall(60, main());
')"

# ---------------------------------------------------------------------------
# AXIS 8 — a sibling with NO definition never takes the call (6.7.11, the user's decision (b),
# 2026-10-13; docs/development/issues/2026-10-11-overload-router-undefined-sibling-under-allow-undef-decision.md).
# `_OV_ARITY_OK` let a target with no recorded definition (offset < 0, GFDS 0 — a name only CALLED
# somewhere) through, "into the undefined-function diagnostic": `pr(s)`, written to the DEFINED `pr`,
# was sent to the undefined `pr_str`. The default build was refused only because that route made the
# name reachable; under --allow-undef the call trapped (x86 / aarch64 rc 132, PE 29). The route also
# hung on text order (a sibling first named BELOW the call was never registered in time: 11). Now the
# base takes the call in every build and position, and in an `object;` unit, where a sibling defined
# in another object is such a name too. cx refuses every undefined call (no --allow-undef): no row.
# Mutation: put back `return 1` for a target with no definition -> RED every row below but the
# below-named one (132 / NOEMIT / 2 relocations; aarch64 132, PE 29).
# ---------------------------------------------------------------------------
echo "axis 8 — a sibling with no definition never takes the call:"
OVR='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn other(): i64 { return pr_str(0); }    # pr_str is named, never defined
fn main(): i64 { alloc_init(); var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }
syscall(60, main());
'
check "filed repro, --allow-undef: pr(s) reaches pr (was 132)"       11 "$(run "$OVR" --allow-undef)"
check "filed repro, default build: builds, pr(s) reaches pr (was refused)" 11 "$(run "$OVR")"
check "the undefined sibling named below the call (11 before too)"   11 \
    "$(run 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn main(): i64 { alloc_init(); var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }
fn later(): i64 { return pr_str(0); }
syscall(60, main());
' --allow-undef)"
check "return / var / assignment, --allow-undef (was 132)"          111 \
    "$(run 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn other(): i64 { return pr_str(0); }
fn t(s: Str): i64 { return pr(s); }
fn main(): i64 { alloc_init(); var s: Str = str_from("ab"); var a = pr(s); var b = 0; b = pr(s); return t(s) * 100 + a * 10 + b; }
syscall(60, main());
' --allow-undef)"
OVI='include "lib/syscalls.cyr"
fn em(a: cstring): i64 { return 11; }
fn mk(): i64 { return 7; }
fn other(): i64 { return em_int(0); }    # em_int is named, never defined
fn main(): i64 { var r = em(mk()); return r; }
syscall(60, main());
'
check "_int arm, an undefined em_int, --allow-undef (was 132)"      11 "$(run "$OVI" --allow-undef)"
check "_int arm, default build: builds (was refused)"               11 "$(run "$OVI")"
# A defined sibling still routes, above and below (axis 4 and axis 7's "routed" rows).
# An `object;` unit: `pr(s)` calls `pr`, so the only relocation against `pr_str` is `other`'s (was 2).
if command -v readelf > /dev/null 2>&1; then
    printf '%s' 'object;
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn other(): i64 { return pr_str(0); }
fn app_main(): i64 { var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }
' > "$D/o.cyr"
    ( cd "$ROOT" && "$CC" < "$D/o.cyr" > "$D/o.o" 2> "$D/o.err" ) || true
    check "object; unit: one relocation against pr_str, other's (was 2)" 1 \
        "$(readelf -r "$D/o.o" 2> /dev/null | grep -c ' pr_str' || true)"
else
    echo "  NOT RUN: the object-mode row (readelf not installed)"; fails=$((fails + 1))
fi
# The other forks: the filed repro under --allow-undef on aarch64 (qemu) and PE (wine), each compiler
# built from this tree by $CC. A fork this box cannot run says so by name and fails the gate.
printf '%s' "$OVR" > "$D/x.cyr"
if command -v qemu-aarch64 > /dev/null 2>&1 && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null ) && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"
    ( cd "$ROOT" && "$D/cc_a64" --allow-undef < "$D/x.cyr" > "$D/x_a64" 2> /dev/null ) || true
    r=NOEMIT
    if [ -s "$D/x_a64" ]; then chmod +x "$D/x_a64"; r=0; ( ulimit -c 0; qemu-aarch64 "$D/x_a64" ) > /dev/null 2>&1 || r=$?; fi
    check "aarch64 (qemu): filed repro, --allow-undef (was 132)" 11 "$r"
else
    echo "  NOT RUN: the aarch64 row (qemu-aarch64 missing, or src/main_aarch64.cyr did not build)"; fails=$((fails + 1))
fi
if command -v wine > /dev/null 2>&1; then
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" --allow-undef < "$D/x.cyr" > "$D/x_pe.exe" 2> /dev/null ) || true
    r=NOEMIT
    if [ -s "$D/x_pe.exe" ]; then
        r=0
        ( cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine ./x_pe.exe > /dev/null 2>&1 ) || r=$?
    fi
    check "PE (wine): filed repro, --allow-undef (was 29, the trap)" 11 "$r"
else
    echo "  NOT RUN: the PE row (wine not installed)"; fails=$((fails + 1))
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: overload-arity-dispatch — arity-aware and consistent across assign / return / nested"
    exit 0
fi
echo "FAIL: overload-arity-dispatch — $fails assertion(s) failed"
exit 1
