#!/bin/sh
# 6.6.13 (I11) — the Str -> `: cstring` warning reaches every shape that hands a Str to a
# `: cstring` param, says what is wrong, and never hints `str_data`.
#
# Filed by bayan 1.5.10 (docs/development/issues/archived/2026-10-01-str-cstring-diagnostic-misses-call-results.md).
# The check typed only an argument whose FIRST token was a `Str` local, on PARSE_FNCALL's path
# alone. Silent: a call result `f(t, str_from("k"))` (W2) or `f(t, mk())` (W3), a global
# declared `: Str` (W4 — compared against the LOCAL encoding `0 - sid`), an inferred global
# `var g = str_from(..)` (W5 — no type recorded), a `: Str` field (W6), a tail call (W7, W8 —
# PARSE_RETURN's own arg loop) and a method call (W9 — `_call_arg_one`). `s.data` was reported
# as the Str itself (F1), and the hint said `use str_data(x)`, which a `: cstring` param reads
# past the Str's length (a slice borrows its parent's bytes) — and `str_data(..)` is a call the
# check could not type, so taking the hint silenced the warning (F2).
#
# ⛔ WHY A GATE: a warning does not change an exit code, so no .tcyr can see any of this.
# ⭐ Axis 3 is the anti-vacuous one for the "warning text only" claim: the same source must
# give a BYTE-IDENTICAL binary with CYRIUS_TYPE_CHECK=0 — and must still warn with it on, so
# a check that warned by changing codegen, or that stopped warning, both fail.
# ⚠ The inferred-global record (GVDSID) is never written into GVTYPE ON PURPOSE: typing an
# inferred global through GVTYPE changes codegen (struct-copy init, field access). Axis 3's cmp
# is what would catch that "simplification". Since 6.6.16 the overload dispatcher READS GVDSID —
# it routes on this check's own classifier (`_str_arg_kind`), so `println(gi)` reaches
# `println_str` — and that routing does not depend on CYRIUS_TYPE_CHECK, so axis 3 still holds.
# Axis 4's last rows pin the invariant that buys: a call the dispatcher can route never warns —
# for a call or method RESULT too (`s.cat(t)`, `mkh().name`), typed by its own declared return.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL str_cstring_arg_shapes: no compiler at $CC"; exit 1; }
cd "$ROOT" || exit 1
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL str_cstring_arg_shapes: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
_ok() { echo "  ok: $1"; pass=$((pass + 1)); }
NEEDLE='which expects a cstring'
# Compile $1 (a .cyr) to $1.bin with the type check at $2; stderr to $1.err. Never merged.
build() { if CYRIUS_TYPE_CHECK=$2 "$CC" < "$1" > "$1.bin" 2> "$1.err"; then echo 0 > "$1.rc"; else echo $? > "$1.rc"; fi; }
warns() { grep -c "$NEEDLE" "$1.err" || true; }

# ---- the filed repro, VERBATIM (its file archives at slot close, so it is carried here) ----
cat > "$T/repro.cyr" <<'EOF'
# repro: the Str -> `: cstring` diagnostic sees only a named local, and its hint is wrong.
#
# Standalone (stdlib only). `lookup(t, key: cstring)` stands in for any C-string-keyed
# lookup: it answers 1 for the key "name", 2 for the key "names", and 0 otherwise. EVERY
# call below means the key "name", so the right answer is always 1.
#
#   W1-W9  hand it a `Str` (a 16-byte {data, len} header): `strlen` walks the header's
#          pointer bytes and the compare misses, a silent 0. Only W1 is warned about.
#   F1     hands it `sl.data`, where `sl` is the slice str_sub(str_from("names"), 0, 4).
#          A slice borrows its parent's bytes, so `sl.data` is NOT NUL-terminated at
#          str_len(sl): `strlen` reads "names" and the lookup answers 2, another key's
#          value. The warning here is right; its text ("passing Str-typed 'sl'") and its
#          hint are not.
#   F2     follows that hint, `str_data(sl)`: the same wrong pair, and now no warning.
#   C1     str_cstr(sl) (a NUL-terminated copy) and C2, a literal: both answer 1.
#
#   cyrius build docs/development/issues/repros/2026-10-01-str-cstring-diagnostic-misses-call-results.cyr r
#   ./r; echo "exit=$?"     # exit = number of W/F calls that did not answer 1
#
# Expected of the diagnostic: a warning on W1-W9, F1 and F2 whose hint names a Str-typed
# sibling or str_cstr(s), never str_data(s). Measured on the cyrius 6.6.12 release
# (x86_64, and --aarch64 under qemu-aarch64): 2 warnings (W1, F1), both hinting
# `str_data(..)`, and exit=11.

