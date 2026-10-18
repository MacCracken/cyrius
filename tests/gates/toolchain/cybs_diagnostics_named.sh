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
#      nothing on stderr. 6.7.14, issues/archived/2026-10-14-cybs-segfaults-on-eof-after-fn-or-var.md — and `var x:`,
#      whose type name shallow_global stepped over the same way (found in passing, 6.7.14)
#   X  a statement that starts with a name and a `[` (`zz[1] = 5;` - cybs has no subscript) names an
#      undefined name, as the read form `var a = zz[1];` does: rc 1, nothing written, the undefined-name
#      message at its line. A known name — a global array (the filing's zd), a local, a fn, an enum member
#      — keeps the class message, which lists `x[i]`. Before, every such statement was the class message,
#      with no `x[i]` in its list. Any other token after the name keeps the class message (L and T: `loop`,
#      `const`, `do` lex as names). 6.7.14, issues/archived/2026-10-14-cybs-indexed-store-undefined-name-not-named.md
#   P  the preprocessor's fixed buffers refuse what does not fit, naming the cap, rc 1, nothing written
#      (6.7.14, issues/archived/2026-10-13-cybs-include-scratch-and-buffers-unchecked.md). Each was unchecked: an
#      include over its 2 MB slot had its tail overwritten by the file it includes (the filing's big.cyr
#      printed a line the file does not contain), stdin past 15 MB was dropped with exit 0, includes past
#      the 8 slots and an expansion past the 16 MB buffer ran on into other regions (130 MB: SIGSEGV).
#      P1 the filed repro verbatim; P2 an include of exactly 2 MB compiles, one byte more is refused;
#      P3 an 8-deep include chain compiles, 9 deep is refused; P4 stdin of exactly 15 MB compiles, a
#      statement past it is refused (the 6.7.13 cybs dropped it: exit 0); P5 an expansion of exactly
#      16 MB compiles, one byte more is refused (the final check), and 65 spellings of one 2 MB include
#      (130 MB) are refused at the first line past 16 MB, before the buffer runs past the brk end
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
#   shallow_fn's and shallow_global's IDENT test dropped (the 6.7.13 cybs)              -> K RED (rc 139, all four)
#   only shallow_g_col's type-name test dropped                                          -> K RED (`var x:`, rc 139)
#   parse_assign_stmt's resolve-first sequence back to `jmp parse_err`                    -> X RED (zi, the top level)
#   the sequence's enum-member lookup dropped                                            -> X RED (EA named undefined)
#   the sequence's `[` test dropped (every other token resolves the name too)             -> L T I RED (`loop`,
#                                                                                         `const`, `do` named undefined)
#   err_syntax without `x[i]`                                                             -> L T I E K X RED
#   pp_do_include's slot-size check dropped                                              -> P1 P2 RED (rc 0: the file
#                                                                                         cut at 2 MB + 1 compiles)
#   (the 6.7.13 cybs, both)                                                              -> P1 RED (the filed `at: ng
#                                                                                         padding ..` line)
#   pp_do_include's depth check dropped                                                  -> P3 RED (9 deep compiles)
#   read_input back to `mov rdx, 0xF00000` (the 6.7.13 read)                              -> P4 RED (exit 0)
#   pp_exp_linestart's check dropped                                                     -> P5 RED (130 MB: rc 139)
#   preprocess's final expanded-length check dropped                                     -> P5 RED (16 MB + 1 compiles)
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

SYN='cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, x[i], >>>, >>=), at: '
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
printf 'var x:' > "$D/kvarcol.cyr"
says K kvarcol.cyr 'the input `var x:`' "${SYN}var x:"

# X — the filing's three programs verbatim (zi, zj, zd), then the known-name and top-level shapes
printf 'fn main() {\n    var a = 1;\n    zz[1] = 5;\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/zi.cyr"
says X zi.cyr '`zz[1] = 5;` with zz undefined (the filed zi)' "${UND}zz, at:     zz[1] = 5;"
printf 'fn main() {\n    var a = zz[1];\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/zj.cyr"
says X zj.cyr '`var a = zz[1];` with zz undefined (the filed zj)' "${UND}zz, at:     var a = zz[1];"
printf 'var zz[16];\nfn main() {\n    var a = 1;\n    zz[1] = 5;\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/zd.cyr"
says X zd.cyr '`zz[1] = 5;` with zz a global array (the filed zd)' "${SYN}    zz[1] = 5;"
printf 'fn main() {\n    var q = 1;\n    q[1] = 5;\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/zl.cyr"
says X zl.cyr '`q[1] = 5;` with q a local' "${SYN}    q[1] = 5;"
printf 'fn g() { return 1; }\nfn main() {\n    g[1] = 5;\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/zf.cyr"
says X zf.cyr '`g[1] = 5;` with g a fn' "${SYN}    g[1] = 5;"
printf 'enum E { EA = 1; }\nfn main() {\n    EA[1] = 5;\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/ze.cyr"
says X ze.cyr '`EA[1] = 5;` with EA an enum member' "${SYN}    EA[1] = 5;"
printf 'var a = 1;\nzz[1] = 5;\nsyscall(60, a);\n' > "$D/zt.cyr"
says X zt.cyr '`zz[1] = 5;` at the top level, zz undefined' "${UND}zz, at: zz[1] = 5;"

# P — the preprocessor's caps. pad <file> <bytes>: comment lines, exactly <bytes> bytes, ending in LF
pad() { awk -v n="$2" 'BEGIN { l = "# padding padding padding padding padding padding padding padding padding padd\n"; L = length(l)
  while (n >= L) { printf "%s", l; n -= L }
  if (n == 1) printf "\n"; else if (n > 1) { t = "#"; for (i = 2; i < n; i++) t = t "x"; printf "%s\n", t } }' > "$1"; }
