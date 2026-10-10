#!/bin/sh
# tests/gates/frontend/default_named_args_checked.sh — 6.7.7 (B6)
#
# PARAMETER DEFAULTS AND NAMED ARGUMENTS. The user's decision (2026-10-08): a default is a
# compile-time constant (a literal, a `const`, a `const fn` call — the 6.7.2 evaluator) on a
# TRAILING parameter; typed parameters take defaults; the arity check becomes min..max; named
# arguments follow the positionals, in any order, each parameter at most once, evaluated left to
# right as written (placed in parameter order); direct calls only. 2026-10-09,
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
#      give exactly the errors the same calls get below their callees; R24c a right-count forward
#      call to a fn with a `u128` / `*u128` / `*fn` parameter builds (pass 1 counts a type token
#      that is not a name); R24d a forward call to such a fn keeps its `: f64` / struct return;
#      U1-U5 a default after such a parameter: filled, named, D1, D3
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
#      record the parameter count and the `: f64`); X0 the grammar refusals under --syntax-only.
#      The tools that read a parameter list (bite 5; each built here from this tree with $CC, each
#      fixture compiling first): S-hdr `cyrius header` (one C parameter per parameter, its type and
#      default skipped whole); S-asf api-surface (`name/MIN-MAX` for a defaulted fn, `name/N`
#      otherwise, string / char literals skipped; removed_symbol_census.sh's strip reads both);
#      S-doc cyrdoc (a `{` in a string / char default does not end the signature); S-lsp
#      cyrius-lsp (a default's names are not parameters, and its `)` does not end the list); S-ta
#      type-audit (a `)` in a literal default does not close the list); S-fmt cyrfmt accepts the
#      crossos tcyr; S-R5 no helper the compiler calls with a FIXED argument count declares a
#      default (the names derived from src; each must be defined in lib/)
#   W  `#inline` on a defaulted fn is ignored by name, and both calls — full and filled — stay calls
#      (objdump)
#   N  named arguments: R21 the call-side refusals, once each, at the label (C2 an unknown name, C3
#      named twice, C4 by position and by name, C5 a positional after a named one, C6 a required one
#      missing, C7 through fncallN / callptr, C8 `self:` in the dot form, C9 a callee with no declared
#      list, C10 an overload-routed base, C11 a variadic fn, C12 a redefined fn, C13 a reordered call
#      in a #naked fn, C1-named too many positionals; C14 a builtin: today's two errors and a note);
#      R22 the same refusals in a const context; X0c / X0d C5 / C7 under --syntax-only; G1-G3 generics
#      (T inferred through a name, the tail form, one report for a bad default with two instances);
#      I1 / I2 #inline (a named call to an inline-eligible fn is a call, objdump; an inlined body
#      holding one); TL1 a reordered call at top level under CYRIUS_IR=0 / 1 / 3; X1 / X2 lint (a
#      sibling's fn called by name, a default naming a sibling's const: --syntax-only, then `cyrius
#      lint` on a hermetic CYRIUS_HOME); AS1 CYRIUS_ASYNC=1; N-cl a named argument's label in a
#      closure body is not a read (no capture: in a fn, and at top level after the callee)
#   GC THE ARGUMENT WALKER STEPS OVER AN EXPLICIT GENERIC CALL'S TYPE ARGUMENTS (`_arg_next`; B4's
#      `_tup_item_end` folded in — one walker). Each row read `pk<i64, i64>(..)`'s comma as an
#      argument boundary on the merged 6.7.7 compiler: GC1 / GC2 B6's two repros verbatim (the
#      tail arm's "internal: ... short of its defaults" through `_pd_call_fills`; "a positional
#      argument cannot follow a named one" through `_pd_nscan`); GC3 the overload repro verbatim
#      (`_CALL_ARGC_PEEK`: routed to `show_str`, 2 — it returned 1, silent since 6.7.6); GC4 the
#      tail divert of a string literal into a `: Str` parameter (`_tc_str_literal_arg`); GC5 the
#      arity error's count after a label (`_pd_nargs`: "got 4", it said 5); GC6 an explicit generic
#      call as a by-value struct argument adds no copy (`_later_args_may_write`: the size of
#      `rd(mk<i64, i64>(1, 2), n)` equals `rd(mk(1, 2), n)`'s — a false copy since the lane's
#      by-value fix, never on the merged compiler, which copies nothing). Controls — a comparison
#      `a < b, c > (d)` keeps its comma (`a` is no generic fn: `_tup_gopen` looks the name up, as
#      `_tup_item_end` did): GC7 `return slc(a < b, c > (d), "hello")` still wraps the literal
#      (argument 2), GC8 `sh3(s, a < b, c > (d))` is still routed to `sh3_str` (3 arguments). The
#      runtime half is tests/tcyr/crossos/closure_argument_commas.tcyr (AC below).
#   A  ANTI-VACUOUS: the crossos tcyr built and run — x86 plain, CYRIUS_IR=3 and CYRIUS_DCE=1, then
#      aarch64 (qemu), cx (cxvm) and PE (wine), each with the full assertion count (cx: less the rows
#      under `#ifndef CYRIUS_TARGET_CX`, derived); AC the same six legs for
#      crossos/closure_argument_commas.tcyr, the walker's runtime rows (closure bars, generic
#      type arguments)
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
#   (bite 4)
#   M4  the named bypass in `_fnc_no_inline` dropped      -> I1/I2 (the replay reads `b:` as a
#                                                          variable) and the tcyr on every leg (A17)
#   M5  the reordered phase pushes in written order       -> A7, A9 (and A8, A11, A14, A16, A22) on
#       (no temporaries)                                     every leg; G1, G2, TL1, AS1, N-gates
#   M6  named arguments evaluated in parameter order      -> A8 (123, want 312) and A15 on every leg;
#                                                          TL1 (exit 65)
#   M7  `_simd_ord_at` replaced by the running ordinal    -> A20 on x86 (plain / IR=3 / DCE), aarch64
#                                                          and cx (vtwo(b: y, a: x) = 31); PE green
#                                                          by design (a vector travels by pointer)
#   M10 `_bx_pname` without its `=` skip                  -> the tcyr refused on every leg: a name
#                                                          after `b = A < B` is "no parameter named"
#   M14 `_HTEMP` a frame slot at top level too            -> TL1 (IR=0 / 1 / 3) and A15 SIGSEGV on x86,
#                                                          aarch64 and PE
#   (bite 5 — the tools; each mutant RED on its own row only, every other row green)
#   MT1 `_hdr_close` counts no depth                      -> S-hdr (`cyr_val hg(.., cyr_val 2)`)
#   MT2 the header's name scan does not stop at `=`      -> S-hdr (`cyr_val b = 2`, `cyr_val s =`)
#   MT3 `_asf_arity` skips `#` comments only (no literal) -> S-asf (af/1-4, ah/1-4, awr/1-3)
#   MT4 `_asf_amin` not taken from the first default      -> S-asf (af/2, ak/1: no ranges)
#   MT5 cyrdoc's signature scan not literal-aware         -> S-doc (`fn df(a, s = "`)
#   MT6 the LSP's `sig_depth` never raised                -> S-lsp (YY a parameter; c, d not)
#   MT7 the LSP collector skips no char literal           -> S-lsp (`c = ')'` ends the list: no d)
#   MT8 type-audit's paren match not literal-aware        -> S-ta (ta_s, ta_c unannotated: 2/5)
#   MT9 lib/vec.cyr's vec_get gains `z = 0` (the for-in   -> S-R5 (names lib/vec.cyr:86 vec_get)
#       call passes 2)
#   (review fixes)
#   MU1 pass 1 takes only a NAME as a parameter's type    -> R24c (all four: "'g' expects 1 argument,
#       (`_prescan_params_scan`'s non-name arm dropped)      got 3"), U1-U5: `_pd_pc_check` refuses
#                                                          each, loudly ("its two passes count its
#                                                          parameters apart (1 and 2)"); R24d
#                                                          ("'g' expects 1 argument, got 2"; at
#                                                          e44470b7: exit 0, and SIGSEGV)
#   MU2 MU1 plus `_pd_pc_check` dropped                   -> U1 exit 0, U2 exit 2, U3 exit 1 (silent),
#                                                          U3b the mode-3 internal error, U4 / U5
#                                                          build; R24c / R24d as MU1. (Dropped
#                                                          alone, `_pd_pc_check` has no killing row:
#                                                          a backstop no valid program reaches, as
#                                                          M21's D17 is.)
#   MU3 `_arg_next` steps over the FIRST `|..|` head only  -> the tcyr on every leg: "internal: tail
#                                                          call to 'ap2' reached the tail arm short"
#   MU3b `_arg_next` without its `||` arm                 -> the tcyr on every leg: the same for 'apz'
#   MU4 `_cl_is_arg_label` never 1 (a label is a read)    -> N-cl (refused: "a capturing closure needs
#                                                          include lib/alloc.cyr"; exit 139), the tcyr
#                                                          exit 139 on x86 (plain / IR=3 / DCE) and
#                                                          aarch64, 5 on PE (A21 at top level)
#   (the generic-comma fix)
#   MU5 `_arg_next` without the generic step (`return    -> GC1-GC6; AC refused on every leg (the
#       _tok_item_end(S, q)`, the pre-fix walker)          internal error first); and, the tuple
#                                                          walker being this one, tuple_checked.sh's
#                                                          C3 C4 ZG1-ZG6 ZG10 and its tcyr (A1-A7)
#   MU6 `_arg_gen_past` reads by shape (`_gcall_syn`,     -> GC7 (exit 122: the raw literal in the
#       no lookup) instead of `_tup_gopen`                 Str), GC8 (exit 242: not routed); AC refused on
#                                                          every leg (gc_cmp_infer: "generic 'gx2'
#                                                          has no i64 ... instance")
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
    n=$(grep -c '^error' "$T/$1.err" || true)
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
# R24c: pass 1 counts a parameter whose type token is not a name (`u128`, `*u128`, the `fn` of
# `*fn`): it stopped there, so a RIGHT-count forward call was refused ("'g' expects 1 argument").
exits r24u 3 "R24c: a forward call with the right count to fn g(a: u128, b, c) builds and runs" 'fn main(): i64 { var x = g(1, 2, 3); return x; }\nfn g(a: u128, b, c): i64 { return c; }\nsyscall(60, main());\n'
exits r24p 3 "R24c: ... to fn g(a: u64, b: *u128, c)" 'fn main(): i64 { var x = g(1, 2, 3); return x; }\nfn g(a: u64, b: *u128, c): i64 { return c; }\nsyscall(60, main());\n'
exits r24f 3 "R24c: ... to fn g(a: *fn, b, c), in tail position" 'fn main(): i64 { return g(1, 2, 3); }\nfn g(a: *fn, b, c): i64 { return c; }\nsyscall(60, main());\n'
refused r24w "'g' expects 3 arguments, got 2" "R24c: ... and a wrong count to it is refused with the whole count" "fn main(): i64 { var x = g(1, 2); return x; }\nfn g(a: u128, b, c): i64 { return c; }\nsyscall(60, main());\n" "1"
# R24d: the same stop left pass 1's return-type scan on the parameter, so a forward call to such a
# fn lost its `: f64` (exit 0) and its >16 B struct return (SIGSEGV) before 6.7.7.
exits r24r 6 "R24d: a forward call to fn g(a: u128, b): f64, in f64 arithmetic" 'fn main(): i64 { var r: f64 = g(1, 3) * 2.0; return f64_to(r); }\nfn g(a: u128, b): f64 { return f64_from(b); }\nsyscall(60, main());\n'
exits r24s 23 "R24d: ... to fn mk(a: u128, k): Big (a retptr struct return)" 'struct Big { a; b; c; }\nfn main(): i64 { var b: Big = mk(1, 2); return b.a * 100 + b.b * 10 + b.c; }\nfn mk(a: u128, k): Big { var r = Big { 1, k, 3 }; return r; }\nsyscall(60, main() - 100);\n'
# U: a default after a parameter whose type token is not a name. Pass 1 counted the list short, so
# the default was never recorded, evaluated, refused or filled — while pass 2's count let the
# short call through: the callee read an unset register (exit 0 / 2, silently).
exits u1 7 "U1: a default after a u128 parameter is filled" 'fn g(a: u128, b = 7): i64 { return b; }\nfn main(): i64 { var r = g(5); return r; }\nsyscall(60, main());\n'
exits u2 7 "U2: ... after a *fn parameter (a stale argument register in the callee)" 'fn h(x, y, z): i64 { return 99; }\nfn g(a: *fn, b = 7): i64 { return b; }\nfn main(): i64 { h(1, 2, 3); var r = g(5); return r; }\nsyscall(60, main());\n'
exits u3 71 "U3: ... a named call after a u128 parameter" 'fn g(a: u128, b = 7, c = 9): i64 { return b * 10 + c; }\nfn main(): i64 { var r = g(5, c: 1); return r; }\nsyscall(60, main());\n'
exits u3t 79 "U3b: ... after a *u128 parameter, filled in tail position" 'fn g(a: *u128, b = 7, c = 9): i64 { return b * 10 + c; }\nfn t(): i64 { return g(0); }\nsyscall(60, t());\n'
refused u4 "parameter 'c' of 'g' needs a default: it follows one that has a default (defaults are trailing)" "U4: D1 after a u128 parameter" "fn g(a: u128, b = 1, c): i64 { return c; }$E" "1:22"
refused u5 "unknown name 'nope' in a const context" "U5: D3 after a *fn parameter" "fn g(a: *fn, b = 1 + nope): i64 { return b; }$E" "1:22"

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
            nj=$(objdump -d --start-address=0x"$d" --stop-address=0x"$w" "$T/t01.bin" | grep -cE "jmp +0x$ds\b" || true)
            [ "$nj" -eq 1 ] && ok "T1: the full-arity self tail call to a defaulted fn keeps its jmp" || bad "T1: down has $nj jmp(s) to itself, want 1"
            nc=$(objdump -d --start-address=0x"$t" --stop-address=0x"$e" "$T/t01.bin" | grep -cE "call +0x$ws\b" || true)
            nj2=$(objdump -d --start-address=0x"$t" --stop-address=0x"$e" "$T/t01.bin" | grep -cE "jmp +0x$ws\b" || true)
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
            nc=$(objdump -d --start-address=0x"$h" --stop-address=0x"$e" "$T/w01.bin" | grep -cE "call +0x$gs\b" || true)
            [ "$nc" -eq 2 ] && ok "W1: ... and h calls g twice (not inlined)" || bad "W1: h has $nc call(s) to g, want 2 (inlined?)"
        fi
    else echo "  SKIP W1's call row: no objdump"; skips=$((skips + 1)); fi
