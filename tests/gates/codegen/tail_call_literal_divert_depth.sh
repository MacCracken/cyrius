#!/bin/sh
# tests/gates/codegen/tail_call_literal_divert_depth.sh — 6.6.5
#
# ⛔ WHAT THIS PINS. `return f(args);` is emitted by PARSE_RETURN's own tail path, which writes
# the epilogue and a `jmp` instead of a call — so anything PARSE_FNCALL does to an ARGUMENT
# has to be replicated there or diverted back. Four times now it was neither (v6.3.36
# plain-struct params, v6.4.53 value-form SIMD params, v6.5.1 overload dispatch, v6.5.2
# integer-literal-into-cstring), and 6.6.5 found the fifth: a string literal into a `: Str`
# param was wrapped in `str_from()` by PARSE_FNCALL and by nothing else, so
#   var r = f("abcde");   -> 5
#   return f("abcde");    -> 0        (the callee got a raw cstr; a SILENT wrong value)
#
# ⭐ AND THE FIX'S OWN FIRST CUT BROKE A CORRECT PROGRAM, which is why this gate exists rather
# than just a value row. The divert was armed by a token-30 ANYWHERE inside the call's paren
# span, so `return deep(n - 1, str_from("abc"));` — whose literal is already wrapped by hand —
# lost its TAIL CALL. Losing TCO is not "a small cost": on a self-recursive tail call it turns
# bounded recursion into unbounded stack growth. Measured at the time: that program ran to
# completion on 6.6.4 and SIGSEGV'd (139) on the first cut.
#
# The criterion is DEPTH 1, and it is not a heuristic — it is PARSE_FNCALL's own criterion,
# read off `_try_push_str_literal_arg`, which opens `if (PEEKT(S) != 30) return 0` and so
# wraps a literal only when it is the FIRST token of an argument. Anything deeper is not
# wrapped by PARSE_FNCALL either, so diverting for it buys nothing and costs the tail call.
#
# ⚠ THE STACK LIMIT IS PINNED HERE, NOT INHERITED. Whether an untail-called recursion dies at
# a given depth depends on the host's `ulimit -s`, so a gate that used the ambient limit would
# be measuring the machine. Each run below is executed under an explicit small stack, which
# makes "did TCO survive" a decision the gate makes rather than one the box makes. MEASURED:
# the `tco_absent` recursion at this depth exits 3 under the ambient 8192K limit and SIGSEGVs
# under the pin — so if the pin ever stops applying, that row (not the two rows that matter)
# goes red first, and says so.
#
# Every expected value is computed by the shell a different way from the compiler's (a string
# length from `wc -c`, a recursion depth from arithmetic), never typed in beside the source.
#
# MUTATION LEDGER — each mutant BUILT as a full cycc from mutated source and RUN:
#   D1 record token 30 at ANY depth (the pre-review-round-3 code: drop `if (tc_depth == 1)`)
#        -> row tco_wrapped red: SIGSEGV 139 under the pinned stack. Rows divert_value and
#           divert_tail stay GREEN, which is exactly why the value rows alone were not enough.
#   D2 delete the `_fnt_strmask` divert block entirely (the 6.6.4 code)
#        -> rows divert_tail and both_positions red (tail position returns 0 for 5); row
#           tco_wrapped stays green. D1 and D2 redden DISJOINT rows — the gate needs both.
#   D3 arm the divert unconditionally (`tc_has_addr = 1` whenever `_tc_cfi >= 0`)
#        -> row tco_plain red: a tail call with NO literal anywhere loses TCO too.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
fail=0

STACK_KB=1024          # pinned, see the header
LIT=abc
WANT_LEN=$(printf %s "$LIT" | wc -c | tr -d ' ')
# A depth that cannot fit in STACK_KB without TCO by any plausible frame size: even a
# 16-byte frame would need 3 MB here, and cyrius frames are far larger than that.
DEPTH=$(( STACK_KB * 1024 / 16 + 1 ))

PRE='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
'

# run <name> <body>  -> sets $rc, $out; refuses to score an empty binary as a pass
run_src() {
    _n=$1; _src=$2
    printf '%s%s' "$PRE" "$_src" > "$T/$_n.cyr"
    "$CC" < "$T/$_n.cyr" > "$T/$_n.bin" 2> "$T/$_n.err" || true
    if [ ! -s "$T/$_n.bin" ]; then
        echo "  FAIL: tail_call_literal_divert [$_n]: did not build (an empty file 'runs' with exit 0 — scoring it would be a fake pass)"
        head -3 "$T/$_n.err" | sed 's/^/      /'; fail=1; rc=-1; out=""; return 1
    fi
    chmod +x "$T/$_n.bin"
    out=$( ulimit -s "$STACK_KB" 2>/dev/null; "$T/$_n.bin" 2>/dev/null )
    rc=$?
    return 0
}