# runs <row> <file> <what>: cybs (in $D) compiles it, and the program exits 42
runs() {
  rc=0; (cd "$D" && ./cybs < "$2" > "$2.out" 2> "$2.err") || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$D/$2.out" ]; then bad "$1: $3 was refused (rc $rc): $(head -1 "$D/$2.err")"; return; fi
  chmod +x "$D/$2.out"; got=0; "$D/$2.out" || got=$?
  [ "$got" -eq 42 ] && echo "  ok   $1: $3 compiles and runs (exit 42)" || bad "$1: $3 exited $got, want 42"
}
CAP_FILE="cybs: an included file is over 2 MB, the size of the preprocessor's include slot"
CAP_DEPTH="cybs: includes nest more than 8 deep, the preprocessor's 8 include slots"
CAP_IN="cybs: the input is over 15 MB, the size of the input buffer"
CAP_EXP="cybs: the input with its includes spliced in is over 16 MB, the size of the expansion buffer"
LC_ALL=C; export LC_ALL
# P1 — the filing's repro, verbatim (big.cyr 2,178,045 B, which includes small.cyr)
printf 'fn small() { return 1; }\n' > "$D/small.cyr"
{ printf 'include "small.cyr"\n'; i=0; while [ $i -lt 33000 ]; do
    printf '# padding padding padding padding padding padding padding padding\n'; i=$((i+1)); done
  printf 'fn tail() { return 41; }\n'; } > "$D/big.cyr"
printf 'include "big.cyr"\nsyscall(60, tail() + small());\n' > "$D/pmain.cyr"
says P1 pmain.cyr 'the filed 2,178,045 B include that includes another file' "$CAP_FILE"
rm -f "$D/big.cyr"
# P2 — the slot's edge
pad "$D/p2m.cyr" 2097152; pad "$D/p2m1.cyr" 2097153
printf 'include "p2m.cyr"\nsyscall(60, 42);\n' > "$D/i2m.cyr"
printf 'include "p2m1.cyr"\nsyscall(60, 42);\n' > "$D/i2m1.cyr"
runs P2 i2m.cyr 'an include of exactly 2 MB'
says P2 i2m1.cyr 'an include of 2 MB + 1' "$CAP_FILE"
rm -f "$D/p2m1.cyr"
# P3 — the depth: c<n>_1 .. c<n>_<n> each include the next; the last defines deep()
chain() { i=1; while [ $i -lt $1 ]; do printf 'include "c%s_%s.cyr"\n' $1 $((i + 1)) > "$D/c$1_$i.cyr"; i=$((i + 1)); done
  printf 'fn deep() { return 42; }\n' > "$D/c$1_$1.cyr"; printf 'include "c%s_1.cyr"\nsyscall(60, deep());\n' $1 > "$D/chain$1.cyr"; }
chain 8; chain 9
runs P3 chain8.cyr 'an include chain 8 deep'
says P3 chain9.cyr 'an include chain 9 deep' "$CAP_DEPTH"
# P4 — stdin: the statement that sets the exit is the input's last 17 bytes
tl=$(printf 'syscall(60, 42);\n' | wc -c)
pad "$D/in15.cyr" $((15728640 - tl)); printf 'syscall(60, 42);\n' >> "$D/in15.cyr"
runs P4 in15.cyr 'an input of exactly 15 MB'
rm -f "$D/in15.cyr" "$D/in15.cyr.out"
pad "$D/in15p.cyr" 15728640; printf 'syscall(60, 42);\n' >> "$D/in15p.cyr"
says P4 in15p.cyr 'an input of 15 MB with a statement past it' "$CAP_IN"
rm -f "$D/in15p.cyr"
# P5 — the expansion: seven spellings of one 2 MB file (./, ././, ..: include-once keys on the
# spelling) and a last include that brings it to exactly 16 MB with main's 17-byte tail, then 1 more
sp() { k=0; o=; while [ $k -lt $1 ]; do o="$o./"; k=$((k + 1)); done; printf '%s' "$o"; }
{ k=1; while [ $k -le 7 ]; do printf 'include "%sp2m.cyr"\n' "$(sp $k)"; k=$((k + 1)); done; printf 'include "e16.cyr"\nsyscall(60, 42);\n'; } > "$D/ex16.cyr"
{ k=1; while [ $k -le 7 ]; do printf 'include "%sp2m.cyr"\n' "$(sp $k)"; k=$((k + 1)); done; printf 'include "e16p.cyr"\nsyscall(60, 42);\n'; } > "$D/ex16p.cyr"
pad "$D/e16.cyr" $((2097152 - tl)); pad "$D/e16p.cyr" $((2097152 - tl + 1))
runs P5 ex16.cyr 'an expansion of exactly 16 MB'
says P5 ex16p.cyr 'an expansion of 16 MB + 1' "$CAP_EXP"
{ k=1; while [ $k -le 65 ]; do printf 'include "%sp2m.cyr"\n' "$(sp $k)"; k=$((k + 1)); done; printf 'syscall(60, 42);\n'; } > "$D/ex130.cyr"
says P5 ex130.cyr '65 spellings of one 2 MB include (130 MB expanded)' "$CAP_EXP"
rm -f "$D"/*.out "$D/p2m.cyr" "$D/e16.cyr" "$D/e16p.cyr"
unset LC_ALL

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
echo "PASS: cybs_diagnostics_named — every refusal in the filing's table names what cybs lacks and prints its own line of the expanded stream; an undefined name is named (a subscript's too); an input ending at fn / var is refused, not a crash; the preprocessor refuses what does not fit its buffers, naming the cap; a valid program still compiles (closure intact)"