fi

# ── N: named arguments (bite 4) ──────────────────────────────────────────────────────────────
# R21: the call-side refusals, each once, at its token, with no binary.
F3='fn f(a, b = 1, c = 2): i64 { return a * 100 + b * 10 + c; }\n'
refused c2 "'f' has no parameter named 'd' - its parameters are: a, b, c" "C2: an unknown name (the message lists the parameters)" "${F3}fn main(): i64 { return f(1, d: 3); }$E" "2:30"
refused c3 "parameter 'b' of 'f' is named twice" "C3: a parameter named twice" "${F3}fn main(): i64 { return f(1, b: 3, b: 4); }$E" "2:36"
refused c4 "parameter 'a' of 'f' is given by position and by name" "C4: a parameter given by position and by name" "${F3}fn main(): i64 { return f(1, a: 3); }$E" "2:30"
refused c5 "a positional argument cannot follow a named one (in a call to 'f')" "C5: a positional argument after a named one" "${F3}fn main(): i64 { return f(1, b: 3, 4); }$E" "2:36"
refused c6 "missing argument for parameter 'b' of 'g' (it has no default)" "C6: a required parameter missing from a named call" "fn g(a, b, c = 2): i64 { return a + b + c; }\nfn main(): i64 { return g(1, c: 3); }$E" "2:34"
refused c7 "named arguments need a direct call - fncallN / callptr pass arguments by position" "C7: a named argument through fncallN (once per call)" "include \"lib/fnptr.cyr\"\n${F3}fn main(): i64 { return fncall3(&f, 1, c: 2, b: 3); }$E" "3:40"
refused c7b "named arguments need a direct call" "C7b: ... and through callptr" "include \"lib/fnptr.cyr\"\n${F3}fn main(): i64 { return callptr(&f, 1, b: 2, c: 3); }$E" "3:40"
refused c8 "'self' is the receiver of a method call (o.m(..)) - it cannot be named" "C8: self: in the dot form" "struct P { v; }\nimpl P { fn m(self, k = 1): i64 { return self.v + k; } }\nfn main(): i64 { var p = P { 1 }; return p.m(self: 2); }$E" "3:46"
refused c9 "'Okk' takes no named arguments: it has no declared parameter list" "C9: a variant constructor (no declared list)" "include \"lib/alloc.cyr\"\nenum R { Okk(v), Er(e) }\nfn main(): i64 { var x = Okk(v: 1); return 0; }$E" "3:30"
refused c10 "a call with named arguments cannot be overload-routed: 'pr' has a routed sibling - call the one you mean" "C10: a base with a _str sibling, called by name" "include \"lib/syscalls.cyr\"\ninclude \"lib/alloc.cyr\"\ninclude \"lib/str.cyr\"\nfn pr(x): i64 { return 1; }\nfn pr_str(s: Str): i64 { return 2; }\nfn main(): i64 { return pr(x: 5); }$E" "6:28"
refused c10b "'vadd' has a routed sibling" "C10b: a positional &x first argument with a <base>_ptr sibling, then a name" "fn vadd(a, b): i64 { return 1; }\nfn vadd_ptr(a, b): i64 { return 2; }\nfn main(): i64 { var x = 1; var y = 2; return vadd(&x, b: &y); }$E" "3:56"
refused c11 "'f' is variadic: its arguments are positional" "C11: a variadic fn called by name" "fn f(a, ...): i64 { return a; }\nfn main(): i64 { return f(a: 1); }$E" "2:27"
refused c12 "'f' is defined twice: name its arguments only on a fn defined once" "C12: a redefined fn called by name" "fn f(a, b): i64 { return a; }\nfn f(a, b): i64 { return b; }\nfn main(): i64 { return f(b: 1, a: 2); }$E" "3:27"
refused c13 "a reordered named call needs a frame: not inside #naked fn 'isr'" "C13: a reordered named call in a #naked fn" "fn f(a, b): i64 { return a; }\n#naked\nfn isr() { f(b: 1, a: 2); asm { iretq } }$E" "3:14"
refused c1n "'f' expects 1 to 3 arguments, got 5" "C1-named: more positionals than parameters, then a name" "${F3}fn main(): i64 { return f(1, 2, 3, 4, b: 4); }$E" "2"
refused r22 "'cf' has no parameter named 'zz' - its parameters are: a, b" "R22: an unknown name in a const context" "const fn cf(a, b = 1): i64 { return a + b; }\nconst N = cf(1, zz: 3);$E" "2:17"
refused r22b "parameter 'b' of 'cf' is named twice" "R22b: a const context names a parameter twice" "const fn cf(a, b = 1): i64 { return a + b; }\nconst N = cf(a: 1, b: 2, b: 3);$E" "2:26"
refused r22c "missing argument for parameter 'a' of 'cf' (it has no default)" "R22c: a const context misses a required one" "const fn cf(a, b = 1): i64 { return a + b; }\nconst N = cf(b: 3);$E" "2:18"
# The grammar refusals hold under --syntax-only (what `cyrius lint` runs).
refused x0c "a positional argument cannot follow a named one" "X0c: C5 under --syntax-only, to a callee it cannot resolve" "fn main(): i64 { return sib_f(k: 1, 2); }$E" "1:37" "--syntax-only --allow-undef"
refused x0d "named arguments need a direct call" "X0d: C7 under --syntax-only" "include \"lib/fnptr.cyr\"\n${F3}fn main(): i64 { return fncall3(&f, 1, b: 2, c: 3); }$E" "3:40" "--syntax-only"
# A named argument runs its PARAMETER's gates (each keyed by the parameter index): the `: cstring`
# literal error, the bool check, a `: Str` literal's wrap and a >8 B struct's address push.
refused ncs "passing integer literal 42 to 'f' which expects a cstring" "N-gates: an integer literal named into a : cstring parameter" "fn f(a, s: cstring): i64 { return a; }\nfn main(): i64 { return f(s: 42, a: 1); }$E" "2:30"
refused nbl "cannot pass a value that is not a bool to bool parameter 't' of 'bf'" "N-gates: a non-bool named into a bool parameter" "fn bf(a, t: bool): i64 { return a; }\nfn main(): i64 { return bf(t: 1, a: 0); }$E" "2:31"
exits nst 42 "N-gates: a \`: Str\` literal and a >8 B struct, named and reordered" 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/str.cyr"\nstruct Big { a; b; c; }\nfn rd(s: Big, z): i64 { return s.a * 100 + s.c * 10 + z; }\nfn sl(n, s: Str): i64 { return str_len(s) * 10 + n; }\nfn main(): i64 {\n    alloc_init();\n    var b: Big = Big { 1, 2, 3 };\n    if (rd(z: 4, s: b) != 134) { return 1; }\n    if (sl(s: "hello", n: 7) != 57) { return 2; }\n    return 42;\n}\nsyscall(60, main());\n'
# C14: a named argument to a builtin keeps today's two errors and gains the note.
printf 'fn main(): i64 { syscall(n: 60, 3); return 0; }%b' "$E" > "$T/c14.cyr"
build c14
if [ "$rc" -eq 0 ]; then bad "C14: a named argument to a builtin BUILT"
elif ! grep -q "undefined variable 'n'" "$T/c14.err" || ! grep -q "expected ')', got ':'" "$T/c14.err"; then bad "C14: today's two errors changed: $(grep '^error' "$T/c14.err" | tr '\n' '|')"
elif ! grep -q "^note: named arguments go only to a direct call of a declared fn (builtins, fncallN and callptr take positional arguments)" "$T/c14.err"; then bad "C14: no note naming the rule"
else ok "C14: a named argument to a builtin: today's two errors, and the note"; fi
# N-cl: a named argument's label inside a closure body is not a READ — the capture pre-scan took
# `c:` for the enclosing fn's local `c` (refused without lib/alloc.cyr), and at top level for the
# stale local table's `c` (the callee's own parameter: a capture of a dead slot, SIGSEGV).
exits cla 9 "N-cl: a closure's named call whose label names an enclosing local captures nothing (no lib/alloc.cyr)" 'include "lib/fnptr.cyr"\nfn w3(a, b = 2, c = 3): i64 { return a * 100 + b * 10 + c; }\nfn main(): i64 { var c = 50; var cl = |n| w3(1, c: n); return fncall1(cl, 7) - 127 + 9; }\nsyscall(60, main());\n'
exits clb 9 "N-cl: a top-level closure's reordered named call, just after its callee" 'include "lib/fnptr.cyr"\ninclude "lib/alloc.cyr"\nfn w3(a, b = 2, c = 3): i64 { return a * 100 + b * 10 + c; }\nalloc_init();\nvar cl = |n| w3(c: n, a: 1);\nvar r = fncall1(cl, 7);\nsyscall(60, (r - 127) + 9);\n'
# G: generics through names.
GS='struct Pt { x; y; }\ntrait Show { fn show(self): i64; }\nimpl Show for Pt { fn show(self): i64 { return self.x; } }\nfn gid<T: Show>(x: T, n = 1): i64 { return x.show() * 10 + n; }\n'
exits g1 42 "G1: gid(n: 2, x: p) infers T from the named argument and instantiates gid\$Pt" "${GS}fn main(): i64 { var p = Pt { 4, 0 }; return gid(n: 2, x: p); }\nsyscall(60, main());\n"
exits g2 51 "G2: ... the tail form (return gid(n: 1, x: p) is an ordinary call)" "${GS}fn t(p: Pt): i64 { return gid(n: 1, x: p); }\nfn main(): i64 { var p = Pt { 5, 0 }; return t(p); }\nsyscall(60, main());\n"
refused g3 "the default 300 does not fit parameter 'n' of 'g' (': u8')" "G3: one error line for a bad default in a generic base with two instances" "struct Pt { x; }\nstruct Qt { y; }\nfn g<T>(v: T, n: u8 = 300): i64 { return n; }\nfn main(): i64 { var p = Pt { 1 }; var q = Qt { 2 }; return g(p, 1) + g(q, 2) + g(n: 3, v: p); }$E" "3:23"
# I: #inline. I1 a named call to an inline-eligible fn takes the normal path (a call, objdump);
# I2 an inlined body holding a named call.
printf '#inline\nfn s2(a, b): i64 { return a * 10 + b; }\n#inline\nfn wr(x): i64 { return s2(b: x, a: 4); }\nfn h(): i64 { return s2(b: 1, a: 5) + s2(3, 2) * 100 + wr(7) * 10000; }\nfn hend(): i64 { return 0; }\nsyscall(60, (h() + hend()) %% 256);\n' > "$T/i01.cyr"
rc=0; CYRIUS_SYMS="$T/i01.syms" "$CC" < "$T/i01.cyr" > "$T/i01.bin" 2> "$T/i01.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "I1/I2: the probe did not build: $(grep '^error' "$T/i01.err" | head -1)"
else
    chmod +x "$T/i01.bin"; got=0; timeout 10 "$T/i01.bin" || got=$?
    want=$(( (51 + 3200 + 470000) % 256 ))
    [ "$got" -eq "$want" ] && ok "I1/I2: s2(b: 1, a: 5) = 51, s2(3, 2) = 32, an inlined wr(7) holding s2(b: 7, a: 4) = 47: exit $got" || bad "I1/I2: exit $got, want $want"
    if command -v objdump > /dev/null 2>&1; then
        f=$(awk '$2 == "s2" { print $1 }' "$T/i01.syms"); h=$(awk '$2 == "h" { print $1 }' "$T/i01.syms"); e=$(awk '$2 == "hend" { print $1 }' "$T/i01.syms")
        if [ -z "$f" ] || [ -z "$h" ] || [ -z "$e" ]; then bad "I1: the symbol map does not name s2 / h / hend"
        else
            nc=$(objdump -d --start-address=0x"$h" --stop-address=0x"$e" "$T/i01.bin" | grep -cE "call +0x$(printf '%x' "0x$f")\b" || true)
            [ "$nc" -eq 2 ] && ok "I1: h calls s2 for the two named calls (the positional one is inlined)" || bad "I1: h has $nc call(s) to s2, want 2"
        fi
    else echo "  SKIP I1's call row: no objdump"; skips=$((skips + 1)); fi
