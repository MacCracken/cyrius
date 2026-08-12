#!/bin/sh
# tests/gates/diagnostics/recursion_depth_bounded.sh — v6.5.19 (CVE-40)
#
# cycc must not SIGSEGV on deeply nested source. Recursive descent had NO depth bound,
# so hostile-but-tiny stdin exhausted the native stack.
#
# THE DEFECT. `fn f() { ` repeated 514 times SIGSEGV'd cycc. Five more shapes did the
# same at their own depths: nested blocks, nested `if`, nested `while`, parenthesised
# expressions, unary-minus chains and call chains. Reachable from ordinary untrusted
# input (`cat hostile.cyr | cycc`) — the CVE-32/33 threat model exactly.
#
# ⭐ PROVEN STACK EXHAUSTION, NOT A TABLE OVERFLOW. The crash depth scales LINEARLY with
# RLIMIT_STACK: last-OK 512 at `ulimit -s 8192`, 1026 at 16384, 2053 at 32768. That is
# ~16 KB of stack per nesting level for the `fn` vector. It matters which one it is: a
# table overflow is fixed by resizing the table, and resizing would have fixed nothing.
#
# ⛔ WHY NEITHER EXISTING WATCHDOG CAUGHT IT — the reason this is a THIRD mechanism and
# not a tuning change. `_wd_tick` fires when the parse STALLS (GTI stops advancing) and
# is gated on `_had_error`; `_wd_eof_tick` fires on reads PAST EOF. A deeply nested
# source advances GTI at every level and never reads past the end, so both stay inert
# all the way into the guard page. See `_rd_enter` in src/common/util.cyr.
#
# THE FIX: a depth counter at the FIVE recursive-descent chokepoints — PARSE_STMT,
# PARSE_FN_DEF, PEXPR, PARSE_TERM, PARSE_FACTOR — bounded at 256, plus raising the PE
# `SizeOfStackReserve` from 1 MB to 8 MB so the bound is reachable on Windows too.
#
# ⚠ IT TOOK FOUR PASSES TO COVER THE CLASS, WHICH IS THE LESSON. Bounding PARSE_STMT
# alone left THREE expression vectors live. Adding PEXPR left the unary chain live
# (unary recurses in PARSE_FACTOR, one tier BELOW PARSE_TERM). Adding PARSE_TERM left
# nested `fn` live (a nested definition re-enters PARSE_FN_DEF, never the statement
# wrapper). Each intermediate state looked fixed against the shape last tested — the
# "grep the SHAPE, not the operator" trap from v6.4.80. Hence axis 1 runs ALL SEVEN
# shapes every time rather than the one that motivated the patch.
#
# MUTATION PROOF (run at v6.5.19, RED then GREEN):
#   * raise the bound in `_rd_enter` from 256 to 100000000 (semantically "no bound",
#     leaving every call site and message intact) and rebuild cycc -> axis 1 RED on
#     nested-fn / blocks / if / while / parens / unary / call (the SIGSEGVs return),
#     axis 2 and axis 3 stay green. A textual mutation — renaming `_rd_enter`, deleting
#     the message — proves nothing here; the bound VALUE is the whole mechanism.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$CC" ] || { echo "FAIL: recursion-depth-bounded — build/cycc not built"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; exit 0; }

# The whole gate is one python run: it needs signal-vs-exit fidelity, which the shell
# cannot give (the shell maps a signal to 128+N and cannot distinguish it from a real
# exit code — the exact confusion that made cycc_parser_fuzz.sh's signal branch dead
# code for three minors).
python3 - "$CC" <<'PY'
import subprocess, sys

cc = sys.argv[1]
fails = 0

def check(label, expected, got):
    global fails
    if expected == got:
        print(f"  ok: {label} ({got})")
    else:
        print(f"  FAIL: {label} — expected {expected}, got {got}")
        fails += 1

def run(src, timeout=90):
    """-> (returncode, stderr). returncode < 0 means killed by a signal."""
    try:
        r = subprocess.run([cc], input=src.encode(), stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=timeout)
        return r.returncode, r.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""

