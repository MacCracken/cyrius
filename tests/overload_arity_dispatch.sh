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
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

# Compile $1 (source text) and echo the run exit code, or NOEMIT if no binary.
run() {
    printf '%s' "$1" > "$D/p.cyr"
    ( cd "$ROOT" && cat "$D/p.cyr" | "$CC" > "$D/p.bin" 2>"$D/p.err" ) || true
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

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: overload-arity-dispatch — arity-aware and consistent across assign / return / nested"
    exit 0
fi
echo "FAIL: overload-arity-dispatch — $fails assertion(s) failed"
exit 1