include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"

fn lookup(t, key: cstring): i64 {
    var n = strlen(key);
    if (n == 4) { if (memeq(key, "name", 4) == 1) { return 1; } }
    if (n == 5) { if (memeq(key, "names", 5) == 1) { return 2; } }
    return 0;
}

fn mk(): Str { return str_from("name"); }
struct H { name: Str; }
struct T { n; }
fn T_lk(self, key: cstring): i64 { return lookup(0, key); }
var gs: Str = str_from("name");
var gi = str_from("name");

fn w7(t): i64 { var sk = str_from("name"); return lookup(t, sk); }
fn w8(t, ps: Str): i64 { return lookup(t, ps); }

var _out[2];
# Print "<tag> <answer>\n"; count it as wrong when the answer is not 1.
fn show(tag, got): i64 {
    syscall(SYS_WRITE, 1, tag, strlen(tag));
    store8(&_out, 32);
    store8(&_out + 1, 48 + got);
    syscall(SYS_WRITE, 1, &_out, 2);
    syscall(SYS_WRITE, 1, "\n", 1);
    if (got == 1) { return 0; }
    return 1;
}

fn main(): i64 {
    alloc_init();
    var t = 0;
    var sk = str_from("name");
    var h: H;
    h.name = sk;
    var o: T;
    o.n = 0;
    var sl = str_sub(str_from("names"), 0, 4);
    var bad = 0;
    bad = bad + show("W1", lookup(t, sk));                # named Str local -> warned
    bad = bad + show("W2", lookup(t, str_from("name")));  # inline str_from(..)
    bad = bad + show("W3", lookup(t, mk()));              # a fn declared `: Str`
    bad = bad + show("W4", lookup(t, gs));                # a global declared `var gs: Str`
    bad = bad + show("W5", lookup(t, gi));                # an inferred global `var gi = str_from(..)`
    bad = bad + show("W6", lookup(t, h.name));            # a `: Str` struct field
    bad = bad + show("W7", w7(t));                        # tail call `return lookup(t, sk)`
    bad = bad + show("W8", w8(t, sk));                    # tail call with a `ps: Str` param
    bad = bad + show("W9", o.lk(sk));                     # method call into `key: cstring`
    bad = bad + show("F1", lookup(t, sl.data));           # a slice's data pointer -> warned
    bad = bad + show("F2", lookup(t, str_data(sl)));      # what the hint says to write
    if (show("C1", lookup(t, str_cstr(sl))) != 0) { bad = bad + 100; }
    if (show("C2", lookup(t, "name")) != 0) { bad = bad + 100; }
    return bad;
}
var rc = main();
syscall(SYS_EXIT, rc);
EOF
# The carried copy must still BE the filed repro, wherever the issue now lives.
FILED=$(find docs/development/issues -name '2026-10-01-str-cstring-diagnostic-misses-call-results.cyr' 2>/dev/null | head -1)
if [ -n "$FILED" ]; then
    if cmp -s "$FILED" "$T/repro.cyr"; then _ok "axis 0: the carried repro is byte-identical to $FILED"
    else _bad "axis 0: the carried repro differs from the filed $FILED — re-copy it verbatim"; fi
fi

# ---- axis 1: the filed repro warns on W1-W9, F1, F2 — and nothing else ----
build "$T/repro.cyr" 1
if [ "$(cat "$T/repro.cyr.rc")" != 0 ]; then
    _bad "axis 1: the filed repro did not compile"; sed -n 1,5p "$T/repro.cyr.err"
