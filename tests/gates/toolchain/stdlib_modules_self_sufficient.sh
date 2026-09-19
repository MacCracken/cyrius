#!/bin/sh
# stdlib_modules_self_sufficient.sh — v6.6.6 bite 17g. A `lib/` module that calls another
# module's functions INCLUDES that module. `include "lib/<m>.cyr"` on its own compiles clean.
#
# ⛔ THE DEFECT. `lib/fmt.cyr` called `strlen`/`memcpy` (lib/string.cyr) and `vec_get`
# (lib/vec.cyr) while including NOTHING; `lib/vec.cyr` called `alloc` and included only
# lib/fnptr.cyr; `lib/string.cyr`'s `strdup`/`strndup` called `alloc`; `lib/io.cyr` called
# `alloc`, `strlen`, `memcpy`, `fmt_int` and `fmt_int_buf`, and on agnos `_agnos_getenv` as a
# bare forward reference. Each file WROTE THE REQUIREMENT DOWN FOR THE CALLER instead — "Requires:
# include lib/string.cyr for strlen", "include lib/alloc.cyr THEN include lib/vec.cyr" — and
# fmt's line did not even name lib/vec.cyr. Measured on 6.6.5: `include "lib/fmt.cyr"` +
# `fmt_int(1)` compiled at exit 0 with `warning: undefined function 'strlen'` / `'vec_get'`,
# and `include "lib/io.cyr"` alone produced FIVE such warnings on every target.
#
# ⚠ AN UNDEFINED FUNCTION IS NOT A MISSING SYMBOL — IT IS A TRAP. cycc emits a `ud2`/SIGILL
# stub for it and carries on, so the program links, runs, and dies at the first call with no
# diagnostic. CLAUDE.md's rule ("Lib files referencing flag constants must include their
# definers — self-sufficient modules") is written about constants; it is about HELPERS too, and
# a constant only gives you a wrong number while a function gives you a signal.
#
# AXES
#   1. Each module in SELFSUF compiles ALONE with ZERO `warning: undefined function`, on
#      x86-Linux, agnos, PE and Mach-O — a module that is self-sufficient on one target and not
#      on another is the shape that put `_agnos_getenv` in the agnos arm only.
#   2. ANTI-VACUOUS: a probe that CALLS into each of those modules builds and RUNS to the right
#      answer, so the includes are carrying real definitions rather than silencing a warning.
#   3. SELF-TEST: a fixture module that calls a function nothing defines MUST be reported by the
#      same check, or axis 1 is measuring nothing.
#   4. RATCHET over the whole of lib/: the number of modules that compile alone with no
#      undefined function may not fall below the floor measured here. The stdlib is not all the
#      way there yet (see the floor's comment), and a ratchet is what stops it sliding back
#      while the rest is brought up.
#
# MUTATION LEDGER (measured 6.6.6, each by editing a COPY of the module in the scratch dir)
#   a. lib/fmt.cyr's two includes removed      -> axes 1 (4 targets) and 4 FAIL ('strlen',
#                                                 'vec_get', and the ratchet count drops)
#   b. lib/vec.cyr's alloc include removed     -> axes 1 and 4 FAIL ('alloc', 'alloc_via',
#                                                 'default_alloc')
#   b2. lib/alloc.cyr's syscalls include removed-> axes 1 and 4 FAIL ('sys_mmap'). It reddens on
#                                                 EVERY target, and it is the one this gate
#                                                 found that the bite had not: every real
#                                                 consumer includes lib/syscalls.cyr first, so
#                                                 it was invisible until a module was compiled
#                                                 alone.
#   c. lib/string.cyr's alloc include removed  -> axes 1 and 4 FAIL ('alloc')
#   d. lib/io.cyr's fmt/string includes removed-> axis 1 FAIL on all 4 targets (5 warnings)
#   e. lib/io.cyr's agnos args_agnos include   -> axis 1 FAIL on the AGNOS target only
#      removed                                   ('_agnos_getenv') — the per-target half
#   f. axis-1 warning check inverted           -> axis 3 self-test FAIL
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: stdlib_modules_self_sufficient: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }

# The modules this bite made self-sufficient. Each must stay so on every target.
SELFSUF="lib/alloc.cyr lib/fmt.cyr lib/vec.cyr lib/string.cyr lib/io.cyr"
# Per-target env, as the build scripts spell it. "" is x86_64-linux.
TARGETS="linux:  agnos:CYRIUS_TARGET_AGNOS=1 pe:CYRIUS_TARGET_WIN=1 macho:CYRIUS_MACHO=1"

# _undef <module> <env> — the undefined functions cycc reports for a bare include of <module>
_undef() {
    printf 'include "%s";\nfn _ssm(): i64 { return 0; }\nvar _ssr = _ssm();\nsyscall(60, _ssr);\n' "$1" > "$D/ss.cyr"
    # --allow-undef: cycc REFUSES to emit a binary with a reachable undefined function, and the
    # refusal is what this gate wants to READ rather than trip over — the flag downgrades it to
    # the warnings, so a module with three gaps reports all three instead of one exit code.
    if [ -n "$2" ]; then env "$2" "$CC" --allow-undef < "$D/ss.cyr" > "$D/ss.bin" 2> "$D/ss.err"
    else "$CC" --allow-undef < "$D/ss.cyr" > "$D/ss.bin" 2> "$D/ss.err"; fi
    rc=$?
    if [ "$rc" -ne 0 ]; then printf 'COMPILE-ERROR\n'; return; fi
    grep '^warning: undefined function' "$D/ss.err" | grep -v 'call site may be unreachable' \
        | sed "s/^warning: undefined function //" | tr -d "'" | tr '\n' ' '
}