# Every shape that crashed, plus the three that never did (so a regression in the
# always-fine ones is visible too).
SHAPES = {
    "nested fn":          lambda n: "fn f() { " * n,
    "nested blocks":      lambda n: "fn f() { " + "{ " * n + "}" * n + " }",
    "nested if":          lambda n: "fn f() { " + "if (1) { " * n + "}" * n + " }",
    "nested while":       lambda n: "fn f() { " + "while (1) { " * n + "}" * n + " }",
    "nested parens":      lambda n: "fn f() { return " + "(" * n + "1" + ")" * n + "; }",
    "unary minus chain":  lambda n: "fn f() { return " + "-" * n + "1; }",
    "call chain":         lambda n: "fn f() { return " + "g(" * n + "1" + ")" * n + "; }",
    "not chain":          lambda n: "fn f() { return " + "!" * n + "1; }",
    "index chain":        lambda n: "fn f() { return a" + "[0]" * n + "; }",
    "add chain":          lambda n: "fn f() { return 1" + " + 1" * n + "; }",
}

# ── AXIS 1 — no shape, at any depth, may die by a SIGNAL or hang.
# 1024 is just past the 8 MB crash point for the worst vector; 16384 and 65536 are far
# beyond every other one. Depth, not input size, is what matters: nested-fn at 1024 is
# only 9 KB of input.
print("axis 1 — no nesting shape kills cycc by a signal (SIGSEGV) or hangs:")
for name, gen in SHAPES.items():
    for n in (1024, 16384, 65536):
        rc, _ = run(gen(n))
        died = (rc == "TIMEOUT") or (isinstance(rc, int) and rc < 0)
        check(f"{name} @ {n} does not crash/hang", False, died)

# ── AXIS 2 — ⭐ ANTI-VACUOUS. The bound must not have been bought by refusing
# everything: ordinary, shallowly-nested, VALID source must still compile to exit 0.
# Without this row the gate is satisfiable by making cycc reject all input.
print("axis 2 — ⭐ ANTI-VACUOUS: ordinary valid source still COMPILES (exit 0):")
ok_src = """fn add(a, b) { return a + b; }
fn classify(x) {
    if (x > 10) {
        while (x > 10) { x = x - 1; }
        return add(x, 1);
    } else {
        if (x > 5) { return 2; }
        return -(-(x + 1));
    }
}
fn main() { return classify(3); }
var r = main();
"""
rc, err = run(ok_src)
check("a normal program compiles", 0, rc)
check("…and no depth diagnostic is printed", False, "nesting too deep" in err)

# Legitimately deep but plausible nesting (32 levels) must also be accepted — the bound
# is 256 precisely so real code never meets it.
rc, err = run("fn f() { " + "if (1) { " * 32 + "}" * 32 + " }\nfn main() { return 0; }\nvar r = main();\n")
check("32 levels of real nesting still accepted", 0, rc)
check("…and no depth diagnostic at 32 levels", False, "nesting too deep" in err)

# ── AXIS 3 — the refusal is a clean, located DIAGNOSTIC, not a silent death.
# A bounded parser that exits 1 with nothing on stderr would pass axis 1 while being
# useless to a user, and `cyrius lint`'s pre-pass classifies on the MESSAGE.
print("axis 3 — over-deep input is REFUSED with a located diagnostic, not killed:")
rc, err = run(SHAPES["nested fn"](1024))
check("exits 1 (graceful), not a signal", 1, rc)
check("names the depth bound", True, "nesting too deep" in err)
check("carries an error: prefix", True, err.startswith("error:") or "\nerror:" in err)

print("")
if fails == 0:
    print("PASS: recursion-depth-bounded — recursive descent is bounded on every tier")
    sys.exit(0)
print(f"FAIL: recursion-depth-bounded — {fails} assertion(s) failed")
sys.exit(1)
PY
rc=$?
exit $rc
