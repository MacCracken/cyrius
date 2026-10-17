#!/bin/sh
# tests/gates/toolchain/cybs_diagnostics_named.sh — 6.7.11
#
# cybs (the bootstrap compiler the seed assembles; bootstrap/cybs.cyr) compiles a subset of cyrius,
# and when src/ used anything outside it — const, loop, do/while, an if-expression, unary minus,
# >>>, >>= — or just a syntax error, cybs printed two words, `syntax error` (or `undefined
# variable`), with no line, no name and no construct, for seed-derive's 1.7 MB input spliced from
# 20+ files. The user's decision (2026-10-13, option A): parse_err prints ONE message that lists
# what cybs lacks, followed by the text of the offending line from the expanded stream; the
# undefined-variable path names the identifier and prints its line. Tokens carry no file, but the
# line's text greps straight to its src/ file. The lexer records each token's position in the
# stream (a cybs-private region, r15 + 0xA000000). Per-construct refusals and file:line need more
# seed labels than are left: issues/2026-10-13-cybs-per-construct-refusal-and-file-line.md, the
# seed-rotation minor. issues/archived/2026-10-08-cybs-bare-syntax-error-no-location.md
#
#   A  closure: the seed assembles cybs, and cybs reproduces the seed
#   L  the filed loop repro, verbatim: exit 1, nothing on stdout, and stderr is exactly the class
#      message + ` at: ` + the line
#   T  every other row of the filing's table, each in a multi-line `fn main() { .. }` so the line
#      printed must be the construct's own: const at the top level and in a fn, do/while, an
#      if-expression, `-a`, `-3`, `>>>`, `>>=`, `fn bad( { }` after valid code
#   N  the undefined-name path names the identifier and prints its line: `var x = nosuch(1);`, and
#      a top-level const read from a fn (cybs compiles fn bodies before top-level statements)
#   I  the line comes from the EXPANDED stream: an error inside an included file prints that file's
#      line, and one after an include prints the main file's
#   E  an error at the end of the input prints the last token's line, not an empty one
#   K  the input ends right after `fn` or `var` (`fn`, `var`, `fn ` with a trailing blank): exit 1, the class
#      message at the keyword's line, nothing written. Pass 0 (shallow_fn / shallow_global) stepped over the
#      name unchecked, past the EOF token, and every later EOF test read beyond the token array: SIGSEGV (139),
#      nothing on stderr. 6.7.14, issues/2026-10-14-cybs-segfaults-on-eof-after-fn-or-var.md
#   V  ANTI-VACUOUS: a valid program using every neighbour of the refused shapes (`0 - a`, `>>`,
#      `while`, an if statement, a top-level var, a forward call) compiles and runs (exit 42)
#
# Mutations (6.7.11, each verified RED in a scratch copy of the tree):
#   parse_err's `mov rdx, 140` back to 13 and the line not written (jmp sys_exit_err)  -> L T I E RED
#   lexer_emit_kw's position store dropped (a keyword token keeps position 0)           -> T RED (the
#                                                                                         if-expression row prints line 1)
#   find_var_undef back to `jmp sys_exit_err` after its message (no name, no line)      -> N RED
#   parse_err's end-of-input step (`dec rbx`) dropped                                   -> E RED (an empty line)
# 6.7.14:
#   shallow_fn's and shallow_global's IDENT test dropped (the 6.7.13 cybs)              -> K RED (rc 139, all three)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_diagnostics_named: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_diagnostics_named: bootstrap/asm missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_diagnostics_named: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_diagnostics_named $1"; fail=$((fail + 1)); }

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_diagnostics_named: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }
cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
cmp -s "$D/asm2" bootstrap/asm && echo "  ok   A: closure — cybs reproduces the seed" || bad "A: closure — cybs no longer reproduces the seed"

SYN='cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=), at: '
UND='cybs: undefined variable or function (cybs has no const): '
# says <row> <file> <what> <expected stderr line>: cybs (run in $D, so an include resolves there) must
# exit 1, write nothing to stdout, and print exactly that one line
says() {
  rc=0; (cd "$D" && ./cybs < "$2" > "$2.out" 2> "$2.err") || rc=$?
  n=$(wc -l < "$D/$2.err")
  if [ "$rc" -ne 1 ]; then bad "$1: $3 exited $rc, want 1: $(head -1 "$D/$2.err")"
  elif [ -s "$D/$2.out" ]; then bad "$1: $3 was refused but cybs still wrote a binary"
  elif [ "$n" -eq 1 ] && grep -qxF "$4" "$D/$2.err"; then echo "  ok   $1: $3 -> $(cat "$D/$2.err")"
  else bad "$1: $3 printed [$(head -1 "$D/$2.err")] ($n line(s)), want [$4]"; fi
}

# L — the filing's repro, verbatim
printf 'fn main() { var x = 0; loop { x = x + 1; if (x == 3) { break; } } return x; }\nvar r = main();\nsyscall(60, r);\n' > "$D/l.cyr"
says L l.cyr 'the filed `loop` repro' "${SYN}fn main() { var x = 0; loop { x = x + 1; if (x == 3) { break; } } return x; }"