# ── row tco_wrapped — THE REGRESSION ROW. The literal is nested inside str_from(), i.e. at
# paren depth 2, and is therefore NOT something PARSE_FNCALL would wrap. The tail call must
# survive. ───────────────────────────────────────────────────────────────────────────────
if run_src tco_wrapped "fn deep(n, s: Str): i64 {
    if (n == 0) { return str_len(s); }
    return deep(n - 1, str_from(\"$LIT\"));
}
fn main(): i64 { alloc_init(); return deep($DEPTH, str_from(\"$LIT\")); }
var e = main(); syscall(60, e);"; then
    if [ "$rc" = 139 ]; then
        echo "  FAIL: tail_call_literal_divert [tco_wrapped]: SIGSEGV at depth $DEPTH under a ${STACK_KB}K stack — the tail call was diverted for a literal at paren depth 2, which PARSE_FNCALL would not have wrapped"
        fail=1
    elif [ "$rc" != "$WANT_LEN" ]; then
        echo "  FAIL: tail_call_literal_divert [tco_wrapped]: exit $rc, expected $WANT_LEN (computed by wc -c)"; fail=1
    fi
fi

# ── row tco_plain — the control: the SAME recursion with no literal in the call at all must
# also survive. Without it, a compiler that simply never diverts would pass tco_wrapped and
# this gate would be measuring nothing about the divert. ─────────────────────────────────
if run_src tco_plain "fn deep2(n, s: Str): i64 {
    if (n == 0) { return str_len(s); }
    return deep2(n - 1, s);
}
fn main(): i64 { alloc_init(); return deep2($DEPTH, str_from(\"$LIT\")); }
var e = main(); syscall(60, e);"; then
    if [ "$rc" != "$WANT_LEN" ]; then
        echo "  FAIL: tail_call_literal_divert [tco_plain]: exit $rc (want $WANT_LEN) — a tail call with NO literal lost its TCO, so the harness is not measuring the literal"; fail=1
    fi
fi

# ── row tco_absent — the floor UNDER the two rows above: the same recursion written so that
# it is NOT a tail call must actually die under this stack limit. If it survives, the stack
# pin is not taking effect and neither of the rows above proves anything. ────────────────
if run_src tco_absent "fn deep3(n, s: Str): i64 {
    if (n == 0) { return str_len(s); }
    var r = deep3(n - 1, s);
    return r + 0;
}
fn main(): i64 { alloc_init(); return deep3($DEPTH, str_from(\"$LIT\")); }
var e = main(); syscall(60, e);"; then
    if [ "$rc" != 139 ]; then
        echo "  FAIL: tail_call_literal_divert [tco_absent]: a deliberately NON-tail recursion at depth $DEPTH exited $rc instead of SIGSEGV — the ${STACK_KB}K stack pin is not in effect, so tco_wrapped/tco_plain are vacuous"; fail=1
    fi
fi

# ── row divert_tail — the value half: a literal at depth 1 in TAIL position must still be
# wrapped, i.e. the divert must still fire where PARSE_FNCALL would have wrapped. ────────
if run_src divert_tail "fn slen(s: Str): i64 { return str_len(s); }
fn tailer(): i64 { return slen(\"$LIT\"); }
fn main(): i64 { alloc_init(); return tailer(); }
var e = main(); syscall(60, e);"; then
    if [ "$rc" != "$WANT_LEN" ]; then
        echo "  FAIL: tail_call_literal_divert [divert_tail]: exit $rc, expected $WANT_LEN — a depth-1 string literal in tail position was not wrapped in str_from()"; fail=1
    fi
fi

# ── row both_positions — the two call positions in ONE program must agree. This is the shape
# the defect actually had: `var r = f(lit)` and `return f(lit)` disagreeing in the same
# compiland, which no single-position test can see. ─────────────────────────────────────
if run_src both_positions "fn slen(s: Str): i64 { return str_len(s); }
fn tailer(): i64 { return slen(\"$LIT\"); }
fn main(): i64 { alloc_init(); var a = slen(\"$LIT\"); var b = tailer(); if (a != b) { return 100; } return a; }
var e = main(); syscall(60, e);"; then
    if [ "$rc" = 100 ]; then
        echo "  FAIL: tail_call_literal_divert [both_positions]: 'var r = f(lit)' and 'return f(lit)' returned DIFFERENT values in one program"; fail=1
    elif [ "$rc" != "$WANT_LEN" ]; then
        echo "  FAIL: tail_call_literal_divert [both_positions]: exit $rc, expected $WANT_LEN"; fail=1
    fi
fi

# ── row tco_wrong_position — the SECOND over-reach, and the one a depth rule cannot see. The
# callee's `: Str` param is argument 0; the literal is argument 1, whose strmask bit is CLEAR,
# so PARSE_FNCALL would not wrap it and the divert buys nothing. Found in a real ecosystem
# source (mneme's `_te_json_str` callers) as a byte difference against 6.6.4 that had no
# behavioural reason to exist. ───────────────────────────────────────────────────────────
if run_src tco_wrong_position "fn keyed(s: Str, k, tag): i64 {
    if (k == 0) { return str_len(s); }
    return keyed(s, k - 1, \"$LIT\");
}
fn main(): i64 { alloc_init(); var s = str_from(\"$LIT\"); return keyed(s, $DEPTH, \"$LIT\"); }
var e = main(); syscall(60, e);"; then
    if [ "$rc" = 139 ]; then
        echo "  FAIL: tail_call_literal_divert [tco_wrong_position]: SIGSEGV at depth $DEPTH — the tail call was diverted for a literal in argument 2, whose callee strmask bit is CLEAR, so the wrap would never have fired and the divert bought nothing"
        fail=1
    elif [ "$rc" != "$WANT_LEN" ]; then
        echo "  FAIL: tail_call_literal_divert [tco_wrong_position]: exit $rc, expected $WANT_LEN"; fail=1
    fi
fi

# ── row divert_position — the polarity control for it: when the literal IS in the Str-annotated
# position the divert MUST still fire, in tail position, or the wrap is lost and the value is
# silently wrong. Together these two rows pin the criterion from both sides; neither alone
# distinguishes "exact" from "too loose" or "too tight". ─────────────────────────────────
if run_src divert_position "fn two_arg(k, s: Str): i64 { return str_len(s) + k; }
fn tailer(): i64 { return two_arg(0, \"$LIT\"); }
fn main(): i64 { alloc_init(); return tailer(); }
var e = main(); syscall(60, e);"; then
    if [ "$rc" != "$WANT_LEN" ]; then
        echo "  FAIL: tail_call_literal_divert [divert_position]: exit $rc, expected $WANT_LEN — a literal in argument 1, whose callee annotates argument 1 \`: Str\`, was not wrapped"; fail=1
    fi
fi

# ── row source_criterion — DERIVED, not asserted from memory: the tail path must ask
# PARSE_FNCALL's OWN question, and PARSE_FNCALL's wrap must still be the question it asks. The
# two halves are checked against each other, so if either side moves this fails instead of
# drifting. ⚠ This row has already earned its place: it went red the moment the divert's
# predicate was tightened from "depth-1 literal" to "first token of an argument whose strmask
# bit is set", which is exactly the drift it exists to catch. ───────────────────────────────
grep -q '_tc_str_literal_arg(S, ti_after, _tc_cfi)' src/frontend/parse_fn.cyr \
  || { echo "  FAIL: tail_call_literal_divert [source_criterion]: the tail path no longer routes its \`: Str\` divert through _tc_str_literal_arg"; fail=1; }
TCB=$(sed -n '/^fn _tc_str_literal_arg/,/^}/p' src/frontend/parse_fn.cyr)
echo "$TCB" | grep -q 'if (t == 30)' \
  || { echo "  FAIL: tail_call_literal_divert [source_criterion]: _tc_str_literal_arg no longer tests for a string-literal token"; fail=1; }
echo "$TCB" | grep -q 'mask & (1 << pos)' \
  || { echo "  FAIL: tail_call_literal_divert [source_criterion]: _tc_str_literal_arg no longer tests the callee's per-ARGUMENT _fnt_strmask bit — it would divert calls whose literal is in a position the wrap never touches"; fail=1; }
echo "$TCB" | grep -q 'first = 1' \
  || { echo "  FAIL: tail_call_literal_divert [source_criterion]: _tc_str_literal_arg no longer tracks the FIRST token of each argument"; fail=1; }
FPB=$(sed -n '/^fn _try_push_str_literal_arg/,/^}/p' src/frontend/parse_fn.cyr)
echo "$FPB" | grep -q 'if (PEEKT(S) != 30) { return 0; }' \
  || { echo "  FAIL: tail_call_literal_divert [source_criterion]: _try_push_str_literal_arg no longer wraps only a literal at an argument's FIRST token — the tail path's predicate is now mis-matched"; fail=1; }
echo "$FPB" | grep -q '_fnt_strmask + fi \* 8) & (1 << argc)' \
  || { echo "  FAIL: tail_call_literal_divert [source_criterion]: _try_push_str_literal_arg no longer gates on the per-argument strmask bit — the tail path's predicate is now mis-matched"; fail=1; }

[ "$fail" = 0 ] && echo "  PASS: the tail path's \`: Str\` literal divert fires on exactly the arguments PARSE_FNCALL would wrap (an argument's FIRST token, and only where the callee's per-argument strmask bit is set) — both call positions agree, and an already-wrapped literal keeps its TCO under a pinned ${STACK_KB}K stack"
exit $fail
