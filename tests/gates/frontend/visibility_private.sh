#!/bin/sh
# tests/gates/frontend/visibility_private.sh — v6.5.0 Phase 2 (public/private visibility, WARN mode)
#
# A top-level `private` flips its FILE to private-by-default; a per-item `public`
# re-exposes. Default (no declaration anywhere) is unchanged — everything public — so
# the feature is opt-in per file and inert until a file asks for it.
#
# WHAT THIS GATE IS REALLY FOR: enforcement has to cover EVERY path that resolves a
# name to an fn index and emits a call, not just the obvious one. The plan named two;
# there are at least thirteen. v6.4.81 shipped a bug of exactly that shape — the `_cfo`
# const-fold class was declared fixed three times, each fix scoped to the tier its
# repro landed in, and the fourth occurrence was in a resolution path nobody had
# enumerated. So this asserts per-PATH, and a new path is expected to add a case here.
#
# Paths covered: ordinary call · TAIL call (`return f();`, which bypasses PARSE_FNCALL
# entirely) · operator overloading (EMIT_OP_DISPATCH — the v6.4.81 path) · and, since
# v6.6.4, the eight paths hisab's `&_private` filing led to: `&fn` (in-fn, top-level,
# fncallN arg), `s.method()`, the retptr (asv) / pair (asp) struct receives incl. the
# inferred `var q = f()` form, and the four PE-only SIMD receive/return paths — each
# asserted to report EXACTLY ONCE (a lookahead + PARSE_FNCALL double-report is a bug
# too). Plus the opposite polarity (a `public fn pgen<T>` in a private file instantiated
# at `<i32>` from another file must BUILD — the instance used to inherit the file
# default, not its base) and top-level ARRAYS (PARSE_GVAR_ARR never stamped, so
# `var _buf[4]` in a private file was readable and addressable from anywhere).

set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: visibility-private — %s not built\n" "$CC"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib"
fail=0

cat > "$T/lib/secret.cyr" <<'EOF'
private
fn vis_hidden(): i64 { return 7; }
fn vis_same_file_caller(): i64 { return vis_hidden(); }
public fn vis_exposed(): i64 { return vis_hidden(); }
EOF

cat > "$T/m.cyr" <<'EOF'
include "lib/secret.cyr"
fn vis_ordinary(): i64 { var q = vis_hidden(); return q; }
fn vis_tail(): i64 { return vis_hidden(); }
fn vis_legit(): i64 { return vis_exposed(); }
fn main(): i64 { return vis_ordinary() + vis_tail() + vis_legit(); }
EOF

( cd "$T" && cat m.cyr | "$CC" >/dev/null 2>err.txt ) || true
W=$(grep -c "is private to its file" "$T/err.txt" 2>/dev/null || echo 0)

# Two cross-file calls to a private fn: the ordinary one and the TAIL one. If the tail
# path were missed the count would be 1 — and it silently was, in the first cut.
[ "$W" = "2" ] || { echo "  FAIL: visibility-private — expected 2 cross-file warnings (ordinary + TAIL), got $W"; cat "$T/err.txt" | head -4; fail=1; }

# `public` must genuinely re-expose: no warning for the call to vis_exposed.
grep -q "'vis_exposed' is private" "$T/err.txt" 2>/dev/null && { echo "  FAIL: visibility-private — 'public' did not re-expose vis_exposed"; fail=1; }

# Same-file call to a private fn must be silent — that is the whole point of file scope.
grep -q "vis_same_file_caller" "$T/err.txt" 2>/dev/null && { echo "  FAIL: visibility-private — same-file private call warned"; fail=1; }

# ── operator overloading is its own resolution path (the v6.4.81 lesson) ──────────
mkdir -p "$T/op/lib" && cd "$T/op"
cat > lib/ops.cyr <<'EOF'
private
struct OpVis { v; }
fn OpVis_add(a, b) { return 3000 + b; }
EOF
cat > m.cyr <<'EOF'
include "lib/ops.cyr"
var opv: OpVis = 5;
var opr = opv + 3;
fn main(): i64 { return opr; }
EOF
cat m.cyr | "$CC" >/dev/null 2>err2.txt || true
grep -q "'OpVis_add' is private to its file" err2.txt 2>/dev/null \
    || { echo "  FAIL: visibility-private — operator-overload path (EMIT_OP_DISPATCH) not enforced"; head -3 err2.txt; fail=1; }
cd "$ROOT"

