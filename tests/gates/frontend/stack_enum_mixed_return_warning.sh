#!/bin/sh
# stack_enum_mixed_return_warning.sh — 6.6.9 bite 3. The mixed-return warning ("returns a
# `: stack` pair on another path but a SINGLE value here") fires on a dropped TAG, and not on
# a nullary variant, which IS a whole value.
#
# ⛔ WHY. `_warn_mixed_pair_returns` (src/frontend/parse.cyr) treated `return IDENT(...)` as
# a pair return only when the callee had fn flag 256. Nullary `: stack` variant constructors
# (`None()`, any `Nope();`) never get 256, and correctly so, because they return the tag
# alone. So `return None();` beside `return Some(v);` was reported as a dropped tag and
# told to `return Err(x);`, which is wrong for an Option. The code was correct; the warning
# fired on every build. kybernet 1.6.20 shipped with it on its PID-1 signal path, and
# agnodrm's audit (scripts/audit.sh) FAILS a build on that text, so for any consumer that
# adopts Option it breaks the build. 6.6.9 marks nullary stack-variant constructors with
# fn flag 512 and treats `return <nullary>()` / `return <nullary>;` as whole variants.
#
# Anti-vacuous rows: the dropped-tag shapes still warn — a forwarded payload (`return rv;`
# after destructuring an Err), a raw `return 0;`, a wrapper fn and a local all hide the
# variant from the check. Ok/Err on every path stays silent. The fixture probe also RUNS
# (is_some=1 payload=40 / is_some=0), so "no warning" is not bought with wrong code.
#
# The compilers are built FROM SOURCE, so reverting the fix turns this RED.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: stack_enum_mixed_return_warning: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL stack_enum_mixed_return_warning: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
"$CC" < src/main.cyr > "$T/x86" 2>"$T/eb" || { echo "FAIL stack_enum_mixed_return_warning: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
"$T/x86" < src/main_aarch64.cyr > "$T/aarch64" 2>"$T/eb" || { echo "FAIL stack_enum_mixed_return_warning: could not build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/aarch64"
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
NEEDLE='SINGLE value here'

# The filed repro (docs/development/issues/archived/2026-09-23-kybernet-mixed-return-...md), verbatim
# apart from the trailing exit so it can be run.
cat > "$T/kyb.cyr" <<'EOF'
include "lib/string.cyr"
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"

# Some(v) on one path, the nullary None() on the other.
fn pick(x) {
    if (x > 0) {
        return Some(x * 10);
    }
    return None();
}

fn say(label, v) {
    var b[32];
    var l = fmt_int_buf(v, &b);
    sys_write(1, label, strlen(label));
    sys_write(1, &b, l);
    sys_write(1, "\n", 1);
    return 0;
}

fn main() {
    var t1, v1 = pick(4);
    var t2, v2 = pick(0);
    say("pick(4) is_some=", is_some(t1));
    say("pick(4) payload=", v1);
    say("pick(0) is_some=", is_some(t2));
    return 0;
}
var r = main();
sys_exit(r);
EOF
H='include "lib/string.cyr"
include "lib/syscalls.cyr"
include "lib/tagged.cyr"
include "lib/result.cyr"'
fx() { printf '%s\n%s\nvar t, v = f(3);\nsys_exit(t);\n' "$H" "$2" > "$T/$1.cyr"; }
# silent: nullary variants are whole values
fx none_first   'fn f(x) { if (x > 0) { return None(); } return Some(x); }'
fx bare_none    'fn f(x) { if (x > 0) { return Some(x); } return None; }'
fx user_nullary 'enum Tri: stack { Nope(); Yes(v); }
fn f(x) { if (x > 0) { return Yes(x); } return Nope(); }'
fx user_after   'fn f(x) { if (x > 0) { return Yes(x); } return Nope(); }
enum Tri: stack { Nope(); Yes(v); }'
fx okerr        'fn f(x) { if (x > 0) { return Ok(x); } return Err(1); }'
# still warned: the dropped-tag class
fx dropped      'fn g(x) { if (x > 0) { return Ok(x); } return Err(1); }
fn f(x) { var rt, rv = g(x); if (is_err_result(rt) == 1) { return rv; } return Ok(rv); }'
fx raw_zero     'fn f(x) { if (x > 0) { return Some(x); } return 0; }'
fx wrapper      'fn nw() { return None(); }
fn f(x) { if (x > 0) { return Some(x); } return nw(); }'
fx local        'fn f(x) { if (x > 0) { return Some(x); } var n = None(); return n; }'

# warns <compiler> <fixture> <expected count>
warns() {
  "$T/$1" < "$T/$2.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -ne 0 ]; then _bad "$1 $2: rc $rc (the fixture must build)"; grep '^error' "$T/e" | head -2; return; fi
  n=$(grep -c "$NEEDLE" "$T/e")
  if [ "$n" -ne "$3" ]; then _bad "$1 $2: $n mixed-return warning(s), expected $3"; grep "$NEEDLE" "$T/e" | head -2 | cut -c1-160 | sed 's/^/      /'; return; fi
  pass=$((pass + 1))
}
for c in x86 aarch64; do
  warns "$c" kyb 0
  warns "$c" none_first 0
  warns "$c" bare_none 0
  warns "$c" user_nullary 0
  warns "$c" user_after 0
  warns "$c" okerr 0
  warns "$c" dropped 1
  warns "$c" raw_zero 1
  warns "$c" wrapper 1
  warns "$c" local 1
done

# the hint no longer prescribes Err alone (it named `return Err(x);` for an Option)
"$T/x86" < "$T/raw_zero.cyr" > "$T/o" 2>"$T/e"
if grep "$NEEDLE" "$T/e" | grep -q 'None()'; then pass=$((pass + 1)); else _bad "the hint does not name the Option case"; fi
if grep "$NEEDLE" "$T/e" | grep -q 'Did you mean `return Err(x);`'; then _bad "the hint still prescribes Err for every enum"; else pass=$((pass + 1)); fi

# the repro runs correctly (x86 natively)
"$T/x86" < "$T/kyb.cyr" > "$T/kyb" 2>/dev/null && chmod +x "$T/kyb"
out=$("$T/kyb" | tr '\n' ' ')
if [ "$out" = "pick(4) is_some=1 pick(4) payload=40 pick(0) is_some=0 " ]; then pass=$((pass + 1)); else _bad "kyb repro printed '$out'"; fi

if [ "$fail" -ne 0 ]; then echo "FAIL stack_enum_mixed_return_warning: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS stack_enum_mixed_return_warning: $pass rows — nullary variants silent, dropped tags warned, on x86 and aarch64"
exit 0
