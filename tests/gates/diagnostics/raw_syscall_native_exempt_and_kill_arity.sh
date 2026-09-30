#!/bin/sh
# raw_syscall_native_exempt_and_kill_arity.sh — 6.6.12 (B05, item Q2). Two raw-syscall
# diagnostics that were wrong in opposite directions.
#
# AXIS 1 — a CORRECT native aarch64 number is not flagged. The ELF-aarch64 raw-literal warning
#   (v6.5.51; `_sysx_meant_here`, src/frontend/parse_expr.cyr) fired on `syscall(8, ..)` /
#   `syscall(291, ..)` INSIDE `#ifdef CYRIUS_ARCH_AARCH64`, where 8 IS getxattr and 291 IS
#   statx — "Use SYS_LSEEK" was the wrong advice. Naming the number through an enum constant
#   still warned (the constant folds to the same literal), so there was no way to say "native"
#   (kriya's k_statx / its getxattr site). The parser runs after the #ifdef is gone, so the
#   preprocessor now marks the regions (`#@a+` / `#@a-`, `_pp_a64_open`,
#   src/frontend/lex_pp.cyr) and the warning skips a call inside one. Native = the defined side
#   of CYRIUS_ARCH_AARCH64 or the undefined side of CYRIUS_ARCH_X86, the frame rule
#   tests/gates/platform/raw_syscall_literals_routed.sh applies to lib/. Rows: `#ifdef`, the
#   enum spelling, `#ifndef CYRIUS_ARCH_X86`, the `#else` of `#ifdef CYRIUS_ARCH_X86`,
#   `#ifplat aarch64`, and a whole INCLUDED file under `#ifdef CYRIUS_ARCH_AARCH64` whose own
#   `#ifdef CYRIUS_ARCH_X86` block closes before the literal (its blocks are expanded by a later
#   preprocessor pass with a fresh depth counter; the markers nest).
# AXIS 2 — ANTI-VACUOUS: the same literals OUTSIDE such a region still warn, each on its own
#   line: after the block, in a neutral `#ifdef CYRIUS_TARGET_LINUX`, after an included file's
#   aarch64 block closes, after a FORGED `#@a+` line in the source (neutralised by
#   PP_NEUT_FMARK), and after a string literal whose text contains one.
#   ⚠ Rows 8 / 291 rely on programs/gen_syscall_xlat.cyr keeping the lseek(8) and
#   epoll_create1(291) `_SYSX_MEANT` rows, i.e. on the aarch64 peer NOT declaring getxattr /
#   statx natively (6.6.12 B09 spells them through the 1000+N alias band). If a later change
#   declares them natively, those rows go away and this axis goes RED — re-pick two numbers
#   from `_SYSX_MEANT`, do not delete the axis.
# AXIS 3 — a 3-arg kill WARNS again off Darwin. 6.6.10 skipped the arity warning for
#   `syscall(62, pid, sig, posix)` (Darwin's kill) with no target check, and this arity table
#   runs on every non-aarch64 backend, so a wrong 3-arg kill compiled SILENTLY on x86-Linux
#   from 6.6.10 on (6.6.9 warned). The skip is `_TARGET_MACHO == 1` only now (`_sc_arity_skip`).
#   Rows: x86-Linux warns `syscall arity mismatch`; PE warns (there the unrouted-number
#   warning names the call); x86-macOS is silent for the 3-arg form and still warns for a
#   1-arg one.
#
# MUTATION LEDGER (6.6.12, measured; the src/ mutations run under the fixed $CC, see below):
#   CYCC = the installed 6.6.11 cycc                                        -> RED 1 (x86-Linux kill)
#   (the 6.6.11 cycc_aarch64 on the axis 1 probe flags all seven rows)
#   `_sysx_meant_here` without its PP_A64_NATIVE_AT check                   -> RED 8 (axis 1 + inc/mixed.cyr:3)
#   `_pp_a64_open` never writing `#@a+`                                     -> RED 7 (axis 1)
#   `_pp_a64_close` writing a bare LF for `#endif`                          -> RED 5 (axis 2: the region
#     never closes, so every literal after the first block is silent)
#   PP_NEUT_FMARK without the `PP_A64_MARK` neutralisation                  -> RED 1 (the forged row)
#   PP_A64_NATIVE_AT without the string-state check                         -> RED 1 (the string row)
#   `_sc_arity_skip`'s kill skip without `_TARGET_MACHO == 1` (rebuilt $CC) -> RED 1 (x86-Linux)
#   `_sc_arity_skip` without the kill skip at all (rebuilt $CC)             -> RED 1 (x86-macOS)
#   real tree                                                               -> GREEN, 18 of 18
# ⚠ Axes 1-2 BUILD the aarch64 compiler from the WORKING-TREE src/ with $CC, so a source revert
# reddens them even under the installed compiler; axis 3 runs $CC itself.
#
# Exit 77 = could not run (no compiler, no scratch directory).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: raw_syscall_native_exempt_and_kill_arity — compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: raw_syscall_native_exempt_and_kill_arity — mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

