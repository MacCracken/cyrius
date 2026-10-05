#!/bin/sh
# deprecated_every_call_path.sh — 6.6.16 (C9). `#deprecated("msg")` warns EXACTLY ONCE, on the
# call's own line, on EVERY path that reaches the fn — and changes no byte of any binary.
#
# ⛔ THE DEFECT (measured on the slot open; filed by bayan 1.5.10 on 6.6.12, roadmap backlog):
#   - a call parsed BEFORE the definition was silent on every path: only pass 2 set fn flag 4, at
#     PARSE_FN_DEF, so `fn early() { return old_f(x); }` above the definition never warned;
#   - `_DEPRECATED_WARN` had 3 callers while `_vis_check` had 14, so `&old_f`, `o.m()`, the struct
#     receives (`var q: P3 = f()`, `var p: P2 = f()`), operator dispatch (scalar and struct result)
#     and the PE-only vector receives / return were silent;
#   - a tail call was reported at the NEXT token (`return old_f(x);` on 14 printed 15:1), because
#     the warning read the cursor after `);` was consumed;
#   - a generic instance (`old_g<i32>(..)`, minted `old_g$i32`) never carried the bit, and the
#     re-parses of the same tokens (an `#inline` body per expansion, a generic body per instance,
#     a vector fn's `return` on aarch64/cx) printed the identical line again.
#
# ⭐ THE FIX (src/frontend/parse_fn.cyr): one per-callee check, `_callee_site_checks(S, fi, noff,
# ti)` (`private` + `#deprecated`), replaces every `_vis_check` site and names a token of the
# call; pass 1 records the attribute (`_tl_deprecated(S, 0)` -> `_prescan_dep_take`, one call in
# `_prescan_fn_sig`); an instance inherits its base's bit (`_gen_inherit_dep`); `_dep_seen`
# prints a (token, fn) pair once.
#
# ROWS — every fixture through five compilers built FROM THIS TREE: x86 (src/main.cyr), PE through
# main.cyr (CYRIUS_TARGET_WIN=1), PE through src/main_win.cyr, the aarch64 cross and cx (cx skips
# the 16-byte pair-return fixture: cx refuses that ABI by name). Plus the aarch64-native fork under
# qemu-aarch64 when present. For each:
#   1. the lines carrying a `#W` marker are EXACTLY the reported lines, one warning each — so a
#      missing path, a double fire and a warning on a non-deprecated fn are all red;
#   2. the attribute-free twin compiles to a BYTE-IDENTICAL binary and warns nothing — diagnostics
#      only. The twin keeps the message literal (`#assert 1, "msg";` on the same line): the lexer's
#      string pool is emitted whole, so the text is in .rodata with or without the attribute;
#   3. the filed repro's five reports, verbatim with columns, on x86: 3:18 6:19 14:18 17:22 21:19;
#   4. the PE-only vector paths are the ones that fire on PE: they name the callee (11:20, 12:20,
#      13:9, 6:12) where PARSE_FNCALL names the first argument (11:26 ...);
#   5. an `async fn`: pass 2 marks its body fn `old_a$impl` (reached only by pointer), so a call
#      or `await` of `old_a` was silent; pass 1 marks `old_a`. x86, CYRIUS_ASYNC=1;
#   6. a bare `#deprecated` is still refused by name, before and after the first statement;
#   7. a fixture floor, so an empty fixture set cannot pass.
#
# On the tree before the fix: 52 of 114 rows red.
# MUTATION LEDGER (6.6.16: a copy of the tree with ONE edit, its compilers rebuilt by this gate):
#   a. `_prescan_dep_take` takes nothing (no pass-1 record)     -> 43 red: every call parsed before
#        its definition (filed 3 6, tailregion 2 5, addr 2, method 6, agg 6, pair 3, generic 2 3) on
#        every compiler, and the async row
#   b. the tail path names the cursor again                     -> 7 red (filed 4 and 15, verbatim row)
#   c. one site back to `_vis_check` alone: `&fn` -> 13 red; method-dot 6; scalar operator 6;
#        struct-result operator 6; retptr receive 6; pair receive 5; each PE vector path (`_f2c`,
#        `_f4c`, `_try_vector_call_assign`, `_rc`) 4 (both PE compilers, lines and columns)
#   d. an instance does not inherit its base's bit              -> 6 red (generic 3 14)
#   e. no one-warning-per-site record                           -> 11 red (generic 10 twice, 12 three
#        times; vec 6 twice on x86, aarch64, cx and the native fork)
#   f. the tail scan keeps the pending past a nested fn         -> 6 red (parity: `b` warned at 6, 7)
#   g. the pass-1 pending not cleared at `_prescan_tail` exit   -> 0 red: nothing reads the pass-1
#        pair after pass 1, so the clear is hygiene, not a row.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: deprecated_every_call_path: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL deprecated_every_call_path: no compiler at $CC"; exit 1; }
cd "$R" || exit 1