fi
# TL1: a reordered named call at top level (hidden globals, no frame) under the IR modes.
printf 'var g_log = 0;\nfn lg(v): i64 { g_log = g_log * 10 + v; return v; }\nfn w3(a, b = 2, c = 3): i64 { return a * 100 + b * 10 + c; }\nvar r = w3(c: lg(9), b: lg(8), a: lg(7));\nsyscall(60, (r - 789) + (g_log - 987) + 7);\n' > "$T/tl1.cyr"
for ir in 0 1 3; do
    rc=0; CYRIUS_IR=$ir "$CC" < "$T/tl1.cyr" > "$T/tl1_$ir.bin" 2> "$T/tl1_$ir.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "TL1 (CYRIUS_IR=$ir): rc $rc: $(grep '^error' "$T/tl1_$ir.err" | head -1)"; continue; fi
    chmod +x "$T/tl1_$ir.bin"; got=0; timeout 10 "$T/tl1_$ir.bin" || got=$?
    [ "$got" -eq 7 ] && ok "TL1 (CYRIUS_IR=$ir): a reordered named call at top level: exit 7" || bad "TL1 (CYRIUS_IR=$ir): exit $got, want 7"
done
# X: lint. X1 a call to a sibling module's fn by name, X2 a default naming a sibling's const: the
# compiler's half under `--syntax-only --allow-undef` (what `cyrius lint`'s pre-pass passes), and
# `cyrius lint` itself on a hermetic CYRIUS_HOME holding this compiler.
printf 'fn main(): i64 { return sib_f(1, k: 2, c: |a, b| a + b); }\nsyscall(60, main());\n' > "$T/x1.cyr"
printf 'fn f(a, b = SIB_K): i64 { return a + b; }\nfn main(): i64 { return f(b: 2, a: 1); }\nsyscall(60, main());\n' > "$T/x2.cyr"
rc=0; "$CC" --syntax-only --allow-undef < "$T/x1.cyr" > /dev/null 2> "$T/x1.err" || rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^error' "$T/x1.err" && ok "X1: --syntax-only: a sibling module's fn called by name: rc 0" || bad "X1: rc $rc: $(grep '^error' "$T/x1.err" | head -1)"
rc=0; "$CC" --syntax-only --allow-undef < "$T/x2.cyr" > /dev/null 2> "$T/x2.err" || rc=$?
if [ "$(grep '^error' "$T/x2.err" | grep -vc "unknown name 'SIB_K' in a const context")" -eq 0 ] && grep -q "unknown name 'SIB_K' in a const context" "$T/x2.err"; then
    ok "X2: --syntax-only: a default naming a sibling's const gives only lint's context message"