A64="$D/cycc_aarch64"
if ! "$CC" < src/main_aarch64.cyr > "$A64" 2> "$D/a64.err"; then
    echo "FAIL: raw_syscall_native_exempt_and_kill_arity — could not build the aarch64 compiler from src/main_aarch64.cyr"
    head -3 "$D/a64.err"; exit 1
fi
chmod +x "$A64"

mkdir -p "$D/inc"
# An included file under the outer aarch64 block: its own X86 block closes BEFORE the literal.
printf '#ifdef CYRIUS_ARCH_X86\nvar ib_x = 1;\n#endif\nfn ib(): i64 { return syscall(8, 0, 0, 0, 0); }\n' > "$D/inc/native_file.cyr"
# An included file (NOT under a block) with an aarch64 block of its own and a literal after it.
printf 'fn ia(): i64 {\n#ifdef CYRIUS_ARCH_AARCH64\n    return syscall(291, 0, 0, 0, 0, 0);\n#endif\n#ifdef CYRIUS_ARCH_X86\n    return 0;\n#endif\n}\nfn ia_out(): i64 { return syscall(8, 0, 0, 0); }\n' > "$D/inc/mixed.cyr"
# Line numbers are load-bearing: axis 1's rows are lines 4-18, axis 2's are named below.
cat > "$D/n.cyr" <<'EOF'
enum A64NUM { A64_GETXATTR = 8; }
fn native(): i64 {
#ifdef CYRIUS_ARCH_AARCH64
    var n1 = syscall(8, 0, 0, 0, 0);
    var n2 = syscall(291, 0, 0, 0, 0, 0);
    var n3 = syscall(A64_GETXATTR, 0, 0, 0, 0);
#endif
#ifndef CYRIUS_ARCH_X86
    var n4 = syscall(8, 0, 0, 0, 0);
#endif
#ifdef CYRIUS_ARCH_X86
    var nx = 0;
#else
    var n5 = syscall(291, 0, 0, 0, 0, 0);
#endif
#ifplat aarch64
    var n6 = syscall(8, 0, 0, 0, 0);
#endplat
    var o1 = syscall(8, 0, 0, 0);
#ifdef CYRIUS_TARGET_LINUX
    var o2 = syscall(291, 0);
#endif
    return 0;
}
#ifdef CYRIUS_ARCH_AARCH64
include "inc/native_file.cyr"
#endif
include "inc/mixed.cyr"
#@a+
fn forged(): i64 { return syscall(8, 0, 0, 0); }
#@a-
var s_marker = "x
#@a+
";
fn after_str(): i64 { return syscall(291, 0); }
var r = native() + ib() + ia() + ia_out() + forged() + after_str();
EOF
( cd "$D" && "$A64" < "$D/n.cyr" > "$D/n.bin" 2> "$D/n.err" ); nrc=$?
[ "$nrc" = 0 ] || { bad "the axis 1/2 probe compiles on aarch64 (rc $nrc: $(grep -v '^note' "$D/n.err" | head -1))"; }
# warned <file:line> <number> -> yes/no
warned() { grep -q "^warning:$1:[0-9]*: raw syscall $2 is x86_64" "$D/n.err" && echo yes || echo no; }