# T — the rest of the table
printf 'var a = 1;\nconst N = 3;\nsyscall(60, a);\n' > "$D/ctop.cyr"
says T ctop.cyr '`const` at the top level' "${SYN}const N = 3;"
printf 'fn main() {\n    const N = 3;\n    return N;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/cfn.cyr"
says T cfn.cyr '`const` in a fn' "${SYN}    const N = 3;"
printf 'fn main() {\n    var x = 0;\n    do { x = x + 1; } while (x < 3);\n    return x;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/dowh.cyr"
says T dowh.cyr '`do { .. } while (c);`' "${SYN}    do { x = x + 1; } while (x < 3);"
printf 'fn main() {\n    var a = 1;\n    var x = if (a == 1) { 3 } else { 4 };\n    return x;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/ifex.cyr"
says T ifex.cyr 'an if-expression' "${SYN}    var x = if (a == 1) { 3 } else { 4 };"
printf 'fn main() {\n    var a = 1;\n    var b = -a;\n    return b;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/nega.cyr"
says T nega.cyr 'unary minus on a name (`-a`)' "${SYN}    var b = -a;"
printf 'fn main() {\n    var b = -3;\n    return b;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/neg3.cyr"
says T neg3.cyr 'unary minus on a literal (`-3`)' "${SYN}    var b = -3;"
printf 'fn main() {\n    var a = 8;\n    var b = a >>> 2;\n    return b;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/sar.cyr"
says T sar.cyr '`a >>> 2`' "${SYN}    var b = a >>> 2;"
printf 'fn main() {\n    var a = 8;\n    a >>= 2;\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/shreq.cyr"
says T shreq.cyr '`a >>= 2`' "${SYN}    a >>= 2;"
printf 'fn ok(a) { return a; }\nvar r = ok(1);\nfn bad( { }\nsyscall(60, r);\n' > "$D/badfn.cyr"
says T badfn.cyr '`fn bad( { }` after valid code' "${SYN}fn bad( { }"

# N — the undefined-name path
printf 'fn main() {\n    var x = nosuch(1);\n    return x;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/undefn.cyr"
says N undefn.cyr '`var x = nosuch(1);`' "${UND}nosuch, at:     var x = nosuch(1);"
printf 'const N = 3;\nfn main() {\n    return N + 1;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/cread.cyr"
says N cread.cyr 'a top-level `const` read from a fn' "${UND}N, at:     return N + 1;"

# I — the expanded stream: an include's own line, and the main file's after an include
printf 'fn helper(a) {\n    return a;\n}\nfn twice(a) {\n    loop { break; }\n    return a;\n}\n' > "$D/inc_bad.cyr"
printf 'include "inc_bad.cyr"\nvar r = helper(3);\nsyscall(60, r);\n' > "$D/inc1.cyr"
says I inc1.cyr 'an error inside an included file' "${SYN}    loop { break; }"
printf 'fn helper(a) {\n    return a;\n}\n' > "$D/inc_ok.cyr"
printf 'include "inc_ok.cyr"\nvar r = helper(3);\nvar s = r >>> 1;\nsyscall(60, r);\n' > "$D/inc2.cyr"
says I inc2.cyr 'an error after an include' "${SYN}var s = r >>> 1;"

# E — the end of the input (a fn never closed, trailing blank lines)
printf 'fn main() {\n    var x = 1;\n    return x;\n\n\n' > "$D/eof.cyr"
says E eof.cyr 'a fn left open at the end of the input' "${SYN}    return x;"

# K — the input ends right after `fn` / `var` (no trailing LF, as the filing's printf '%s')
printf 'fn' > "$D/kfn.cyr"
says K kfn.cyr 'the input `fn`' "${SYN}fn"
printf 'var' > "$D/kvar.cyr"
says K kvar.cyr 'the input `var`' "${SYN}var"
printf 'fn ' > "$D/kfnsp.cyr"
says K kfnsp.cyr 'the input `fn ` (a trailing blank)' "${SYN}fn "

# V — anti-vacuous
cat > "$D/ok.cyr" <<'EOF'
var g = 40;
fn main() {
    var a = 3;
    var b = 0 - a;
    var c = 16 >> 2;
    var i = 0;
    while (i < 2) { i = i + 1; }
    if (b == 0 - 3) { a = a + 1; }
    return g + c - i + later(0) + a - 4;
}
fn later(x) { return x; }
var r = main();
syscall(60, r);
EOF
rc=0; "$D/cybs" < "$D/ok.cyr" > "$D/ok" 2> "$D/ok.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/ok" ] || [ -s "$D/ok.err" ]; then bad "V: a valid program was refused (rc $rc): $(head -1 "$D/ok.err")"
else
  chmod +x "$D/ok"
  got=0; "$D/ok" || got=$?
  if [ "$got" -eq 42 ]; then echo "  ok   V: a valid program (0 - a, >>, while, if, a forward call) compiles and runs (exit 42)"
  else bad "V: the valid program exited $got, want 42"; fi
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_diagnostics_named — $fail row(s) red"; exit 1; fi
echo "PASS: cybs_diagnostics_named — every refusal in the filing's table names what cybs lacks and prints its own line of the expanded stream; an undefined name is named; a valid program still compiles (closure intact)"