else bad "X2: $(grep '^error' "$T/x2.err" | head -2 | tr '\n' '|')"; fi
# (The wrapper runs the cycc BESIDE it, so it is copied next to this compiler.)
if [ -x "$ROOT/build/cyrius" ] && [ -x "$ROOT/build/cyrlint" ]; then
    mkdir -p "$T/lh/bin" "$T/lw"
    cp "$CC" "$T/lh/bin/cycc"; cp "$ROOT/build/cyrlint" "$T/lh/bin/cyrlint"; cp "$ROOT/build/cyrius" "$T/lh/bin/cyrius"
    chmod +x "$T/lh/bin/cycc" "$T/lh/bin/cyrlint" "$T/lh/bin/cyrius"
    cp "$T/x1.cyr" "$T/x2.cyr" "$T/lw/"
    for x in x1 x2; do
        rc=0; ( cd "$T/lw" && CYRIUS_HOME="$T/lh" HOME="$T/lh" timeout 120 "$T/lh/bin/cyrius" lint "$x.cyr" > "$T/l$x.out" 2> "$T/l$x.err" ) || rc=$?
        [ "$rc" -eq 0 ] && ok "$(echo "$x" | tr x X)-lint: cyrius lint: rc 0" || bad "$(echo "$x" | tr x X)-lint: cyrius lint rc $rc: $(head -2 "$T/l$x.err" | tr '\n' '|')"
    done