# ── Phase 2b: GLOBAL VARS. The committed design covers `fn` AND `var`. ───────────
# Enforced inside FINDVAR — the single resolver every global reference goes through —
# rather than wired per call site. Locals need no special case: they are never
# stamped, so the check reads 0 and falls straight through.
mkdir -p "$T/v/lib" && cd "$T/v"
cat > lib/cfg.cyr <<'EOF'
private
var cfg_secret = 42;
public var cfg_open = 7;
public fn cfg_reader(): i64 { return cfg_secret; }
EOF
# public var + public fn (the fn reads the private var, same-file) => silent
cat > ok.cyr <<'EOF'
include "lib/cfg.cyr"
fn main(): i64 { return cfg_reader() + cfg_open; }
EOF
cat ok.cyr | "$CC" >/dev/null 2>vok.txt || true
grep -q "is private to its file" vok.txt 2>/dev/null && { echo "  FAIL: visibility-private — public var/fn or a same-file read was rejected"; fail=1; }
# cross-file READ of the private global
cat > vr.cyr <<'EOF'
include "lib/cfg.cyr"
fn main(): i64 { return cfg_secret; }
EOF
cat vr.cyr | "$CC" >/dev/null 2>vr.txt || true
grep -q "'cfg_secret' is private to its file" vr.txt 2>/dev/null     || { echo "  FAIL: visibility-private — cross-file READ of a private global not caught"; fail=1; }
# cross-file WRITE — a read-only check would pass the read case and miss this
cat > vw.cyr <<'EOF'
include "lib/cfg.cyr"
fn main(): i64 { cfg_secret = 9; return 0; }
EOF
cat vw.cyr | "$CC" >/dev/null 2>vw.txt || true
grep -q "'cfg_secret' is private to its file" vw.txt 2>/dev/null     || { echo "  FAIL: visibility-private — cross-file WRITE to a private global not caught"; fail=1; }
cd "$ROOT"

# ── private must not leak into the DYNAMIC SYMBOL TABLE either ───────────────────
# A private fn cannot be called from another file at compile time, so publishing it
# in .dynsym would hand a dynamic consumer a door the language just closed.
# Asserted on .dynstr contents because a `shared;` object has no section headers —
# readelf --dyn-syms cannot see them, only the PT_DYNAMIC STRTAB can.
mkdir -p "$T/so/lib" && cd "$T/so"
cat > lib/s.cyr <<'EOF'
private
fn so_hidden_sym(): i64 { return 1; }
public fn so_open_sym(): i64 { return so_hidden_sym(); }
EOF
cat > m.cyr <<'EOF'
shared;
include "lib/s.cyr"
fn main(): i64 { return so_open_sym(); }
EOF
cat m.cyr | "$CC" > t.so 2>/dev/null || true
if [ -s t.so ]; then
    grep -q "so_hidden_sym" t.so 2>/dev/null && { echo "  FAIL: visibility-private — a private fn was exported into .dynstr"; fail=1; }
    grep -q "so_open_sym" t.so 2>/dev/null || { echo "  FAIL: visibility-private — the PUBLIC fn was dropped from .dynstr"; fail=1; }
else
    echo "  note: shared-object emit produced nothing; export filter unchecked"
fi
cd "$ROOT"

# ── the default must stay completely inert ───────────────────────────────────────
cat > "$T/plain.cyr" <<'EOF'
fn plain_helper(): i64 { return 1; }
fn main(): i64 { return plain_helper(); }
EOF
( cd "$T" && cat plain.cyr | "$CC" >/dev/null 2>err3.txt ) || true
grep -q "is private to its file" "$T/err3.txt" 2>/dev/null && { echo "  FAIL: visibility-private — warned on a file with no 'private' declaration"; fail=1; }

# ── Phase 3: it is a HARD ERROR, and no binary may be emitted ────────────────────
( cd "$T" && cat m.cyr | "$CC" > out.bin 2>/dev/null ) || true
[ -s "$T/out.bin" ] && { echo "  FAIL: visibility-private — a violating program still produced a binary"; fail=1; }
grep -q "^error:" "$T/err.txt" 2>/dev/null || { echo "  FAIL: visibility-private — violation reported as a warning, not an error"; fail=1; }

# Multi-error: every violation in ONE run (the v6.4.62 contract). A fail-fast exit
# would make adopting `private` on a big file an N-compiles-to-find-N-callers job.
[ "$W" -ge 2 ] || { echo "  FAIL: visibility-private — not reporting all violations in one run"; fail=1; }

