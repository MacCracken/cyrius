#!/bin/sh
# tests/gates/frontend/silent_values_checked.sh — 6.7.6 (Break 1, lane D)
#
# SILENT WRONG VALUES (the user's decisions, 2026-10-08 — roadmap "Break 1 decisions"):
#   F  `var x: f32 = <an f64 value>` ROUNDS to f32 (a local, a global in either zone, a for-init),
#      as a 6.7.4 `f32[N]` list element does; it stored the f64 bits, which read as 0.0. The
#      runtime half is tests/tcyr/crossos/f32_scalar_init_rounds.tcyr (A rows).
#   I  CYRIUS_IR=3 keeps the x86 f32 conversions (`f32_from`, `f32_to`, and the initializer's): their
#      raw bytes were not IR-recorded, so the opt-in pass forwarded rax across them (a prerequisite
#      of F under IR=3; pre-existing since the builtins landed).
#   P  a top-level `var v = pair_fn();` is REFUSED by name, with the fn-body rule's wording (v6.5.67):
#      it kept the tag and dropped the payload, silently — in the declaration zone (the replay's
#      `_gvi_expr`) and after the first statement (PARSE_VAR) alike; the destructure still binds.
#   R  a name DECLARED an integer (a local, a parameter — #inline too —, a closure capture, a global)
#      as the whole first argument routes to the base's `_int` overload: `println(n)` with `n: i64`
#      ran println's cstring body over 42 (rc 139). The runtime half is
#      tests/tcyr/crossos/int_name_routes_int_overload.tcyr (A rows).
#   O  `OP=` on a SIMD vector (a local or parameter), a TYPED array (`var a: T[N]`, any T, local, global
#      or static) or a slice is REFUSED by name, as 6.7.5 refused it on a struct: each integer-operated
#      on the first word (`a += 8` added to a[0], `s += 1` to `.ptr`), as a statement and a for step.
#      The element forms, the slice fields and a bare `var b[N]` (not decided) keep working.
#   U  `OP=` on a u128 computes exactly as `a = a OP x` does (not refused) — all 16 bytes, every
#      operator: tests/tcyr/crossos/u128_compound_matches_long_form.tcyr (A rows). Neither spelling
#      carries into the high word (see the lane report: the decision's "carry included" premise).
#   A  ANTI-VACUOUS: each crossos tcyr on x86_64 (default, CYRIUS_IR=3, CYRIUS_DCE=1) and with
#      compilers built from this tree on aarch64 (qemu), cx (cxvm) and PE (wine, a private prefix),
#      with its full assertion count.
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-08):
#   (filled in below as each row lands)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=silent_values_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 env ${2:-} "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
exits() {   # <name> <want> <what> <source> [ENV=V]: builds (under ENV), runs, exits <want>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1" "${5:-}"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
refused() {   # <name> <message fragment> <what> <source>: refused once, with the fragment
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}

# ── P: a `: stack` pair bound to ONE global is refused, as in a fn body ─────────────────────────
PR='include "lib/syscalls.cyr"\nenum R: stack { ROk(v); RErr(e); }\nfn mk(n) { if (n == 0) { return RErr(99); } return ROk(n); }\nfn mkg<T>(n: T) { return ROk(n); }\nstruct Pt { x; }\nfn Pt_mk(self: Pt, n) { return ROk(n); }\nfn one(): i64 { return 7; }\n'
BB="a \`: stack\` enum returns two values — bind both: \`var tag, val = f();\`"
refused p01 "$BB" "P1: \`var v = mk(42);\` in the declaration zone" "${PR}var v = mk(42);\nsyscall(60, v);\n"
refused p02 "$BB" "P2: ... after the first top-level statement" "${PR}syscall(1, 1, \"\", 0);\nvar v = mk(42);\nsyscall(60, v);\n"
refused p03 "$BB" "P3: ... annotated \`var v: i64 = mk(42);\`" "${PR}var v: i64 = mk(42);\nsyscall(60, v);\n"
refused p04 "$BB" "P4: ... the generic spelling \`mkg<i64>(..)\`" "${PR}var v = mkg<i64>(42);\nsyscall(60, v);\n"
refused p05 "$BB" "P5: ... the method spelling \`p.mk(..)\`" "${PR}var p = Pt { 1 };\nsyscall(1, 1, \"\", 0);\nvar v = p.mk(42);\nsyscall(60, v);\n"
refused p06 "$BB" "P6: inside a fn (the v6.5.67 rule, unchanged)" "${PR}fn main(): i64 { var v = mk(42); return v; }\nsyscall(60, main());\n"
exits p07 42 "P7: the top-level destructure binds both (both zones)" "${PR}var t, v = mk(42);\nsyscall(1, 1, \"\", 0);\nvar t2, v2 = mk(0);\nvar o = one();\nsyscall(60, v + t + (t2 - 1) * 100 + (v2 - 99) + o - 7);\n"
exits p08 7 "P8: a one-value global from a plain fn is untouched" "${PR}var o = one();\nsyscall(1, 1, \"\", 0);\nvar o2 = one();\nsyscall(60, o * o2 / 7);\n"

# ── O: `OP=` on a vector, a typed array or a slice is refused by name ──────────────────────────
OS='struct P { x; y; }\nvar GA: i64[4];\n'
OV="compound assignment to vector"
OA="compound assignment to array"
OL="compound assignment to slice"
refused o01 "$OV 'v' is refused - a vector value is not an integer or a float" "O1: \`v += 1\` on an i64v2 local" "${OS}fn main(): i64 { var v: i64v2 = 0; v += 1; return 0; }\nsyscall(60, main());\n"
refused o02 "$OV 'v'" "O2: ... on an f64v2 parameter" "${OS}fn f(v: f64v2): i64 { v -= 1.0; return 0; }\nsyscall(60, 0);\n"
refused o03 "$OA 'a' is refused - an array is not an integer or a float (index an element: \`a[i] += b\`)" "O3: \`a += 8\` on a \`var a: i64[4]\` local" "${OS}fn main(): i64 { var a: i64[4]; a += 8; return 0; }\nsyscall(60, main());\n"
refused o04 "$OA 'fa'" "O4: ... an f64[2] local" "${OS}fn main(): i64 { var fa: f64[2]; fa += 1.5; return 0; }\nsyscall(60, main());\n"
refused o05 "$OA 'pa'" "O5: ... a struct-element array" "${OS}fn main(): i64 { var pa: P[2]; pa |= 1; return 0; }\nsyscall(60, main());\n"
refused o06 "$OA 'GA'" "O6: ... a typed-array global, at top level" "${OS}GA += 8;\nsyscall(60, 0);\n"
refused o07 "$OA 'a'" "O7: ... a for step" "${OS}fn main(): i64 { var a: i64[4]; var i = 0; for (i = 0; i < 2; a += 8) { i = i + 1; } return 0; }\nsyscall(60, main());\n"
refused o08 "$OA 'big'" "O8: ... an array over the frame budget (static storage)" "${OS}fn main(): i64 { var big: u8[130000]; big >>>= 1; return 0; }\nsyscall(60, main());\n"
refused o09 "$OL 's' is refused - a slice is not an integer or a float (step a field: \`s.ptr += n\`, \`s.len -= n\`)" "O9: \`s += 1\` on a slice local" "${OS}fn main(): i64 { var s: [u8] = 0; s += 1; return 0; }\nsyscall(60, main());\n"
printf '%b' "${OS}fn main(): i64 { var a: i64[4]; a += 1; var s: [u8] = 0; s -= 1; return 0; }\nsyscall(60, main());\n" > "$T/o10.cyr"
build o10
if [ "$(grep -c '^error' "$T/o10.err")" -eq 2 ]; then ok "O10: an array then a slice: both reported (the parse stays in sync)"
else bad "O10: want 2 error lines: $(grep '^error' "$T/o10.err" | tr '\n' '|')"; fi
exits o11 21 "O11: the element forms and the slice fields still work" "${OS}fn main(): i64 { var a: i64[4]; a[0] = 1; a[0] += 8; var d: u8[4]; var s: [u8] = 0; store64(&s, &d); store64(&s + 8, 4); s.ptr += 1; s.len -= 2; return a[0] + (s.ptr - &d) * 10 + s.len; }\nsyscall(60, main());\n"
exits o12 9 "O12: a bare \`var b[16]\` keeps its OP= (not a typed array; not decided)" "fn main(): i64 { var b[16]; store64(&b, 1); b += 8; return load64(&b); }\nsyscall(60, main());\n"

# ── I: CYRIUS_IR=3 and the x86 f32 conversions ──────────────────────────────────────────────────
I1='fn lo32(p): i64 { return load32(p) & 0xFFFFFFFF; }\nfn main(): i64 {\n    var y: f64 = 1.5;\n    var fy: f32 = f32_from(y);\n    var ok = 0;\n    if (lo32(&fy) == 0x3FC00000) { ok = ok + 1; }\n    var m: f32 = f32_from(1.5);\n    var m2: f32 = m * f32_from(2.0);\n    if (f32_to(m2) == 0x4008000000000000) { ok = ok + 2; }\n    var g: f32 = y;\n    if (lo32(&g) == 0x3FC00000) { ok = ok + 4; }\n    return ok;\n}\nsyscall(60, main());\n'
exits i1 7 "I1: f32_from / f32_to / an f32 initializer under CYRIUS_IR=3" "$I1" CYRIUS_IR=3
exits i2 7 "I2: ... the same program, default pipeline" "$I1"

# ── A: each crossos tcyr, every leg, with its full assertion count ─────────────────────────────
X86_LEGS="plain IR3 DCE"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"
    else bad "A0: could not build src/main_aarch64.cyr"; fi
fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then chmod +x "$T/cc_cx" "$T/cxvm"
else bad "A0: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
tcyr_ok() {   # <label> <output file> <exit> <want>
    if [ "$3" -eq 0 ] && grep -q "^$4 passed, 0 failed" "$2"; then ok "$1: $4 passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
tcyr_all() {   # <tag> <tcyr path> <assertion floor>
    tg=$1; TC="$ROOT/$2"
    want=$(grep -cE '^ *assert_eq\(' "$TC")
    [ "$want" -ge "$3" ] || bad "$tg: only $want assertions derived from $2 (floor $3)"
    for mode in $X86_LEGS; do
        case $mode in
            plain) env_=""; lbl="$tg x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="$tg x86, CYRIUS_IR=3" ;;
            DCE) env_="CYRIUS_DCE=1"; lbl="$tg x86, CYRIUS_DCE=1" ;;
        esac
        rc=0; env $env_ "$CC" < "$TC" > "$T/$tg.$mode" 2> "$T/$tg.$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/$tg.$mode.err" | head -1)"; continue; fi
        chmod +x "$T/$tg.$mode"; got=0; timeout 60 "$T/$tg.$mode" > "$T/$tg.$mode.out" 2>&1 || got=$?
        tcyr_ok "$lbl" "$T/$tg.$mode.out" "$got" "$want"
    done
    if [ -x "$T/cc_a64" ]; then
        if "$T/cc_a64" < "$TC" > "$T/$tg.a" 2> "$T/$tg.aerr"; then
            chmod +x "$T/$tg.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 "./$tg.a" > "$T/$tg.aout" 2>&1) || got=$?
            tcyr_ok "$tg aarch64 (qemu)" "$T/$tg.aout" "$got" "$want"
        else bad "$tg aarch64: the tcyr did not compile: $(grep '^error' "$T/$tg.aerr" | head -1)"; fi
    else echo "  SKIP $tg aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
    if [ -x "$T/cc_cx" ]; then
        if "$T/cc_cx" < "$TC" > "$T/$tg.cyx" 2> "$T/$tg.cxerr" && [ -s "$T/$tg.cyx" ]; then
            got=0; timeout 120 "$T/cxvm" < "$T/$tg.cyx" > "$T/$tg.cxout" 2>&1 || got=$?
            tcyr_ok "$tg cx (cxvm)" "$T/$tg.cxout" "$got" "$want"
        else bad "$tg cx: the tcyr did not compile: $(grep '^error' "$T/$tg.cxerr" | head -1)"; fi
    fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/$tg.exe" 2> "$T/$tg.werr" && [ -s "$T/$tg.exe" ]; then
            got=0
            (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$tg.exe" > "$T/$tg.wout" 2>/dev/null) || got=$?
            tcyr_ok "$tg PE (wine)" "$T/$tg.wout" "$got" "$want"
        else bad "$tg PE: the tcyr did not compile: $(grep '^error' "$T/$tg.werr" | head -1)"; fi
    else echo "  SKIP $tg PE — wine not installed"; skips=$((skips + 1)); fi
}
tcyr_all AF tests/tcyr/crossos/f32_scalar_init_rounds.tcyr 30
tcyr_all AR tests/tcyr/crossos/int_name_routes_int_overload.tcyr 20
tcyr_all AU tests/tcyr/crossos/u128_compound_matches_long_form.tcyr 15

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — f32 initializers round (F); a top-level pair bind refused (P); an integer name routes to _int (R); vector / typed-array / slice OP= refused (O); u128 OP= is the long form (U); IR=3 keeps the f32 conversions (I); every tcyr on x86_64 / IR / DCE / aarch64 / cx / PE (A)"