else echo "  SKIP X1-lint / X2-lint: build/cyrius or build/cyrlint not built"; skips=$((skips + 1)); fi
# AS1: an async fn with a default, awaited filled and by name, and its constructor called by name.
if [ -f "$ROOT/lib/async.cyr" ]; then
    printf 'include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/async.cyr"\nasync fn job(a, b = 2, c = 3): i64 { return a * 100 + b * 10 + c; }\nasync fn outer(x): i64 {\n    var u = await job(x);\n    var v = await job(c: 9, a: x);\n    return u * 1000 + v;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = outer(1);\n    var r = 0;\n    var n = 0;\n    while (n < 4) { r = future_force(C); n = n + 1; }\n    var D = job(b: 7, a: 4);\n    var s = future_force(D);\n    if (r != 123129) { return 1; }\n    if (s != 473) { return 2; }\n    return 42;\n}\nsyscall(60, main());\n' > "$T/as1.cyr"
    rc=0; CYRIUS_ASYNC=1 "$CC" < "$T/as1.cyr" > "$T/as1.bin" 2> "$T/as1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "AS1: rc $rc: $(grep '^error' "$T/as1.err" | head -1)"
    else chmod +x "$T/as1.bin"; got=0; timeout 10 "$T/as1.bin" || got=$?
        [ "$got" -eq 42 ] && ok "AS1: CYRIUS_ASYNC=1: await job(x) fills, await job(c: 9, a: x) and job(b: 7, a: 4) by name" || bad "AS1: exit $got, want 42"; fi
else bad "AS1: lib/async.cyr is missing"; fi

# ── S: the tools that read a parameter list (bite 5) ─────────────────────────────────────────
# Each tool is built HERE from this tree's source with $CC (a mutant's source builds a mutant's
# tool), and each fixture first compiles — it is real B6 syntax, not a tool's guess at it.
mkdir -p "$T/st/hh" "$T/st/hw" "$T/st/ap/src" "$T/st/ta/lib" "$T/st/dc" "$T/st/lw/home" "$T/st/lw/cwd"
tool() {   # <name> <source, from the tree root>: built with $CC into $T/st/<name>
    rc=0; "$CC" < "$ROOT/$2" > "$T/st/$1" 2> "$T/st/$1.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/st/$1" ]; then bad "S: $2 does not build: $(grep '^error' "$T/st/$1.err" | head -1)"; return 1; fi
    chmod +x "$T/st/$1"
}
premise() {   # <label> <fixture>: it compiles
    rc=0; ( cd "$(dirname "$2")" && timeout 60 "$CC" < "$2" > "$T/st/premise.bin" 2> "$T/st/premise.err" ) || rc=$?
    [ "$rc" -eq 0 ] && return 0
    bad "$1: the fixture does not compile: $(grep '^error' "$T/st/premise.err" | head -1)"; return 1
}
# S-hdr: `cyrius header` — every parameter, its type and default skipped whole (`b = sq2(1, 2)`
# held a `,` and a `)`, `s = ",)"` both); it printed `cyr_val b = 2` (not C) and lost parameters.
printf 'const fn sq2(x, y): i64 { return x * y; }\nfn hf(a, b = 2): i64 { return a + b; }\nfn hg(a, b = sq2(1, 2), c: f64 = 1.5): i64 { return a; }\nfn hh(s = ",)", n: i64 = 3): i64 { return n; }\nfn hk(a, c = \047,\047, d: u8 = 7): i64 { return a; }\nfn hw(a, b = 1 < 2, e = 3): i64 { return a; }\nfn hz(a, b): i64 { return a; }\nsyscall(60, 0);\n' > "$T/st/hw/d.cyr"
if tool cyrius cbt/cyrius.cyr && premise "S-hdr" "$T/st/hw/d.cyr"; then
    rc=0; ( cd "$T/st/hw" && CYRIUS_HOME="$T/st/hh" HOME="$T/st/hh" timeout 60 "$T/st/cyrius" header d.cyr > "$T/st/hdr.out" 2>&1 ) || rc=$?
    miss=""
    for l in 'cyr_val hf(cyr_val a, cyr_val b);' 'cyr_val hg(cyr_val a, cyr_val b, cyr_val c);' 'cyr_val hh(cyr_val s, cyr_val n);' 'cyr_val hk(cyr_val a, cyr_val c, cyr_val d);' 'cyr_val hw(cyr_val a, cyr_val b, cyr_val e);' 'cyr_val hz(cyr_val a, cyr_val b);'; do
        grep -qxF "$l" "$T/st/hdr.out" || miss="$miss [$l]"
    done
    n=$(grep -c '^cyr_val h' "$T/st/hdr.out" || true)
    if [ "$rc" -eq 0 ] && [ -z "$miss" ] && [ "$n" -eq 6 ]; then ok "S-hdr: cyrius header: a defaulted parameter is one C parameter (6 prototypes)"
    else bad "S-hdr: rc $rc, $n prototype(s); missing:$miss; got: $(grep '^cyr_val h' "$T/st/hdr.out" | tr '\n' '|')"; fi