# ── the compilers, from this tree ──────────────────────────────────────────────────────────────
"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" || { echo "FAIL deprecated_every_call_path: could not build src/main.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
for f in main_win main_aarch64 main_cx; do
    "$T/x86" < "src/$f.cyr" > "$T/$f" 2> "$T/eb" || { echo "FAIL deprecated_every_call_path: could not build src/$f.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    chmod +x "$T/$f"
done
printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$T/x86" > "$T/pe_main"; chmod +x "$T/pe_main"
COMPILERS="x86 pe_main main_win main_aarch64 main_cx"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    "$T/main_aarch64" < src/main_aarch64_native.cyr > "$T/native.bin" 2> "$T/eb" \
        || { echo "FAIL deprecated_every_call_path: could not build src/main_aarch64_native.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    chmod +x "$T/native.bin"
    printf '#!/bin/sh\nexec qemu-aarch64 "%s"\n' "$T/native.bin" > "$T/main_aarch64_native"; chmod +x "$T/main_aarch64_native"
    COMPILERS="$COMPILERS main_aarch64_native"
else
    echo "  SKIP (named): the aarch64-native fork row — qemu-aarch64 is not installed"
fi

fail=0
pass=0
_ok()  { pass=$((pass + 1)); }
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# ── the fixtures. `#W` marks a line that must carry exactly one warning. ───────────────────────
mkdir -p "$T/fx"
# The filed shapes (roadmap backlog "`#deprecated` gaps"), as the 6.6.16 premise measured them —
# verbatim, so the call lines are listed beside it rather than marked in it.
cat > "$T/fx/filed.cyr" <<'EOF'
include "lib/fnptr.cyr"
fn early(x) {
    return old_f(x);
}
fn early2(x) {
    var r = old_f(x);
    return r;
}
#deprecated("use new_f")
fn old_f(x) {
    return x + 1;
}
fn tailer(x) {
    return old_f(x);
}
fn viaptr() {
    var r = fncall1(&old_f, 1);
    return r;
}
fn nontail() {
    var r = old_f(1);
    return r;
}
var a = early(1) + early2(1) + tailer(1) + viaptr() + nontail();
syscall(60, a);
EOF
printf '3\n6\n14\n17\n21\n' > "$T/fx/filed.lines"
# A deprecated fn defined AFTER the first top-level statement — pass 1's `_prescan_tail` region.
cat > "$T/fx/tailregion.cyr" <<'EOF'
fn a1(x) {
    var r = late_dep(x);   #W
    return r;
}
fn a0(x) { return late_dep(x); }   #W
var g = 0;
g = a1(1) + a0(1);
#deprecated("late")
fn late_dep(x) { return x * 2; }
fn a2(x) { return late_dep(x); }   #W
g = g + a2(2) + late_dep(3);   #W
syscall(60, g);
EOF
# `&fn` in a fn before and after the definition, and at top level.
cat > "$T/fx/addr.cyr" <<'EOF'
include "lib/fnptr.cyr"
fn fwd() { var h = &old_f; return fncall1(h, 1); }   #W
#deprecated("use new_f")
fn old_f(x) { return x + 1; }
var g = &old_f;   #W
fn bwd() {
    var h = &old_f;   #W
    return fncall1(g, 1) + fncall1(h, 2);
}
var rc = fwd() + bwd();
syscall(60, rc);
EOF
# `u.m()` reaching a top-level `#deprecated fn U_m(self)`, before and after the definition.
cat > "$T/fx/method.cyr" <<'EOF'
include "lib/alloc.cyr"
struct U { n: i64; }
fn early() {
    var u: U = alloc(8);
    store64(u, 4);
    return u.m();   #W
}
#deprecated("use U_m2")
fn U_m(self) { return load64(self); }
fn U_m2(self) { return load64(self) + 1; }
fn late() {
    var u: U = alloc(8);
    store64(u, 5);
    var a = u.m();   #W
    var b = u.m2();
    return a + b;
}
alloc_init();
var rc = early() + late();
syscall(60, rc);
EOF
# The retptr struct receive (forward and backward), operator dispatch with a scalar and with a
# struct result, and a struct-valued assignment.
cat > "$T/fx/agg.cyr" <<'EOF'
include "lib/alloc.cyr"
struct P3 { a: i64; b: i64; c: i64; }
struct V { x: i64; }
struct W3 { a: i64; b: i64; c: i64; }
fn early() {
    var q: P3 = old_mk3(1);   #W
    return q.a;
}
#deprecated("mk3 old")
fn old_mk3(x): P3 { var r: P3; r.a = x; r.b = x; r.c = x; return r; }
#deprecated("V_add old")
fn V_add(a, b) { return load64(a) + load64(b); }
#deprecated("W3_add old")
fn W3_add(a, b): W3 { var r: W3; r.a = load64(a) + load64(b); r.b = 0; r.c = 0; return r; }
fn main() {
    var q: P3 = old_mk3(1);   #W
    var v1: V = alloc(8);
    var v2: V = alloc(8);
    store64(v1, 1);
    store64(v2, 2);
    var s = v1 + v2;   #W
    var w1: W3;
    w1.a = 1; w1.b = 0; w1.c = 0;
    var w2: W3;
    w2.a = 2; w2.b = 0; w2.c = 0;
    var w3: W3 = w1 + w2;   #W
    q = old_mk3(4);   #W
    return s + q.c + w3.a + early();
}
alloc_init();
var rc = main();
syscall(60, rc);
EOF
# The 16-byte pair receive, declared and inferred (cx refuses this ABI by name: skipped there).
cat > "$T/fx/pair.cyr" <<'EOF'
struct P2 { a: i64; b: i64; }
fn early() {
    var p: P2 = old_mk2(1);   #W
    return p.a;
}
#deprecated("mk2 old")
fn old_mk2(x): P2 { var r: P2; r.a = x; r.b = x; return r; }
fn main() {
    var p: P2 = old_mk2(2);   #W
    var t = old_mk2(5);   #W
    return p.b + t.a + early();
}
var rc = main();
syscall(60, rc);
EOF
# A generic: the i64 spelling, an instance before and after the definition, a call inside a
# generic body (parsed again per instance), an `#inline` body (parsed again per expansion).
cat > "$T/fx/generic.cyr" <<'EOF'
fn early() {
    var a = old_g<i64>(3);   #W
    var c = old_g<i32>(5);   #W
    return a + c;
}
#deprecated("g old")
fn old_g<T>(x: T): T { return x; }
#deprecated("f old")
fn old_f(x) { return x + 1; }
fn gb<T>(x: T): T { var y = old_f(1); return x + y; }   #W
#inline
fn w(x) { return old_f(x) + 0; }   #W
fn late() {
    var d = old_g<i32>(6);   #W
    var e = gb<i32>(1) + gb(2) + w(1) + w(2);
    return d + e;
}
var rc = early() + late();
syscall(60, rc);
EOF
# The pass-1 / pass-2 agreement: pass 2 gives a pending attribute to the next fn it PARSES, which
# here sits inside a top-level block; pass 1 never prescans that fn, so it must not hand the
# attribute to the next top-level fn instead (`b` would warn falsely at every call).
cat > "$T/fx/parity.cyr" <<'EOF'
var z = 1;
z = 2;
#deprecated("x")
if (z == 2) { fn a(): i64 { return 1; } }
fn b(): i64 { return 2; }
var r = b() + a();   #W
r = r + b();
syscall(60, r);
EOF
# The vector returns: on PE each is its OWN path (the retptr receive, the 32-byte receive, the
# assignment, the return of a vector call); elsewhere PARSE_FNCALL.
cat > "$T/fx/vec.cyr" <<'EOF'
#deprecated("v old")
fn old_v(a: f64v2): f64v2 { return a; }
#deprecated("v4 old")
fn old_v4(a: f64v4): f64v4 { return a; }
fn fwd(a: f64v2): f64v2 {
    return old_v(a);   #W
}
fn main() {
    var a: f64v2;
    var b: f64v4;
    var v: f64v2 = old_v(a);   #W
    var w: f64v4 = old_v4(b);   #W
    v = old_v(a);   #W
    var x: f64v2 = fwd(v);
    return 0;
}
var rc = main();
syscall(60, rc);
EOF

NFX=0
NROWS=0
for fx in "$T"/fx/*.cyr; do
    n=$(basename "$fx" .cyr)
    NFX=$((NFX + 1))
    if [ -f "$T/fx/$n.lines" ]; then sort -n "$T/fx/$n.lines" > "$T/want.$n"
    else grep -n '#W' "$fx" | cut -d: -f1 | sort -n > "$T/want.$n"; fi
    NROWS=$((NROWS + $(wc -l < "$T/want.$n")))
    # The twin swaps the attribute for an `#assert` carrying the SAME string literal: the lexer's
    # string pool is emitted whole, so the message text is in .rodata either way; a comment would
    # drop it from the pool and move every byte after it, which is not what this row measures.
    sed 's/^#deprecated(\(.*\))$/#assert 1, \1;/' "$fx" > "$T/strip.$n.cyr"
    grep -q '^#deprecated' "$T/strip.$n.cyr" && { _bad "$n: the stripped twin still carries an attribute"; continue; }
    for c in $COMPILERS; do
        if [ "$c" = main_cx ] && [ "$n" = pair ]; then continue; fi
        "$T/$c" < "$fx" > "$T/a.bin" 2> "$T/a.err"; arc=$?
        "$T/$c" < "$T/strip.$n.cyr" > "$T/s.bin" 2> "$T/s.err"; src=$?
        if [ "$arc" -ne 0 ] || [ ! -s "$T/a.bin" ]; then
            _bad "$n [$c]: the fixture did not compile (rc $arc)"; sed 's/^/      /' "$T/a.err" | head -3; continue
        fi
        sed -n "s/^warning:<source>:\([0-9]*\):[0-9]*: '[^']*' is deprecated: .*/\1/p" "$T/a.err" | sort -n > "$T/got"
        if cmp -s "$T/got" "$T/want.$n"; then _ok
        else
            _bad "$n [$c]: deprecation warnings on lines {$(tr '\n' ' ' < "$T/got")} — want exactly one on each of {$(tr '\n' ' ' < "$T/want.$n")}"
            grep 'is deprecated' "$T/a.err" | sed 's/^/      /' | head -12
        fi
        if [ "$src" -ne 0 ] || grep -q 'is deprecated' "$T/s.err"; then _bad "$n [$c]: the attribute-free twin failed (rc $src) or warned"
        elif cmp -s "$T/a.bin" "$T/s.bin"; then _ok
        else _bad "$n [$c]: the binary CHANGED with the attribute — #deprecated must be diagnostics only"
        fi
    done
done

# ── the filed repro verbatim, columns included (x86) ───────────────────────────────────────────
"$T/x86" < "$T/fx/filed.cyr" > "$T/a.bin" 2> "$T/a.err"
grep 'is deprecated' "$T/a.err" > "$T/got"
cat > "$T/want" <<'EOF'
warning:<source>:3:18: 'old_f' is deprecated: use new_f
warning:<source>:6:19: 'old_f' is deprecated: use new_f
warning:<source>:14:18: 'old_f' is deprecated: use new_f
warning:<source>:17:22: 'old_f' is deprecated: use new_f
warning:<source>:21:19: 'old_f' is deprecated: use new_f
EOF
if cmp -s "$T/got" "$T/want"; then _ok
else _bad "filed repro: the five reports are not 3:18 6:19 14:18 17:22 21:19 (the tail call is 14:18, not 15:1)"; sed 's/^/      /' "$T/got"
fi

# ── the PE-only vector paths are the ones that fire on PE ──────────────────────────────────────
for c in pe_main main_win; do
    "$T/$c" < "$T/fx/vec.cyr" > "$T/a.bin" 2> "$T/a.err"
    got=$(sed -n "s/^warning:<source>:\([0-9]*:[0-9]*\): .*is deprecated.*/\1/p" "$T/a.err" | sort | tr '\n' ' ')
    if [ "$got" = "11:20 12:20 13:9 6:12 " ]; then _ok
    else _bad "vec [$c]: want the PE vector paths at 11:20 12:20 13:9 6:12 (each names the callee), got {$got}"
    fi
done
"$T/x86" < "$T/fx/vec.cyr" > "$T/a.bin" 2> "$T/a.err"
got=$(sed -n "s/^warning:<source>:\([0-9]*:[0-9]*\): .*is deprecated.*/\1/p" "$T/a.err" | sort | tr '\n' ' ')
if [ "$got" = "11:26 12:27 13:15 6:18 " ]; then _ok
else _bad "vec [x86]: want PARSE_FNCALL's 11:26 12:27 13:15 6:18, got {$got}"
fi

# ── an `async fn` (CYRIUS_ASYNC=1, x86): pass 2 gives the attribute to the BODY fn `old_a$impl`,
# which is reached only by pointer, so `old_a(..)` / `await old_a(..)` were silent; pass 1 gives it
# to `old_a`, the name callers use. One warning per call, binary unchanged. ────────────────────────
cat > "$T/async.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/async.cyr"
fn early() { var f = old_a(1); return 0; }
#deprecated("a old")
async fn old_a(x) { return x + 1; }
async fn user(x) {
    var r = await old_a(x);
    return r;
}
fn main() {
    var f = user(2);
    return early();
}
alloc_init();
var rc = main();
syscall(60, rc);
EOF
sed 's/^#deprecated(\(.*\))$/#assert 1, \1;/' "$T/async.cyr" > "$T/async_twin.cyr"
CYRIUS_ASYNC=1 "$T/x86" < "$T/async.cyr" > "$T/a.bin" 2> "$T/a.err"; arc=$?
CYRIUS_ASYNC=1 "$T/x86" < "$T/async_twin.cyr" > "$T/s.bin" 2> "$T/s.err"
got=$(sed -n "s/^warning:<source>:\([0-9]*:[0-9]*\): 'old_a' is deprecated: a old$/\1/p" "$T/a.err" | tr '\n' ' ')
if [ "$arc" -eq 0 ] && [ "$got" = "3:28 7:25 " ] && [ "$(grep -c 'is deprecated' "$T/a.err")" -eq 2 ]; then _ok
else _bad "async: want 'old_a' warned at 3:28 and 7:25 only (rc $arc), got {$got}"; grep 'is deprecated' "$T/a.err" | sed 's/^/      /'
fi
if [ -s "$T/a.bin" ] && cmp -s "$T/a.bin" "$T/s.bin" && ! grep -q 'is deprecated' "$T/s.err"; then _ok
else _bad "async: the binary changed with the attribute, or the twin warned"
fi

# ── a bare #deprecated is still refused by name, before and after the first statement ──────────
printf '#deprecated\nfn f(a): i64 { return a; }\nvar r = f(1);\nsyscall(60, r);\n' > "$T/bare_pre.cyr"
printf 'var z = 0;\nz = 1;\n#deprecated\nfn f(a): i64 { return a; }\nvar r = f(1);\nsyscall(60, r);\n' > "$T/bare_post.cyr"
for b in bare_pre bare_post; do
    "$T/x86" < "$T/$b.cyr" > "$T/a.bin" 2> "$T/a.err"; rc=$?
    if [ "$rc" -ne 0 ] && grep -q '#deprecated needs a message string' "$T/a.err" && ! grep -q 'is deprecated' "$T/a.err"; then _ok
    else _bad "$b: a bare #deprecated was not refused by name (rc $rc)"
    fi
done

# ── floor ──────────────────────────────────────────────────────────────────────────────────────
[ "$NFX" -ge 9 ] || _bad "only $NFX fixtures ran (floor 9) — an empty fixture set must not read green"
[ "$NROWS" -ge 32 ] || _bad "only $NROWS marked call sites (floor 32)"

if [ "$fail" -ne 0 ]; then
    echo "FAIL deprecated_every_call_path: $fail failed, $pass passed"
    exit 1
fi
echo "PASS deprecated_every_call_path: $pass rows — $NFX fixtures, $NROWS call sites, each warned exactly once on its own line by [$COMPILERS], binaries identical without the attribute; the filed repro verbatim (tail 14:18); the PE vector paths; an async fn; bare #deprecated refused"
exit 0
