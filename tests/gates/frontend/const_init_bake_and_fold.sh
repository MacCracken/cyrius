#!/bin/sh
# const_init_bake_and_fold.sh — 6.7.14: a declaration-zone global whose initializer folds to a constant is its value
# from program start, with no startup code (issues/archived/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md
# item 1; issues/archived/2026-10-11-folded-zero-or-enum-global-reruns-at-startup-decision.md, the user's decision D11 (b),
# 2026-10-16).
#
# Since 6.6.16 `var X = C;`, `= E.A`, `= A + 1` were baked into the image (_gvk_pre) AND replayed at startup — the
# expression re-run and stored again (x86_64: `mov eax,5; movabs rcx,X; mov [rcx],rax`, 18 bytes) — where `var X =
# 5;` emits nothing. A global folding to zero or through an enum constant re-ran a trapping division there:
# `var R = INT_MIN % -1;` and `var Q = (0 - CF_MAX - 1) / (0 - 1);` died SIGFPE (136) on x86_64 and cx, ran on
# aarch64. The replay now steps over a baked entry whose store wrote what the slot already holds (_gvk_quiet): the
# image value is its own and the nearest earlier replayed writer of the slot, if any, is a baked entry of that
# value. A computed initializer, `= 0` or a const- / enum-named constant of another value before it keeps the store,
# in order; over an earlier nonzero literal (a static init, not replayed) the constant is the value from program start.
#
#   S0-S7  the store is gone: each build is BYTE-IDENTICAL to the same program with the literal written out —
#          S0 the filed repro (`var X = C;`, exit 15), S1 `= C`, S2 `= E.A`, S3 `= A + 1`, S4 narrow `u8` / `i32`,
#          S5 D11's repro A (folds to zero) against `= 0`, S6 repro B (enum) against its literal; S7 `= 0` emits
#          nothing at the entry
#   O1-O13 orderings, by value, on x86_64, aarch64 (qemu, the tree's cross compiler) and cx (the tree's cycc_cx +
#          cxvm): a constant / computed redeclaration in either order, two constants, an enum pair, a literal then
#          a const, a list then a scalar, a same-valued redeclaration, and the program-start rule — a call in an
#          EARLIER initializer that writes the global keeps its write over `= C` / `= 0` (as it did over `= 5`),
#          and over `= C` redeclaring a literal (O13: `var G = 3; var r = setg(); var G = C;` ends at 9)
#          ⛔ 6.7.15 (the user's decision D2 (a), 2026-10-18): EVERY constant redeclaration is the value from program
#          start — a const- / enum-named or folded-only-at-the-replay one too, which stored in declaration order
#          after the slot's earlier writers (issues/2026-10-17-named-constant-redeclaration-ordered-unlike-a-
#          literal.md). O3 35 -> 55 (an earlier computed initializer runs into a sink), O4 57 -> 77, O6 24 -> 44,
#          O8 37 -> 77 (a list before it is not laid down), as their literal forms (O2, B in
#          global_redeclaration_one_definition.sh, a list then `var B = 7;` 77)
#   O14    a superseded constant is not the "last var" (the no-main exit value): `var z = g(); var a = C; var a = 5;`
#          exits g()'s 9, as through 6.7.14 (its sink was not one either)
#   N1-N11 the issue's table, by value on every leg: the guide's literal example, a literal then a const, a const
#          pair (the filed repro), an enum pair, `= 0` then a literal / a const, and a call between the two that
#          writes the global (`setg`) keeping its write over `= 5` / `= C` after `= 3`, `= D`, `= 0`; N12 an earlier
#          computed initializer still runs (its count) with its result discarded; N13 a bool global keeps its
#          startup store (its replay judges the value, after setg)
#   N14-N22 6.7.16 (the user's decision D13 (a), 2026-10-19): a FLOAT constant redeclaration is the value from program
#          start too (issues/archived/2026-10-18-float-literal-global-redeclaration-keeps-declaration-order.md), by value on every
#          leg: the three filed repros (N14 / N15 248 -> 4, N16 4 -> 224: setg's 0.5 kept), an f32 pair (N17 63 -> 64),
#          `= CF` (N18) and `= 1.5 + 1.0` (N19) after a literal, a computed float redeclaration still in order (N20: 252),
#          a computed initializer then a float constant (N21: f() runs into a sink, 5 -> 249), `= 0` then a float (N22:
#          0 -> 248); S25-S28 the earlier float's store is gone (byte-identical to the later one alone)
#   T1-T4  tests/tcyr/crossos/global_constant_redeclaration_order.tcyr (the table and the controls in one zone) on
#          x86_64, aarch64 (qemu), cx (cxvm) and PE (wine, a private prefix) — the release gate runs it on the hosts
#   S8-S11 an earlier constant declaration leaves no startup store: `var a = D; var a = C;`, `var a = 0; var a = C;`,
#          an enum pair, and `var a = C; var a = 5;` are each BYTE-IDENTICAL to the one literal (through 6.7.14 the
#          earlier store ran — into the slot, or into an 8-byte sink after a literal)
#   V4-V5  a superseded entry's replay still reports: another file's private const, a bool global's refusal
#   S12-S24 6.7.15: a baked struct or tuple literal leaves no startup stores (issues/2026-10-16-zone-struct-literal-baked-
#          and-stored.md) — S12-S16 and S22 BYTE-IDENTICAL to the same bytes as a typed list (positional, named, a tuple
#          inferred and annotated, an x86 `kernel;` build, enum constants), S17-S24 the entry `jmp` followed by the
#          program's own first instruction (the filed repro verbatim, named, tuple, nested narrow fields, f64 / f32
#          fields, a generic literal, a wrap)
#   Z1-Z13 the same shapes by value on every leg, and the orderings: an earlier read through a fn sees the bytes (Z7), a
#          redeclared literal of other bytes is the later one from program start (Z8: 33 — 6.7.16, D14 (a); 6.7.15 13),
#          a same-bytes one (Z9), and the program-start rule (6.7.14's D11 (b)) — a call in an earlier initializer that
#          writes the global keeps its write over the literal (Z10, and Z11 between two same literals: 92, through
#          6.7.14 12), and between two literals of other bytes (Z12: 94 — 6.7.16; 6.7.15 34: the later literal was
#          stored at its place); a later copy of another global (Z13)
#   Z14-Z26 6.7.16 (the user's decision D14 (a), 2026-10-19): a redeclared literal of constants is the value from program
#          start (issues/archived/2026-10-18-struct-tuple-literal-redeclaration-order-vs-d2.md), by value on every leg: the
#          filing's d1-d4 (Z14 12 -> 32, Z15 1 -> 3, Z16 / Z17 9), every spelling of the pair (Z18 named, Z19 generic,
#          Z20 wrapped, Z21 an annotated tuple: 14 -> 34), an earlier computed literal runs once into a sink (Z22: 71 ->
#          31), a later computed one keeps its order (Z23: 17), a constant literal before a computed one leaves no
#          store (Z24: the earlier call's write is read, 15 -> 95), an earlier computed struct initializer runs into a
#          sink (Z25: 73 -> 33), a same-bytes pair then other bytes (Z26: 94); S29-S32 the earlier literal leaves
#          nothing (byte-identical to the later one alone)
#   V6-V8  the dropped literal's walk still reports: an integer into an f64 field (warned, at 2:14), a bool field's
#          non-bool value, another file's private const
#   T5-T8  tests/tcyr/crossos/zone_struct_literal_value.tcyr on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine)
#   T9-T12 6.7.15: tests/tcyr/crossos/zone_float_constant_initializer.tcyr on the same four legs — a float global's
#          constant f64 expression (`= CF`, `= (1.5)`, `= 1.5 + 1.0`, an f32's rounding) is baked as its literal is,
#          its bits IEEE's on every target; an earlier read sees it (was 0), an earlier call's write is kept
#          (issues/archived/2026-10-16-kernel-float-global-constant-not-a-literal-left-late.md; the kernel rows are
#          kmode_enum_initializer_baked.sh RC / KC); 6.7.16 (D15 (a)) rows 12-18: an integer or enum operand on the
#          right (`1.5 + 1`, `1.5 * E.A`) baked too, its bits the target's own run-time arithmetic (18)
#   L1-L13 6.7.16: a list over a NAMED scalar constant keeps the bytes it does not list, as over a literal (L10)
#          (issues/archived/2026-10-18-list-redeclaration-over-named-scalar-constant-loses-unlisted-bytes.md), by value on every
#          leg: a const name (L1, the filed repro: 9 -> 14), an enum name (L2), a literal then a const (L3: the later
#          constant, 14 -> 16), a const then a literal (L4), a computed scalar (L5: 9) and the guide's `var a = f();
#          var a[1] = {0, 4};` (L6: 0x400), a const between two lists (L7: 9 -> 14), a computed initializer between
#          the const and the list (L8: 9 -> 14), an earlier initializer's read (L9: 9 -> 14); the seed is the slot's
#          last INTEGER constant: a float constant between it and the list stops the search (L11, the zone review's
#          program: 0, and L12: 9 — stepping past the float seeded the const it superseded, 5 / 14), a const after the
#          float seeds (L13: 14, the control)
#   L14-L24 6.7.16 (the user's decision D86 (a), 2026-10-20): a list over an untyped FLOAT constant keeps the float's
#          bytes it does not list, as over the integer spelling of those bits
#          (issues/archived/2026-10-20-list-redeclaration-over-untyped-float-constant-loses-unlisted-bytes.md), by value on every
#          leg: the filed x12 (L14: 0 -> 63) and x14 (L15: a literal before the float, 5 -> 0), a const before the
#          float (L16: 0 -> 63; L11 / L12, its low bytes, do not move), the listed byte kept under the float's (L17: 9
#          -> 72), a constant f64 expression (L18: 0 -> 64), a negated literal (L19: 0 -> 191), an f64 const name (L20:
#          0 -> 63), a float between two lists (L21: 0 -> 63), an earlier initializer's read (L22: 0 -> 63); controls: a
#          later pass-1 literal is the seed (L23: 14), a computed float is no constant (L24: 0)
#   T13-T16 6.7.16: tests/tcyr/crossos/global_array_initializer.tcyr on the same four legs
#   S33    6.7.16 (D15 (a)): `var M: f64 = 1.5 + 1;` (warned) is byte-identical to `= 1.5` — no startup store
#   D1-D3  D11's repros A, B and B's `%` twin exit 5 / 8 / 3 on x86_64, aarch64 and cx (PE: the crossos file
#          const_fold_int_min_div.tcyr on wine and cass)
#   K1     an x86 `kernel;` build (ELF64): the program reads the baked values, no late-replay warning, and the build
#          is byte-identical to the literal one (no late store)
#   V1-V2  what the replay's parse reports is still reported: another file's private const (`'PC' is private to its
#          file`), a `*T` global's "assigning non-pointer to typed pointer", a bool global's refusal
#
# Item 2 — the run-time fold arms (parse/expr/term.cyr `_PARSE_TERM_IMPL` / parse/expr/pexpr.cyr `_PEXPR_IMPL`) take a constant NAME on the
# right (and `+ - & | ^` a constant term): `2 * C` was `mov eax,2; push rax; mov eax,5; pop rcx; imul rcx`, `1 + C`
# an add, `2 + C * 3` an add of the folded `C * 3`.
#   F1-F15 each `return <expr>;` is BYTE-IDENTICAL to `return <its value>;` — on x86_64, and with the tree's aarch64
#          and cx compilers: `2 * C` (the filed shape), `1 + C`, `2 + C * 3`, `2 * E.A`, `2 * A`, `2 * B * C`,
#          `20 / C`, `1 << C`, `64 >> C`, `1 | C`, `7 & C`, `1 ^ C`, `9 - C`, a local const `3 * L`, and the
#          literal term `2 + 5 * 3`
#   F16-F21 values on every leg, the folded and the not folded: a negative const, a local var hiding the const,
#          `>>>` (never folded), `*%` in a name's term, a result under zero, `2 * (C)`; V3 another file's private
#          const on the right is still refused
#   F22-F45 6.7.15: a literal left operand, then `+ - & | ^` and a literal followed by `*%`, `*|`, `*?` or `>>>`
#          (`9 + 3 *% 4`, `57 & 48 >>> 2`, ...) compiles, by value on every leg — through 6.7.14 each was refused
#          "expected ';'": the arm folded `9 + 3` and stopped at the term operator `_cf_excl` did not list
#          (issues/archived/2026-10-16-constant-left-literal-then-term-operator-refused.md); F42 `2 - 3 *% 4` (a result under
#          zero, compiled before) is the control, F43-F45 the filed repros
#
# MUTATION (item 2, measured): _cf_fac_at reading a literal only (its name arms gone) -> 42 red: F1-F14 on x86_64,
# aarch64 and cx (F15, the literal term, still folds); _cf_can's term arm gone -> 21 red: F2, F3, F10-F13, F15 on
# the three legs (the `* / << >>` arms F1, F4-F9, F14 still fold their factor).
# MUTATION (measured, 6.7.15, a mutated scratch copy of the tree): _cf_excl without 119 / 120 / 121 / 152 -> 69 red:
# F22-F41 and F43-F45 on x86_64, aarch64 and cx, each "compile failed: expected ';'" (F42, the control, stays green).
# MUTATION (measured, 6.7.15, mutated scratch copies of the tree, every leg built from each): the tree before the
# fix (79f6ca16d's src) -> 38 red: O3 O4 O6 O8 N3 N4 N6 N9 N10 N12 on all three legs, S8-S11, T1-T4; `_gvk_link`
# superseding nothing -> 37 red: the same but S11; `_gvk_quiet` not dropping a superseded constant -> S8-S10 (its
# store runs into a sink); `_gvi_slot` always making the sink -> S8-S11; `_gvk_one` not folding a superseded entry
# (6.7.14's early return) -> S11 (`var a = C; var a = 5;`: C's sink store, as through 6.7.14); `_gvi_baked` making
# a superseded constant the last var -> O14 on all three legs.
# MUTATION (measured, 6.7.16 — the mixed operand, D15 (a); the kernel rows are kmode_enum_initializer_baked.sh's
# ledger): `_gvk_fscan` not taking an integer literal -> 5 red: S33, T9-T12 (row 12: 0); `_gvk_fqual` taking no `E.A`
# -> 4 red: T9-T12 (row 13: the call's write reset); `_gvi_mixw` keeping its code -> 1 red: S33.
# MUTATION (measured, 6.7.15 — the float constant expression): the tree before the fix (8981d679b's src) -> 4 red, T9-T12
# (9: an earlier read 0, 10: the startup store reset the call's write); `_gvk_fx`'s f32 narrowing dropped -> T9-T12
# (4, 8: binary64 bits in an f32).
# MUTATION (measured, 6.7.15, mutated scratch copies of the tree, every leg built from each — the struct literal): the
# tree before the fix (50b9a8817's src) -> 24 red: S12-S24, V6, Z10 / Z11 on all three legs, T5-T8; `_gvs_quiet`
# returning 0 -> the same 24; `_gvs_later` returning 0 (a later literal not considered) -> 7 red: Z8 on all three legs
# (33: the first literal's stores dropped under the second's bytes), T5-T8; `_gvs_same` returning 0 -> 7 red: Z11 on
# all three legs, T5-T8; `_gvs_undo` not taking the fixups back -> 48 red (the stale fixups patch the program's code:
# SIGSEGV / SIGILL).
# MUTATION (measured, 6.7.16, mutated scratch copies of the tree, every leg built from each — the redeclared literal,
# D14 (a)): `_gvs_pre` marking nothing (no literal supersedes) -> 20 red: S29-S32, Z12 / Z22 / Z25 / Z26 on all three
# legs (the earlier literal's or computed writer's store reset the call's write, or ran into the slot), T5-T8 (3 rows
# each) — Z8, Z14, Z15, Z18-Z21 stay green, the earlier literal's dropped stores leaving the later bake to be read;
# `_gvs_quiet` keeping a superseded literal's stores -> 38 red: S29-S32 (31: 12), Z8 Z12 Z14 Z15 Z18-Z21 Z26 on all
# three legs (the earlier literal stored over the later bytes at startup), T5-T8 (8 rows each); `_gvi_slot` making a
# sink for it -> 4 red: S29-S32 (a sink and its code); `_gvk_left` naming it in a kernel build -> 1 red: S32 (the late
# warning); `_spc_try` baking a superseded literal -> GREEN (the later literal's bake writes every byte over it: the
# guard keeps a superseded literal out of the blob, as a superseded list is, _gai_replay).
# MUTATION (measured, 6.7.16, a mutated scratch copy of the tree, every leg built from it — the float redeclaration):
# `_gvk_chain` linking integer folds only (6.7.15's `== 1`) -> 31 red: S25-S27, N14-N19 / N21 / N22 on all three legs
# (N20, the computed control, stays green), T1-T4 (6 of the tcyr's rows each).
# MUTATION (measured, 6.7.16, mutated scratch copies of the tree, every leg built from each — the list seed):
# `_gai_seed` returning the static init (the tree before the fix) -> 22 red: L1-L3 and L7-L9 on all three legs,
# T13-T16 (6 of the tcyr's rows each); `_gvk_link` not superseding for a superseded fold (bk 4) -> 7 red: L7 on all
# three legs (9: the earlier list's blob kept), T13-T16; `_gv_supersede` not setting bit 43 -> 7 red: L4 on all three
# legs (16: the const before the literal seeded), T13-T16.
# MUTATION (measured, 6.7.16, a scratch copy of the tree at cbb267ab3's src — the zone review's fix): `_gai_seed`
# stepping past a float constant (`_gai_seed_ent` 0 for `_gvk_ik` 2) -> 10 red: L11 / L12 on all three legs (5 / 14: the
# const the float superseded seeded the list), T13-T16 (GRKF 0x0509); L13 stays green.
# MUTATION (measured, 6.7.16, a scratch copy of the tree — D86 (a)): `_gai_seed_ent` answering 2 for a float constant
# (`_gvk_ik` 2: the walk stops at the static init, the tree before the fix) -> 31 red: L14-L22 on all three legs (L23 /
# L24, the controls, stay green), T13-T16 (4 of the tcyr's rows each).
# MUTATION (measured, 6.7.14, a mutated scratch copy of the tree, every leg built from it): _gvk_quiet returning 0
# (every store kept, as 6.6.16 - 6.7.13) -> 26 red: S0-S7, K1, O11 - O13 on all three legs, D1-D3 on x86_64 and cx
# (the SIGFPE, 136); _gvk_prev returning -1 (no earlier writer considered) -> 12 red: O3 / O4 / O6 / O8 on all
# three legs (the earlier computed / other-valued / list writer's value left in the slot).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: const_init_bake_and_fold: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
[ -x "$CC" ] || { echo "FAIL: const_init_bake_and_fold: no compiler at $CC"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: const_init_bake_and_fold: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $W (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper (T4).
WP="$W/wine"
WHM="$W/whome"
_wine_down() {
  [ -d "$WP" ] || return 0
  _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
  WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
  WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
  rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT
fail=0; rows=0; skips=0
bad() { echo "  FAIL: const_init_bake_and_fold $1"; fail=$((fail + 1)); }

# same ID WANT TEST LITERAL [env] — both compile clean, are byte-identical and exit WANT.
same() {
  rows=$((rows + 1))
  printf '%b' "$3" > "$W/$1.cyr"; printf '%b' "$4" > "$W/$1.l.cyr"
  r1=0; env ${5:-X=1} "$CC" < "$W/$1.cyr" > "$W/$1" 2> "$W/$1.err" || r1=$?
  r2=0; env ${5:-X=1} "$CC" < "$W/$1.l.cyr" > "$W/$1.l" 2> "$W/$1.l.err" || r2=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || { bad "$1: compile rc $r1 / $r2: $(grep -m1 '^error' "$W/$1.err" "$W/$1.l.err")"; return; }
  # `|| true`: a grep matching nothing exits 1, which `bash -eo pipefail` turns into the gate's exit (CI may run a gate either way)
  n=$(cat "$W/$1.err" "$W/$1.l.err" | grep -cE '^(error|warning)' || true)
  [ "$n" -eq 0 ] || { bad "$1: $n diagnostics: $(grep -hE '^(error|warning)' "$W/$1.err" "$W/$1.l.err" | head -2 | tr '\n' '|')"; return; }
  cmp -s "$W/$1" "$W/$1.l" || bad "$1: not byte-identical to the literal form ($(wc -c < "$W/$1") / $(wc -c < "$W/$1.l") B): the replay still emits code for it"
  chmod +x "$W/$1"; x=0; timeout 10 "$W/$1" > /dev/null 2>&1 || x=$?
  [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
}

F='fn f(): i64 { return 3; }\n'
same S0 15 'const C = 5;\nvar X = C;              # 1: baked AND stored\nfn f(): i64 { return 2 * C; }   # 2: imul at run time\nsyscall(60, X + f());\n' \
           'const C = 5;\nvar X = 5;              # 1: baked AND stored\nfn f(): i64 { return 2 * C; }   # 2: imul at run time\nsyscall(60, X + f());\n'
same S1 5 'const C = 5;\nvar X = C;\nsyscall(60, X);\n' 'const C = 5;\nvar X = 5;\nsyscall(60, X);\n'
same S2 5 'enum E { A = 5; }\nvar X = E.A;\nsyscall(60, X);\n' 'enum E { A = 5; }\nvar X = 5;\nsyscall(60, X);\n'
same S3 6 'enum E { A = 5; }\nvar X = A + 1;\nsyscall(60, X);\n' 'enum E { A = 5; }\nvar X = 6;\nsyscall(60, X);\n'
same S4 7 'const C = 5;\nvar X: u8 = C;\nvar Y: i32 = 0 - C;\nsyscall(60, X + Y + 7);\n' 'const C = 5;\nvar X: u8 = 5;\nvar Y: i32 = 0 - 5;\nsyscall(60, X + Y + 7);\n'
same S5 5 'var R = (0 - 0x7FFFFFFFFFFFFFFF - 1) % (0 - 1);\nsyscall(60, R + 5);\n' 'var R = 0;\nsyscall(60, R + 5);\n'
same S6 8 'enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }\nvar Q = (0 - CF_MAX - 1) / (0 - 1);\nsyscall(60, (Q >> 63) + 7);\n' \
          'enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }\nvar Q = 0x8000000000000000;\nsyscall(60, (Q >> 63) + 7);\n'
# S7 — `var Z = 0;` (folded zero, baked over the zero BSS) has no startup code either: the code after the x86_64
# entry `jmp` (e9 00 00 00 00, no fn) is the program's own `mov eax, 60` (b8 3c 00 00 00); through 6.7.13 it was
# the store (31 c0 48 b9 ..). The literal form cannot be compared byte for byte: a static global is not the
# "last var" the replayed entry is (_gv_slvar).
rows=$((rows + 1))
printf 'var Z = 0;\nsyscall(60, Z + 5);\n' > "$W/S7.cyr"
if "$CC" < "$W/S7.cyr" > "$W/S7" 2> "$W/S7.err"; then
  e=$(od -An -tx1 -j 176 -N 10 "$W/S7" | tr -d ' \n')
  [ "$e" = e900000000b83c000000 ] || bad "S7: \`var Z = 0;\` entry code is $e, want e900000000b83c000000 (no startup store)"
  chmod +x "$W/S7"; x=0; "$W/S7" > /dev/null 2>&1 || x=$?
  [ "$x" -eq 5 ] || bad "S7: exit $x, expected 5"
else bad "S7: compile failed: $(grep -m1 '^error' "$W/S7.err")"; fi
same K1 7 'kernel;\nconst C = 5;\nenum E { A = 2; }\nvar X = C;\nvar Y = E.A;\nsyscall(60, X + Y);\n' \
          'kernel;\nconst C = 5;\nenum E { A = 2; }\nvar X = 5;\nvar Y = 2;\nsyscall(60, X + Y);\n' CYRIUS_ELF64_KERNEL=1
# S8-S11 — 6.7.15 (D2 (a)): an earlier constant declaration of the slot leaves no startup store, and no sink. S8-S10
# are pairs of two values (whether they warn is global_redeclaration_one_definition.sh's question: `same_w` compares
# the bytes and the exit only); S11, one value twice, is silent as well (`same`).
same_w() {
  rows=$((rows + 1))
  printf '%b' "$3" > "$W/$1.cyr"; printf '%b' "$4" > "$W/$1.l.cyr"
  r1=0; "$CC" < "$W/$1.cyr" > "$W/$1" 2> "$W/$1.err" || r1=$?
  r2=0; "$CC" < "$W/$1.l.cyr" > "$W/$1.l" 2> "$W/$1.l.err" || r2=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || { bad "$1: compile rc $r1 / $r2: $(grep -m1 '^error' "$W/$1.err" "$W/$1.l.err")"; return; }
  cmp -s "$W/$1" "$W/$1.l" || bad "$1: not byte-identical to the literal form ($(wc -c < "$W/$1") / $(wc -c < "$W/$1.l") B): the earlier constant left code or a sink"
  chmod +x "$W/$1"; x=0; timeout 10 "$W/$1" > /dev/null 2>&1 || x=$?
  [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
}
same_w S8 5 'const C = 5;\nconst D = 3;\nvar a = D;\nvar a = C;\nsyscall(60, a);\n' 'const C = 5;\nconst D = 3;\nvar a = 5;\nsyscall(60, a);\n'
same_w S9 5 'const C = 5;\nvar a = 0;\nvar a = C;\nsyscall(60, a);\n' 'const C = 5;\nvar a = 5;\nsyscall(60, a);\n'
same_w S10 4 'enum E { A = 2; B = 4; }\nvar a = E.A;\nvar a = E.B;\nsyscall(60, a);\n' 'enum E { A = 2; B = 4; }\nvar a = 4;\nsyscall(60, a);\n'
same S11 5 'const C = 5;\nvar a = C;\nvar a = 5;\nsyscall(60, a);\n' 'const C = 5;\nvar a = 5;\nsyscall(60, a);\n'
# S25-S28 — 6.7.16 (D13 (a)): an earlier FLOAT constant declaration leaves no startup store either: an f64 pair, an f32
# pair, `= 1.5` then `= CF` are each BYTE-IDENTICAL to the later one alone (through 6.7.15 the earlier literal's store
# ran first, at the same size), and a same-bits pair (S28, silent) was already.
G48='syscall(60, (load64(&G) >> 48) & 255);\n'
same_w S25 4 "var G: f64 = 1.5;\nvar G: f64 = 2.5;\n$G48" "var G: f64 = 2.5;\n$G48"
same_w S26 64 'var F: f32 = 1.5;\nvar F: f32 = 2.5;\nsyscall(60, (load32(&F) >> 24) & 255);\n' 'var F: f32 = 2.5;\nsyscall(60, (load32(&F) >> 24) & 255);\n'
same_w S27 4 "const CF = 2.5;\nvar G: f64 = 1.5;\nvar G: f64 = CF;\n$G48" "const CF = 2.5;\nvar G: f64 = CF;\n$G48"
same S28 248 "var G: f64 = 1.5;\nvar G: f64 = 1.5;\n$G48" "var G: f64 = 1.5;\n$G48"
# S33 — 6.7.16 (the user's decision D15 (a), 2026-10-19): f64 arithmetic with an integer operand on the right (`1.5 + 1`,
# warned) is baked and leaves no startup code: BYTE-IDENTICAL to the literal of its bits, 1.5 (through 6.7.15 a
# startup store; its replay is parsed for the warning and taken back, _gvi_mixw).
same_w S33 63 'var M: f64 = 1.5 + 1;\nsyscall(60, (load64(&M) >> 56) & 255);\n' 'var M: f64 = 1.5;\nsyscall(60, (load64(&M) >> 56) & 255);\n'
# S12-S16 — 6.7.15: a baked struct / tuple literal leaves no startup stores (issues/2026-10-16-zone-struct-literal-baked-
# and-stored.md): each build is BYTE-IDENTICAL to the same 16 bytes written as a typed list (baked since 6.6.16, no
# code) — positional, named, a tuple inferred and annotated, and an x86 `kernel;` build (ELF64). Through 6.7.14 each
# element was stored again at startup (x86_64: `mov eax, imm; push rax; movabs rcx, p; [add rcx, 8;] pop rax; mov
# [rcx], rax`).
ZL='var p: i64[2] = { 1, 2 };\nsyscall(60, load64(&p + 8));\n'
same S12 2 'struct P { a; b; }\nvar p = P { 1, 2 };\nsyscall(60, load64(&p + 8));\n' "struct P { a; b; }\n$ZL"
same S13 2 'struct P { a; b; }\nvar p = P { b: 2, a: 1 };\nsyscall(60, load64(&p + 8));\n' "struct P { a; b; }\n$ZL"
same S14 2 'var p = (1, 2);\nsyscall(60, load64(&p + 8));\n' "$ZL"
same S15 2 'var p: (i64, i64) = (1, 2);\nsyscall(60, load64(&p + 8));\n' "$ZL"
# S22 enum constants (each enum member's own startup store, 6.6.6, is in both builds): byte-identical to the list.
same S22 35 'enum E { A = 3; B = 4; }\nstruct P { a; b; }\nvar p = P { A, E.B + 1 };\nsyscall(60, load64(&p) * 10 + load64(&p + 8));\n' \
            'enum E { A = 3; B = 4; }\nstruct P { a; b; }\nvar p: i64[2] = { 3, 5 };\nsyscall(60, load64(&p) * 10 + load64(&p + 8));\n'
same S16 2 'kernel;\nstruct P { a; b; }\nvar p = P { 1, 2 };\nsyscall(60, load64(&p + 8));\n' "kernel;\nstruct P { a; b; }\n$ZL" CYRIUS_ELF64_KERNEL=1
# S17-S24 — the program's first instruction follows the x86_64 entry `jmp` (e9 00 00 00 00), its `mov eax, 60` (b8 3c
# 00 00 00): no store before it. S17 the filed repro verbatim (exit 2), S18 the named form, S19 a tuple, S20 a nested
# struct of narrow fields, S21 f64 / f32 fields, S23 a generic struct's literal, S24 a wrap.
entry() {
  rows=$((rows + 1))
  printf '%b' "$3" > "$W/$1.cyr"
  if "$CC" < "$W/$1.cyr" > "$W/$1" 2> "$W/$1.err"; then
    e=$(od -An -tx1 -j 176 -N 10 "$W/$1" | tr -d ' \n')
    [ "$e" = e900000000b83c000000 ] || bad "$1: entry code is $e, want e900000000b83c000000 (no startup store)"
    chmod +x "$W/$1"; x=0; timeout 10 "$W/$1" > /dev/null 2>&1 || x=$?
    [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
  else bad "$1: compile failed: $(grep -m1 '^error' "$W/$1.err")"; fi
}
entry S17 2 'struct P { a; b; }\nvar p = P { 1, 2 };\nsyscall(60, p.b);\n'
entry S18 12 'struct P { a; b; }\nvar p = P { b: 2, a: 1 };\nsyscall(60, p.a * 10 + p.b);\n'
entry S19 34 'var t = (3, 4);\nsyscall(60, t.0 * 10 + t.1);\n'
entry S20 179 'struct I { x: i8; y: i32; }\nstruct O { a; i: I; c: u16; }\nvar o = O { 1, 0x7F, 0x11223344, 0xBEEF };\nsyscall(60, (o.a + o.i.x + o.i.y + o.c) & 255);\n'
entry S21 211 'struct F { d: f64; g: f32; n; }\nvar f = F { 1.5, 0.1, 7 };\nsyscall(60, ((load64(&f) >> 52) + load32(&f + 8) + f.n) & 255);\n'
entry S23 56 'struct W<T> { v: T; n; }\nvar w = W<i32> { 5, 6 };\nsyscall(60, w.v * 10 + w.n);\n'
entry S24 78 'struct P { a; b; }\nvar p: P = (P { 7, 8 });\nsyscall(60, p.a * 10 + p.b);\n'
# S29-S32 — 6.7.16 (the user's decision D14 (a), 2026-10-19): an earlier literal of constants leaves no startup store, no
# blob and no sink — a struct pair, a tuple pair, a named pair and an x86 `kernel;` (ELF64) pair are each BYTE-IDENTICAL
# to the later literal alone (through 6.7.15 both literals were stored in order, at the same size).
PQ='syscall(60, p.a * 10 + p.b);\n'
same S29 34 "struct P { a; b; }\nvar p = P { 1, 2 };\nvar p = P { 3, 4 };\n$PQ" "struct P { a; b; }\nvar p = P { 3, 4 };\n$PQ"
same S30 34 'var t = (1, 2);\nvar t = (3, 4);\nsyscall(60, t.0 * 10 + t.1);\n' 'var t = (3, 4);\nsyscall(60, t.0 * 10 + t.1);\n'
same S31 34 "struct P { a; b; }\nvar p = P { b: 2, a: 1 };\nvar p = P { b: 4, a: 3 };\n$PQ" "struct P { a; b; }\nvar p = P { b: 4, a: 3 };\n$PQ"
same S32 34 "kernel;\nstruct P { a; b; }\nvar p = P { 1, 2 };\nvar p = P { 3, 4 };\n$PQ" "kernel;\nstruct P { a; b; }\nvar p = P { 3, 4 };\n$PQ" CYRIUS_ELF64_KERNEL=1

# The ordering / value rows: ID|WANT|SOURCE, run on every leg.
ROWS="O1|53|${F}var a = 5;\nvar b = a;\nvar a = f();\nsyscall(60, b * 10 + a);\n
O2|55|${F}var a = f();\nvar b = a;\nvar a = 5;\nsyscall(60, b * 10 + a);\n
O3|55|const C = 5;\n${F}var a = f();\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + a);\n
O4|77|const C = 5;\nconst D = 7;\nvar a = C;\nvar b = a;\nvar a = D;\nsyscall(60, b * 10 + a);\n
O5|53|const C = 5;\n${F}var a = C;\nvar b = a;\nvar a = f();\nsyscall(60, b * 10 + a);\n
O6|44|enum E { A = 2; B = 4; }\nvar a = E.A;\nvar b = a;\nvar a = E.B;\nsyscall(60, b * 10 + a);\n
O7|55|const C = 5;\nvar a = 9;\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + a);\n
O8|77|enum E { A = 7; }\nvar B[1] = { 3 };\nvar c = load8(&B);\nvar B = A;\nsyscall(60, c * 10 + B);\n
O9|55|const C = 5;\nvar a = C;\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + a);\n
O10|9|fn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = 5;\nsyscall(60, G);\n
O11|9|const C = 5;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n
O12|9|fn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = 0;\nsyscall(60, G);\n
O13|9|const C = 5;\nvar G = 3;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n
O14|9|const C = 5;\nfn g(): i64 { return 9; }\nvar z = g();\nvar a = C;\nvar a = 5;\n
N1|7|var a = 5;\nvar b = a;\nvar a = 7;\nsyscall(60, b);\n
N2|5|const C = 5;\nvar G = 3;\nvar b = G;\nvar G = C;\nsyscall(60, b);\n
N3|5|const C = 5;\nconst D = 3;\nvar a = D;\nvar b = a;\nvar a = C;\nsyscall(60, b);\n
N4|44|enum E { A = 2; B = 4; }\nvar a = E.A;\nvar b = a;\nvar a = E.B;\nsyscall(60, b * 10 + a);\n
N5|5|var G = 0;\nvar b = G;\nvar G = 5;\nsyscall(60, b);\n
N6|5|const C = 5;\nvar G = 0;\nvar b = G;\nvar G = C;\nsyscall(60, b);\n
N7|9|var G = 3;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = 5;\nsyscall(60, G);\n
N8|9|const C = 5;\nvar G = 3;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n
N9|9|const C = 5;\nconst D = 3;\nvar G = D;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n
N10|9|const C = 5;\nvar G = 0;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n
N11|9|var G = 0;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = 5;\nsyscall(60, G);\n
N12|51|const C = 5;\nvar n = 0;\nfn f(): i64 { n = n + 1; return 3; }\nvar a = f();\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + n);\n
N14|4|var G: f64 = 1.5;\nvar b = load64(&G);\nvar G: f64 = 2.5;\nsyscall(60, (b >> 48) & 255);\n
N15|4|var K = 1.5;\nvar b = load64(&K);\nvar K = 2.5;\nsyscall(60, (b >> 48) & 255);\n
N16|224|var G: f64 = 1.5;\nfn setg(): i64 { G = 0.5; return 1; }\nvar r = setg();\nvar G: f64 = 2.5;\nsyscall(60, (load64(&G) >> 48) & 255);\n
N17|64|var F: f32 = 1.5;\nvar b = load32(&F);\nvar F: f32 = 2.5;\nsyscall(60, (b >> 24) & 255);\n
N18|4|const CF = 2.5;\nvar G: f64 = 1.5;\nvar b = load64(&G);\nvar G: f64 = CF;\nsyscall(60, (b >> 48) & 255);\n
N19|4|var G: f64 = 1.5;\nvar b = load64(&G);\nvar G: f64 = 1.5 + 1.0;\nsyscall(60, (b >> 48) & 255);\n
N20|252|fn fx(): f64 { return 2.5; }\nvar G: f64 = 1.5;\nvar b = load64(&G);\nvar G: f64 = fx();\nsyscall(60, ((b >> 48) & 255) + ((load64(&G) >> 48) & 255));\n
N21|249|var n = 0;\nfn fx(): f64 { n = n + 1; return 2.5; }\nvar G: f64 = fx();\nvar b = load64(&G);\nvar G: f64 = 1.5;\nsyscall(60, ((b >> 48) & 255) + n);\n
N22|248|var G: f64 = 0;\nvar b = load64(&G);\nvar G: f64 = 1.5;\nsyscall(60, (b >> 48) & 255);\n
N13|11|const T = true;\nvar G: bool = T;\nfn setg(): i64 { G = false; return 1; }\nvar r = setg();\nvar G: bool = T;\nsyscall(60, G + 10);\n
D1|5|var R = (0 - 0x7FFFFFFFFFFFFFFF - 1) % (0 - 1);\nsyscall(60, R + 5);\n
D2|8|enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }\nvar Q = (0 - CF_MAX - 1) / (0 - 1);\nsyscall(60, (Q >> 63) + 7);\n
D3|3|enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }\nvar R = (0 - CF_MAX - 1) % (0 - 1);\nsyscall(60, R + 3);\n
F16|250|const N = 0 - 3;\nfn f(): i64 { return 2 * N; }\nsyscall(60, f() & 255);\n
F17|14|const C = 5;\nfn f(): i64 { var C = 7; return 2 * C; }\nsyscall(60, f());\n
F18|4|const C = 5;\nfn f(): i64 { return 2 + C >>> 1; }\nsyscall(60, f());\n
F19|22|const C = 5;\nfn f(): i64 { return 2 + C *% 4; }\nsyscall(60, f());\n
F20|206|const C = 5;\nfn f(): i64 { return 100 - C * 30; }\nsyscall(60, f() & 255);\n
F21|10|const C = 5;\nfn f(): i64 { return 2 * (C); }\nsyscall(60, f());\n
F22|21|fn f(): i64 { return 9 + 3 *% 4; }\nsyscall(60, f() & 255);\n
F23|21|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 + 3 *| 4; }\nsyscall(60, f() & 255);\n
F24|21|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 + 3 *? 4; }\nsyscall(60, f() & 255);\n
F25|21|fn f(): i64 { return 9 + 48 >>> 2; }\nsyscall(60, f() & 255);\n
F26|253|fn f(): i64 { return 9 - 3 *% 4; }\nsyscall(60, f() & 255);\n
F27|253|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 - 3 *| 4; }\nsyscall(60, f() & 255);\n
F28|253|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 - 3 *? 4; }\nsyscall(60, f() & 255);\n
F29|45|fn f(): i64 { return 57 - 48 >>> 2; }\nsyscall(60, f() & 255);\n
F30|8|fn f(): i64 { return 9 & 3 *% 4; }\nsyscall(60, f() & 255);\n
F31|8|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 & 3 *| 4; }\nsyscall(60, f() & 255);\n
F32|8|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 & 3 *? 4; }\nsyscall(60, f() & 255);\n
F33|8|fn f(): i64 { return 57 & 48 >>> 2; }\nsyscall(60, f() & 255);\n
F34|13|fn f(): i64 { return 9 | 3 *% 4; }\nsyscall(60, f() & 255);\n
F35|13|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 | 3 *| 4; }\nsyscall(60, f() & 255);\n
F36|13|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 | 3 *? 4; }\nsyscall(60, f() & 255);\n
F37|13|fn f(): i64 { return 9 | 48 >>> 2; }\nsyscall(60, f() & 255);\n
F38|5|fn f(): i64 { return 9 ^ 3 *% 4; }\nsyscall(60, f() & 255);\n
F39|5|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 ^ 3 *| 4; }\nsyscall(60, f() & 255);\n
F40|5|include \"lib/overflow.cyr\"\nfn f(): i64 { return 9 ^ 3 *? 4; }\nsyscall(60, f() & 255);\n
F41|5|fn f(): i64 { return 9 ^ 48 >>> 2; }\nsyscall(60, f() & 255);\n
F42|246|fn f(): i64 { return 2 - 3 *% 4; }\nsyscall(60, f() & 255);\n
F43|14|fn f(): i64 { return 2 + 3 *% 4; }\nsyscall(60, f());\n
F44|6|fn f(): i64 { return 2 + 16 >>> 2; }\nsyscall(60, f());\n
F45|9|fn g(): i64 { return 1 | 2 *% 4; }\nsyscall(60, g());\n
Z1|2|struct P { a; b; }\nvar p = P { 1, 2 };\nsyscall(60, p.b);\n
Z2|12|struct P { a; b; }\nvar p = P { b: 2, a: 1 };\nsyscall(60, p.a * 10 + p.b);\n
Z3|56|var t = (3, 4);\nvar u: (i64, i64) = (5, 6);\nsyscall(60, t.0 + t.1 + u.0 * 10 + u.1 - 7);\n
Z4|179|struct I { x: i8; y: i32; }\nstruct O { a; i: I; c: u16; }\nvar o = O { 1, 0x7F, 0x11223344, 0xBEEF };\nsyscall(60, (o.a + o.i.x + o.i.y + o.c) & 255);\n
Z5|211|struct F { d: f64; g: f32; n; }\nvar f = F { 1.5, 0.1, 7 };\nsyscall(60, ((load64(&f) >> 52) + load32(&f + 8) + f.n) & 255);\n
Z6|35|enum E { A = 3; B = 4; }\nstruct P { a; b; }\nvar p = P { A, E.B + 1 };\nsyscall(60, p.a * 10 + p.b);\n
Z7|66|struct P { a; b; }\nfn rd(): i64 { return p.b; }\nvar r = rd();\nvar p = P { 5, 6 };\nsyscall(60, r * 10 + p.b);\n
Z8|33|struct P { a; b; }\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p = P { 3, 4 };\nsyscall(60, b * 10 + p.a);\n
Z9|11|struct P { a; b; }\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p = P { 1, 2 };\nsyscall(60, b * 10 + p.a);\n
Z10|92|struct P { a; b; }\nfn setp(): i64 { p.a = 9; return 1; }\nvar r = setp();\nvar p = P { 1, 2 };\nsyscall(60, p.a * 10 + p.b);\n
Z11|92|struct P { a; b; }\nvar p = P { 1, 2 };\nfn setp(): i64 { p.a = 9; return 1; }\nvar r = setp();\nvar p = P { 1, 2 };\nsyscall(60, p.a * 10 + p.b);\n
Z12|94|struct P { a; b; }\nvar p = P { 1, 2 };\nfn setp(): i64 { p.a = 9; return 1; }\nvar r = setp();\nvar p = P { 3, 4 };\nsyscall(60, p.a * 10 + p.b);\n
Z13|17|struct P { a; b; }\nvar q = P { 7, 8 };\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p: P = q;\nsyscall(60, b * 10 + p.a);\n
Z14|32|var t = (1, 2);\nvar b = t.0;\nvar t = (3, 4);\nvar a = 1;\nvar c = a;\nvar a = 2;\nsyscall(60, b * 10 + c);\n
Z15|3|struct P { a; b; }\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p = P { 3, 4 };\nsyscall(60, b);\n
Z16|9|struct P { a; b; }\nfn setp(): i64 { p.a = 9; return 0; }\nvar r = setp();\nvar p = P { 1, 2 };\nsyscall(60, p.a);\n
Z17|9|struct P { a; b; }\nvar p = P { 1, 2 };\nfn setp(): i64 { p.a = 9; return 0; }\nvar r = setp();\nvar p = P { 1, 2 };\nsyscall(60, p.a);\n
Z18|34|struct P { a; b; }\nvar p = P { b: 2, a: 1 };\nvar b = p.a;\nvar p = P { b: 4, a: 3 };\nsyscall(60, b * 10 + p.b);\n
Z19|34|struct W<T> { v: T; n; }\nvar w = W<i32> { 1, 2 };\nvar b = w.v;\nvar w = W<i32> { 3, 4 };\nsyscall(60, b * 10 + w.n);\n
Z20|34|struct P { a; b; }\nvar p: P = (P { 1, 2 });\nvar b = p.a;\nvar p: P = (P { 3, 4 });\nsyscall(60, b * 10 + p.b);\n
Z21|34|var t: (i64, i64) = (1, 2);\nvar b = t.0;\nvar t: (i64, i64) = (3, 4);\nsyscall(60, b * 10 + t.1);\n
Z22|31|struct P { a; b; }\nvar n = 0;\nfn f(): i64 { n = n + 1; return 7; }\nvar p = P { f(), 2 };\nvar b = p.a;\nvar p = P { 3, 4 };\nsyscall(60, b * 10 + n);\n
Z23|17|struct P { a; b; }\nfn f(): i64 { return 7; }\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p = P { f(), 4 };\nsyscall(60, b * 10 + p.a);\n
Z24|95|struct P { a; b; }\nfn setp(): i64 { p.a = 9; return 0; }\nvar r = setp();\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p = P { f(), 2 };\nfn f(): i64 { return 5; }\nsyscall(60, b * 10 + p.a);\n
Z25|33|struct P1 { a; }\nfn mk(): P1 { var t: P1 = P1 { 7 }; return t; }\nvar p: P1 = mk();\nvar b = p.a;\nvar p = P1 { 3 };\nsyscall(60, b * 10 + p.a);\n
Z26|94|struct P { a; b; }\nvar p = P { 1, 2 };\nfn setp(): i64 { p.a = 9; return 0; }\nvar r = setp();\nvar p = P { 1, 2 };\nvar p = P { 3, 4 };\nsyscall(60, p.a * 10 + p.b);\n
L1|14|const C = 0x0506;\nvar a = C;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L2|14|enum E { V = 0x0506; }\nvar a = E.V;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L3|16|const C = 0x0708;\nvar a = 0x0506;\nvar a = C;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L4|14|const C = 0x0708;\nvar a = C;\nvar a = 0x0506;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L5|9|fn f(): i64 { return 0x0506; }\nvar a = f();\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L6|4|fn f(): i64 { return 7; }\nvar a = f();\nvar a[1] = {0, 4};\nsyscall(60, a >> 8);\n
L7|14|const C = 0x0506;\nvar a[1] = {7};\nvar a = C;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L8|14|const C = 0x0506;\nfn f(): i64 { return 0x0102; }\nvar a = C;\nvar a = f();\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L9|14|const C = 0x0506;\nfn g(): i64 { return a; }\nvar b = g();\nvar a = C;\nvar a[1] = {9};\nsyscall(60, (b & 255) + (b >> 8));\n
L10|14|var a = 0x0506;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L11|0|const C = 0x0506;\nvar a = C;\nvar a = 1.5;\nvar a[1] = {9};\nsyscall(60, (a >> 8) & 255);\n
L12|9|const C = 0x0506;\nvar a = C;\nvar a = 1.5;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L13|14|const C = 0x0506;\nvar a = 1.5;\nvar a = C;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n
L14|63|var K = 1.5;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n
L15|0|var a = 0x0506;\nvar a = 1.5;\nvar a[1] = {9};\nsyscall(60, (a >> 8) & 255);\n
L16|63|const C = 0x0506;\nvar a = C;\nvar a = 1.5;\nvar a[1] = {9};\nsyscall(60, (a >> 56) & 255);\n
L17|72|var K = 1.5;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) + (load64(&K) & 255));\n
L18|64|var K = 1.5 + 1.0;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n
L19|191|var K = -1.5;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n
L20|63|const CF = 1.5;\nvar K = CF;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n
L21|63|var a[1] = {7};\nvar a = 1.5;\nvar a[1] = {9};\nsyscall(60, (a >> 56) & 255);\n
L22|63|fn g(): i64 { return K; }\nvar b = g();\nvar K = 1.5;\nvar K[1] = {9};\nsyscall(60, (b >> 56) & 255);\n
L23|14|var K = 1.5;\nvar K = 0x0506;\nvar K[1] = {9};\nsyscall(60, (K & 255) + (K >> 8));\n
L24|0|fn f(): f64 { return 1.5; }\nvar K = f();\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n"