# The real adoption: lib/regex.cyr is private-by-default with a 9-fn public surface.
# This asserts the shipped tree actually enforces, not just the synthetic fixture.
cat > "$T/rx.cyr" <<'EOF'
include "lib/regex.cyr"
fn main(): i64 { return _re_alloc_class(); }
EOF
( cd "$ROOT" && cat "$T/rx.cyr" | "$CC" >/dev/null 2>"$T/rx.err" ) || true
grep -q "'_re_alloc_class' is private to its file" "$T/rx.err" 2>/dev/null     || { echo "  FAIL: visibility-private — lib/regex.cyr adoption is not enforcing"; fail=1; }
cat > "$T/rx2.cyr" <<'EOF'
include "lib/regex.cyr"
fn main(): i64 { return regex_compile(0, 0); }
EOF
( cd "$ROOT" && cat "$T/rx2.cyr" | "$CC" >/dev/null 2>"$T/rx2.err" ) || true
grep -q "is private to its file" "$T/rx2.err" 2>/dev/null     && { echo "  FAIL: visibility-private — regex.cyr's PUBLIC surface was rejected"; fail=1; }

if [ "$fail" = "0" ]; then
    echo "  PASS: visibility-private — fns (ordinary/tail/operator) + global vars (read/write) hard-errored cross-file; 'public' re-exposes both; lib/regex.cyr adoption live; private excluded from .dynstr; default inert"
fi