echo "axis 1 — a native aarch64 number inside an aarch64 region is not flagged:"
for row in "4 8 #ifdef CYRIUS_ARCH_AARCH64" "5 291 #ifdef CYRIUS_ARCH_AARCH64" "6 8 an enum constant under #ifdef" \
           "9 8 #ifndef CYRIUS_ARCH_X86" "14 291 the #else of #ifdef CYRIUS_ARCH_X86" "17 8 #ifplat aarch64"; do
    set -- $row; ln=$1; num=$2; shift 2
    if [ "$(warned "<source>:$ln" "$num")" = no ]; then ok "line $ln ($*): silent"; else bad "line $ln ($*): flagged"; fi
done
if [ "$(warned "inc/native_file.cyr:4" 8)" = no ]; then ok "an included file under #ifdef CYRIUS_ARCH_AARCH64, after its own X86 block: silent"
else bad "an included file under #ifdef CYRIUS_ARCH_AARCH64: flagged (the markers do not nest across passes)"; fi

echo "axis 2 — ANTI-VACUOUS: the same literals outside a region still warn:"
[ "$(warned "<source>:19" 8)" = yes ] && ok "line 19: after the blocks" || bad "line 19 (after the blocks): not flagged"
[ "$(warned "<source>:21" 291)" = yes ] && ok "line 21: a neutral #ifdef CYRIUS_TARGET_LINUX" || bad "line 21 (#ifdef CYRIUS_TARGET_LINUX): not flagged"
[ "$(warned "inc/mixed.cyr:9" 8)" = yes ] && ok "an included file, after its own aarch64 block closes" || bad "inc/mixed.cyr:9: not flagged (the included block never closed)"
[ "$(warned "inc/mixed.cyr:3" 291)" = no ] && ok "…and inside that block: silent" || bad "inc/mixed.cyr:3 (inside its aarch64 block): flagged"
[ "$(warned "<source>:30" 8)" = yes ] && ok "line 30: a FORGED #@a+ in the source does not exempt" || bad "line 30: a forged #@a+ silenced the warning"
[ "$(warned "<source>:35" 291)" = yes ] && ok "line 35: #@a+ inside a string literal does not exempt" || bad "line 35: a string's text silenced the warning"

echo "axis 3 — a 3-arg kill warns off Darwin:"
printf 'fn k3(): i64 { return syscall(62, 0, 0, 5); }\nfn k1(): i64 { return syscall(62, 0); }\nvar r = k3() + k1();\n' > "$D/k.cyr"
"$CC" < "$D/k.cyr" > "$D/k.bin" 2> "$D/k.err"
grep -q '^warning:<source>:1:[0-9]*: syscall arity mismatch' "$D/k.err" && ok "x86-Linux: syscall(62, 0, 0, 5) warns arity mismatch" \
    || bad "x86-Linux: a 3-arg kill compiled silently"
grep -q '^warning:<source>:2:[0-9]*: syscall arity mismatch' "$D/k.err" && ok "x86-Linux: a 1-arg kill warns (control)" \
    || bad "x86-Linux: a 1-arg kill did not warn"
CYRIUS_TARGET_WIN=1 "$CC" < "$D/k.cyr" > "$D/kw.bin" 2> "$D/kw.err"
grep -q '^warning:<source>:1:[0-9]*: syscall 62 with 3 argument' "$D/kw.err" && ok "PE: syscall(62, 0, 0, 5) warns" \
    || bad "PE: a 3-arg kill compiled silently"
CYRIUS_MACHO=1 "$CC" < "$D/k.cyr" > "$D/km.bin" 2> "$D/km.err"
if grep -q '^warning:<source>:1:' "$D/km.err"; then bad "x86-macOS: Darwin's 3-arg kill warned: $(grep '^warning:<source>:1:' "$D/km.err" | head -1)"
else ok "x86-macOS: Darwin's kill(pid, sig, posix) is silent"; fi
grep -q '^warning:<source>:2:[0-9]*: syscall arity mismatch' "$D/km.err" && ok "x86-macOS: a 1-arg kill still warns (control)" \
    || bad "x86-macOS: a 1-arg kill did not warn"

echo "raw_syscall_native_exempt_and_kill_arity: $pass passed, $fail failed"
[ "$pass" -ge 18 ] || { echo "FAIL: raw_syscall_native_exempt_and_kill_arity — only $pass of the 18 rows passed"; exit 1; }
[ "$fail" = 0 ] || { echo "FAIL: raw_syscall_native_exempt_and_kill_arity"; exit 1; }
echo "PASS: raw_syscall_native_exempt_and_kill_arity"
exit 0