else
    got=$(grep "$NEEDLE" "$T/repro.cyr.err" | sed -n 's/^warning:<source>:\([0-9]*:[0-9]*\):.*/\1/p' | tr '\n' ' ')
    want='44:61 45:43 69:38 70:38 71:38 72:38 73:38 74:38 77:33 78:38 79:38 '
    if [ "$got" = "$want" ]; then _ok "axis 1: 11 warnings at exactly W7 W8 (their tail-call sites) W1-W6 W9 F1 F2, none at C1 C2"
    else _bad "axis 1: warning sites are '$got', want '$want'"; fi
    n=$(grep -c 'hint:.*str_data' "$T/repro.cyr.err" || true)
    if [ "$n" -eq 0 ]; then _ok "axis 1b: no hint suggests str_data"
    else _bad "axis 1b: $n hint(s) still suggest str_data — the hint that turned F1 into the silent F2"; fi
    n=$(grep -c 'hint:.*str_cstr(' "$T/repro.cyr.err" || true)
    if [ "$n" -eq 11 ]; then _ok "axis 1c: every hint offers str_cstr(..)"
    else _bad "axis 1c: $n of 11 hints offer str_cstr(..)"; fi
    if grep -q ":78:38: passing a Str's data pointer 'sl.data' .*not NUL-terminated at its length" "$T/repro.cyr.err" \
       && grep -q ":79:38: passing a Str's data pointer 'str_data(sl)' .*not NUL-terminated at its length" "$T/repro.cyr.err"; then
        _ok "axis 1d: F1 and F2 are reported as a Str's DATA POINTER, not as the Str"
    else _bad "axis 1d: F1/F2 are not worded as a Str's data pointer"; grep ':7[89]:' "$T/repro.cyr.err" || true; fi
    if grep -q ":77:33: passing Str-typed 'sk' to 'T_lk'" "$T/repro.cyr.err" \
       && grep -q ":70:38: passing Str-typed 'str_from(..)'" "$T/repro.cyr.err" \
       && grep -q ":74:38: passing Str-typed 'h.name'" "$T/repro.cyr.err"; then
        _ok "axis 1e: the message names the argument as written (call, field) and the method's registered fn"
    else _bad "axis 1e: argument / callee naming wrong"; grep ':7[047]:' "$T/repro.cyr.err" || true; fi
    # ---- axis 2: warning text only — the program still computes the same wrong answers ----
    chmod +x "$T/repro.cyr.bin"
    out=$("$T/repro.cyr.bin" | tr '\n' ' ' || true)
    if "$T/repro.cyr.bin" > /dev/null; then rc=0; else rc=$?; fi
    if [ "$rc" = 11 ] && [ "$out" = 'W1 0 W2 0 W3 0 W4 0 W5 0 W6 0 W7 0 W8 0 W9 0 F1 2 F2 2 C1 1 C2 1 ' ]; then
        _ok "axis 2: the repro still runs exit=11 with the filed output (the warning fixes nothing by itself)"
    else _bad "axis 2: repro output changed: exit=$rc, '$out'"; fi
fi

# ---- axis 3 (ANTI-VACUOUS): byte-identical binary with the type check OFF, warnings only ON ----
build "$T/repro.cyr" 0
cp "$T/repro.cyr.err" "$T/repro.tc0.err"
cp "$T/repro.cyr.bin" "$T/repro.tc0.bin"
build "$T/repro.cyr" 1
if cmp -s "$T/repro.tc0.bin" "$T/repro.cyr.bin" && [ "$(grep -c "$NEEDLE" "$T/repro.tc0.err" || true)" -eq 0 ] \
   && [ "$(warns "$T/repro.cyr")" -eq 11 ]; then
    _ok "axis 3: CYRIUS_TYPE_CHECK=0 and =1 give byte-identical binaries; only =1 warns"
else _bad "axis 3: the check changed codegen, or its on/off switch no longer works"; fi

# ---- axis 4: the shapes beyond the repro, each with an exact warning count ----
# row <name> <want> — compiles $T/row.cyr (written just before) and counts warnings.
row() {
    build "$T/row.cyr" 1
    if [ "$(cat "$T/row.cyr.rc")" != 0 ]; then _bad "axis 4 $1: did not compile"; sed -n 1,4p "$T/row.cyr.err"; return; fi
    n=$(warns "$T/row.cyr")
    if [ "$n" -eq "$2" ]; then _ok "axis 4 $1: $n warning(s)"
    else _bad "axis 4 $1: $n warning(s), want $2"; grep -A1 "$NEEDLE" "$T/row.cyr.err" || true; fi
}
HDR='include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn foo(t, k: cstring): i64 { return strlen(k); }
fn foo_str(t, k: Str): i64 { return str_len(k); }
fn kv_by_cstr(t, k: cstring): i64 { return strlen(k); }
fn kv_by_str(t, k: Str): i64 { return str_len(k); }
fn later(t, k: cstring): i64 { return strlen(k); }
struct H { name: Str; n; }
struct T { n; }
fn T_m(self, k: cstring): i64 { return strlen(k); }'

