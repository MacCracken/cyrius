#!/bin/sh
# tests/gates/toolchain/cybs_undefined_fn_named.sh — 6.7.11
#
# cybs (the bootstrap compiler the seed assembles; bootstrap/cybs.cyr) compiled a STATEMENT-position
# call to a fn that is never defined with exit 0, and the binary died with SIGSEGV: the statement
# arm registers an unknown name (so a definition further down can fill it in) with entry -1, and
# fixup_fn_call patched the call to `-1 - (site + 4)`, one byte before the code. `fp(5);` on a
# fn-pointer VARIABLE takes the same arm (cybs calls a variable by name only in an expression) and
# died the same way. cycc refuses both ("undefined function"); cybs now refuses them at the fixup,
# naming the fn, and writes nothing. cybs's language narrows to what cycc already refuses: no
# input that built before changes (gen1 and the closure are byte-identical with the fix).
# issues/archived/2026-10-08-cybs-undefined-fn-call-in-statement-silent.md
#
#   A  closure: the seed assembles cybs, and cybs reproduces the seed
#   U  the filed repro, verbatim (`nosuch(1);` in a fn): exit 1, `cybs: undefined function: nosuch`,
#      nothing on stdout
#   P  `fp(5);` (a global fn-pointer variable called as a statement): refused the same way, naming fp
#   R  the U and P fixtures are refusals under build/cycc too (the spec cybs narrows to)
#   F  ANTI-VACUOUS: a statement call to a fn defined AFTER its use still compiles and runs (exit 7),
#      and so does the filing's control (`f(1);` with f defined first)
#   E  ANTI-VACUOUS: a call through a fn-pointer variable in an EXPRESSION (gate cybs_call_arity_named
#      row E's shape) still compiles and runs (exit 42)
#
# Mutations (6.7.11, each verified RED in a scratch copy of the tree):
#   fixup_fn_call's `cmp rax, -1` / `je fixup_fn_undef` deleted       -> U P RED (rc 0, SIGSEGV binary)
#   fixup_fn_undef's name write dropped (`call cybs_write_name`)      -> U P RED (the name missing)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_undefined_fn_named: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_undefined_fn_named: bootstrap/asm missing"; exit 77; }
CC=${CYCC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_undefined_fn_named: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_undefined_fn_named $1"; fail=$((fail + 1)); }

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_undefined_fn_named: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }
cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
cmp -s "$D/asm2" bootstrap/asm && echo "  ok   A: closure — cybs reproduces the seed" || bad "A: closure — cybs no longer reproduces the seed"

# refused <row> <file> <what> <message>: cybs must exit 1, write nothing to stdout, and print <message>
refused() {
  rc=0; "$D/cybs" < "$D/$2" > "$D/$2.out" 2> "$D/$2.err" || rc=$?
  if [ "$rc" -eq 0 ]; then
    got=0; chmod +x "$D/$2.out"; [ -s "$D/$2.out" ] && { ( "$D/$2.out" > /dev/null 2>&1 ) 2>/dev/null || got=$?; }
    bad "$1: $3 compiled (rc 0; the binary exits $got)"
  elif [ "$rc" -ne 1 ]; then bad "$1: $3 exited $rc, want 1: $(head -1 "$D/$2.err")"
  elif [ -s "$D/$2.out" ]; then bad "$1: $3 was refused but cybs still wrote a binary"
  elif grep -qxF "$4" "$D/$2.err"; then echo "  ok   $1: $3 is refused: $4"
  else bad "$1: $3 failed without the message '$4': $(head -1 "$D/$2.err")"; fi
}
# runs <row> <file> <what> <exit>: cybs compiles it and the binary exits <exit>
runs() {
  rc=0; "$D/cybs" < "$D/$2" > "$D/$2.bin" 2> "$D/$2.err" || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$D/$2.bin" ]; then bad "$1: $3 no longer compiles (rc $rc): $(head -1 "$D/$2.err")"; return; fi
  chmod +x "$D/$2.bin"
  got=0; "$D/$2.bin" || got=$?
  if [ "$got" -eq "$4" ]; then echo "  ok   $1: $3 compiles and runs (exit $4)"
  else bad "$1: $3 exited $got, want $4"; fi
}

# U — the filing's repro, verbatim
cat > "$D/stmt.cyr" <<'EOF'
fn main() {
    nosuch(1);
    return 7;
}
var r = main();
syscall(60, r);
EOF
refused U stmt.cyr 'a statement call to an undefined fn (`nosuch(1);`)' 'cybs: undefined function: nosuch'

printf 'var fp = 0;\nfn f(a) { return a + 2; }\nfn main() { fp = &f; fp(5); return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$D/fp.cyr"
refused P fp.cyr 'a statement call through a fn-pointer variable (`fp(5);`)' 'cybs: undefined function: fp'

if [ -x "$CC" ]; then
  for f in stmt fp; do
    rc=0; "$CC" < "$D/$f.cyr" > "$D/$f.cc" 2> "$D/$f.cc.err" || rc=$?
    if [ "$rc" -ne 0 ] && [ ! -s "$D/$f.cc" ] && grep -q 'undefined function' "$D/$f.cc.err"; then echo "  ok   R: $f.cyr is refused by $(basename "$CC") too (undefined function)"
    else bad "R: $f.cyr under $(basename "$CC"): rc $rc — the fixture is not a refusal any more: $(head -1 "$D/$f.cc.err")"; fi
  done
else bad "R: no compiler at $CC to check the fixtures against"; fi

printf 'fn main() {\n    later(1);\n    return 7;\n}\nfn later(a) { return a; }\nvar r = main();\nsyscall(60, r);\n' > "$D/later.cyr"
runs F later.cyr 'a statement call to a fn defined after its use' 7
printf 'fn f(a) { return a; }\nfn main() {\n    f(1);\n    return 7;\n}\nvar r = main();\nsyscall(60, r);\n' > "$D/ctl.cyr"
runs F ctl.cyr "the filing's control (\`f(1);\`, f defined first)" 7

printf 'var gp = 0;\nfn f4(a, b, c, d) { return a * 10 + b + c + d; }\nfn t() { gp = &f4; var v = gp(3, 4, 4, 4); return v; }\nsyscall(60, t());\n' > "$D/ind.cyr"
runs E ind.cyr 'a call through a fn-pointer variable in an expression (`gp(..)`)' 42

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_undefined_fn_named — $fail row(s) red"; exit 1; fi
echo "PASS: cybs_undefined_fn_named — cybs refuses a statement call to an undefined fn (and \`fp(5);\` on a fn-pointer variable) by name, as cycc does; forward calls and expression calls through a variable still compile (closure intact)"