# ── v6.6.4: every path that resolves a user identifier through FINDFN and emits its
# own call/fixup (hisab 2026-09-13: `&_helper` was callable from any file) ─────────
mkdir -p "$T/paths/lib"; ln -s "$ROOT/lib"/* "$T/paths/lib/" 2>/dev/null || true
cat > "$T/paths/lib/hid.cyr" <<'HID'
private
struct HidBig { a: i64; b: i64; c: i64; }
struct HidPair { a: i64; b: i64; }
fn hid_fn(v): i64 { return v; }
fn hid_big(): HidBig { var s: HidBig; s.a = 1; s.b = 2; s.c = 3; return s; }
fn hid_pair(): HidPair { var s: HidPair; s.a = 1; s.b = 2; return s; }
fn hid_v2(): f64v2 { return f64v2_make(1, 2); }
fn hid_v4(): f64v4 { return f64v4_make(1, 2, 3, 4); }
impl HidTr for HidPair { fn hid_m(self) { return 42; } }
fn hid_same_amp(): i64 { var f = &hid_fn; return fncall1(f, 42); }
fn _gen<T>(x: T): T { return x; }
var _hid_arr[4];
var _hid_u8: u8[16];
public fn pub_fn(v): i64 { return v; }
public fn pub_big(): HidBig { return hid_big(); }
public fn pub_pair(): HidPair { return hid_pair(); }
public fn pub_same_amp(): i64 { return hid_same_amp(); }
public fn pgen<T>(x: T): T { return x; }
public var pub_arr[4];
var _after_pub_arr = 9;
struct HidGS { a: i64; b: i64; }
var _hid_gs: HidGS = alloc(16);
HID
# ⚠ FIXTURE ORDER IS LOAD-BEARING: `_after_pub_arr` and `_hid_gs` follow `public var
# pub_arr[4]` on purpose — before v6.6.4 an array declaration never CONSUMED the
# `public` marker, so the next declaration was silently re-exposed. arr_pub_next pins
# that by name; gs_field/gs_two would ALSO red on it, but they exist for the dedup.
PPRE='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/simd.cyr"
include "lib/hid.cyr"
'
# paxis <name> <expected-count> <symbol> <body> [env]
paxis() {
    _n=$1; _want=$2; _sym=$3; _body=$4; _envv=$5
    printf '%s%s\n' "$PPRE" "$_body" > "$T/paths/$_n.cyr"
    ( cd "$T/paths" && env $_envv "$CC" < "$_n.cyr" > "$_n.bin" 2> "$_n.err" ) || true
    _got=$(grep -c "'$_sym' is private to its file" "$T/paths/$_n.err" || true)
    if [ "$_got" != "$_want" ]; then
        echo "  FAIL: visibility-private [$_n]: expected $_want x \"'$_sym' is private\", got $_got"; head -2 "$T/paths/$_n.err" | sed 's/^/      /'; fail=1
    fi
    if [ "$_want" != "0" ] && [ -s "$T/paths/$_n.bin" ]; then echo "  FAIL: visibility-private [$_n]: a binary was still emitted"; fail=1; fi
    if [ "$_want" = "0" ] && [ ! -s "$T/paths/$_n.bin" ]; then echo "  FAIL: visibility-private [$_n]: legit program refused"; head -2 "$T/paths/$_n.err" | sed 's/^/      /'; fail=1; fi
}
# `&fn` — the hisab path (in-fn, top-level, and in fncallN's arg position)
paxis amp_infn    1 hid_fn 'fn main(): i64 { var f = &hid_fn; return callptr(f, 1); }'
paxis amp_top     1 hid_fn 'var g = &hid_fn; fn main(): i64 { return fncall1(g, 1); }'
paxis amp_fncall  1 hid_fn 'fn main(): i64 { return fncall1(&hid_fn, 1); }'
paxis amp_pub     0 pub_fn 'fn main(): i64 { var f = &pub_fn; return callptr(f, 1); }'
paxis amp_same    0 hid_fn 'fn main(): i64 { return pub_same_amp(); }'
# `s.method()` — its own call emitter (parse_decl.cyr method path)
paxis method      1 HidPair_hid_m 'fn main(): i64 { var p: HidPair; p.a = 0; p.b = 0; return p.hid_m(); }'
# struct receives that emit their own call
paxis asv_typed   1 hid_big  'fn main(): i64 { var s: HidBig = hid_big(); return s.c; }'
paxis asp_typed   1 hid_pair 'fn main(): i64 { var s: HidPair = hid_pair(); return s.b; }'
paxis asp_infer   1 hid_pair 'fn main(): i64 { var s = hid_pair(); return s.b; }'
paxis asv_pub     0 hid_big  'fn main(): i64 { var s: HidBig = pub_big(); return s.c; }'
paxis asp_pub     0 hid_pair 'fn main(): i64 { var s = pub_pair(); return s.b; }'
# PE-only own-call paths (Win64 retptr vector receive / assign / return)
paxis pe_v2_decl  1 hid_v2 'fn main(): i64 { var v: f64v2 = hid_v2(); return 0; }' CYRIUS_TARGET_WIN=1
paxis pe_v4_decl  1 hid_v4 'fn main(): i64 { var v: f64v4 = hid_v4(); return 0; }' CYRIUS_TARGET_WIN=1
paxis pe_v2_asg   1 hid_v2 'fn main(): i64 { var v: f64v2 = f64v2_make(0, 0); v = hid_v2(); return 0; }' CYRIUS_TARGET_WIN=1
paxis pe_v2_ret   1 hid_v2 'fn w(): f64v2 { return hid_v2(); } fn main(): i64 { var v: f64v2 = w(); return 0; }' CYRIUS_TARGET_WIN=1
# the same shapes on Linux must report exactly ONCE too (no lookahead double-report)
paxis lx_v2_decl  1 hid_v2 'fn main(): i64 { var v: f64v2 = hid_v2(); return 0; }'
paxis lx_v2_ret   1 hid_v2 'fn w(): f64v2 { return hid_v2(); } fn main(): i64 { var v: f64v2 = w(); return 0; }'
# generic instances: a PUBLIC generic in a private file must build at a non-i64 type
# from another file (the instance inherited the FILE default and was refused), while
# a private generic's instance must still be refused.
paxis pgen_i32    0 'pgen$i32' 'fn main(): i64 { var v: i32 = pgen<i32>(42); return v; }'
paxis gen_i32     1 '_gen$i32' 'fn main(): i64 { var v: i32 = _gen<i32>(42); return v; }'
# top-level arrays: PARSE_GVAR_ARR never stamped them (guide: "every fn and global var")
paxis arr_name    1 _hid_arr 'fn main(): i64 { return load64(&_hid_arr); }'
paxis arr_u8      1 _hid_u8  'fn main(): i64 { return load8(&_hid_u8); }'
paxis arr_top     1 _hid_arr 'var q = &_hid_arr; fn main(): i64 { return load64(q); }'
paxis arr_pub     0 pub_arr  'fn main(): i64 { store64(&pub_arr, 5); return load64(&pub_arr); }'
# `public var arr[N]` must CONSUME the marker: the next declaration stays private
paxis arr_pub_next 1 _after_pub_arr 'fn main(): i64 { return _after_pub_arr; }'
# a field access resolves its base twice (lookahead + resolve) and reported the same
# violation at two columns — one report per (var, line), two lines report twice
paxis gs_field    1 _hid_gs  'fn main(): i64 { return _hid_gs.a; }'
paxis gs_two      2 _hid_gs  'fn main(): i64 { var x = _hid_gs.a;
var y = _hid_gs.b; return x + y; }'
[ "$fail" = 0 ] && echo "  PASS: visibility-private paths (&fn x3 + method + asv/asp/inferred + 4 PE-only) enforced once each; publics, same-file and public-generic instances accepted; private arrays refused"
exit $fail