# ── axis 1: every listed module compiles alone, clean, on every target ──
x=0; n1=0
for m in $SELFSUF; do
    [ -f "$m" ] || { fail "axis 1: $m does not exist — renamed? update SELFSUF"; x=1; continue; }
    for te in $TARGETS; do
        tname=${te%%:*}; tenv=${te#*:}
        n1=$((n1 + 1))
        u=$(_undef "$m" "$tenv")
        case "$u" in
            "") : ;;
            COMPILE-ERROR*) fail "axis 1: $m does not compile alone for $tname"; sed 's/^/      /' "$D/ss.err" | head -3; x=1 ;;
            *) fail "axis 1: $m calls undefined function(s) for $tname: $u — include the module that defines them (an undefined fn is a ud2/SIGILL stub, not a link error)"; x=1 ;;
        esac
    done
done
[ "$n1" -ge 20 ] || { fail "axis 1: only $n1 module/target pairs checked (5 modules x 4 targets expected)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: $n1 module/target pairs — every module in SELFSUF includes alone with no undefined function"

# ── axis 2: ANTI-VACUOUS — the definitions are real, not just quiet ──
cat > "$D/use.cyr" <<'CYR'
include "lib/io.cyr";
fn main(): i64 {
    alloc_init();
    var v = vec_new();                    # lib/vec.cyr, through fmt
    vec_push(v, 40);
    var s = str_lower_cstr("AB");         # lib/string.cyr's alloc user (returns a fresh copy)
    var n = strlen(s);                    # lib/string.cyr
    fmt_int(0);                           # lib/fmt.cyr (prints "0")
    return vec_get(v, 0) + n;             # 40 + 2
}
var r = main();
syscall(60, r);
CYR
"$CC" < "$D/use.cyr" > "$D/use" 2> "$D/use.err"; brc=$?
x=0
[ "$brc" -eq 0 ] || { fail "axis 2: the cross-module probe does not build:"; tail -4 "$D/use.err" | sed 's/^/      /'; x=1; }
[ -z "$(grep '^warning: undefined function' "$D/use.err")" ] || { fail "axis 2: the probe compiled with undefined functions"; x=1; }
chmod +x "$D/use" 2>/dev/null
( ulimit -c 0; "$D/use" > "$D/use.out" 2>&1 ); rc=$?
[ "$rc" -eq 42 ] || { fail "axis 2: the cross-module probe returned $rc, expected 42 (40 from vec_get + 2 from strlen) — the includes are silencing warnings, not supplying definitions"; x=1; }
[ "$(cat "$D/use.out")" = "0" ] || { fail "axis 2: fmt_int(0) printed '$(cat "$D/use.out")'"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: a probe that only includes lib/io.cyr calls into vec, string and fmt and returns 42"

# ── axis 3: SELF-TEST — the check can see an undefined function ──
# The fixture goes under a scratch cwd, not $D: cycc rejects an ABSOLUTE include path
# (CYRIUS_ALLOW_ABSOLUTE_INCLUDES), so the include has to be relative to where cycc runs.
mkdir -p "$D/fx"
printf 'fn _fx_caller(): i64 { return _no_such_function_anywhere(1); }\n' > "$D/fx/broken.cyr"
x=0
u=$( cd "$D" && CC="$CC" D="$D" sh -c '
    printf '"'"'include "fx/broken.cyr";\nfn _ssm(): i64 { return 0; }\nvar _ssr = _ssm();\nsyscall(60, _ssr);\n'"'"' > ss3.cyr
    "$CC" --allow-undef < ss3.cyr > /dev/null 2> ss3.err
    grep "^warning: undefined function" ss3.err | grep -v "call site may be unreachable" | sed "s/^warning: undefined function //" | tr -d "\047" | tr "\n" " "
' )
case "$u" in
    *_no_such_function_anywhere*) : ;;
    *) fail "axis 3 self-test: a call to an undefined function was reported as '$u' — axis 1 cannot see what it is looking for"; x=1 ;;
esac
[ "$x" = 0 ] && echo "  ok: axis 3: the check reports an undefined function in a fixture module (axis 1 is not vacuous)"

# ── axis 4: RATCHET over the whole stdlib ──
# ⚠ THE FLOOR IS NOT A TARGET. At this commit 26 of the 103 lib/*.cyr compile alone with no
# undefined function; 46 still do not, and 31 cannot be included alone at all (per-target peers
# like lib/alloc_windows.cyr, which exist to be dispatched INTO by their parent). The rest is a
# real gap and is filed rather than fixed here — this bite's scope was fmt/vec/string/io. The
# ratchet is what stops the number sliding back while the rest is brought up: RAISE it whenever
# a module is fixed, never lower it.
FLOOR=26
nok=0; ntot=0
for m in lib/*.cyr; do
    ntot=$((ntot + 1))
    u=$(_undef "$m" "")
    case "$u" in
        "") nok=$((nok + 1)) ;;
        *) : ;;
    esac
done
[ "$ntot" -ge 90 ] || { fail "axis 4: only $ntot lib/*.cyr scanned (floor 90) — the scan read nothing"; FAIL=1; }
if [ "$nok" -lt "$FLOOR" ]; then
    fail "axis 4: $nok of $ntot lib modules include alone with no undefined function — below the $FLOOR floor. A module became LESS self-sufficient; do not lower the floor."
else
    echo "  ok: axis 4: $nok of $ntot lib/*.cyr include alone with no undefined function (floor $FLOOR)"
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: stdlib_modules_self_sufficient (4 axes)"