printf '%s\n%s\n' "$HDR" 'fn main(): i64 { alloc_init(); var sk = str_from("a"); var r = foo(0, sk); r = r + kv_by_cstr(0, sk); return r; }
var rc = main();' > "$T/row.cyr"
row "sibling hints" 2
if grep -q "hint: call 'foo_str', which takes a Str" "$T/row.cyr.err" && grep -q "hint: call 'kv_by_str', which takes a Str" "$T/row.cyr.err"; then
    _ok "axis 4 sibling hints: name the _str overload (foo_str) and the <stem>_cstr -> <stem>_str pair (kv_by_str)"
else _bad "axis 4 sibling hints: foo_str / kv_by_str not named"; grep 'hint' "$T/row.cyr.err" || true; fi

printf '%s\n%s\n' "$HDR" 'var gl = mkl();
fn mkl(): Str { return str_from("q"); }
fn main(): i64 { alloc_init(); var r = foo(0, gl); return r; }
var rc = main();' > "$T/row.cyr"
row "inferred global from a fn defined AFTER it" 1

printf '%s\n%s\n' "$HDR" 'var gh = H { 0, 0 };
fn main(): i64 { alloc_init(); var r = foo(0, gh.name); return r; }
var rc = main();' > "$T/row.cyr"
row "struct-literal global's Str field" 1

printf '%s\n%s\n' "$HDR" 'fn H_go(self: H): i64 { var r = later(0, self.name); return r; }
fn main(): i64 { alloc_init(); var h: H; h.name = str_from("x"); var r = h.go(); return r; }
var rc = main();' > "$T/row.cyr"
row "a method body passing self's Str field" 1

printf '%s\n%s\n' "$HDR" 'fn main(): i64 { alloc_init(); var o: T; o.n = 0; var r = o.m(str_from("a")); return r; }
var rc = main();' > "$T/row.cyr"
row "a method call with a call argument" 1

printf '%s\n%s\n' "$HDR" 'fn fwd(s: Str): i64 { return later(0, s); }
fn main(): i64 { alloc_init(); var r = fwd(str_from("a")); return r; }
var rc = main();' > "$T/row.cyr"
row "a tail call with a literal argument (diverted to PARSE_FNCALL)" 1

printf '%s\n%s\n' "$HDR" 'var gs: Str = str_from("g");
fn main(): i64 {
    alloc_init();
    var s = str_from("abc");
    var p = &s;
    var r = foo(0, s + 8);
    r = r + foo(0, s.len);
    r = r + foo(0, load64(p));
    r = r + foo(0, str_cstr(s));
    r = r + foo(0, "lit");
    r = r + foo(0, 0);
    var gs = 0;
    r = r + foo(0, gs);
    return r;
}
var rc = main();' > "$T/row.cyr"
row "left alone: s + 8, s.len, load64(p), str_cstr(s), a literal, 0, a local shadowing a Str global" 0

printf '%s\n%s\n' "$HDR" 'var gr = mkr();
var gr = 5;
fn mkr(): Str { return str_from("q"); }
fn main(): i64 { alloc_init(); var r = foo(0, gr); return r; }
var rc = main();' > "$T/row.cyr"
row "a redeclaration folded onto the slot clears the inferred record" 0

# A global declared AFTER the first top-level statement (`alloc_init();` — 139 tcyr files open with
# one) is registered by PARSE_VAR's global arm, never PARSE_GVAR_REG: the inferred record must be
# written on that path too. The first cut wrote it only in PARSE_GVAR_REG, so `g` here was silent
# while the annotated `g3` beside it warned.
printf '%s\n%s\n' "$HDR" 'alloc_init();
var g = str_from("x");
var g3: Str = str_from("y");
var gn = strlen("x");
var gq = str_from("x");
var gq = 5;
var gm = mkm();
fn mkm(): Str { return str_from("q"); }
fn main(): i64 { var r = foo(0, g); r = r + foo(0, g3); r = r + foo(0, gn); r = r + foo(0, gq); r = r + foo(0, gm); return r; }
var rc = main();' > "$T/row.cyr"
row "globals after a top-level statement: inferred g, annotated g3, forward-fn gm warn; i64 gn, redeclared gq do not" 3
if grep -q "passing Str-typed 'g' " "$T/row.cyr.err" && grep -q "passing Str-typed 'gm' " "$T/row.cyr.err"; then
    _ok "axis 4 after-statement globals: the inferred g and gm are among the warnings"
