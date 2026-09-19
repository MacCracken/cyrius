#!/bin/sh
# private_per_item_rejected.sh — v6.5.56. `private fn h()` must be REJECTED, not silently
# reinterpreted as a file-level declaration.
#
# THE DEFECT, twelve releases live. `private` flips the FILE it sits in (`_TL_VIS`,
# src/frontend/parse.cyr) — deliberately, because a running per-item flag would leak into every
# file included after it. But the per-item spelling `private fn h(): i64 { ... }` parsed with
# **no diagnostic** and privatised the ENTIRE FILE, `main` included. It reads exactly like the
# per-item visibility other languages have, so it is the spelling a user reaches for first.
#
# ⭐ THE DISCRIMINATOR IS THE LINE, not the next token. `private` alone on its own line followed
# by `fn h()` on the NEXT line is the legitimate file-level form and must keep working — so a
# naive "reject if the next token is `fn`" test would break every correct use. Axes 2 and 3 are
# what stop that fix from being written.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: private_per_item_rejected: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL private_per_item_rejected: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL private_per_item_rejected: stage1 build failed"; exit 1; }
chmod +x "$T/cc"
fail=0

# axis 1 — the per-item form must HARD ERROR and say why.
printf 'include "lib/syscalls.cyr"\nprivate fn helper(): i64 { return 7; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a1.cyr"
if "$T/cc" < "$T/a1.cyr" > /dev/null 2>"$T/a1.err"; then
  echo "FAIL private_per_item_rejected axis1: 'private fn h()' COMPILED — it silently privatises the whole file including main"
  fail=1
else
  grep -q "per-item" "$T/a1.err" || { echo "FAIL private_per_item_rejected axis1: rejected without the explaining message"; sed -n 1,2p "$T/a1.err"; fail=1; }
fi

# ⚠ 6.6.5 — every status that is DATA here (a probe's exit code, a refused compile) is
# captured into a variable through `|| rc=$?`, never left bare. Axes 2 and 3 used to run
# `"$T/cc" < a2.cyr … && "$T/a2"` and read `$?`, so under `bash -eo pipefail` the probe's
# exit code 7 killed the script at that line — the file exited 7 with NO output and the
# four axes below it never ran. check.sh invokes gates with `sh`, so nothing was red; a CI
# runner that uses bash -e would have silently skipped most of this file.
run_rc() {   # run_rc <src> <bin> -> echoes the program's exit code, or -1 if it did not build
  _s=$1; _b=$2; _c=0
  "$T/cc" < "$_s" > "$_b" 2>/dev/null || _c=$?
  if [ ! -s "$_b" ]; then echo "-1"; return 0; fi
  chmod +x "$_b"; _r=0; "$_b" || _r=$?; echo "$_r"
}

# axis 2 — the file-level form (own line) must STILL WORK. This is what stops the axis-1 fix
# from being written as "reject if followed by fn".
printf 'include "lib/syscalls.cyr"\nprivate\nfn helper(): i64 { return 7; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a2.cyr"
r2=$(run_rc "$T/a2.cyr" "$T/a2")
[ "$r2" = "7" ] || { echo "FAIL private_per_item_rejected axis2: file-level 'private' on its own line no longer works (got $r2)"; fail=1; }

# axis 3 — the `private;` form must still work too (the trailing semicolon closes the statement,
# so a following `fn` on the SAME line is legal there).
printf 'include "lib/syscalls.cyr"\nprivate; fn helper(): i64 { return 9; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a3.cyr"
r3=$(run_rc "$T/a3.cyr" "$T/a3")
[ "$r3" = "9" ] || { echo "FAIL private_per_item_rejected axis3: 'private;' form regressed (got $r3)"; fail=1; }

