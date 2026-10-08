#!/bin/sh
# tests/gates/toolchain/cybs_lexer_drops_nothing.sh — 6.7.6
#
# cybs (the bootstrap compiler the seed assembles; bootstrap/cybs.cyr) must never DROP a byte it
# does not lex. Its `lexer_bang` arm sent a `!` without a following `=` to `lexer_skip`, so
# `fn f(x) { return !x; }` compiled as `return x;` — f(0) was 0 under a seed-built cybs and 1
# under cycc, with nothing said. `!` has been legal cyrius since 6.7.3 and cybs compiles the
# compiler (src/main.cyr) on the seed chain, so the first lone `!` in compiler source would have
# miscompiled gen1 silently: the dropped-`!` lexer bug class (cycc's own instance was fixed at
# 6.7.3) in the trusted root. A lone `!` is now refused BY NAME; cybs does not learn `!`.
# The class was wider than `!`: the dispatch's last line sent EVERY byte it had no arm for to
# `lexer_skip`, so `var r = g()?;` compiled as `g()` (exit 7), `@a = 5;` as `a = 5;`, and a UTF-8
# identifier `café` became `caf` (one slot with a `caf`). Those bytes are refused now too, the
# byte named. No cybs input carries one: gen1 and the closure are byte-identical with the change.
#
#   A  closure: the seed assembles cybs, and cybs reproduces the seed
#   B  `return !x;` is refused naming the lone `!` (exit non-zero, nothing written to stdout)
#   E  a `!` as the last byte of the input is refused the same way
#   N  ANTI-VACUOUS: `!=` still lexes as not-equal (a program using it exits 42)
#   C  `?`, `@` and a UTF-8 lead byte outside a string or comment are refused, the byte named
#   K  ANTI-VACUOUS: the same bytes inside a comment and a string still compile (exit 42)
#
# Mutations (6.7.6, each verified RED in a scratch copy of the tree):
#   lexer_bang's `jne lexer_bang_err` back to `jne lexer_skip`  -> B RED
#   lexer_bang's `jge lexer_bang_err` back to `jge lexer_skip`  -> E RED
#   lexer_bang's `je` NEQ path dropped (every `!` refused)      -> N RED
#   the dispatch's last line back to `jmp lexer_skip`           -> C RED
#   the comment arm (`je lexer_comment`) to lexer_char_err      -> K RED
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_lexer_drops_nothing: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_lexer_drops_nothing: bootstrap/asm missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_lexer_drops_nothing: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_lexer_drops_nothing $1"; fail=$((fail + 1)); }

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_lexer_drops_nothing: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }
cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
cmp -s "$D/asm2" bootstrap/asm && echo "  ok   A: closure — cybs reproduces the seed" || bad "A: closure — cybs no longer reproduces the seed"

# refused <row> <file> <what> <pattern>: cybs must exit non-zero, write nothing, and name it
refused() {
  rc=0; "$D/cybs" < "$D/$2" > "$D/$2.out" 2> "$D/$2.err" || rc=$?
  if [ "$rc" -eq 0 ]; then bad "$1: $3 compiled (rc 0) — the byte was dropped"
  elif [ -s "$D/$2.out" ]; then bad "$1: $3 was refused but cybs still wrote a binary"
  elif grep -q "$4" "$D/$2.err"; then echo "  ok   $1: $3 is refused by name"
  else bad "$1: $3 failed without naming it: $(head -1 "$D/$2.err")"; fi
}
printf 'fn f(x) { return !x; }\nsyscall(60, f(0));\n' > "$D/bang.cyr"
refused B bang.cyr 'a lone `!` (`return !x;`)' 'a lone `!`'
printf 'syscall(60, 0);\n!' > "$D/bang_eof.cyr"
refused E bang_eof.cyr 'a `!` as the last byte of the input' 'a lone `!`'

printf 'fn f(x) { if (x != 3) { return 42; } return 1; }\nsyscall(60, f(5));\n' > "$D/neq.cyr"
"$D/cybs" < "$D/neq.cyr" > "$D/neq" 2>/dev/null || true
chmod +x "$D/neq" 2>/dev/null || true
got=0; [ -s "$D/neq" ] && { "$D/neq" || got=$?; }
[ "$got" -eq 42 ] && echo "  ok   N: \`!=\` still lexes as not-equal (exit 42)" || bad "N: a program using \`!=\` exited $got, want 42"

printf 'fn g() { return 7; }\nfn f() { var r = g()?; return r; }\nsyscall(60, f());\n' > "$D/q.cyr"
refused C q.cyr '`?` (`g()?`)' 'cannot lex this byte.*: ?$'
printf 'var a = 1;\n@a = 5;\nsyscall(60, a);\n' > "$D/at.cyr"
refused C at.cyr '`@` (`@a = 5;`)' 'cannot lex this byte.*: @$'
printf 'var caf = 1;\nvar caf\303\251 = 2;\nsyscall(60, caf);\n' > "$D/u.cyr"
refused C u.cyr 'a UTF-8 identifier byte (`café`)' 'cannot lex this byte'

printf '# a.b? @x $ \303\251 !\nvar s = "a.b?@$\303\251!";\nsyscall(60, 42);\n' > "$D/k.cyr"
"$D/cybs" < "$D/k.cyr" > "$D/k" 2>/dev/null || true
chmod +x "$D/k" 2>/dev/null || true
got=0; [ -s "$D/k" ] && { "$D/k" || got=$?; }
[ "$got" -eq 42 ] && echo "  ok   K: those bytes inside a comment and a string still compile (exit 42)" || bad "K: bytes inside a comment / string: exited $got, want 42"

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_lexer_drops_nothing — $fail row(s) red"; exit 1; fi
echo "PASS: cybs_lexer_drops_nothing — cybs refuses a lone \`!\` and every byte it does not lex, by name, instead of dropping them; \`!=\`, comments and strings unchanged (closure intact)"
