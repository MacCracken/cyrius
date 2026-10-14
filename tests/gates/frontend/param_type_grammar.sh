#!/bin/sh
# tests/gates/frontend/param_type_grammar.sh — 6.7.11
#
# A FN PARAMETER'S TYPE IS READ WHOLE, BY ONE GRAMMAR IN BOTH PASSES: the trait-signature reader's
# (`_trs_type`, 6.7.8) plus a bare `*fn` (the user's decision, 2026-10-13: (b)) — any number of `*`,
# then `u128`, a tuple, `*fn( .. )` with an optional `: T`, a bare `*fn` (accepted since 6.7.7), or a
# name with its `<..>`. Anything else is refused by name, once: "expected a type for parameter 'a', got
# '+'". Both scans stepped ONE token after at most one `*` (`_param_type_step` / `_param_type_step_q`),
# so `fn f(p: **i64)` was "expected ')', got identifier 'i64'" and `*fn(i64): i64` "expected ')', got
# '('", while `fn f(a: 5)` / `(a: +)` / `(a: "s")` compiled with the token skipped (rc 0, exit 42).
# Measured on 6.7.4 - 6.7.10, x86_64 (the parse is shared by every target).
# Filed: docs/development/issues/2026-10-10-param-type-annotation-reads-one-token.md
#
#   RA the filed repro (a) verbatim: refused, exactly its 4 error lines (`5`, `+`, `;`, a string), each
#      "expected a type for parameter", no binary; RX the same under --syntax-only (lint's pre-pass)
#   RB the filed repro (b) verbatim exits 42 on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm)
#      and PE (wine)
#   G  each refused shape: exactly one error line holding its text — every token class (a number, an
#      operator, `;`, a string, a keyword, `)`, a lone `*`, `fn` with no `*`), a two-token non-type
#      (`-1`, `5 + 3`) with no cascade, a refused type before a default / mid-list / in an impl method /
#      in a generic with two instances (once) / on a fn a FORWARD call reaches (no arity cascade), and
#      what the reader checks that no other arm does: a name behind two `*`, the names and tokens inside
#      `*fn( .. )`, `**( .. )`, `**[T]`
#   P  pass 1 and pass 2 agree on the count (`_pd_pc_check`): a forward call into `**T` / `*fn( .. ): T`
#      parameters with defaults, by position and by name, runs
#   T  tests/tcyr/crossos/param_type_pointer_forms.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#
# MUTATION LEDGER (2026-10-13; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<its 2-stage mutant>; measured):
#   M0  the fix reverted (the slot-open parameter branch)  -> RED 39: RA RX (rc 0); RB on every leg ("expected
#                                                             ')', got identifier 'i64'"); G1-G4 G7 G17-G21
#                                                             (compiled); G5 G6 G8-G16 (a cascade, or "expected
#                                                             ')'" in place of the refusal); P1 P2 (the arity);
#                                                             T on every leg
#   M1  pass 1 steps one token again (`_param_type_step_q`) -> RED P1 P2 and T on every leg ("'pf_fwd3' expects
#                                                             1 argument, got 2": the passes count apart)
#   M2  a refused token stepped alone (no `_pty_skip`)     -> RED G5 G6 G8 G9 (a second error)
#   M3  the reader checks no name (`_pty_name` a no-op)    -> RED G12 G13 G14 (they compile)
#   M4  `_pty_err` without its `_tn_once`                  -> RED G18 (one error per instance)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=param_type_grammar
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
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
ulimit -c 0 2>/dev/null

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/param_type_pointer_forms.tcyr
RA=docs/development/issues/repros/2026-10-10-param-type-annotation-reads-one-token-a-non-type-accepted.cyr
RB=docs/development/issues/repros/2026-10-10-param-type-annotation-reads-one-token-b-double-pointer.cyr
for f in "$TC" "$RA" "$RB"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=23
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi

# build_leg <leg> <src> <out>: compile only; 0 = built.
build_leg() {
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3" 2> "$3.err" ;;
    esac
}
# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    if [ "$1" = pe ]; then build_leg pe "$2" "$3.exe" || return 0
    else build_leg "$1" "$2" "$3" || return 0; fi
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"