# leg NAME COMPILER RUNNER... — every row compiled by COMPILER and run (RUNNER prefix; "cx" runs the .cyx on cxvm).
leg() {
  name=$1; comp=$2; shift 2
  printf '%s\n' "$ROWS" | while IFS='|' read -r id want src; do
    [ -n "$id" ] || continue
    printf '%b' "$src" > "$W/$name.$id.cyr"
    if ! "$comp" < "$W/$name.$id.cyr" > "$W/$name.$id" 2> "$W/$name.$id.err" || [ ! -s "$W/$name.$id" ]; then
      echo "  FAIL: const_init_bake_and_fold $name $id: compile failed: $(grep -m1 '^error' "$W/$name.$id.err")"; echo x >> "$W/fails"; continue
    fi
    chmod +x "$W/$name.$id"; x=0
    if [ "$name" = cx ]; then timeout 20 "$VM" < "$W/$name.$id" > /dev/null 2>&1 || x=$?
    else timeout 20 "$@" "$W/$name.$id" > /dev/null 2>&1 || x=$?; fi
    [ "$x" -eq "$want" ] || { echo "  FAIL: const_init_bake_and_fold $name $id: exit $x, expected $want"; echo x >> "$W/fails"; }
    echo r >> "$W/rows"
  done
}
: > "$W/fails"; : > "$W/rows"
leg x86_64 "$CC" env
if cat src/main_cx.cyr | "$CC" > "$W/cycc_cx" 2> /dev/null && [ -s "$W/cycc_cx" ] && cat programs/cxvm.cyr | "$CC" > "$W/cxvm" 2> /dev/null && [ -s "$W/cxvm" ]; then
  chmod +x "$W/cycc_cx" "$W/cxvm"; VM="$W/cxvm"; leg cx "$W/cycc_cx"
else bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v qemu-aarch64 > /dev/null 2>&1; then
  if cat src/main_aarch64.cyr | "$CC" > "$W/cycc_a64" 2> /dev/null && [ -s "$W/cycc_a64" ]; then
    chmod +x "$W/cycc_a64"; leg aarch64 "$W/cycc_a64" qemu-aarch64
  else bad "aarch64 leg: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP: const_init_bake_and_fold aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
nf=$(wc -l < "$W/fails" | tr -d ' '); nr=$(wc -l < "$W/rows" | tr -d ' ')
fail=$((fail + nf)); rows=$((rows + nr))

# F — item 2: a constant on the right folds. fold ID COMPILER LEG EXPR VALUE: `return EXPR;` and `return VALUE;`
# compile to the same bytes.
FH='const C = 5;\nenum E { A = 3; B = 9; }\n'
fold() {
  printf '%b' "${FH}fn f(): i64 { $4 }\nsyscall(60, f() & 255);\n" > "$W/f.$3.$1.cyr"
  printf '%b' "${FH}fn f(): i64 { return $5; }\nsyscall(60, f() & 255);\n" > "$W/f.$3.$1.l.cyr"
  if "$2" < "$W/f.$3.$1.cyr" > "$W/f.$3.$1" 2> /dev/null && "$2" < "$W/f.$3.$1.l.cyr" > "$W/f.$3.$1.l" 2> /dev/null; then
    cmp -s "$W/f.$3.$1" "$W/f.$3.$1.l" || bad "$3 $1: \`$4\` is not folded to $5 (not byte-identical to \`return $5;\`)"
  else bad "$3 $1: compile failed"; fi
}
foldset() {
  for spec in 'F1~return 2 * C;~10' 'F2~return 1 + C;~6' 'F3~return 2 + C * 3;~17' 'F4~return 2 * E.A;~6' \
              'F5~return 2 * A;~6' 'F6~return 2 * B * C;~90' 'F7~return 20 / C;~4' 'F8~return 1 << C;~32' \
              'F9~return 64 >> C;~2' 'F10~return 1 | C;~5' 'F11~return 7 & C;~5' 'F12~return 1 ^ C;~4' \
              'F13~return 9 - C;~4' 'F14~const L = 4; return 3 * L;~12' 'F15~return 2 + 5 * 3;~17'; do
    id=${spec%%~*}; rest=${spec#*~}; ex=${rest%%~*}; val=${rest#*~}
    rows=$((rows + 1)); fold "$id" "$1" "$2" "$ex" "$val"
  done
}
foldset "$CC" x86_64
[ -x "$W/cycc_a64" ] && foldset "$W/cycc_a64" aarch64
[ -x "$W/cycc_cx" ] && foldset "$W/cycc_cx" cx
rows=$((rows + 1))
mkdir -p "$W/v3/lib"
printf 'private\nconst PC = 5;\npublic fn pv(): i64 { return PC; }\n' > "$W/v3/lib/sec.cyr"
printf 'include "lib/sec.cyr"\nfn f(): i64 { return 2 * PC; }\nsyscall(60, f());\n' > "$W/v3/m.cyr"
rc=0; (cd "$W/v3" && "$CC" < m.cyr > m.bin 2> m.err) || rc=$?
[ "$rc" -ne 0 ] && grep -q "'PC' is private to its file" "$W/v3/m.err" || bad "V3: \`2 * PC\` (another file's private const) was not refused (rc $rc)"

# V — the replay's own reports for these entries are kept.
rows=$((rows + 1))
mkdir -p "$W/v/lib"
printf 'private\nconst PC = 5;\npublic fn pv(): i64 { return PC; }\n' > "$W/v/lib/sec.cyr"
printf 'include "lib/sec.cyr"\nvar X = PC;\nsyscall(60, X);\n' > "$W/v/m.cyr"
rc=0; (cd "$W/v" && "$CC" < m.cyr > m.bin 2> m.err) || rc=$?
[ "$rc" -ne 0 ] && grep -q "'PC' is private to its file" "$W/v/m.err" || bad "V1: \`var X = PC;\` (another file's private const) was not refused (rc $rc): $(grep -m1 -E '^(error|warning)' "$W/v/m.err")"
rows=$((rows + 1))
printf 'const C = 5;\nconst Z = 0;\nconst BC = 1;\nvar P: *i64 = C;\nvar Q: *i64 = Z;\nvar b: bool = BC;\nsyscall(60, 0);\n' > "$W/v2.cyr"
rc=0; "$CC" < "$W/v2.cyr" > "$W/v2" 2> "$W/v2.err" || rc=$?
# `|| true`: a grep matching nothing exits 1, which `bash -eo pipefail` turns into the gate's exit (CI may run a gate either way)
nw=$(grep -c '^warning.*assigning non-pointer to typed pointer' "$W/v2.err" || true)
[ "$rc" -ne 0 ] && [ "$nw" -eq 2 ] && grep -q "^error.*cannot initialize bool 'b'" "$W/v2.err" \
  || bad "V2: want the two \`*T\` warnings (lines 4, 5) and the bool refusal: rc $rc, $(grep -E '^(error|warning)' "$W/v2.err" | tr '\n' '|')"
# V4 / V5 — 6.7.15: an entry a later constant superseded still has its replay's reports (it runs into its sink, never
# stepped): another file's private const before a literal, a bool global's non-bool value before a bool constant.
rows=$((rows + 1))
printf 'include "lib/sec.cyr"\nvar X = PC;\nvar X = 5;\nsyscall(60, X);\n' > "$W/v/m4.cyr"
rc=0; (cd "$W/v" && "$CC" < m4.cyr > m4.bin 2> m4.err) || rc=$?
[ "$rc" -ne 0 ] && grep -q "'PC' is private to its file" "$W/v/m4.err" || bad "V4: a superseded \`var X = PC;\` was not refused (rc $rc): $(grep -m1 -E '^(error|warning)' "$W/v/m4.err")"
rows=$((rows + 1))
printf 'const BC = 1;\nconst T = true;\nvar b: bool = BC;\nvar b: bool = T;\nsyscall(60, 0);\n' > "$W/v5.cyr"
rc=0; "$CC" < "$W/v5.cyr" > "$W/v5" 2> "$W/v5.err" || rc=$?
[ "$rc" -ne 0 ] && grep -q "^error.*cannot initialize bool 'b'" "$W/v5.err" || bad "V5: a superseded \`var b: bool = BC;\` was not refused (rc $rc): $(grep -m1 -E '^(error|warning)' "$W/v5.err")"

# V6-V8 — 6.7.15: a baked literal whose stores are dropped still gives every diagnostic its walk gives: an integer into
# an f64 field warns (and no store is left), a bool field's non-bool value and another file's private const are refused.
rows=$((rows + 1))
printf 'struct F { d: f64; n; }\nvar f = F { 3, 7 };\nsyscall(60, load64(&f) + f.n);\n' > "$W/v6.cyr"
rc=0; "$CC" < "$W/v6.cyr" > "$W/v6" 2> "$W/v6.err" || rc=$?
if [ "$rc" -eq 0 ]; then
  grep -q '^warning:<source>:2:14: an integer stored into an f64/f32 slot keeps its integer bits' "$W/v6.err" || bad "V6: no integer-into-f64-field warning at 2:14: $(grep -m1 -E '^(error|warning)' "$W/v6.err")"
  e=$(od -An -tx1 -j 176 -N 10 "$W/v6" | tr -d ' \n')
  [ "$e" = e900000000b83c000000 ] || bad "V6: entry code is $e, want e900000000b83c000000 (no startup store)"
  chmod +x "$W/v6"; x=0; "$W/v6" > /dev/null 2>&1 || x=$?
  [ "$x" -eq 10 ] || bad "V6: exit $x, expected 10"
else bad "V6: compile failed: $(grep -m1 '^error' "$W/v6.err")"; fi
rows=$((rows + 1))
printf 'struct B { ok: bool; n; }\nvar q = B { 1, 7 };\nsyscall(60, q.n);\n' > "$W/v7.cyr"
rc=0; "$CC" < "$W/v7.cyr" > "$W/v7" 2> "$W/v7.err" || rc=$?
[ "$rc" -ne 0 ] && grep -q "^error:<source>:2:13: cannot store a value that is not a bool into bool field 'ok'" "$W/v7.err" \
  || bad "V7: \`B { 1, 7 }\` into a bool field was not refused at 2:13 (rc $rc): $(grep -m1 -E '^(error|warning)' "$W/v7.err")"
rows=$((rows + 1))
printf 'include "lib/sec.cyr"\nstruct P { a; b; }\nvar p = P { PC, 2 };\nsyscall(60, p.a);\n' > "$W/v/m8.cyr"
rc=0; (cd "$W/v" && "$CC" < m8.cyr > m8.bin 2> m8.err) || rc=$?
[ "$rc" -ne 0 ] && grep -q "'PC' is private to its file" "$W/v/m8.err" || bad "V8: \`P { PC, 2 }\` (another file's private const) was not refused (rc $rc): $(grep -m1 -E '^(error|warning)' "$W/v/m8.err")"

# T1-T4 — 6.7.15: tests/tcyr/crossos/global_constant_redeclaration_order.tcyr, every assertion, on x86_64, aarch64
# (qemu), cx (cxvm) and PE (wine, the private prefix above).
TC="$ROOT/tests/tcyr/crossos/global_constant_redeclaration_order.tcyr"
NT=$(grep -c '^assert_eq' "$TC")
# tl ID BIN [RUNNER...] — BIN (the compiled file) runs to exit 0 with every assertion passed
tl() {
  rows=$((rows + 1)); id=$1; b=$2; shift 2
  [ -s "$b" ] || { bad "$id: the crossos file did not compile"; return; }
  chmod +x "$b"; x=0
  if [ "$id" = T3 ] || [ "$id" = T7 ] || [ "$id" = T11 ] || [ "$id" = T15 ]; then timeout 60 "$VM" < "$b" > "$b.out" 2>&1 || x=$?
  else timeout 180 "$@" "$b" > "$b.out" 2> /dev/null || x=$?; fi
  [ "$x" -eq 0 ] && grep -q "$NT passed, 0 failed" "$b.out" || bad "$id: exit $x: $(grep -m3 FAIL "$b.out" | tr '\n' '|')$(tail -1 "$b.out")"
}
"$CC" < "$TC" > "$W/t1" 2> /dev/null; tl T1 "$W/t1" env
if [ -x "$W/cycc_a64" ]; then "$W/cycc_a64" < "$TC" > "$W/t2" 2> /dev/null; tl T2 "$W/t2" qemu-aarch64; fi
if [ -x "$W/cycc_cx" ]; then "$W/cycc_cx" < "$TC" > "$W/t3" 2> /dev/null; tl T3 "$W/t3"; fi
if command -v wine > /dev/null 2>&1; then
  CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$W/t4.exe" 2> /dev/null
  tl T4 "$W/t4.exe" env WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' wine
else echo "  SKIP: const_init_bake_and_fold T4 (PE) — wine not installed"; skips=$((skips + 1)); fi
# T5-T8 — 6.7.15: tests/tcyr/crossos/zone_struct_literal_value.tcyr (baked struct / tuple literals, their orderings and
# the program-start rows) on the same four legs.
TC="$ROOT/tests/tcyr/crossos/zone_struct_literal_value.tcyr"
NT=$(grep -c '^assert_eq' "$TC")
"$CC" < "$TC" > "$W/t5" 2> /dev/null; tl T5 "$W/t5" env
if [ -x "$W/cycc_a64" ]; then "$W/cycc_a64" < "$TC" > "$W/t6" 2> /dev/null; tl T6 "$W/t6" qemu-aarch64; fi
if [ -x "$W/cycc_cx" ]; then "$W/cycc_cx" < "$TC" > "$W/t7" 2> /dev/null; tl T7 "$W/t7"; fi
if command -v wine > /dev/null 2>&1; then
  CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$W/t8.exe" 2> /dev/null
  tl T8 "$W/t8.exe" env WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' wine
else echo "  SKIP: const_init_bake_and_fold T8 (PE) — wine not installed"; skips=$((skips + 1)); fi
# T9-T12 — 6.7.15: tests/tcyr/crossos/zone_float_constant_initializer.tcyr (a float global's constant f64 expression
# baked as its literal is: the bits on each target, an earlier read, an earlier call's write) on the same four legs.
TC="$ROOT/tests/tcyr/crossos/zone_float_constant_initializer.tcyr"
NT=$(grep -c '^assert_eq' "$TC")
"$CC" < "$TC" > "$W/t9" 2> /dev/null; tl T9 "$W/t9" env
if [ -x "$W/cycc_a64" ]; then "$W/cycc_a64" < "$TC" > "$W/t10" 2> /dev/null; tl T10 "$W/t10" qemu-aarch64; fi
if [ -x "$W/cycc_cx" ]; then "$W/cycc_cx" < "$TC" > "$W/t11" 2> /dev/null; tl T11 "$W/t11"; fi
if command -v wine > /dev/null 2>&1; then
  CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$W/t12.exe" 2> /dev/null
  tl T12 "$W/t12.exe" env WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' wine
else echo "  SKIP: const_init_bake_and_fold T12 (PE) — wine not installed"; skips=$((skips + 1)); fi

# T13-T16 — 6.7.16: tests/tcyr/crossos/global_array_initializer.tcyr (its list-over-a-named-scalar rows, L1-L9's,
# L12's and L13's shapes in one zone) on the same four legs.
TC="$ROOT/tests/tcyr/crossos/global_array_initializer.tcyr"
NT=$(grep -c '^assert_eq' "$TC")
"$CC" < "$TC" > "$W/t13" 2> /dev/null; tl T13 "$W/t13" env
if [ -x "$W/cycc_a64" ]; then "$W/cycc_a64" < "$TC" > "$W/t14" 2> /dev/null; tl T14 "$W/t14" qemu-aarch64; fi
if [ -x "$W/cycc_cx" ]; then "$W/cycc_cx" < "$TC" > "$W/t15" 2> /dev/null; tl T15 "$W/t15"; fi
if command -v wine > /dev/null 2>&1; then
  CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$W/t16.exe" 2> /dev/null
  tl T16 "$W/t16.exe" env WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' wine
else echo "  SKIP: const_init_bake_and_fold T16 (PE) — wine not installed"; skips=$((skips + 1)); fi

[ "$rows" -ge 50 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL const_init_bake_and_fold: $fail of $rows row(s) red"; exit 1; fi
echo "PASS const_init_bake_and_fold: $rows rows — a folded constant global and a baked struct / tuple literal have no startup code (byte-identical to the literal / list), every constant redeclaration is the value from program start (6.7.15) on x86_64 / aarch64 / cx / PE, D11's repros give 5 / 8 / 3, the replay's reports are kept"
exit 0
