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
# 6.6.16 (C4) rows: a pair forwarded through the explicit generic `g<T>(..)` or the method
# `p.m(..)` beside `return Ok(5)` is silent (both were reported as a dropped tag), the same spellings
# returning ONE value still warn, and a closure is judged through either spelling's `return` / `?`.
# Mutations (scratch tree, measured): `_ret_is_variant` without `_tok_ret_callee` -> gen_pair and
# m_pair red on both targets (4 rows); `_tok_q_is_pair` not rewinding `g<..>(` / `x.m(` to the call's
# first token -> cl_gq_mixed red on both (2 rows). The tree before this fix: 10 rows red.
# The receiver rows (m_*, m3_*; review of the first cut, where 20 of them were red — false warnings
# on a wrapper typed by inference, by scope or through a capture, and missed ones). Mutations,
# each measured red on x86 and aarch64: `_ret_is_variant` treating an unresolved method as plain
# again -> m3_unknown; `_tok_decl_sid` without the initializer inference -> m3_lit_one +
# m3_call_one + m3_gen_one + m3_geni_one, its literal arm alone -> m3_lit_one, its call arm alone ->
# m3_call_one, its generic `: T` arm -> m3_gen_one + m3_geni_one; `_tok_decl_sid` not skipping a
# param's `*` -> m3_ptr_one;
# `_tok_name_sid` not stepping over a closed block -> m3_scope_pair + m3_scope_one; a closure's
# names resolved in the closure alone (no capture) -> m3_cap_one + m3_cap_mixed.
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