# refused <name> <fragment> <what> <body>: compile fails with exactly one error line holding the
# fragment, and no binary
refused() {
    printf '%b' "$4" > "$D/$1.cyr"
    rc=0; timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    n=$(grep -c '^error' "$D/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want the refusal \"$2\""
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want exactly 1: $(grep '^error' "$D/$1.err" | head -3 | tr '\n' '|')"
    elif ! grep '^error' "$D/$1.err" | grep -qF -- "$2"; then bad "$3: wrong refusal: $(grep '^error' "$D/$1.err" | head -1)"
    elif [ -s "$D/$1.bin" ]; then bad "$3: refused, but a binary was written"
    else ok "$3"; fi
}
# exits <name> <want> <what> <body>: compiles (x86_64) and exits <want>
exits() {
    printf '%b' "$4" > "$D/$1.cyr"
    rc=0; timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$D/$1.err" | head -1)"; return; fi
    chmod +x "$D/$1.bin"; got=0; timeout 10 "$D/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
H='include "lib/syscalls.cyr"\n'
M='fn main(): i64 { return 0; }\nvar rc = main();\nsyscall(60, rc);\n'

echo "RA. the filed repro (a), verbatim: refused, its 4 non-type tokens each once"
ra_check() {   # <tag> <flags>
    rc=0; timeout 60 "$CC" $2 < "$RA" > "$D/ra$1.bin" 2> "$D/ra$1.err" || rc=$?
    n=$(grep -c '^error' "$D/ra$1.err" || true)
    k=$(grep '^error' "$D/ra$1.err" | grep -c 'expected a type for parameter' || true)
    if [ "$rc" -eq 0 ]; then bad "$1: compiled (rc 0; it exited 42 through 6.7.10) — want 4 refusals"
    elif [ "$n" -ne 4 ] || [ "$k" -ne 4 ]; then bad "$1: $n error lines ($k named), want 4: $(grep '^error' "$D/ra$1.err" | head -5 | tr '\n' '|')"
    elif [ -s "$D/ra$1.bin" ]; then bad "$1: refused, but a binary was written"
    else ok "$1: rc $rc, 4 refusals: $(grep '^error' "$D/ra$1.err" | sed 's/.*got //' | tr '\n' ' ')"; fi
}
ra_check RA ""
ra_check RX --syntax-only

echo "RB. the filed repro (b), verbatim: \`fn f(p: **i64)\` compiles and exits 42"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'RB_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$RB" "$D/rb_$n"
    if [ "$RC" -eq -1 ]; then bad "RB $leg: did not build: $(grep -h -m1 'error' "$D/rb_$n.err" "$D/rb_$n.exe.err" 2>/dev/null | head -1)"
    elif [ "$RC" -eq 42 ]; then ok "RB $leg: exit 42"
    else bad "RB $leg: exit $RC, want 42"; fi
done

echo "G. refused by name, exactly once"
refused G1 "expected a type for parameter 'a', got number 5" "G1 a number" "${H}fn f(a: 5): i64 { return a; }\n${M}"
refused G2 "expected a type for parameter 'a', got '+'" "G2 an operator" "${H}fn f(a: +): i64 { return a; }\n${M}"
refused G3 "expected a type for parameter 'b', got ';'" "G3 a ';' (second parameter)" "${H}fn f(a: i64, b: ;): i64 { return a + b; }\n${M}"
refused G4 "expected a type for parameter 'a', got string" "G4 a string" "${H}fn f(a: \"s\"): i64 { return a; }\n${M}"
refused G5 "expected a type for parameter 'a', got '-'" "G5 \`a: -1\` (two tokens, no cascade)" "${H}fn f(a: -1): i64 { return a; }\n${M}"
refused G6 "expected a type for parameter 'a', got number 5" "G6 \`a: 5 + 3, b: i64\` (no cascade)" "${H}fn f(a: 5 + 3, b: i64): i64 { return b; }\n${M}"
refused G7 "expected a type for parameter 'a', got if" "G7 a keyword" "${H}fn f(a: if): i64 { return a; }\n${M}"
refused G8 "expected a type for parameter 'a', got ')'" "G8 no type (\`a:\`)" "${H}fn f(a:): i64 { return a; }\n${M}"
refused G9 "expected a type for parameter 'a', got ')'" "G9 a lone \`*\`" "${H}fn f(a: *): i64 { return a; }\n${M}"
refused G10 "expected a type for parameter 'cb', got fn" "G10 \`fn( .. )\` with no \`*\`" "${H}fn f(cb: fn(i64)): i64 { return 0; }\n${M}"
refused G11 "expected a type for parameter 'cb', got number 5" "G11 a number inside \`*fn( .. )\`" "${H}fn f(cb: *fn(5): i64): i64 { return 0; }\n${M}"
refused G12 "unknown type 'Nope' for parameter 'cb'" "G12 an unknown name inside \`*fn( .. )\`" "${H}fn f(cb: *fn(Nope): i64): i64 { return 0; }\n${M}"
refused G13 "unknown type 'Nope' for parameter 'cb'" "G13 an unknown \`*fn( .. )\` result" "${H}fn f(cb: *fn(i64): Nope): i64 { return 0; }\n${M}"
refused G14 "unknown type 'Nope' for parameter 'p'" "G14 an unknown name behind two \`*\`" "${H}fn f(p: **Nope): i64 { return 0; }\n${M}"
refused G15 "a tuple type cannot be a pointer target" "G15 \`**( .. )\`" "${H}fn f(p: **(i64, i64)): i64 { return 0; }\n${M}"
refused G16 "a pointer to a slice is not a type" "G16 \`**[u8]\`" "${H}fn f(p: **[u8]): i64 { return 0; }\n${M}"
refused G17 "expected a type for parameter 'a', got number 5" "G17 an impl method" "${H}struct P { x; }\nimpl P {\n    fn m(self, a: 5): i64 { return a; }\n}\n${M}"
refused G18 "expected a type for parameter 'a', got number 5" "G18 a generic with two instances (once)" "${H}struct P { x; }\nfn g<T>(a: 5, b: T): i64 { return a; }\nfn main(): i64 { var p = P { 1 }; return g(1, 2) + g(1, p); }\nvar rc = main();\nsyscall(60, rc);\n"
refused G19 "expected a type for parameter 'a', got '+'" "G19 a forward call to it (no arity cascade)" "${H}fn main(): i64 { return f(1, 2); }\nfn f(a: +, b: i64): i64 { return a + b; }\nvar rc = main();\nsyscall(60, rc);\n"
refused G20 "expected a type for parameter 'a', got number 5" "G20 before a default" "${H}fn f(a: 5 = 3): i64 { return a; }\n${M}"
refused G21 "expected a type for parameter 'b', got number 7" "G21 mid-list" "${H}fn f(a: i64, b: 7, c: i64): i64 { return a + c; }\n${M}"

echo "P. pass 1 and pass 2 count the same parameters: forward calls with defaults"
exits P1 42 "P1 \`*fn(i64): i64\`, defaults, by position and by name" "${H}fn inc(x: i64): i64 { return x + 1; }\nfn main(): i64 { return ap(&inc, 5) + ap(&inc, 5, k: 6); }\nfn ap(cb: *fn(i64): i64, x: i64, k = 1): i64 { return fncall1(cb, x) * k; }\nvar rc = main();\nsyscall(60, rc);\n"
exits P2 42 "P2 \`**i64\` then \`***i64\`, defaults" "${H}fn main(): i64 { var x = 40; var p: *i64 = &x; var pp: **i64 = &p; var ppp: ***i64 = &pp; return dd(pp, ppp) + dd(pp, ppp, k: 2); }\nfn dd(p: **i64, q: ***i64, k = 1): i64 { return **p + ***q * k - 79; }\nvar rc = main();\nsyscall(60, rc);\n"

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -h -m1 'error' "$D/t_$n.err" "$D/t_$n.exe.err" 2>/dev/null | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a parameter's type is read whole by one grammar: the filed repros (RA RX RB), 21 refusals each once (G), the pass agreement (P) and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
