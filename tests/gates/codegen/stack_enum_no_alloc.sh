#!/bin/sh
# stack_enum_no_alloc.sh — v6.5.55. `enum N: stack` constructs payload variants with NO
# allocation, and the boxed form is untouched.
#
# WHY. The payload-variant constructor emitted an unconditional `alloc(8 + arity*8)`, so every
# `Ok(v)` / `Err(e)` / `Some(v)` cost 16 bytes of never-reclaimed global bump allocator —
# measured at 1600 B per 100 `sock_send` calls, unbounded for a long-running server. A stack
# enum hands back (tag, payload) in the multi-return register pair instead.
#
# ⭐ EVERY ZERO-GROWTH ASSERTION IS PAIRED WITH A NON-ZERO CONTROL. Axis 2 asserts a plain
# `enum` still grows by exactly 16. Without it this gate passes on any machine or build where
# the allocator happens not to move, which is how a zero-assertion quietly becomes vacuous.
#
# ⭐ AXIS 3 IS THE ONE THAT MATTERS. v6.5.15 already tried to stop boxing — by relocating the
# box to a per-call-site anonymous global — and shipped a compiler that "reported a failed file
# open as SUCCESS in a retaining loop". It passed every gate of its day. Axis 3 is that exact
# shape: N values built at ONE call site, all live simultaneously, each checked. The value form
# passes it by construction (each binding is a copy of two registers, so nothing aliases and
# there is no storage to dangle into) — but the gate pins the PROPERTY, so any future
# representation that reintroduces sharing fails here rather than in a consumer.
#
# ⚠ Builds a compiler FROM SOURCE and measures what it emits: the behaviour under test lives in
# the compiler being built, not in build/cycc, so a source revert flips this gate RED.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL stack_enum_no_alloc: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL stack_enum_no_alloc: stage1 build failed"; exit 1; }
chmod +x "$T/cc"

cat > "$T/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
enum S: stack { SOk(v); SErr(e); }
enum B { BOk(v); }
fn mk(n): i64 { return SOk(n); }
fn retain(): i64 {
    var tg: i64[16]; var vl: i64[16];
    var i = 0;
    while (i < 16) { var t, v = mk(100 + i); store64(&tg + i * 8, t); store64(&vl + i * 8, v); i = i + 1; }
    var bad = 0; i = 0;
    while (i < 16) {
        if (load64(&tg + i * 8) != 0) { bad = bad + 1; }
        if (load64(&vl + i * 8) != 100 + i) { bad = bad + 1; }
        i = i + 1;
    }
    return bad;
}
fn main(): i64 {
    var a0 = alloc_used();
    var t1, v1 = SOk(41);
    var t2, v2 = SErr(0 - 7);
    var stack_grew = alloc_used() - a0;
    var b0 = alloc_used();
    var bx = BOk(41);
    var boxed_grew = alloc_used() - b0;
    var r0 = alloc_used();
    var bad = retain();
    var retain_grew = alloc_used() - r0;
    var code = 0;
    if (stack_grew != 0)  { code = code + 1; }
    if (boxed_grew != 16) { code = code + 2; }
    if (bad != 0)         { code = code + 4; }
    if (retain_grew != 0) { code = code + 8; }
    if (t1 != 0)          { code = code + 16; }
    if (v1 != 41)         { code = code + 32; }
    if (t2 != 1)          { code = code + 64; }
    if (v2 != 0 - 7)      { code = code + 128; }
    syscall(60, code, 0, 0, 0, 0);
    return 0;
}
EOF
"$T/cc" < "$T/p.cyr" > "$T/p" 2>"$T/pe" || { echo "FAIL stack_enum_no_alloc: probe did not compile"; sed -n 1,3p "$T/pe"; exit 1; }
chmod +x "$T/p"
"$T/p"; C=$?
[ $C -eq 0 ] && OK=1 || OK=0
if [ $OK -eq 0 ]; then
  echo "FAIL stack_enum_no_alloc: probe exit $C (bit1 stack allocated, bit2 boxed control not 16 B,"
  echo "  bit4 retained values corrupted, bit8 retaining loop allocated, bits16+ wrong tag/payload)"
  exit 1
fi

# axis 4 — a stack variant that cannot fit the pair must be REJECTED, not silently truncated.
printf 'enum Bad: stack { P(a, b); }\nfn main(): i64 { return 0; }\n' > "$T/bad.cyr"
if "$T/cc" < "$T/bad.cyr" > /dev/null 2>"$T/bad.err"; then
  echo "FAIL stack_enum_no_alloc: arity-2 stack variant COMPILED — it would silently drop a field"
  exit 1
fi
grep -q "exactly 1 field" "$T/bad.err" || { echo "FAIL stack_enum_no_alloc: arity-2 rejected without the explaining message"; sed -n 1,2p "$T/bad.err"; exit 1; }

echo "PASS stack_enum_no_alloc: stack enum 0 B (boxed control 16 B), 16 retained values intact, arity-2 rejected"
exit 0
