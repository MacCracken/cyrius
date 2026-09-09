#!/bin/sh
# Gate: a SIMD intrinsic's operand stash slots are reserved BEFORE its arguments are parsed.
#
# ⛔ THE DEFECT (filed 2026-09-09 by hisab, fixed v6.6.2). Every f64v_*/f32v_*/iv_* handler in
# parse_expr.cyr took `var vbase = GFLC(S);` and did not raise GFLC until AFTER every argument
# had been parsed. So while an argument was being parsed, GFLC still pointed AT the intrinsic's
# own destination slot. Any argument that allocates a frame local therefore bound it there — the
# inline replay's `var saved_flc = GFLC(S);` (parse_fn.cyr) returned `vbase` itself and laid its
# parameter copy over the destination pointer. Measured on the filed repro:
#
#     mov  -0x30(%rbp),%rax ; mov %rax,-0x50(%rbp)   <- dst stashed at vbase
#     mov  -0x38(%rbp),%rax ; mov %rax,-0x58(%rbp)   <- src stashed at vbase+1
#     mov  -0x40(%rbp),%rax ; mov %rax,-0x50(%rbp)   <- ⛔ REPLAY OVERWRITES vbase
#     ...
#     mov  -0x50(%rbp),%rdx ; movupd %xmm0,(%rdx,%rsi,8)   <- stores through the wrong pointer
#
# ⭐ TWO FAILURE MODES, AND THE QUIET ONE IS WORSE. With the register picker ON the repro
# SIGSEGVs; with `CYRIUS_REGALLOC_PICKER_CAP=0` it exits 0 and writes the result into the
# argument object instead — silent wrong code, and a silent out-of-bounds write wherever the
# clobbered slot happens to hold a mapped address. Both are pinned below.
#
# ⭐ NOT A 6.5.71 REGRESSION, THOUGH IT WAS FILED AS ONE. 6.5.71 only routed #derive(accessors)
# getters through the inline-replay path; before it the getter was a real CALL, and the call
# incidentally forced the spill the expansion had been silently depending on. The same shape is
# reachable via `callptr` since 6.0.70 and `#inline` since 6.5.63, so both the version range and
# the "derive" framing in the filing understate it. Axis 3 covers the other admission routes.
#
# ⭐ AXIS 1 COUNTS STORES, NOT VALUES, and that is deliberate. A value assertion cannot see a
# spill that was SKIPPED — only one that produced a wrong number. Exactly one store into the
# destination slot is correct: zero means the picker promoted it to a register the kernel does
# not read, two means the collision is back.
#
# ⚠ THE FIXPOINT AND SEED-DERIVE ARE BLIND TO THIS. cycc's own source contains zero call sites
# of these intrinsics (every grep hit is a comment), so the compiler is byte-identical either
# way. Do not accept "cycc self-hosts" as evidence for this fix. The companion
# tests/tcyr/crossos/simd_intrinsic_inline_arg.tcyr carries it to real ecb/ach/cass/pi.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC=${CYCC_BIN:-"$ROOT/build/cycc"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: simd_intrinsic_operand_slots: $1"; exit 1; }
[ -x "$CYCC" ] || fail "no cycc at $CYCC"
cd "$ROOT"

HDR='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/math.cyr"
'

# Build + run a probe; echo its exit code. Probes return 0 on success, non-zero on the defect.
_run() {
    _src=$1; _pick=$2
    printf '%s' "$HDR" > "$WORK/p.cyr"; cat "$_src" >> "$WORK/p.cyr"
    "$CYCC" < "$WORK/p.cyr" > "$WORK/p" 2>"$WORK/p.err" || { echo 255; return; }
    chmod +x "$WORK/p"
    set +e
    if [ "$_pick" = "off" ]; then CYRIUS_REGALLOC_PICKER_CAP=0 "$WORK/p" >/dev/null 2>&1
    else "$WORK/p" >/dev/null 2>&1; fi
    _rc=$?
    set -e
    echo "$_rc"
}

# ── the shared probe body: dst must be written, and the ARGUMENT OBJECT must be untouched ──
_mkprobe() {   # $1 = out file, $2 = the scalar-argument expression
cat > "$1" <<EOF
#derive(accessors)
struct V4 { x; y; z; w; }
#inline
fn inl_x(p) { return load64(p + 0); }
fn scale_it(r, m, v) {
    var tmp = alloc(32);
    f64v_scale(r, m + 0, $2, 4);
    return r;
}
fn main(): i64 {
    alloc_init();
    var m = alloc(32);
    store64(m + 0, f64_from(1)); store64(m + 8, f64_from(2));
    store64(m + 16, f64_from(3)); store64(m + 24, f64_from(4));
    var v = alloc(32);
    V4_set_x(v, f64_from(2)); V4_set_y(v, f64_from(9));
    V4_set_z(v, f64_from(9)); V4_set_w(v, f64_from(9));
    var r = alloc(32);
    store64(r + 0, 0); store64(r + 8, 0); store64(r + 16, 0); store64(r + 24, 0);
    scale_it(r, m, v);
    var i = 0;
    while (i < 4) {
        if (f64_to(load64(r + i * 8)) != (i + 1) * 2) { return 10 + i; }
        i = i + 1;
    }
    var j = 0;
    while (j < 4) {
        if (f64_to(load64(m + j * 8)) != j + 1) { return 20 + j; }
        j = j + 1;
    }
    if (f64_to(load64(v + 0)) != 2) { return 30; }
    if (f64_to(load64(v + 8)) != 9) { return 31; }
    return 0;
}
var rc = main();
sys_exit_group(rc);
EOF
}