fi
# S-asf: api-surface — `name/MIN-MAX` when a parameter defaults, `name/N` when none does; a string
# or char literal in a default is skipped (`s = "a,b#"` counted its `,` and read `#` as a comment),
# a wrapped list too; removed_symbol_census.sh's `/…` strip reads both shapes as the bare name.
cat > "$T/st/ap/src/am.cyr" <<'EOF'
const fn sq2(x, y): i64 { return x * y; }
fn af(a, s = "a,b#"): i64 { return a; }
fn ag(a, b): i64 { return a; }
fn ah(a, b = sq2(1, 2), c = ','): i64 { return a; }
fn ak(x = 1): i64 { return x; }
fn ae(): i64 { return 0; }
fn awr(a, b = 1,
  c = "x)", # a comment, with a comma
  d = 4): i64 { return a; }
fn alt(a, b = 1 < 2, c: f64 = 1.5): i64 { return a; }
syscall(60, 0);
EOF
if tool api programs/cyrius_api_surface.cyr && premise "S-asf" "$T/st/ap/src/am.cyr"; then
    rc=0; ( cd "$T/st/ap" && timeout 20 "$T/st/api" --update --scope=project --snapshot="$T/st/A.snap" ) > "$T/st/api.out" 2>&1 || rc=$?
    got=$(grep '^am::a' "$T/st/A.snap" | tr '\n' ' ')
    want='am::ae/0 am::af/1-2 am::ag/2 am::ah/1-3 am::ak/0-1 am::alt/1-3 am::awr/1-4 '
    if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "S-asf: api-surface: name/MIN-MAX for a defaulted fn, name/N otherwise, literals skipped"
    else bad "S-asf: rc $rc: got '$got', want '$want'"; fi
    # (the census's own expression, tests/gates/toolchain/removed_symbol_census.sh)
    got=$(grep '^am::a' "$T/st/A.snap" | sed 's|.*::||; s|/.*||' | tr '\n' ' ')
    [ "$got" = "ae af ag ah ak alt awr " ] && ok "S-asf: removed_symbol_census.sh's strip reads /N and /MIN-MAX as the bare name" || bad "S-asf: the census strip gives '$got'"
fi
# S-doc: cyrdoc — the signature runs to the body's `{`, not to a `{` in a string or char default.
printf '# doc for df\nfn df(a, s = "{x}"): i64 { return a; }\n# doc for dg\nfn dg(a, c = \047{\047): i64 { return a; }\nfn dh(a, b = 1): i64 { return a; }\nsyscall(60, 0);\n' > "$T/st/dc/d.cyr"
if tool cyrdoc programs/cyrdoc.cyr && premise "S-doc" "$T/st/dc/d.cyr"; then
    rc=0; ( cd "$T/st/dc" && timeout 20 "$T/st/cyrdoc" d.cyr ) > "$T/st/doc.out" 2>&1 || rc=$?
    miss=""
    for l in '### `fn df(a, s = "{x}"): i64`' "### \`fn dg(a, c = '{'): i64\`" '### `fn dh(a, b = 1): i64`'; do
        grep -qxF "$l" "$T/st/doc.out" || miss="$miss [$l]"
    done
    if [ "$rc" -eq 0 ] && [ -z "$miss" ]; then ok "S-doc: cyrdoc: a { inside a string or char default does not end the signature"
    else bad "S-doc: rc $rc; missing:$miss; got: $(grep '^###' "$T/st/doc.out" | tr '\n' '|')"; fi
fi
# S-lsp: cyrius-lsp's semantic tokens — a default's names are not parameters, and its `)` (a call,
# or a char literal) does not end the list: `YY` was colored a parameter and `c` / `d` were not.
printf 'fn lf(a, b = sq2(XX, YY), c = \047)\047, d: i64 = 3): i64 {\n    return a + b + c + d + XX + YY;\n}\nconst XX = 2;\nconst YY = 3;\nconst fn sq2(x, y): i64 { return x * y; }\nsyscall(60, lf(1) & 0);\n' > "$T/st/lw/doc.cyr"
if [ "$(uname -s)" != Linux ]; then echo "  SKIP S-lsp: cyrius-lsp is driven here on Linux only"; skips=$((skips + 1))
elif tool lsp programs/cyrius-lsp.cyr && premise "S-lsp" "$T/st/lw/doc.cyr"; then
    D="$T/st/lw/doc.cyr"
    lmsg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
    { lmsg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
      lmsg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$D"'","languageId":"cyrius","version":1,"text":""}}}'
      lmsg '{"jsonrpc":"2.0","id":2,"method":"textDocument/semanticTokens/full","params":{"textDocument":{"uri":"file://'"$D"'"}}}'
      lmsg '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'; } | \
      ( cd "$T/st/lw/cwd" && env -i HOME="$T/st/lw/home" PATH=/usr/bin:/bin timeout 60 "$T/st/lsp" 2> /dev/null ) | tr '\r' '\n' > "$T/st/lsp.out"
    data=$(grep -o '"id":2,"result":{"data":\[[0-9,]*\]' "$T/st/lsp.out" | sed 's/.*\[//; s/\]//')
    # Decode the 5-int deltas into `line:name=type`; type 6 is `parameter`.
    awk -v DATA="$data" 'NR == FNR { L[NR - 1] = $0; next }
        END { n = split(DATA, a, ","); ln = 0; col = 0
              for (i = 1; i + 4 <= n; i += 5) {
                  if (a[i] > 0) { ln += a[i]; col = a[i + 1] } else { col += a[i + 1] }
                  print ln ":" substr(L[ln], col + 1, a[i + 2]) "=" a[i + 3] } }' "$D" /dev/null > "$T/st/lsp.tok"
    p0=$(grep '^0:.*=6$' "$T/st/lsp.tok" | sed 's/^0://; s/=6$//' | tr '\n' ' ')
    p1=$(grep '^1:.*=6$' "$T/st/lsp.tok" | sed 's/^1://; s/=6$//' | tr '\n' ' ')
    if [ -n "$data" ] && [ "$p0" = "a b c d " ] && [ "$p1" = "a b c d " ]; then ok "S-lsp: cyrius-lsp: the parameters are a b c d (not a default's XX / YY), in the signature and the body"
    else bad "S-lsp: parameter tokens: line 0 '$p0', line 1 '$p1' (want 'a b c d ' each)"; fi
fi
# S-ta: type-audit — a `)` in a string or char default does not close the list (the fn then read
# as unannotated).
printf 'const fn sq2(x, y): i64 { return x * y; }\nfn ta_s(a, s = ")"): i64 { return a; }\nfn ta_c(a, c = \047)\047): i64 { return a; }\nfn ta_n(a, b = sq2(1, 2)): i64 { return a; }\nfn ta_bare(a, b = 1) { return a; }\nfn ta_plain(a): i64 { return a; }\n' > "$T/st/ta/lib/ta.cyr"
if tool tau programs/cyrius_type_audit.cyr && premise "S-ta" "$T/st/ta/lib/ta.cyr"; then
    rc=0; ( cd "$T/st/ta" && timeout 20 "$T/st/tau" --module=ta > "$T/st/ta.out" 2> "$T/st/ta.err" ) || rc=$?
    un=$(grep '^  ta::' "$T/st/ta.out" | tr -d ' ' | tr '\n' ' ')
    if [ "$un" = "ta::ta_bare " ] && grep -q '^  ta: 4/5 annotated' "$T/st/ta.err"; then ok "S-ta: type-audit: only the fn with no return type is unannotated (4/5)"
    else bad "S-ta: rc $rc: unannotated '$un'; $(grep 'ta:' "$T/st/ta.err" | head -1)"; fi