# The filed repro (docs/development/issues/archived/2026-09-23-kybernet-mixed-return-diagnostic-misfires-on-nullary-none.md), verbatim
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
# 6.6.16 (C4): the explicit generic `g<T>(..)` and the method `p.m(..)` are resolved like `f(..)`
# (`_tok_ret_callee`). Forwarding a pair through either beside `return Ok(5)` warned falsely ("a
# SINGLE value here") because only `name(` was recognised; the same spellings returning ONE value
# must still warn. In a closure (judged as its own unit) the pair is also recognised through
# either spelling's `return` and `?`, which went unwarned.
P2='struct Pt { x; y; }
fn Pt_div(self: Pt, d) { if (d == 0) { return Err(9); } return Ok(self.x / d); }
fn Pt_one(self: Pt): i64 { return self.x; }
fn gd<T>(n: T) { if (n == 0) { return Err(1); } return Ok(n); }
fn gid<T>(n: T): i64 { return n; }'
fx gen_pair     "$P2
fn f(x) { if (x > 5) { return Ok(5); } return gd<i32>(x); }"
fx m_pair       "$P2
fn f(x) { var p: Pt; p.x = x; p.y = 0; if (x > 5) { return Ok(5); } return p.div(1); }"
fx m_single     "$P2
fn f(x) { var p: Pt; p.x = x; p.y = 0; if (x > 5) { return Ok(5); } return p.one(); }"
fx gen_single   "$P2
fn f(x) { if (x > 5) { return Ok(5); } return gid<i32>(x); }"
fx cl_gen_pair  "$P2
fn f(x) { var g = |y| { if (y > 5) { return Ok(5); } return gd<i32>(y); }; return Ok(x); }"
fx cl_m_mixed   "$P2
fn f(x) { var g = |y| { var p: Pt; p.x = y; p.y = 0; if (y > 5) { return p.div(1); } return 0; }; return Ok(x); }"
fx cl_gq_mixed  "$P2
fn f(x) { var g = |y| { var v = gd<i32>(y)?; return v; }; return Ok(x); }"
# The method's RECEIVER, as the warning pass types it (review of the first cut). The parser types
# `var p = Pt { .. }` and flags a wrapper's `return p.div(..)` pair-returning; the warning pass,
# typing only `name: T`, then looked the receiver's NAME up as a fn and called the wrapper's only
# return "a SINGLE value" (m_inf_sole). P3 gives two structs one method name of different pair-ness,
# so the token-typing — not `_tok_method_any`'s one-candidate answer — has to decide those rows:
# by inference (a literal, a call, a generic's bound `: T`), as a `*T` param, by SCOPE (a `var p`
# in a block closed before the call is not seen; the first cut took the lexically-last one), and
# through a closure's CAPTURE. A receiver typed by nothing the tokens can see (a generic fn's
# `p: T` param, with two candidate `_div`s) is UNKNOWN, and unknown is not plain (m3_unknown).
fx m_inf_sole   "$P2
fn f(x) { var p = Pt { x, 0 }; return p.div(1); }"
fx m_inf_beside "$P2
fn f(x) { var p = Pt { x, 0 }; if (x > 5) { return Ok(5); } return p.div(1); }"
fx m_cap_beside "$P2
fn f(x) { var p: Pt; p.x = x; p.y = 0; var g = |y| { if (y > 5) { return Ok(5); } return p.div(y); }; return Ok(x); }"
P3='struct Pt { x; y; }
struct Qt { x; y; }
fn Pt_div(self: Pt, d) { if (d == 0) { return Err(9); } return Ok(self.x / d); }
fn Qt_div(self: Qt, d): i64 { return self.x; }
fn mkp(n): Pt { var p: Pt; p.x = n; p.y = 0; return p; }
fn mkq(n): Qt { var q: Qt; q.x = n; q.y = 0; return q; }
fn idp<T>(v: T): T { return v; }'
fx m3_lit_pair  "$P3
fn f(x) { var p = Pt { x, 0 }; if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_lit_one   "$P3
fn f(x) { var p = Qt { x, 0 }; if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_call_pair "$P3
fn f(x) { var p = mkp(x); if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_call_one  "$P3
fn f(x) { var p = mkq(x); if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_scope_pair "$P3
fn f(x) { var p: Pt; p.x = x; p.y = 0; if (x == 99) { var p: Qt; p.x = 1; } if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_scope_one "$P3
fn f(x) { var p: Qt; p.x = x; p.y = 0; if (x == 99) { var p: Pt; p.x = 1; } if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_cap_one   "$P3
fn f(x) { var p: Qt; p.x = x; p.y = 0; var g = |y| { if (y > 5) { return Ok(5); } return p.div(y); }; return Ok(x); }"
fx m3_cap_mixed "$P3
fn f(x) { var p: Pt; p.x = x; p.y = 0; var g = |y| { if (y > 5) { return p.div(y); } return 0; }; return Ok(x); }"
fx m3_gen_pair  "$P3
fn f(x) { var q: Pt; q.x = x; q.y = 0; var p = idp<Pt>(q); if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_gen_one   "$P3
fn f(x) { var q: Qt; q.x = x; q.y = 0; var p = idp<Qt>(q); if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_geni_one  "$P3
fn f(x) { var q: Qt; q.x = x; q.y = 0; var p = idp(q); if (x > 5) { return Ok(5); } return p.div(1); }"
fx m3_ptr_one   "$P3
fn h(pp: *Qt, x) { if (x > 5) { return Ok(5); } return pp.div(1); }
fn f(x) { var q: Qt; q.x = x; q.y = 0; var t, v = h(&q, x); return Ok(v); }"
fx m3_unknown   "$P3
fn h<T>(p: T, x) { if (x > 5) { return Ok(5); } return p.div(1); }
fn f(x) { var p: Pt; p.x = x; p.y = 0; var t, v = h(p, x); return Ok(v); }"

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
  warns "$c" gen_pair 0
  warns "$c" m_pair 0
  warns "$c" m_single 1
  warns "$c" gen_single 1
  warns "$c" cl_gen_pair 0
  warns "$c" cl_m_mixed 1
  warns "$c" cl_gq_mixed 1
  warns "$c" m_inf_sole 0
  warns "$c" m_inf_beside 0
  warns "$c" m_cap_beside 0
  warns "$c" m3_lit_pair 0
  warns "$c" m3_lit_one 1
  warns "$c" m3_call_pair 0
  warns "$c" m3_call_one 1
  warns "$c" m3_scope_pair 0
  warns "$c" m3_scope_one 1
  warns "$c" m3_cap_one 1
  warns "$c" m3_cap_mixed 1
  warns "$c" m3_gen_pair 0
  warns "$c" m3_gen_one 1
  warns "$c" m3_geni_one 1
  warns "$c" m3_ptr_one 1
  warns "$c" m3_unknown 0
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
echo "PASS stack_enum_mixed_return_warning: $pass rows — nullary variants silent, dropped tags warned, generic and method forwards silent and their single values warned, method receivers typed by scope, inference and capture, on x86 and aarch64"
exit 0
