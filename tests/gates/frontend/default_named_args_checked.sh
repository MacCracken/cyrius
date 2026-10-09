#!/bin/sh
# tests/gates/frontend/default_named_args_checked.sh — 6.7.7 (B6)
#
# PARAMETER DEFAULTS (and, from bite 4, named arguments). The user's decision (2026-10-08): a default
# is a compile-time constant (a literal, a `const`, a `const fn` call — the 6.7.2 evaluator) on a
# TRAILING parameter; typed parameters take defaults; the arity check becomes min..max. 2026-10-09,
# fork F1: a default in a trait's REQUIRED signature is an ERROR (it compiled, ignored); fork F2:
# EVERY forward call is arity-checked (a wrong-arity call to a fn defined later built). Pass 1
# records every definition's defaults and refuses a bad SHAPE at its token; the end of pass 1
# evaluates every default once, in the definition's own scope, and refuses a value its parameter's
# type does not take. A direct call short of max takes the missing defaults (the one marshaller);
# a `return f(..)` that fills is an ordinary call; a const context fills from the same values.
# The runtime half is tests/tcyr/crossos/default_named_args_values.tcyr.
#
#   R  refused once, by name, at its token, with no binary (R1-R16, R18-R20 = the plan's D1-D16,
#      D18-D20; R14 = F1's error). R17 is a PASS: the plan's D17
#      premise ("a fn inside a top-level block is not prescanned") is false since 6.6.17 —
#      `_prescan_block_fn` records it — so such a fn takes defaults like any other; D17 stays in
#      `_pd_late` as a backstop for a definition pass 1 did not record.
#   K  the count: C1 a call outside min..max ("'f' expects 1 to 3 arguments, got 4"), backward and
#      forward; C15 a call through a fn pointer short of a defaulted fn's parameters; R23 a fn
#      without defaults keeps the v6.5.1 text; R24 (F2) the forward-call issue's verbatim repros
#      give exactly the errors the same calls get below their callees
#   T  objdump: T1 a full-arity self tail call to a defaulted fn keeps its `jmp`; T2 a `return f(1)`
#      that fills is a `call` (the tail arm never fills)
#   E  E1 a default is a top-level constant (a caller's local const of the same name never reaches
#      it); E2 a default naming its own file's private const fn resolves there, called from another
#      file that defines a public one of the same name; G0 a generic instance fills from its base's
#      defaults (direct and tail); OV1 an overload-routed `_str` sibling that declares a default
#   S  shapes: S2 a `{` in a default is one refusal and the next fn still parses; S3 a `b = A < B`
#      default in a bounded generic, an inherent impl and a plain fn (each walker skips it whole);
#      C1 a const fn whose default holds a comma (`b = sq2(1, 2)`), run in a const context; FWD-pc a
#      forward call to `fn f(a, b = 1): f64` in f64 arithmetic (pass 1 steps over the default to
#      record the parameter count and the `: f64`); X0 the grammar refusals under --syntax-only
#   W  `#inline` on a defaulted fn is ignored by name, and both calls — full and filled — stay calls
#      (objdump)
#   A  ANTI-VACUOUS: the crossos tcyr built and run — x86 plain, CYRIUS_IR=3 and CYRIUS_DCE=1, then
#      aarch64 (qemu), cx (cxvm) and PE (wine), each with the full assertion count (cx: less the rows
#      under `#ifndef CYRIUS_TARGET_CX`, derived)
#
# MUTATION LEDGER (2026-10-09; each a one-edit scratch COPY of the tree, its build/cycc rebuilt from
# the mutated src, then this gate and the crossos tcyr run from the copy):
#   M3  the `_inl_why = 7` line dropped                    -> W1 (no warning; g inlined: no call)
#   M11 `_ce_bind_params` back to the depth-free skip     -> C1 ("a const fn called with the wrong
#                                                          number of arguments"); the tcyr does
#                                                          not compile on any leg
#   M17 `_prescan_skip_fn` without the parentheses skip   -> S2 (6 error lines: Q, declared below, unregistered)
#   M18 `_pd_sweep` dropped                               -> 19 rows: R2 R3 R5-R9 (each variant)
#                                                          R20 (an unused fn's bad default builds)
#   M22 the `_prescan_params_scan` default skip dropped   -> FWD-pc and the tcyr's F1 on every leg
#                                                          (0, want 8); R1 R11 X0a build (pass 1
#                                                          counts the list short)
#   M21 (the plan's: D17 dropped) has no killing row: no definition reaches `_pd_late`'s refusal
#       (see R17 above).
#   (bite 3)
#   M1  `_pd_call_fills` returns 0 (no divert)            -> T2, the tcyr on every leg: "internal: tail
#                                                          call to 'w3' reached the tail arm short of
#                                                          its defaults" (mode 3: loud, never a jmp)
#   M2  `_arg_next` without the closure-bar skip         -> the tcyr on every leg: the same internal
#                                                          error for `return ap(|a, b| a + b);`
#   M8  `_ce_call` does not fill (`_ce_fill` dropped)    -> R16 ("a const fn called with the wrong
#                                                          number of arguments", not D16); the tcyr
#                                                          refused on every leg (const N = cf(1), ..)
#   M9  the forward gate back to backward-only (= M23, the GFDS half: every row is a pass-1 record,
#       so the plan's `_pd_row` half is the same edit) -> C1-fwd and R24 (both repros) build
#   M12 the instance row copy (`_pd_late`) dropped       -> G0 ("'g$Pt' expects 2 arguments, got 1")
#                                                          and the tcyr on every leg ('gen$Pt')
#   M13 mode 4 dropped (the operator literals back to 1) -> R19 builds
#   M15 the f32 rounding dropped on a default            -> the tcyr's A10 f32 rows on every leg
#   M16 the fill's `SESTYPE(S, 0)` dropped               -> the tcyr's L1 (0, want 42) on every leg
#   M19 `_pd_eval` without the cursor move to the default -> E2 (199: main's public pk, want 149)
#   M20 `_ce_top = 0` in default evaluation: NOT RED alone, by construction — the end of pass 1
#       evaluates every default before any caller's scope exists (no local const, GINFN 0); with
#       `_pd_sweep` also dropped (the default evaluated lazily at the call) -> E1 (99, want 29)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: default_named_args_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: default_named_args_checked: mktemp -d failed"; exit 1; }
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
build() { rc=0; timeout 60 "$CC" ${2:-} < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what> <source> <line:col> [<compiler flag>]
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1" "${6:-}"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    elif ! grep '^error' "$T/$1.err" | grep -qF "<source>:$5: "; then bad "$3: refused at the wrong token (want $5): $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused once, at $5"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
E='\nsyscall(60, 0);\n'
NOTC="a default must be a compile-time constant"

refused r01 "parameter 'c' of 'f' needs a default: it follows one that has a default (defaults are trailing)" "R1: a default that is not trailing" "fn f(a, b = 1, c): i64 { return a + b + c; }$E" "1:16"
refused r02 "$NOTC: 'a' is a parameter of 'g'" "R2: a default naming a parameter of its own fn (even with a global of that name)" "var a = 4;\nfn g(a, b = a * 2): i64 { return a + b; }$E" "2:13"
refused r02t "$NOTC: 'T' is a type parameter of 'g'" "R2b: a default naming a type parameter" "fn g<T>(v: T, b = sizeof(T)): i64 { return b; }$E" "1:26"
refused r03 "'gv' is a variable - a const context takes only constants" "R3: a default that is not constant (the evaluator's own words)" "var gv = 3;\nfn f(a, b = gv): i64 { return a + b; }$E" "2:13"
refused r03b "'h' is not a \`const fn\`" "R3b: a default calling a fn that is not a const fn" "fn h(): i64 { return 1; }\nfn f(a, b = h()): i64 { return a + b; }$E" "2:13"
refused r04 "a parameter default cannot hold a block or an if-expression - declare a const and name it" "R4: an if-expression default" "fn f(a, b = if (a > 1) { 2 } else { 3 }): i64 { return a + b; }$E" "1:13"
refused r05 "parameter 'x' of 'f' is untyped: a float default needs it declared ': f64' (or ': f32')" "R5: a float default on an untyped parameter" "fn f(a, x = 1.5): i64 { return a; }$E" "1:13"
refused r06 "parameter 'x' of 'f' is ': f64': an integer default is its bit pattern - write 1.0" "R6: an integer default on an f64 parameter" "fn f(a, x: f64 = 1): i64 { return a; }$E" "1:18"
refused r06b "parameter 'y' of 'f' is ': f32': an integer default is its bit pattern" "R6b: on an f32 parameter" "fn f(a, y: f32 = 3): i64 { return a; }$E" "1:18"
refused r07 "parameter 'b' of 'f' is ': bool': its default must be a bool" "R7: a default that is not a bool, for a bool" "fn f(a, b: bool = 1): i64 { return a; }$E" "1:19"
refused r07b "parameter 'n' of 'f' is ': i64': its default must be an integer" "R7b: a string default for an integer type" "fn f(a, n: i64 = \"s\"): i64 { return a; }$E" "1:18"
refused r07c "parameter 's' of 'f' is ': cstring': its default must be a string (or 0)" "R7c: a nonzero integer for a cstring" "fn f(a, s: cstring = 7): i64 { return a; }$E" "1:22"
refused r07d "parameter 'p' of 'f' is ': *u8': its default must be an integer" "R7d: a string default for a pointer" "fn f(a, p: *u8 = \"s\"): i64 { return a; }$E" "1:18"
refused r08 "the default 300 does not fit parameter 'x' of 'f' (': u8')" "R8: a default out of a narrow type's range" "fn f(a, x: u8 = 300): i64 { return a; }$E" "1:17"
refused r08b "the default -129 does not fit parameter 'x' of 'f' (': i8')" "R8b: below an i8" "fn f(a, x: i8 = 0 - 129): i64 { return a; }$E" "1:17"
refused r09 "parameter 'p' of 'f' is a struct: it takes no default" "R9: a default on a struct parameter" "struct Pt { x; y; }\nfn f(a, p: Pt = 0): i64 { return a; }$E" "2:17"
refused r09b "parameter 's' of 'f' is a Str: it takes no default" "R9b: a default on a Str parameter" "fn f(a, s: Str = 0): i64 { return a; }$E" "1:18"
refused r09c "parameter 'v' of 'f' is a type parameter: it takes no default" "R9c: a default on a T parameter" "fn f<T>(a, v: T = 0): i64 { return a; }$E" "1:19"
refused r09d "parameter 'v' of 'f' is a vector: it takes no default" "R9d: a default on a vector parameter" "fn f(a, v: f64v2 = 0): i64 { return a; }$E" "1:20"
refused r09e "parameter 'r' of 'f' is a Result: it takes no default" "R9e: a default on a Result parameter" "fn f(a, r: Result = 0): i64 { return a; }$E" "1:21"
refused r10 "the receiver 'self' takes no default" "R10: a default on self" "struct P { v; }\nimpl P { fn m(self = 0, k): i64 { return k; } }$E" "2:20"
refused r11 "a variadic fn takes no parameter defaults" "R11: defaults in a variadic fn" "fn f(a, b = 1, ...): i64 { return a; }$E" "1:11"
T3='fn main(): i64 { var p = P { 5 }; return p.sh(2); }\nsyscall(60, main());\n'
TMSG="trait 'Sh' method 'sh': a trait's methods take no parameter defaults"
refused r12 "$TMSG" "R12: a default in a trait's default method (reported once, though the impl inherits it)" "trait Sh { fn sh(self, n = 1): i64 { return n; } }\nstruct P { v; }\nimpl Sh for P { }\n$T3" "1:26"
refused r12b "$TMSG" "R12b: ... one line, though the inherited default also holds a \`{\`" "trait Sh { fn sh(self, n = if (1 == 1) { 1 } else { 2 }): i64 { return n; } }\nstruct P { v; }\nimpl Sh for P { }\n$T3" "1:26"
refused r13 "'sh' implements trait 'Sh': its parameters take no defaults (the trait's signature is the contract)" "R13: a default on a method of impl Trait for T" "trait Sh { fn sh(self, n): i64; }\nstruct P { v; }\nimpl Sh for P { fn sh(self, n = 1): i64 { return self.v + n; } }\n$T3" "3:31"
refused r14 "$TMSG" "R14 (F1): a default in a trait's REQUIRED signature is an error (it compiled, ignored)" "trait Sh { fn sh(self, n = 1): i64; }\nstruct P { v; }\nimpl Sh for P { fn sh(self, n): i64 { return self.v + n; } }\n$T3" "1:26"
refused r15 "fn 'f' is defined twice and declares parameter defaults" "R15: a redefined fn where one definition declares defaults" "fn f(a, b = 1): i64 { return a + b; }\nfn f(a, b): i64 { return a * b; }$E" "2:4"
refused r15b "fn 'f' is defined twice and declares parameter defaults" "R15b: the defaults on the second definition" "fn f(a, b): i64 { return a * b; }\nfn f(a, b = 1): i64 { return a + b; }$E" "2:4"
exits r17 56 "R17: a fn inside a top-level block takes defaults (pass 1 records it): a call above the block" 'var r = g(5, 6);\nif (1 == 1) {\n    fn g(a, b = 1): i64 { return a * 10 + b; }\n}\nsyscall(60, r);\n'
refused r18 "a closure's parameters take no defaults" "R18: a closure parameter default" "fn main(): i64 { var c = |a, b = 1| a + b; return 0; }\nsyscall(60, main());\n" "1:32"
refused r20 "a parameter default is one constant expression, ending at ',' or ')'" "R20: a default that is not one expression" "fn f(a, b = 1 2): i64 { return a + b; }$E" "1:15"
refused r16 "the default of parameter 'b' of 'cf' is defined in terms of itself" "R16: a default defined in terms of itself (a const fn filling its own default)" "const fn cf(a, b = cf(1)): i64 { return a + b; }$E" "1:20"
refused r19 "operator fn 'V2_add' declares a parameter default: an operator passes exactly its two operands" "R19: an operator fn that declares a default (an operator passes exactly two operands)" "struct V2 { x; y; }\nfn V2_add(a, b, k = 1): i64 { return k; }\nfn main(): i64 { var a = V2 { 1, 2 }; var b = V2 { 3, 4 }; var c = a + b; return c; }\nsyscall(60, main());\n" "3"
# The grammar refusals are reported under --syntax-only (what `cyrius lint` runs) too.
refused x0a "needs a default: it follows one that has a default" "X0a: R1 under --syntax-only" "fn f(a, b = 1, c): i64 { return a + b + c; }$E" "1:16" "--syntax-only"
refused x0b "a parameter default cannot hold a block" "X0b: R4 under --syntax-only" "fn f(a, b = if (a > 1) { 2 } else { 3 }): i64 { return a + b; }$E" "1:13" "--syntax-only"

# ── S: shapes ────────────────────────────────────────────────────────────────────────────────
# S2: pass 1 must step over the whole list — had it taken the default's `{` for the body, its
# declaration scan would stop there, and Q / K (declared below their first use) would go unregistered.
refused s2 "a parameter default cannot hold a block" "S2: an if-expression default, then a fn using a struct and a const declared below it (no cascade)" "fn f(a, b = if (1 == 1) { 2 } else { 3 }): i64 { return a + b; }\nfn h(): i64 { var p = Q { 1, 2 }; return p.y + K; }\nstruct Q { x; y; }\nconst K = 5;\nsyscall(60, h());\n" "1:13"
exits s3 6 "S3: \`b = A < B\` in a bounded generic, an inherent impl and a plain fn (every walker skips it whole)" 'const A = 1;\nconst B = 2;\ntrait Show { fn show(self): i64; }\nstruct P { v; }\nimpl Show for P { fn show(self): i64 { return self.v; } }\nimpl P { fn m(self, k = A < B, j = 3): i64 { return self.v * 100 + k * 10 + j; } }\nfn g<T: Show>(x: T, b = A < B, c = 4): i64 { return x.show() * 100 + b * 10 + c; }\nfn w(a, b = A < B): i64 { return a + b; }\nfn main(): i64 { var p = P { 5 }; return p.m(1, 3) - g(p, 1, 4) + w(0, 0); }\nsyscall(60, main() + 7);\n'
exits c01 23 "C1: a const fn whose default holds a comma, run in a const context (\`_ce_bind_params\` balances it)" 'const fn sq2(x, y): i64 { return x * y; }\nconst fn cf(a, b = sq2(1, 2), c = 3): i64 { return a * 100 + b * 10 + c; }\nconst N = cf(1, 2, 3);\nsyscall(60, N - 100);\n'
exits fwd 8 "FWD-pc: a forward call to fn f(a, b = 1): f64 in f64 arithmetic (pass 1 records the count and the f64 return past the default)" 'fn main(): i64 { var r: f64 = f(3, 1) * 2.0; return f64_to(r); }\nfn f(a, b = 1): f64 { return f64_from(a + b); }\nsyscall(60, main());\n'

# ── K: the count ─────────────────────────────────────────────────────────────────────────────
refused c1hi "'f' expects 1 to 3 arguments, got 4" "C1-hi: too many arguments for a defaulted fn" "fn f(a, b = 1, c = 2): i64 { return a + b + c; }\nvar x = f(1, 2, 3, 4);$E" "2"
refused c1lo "'f' expects 1 to 3 arguments, got 0" "C1-lo: too few (a required parameter missing)" "fn f(a, b = 1, c = 2): i64 { return a + b + c; }\nvar x = f();$E" "2"
# (From a fn body: a top-level statement's call to a top-level fn below it was checked before 6.7.7 too.)
refused c1fwd "'f' expects 1 to 2 arguments, got 4" "C1-fwd: a forward call to a defaulted fn, outside its range" "fn main(): i64 { var x = f(1, 2, 3, 4); return x; }\nfn f(a, b = 1): i64 { return a + b; }\nsyscall(60, main());\n" "1"
refused c15 "a call through a fn pointer passes every argument: 'f' takes 3 (defaults fill only direct calls)" "C15: fncall1(&f, ..) short of a defaulted fn's parameters" "include \"lib/fnptr.cyr\"\nfn f(a, b = 1, c = 2): i64 { return a; }\nfn main(): i64 { return fncall1(&f, 1); }\nsyscall(60, main());\n" "3:33"
refused c15b "a call through a fn pointer passes every argument: 'f' takes 3" "C15b: ... callptr(&f, ..)" "include \"lib/fnptr.cyr\"\nfn f(a, b = 1, c = 2): i64 { return a; }\nfn main(): i64 { return callptr(&f, 1, 2); }\nsyscall(60, main());\n" "3:33"
refused r23 "'g' expects 2 arguments, got 3" "R23: a fn without defaults keeps the v6.5.1 text" "fn g(a, b): i64 { return a + b; }\nvar x = g(1, 2, 3);$E" "2"
# R24 (F2): the issue's verbatim repros; each must give exactly the errors it lists, and no binary.
R24D="$ROOT/docs/development/issues/repros"
r24() {   # <label> <repro> <expected error lines, '|'-separated>
    rc=0; timeout 60 "$CC" < "$R24D/$2" > "$T/r24.bin" 2> "$T/r24.err" || rc=$?
    got=$(grep '^error' "$T/r24.err" | tr '\n' '|' || true)
    if [ "$rc" -eq 0 ]; then bad "$1: BUILT (rc 0)"
    elif [ "$got" != "$3" ]; then bad "$1: got '$got', want '$3'"
    else ok "$1: refused exactly as the same calls below their callees are"; fi
}
[ -f "$R24D/2026-10-09-forward-call-arity-unchecked.cyr" ] || bad "R24: the issue's repro is missing"
r24 "R24 (F2): forward calls — plain, too few, a method, a tail call" 2026-10-09-forward-call-arity-unchecked.cyr "error:<source>:12: 'g' expects 1 argument, got 2|error:<source>:16: 'g' expects 1 argument, got 2|error:<source>:17: 'h' expects 3 arguments, got 2|error:<source>:18: 'P_m' expects 2 arguments, got 3|"
r24 "R24b (F2): a forward call to a fn inside a top-level block" 2026-10-09-forward-call-arity-unchecked-toplevel-block.cyr "error:<source>:6: 'g' expects 1 argument, got 2|"

# ── E: scope, generics, routing ──────────────────────────────────────────────────────────────
exits e1 29 "E1: a default is a top-level constant (main's local const K = 9 never reaches f's b = K)" 'const K = 2;\nfn f(a, b = K): i64 { return b; }\nfn main(): i64 { const K = 9; var x = f(1); return x * 10 + K; }\nsyscall(60, main());\n'
mkdir -p "$T/e2"
printf 'private\nconst fn pk(): i64 { return 4; }\npublic\nfn f(a, b = pk()): i64 { return a * 10 + b; }\n' > "$T/e2/priv.cyr"
printf 'include "priv.cyr"\nconst fn pk(): i64 { return 9; }\nfn main(): i64 { return f(1) * 10 + pk(); }\nsyscall(60, main());\n' > "$T/e2/main.cyr"
rc=0; ( cd "$T/e2" && timeout 60 "$CC" < main.cyr > e2.bin 2> e2.err ) || rc=$?
if [ "$rc" -ne 0 ]; then bad "E2: rc $rc: $(grep '^error' "$T/e2/e2.err" | head -1)"
else chmod +x "$T/e2/e2.bin"; got=0; timeout 10 "$T/e2/e2.bin" || got=$?
    [ "$got" -eq 149 ] && ok "E2: a default's call resolves in its own file (its private pk, not the caller's public one): exit 149" || bad "E2: exit $got, want 149"; fi
exits g0 103 "G0: a generic instance fills from its base's defaults (direct, and in tail position)" 'struct Pt { x; y; }\ntrait Show { fn show(self): i64; }\nimpl Show for Pt { fn show(self): i64 { return self.x; } }\nfn g<T: Show>(v: T, n = 4): i64 { return v.show() * 10 + n; }\nfn tg(p: Pt): i64 { return g(p); }\nfn main(): i64 { var p = Pt { 3, 1 }; return g(p) + g(p, 5) + tg(p); }\nsyscall(60, main());\n'
exits ov1 71 "OV1: a Str argument routed to a \`_str\` sibling that declares a default (min..max), which fills" 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/str.cyr"\nfn pr(x): i64 { return 1; }\nfn pr_str(s: Str, k = 7): i64 { return k; }\nfn main(): i64 { alloc_init(); var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }\nsyscall(60, main());\n'

# ── T: tail calls (objdump) ──────────────────────────────────────────────────────────────────
printf 'fn down(n, acc = 0): i64 {\n    if (n == 0) { return acc; }\n    return down(n - 1, acc + 2);\n}\nfn w(a, b = 3): i64 { return a + b; }\nfn t2(): i64 { return w(1); }\nfn tend(): i64 { return 0; }\nsyscall(60, (down(1000000) + t2() + tend()) & 255);\n' > "$T/t01.cyr"
rc=0; CYRIUS_SYMS="$T/t01.syms" "$CC" < "$T/t01.cyr" > "$T/t01.bin" 2> "$T/t01.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "T1/T2: the probe did not build: $(grep '^error' "$T/t01.err" | head -1)"
else
    chmod +x "$T/t01.bin"; got=0; timeout 10 "$T/t01.bin" || got=$?
    [ "$got" -eq 132 ] && ok "T: down(1000000) + a filled tail call: exit 132" || bad "T: exit $got, want 132"
    if command -v objdump > /dev/null 2>&1; then
        d=$(awk '$2 == "down" { print $1 }' "$T/t01.syms"); w=$(awk '$2 == "w" { print $1 }' "$T/t01.syms")
        t=$(awk '$2 == "t2" { print $1 }' "$T/t01.syms"); e=$(awk '$2 == "tend" { print $1 }' "$T/t01.syms")
        if [ -z "$d" ] || [ -z "$w" ] || [ -z "$t" ] || [ -z "$e" ]; then bad "T: the symbol map does not name down / w / t2 / tend"
        else
            ds=$(printf '%x' "0x$d"); ws=$(printf '%x' "0x$w")
            nj=$(objdump -d --start-address=0x"$d" --stop-address=0x"$w" "$T/t01.bin" | grep -cE "jmp +0x$ds\b")
            [ "$nj" -eq 1 ] && ok "T1: the full-arity self tail call to a defaulted fn keeps its jmp" || bad "T1: down has $nj jmp(s) to itself, want 1"
            nc=$(objdump -d --start-address=0x"$t" --stop-address=0x"$e" "$T/t01.bin" | grep -cE "call +0x$ws\b")
            nj2=$(objdump -d --start-address=0x"$t" --stop-address=0x"$e" "$T/t01.bin" | grep -cE "jmp +0x$ws\b")
            if [ "$nc" -eq 1 ] && [ "$nj2" -eq 0 ]; then ok "T2: a \`return w(1)\` that fills is a call"
            else bad "T2: t2 has $nc call(s) and $nj2 jmp(s) to w, want 1 and 0"; fi
        fi
    else echo "  SKIP T1/T2's objdump rows: no objdump"; skips=$((skips + 1)); fi
fi

# ── W: #inline ───────────────────────────────────────────────────────────────────────────────
printf '#inline\nfn g(a, b = 1): i64 { return a + b; }\nfn h(): i64 { var x = g(5, 2); var y = g(5); return x * 10 + y; }\nfn hend(): i64 { return 0; }\nsyscall(60, h() + hend());\n' > "$T/w01.cyr"
rc=0; CYRIUS_SYMS="$T/w01.syms" "$CC" < "$T/w01.cyr" > "$T/w01.bin" 2> "$T/w01.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "W1: the #inline probe did not build: $(grep '^error' "$T/w01.err" | head -1)"
else
    grep -q "#inline ignored: fn has parameter defaults" "$T/w01.err" && ok "W1: #inline on a defaulted fn is ignored by name" || bad "W1: no '#inline ignored: fn has parameter defaults' warning"
    chmod +x "$T/w01.bin"; got=0; timeout 10 "$T/w01.bin" || got=$?
    [ "$got" -eq 76 ] && ok "W1: ... g(5, 2) and the filled g(5): exit 76" || bad "W1: exit $got, want 76"
    if command -v objdump > /dev/null 2>&1; then
        g=$(awk '$2 == "g" { print $1 }' "$T/w01.syms" 2>/dev/null)
        h=$(awk '$2 == "h" { print $1 }' "$T/w01.syms" 2>/dev/null)
        e=$(awk '$2 == "hend" { print $1 }' "$T/w01.syms" 2>/dev/null)
        if [ -z "$g" ] || [ -z "$h" ] || [ -z "$e" ]; then bad "W1: the symbol map does not name g / h / hend"
        else
            gs=$(printf '%x' "0x$g")
            nc=$(objdump -d --start-address=0x"$h" --stop-address=0x"$e" "$T/w01.bin" | grep -cE "call +0x$gs\b")
            [ "$nc" -eq 2 ] && ok "W1: ... and h calls g twice (not inlined)" || bad "W1: h has $nc call(s) to g, want 2 (inlined?)"
        fi
    else echo "  SKIP W1's call row: no objdump"; skips=$((skips + 1)); fi
fi

# ── A: the crossos tcyr, every leg, with its full assertion count ────────────────────────────
TC="$ROOT/tests/tcyr/crossos/default_named_args_values.tcyr"
WANT=$(grep -cE '^ *assert_eq\(' "$TC")
[ "$WANT" -ge 50 ] || bad "A0: only $WANT assertions derived from the tcyr (floor 50)"
# cx has no 9-16 B register-pair struct return: its leg counts without the rows under `#ifndef CYRIUS_TARGET_CX`.
NCX=$(awk '/^ *#ifndef CYRIUS_TARGET_CX/ { s = 1 } /^ *#endif/ { s = 0 } s && /^ *assert_eq\(/ { n++ } END { print n + 0 }' "$TC")
tcyr_ok() {   # <label> <output file> <exit> [<want>]
    w=${4:-$WANT}
    if [ "$3" -eq 0 ] && grep -q "^$w passed, 0 failed" "$2"; then ok "$1: $w passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL|error' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
for mode in plain IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="A1: x86" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="A2: x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="A3: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$TC" > "$T/tc_$mode" 2> "$T/tc_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/tc_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/tc_$mode"; got=0; timeout 60 "$T/tc_$mode" > "$T/tc_$mode.out" 2>&1 || got=$?
    tcyr_ok "$lbl" "$T/tc_$mode.out" "$got"
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < "$ROOT/src/main_aarch64.cyr" > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        if "$T/cc_a64" < "$TC" > "$T/tc.a" 2> "$T/tc.aerr"; then
            chmod +x "$T/tc.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./tc.a > "$T/tc.aout" 2>&1) || got=$?
            tcyr_ok "A4: aarch64 (qemu)" "$T/tc.aout" "$got"
        else bad "A4: aarch64: the tcyr did not compile: $(grep '^error' "$T/tc.aerr" | head -1)"; fi
    else bad "A4: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A4: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < "$ROOT/src/main_cx.cyr" > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < "$ROOT/programs/cxvm.cyr" > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$TC" > "$T/tc.cyx" 2> "$T/tc.cxerr" && [ -s "$T/tc.cyx" ]; then
        got=0; timeout 120 "$T/cxvm" < "$T/tc.cyx" > "$T/tc.cxout" 2>&1 || got=$?
        tcyr_ok "A5: cx (cxvm)" "$T/tc.cxout" "$got" "$((WANT - NCX))"
    else bad "A5: cx: the tcyr did not compile: $(grep '^error' "$T/tc.cxerr" | head -1)"; fi
else bad "A5: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/tc.exe" 2> "$T/tc.werr" && [ -s "$T/tc.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./tc.exe > "$T/tc.wout" 2>/dev/null) || got=$?
        tcyr_ok "A6: PE (wine)" "$T/tc.wout" "$got"
    else bad "A6: PE: the tcyr did not compile: $(grep '^error' "$T/tc.werr" | head -1)"; fi
else echo "  SKIP A6: PE leg — wine not installed"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: default_named_args_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: default_named_args_checked — $skips leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: default_named_args_checked — parameter defaults: refusals (R), shapes (S), the count (K), scope / generics / routing (E), tail calls (T), #inline (W), every backend (A)"