fi
# S-fmt: cyrfmt has no parameter rule — it accepts every B6 shape in the crossos tcyr.
if tool cyrfmt programs/cyrfmt.cyr; then
    rc=0; "$T/st/cyrfmt" --check "$ROOT/tests/tcyr/crossos/default_named_args_values.tcyr" > "$T/st/fmt.out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && ok "S-fmt: cyrfmt --check accepts the crossos tcyr" || bad "S-fmt: rc $rc: $(head -1 "$T/st/fmt.out")"
fi
# S-R5: no helper the COMPILER calls with a fixed argument count declares a parameter default — the
# synthesized call (for-in, closures, enum constructors, await, slices, the overflow modes, the
# aarch64 polyfills, `: Str` literals) would pass fewer words than the helper reads. The names are
# derived from src (`_FINDFN_CSTR` / `EMIT_OVF_CALL` literals) plus the four the compiler spells
# byte by byte; each must be defined in lib/, and no definition may hold a depth-1 `=`.
R5N=$( (grep -rhoE '(_FINDFN_CSTR\(S, |EMIT_OVF_CALL\(S, )"[A-Za-z_0-9]+"' "$ROOT/src" | sed 's/.*"\([^"]*\)"/\1/'; printf 'vec_len\nvec_get\nalloc\nstr_from\n') | sort -u | tr '\n' ' ')
R5C=$(echo "$R5N" | wc -w | tr -d ' ')
if [ "$R5C" -lt 20 ]; then bad "S-R5: only $R5C compiler-called helper names derived from src (floor 20)"
else
    find "$ROOT/lib" -name '*.cyr' | sort > "$T/st/r5.files"
    awk -v NAMES="$R5N" -v Q="'" '
        BEGIN { n = split(NAMES, nm, " "); for (i = 1; i <= n; i++) want[nm[i]] = 1 }
        { line[NR] = $0; file[NR] = FILENAME; fl[NR] = FNR }
        END {
            for (r = 1; r <= NR; r++) {
                t = line[r]
                if (!match(t, /^[ \t]*((pub|public|const|async|#[A-Za-z_]+(\([^)]*\))?)[ \t]+)*fn[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) continue
                hd = substr(t, 1, RLENGTH); s = substr(t, RLENGTH + 1)
                nmx = hd; sub(/[ \t]*\($/, "", nmx); sub(/.*fn[ \t]+/, "", nmx)
                if (!(nmx in want)) continue
                print "FOUND " nmx
                d = 1; st = 0; has = 0; rr = r
                while (d > 0) {
                    for (p = 1; p <= length(s) && d > 0; p++) {
                        c = substr(s, p, 1)
                        if (st == 1) { if (c == "\\") p++; else if (c == "\"") st = 0; continue }
                        if (st == 4) { if (c == "\\") p++; else if (c == Q) st = 0; continue }
                        if (c == "#") break
                        if (c == "\"") st = 1
                        else if (c == Q) st = 4
                        else if (c == "(" || c == "[") d++
                        else if (c == ")" || c == "]") d--
                        else if (c == "=" && d == 1) has = 1
                    }
                    if (d > 0) { rr++; if (rr > NR || file[rr] != file[r]) break; s = line[rr]; st = 0 }
                }
                if (has == 1) print "DEFAULT " file[r] ":" fl[r] ": " nmx
            }
        }' $(cat "$T/st/r5.files") > "$T/st/r5.out"
    nodef=""
    for nm in $R5N; do grep -qx "FOUND $nm" "$T/st/r5.out" || nodef="$nodef $nm"; done
    if [ -n "$nodef" ]; then bad "S-R5: compiler-called helper(s) not found defined in lib/:$nodef"
    elif grep -q '^DEFAULT ' "$T/st/r5.out"; then bad "S-R5: a compiler-called helper declares a parameter default: $(grep '^DEFAULT ' "$T/st/r5.out" | sed 's/^DEFAULT //' | tr '\n' '|')"
    else ok "S-R5: none of the $R5C compiler-called helpers declares a parameter default ($(grep -c '^FOUND ' "$T/st/r5.out") definitions in lib/)"; fi
fi

# ── GC: an explicit generic call's type arguments separate no arguments ─────────────────────
PK='fn pk<A, B>(a: A, b: B): i64 { return a * 10 + b; }\nfn w(a, b = 3): i64 { return a + b; }\n'
exits gc1 15 "GC1: B6's repro: return w(pk<i64, i64>(1, 2)) fills b (_pd_call_fills)" "${PK}fn t(): i64 { return w(pk<i64, i64>(1, 2)); }\nsyscall(60, t());\n"
exits gc2 13 "GC2: B6's repro: var x = w(b: pk<i64, i64>(1, 2), a: 1) (_pd_nscan)" "${PK}var x = w(b: pk<i64, i64>(1, 2), a: 1);\nsyscall(60, x);\n"
exits gc3 2 "GC3: the overload repro: show(str_from(\"hi\"), pk<i64, i64>(1, 2)) is routed to show_str (_CALL_ARGC_PEEK)" 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/str.cyr"\nfn pk<A, B>(a: A, b: B): i64 { return a + b; }\nfn show(x, c): i64 { return 1; }\nfn show_str(s: Str, c): i64 { return 2; }\nfn main(): i64 { alloc_init(); return show(str_from("hi"), pk<i64, i64>(1, 2)); }\nsyscall(60, main());\n'
exits gc4 62 "GC4: return slg(pk<i64, i64>(1, 2), \"hello\") wraps the literal (_tc_str_literal_arg)" 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/str.cyr"\nfn pk<A, B>(a: A, b: B): i64 { return a * 10 + b; }\nfn slg(c, t: Str): i64 { return str_len(t) * 10 + c; }\nfn viaret(): i64 { return slg(pk<i64, i64>(1, 2), "hello"); }\nfn main(): i64 { alloc_init(); return viaret(); }\nsyscall(60, main());\n'
refused gc5 "'w' expects 1 to 2 arguments, got 4" "GC5: w(1, 2, 3, b: pk<i64, i64>(1, 2)) counts 4 arguments (_pd_nargs)" "${PK}fn main(): i64 { return w(1, 2, 3, b: pk<i64, i64>(1, 2)); }\nsyscall(60, main());\n" "3"
printf 'struct Big { a: i64; b: i64; c: i64; }\nfn mk<A, B>(a: A, b: B): Big { var r: Big = Big { a, b, 3 }; return r; }\nfn rd(s: Big, z): i64 { return s.a * 10 + s.b + z; }\nfn pg(n): i64 { var r = rd(mk<i64, i64>(1, 2), n); return r; }\nfn pi(n): i64 { var r = rd(mk(1, 2), n); return r; }\nfn zend(): i64 { return 0; }\nsyscall(60, pg(5) * 10 + pi(4) - 186 + zend());\n' > "$T/gc6.cyr"
rc=0; CYRIUS_SYMS="$T/gc6.syms" "$CC" < "$T/gc6.cyr" > "$T/gc6.bin" 2> "$T/gc6.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "GC6: the probe did not build: $(grep '^error' "$T/gc6.err" | head -1)"
else
    chmod +x "$T/gc6.bin"; got=0; timeout 10 "$T/gc6.bin" || got=$?
    sort "$T/gc6.syms" > "$T/gc6.sorted"
    gsz() { _se=$(awk -v n="$1" 'f { print a " " $1; exit } $2 == n { a = $1; f = 1 }' "$T/gc6.sorted"); [ -n "$_se" ] && echo $(( 0x${_se#* } - 0x${_se% *} )); }
    sg=$(gsz pg); si=$(gsz pi)
    if [ "$got" -ne 0 ]; then bad "GC6: exit $got, want 0"
    elif [ -z "$sg" ] || [ -z "$si" ]; then bad "GC6: the symbol map does not size pg / pi"
    elif [ "$sg" -eq "$si" ]; then ok "GC6: rd(mk<i64, i64>(1, 2), n) adds no copy ($sg B, as rd(mk(1, 2), n)'s) (_later_args_may_write)"
    else bad "GC6: rd(mk<i64, i64>(1, 2), n) is $sg B, rd(mk(1, 2), n) $si B — a copy for the type arguments' comma"; fi
fi
GCH='include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/str.cyr"\nfn pk<A, B>(a: A, b: B): i64 { return a * 10 + b; }\n'
exits gc7 110 "GC7: control: return slc(a < b, c > (d), \"hello\") wraps the literal, argument 2 (a is no generic fn)" "${GCH}"'fn slc(x, y, t: Str): i64 { return str_len(t) * 100 + x * 10 + y; }\nfn r(): i64 { var a = 1; var b = 2; var c = 3; var d = 4; return slc(a < b, c > (d), "hello"); }\nfn main(): i64 { alloc_init(); return r() - 400; }\nsyscall(60, main());\n'
exits gc8 210 "GC8: control: sh3(s, a < b, c > (d)) is routed to sh3_str (three arguments)" "${GCH}"'fn sh3(x, y, z): i64 { return 1000 + y * 10 + z; }\nfn sh3_str(s: Str, y, z): i64 { return str_len(s) * 100 + y * 10 + z; }\nfn main(): i64 { alloc_init(); var a = 1; var b = 2; var c = 3; var d = 4; var s = str_from("hi"); return sh3(s, a < b, c > (d)); }\nsyscall(60, main());\n'

# ── A / AC: the crossos tcyrs, every leg, with their full assertion counts ──────────────────────
tcyr_ok() {   # <label> <output file> <exit> <want>
    if [ "$3" -eq 0 ] && grep -q "^$4 passed, 0 failed" "$2"; then ok "$1: $4 passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL|error' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
# The cross compilers, built once from this tree.
A64=0; CX=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < "$ROOT/src/main_aarch64.cyr" > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"; A64=1
    else bad "A4: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A4 / AC4: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < "$ROOT/src/main_cx.cyr" > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < "$ROOT/programs/cxvm.cyr" > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then chmod +x "$T/cc_cx" "$T/cxvm"; CX=1
else bad "A5: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
command -v wine > /dev/null 2>&1 || { echo "  SKIP A6 / AC6: PE leg — wine not installed"; skips=$((skips + 1)); }
legs() {   # <tcyr> <label prefix> <floor>: x86 plain / IR=3 / DCE, aarch64, cx, PE
    TC=$1; P=$2
    WANT=$(grep -cE '^ *assert_eq\(' "$TC" || true)
    [ "$WANT" -ge "$3" ] || bad "${P}0: only $WANT assertions derived from $(basename "$TC") (floor $3)"
    # cx has no 9-16 B register-pair struct return: its leg counts without the rows under `#ifndef CYRIUS_TARGET_CX`.
    NCX=$(awk '/^ *#ifndef CYRIUS_TARGET_CX/ { s = 1 } /^ *#endif/ { s = 0 } s && /^ *assert_eq\(/ { n++ } END { print n + 0 }' "$TC")
    for mode in plain IR3 DCE; do
        case $mode in
            plain) env_=""; lbl="${P}1: x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="${P}2: x86, CYRIUS_IR=3" ;;
            DCE) env_="CYRIUS_DCE=1"; lbl="${P}3: x86, CYRIUS_DCE=1" ;;
        esac
        rc=0; env $env_ "$CC" < "$TC" > "$T/${P}_$mode" 2> "$T/${P}_$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/${P}_$mode.err" | head -1)"; continue; fi
        chmod +x "$T/${P}_$mode"; got=0; timeout 60 "$T/${P}_$mode" > "$T/${P}_$mode.out" 2>&1 || got=$?
        tcyr_ok "$lbl" "$T/${P}_$mode.out" "$got" "$WANT"
    done
    if [ "$A64" -eq 1 ]; then
        if "$T/cc_a64" < "$TC" > "$T/$P.a" 2> "$T/$P.aerr"; then
            chmod +x "$T/$P.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 "./$P.a" > "$T/$P.aout" 2>&1) || got=$?
            tcyr_ok "${P}4: aarch64 (qemu)" "$T/$P.aout" "$got" "$WANT"
        else bad "${P}4: aarch64: the tcyr did not compile: $(grep '^error' "$T/$P.aerr" | head -1)"; fi
    fi
    if [ "$CX" -eq 1 ]; then
        if "$T/cc_cx" < "$TC" > "$T/$P.cyx" 2> "$T/$P.cxerr" && [ -s "$T/$P.cyx" ]; then
            got=0; timeout 120 "$T/cxvm" < "$T/$P.cyx" > "$T/$P.cxout" 2>&1 || got=$?
            tcyr_ok "${P}5: cx (cxvm)" "$T/$P.cxout" "$got" "$((WANT - NCX))"
        else bad "${P}5: cx: the tcyr did not compile: $(grep '^error' "$T/$P.cxerr" | head -1)"; fi
    fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/$P.exe" 2> "$T/$P.werr" && [ -s "$T/$P.exe" ]; then
            got=0
            (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$P.exe" > "$T/$P.wout" 2>/dev/null) || got=$?
            tcyr_ok "${P}6: PE (wine)" "$T/$P.wout" "$got" "$WANT"
        else bad "${P}6: PE: the tcyr did not compile: $(grep '^error' "$T/$P.werr" | head -1)"; fi
    fi
}
legs "$ROOT/tests/tcyr/crossos/default_named_args_values.tcyr" A 100
legs "$ROOT/tests/tcyr/crossos/closure_argument_commas.tcyr" AC 30

if [ "$fails" -ne 0 ]; then echo "FAIL: default_named_args_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: default_named_args_checked — $skips leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: default_named_args_checked — parameter defaults and named arguments: refusals (R), shapes and tools (S), the count (K), scope / generics / routing (E), tail calls (T), #inline (W), named arguments (N), every backend (A), the argument walker (GC, AC)"