else _bad "axis 4 after-statement globals: an inferred global on the PARSE_PROG path is silent"; grep "$NEEDLE" "$T/row.cyr.err" || true; fi

# GVTYPE's positive range is shared with scalar WIDTHS: an `i32` global stores 4. With `Str` as
# the 4th struct its sid is 4 too, so an ungated positive compare reads the i32 as a Str.
cat > "$T/row.cyr" <<'EOF'
struct A1 { a; }
struct A2 { a; }
struct A3 { a; }
struct Str { data; len; }
fn f(t, k: cstring): i64 { return k; }
var gw: i32 = 5;
var gv: Str = Str { 0, 0 };
fn main(): i64 { var r = f(0, gw); r = r + f(0, gv); return r; }
var rc = main();
syscall(60, rc);
EOF
row "an i32 global whose width equals Str's struct id stays silent; the Str global beside it warns" 1
if grep -q "passing Str-typed 'gv'" "$T/row.cyr.err"; then _ok "axis 4 width/sid: the one warning is the Str global, not the i32"
else _bad "axis 4 width/sid: the warning is not on the Str global"; grep "$NEEDLE" "$T/row.cyr.err" || true; fi

# 6.6.16 (C3): the overload dispatcher asks `_str_arg_kind` too, so whenever this warning would
# say "passing Str-typed X" to a base with an arity-compatible `_str` sibling, the call is ROUTED
# instead — and must not warn. Before 6.6.16 every call here warned and printed the Str header's
# pointer bytes (no Str global or field was ever routed), and strlen(gs) answered 3.
printf '%s\n%s\n' "$HDR" 'var gs: Str = str_from("explicit-global");
var gi = str_from("inferred-global");
fn main(): i64 {
    alloc_init();
    var h: H;
    h.name = str_from("field");
    println(gs);
    println(gi);
    println(h.name);
    var r = strlen(gs);
    return r;
}
var rc = main();
syscall(SYS_EXIT, rc);' > "$T/row.cyr"
row "routed: println(gs), println(gi), println(h.name), strlen(gs) reach their _str siblings" 0
if [ "$(cat "$T/row.cyr.rc")" = 0 ]; then
    chmod +x "$T/row.cyr.bin"
    out=$("$T/row.cyr.bin" | tr '\n' ' ' || true)
    if "$T/row.cyr.bin" > /dev/null; then rc=0; else rc=$?; fi
    if [ "$out" = 'explicit-global inferred-global field ' ] && [ "$rc" = 15 ]; then
        _ok "axis 4 routed: the binary prints the three strings and strlen(gs) is 15"
    else _bad "axis 4 routed: printed '$out', exit $rc (want the three strings, exit 15)"; fi