# ── axis 1: EXACTLY ONE store into the destination operand slot ─────────────────────────
_mkprobe "$WORK/a1.cyr" "V4_x(v)"
printf '%s' "$HDR" > "$WORK/p1.cyr"; cat "$WORK/a1.cyr" >> "$WORK/p1.cyr"
"$CYCC" < "$WORK/p1.cyr" > "$WORK/p1" 2>/dev/null || fail "axis 1: probe did not compile"
objdump -d "$WORK/p1" > "$WORK/dis.txt" 2>/dev/null || fail "axis 1: objdump unavailable"
# The kernel's destination read is the `mov -0xNN(%rbp),%rdx` directly above `movupd %xmm0,(%rdx`.
DSTDISP=$(grep -B1 'movupd %xmm0,(%rdx' "$WORK/dis.txt" \
          | grep -oE 'mov +-0x[0-9a-f]+\(%rbp\),%rdx' | grep -oE '\-0x[0-9a-f]+' | head -1)
[ -n "$DSTDISP" ] || fail "axis 1: could not locate the destination slot read in the disassembly"
# ⚠ SCOPED TO THE ENCLOSING FUNCTION. cycc emits a single `<.text>` symbol, so a whole-binary
# count is meaningless — the same rbp displacement recurs in every other function (measured 20
# hits binary-wide for a slot that is written once where it matters). Bound the window by the
# `push %rbp` above the store and the first `ret` below it.
NW=$(awk -v d="$DSTDISP" '
  { line[NR]=$0 } /movupd %xmm0,\(%rdx/ { if (!hit) hit=NR }
  END {
    if (!hit) { print "NOHIT"; exit }
    for (i=hit; i>0; i--) if (line[i] ~ /push +%rbp/) { s=i; break }
    for (i=hit; i<=NR; i++) if (line[i] ~ /\tret/) { e=i; break }
    n=0
    for (i=s; i<=e; i++) if (line[i] ~ ("mov +%r[a-z0-9]+," d "\\(%rbp\\)")) n++
    print n
  }' "$WORK/dis.txt")
[ "$NW" != "NOHIT" ] || fail "axis 1: no packed store found — the intrinsic did not lower"
[ "$NW" -eq 1 ] || fail "axis 1: destination slot ${DSTDISP}(%rbp) has $NW stores in its function, expected exactly 1 (0 = promoted away, 2 = the operand-slot collision is back)"

# ── axis 2: VALUES, under BOTH picker settings ──────────────────────────────────────────
# picker ON was the SIGSEGV; picker OFF was the silent wrong write. Both must be correct.
RC=$(_run "$WORK/a1.cyr" on)
[ "$RC" -eq 0 ] || fail "axis 2a: derive getter, picker ON -> rc $RC (139 = the SIGSEGV; 10-13 = dst unwritten; 20-23/30-31 = argument object corrupted)"
RC=$(_run "$WORK/a1.cyr" off)
[ "$RC" -eq 0 ] || fail "axis 2b: derive getter, picker OFF -> rc $RC (the SILENT mode)"

# ── axis 3: the other admission routes into the inline-replay path ──────────────────────
# The filing named #derive only. #inline reaches the same path (6.5.63) and so does a plain
# nested call once inlined; a fix that special-cases derive would pass axis 2 and fail here.
_mkprobe "$WORK/a3.cyr" "inl_x(v)"
RC=$(_run "$WORK/a3.cyr" on)
[ "$RC" -eq 0 ] || fail "axis 3a: #inline fn as the scalar argument -> rc $RC"
RC=$(_run "$WORK/a3.cyr" off)
[ "$RC" -eq 0 ] || fail "axis 3b: #inline fn as the scalar argument, picker OFF -> rc $RC"

# ── axis 4: ARGUMENT POSITION 1 and 2, not just the last one ────────────────────────────
# The collision is with whichever argument allocates a frame local, and the destination is
# argument 1 — a fix that only reserved the LAST slot would pass everything above.
cat > "$WORK/a4.cyr" <<'EOF'
#derive(accessors)
struct P { a; b; }
fn pick(m, p) {
    var tmp = alloc(32);
    var r = alloc(32);
    store64(r + 0, 0); store64(r + 8, 0); store64(r + 16, 0); store64(r + 24, 0);
    f64v_scale(r, m + P_a(p), f64_from(3), 4);
    return r;
}
fn main(): i64 {
    alloc_init();
    var m = alloc(32);
    store64(m + 0, f64_from(1)); store64(m + 8, f64_from(2));
    store64(m + 16, f64_from(3)); store64(m + 24, f64_from(4));
    var p = alloc(16);
    P_set_a(p, 0); P_set_b(p, 7);
    var r = pick(m, p);
    var i = 0;
    while (i < 4) {
        if (f64_to(load64(r + i * 8)) != (i + 1) * 3) { return 40 + i; }
        i = i + 1;
    }
    if (load64(p + 8) != 7) { return 50; }
    return 0;
}
var rc = main();
sys_exit_group(rc);
EOF
RC=$(_run "$WORK/a4.cyr" on)
[ "$RC" -eq 0 ] || fail "axis 4: inline-replay in argument position 2 -> rc $RC"

# ── axis 5 (ANTI-VACUOUS): the inlining must actually be happening ──────────────────────
# If #derive stopped inlining, every axis above passes for the wrong reason — the getter would
# be a real call again, which is the 6.5.70 behaviour this bug hid behind. 6.5.71's own gate
# counts callq for exactly this reason.
NCALL=$(grep -c 'call.*<V4_x>' "$WORK/dis.txt" || true)
[ "$NCALL" -eq 0 ] || fail "axis 5: V4_x is still a real call ($NCALL) — the probe is not exercising the inline-replay path, so axes 1-4 prove nothing"

echo "PASS: simd_intrinsic_operand_slots (5 axes: store-count, values-both-pickers, admission-routes, arg-position, anti-vacuous-inlining)"