# ⛔ 6.6.5 — axis 3b. `private` as the LAST TOKEN of a compiland, with no trailing newline.
# LEX appends its EOF token with ADDTOK(S, 12, 0) on whatever line the source ended on, so
# the EOF shares the marker's line and the line discriminator read it as the per-item form:
# the first cut of the 6.6.5 pre-pass answered "per-item `private` is not supported" to a
# source that breaks no such rule. The file-level form must be accepted wherever it appears,
# including as the final byte. ⚠ The fixture is written with printf and NO trailing \n — a
# heredoc would add one and the row would test nothing.
printf 'include "lib/syscalls.cyr"\nfn helper(): i64 { return 11; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\nprivate' > "$T/a3b.cyr"
r3b=$(run_rc "$T/a3b.cyr" "$T/a3b")
[ "$r3b" = "11" ] || { echo "FAIL private_per_item_rejected axis3b: 'private' as the final token (no trailing newline) did not build+run (got $r3b)"; fail=1; }
"$T/cc" < "$T/a3b.cyr" > /dev/null 2> "$T/a3b.err" || true
if grep -q "per-item" "$T/a3b.err" 2>/dev/null; then
  echo "FAIL private_per_item_rejected axis3b: 'private' at EOF was reported as the per-item form — the EOF token is not 'something on the line'"; fail=1
fi

# ⛔ 6.6.5 — axes 4 and 5. The v6.5.56 rejection was emitted from `_TL_VIS`, which BOTH
# parser passes walk, and it marked the file private BEFORE it rejected. Two consequences,
# both live for nine releases and neither visible to axes 1-3:
#   * the diagnostic printed TWICE for one `private fn h()`;
#   * the file was flipped private anyway, so a LEGITIMATE sibling fn in it was then
#     reported "is private to its file" at its caller — a false cascade blaming innocent
#     code for a mistake made elsewhere in the file, which is worse than the original
#     silence because it points the reader at the wrong line.
# Both are fixed by doing the work once, in the pre-pass that runs before either parser
# pass (`_PRIV_PRESCAN`, src/frontend/parse.cyr), and marking ONLY the accepted form.
mkdir -p "$T/c/lib"
cat > "$T/c/lib/a4.cyr" <<'EOF'
fn a4_g(): i64 { return 7; }
private fn a4_h(): i64 { return 1; }
EOF
cat > "$T/c/a4.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/a4.cyr"
fn main(): i64 { return a4_g(); }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/c" && "$T/cc" < a4.cyr > a4.bin 2> a4.err ) || true
c4=$(grep -c "per-item" "$T/c/a4.err" 2>/dev/null || true)
[ -n "$c4" ] || c4=0
[ "$c4" = "1" ] || { echo "FAIL private_per_item_rejected axis4: the diagnostic was emitted $c4 times, expected exactly 1"; fail=1; }
if grep -q "is private to its file" "$T/c/a4.err" 2>/dev/null; then
  echo "FAIL private_per_item_rejected axis5: the REJECTED per-item form still privatised the file — a legitimate sibling fn is now reported private:"
  grep -m2 "is private to its file" "$T/c/a4.err" | sed 's/^/      /' || true
  fail=1
fi

# axis 6 — anti-vacuous for axis 5: with the per-item line REMOVED, the same two files must
# compile and run, so axis 5 cannot be satisfied by a fixture that never linked anyway. The
# expected exit is computed here, not read back from the compiler.
G=7
cat > "$T/c/lib/a6.cyr" <<EOF
fn a6_g(): i64 { return $G; }
fn a6_h(): i64 { return 1; }
EOF
cat > "$T/c/a6.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/a6.cyr"
fn main(): i64 { return a6_g(); }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/c" && "$T/cc" < a6.cyr > a6.bin 2>/dev/null ) || true
if [ -s "$T/c/a6.bin" ]; then
  chmod +x "$T/c/a6.bin"; g6=0; ( cd "$T/c" && ./a6.bin ) || g6=$?
  [ "$g6" = "$G" ] || { echo "FAIL private_per_item_rejected axis6: control program exited $g6, expected $G"; fail=1; }
else
  echo "FAIL private_per_item_rejected axis6: the control program (no per-item line) did not build"; fail=1
fi

[ $fail -eq 0 ] || exit 1
echo "PASS private_per_item_rejected: per-item form errors ONCE, does not privatise the file, and the own-line / 'private;' / at-EOF forms still work"
exit 0