fi
# A closure capture is typed as PARSE_FACTOR reads it — before any global of the same name. 6.6.15
# warned on the cstr capture `s` (reading the Str global `s`) and was silent on the Str capture `lt`;
# the dispatcher shares this classifier, so the same mistake routed `show(s)` to `show_str`.
printf '%s\n%s\n' "$HDR" 'var s: Str = str_from("g");
fn main(): i64 {
    alloc_init();
    var s = "cstr";
    var lt: Str = str_from("cap");
    var c1 = |x| later(0, s) + x;
    var c2 = |x| later(0, lt) + x;
    return fncall1(c1, 0) + fncall1(c2, 0);
}
var rc = main();' > "$T/row.cyr"
row "closure captures: a cstr capture named like a Str global is silent, a Str capture warns" 1
if grep -q "passing Str-typed 'lt' to 'later'" "$T/row.cyr.err"; then _ok "axis 4 captures: the one warning is the Str capture"
else _bad "axis 4 captures: the warning is not on the Str capture 'lt'"; grep "$NEEDLE" "$T/row.cyr.err" || true; fi
# A call or method RESULT is typed by its own declared return (`_str_step_kind`), never by its
# receiver: the first 6.6.16 cut dropped `s.cat(t)` — routed before only because `s` is a Str,
# which also sent `s.len()` to `println_str` — and printed the header's pointer bytes for it.
printf '%s\n%s\n' "$HDR" 'fn mkh(): H { var h: H; h.name = str_from("callfield"); h.n = 0; return h; }
fn H_getname(self: H): Str { return self.name; }
fn main(): i64 {
    alloc_init();
    var s: Str = str_from("hello");
    var t: Str = str_from("XY");
    var h = mkh();
    println(s.cat(t));
    println(h.getname());
    println(mkh().name);
    var r = strlen(s.sub(1, 4));
    return r;
}
var rc = main();
syscall(SYS_EXIT, rc);' > "$T/row.cyr"
row "routed results: println(s.cat(t)), println(h.getname()), println(mkh().name), strlen(s.sub(1, 4))" 0
if [ "$(cat "$T/row.cyr.rc")" = 0 ]; then
    chmod +x "$T/row.cyr.bin"
    out=$("$T/row.cyr.bin" | tr '\n' ' ' || true)
    if "$T/row.cyr.bin" > /dev/null; then rc=0; else rc=$?; fi
    if [ "$out" = 'helloXY callfield callfield ' ] && [ "$rc" = 4 ]; then
        _ok "axis 4 routed results: the binary prints the three strings and strlen(s.sub(1, 4)) is 4"
    else _bad "axis 4 routed results: printed '$out', exit $rc (want the three strings, exit 4)"; fi
fi
# The same shapes into a `: cstring` param with no sibling warn, named as written; an i64 method
# and an untyped field of a result stay silent.
printf '%s\n%s\n' "$HDR" 'fn mkh(): H { var h: H; h.name = str_from("f"); h.n = 0; return h; }
fn H_getname(self: H): Str { return self.name; }
fn mk(): Str { return str_from("m"); }
fn gstr<X>(x: X): Str { return str_from("g"); }
fn main(): i64 {
    alloc_init();
    var s: Str = str_from("abc");
    var r = later(0, s.clone());
    r = r + later(0, mkh().name);
    r = r + later(0, mkh().getname());
    r = r + later(0, gstr<i64>(0));
    r = r + later(0, mk().data);
    r = r + later(0, s.len());
    r = r + later(0, mkh().n);
    return r;
}
var rc = main();' > "$T/row.cyr"
row "results into a cstring: s.clone(), mkh().name, mkh().getname(), gstr<i64>(0), mk().data warn; s.len(), mkh().n do not" 5
if grep -q "passing Str-typed 's.clone()' to 'later'" "$T/row.cyr.err" \
    && grep -q "pass str_cstr(s.clone())" "$T/row.cyr.err" \
    && grep -q "passing Str-typed 'mkh().name' to 'later'" "$T/row.cyr.err" \
    && grep -q "passing Str-typed 'mkh().getname()' to 'later'" "$T/row.cyr.err" \
    && grep -q "passing Str-typed 'gstr<..>(..)' to 'later'" "$T/row.cyr.err" \
    && grep -q "passing a Str's data pointer 'mk().data' to 'later'" "$T/row.cyr.err" \
    && grep -q "pass str_cstr(mk())" "$T/row.cyr.err"; then
    _ok "axis 4 results: each warning names the argument as written, and the hint wraps it"
else _bad "axis 4 results: a warning or hint does not name the argument as written"; grep -A1 "$NEEDLE" "$T/row.cyr.err" || true; fi
# ...and the data pointer is still not a Str: not routed, and still warned about as one.
printf '%s\n%s\n' "$HDR" 'var gs: Str = str_from("explicit-global");
fn main(): i64 { alloc_init(); println(gs.data); return 0; }
var rc = main();' > "$T/row.cyr"
row "not routed: println(gs.data)" 1
if grep -q "passing a Str's data pointer 'gs.data' to 'println'" "$T/row.cyr.err"; then
    _ok "axis 4 not routed: println(gs.data) is still reported as a Str's data pointer"
else _bad "axis 4 not routed: println(gs.data) is not reported as a data pointer"; grep "$NEEDLE" "$T/row.cyr.err" || true; fi

echo "str_cstring_arg_shapes: $pass ok, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "PASS: str-cstring-arg-shapes"
exit 0
