#!/bin/sh
# type_audit_generic_fns.sh — 6.7.12 (the tools lane). `cyrius_type_audit` (programs/
# cyrius_type_audit.cyr) counts a generic fn as the public fn it is.
#
# WHY: _match_fn_decl took the identifier after the declaration prefix and required `(` right
# after it, so a generic fn's `<T>` between its name and its parameter list made the line no
# declaration: `fn gid<T>(a: T): T` was missing from the module's count and from the
# unannotated list (`g: 1/1 annotated`, `total public fns: 1` for a module of two public fns).
# cyrdoc and cyrius_api_surface step to the `(` and list it. The audit now steps over blanks,
# a balanced `<..>` (each `<` opens and each `>` closes a level, so a `>>` closes two, as
# _asf_arity counts them) and blanks again, as the compiler accepts them, before the `(` test.
#
# ROWS (each fixture COMPILES first — a premise; the tool built from programs/ by build/cycc)
#   1  the filed repro verbatim (issues/2026-10-13-type-audit-skips-generic-fns.md): it exits 3;
#      `--module=g` reports `g: 2/2 annotated` and `total public fns: 2`
#   2  shapes: a bounded `fn gb<T: Tr>`, `fn gp<T>` whose parameter is a nested
#      `Pair<i64, Pair<i64, i64>>` (its `>>` inside the list), two type parameters, a blank
#      before the `<` and one after the `>`, `pub fn`, an unannotated generic listed by name, a
#      `_` generic not counted: `gs: 7/8 annotated`, the unannotated list exactly `gs::gun`
#
# MUTATION LEDGER (6.7.12) — each a scratch copy of the tree (git archive + the mutant):
#   M1  the 6.7.11 _match_fn_decl (`(` required right after the name)        RED 1, 2
#   M2  the generic skipped but no blank stepped over around it               RED 2
#   M3  `>` not counted as a close (the skip runs to the line's end)          RED 1, 2
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=type_audit_generic_fns
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < programs/cyrius_type_audit.cyr > "$W/tau" 2> "$W/tau.err" || { echo "FAIL: $G: programs/cyrius_type_audit.cyr does not build"; tail -3 "$W/tau.err"; exit 1; }
[ "$(wc -c < "$W/tau")" -ge 10000 ] || { echo "FAIL: $G: the tool built a $(wc -c < "$W/tau")-byte binary"; exit 1; }
chmod +x "$W/tau"
# audit <dir> <module> — stdout to $W/out, stderr to $W/err, exit in RC
audit() { RC=0; ( cd "$W/$1" && "$W/tau" --module="$2" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?; }
# premise <file> <want exit>: the fixture compiles and exits as written
premise() { prc=0; "$CC" < "$1" > "$W/p.bin" 2> "$W/p.err" || prc=$?; chmod +x "$W/p.bin" 2> /dev/null; xrc=0; [ "$prc" = 0 ] && { "$W/p.bin" || xrc=$?; }; [ "$prc" = 0 ] && [ "$xrc" = "$2" ]; }
show() { cat "$W/out" "$W/err" | grep -E 'annotated|total public|::' | sed 's/^/      /' | head -8; }

# ── 1: the filed repro, verbatim ──
mkdir -p "$W/t/lib"
printf 'fn gid<T>(a: T): T { return a; }\nfn plain(a): i64 { return a; }\nsyscall(60, plain(gid(3)));\n' > "$W/t/lib/g.cyr"
if premise "$W/t/lib/g.cyr" 3; then
    audit t g
    if [ "$RC" = 0 ] && grep -qxF '  g: 2/2 annotated' "$W/err" && cat "$W/out" "$W/err" | grep -qE '^  total public fns: +2$'; then
        echo "  ok 1: the filed repro — g: 2/2 annotated, total public fns: 2 (gid counted)"
    else fail "1: rc $RC, want 'g: 2/2 annotated' and 'total public fns: 2'"; show; fi
else fail "1 premise: the repro does not compile and exit 3 (compile rc $prc, exit $xrc)"; fi

# ── 2: the shapes ──
mkdir -p "$W/s/lib"
cat > "$W/s/lib/gs.cyr" <<'EOF'
trait Tr { fn v(self): i64; }
impl Tr for i64 { fn v(self): i64 { return self + 1; } }
struct Pair<A, B> { a: A; b: B; }
fn gb<T: Tr>(a: T): i64 { return a.v(); }
fn gp<T>(v: Pair<i64, Pair<i64, i64>>, a: T): T { return a; }
fn g2<T, U>(a: T, b: U): T { return a; }
fn gsp <T>(a: T): T { return a; }
fn gsq<T> (a: T): T { return a; }
fn gun<T>(a: T) { return a; }
fn _gpriv<T>(a: T): T { return a; }
pub fn gpub<T>(a: T): T { return a; }
fn plain(a): i64 { return a; }
syscall(60, gb(1) + g2(3, 4) + gsp(5) + gsq(6) + gun(7) + _gpriv(8) + gpub(9) + plain(10) - 50);
EOF
if premise "$W/s/lib/gs.cyr" 0; then
    audit s gs
    un=$(grep '^  gs::' "$W/out" | tr -d ' ' | tr '\n' ' ')
    if [ "$RC" = 0 ] && grep -qxF '  gs: 7/8 annotated' "$W/err" && [ "$un" = "gs::gun " ]; then
        echo "  ok 2: shapes — bounded, nested-generic parameter, two type parameters, blanks around <..>, pub: gs: 7/8, unannotated gs::gun"
    else fail "2: rc $RC, unannotated '$un' (want 'gs::gun '), want 'gs: 7/8 annotated'"; show; fi
else fail "2 premise: the shapes fixture does not compile and exit 0 (compile rc $prc, exit $xrc)"; head -3 "$W/p.err"; fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G — $FAIL row(s) failed"; exit 1; }
echo "PASS: $G (a generic fn is a public fn to the audit: the filed repro 2/2, the shapes 7/8)"
