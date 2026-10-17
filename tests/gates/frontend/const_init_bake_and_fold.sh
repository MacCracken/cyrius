#!/bin/sh
# const_init_bake_and_fold.sh — 6.7.14: a declaration-zone global whose initializer folds to a constant is its value
# from program start, with no startup code (issues/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md
# item 1; issues/2026-10-11-folded-zero-or-enum-global-reruns-at-startup-decision.md, the user's decision D11 (b),
# 2026-10-16).
#
# Since 6.6.16 `var X = C;`, `= E.A`, `= A + 1` were baked into the image (_gvk_pre) AND replayed at startup — the
# expression re-run and stored again (x86_64: `mov eax,5; movabs rcx,X; mov [rcx],rax`, 18 bytes) — where `var X =
# 5;` emits nothing. A global folding to zero or through an enum constant re-ran a trapping division there:
# `var R = INT_MIN % -1;` and `var Q = (0 - CF_MAX - 1) / (0 - 1);` died SIGFPE (136) on x86_64 and cx, ran on
# aarch64. The replay now steps over a baked entry whose store wrote what the slot already holds (_gvk_quiet): the
# image value is its own and the nearest earlier replayed writer of the slot, if any, is a baked entry of that
# value. A computed initializer or a constant of another value before it keeps the store, in order.
#
#   S0-S7  the store is gone: each build is BYTE-IDENTICAL to the same program with the literal written out —
#          S0 the filed repro (`var X = C;`, exit 15), S1 `= C`, S2 `= E.A`, S3 `= A + 1`, S4 narrow `u8` / `i32`,
#          S5 D11's repro A (folds to zero) against `= 0`, S6 repro B (enum) against its literal; S7 `= 0` emits
#          nothing at the entry
#   O1-O12 orderings, by value, on x86_64, aarch64 (qemu, the tree's cross compiler) and cx (the tree's cycc_cx +
#          cxvm): a constant / computed redeclaration in either order, two constants, an enum pair, a literal then
#          a const, a list then a scalar, a same-valued redeclaration, and the program-start rule — a call in an
#          EARLIER initializer that writes the global keeps its write over `= C` / `= 0` (as it did over `= 5`)
#   D1-D3  D11's repros A, B and B's `%` twin exit 5 / 8 / 3 on x86_64, aarch64 and cx (PE: the crossos file
#          const_fold_int_min_div.tcyr on wine and cass)
#   K1     an x86 `kernel;` build (ELF64): the program reads the baked values, no late-replay warning, and the build
#          is byte-identical to the literal one (no late store)
#   V1-V2  what the replay's parse reports is still reported: another file's private const (`'PC' is private to its
#          file`), a `*T` global's "assigning non-pointer to typed pointer", a bool global's refusal
#
# Item 2 — the run-time fold arms (parse_expr.cyr `_PARSE_TERM_IMPL` / `_PEXPR_IMPL`) take a constant NAME on the
# right (and `+ - & | ^` a constant term): `2 * C` was `mov eax,2; push rax; mov eax,5; pop rcx; imul rcx`, `1 + C`
# an add, `2 + C * 3` an add of the folded `C * 3`.
#   F1-F15 each `return <expr>;` is BYTE-IDENTICAL to `return <its value>;` — on x86_64, and with the tree's aarch64
#          and cx compilers: `2 * C` (the filed shape), `1 + C`, `2 + C * 3`, `2 * E.A`, `2 * A`, `2 * B * C`,
#          `20 / C`, `1 << C`, `64 >> C`, `1 | C`, `7 & C`, `1 ^ C`, `9 - C`, a local const `3 * L`, and the
#          literal term `2 + 5 * 3`
#   F16-F21 values on every leg, the folded and the not folded: a negative const, a local var hiding the const,
#          `>>>` (never folded), `*%` in a name's term, a result under zero, `2 * (C)`; V3 another file's private
#          const on the right is still refused
#
# MUTATION (item 2, measured): _cf_fac_at reading a literal only (its name arms gone) -> 42 red: F1-F14 on x86_64,
# aarch64 and cx (F15, the literal term, still folds); _cf_can's term arm gone -> 21 red: F2, F3, F10-F13, F15 on
# the three legs (the `* / << >>` arms F1, F4-F9, F14 still fold their factor).
# MUTATION (measured, 6.7.14, a mutated scratch copy of the tree, every leg built from it): _gvk_quiet returning 0
# (every store kept, as 6.6.16 - 6.7.13) -> 23 red: S0-S7, K1, O11 / O12 on all three legs, D1-D3 on x86_64 and cx
# (the SIGFPE, 136); _gvk_prev returning -1 (no earlier writer considered) -> 12 red: O3 / O4 / O6 / O8 on all
# three legs (the earlier computed / other-valued / list writer's value left in the slot).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: const_init_bake_and_fold: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
[ -x "$CC" ] || { echo "FAIL: const_init_bake_and_fold: no compiler at $CC"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: const_init_bake_and_fold: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0; rows=0; skips=0
bad() { echo "  FAIL: const_init_bake_and_fold $1"; fail=$((fail + 1)); }

# same ID WANT TEST LITERAL [env] — both compile clean, are byte-identical and exit WANT.
same() {
  rows=$((rows + 1))
  printf '%b' "$3" > "$W/$1.cyr"; printf '%b' "$4" > "$W/$1.l.cyr"
  r1=0; env ${5:-X=1} "$CC" < "$W/$1.cyr" > "$W/$1" 2> "$W/$1.err" || r1=$?
  r2=0; env ${5:-X=1} "$CC" < "$W/$1.l.cyr" > "$W/$1.l" 2> "$W/$1.l.err" || r2=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || { bad "$1: compile rc $r1 / $r2: $(grep -m1 '^error' "$W/$1.err" "$W/$1.l.err")"; return; }
  n=$(cat "$W/$1.err" "$W/$1.l.err" | grep -cE '^(error|warning)')
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

# The ordering / value rows: ID|WANT|SOURCE, run on every leg.
ROWS="O1|53|${F}var a = 5;\nvar b = a;\nvar a = f();\nsyscall(60, b * 10 + a);\n
O2|55|${F}var a = f();\nvar b = a;\nvar a = 5;\nsyscall(60, b * 10 + a);\n
O3|35|const C = 5;\n${F}var a = f();\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + a);\n
O4|57|const C = 5;\nconst D = 7;\nvar a = C;\nvar b = a;\nvar a = D;\nsyscall(60, b * 10 + a);\n
O5|53|const C = 5;\n${F}var a = C;\nvar b = a;\nvar a = f();\nsyscall(60, b * 10 + a);\n
O6|24|enum E { A = 2; B = 4; }\nvar a = E.A;\nvar b = a;\nvar a = E.B;\nsyscall(60, b * 10 + a);\n
O7|55|const C = 5;\nvar a = 9;\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + a);\n
O8|37|enum E { A = 7; }\nvar B[1] = { 3 };\nvar c = load8(&B);\nvar B = A;\nsyscall(60, c * 10 + B);\n
O9|55|const C = 5;\nvar a = C;\nvar b = a;\nvar a = C;\nsyscall(60, b * 10 + a);\n
O10|9|fn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = 5;\nsyscall(60, G);\n
O11|9|const C = 5;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n
O12|9|fn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = 0;\nsyscall(60, G);\n
D1|5|var R = (0 - 0x7FFFFFFFFFFFFFFF - 1) % (0 - 1);\nsyscall(60, R + 5);\n
D2|8|enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }\nvar Q = (0 - CF_MAX - 1) / (0 - 1);\nsyscall(60, (Q >> 63) + 7);\n
D3|3|enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }\nvar R = (0 - CF_MAX - 1) % (0 - 1);\nsyscall(60, R + 3);\n
F16|250|const N = 0 - 3;\nfn f(): i64 { return 2 * N; }\nsyscall(60, f() & 255);\n
F17|14|const C = 5;\nfn f(): i64 { var C = 7; return 2 * C; }\nsyscall(60, f());\n
F18|4|const C = 5;\nfn f(): i64 { return 2 + C >>> 1; }\nsyscall(60, f());\n
F19|22|const C = 5;\nfn f(): i64 { return 2 + C *% 4; }\nsyscall(60, f());\n
F20|206|const C = 5;\nfn f(): i64 { return 100 - C * 30; }\nsyscall(60, f() & 255);\n
F21|10|const C = 5;\nfn f(): i64 { return 2 * (C); }\nsyscall(60, f());\n"

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
nw=$(grep -c '^warning.*assigning non-pointer to typed pointer' "$W/v2.err")
[ "$rc" -ne 0 ] && [ "$nw" -eq 2 ] && grep -q "^error.*cannot initialize bool 'b'" "$W/v2.err" \
  || bad "V2: want the two \`*T\` warnings (lines 4, 5) and the bool refusal: rc $rc, $(grep -E '^(error|warning)' "$W/v2.err" | tr '\n' '|')"

[ "$rows" -ge 50 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL const_init_bake_and_fold: $fail of $rows row(s) red"; exit 1; fi
echo "PASS const_init_bake_and_fold: $rows rows — a folded constant global has no startup code (byte-identical to its literal), the orderings keep their values on x86_64 / aarch64 / cx, D11's repros give 5 / 8 / 3, the replay's reports are kept"
exit 0
