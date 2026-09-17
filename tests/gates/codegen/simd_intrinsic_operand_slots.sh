#!/bin/sh
# Gate: every SIMD batch intrinsic's operand slots are WRITTEN before its kernel reads them —
# neither the argument parse (6.6.2) nor the register picker (6.6.5) may take one away.
#
# ⛔ DEFECT 1 (filed 2026-09-09 by hisab, fixed v6.6.2). Every f64v_*/f32v_*/iv_* handler in
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
# Axes 1-5 pin it. Filed as a 6.5.71 derive regression; it is neither (reachable via `callptr`
# since 6.0.70 and `#inline` since 6.5.63). Its picker-ON SIGSEGV was DEFECT 2 below.
#
# ⛔ DEFECT 2 (filed 2026-09-14 by hisab, fixed 6.6.5 —
# docs/development/issues/archived/2026-09-14-hisab-simd-dst-slot-regalloc-picker.md).
# The register picker in `_PARSE_FN_DEF_IMPL` is three byte-pattern stages, and they disagreed
# about which frame references it can rewrite. The use scan counted `48 8B 85` / `48 89 85`
# (rax moves) only; the unsafe scan exempted any `48 8B` / `48 89` WITHOUT reading the ModRM reg
# field; the patch pass rewrote exact 0x85 only. Every batch kernel reads its operands with
# `mov rdx,[rbp+disp32]` (48 8B 95, `_EMIT_LOAD_RDX_FROM_LOCAL`, 19 emitters) — a form the unsafe
# scan waved through and the patch pass never touched. So an operand slot with two rax
# references was promoted, its stash became `mov r13,rax`, and the kernel read a slot nothing
# wrote. The second rax reference comes from LEGITIMATE slot reuse: a nested inline replay
# (`sz(t, gz(t) + 1)`) takes a param slot, parse_fn.cyr lowers GFLC back after the arguments,
# and the next intrinsic's `_SIMD_RESERVE` reuses that slot. No #derive, setter, getter or shared
# object is needed; a `var` declared between the two statements hides it. Filed repro (column 3
# of M lost): stock printed `1 4 3`, exit 1 — SILENT; a stdlib-free copy and hisab's tree
# SIGSEGV. Every x86 target that runs the picker (ELF, PE, x86 Mach-O, agnos). The fix gives the
# three stages ONE predicate, `_ra_plain_slot_mov`.
#
# ⭐ AXIS 0 IS A REPAIR OF THIS GATE. The 6.6.2 `_run` set CYRIUS_REGALLOC_PICKER_CAP=0 on the
# PROBE BINARY, which never reads it — the knob is read by cycc at COMPILE time (main.cyr). Axes
# 2b and 3b therefore re-ran the picker-ON binary and never compiled a picker-off build: against
# the 6.6.1 compiler the old "off" run returned 139 (the ON crash) while a real picker-off build
# returns 10 (the silent dst-unwritten mode those axes claimed to pin). The archived 6.6.2 issue's
# "Both are now pinned" was false for the silent mode until this repair.
#
# ⚠ THE FIXPOINT AND SEED-DERIVE ARE BLIND TO BOTH DEFECTS. cycc's own source contains zero call
# sites of these intrinsics, so the compiler is byte-identical either way (6.6.5: the fixed cycc
# compiles the UNMODIFIED source to the committed binary). "cycc self-hosts" is not evidence here.
# The companion tests/tcyr/crossos/simd_intrinsic_inline_arg.tcyr carries both shapes to real
# ecb/ach/cass/pi — ach (x86 Mach-O) and cass (PE) are the picker targets.
#
# AXES
#   0  the "off" builds are really picker-off builds (ON and OFF bytes must differ)
#   1  exactly one store into the destination slot                          (6.6.2)
#   2  values, derive getter as the scalar argument, picker ON and OFF      (6.6.2)
#   3  values, #inline fn as the scalar argument, picker ON and OFF         (6.6.2)
#   4  inline replay in argument position 2                                 (6.6.2)
#   5  anti-vacuous: V4_x really is inlined                                 (6.6.2)
#   A  22 intrinsic spellings (all 19 batch kernels), a nested inline replay in an EARLIER
#      statement, then the intrinsic: exact lane values, picker ON and OFF (compile-time knob),
#      plus 2 rows for the other two admission routes the issue documents — a replay that is NOT
#      a setter (`q = add2(gz(t), 1)`) and one whose getter and setter are on DIFFERENT objects.
#      Both reproduce against 6.6.4 (rc 139); until 6.6.5 every probe here was the same-object
#      setter-of-getter, so that documented breadth rested on the fix being shape-agnostic
#   B  the filed repro, verbatim — the spec
#   C  byte-level oracle, INDEPENDENT of the picker's own byte scan: objdump decodes both builds,
#      and every frame slot with any reference other than a plain `mov %rax <-> slot` in the OFF
#      build must keep EVERY reference in the ON build (i.e. was never promoted)
#   D  anti-vacuous: the OFF build really has a slot with >= 2 rax moves AND a kernel rdx read (the
#      shared slot), and the picker really engaged in that function (ON has fewer frame refs).
#      Without it, a change that stopped releasing the replay's slot would make A and C pass while
#      the classifier hole stayed open
#   E  C + D on PE (GNU objdump) and x86 Mach-O (llvm-objdump, normalised) builds — SKIPs loudly
#      when the decoder is missing
#   F  census: in every function carrying the regalloc frame, no rbp-disp8 and no rbp-based SIB
#      reference to a local slot. The classifier only sees [rbp+disp32]; a disp8 operand read would
#      be invisible to all three stages and reopen the hole. Only ASM_PARAM_LOAD emits disp8 and
#      inline-asm fns never enable the picker — measured 0 violations over the whole x86 corpus
#      (tests/tcyr + programs + benches + fuzz) at 6.6.5. Its floors are DERIVED per binary (the
#      regalloc frames must be >= 3/4 of that binary's functions and carry >= 1 local disp32 ref
#      each) and the aggregate is derived from the row table — a hand-set total let the census
#      halve unnoticed, and a census that stops censusing still reports 0 violations
#   G  no x86 byte-pattern pass may scan cx bytecode. A SOURCE assertion on purpose: the cx driver
#      has a stub `_read_env`, so every runtime knob (picker cap, frametrim, regalloc dump) is
#      inert there and a check built on one cannot fail. See the axis itself
#
# MUTATION LEDGER (6.6.5; each mutant run against a scratch copy of this gate — fail-fast for
# RED, and a keep-going copy to count every axis that fires — then removed; the gate is GREEN):
#   M1 the pre-fix compiler (6.6.4 build/cycc)      -> A x22 (rc 139), B x2 (`1 4 3`, rc 1),
#                                                      C x69 (ELF + PE + Mach-O) red; D green
#   M2 exemption reads the reg field on STORES only  -> identical to M1 (a load-side hole is the bug)
#   M3 `_ra_plain_slot_mov` accepts any reg field     -> 1, 2a, 3a, 4, A x22, B, C x69 red (the patch
#                                                      pass rewrites the kernel's rdx read into rax)
#   M4 the replay slot is never released (parse_fn.cyr `SFLC(S, saved_flc + _ptot)` made
#      raise-only)                                   -> ONLY D red (x69); A, B, C all green — the
#                                                      reason D exists
#   M5 `_EMIT_LOAD_RDX_FROM_LOCAL` emits disp8 when the disp fits
#                                                    -> F x23, A x22, C x66 red (the invisible read)
#   M6 this gate with `_build` ignoring "off" (the 6.6.2 placement's effect) -> 0 red
#   M7 one expected lane edited (f64v_add `3 4` -> `3 5`) -> A red, rc 11 on BOTH builds
#   M8 the 6.6.1 compiler (defect 1 still present)   -> 1, 2a, 2b, 3a, 3b, 4, A, B, C red; 2b and 3b
#                                                      now report rc 10, the silent mode — the 6.6.2
#                                                      gate reported 139 there, the ON binary's crash
#   M9 a "compiler" that exits 0 and writes nothing  -> 0 red: "probe did not compile"
#  M10 the pre-fix compiler on the two NEW rows      -> both rc 139 (the non-setter and
#                                                      different-object replays are real triggers,
#                                                      not restatements of the setter one)
#  M11 the census signature matched in 1/2, then 2/3, of each binary's functions
#                                                    -> F red both times (the hand-set `>= 200`
#                                                      total this replaced passed the 2/3 mutant)
#  M12 the `nonsetter` shape field dropped from its row -> A red ("1 rows carry an explicit shape")
#  M13 one of the four `bp_x86` gates reverted to `_AARCH64_BACKEND == 0`
#                                                    -> G red (3 of 4)
#  M14 `bp_x86` defined without `_TARGET_CX`         -> G red
#  M15 the picker's enable test without `_TARGET_CX == 0` -> G red
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC=${CYCC_BIN:-"$ROOT/build/cycc"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: simd_intrinsic_operand_slots: $1"; exit 1; }
[ -x "$CYCC" ] || fail "no cycc at $CYCC"
command -v objdump >/dev/null 2>&1 || fail "objdump unavailable — axes 1, C, D and F need a real decoder"
cd "$ROOT"

HDR='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/math.cyr"
'

# _build MODE SRC OUT [VAR=VAL ...] — compile; MODE=off sets the picker knob ON CYCC (axis 0).
# Fails on a non-zero exit AND on an empty output (an empty file "runs" and exits 0).
_build() {
    _bm=$1; _bs=$2; _bo=$3; shift 3
    if [ "$_bm" = "off" ]; then set -- CYRIUS_REGALLOC_PICKER_CAP=0 "$@"; fi
    env "$@" "$CYCC" < "$_bs" > "$_bo" 2> "$_bo.err" || return 1
    [ -s "$_bo" ] || return 1
    chmod +x "$_bo"
}

# Build + run a stdlib probe; echo its exit code (255 = did not compile).
_run() {
    _src=$1; _pick=$2
    printf '%s' "$HDR" > "$WORK/p.cyr"; cat "$_src" >> "$WORK/p.cyr"
    _build "$_pick" "$WORK/p.cyr" "$WORK/p" || { echo 255; return; }
    set +e
    "$WORK/p" >/dev/null 2>&1
    _rc=$?
    set -e
    echo "$_rc"
}

# ── the decoders (portable awk: no gawk-only strtonum, so mawk runners get the same answer) ──
cat > "$WORK/refs.awk" <<'AWK'
# per (function ordinal, rbp disp): total refs, plain rax moves, kernel rdx reads, non-plain refs
function hexval(s,   i, c, v) { v = 0; for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)); if (c == 0) return -1; v = v * 16 + c - 1 } return v }
/\tpush +%rbp *$/ { fn++; next }
fn > 0 {
  n = split($0, f, "\t"); ins = f[n]; gsub(/ +/, " ", ins); sub(/ $/, "", ins)
  s = ins
  while (match(s, /-0x[0-9a-f]+\(%rbp\)/)) {
    d = substr(s, RSTART, RLENGTH - 6)
    if (hexval(substr(d, 4)) >= lo) {
      k = fn " " d; tot[k]++
      if (ins == "mov %rax," d "(%rbp)" || ins == "mov " d "(%rbp),%rax") pl[k]++
      else if (ins == "mov " d "(%rbp),%rdx") rx[k]++
    }
    s = substr(s, RSTART + RLENGTH)
  }
}
END { for (k in tot) print k, tot[k], pl[k] + 0, rx[k] + 0, tot[k] - pl[k] }
AWK
cat > "$WORK/census.awk" <<'AWK'
# every local-slot rbp reference in a regalloc-frame fn is disp32; no rbp-based SIB at all
function hexval(s,   i, c, v) { v = 0; for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)); if (c == 0) return -1; v = v * 16 + c - 1 } return v }
/\tpush +%rbp *$/ { fn++; k = 0; ra = 0; next }
fn > 0 {
  n = split($0, f, "\t"); ins = f[n]; by = f[2]; gsub(/ +/, " ", ins); sub(/ $/, "", ins)
  k++
  # The regalloc frame saves rbx at -0x8 as its third instruction; an inline-asm fn homes rdi there.
  if (k <= 3 && ins == "mov %rbx,-0x8(%rbp)") { ra = 1; nra++ }
  if (ra == 0) next
  if (ins ~ /\(%rbp,/) { print "  SIB: " $0; bad++ }
  s = ins
  while (match(s, /-0x[0-9a-f]+\(%rbp\)/)) {
    v = hexval(substr(s, RSTART + 3, RLENGTH - 9))
    if (v >= lo) {
      w = 4294967296 - v
      want = sprintf("%02x %02x %02x %02x", w % 256, int(w / 256) % 256, int(w / 65536) % 256, int(w / 16777216) % 256)
      if (index(by, want) == 0) { print "  DISP8: " $0; bad++ } else chk++
    }
    s = substr(s, RSTART + RLENGTH)
  }
}
END { print nra + 0, chk + 0, bad + 0, fn + 0 }
AWK
cat > "$WORK/norm_macho.awk" <<'AWK'
# llvm-objdump -d --no-show-raw-insn (x86 Mach-O) -> the GNU objdump shape the scripts above read
/^ *[0-9a-f]+:/ {
  addr = $1; rest = $0
  sub(/^ *[0-9a-f]+:[ \t]*/, "", rest); sub(/[ \t]*##.*$/, "", rest)
  t = index(rest, "\t")
  if (t > 0) { mn = substr(rest, 1, t - 1); ops = substr(rest, t + 1) } else { mn = rest; ops = "" }
  if (mn ~ /^(mov|push|pop|lea|sub|add|cmp|and|or|xor|test)q$/) mn = substr(mn, 1, length(mn) - 1)
  gsub(/, /, ",", ops)
  if (ops == "") print addr "\t\t" mn; else print addr "\t\t" mn " " ops
}
AWK

_dis() {   # _dis FORMAT BIN
    if [ "$1" = "macho" ]; then llvm-objdump -d --no-show-raw-insn "$2" | awk -f "$WORK/norm_macho.awk"
    else objdump -d --insn-width=16 "$2"; fi
}
# Local slots start below the regalloc save area: 5 callee-saved words on ELF/PE, 4 on x86 Mach-O.
_lo() { if [ "$1" = "macho" ]; then echo 40; else echo 48; fi; }

NC=0; ND=0
_axis_c() {   # _axis_c FORMAT ON OFF LABEL
    _dis "$1" "$2" | awk -v lo="$(_lo "$1")" -f "$WORK/refs.awk" | sort > "$WORK/c_on.refs"
    _dis "$1" "$3" | awk -v lo="$(_lo "$1")" -f "$WORK/refs.awk" | sort > "$WORK/c_off.refs"
    [ -s "$WORK/c_off.refs" ] || fail "axis C $4: the decoder saw no frame references at all"
    # The join is by FUNCTION ORDINAL (the n-th `push %rbp`), which is sound only while the picker
    # changes nothing but instructions — it rewrites moves and harvests NOPs, never adds or removes
    # a function. Check that, or a future change silently compares different functions to each
    # other. ⚠ Compare the PROLOGUE count, not the highest ordinal seen in the tables above: a
    # function whose every frame reference was legitimately promoted drops out of them entirely.
    _cf_on=$(_dis "$1" "$2" | grep -c '	push  *%rbp *$' || true)
    _cf_off=$(_dis "$1" "$3" | grep -c '	push  *%rbp *$' || true)
    [ "$_cf_on" = "$_cf_off" ] || fail "axis C $4: the picker-ON build has $_cf_on functions and the OFF build $_cf_off — the ordinal join is no longer sound, fix the join before trusting this axis"
    if ! awk 'NR == FNR { on[$1 " " $2] = $3; next }
              $6 > 0 { k = $1 " " $2; if (on[k] + 0 != $3) { printf "  PROMOTED fn#%s slot %s: OFF %d refs (%d non-plain), ON %d\n", $1, $2, $3, $6, on[k] + 0; bad++ } }
              END { exit (bad > 0) }' "$WORK/c_on.refs" "$WORK/c_off.refs" > "$WORK/c.out"; then
        cat "$WORK/c.out"
        fail "axis C $4: the picker promoted a frame slot that still has a reference it cannot rewrite — the kernel reads a slot nothing writes"
    fi
    NC=$((NC + 1))
}
_axis_d() {   # _axis_d FORMAT ON OFF LABEL
    _dis "$1" "$2" | awk -v lo="$(_lo "$1")" -f "$WORK/refs.awk" | sort > "$WORK/d_on.refs"
    _dis "$1" "$3" | awk -v lo="$(_lo "$1")" -f "$WORK/refs.awk" | sort > "$WORK/d_off.refs"
    awk 'NR == FNR { ont[$1] += $3; next }
         { offt[$1] += $3; if ($4 >= 2 && $5 >= 1) sh[$1] = 1 }
         END { for (f in sh) if (ont[f] + 0 < offt[f]) ok++; exit (ok == 0) }' \
        "$WORK/d_on.refs" "$WORK/d_off.refs" \
        || fail "axis D $4: no function has a slot shared by >= 2 rax moves and a kernel rdx read with the picker engaged — this probe no longer exercises the hole, so A/C prove nothing for it"
    ND=$((ND + 1))
}
CEN_FNS=0; CEN_REFS=0; CEN_N=0
# ⚠ EVERY FLOOR HERE IS DERIVED FROM THE BINARY ITSELF. The first version of this axis checked
# one hand-set total (`CEN_FNS -ge 200` against a measured 386) and never asserted CEN_REFS at
# all, so the census could have shrunk by half — the regalloc-frame signature below matching in
# only some functions — and still passed. The whole point of F is the disp32-only census, so a
# census that silently stops censusing is the one failure it must not survive. Two ratios, both
# read off the same objdump pass: regalloc frames are the OVERWHELMING majority of functions
# (measured 9/9 in the stdlib-free rows, 188/201 in the axis-B probe — the rest are inline-asm
# and #naked fns), and each one carries several local disp32 references (measured 4.8 and 6.3).
_axis_f() {   # _axis_f BIN LABEL (ELF only)
    set -- $(objdump -d --insn-width=16 "$1" | awk -v lo=48 -f "$WORK/census.awk" | tee "$WORK/f.out" | tail -1) "$2"
    # $1 regalloc fns   $2 local disp32 refs   $3 violations   $4 functions in the binary   $5 label
    if [ "$3" -ne 0 ]; then
        grep -E '^  (SIB|DISP8):' "$WORK/f.out" | sed -n 1,5p
        fail "axis F $5: $3 rbp-disp8/SIB reference(s) to a local slot in a regalloc fn — invisible to the picker's disp32 classifier"
    fi
    [ "$1" -ge 1 ] && [ "$2" -ge 1 ] || fail "axis F $5: census saw $1 regalloc fns / $2 local refs — the prologue signature moved and the census is vacuous"
    [ $(($1 * 4)) -ge $(("$4" * 3)) ] || fail "axis F $5: only $1 of the binary's $4 functions matched the regalloc-frame signature (\`mov %rbx,-0x8(%rbp)\` within 3 instructions of the prologue) — it has moved, and the census is measuring a fraction of the program while still reporting 0 violations"
    [ "$2" -ge "$1" ] || fail "axis F $5: $2 local disp32 references over $1 regalloc fns — fewer than one per function, so the reference matcher is no longer seeing the frame"
    CEN_FNS=$((CEN_FNS + $1)); CEN_REFS=$((CEN_REFS + $2)); CEN_N=$((CEN_N + 1))
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

# ── axis 0: the picker-OFF builds below really are picker-off builds ────────────────────
_mkprobe "$WORK/a1.cyr" "V4_x(v)"
printf '%s' "$HDR" > "$WORK/z.cyr"; cat "$WORK/a1.cyr" >> "$WORK/z.cyr"
_build on "$WORK/z.cyr" "$WORK/z_on" || fail "axis 0: probe did not compile (picker on)"
_build off "$WORK/z.cyr" "$WORK/z_off" || fail "axis 0: probe did not compile (picker off)"
if cmp -s "$WORK/z_on" "$WORK/z_off"; then
    fail "axis 0: the picker-OFF build is byte-identical to the picker-ON build — CYRIUS_REGALLOC_PICKER_CAP=0 is not reaching cycc, so every 'off' axis would re-test the ON binary (the 6.6.2 gate set it on the probe)"
fi

# ── axis 1: EXACTLY ONE store into the destination operand slot ─────────────────────────
printf '%s' "$HDR" > "$WORK/p1.cyr"; cat "$WORK/a1.cyr" >> "$WORK/p1.cyr"
_build on "$WORK/p1.cyr" "$WORK/p1" || fail "axis 1: probe did not compile"
objdump -d "$WORK/p1" > "$WORK/dis.txt" 2>/dev/null || fail "axis 1: objdump could not read the probe"
# The kernel's destination read is the `mov -0xNN(%rbp),%rdx` directly above `movupd %xmm0,(%rdx`.
DSTDISP=$(grep -B1 'movupd %xmm0,(%rdx' "$WORK/dis.txt" \
          | grep -oE 'mov +-0x[0-9a-f]+\(%rbp\),%rdx' | grep -oE '\-0x[0-9a-f]+' | sed -n 1p)
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
RC=$(_run "$WORK/a1.cyr" on)
[ "$RC" -eq 0 ] || fail "axis 2a: derive getter, picker ON -> rc $RC (139 = the SIGSEGV; 10-13 = dst unwritten; 20-23/30-31 = argument object corrupted; 255 = did not compile)"
RC=$(_run "$WORK/a1.cyr" off)
[ "$RC" -eq 0 ] || fail "axis 2b: derive getter, picker OFF -> rc $RC (the SILENT mode; 255 = did not compile)"

# ── axis 3: the other admission routes into the inline-replay path ──────────────────────
_mkprobe "$WORK/a3.cyr" "inl_x(v)"
RC=$(_run "$WORK/a3.cyr" on)
[ "$RC" -eq 0 ] || fail "axis 3a: #inline fn as the scalar argument -> rc $RC"
RC=$(_run "$WORK/a3.cyr" off)
[ "$RC" -eq 0 ] || fail "axis 3b: #inline fn as the scalar argument, picker OFF -> rc $RC"

# ── axis 4: ARGUMENT POSITION 1 and 2, not just the last one ────────────────────────────
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
NCALL=$(grep -c 'call.*<V4_x>' "$WORK/dis.txt" || true)
[ "$NCALL" -eq 0 ] || fail "axis 5: V4_x is still a real call ($NCALL) — the probe is not exercising the inline-replay path, so axes 1-4 prove nothing"

# ── axis A: every batch kernel, behind a nested replay in an EARLIER statement ──────────
# Stdlib-free (bump allocator over a global array) so axes C/D/F see only the probe's own code.
# name | cpu flags needed to EXECUTE | the call | the fill | result kind | expected lanes | shape.
# Expected values are integers worked by hand from the fill, not computed by any compiled code;
# the picker-off build is the second, independent oracle. The 7th field is the replay SHAPE and
# defaults to `setter` when absent (the 22 kernel rows); the last two rows pin the other two
# admission routes the issue documents.
_rows() {
cat <<'ROWS'
f64v_add|-|f64v_add(d, a, b, 2)|F64|d64|3 4
f64v_sub|-|f64v_sub(d, a, b, 2)|F64 put64(a, 0, 5); put64(a, 1, 7);|d64|3 5
f64v_div|-|f64v_div(d, a, b, 2)|F64 put64(a, 0, 6); put64(a, 1, 8);|d64|3 4
f64v_sqrt|-|f64v_sqrt(d, a, 2)|F64 put64(a, 0, 9); put64(a, 1, 16);|d64|3 4
f64v_abs|-|f64v_abs(d, a, 2)|F64 put64(a, 0, 0 - 3); put64(a, 1, 0 - 4);|d64|3 4
f64v_scale|-|f64v_scale(d, a, 4613937818241073152, 2)|F64|d64|3 6
f64v_fmadd|-|f64v_fmadd(d, a, b, c, 2)|F64|d64|3 5
f64v_axpy|-|f64v_axpy(d, a, 4611686018427387904, 2)|F64 put64(d, 0, 1); put64(d, 1, 1);|d64|3 5
f64v_dot|-|res = f64v_dot(a, b, 2)|F64|r64|6
f64v256_add|avx2|f64v256_add(d, a, b, 4)|F64|d64|3 4 5 6
f64v256_scale|avx2|f64v256_scale(d, a, 4613937818241073152, 4)|F64|d64|3 6 9 12
f64v256_sqrt|avx2|f64v256_sqrt(d, a, 4)|F64 put64(a, 0, 9); put64(a, 1, 16); put64(a, 2, 25); put64(a, 3, 36);|d64|3 4 5 6
f64v256_fmadd|avx2|f64v256_fmadd(d, a, b, c, 4)|F64|d64|3 5 7 9
f64v256_dot|avx2|res = f64v256_dot(a, b, 4)|F64|r64|20
f32v_add|-|f32v_add(d, a, b, 4)|F32|d32|3 4 5 6
f32v_fmadd|-|f32v_fmadd(d, a, b, c, 4)|F32|d32|3 5 7 9
f32v_dot|-|res = f32v_dot(a, b, 4)|F32|r32|20
f32v8_add|avx2|f32v8_add(d, a, b, 8)|F32|d32|3 4 5 6 7 8 9 10
f32v8_fma|avx2 fma|f32v8_fma(d, a, b, c, 8)|F32|d32|3 5 7 9 11 13 15 17
f32v8_dot|avx2|res = f32v8_dot(a, b, 8)|F32|r32|72
iv_add|-|iv_add(d, a, b, 2, 8)|store64(a, 1); store64(a + 8, 2); store64(b, 2); store64(b + 8, 2);|di|3 4
iv_dp8|ssse3|res = iv_dp8(a, b, 16)|k = 0; while (k < 16) { store8(a + k, k + 1); store8(b + k, 2); k = k + 1; }|ri|272
f64v_add_nonsetter|-|f64v_add(d, a, b, 2)|F64|d64|3 4|nonsetter
f64v_add_diffobj|-|f64v_add(d, a, b, 2)|F64|d64|3 4|diffobj
ROWS
}
# 3.0 = 0x4008000000000000 = 4613937818241073152; 2.0 = 0x4000000000000000 = 4611686018427387904.
F64='k = 0; while (k < 8) { put64(a, k, k + 1); put64(b, k, 2); put64(c, k, 1); k = k + 1; }'
F32='k = 0; while (k < 8) { put32(a, k, k + 1); put32(b, k, 2); put32(c, k, 1); k = k + 1; }'
_fill() { printf '%s' "$1" | sed -e "s/^F64/$F64/" -e "s/^F32/$F32/"; }
_checks() {   # _checks KIND "EXPECTED..." -> cyrius statements (exit 10+lane / 20 on a mismatch)
    _ck=""; _ci=0
    for _e in $2; do
        case $1 in
            d64) _ck="$_ck if (get64(d, $_ci) != $_e) { return $((10 + _ci)); }" ;;
            d32) _ck="$_ck if (get32(d, $_ci) != $_e) { return $((10 + _ci)); }" ;;
            di)  _ck="$_ck if (load64(d + $((_ci * 8))) != $_e) { return $((10 + _ci)); }" ;;
            r64) _ck="$_ck if (f64_to(res) != $_e) { return 20; }" ;;
            r32) _ck="$_ck if (f64_to(f32_to(res)) != $_e) { return 20; }" ;;
            ri)  _ck="$_ck if (res != $_e) { return 20; }" ;;
            *)   fail "axis A: unknown result kind '$1'" ;;
        esac
        _ci=$((_ci + 1))
    done
    printf '%s' "$_ck"
}
# `sz(t, gz(t) + 1)` is the whole trigger: the inner replay's param slot is released after the
# outer call's arguments, and the intrinsic's `_SIMD_RESERVE` takes it. `_gt` carries `t` out so
# the replay's own store is checked (exit 9) without declaring a local between the two.
#
# ⚠ THREE SHAPES, because the archived issue and the CHANGELOG both say the trigger needs NO
# setter and NO shared object, and until 6.6.5 every probe here was the same-object
# setter-of-getter — so the documented breadth rested on the fix being shape-agnostic rather than
# on any assertion. Each shape is confirmed to reproduce against 6.6.4 (rc 139).
#   setter   `sz(t, gz(t) + 1)`            — the filed shape (a derived setter of a derived getter)
#   nonsetter `q = add2(gz(t), 1)`         — a plain inline call, NOT a setter. `var q` is hoisted
#                                            ABOVE the replay and the store of `q` moved BELOW the
#                                            intrinsic, so no local is declared between the two
#                                            (one there takes the freed slot and hides the defect)
#   diffobj  `sz(t, gz(u) + 1)`            — getter and setter on DIFFERENT objects
_mkrow() {   # _mkrow OUT CALL FILL CHECKS [SHAPE]
_mk_shape=${5:-setter}
case $_mk_shape in
    setter)    _mk_helper='#inline
fn sz(p, v) { store64(p + 8, v); return 0; }'
               _mk_body='    var t = balloc(16); store64(t, 0); store64(t + 8, 41);
    sz(t, gz(t) + 1);'
               _mk_tail='    _gt = t;' ;;
    nonsetter) _mk_helper='#inline
fn add2(x, y) { return x + y; }'
               _mk_body='    var q = 0;
    var t = balloc(16); store64(t, 0); store64(t + 8, 41);
    q = add2(gz(t), 1);'
               _mk_tail='    store64(t + 8, q);
    _gt = t;' ;;
    diffobj)   _mk_helper='#inline
fn sz(p, v) { store64(p + 8, v); return 0; }'
               _mk_body='    var u = balloc(16); store64(u, 0); store64(u + 8, 41);
    var t = balloc(16); store64(t, 0); store64(t + 8, 0);
    sz(t, gz(u) + 1);'
               _mk_tail='    _gt = t;' ;;
    *)         fail "axis A: unknown replay shape '$_mk_shape'" ;;
esac
cat > "$1" <<EOF
var heap[2048];
var hp = 0;
var _gt = 0;
fn balloc(n) { var p = &heap + hp; hp = hp + n; return p; }
#inline
fn gz(p) { return load64(p + 8); }
$_mk_helper
fn put64(p, i, v) { store64(p + i * 8, f64_from(v)); return 0; }
fn get64(p, i) { return f64_to(load64(p + i * 8)); }
fn put32(p, i, v) { store32(p + i * 4, f32_from(f64_from(v))); return 0; }
fn get32(p, i) { return f64_to(f32_to(load32(p + i * 4))); }
fn run(d, a, b, c) {
    var res = 0;
$_mk_body
    $2;
$_mk_tail
    return res;
}
fn main() {
    var d = balloc(128); var a = balloc(128); var b = balloc(128); var c = balloc(128);
    var k = 0;
    while (k < 128) { store8(d + k, 0); store8(a + k, 0); store8(b + k, 0); store8(c + k, 0); k = k + 1; }
    $3
    var res = run(d, a, b, c);
    if (load64(_gt + 8) != 42) { return 9; }
    $4
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
}
_cpu_ok() {   # all listed flags present in /proc/cpuinfo ("-" = baseline x86-64)
    [ "$1" = "-" ] && return 0
    for _fl in $1; do grep -qw "$_fl" /proc/cpuinfo 2>/dev/null || return 1; done
    return 0
}
_exec() { set +e; "$1" > "$1.out" 2>&1; _xr=$?; set -e; echo "$_xr"; }

NROW=0; NEXEC=0; NSKIP=""
_rows > "$WORK/rows.txt"
while IFS='|' read -r n cpu call fill kind exp shape; do
    NROW=$((NROW + 1))
    _mkrow "$WORK/A_$n.cyr" "$call" "$(_fill "$fill")" "$(_checks "$kind" "$exp")" "${shape:-setter}"
    _build on "$WORK/A_$n.cyr" "$WORK/A_$n.on" || fail "axis A $n: probe did not compile (picker on): $(head -3 "$WORK/A_$n.on.err")"
    _build off "$WORK/A_$n.cyr" "$WORK/A_$n.off" || fail "axis A $n: probe did not compile (picker off)"
    if _cpu_ok "$cpu"; then
        R1=$(_exec "$WORK/A_$n.on"); R2=$(_exec "$WORK/A_$n.off")
        [ "$R1" -eq 0 ] || fail "axis A $n: picker ON -> rc $R1 (139 = SIGSEGV through an operand slot nothing wrote; 10-17 = wrong lane; 20 = wrong scalar; 9 = the replay's own store lost); picker OFF -> rc $R2"
        [ "$R2" -eq 0 ] || fail "axis A $n: picker OFF -> rc $R2 (the independent oracle disagrees with the constants)"
        NEXEC=$((NEXEC + 1))
    else
        NSKIP="$NSKIP $n"
    fi
    _axis_c elf "$WORK/A_$n.on" "$WORK/A_$n.off" "A/$n"
    _axis_d elf "$WORK/A_$n.on" "$WORK/A_$n.off" "A/$n"
    _axis_f "$WORK/A_$n.on" "A/$n"
done < "$WORK/rows.txt"
# 22 kernel rows (all 19 batch emitters) + the nonsetter and different-object replay shapes.
[ "$NROW" -eq 24 ] || fail "axis A: the row table has $NROW rows, expected 24 — a row was dropped"
NSHAPE=$(cut -d'|' -f7 "$WORK/rows.txt" | grep -c . || true)
[ "$NSHAPE" -eq 2 ] || fail "axis A: $NSHAPE rows carry an explicit replay shape, expected 2 (nonsetter + diffobj) — the non-setter/different-object admission routes the issue documents are unpinned again"

# ── axis B: the filed repro, VERBATIM ───────────────────────────────────────────────────
REPRO="docs/development/issues/repros/2026-09-14-hisab-simd-dst-slot-regalloc-picker.cyr"
[ -f "$REPRO" ] || fail "axis B: the filed repro is missing ($REPRO) — it is the spec"
printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\n' > "$WORK/B.cyr"
cat "$REPRO" >> "$WORK/B.cyr"
_build on "$WORK/B.cyr" "$WORK/B.on" || fail "axis B: the filed repro did not compile (picker on)"
_build off "$WORK/B.cyr" "$WORK/B.off" || fail "axis B: the filed repro did not compile (picker off)"
for _m in on off; do
    RB=$(_exec "$WORK/B.$_m")
    [ "$RB" -eq 0 ] || fail "axis B: filed repro, picker $_m -> rc $RB, printed: $(tr '\n' ' ' < "$WORK/B.$_m.out") (stock 6.6.4 printed \`1 4 3\`)"
    grep -q 'OK: (4, 5, 3)' "$WORK/B.$_m.out" || fail "axis B: filed repro, picker $_m exited 0 without printing its OK line"
done
_axis_c elf "$WORK/B.on" "$WORK/B.off" "B"
_axis_d elf "$WORK/B.on" "$WORK/B.off" "B"
_axis_f "$WORK/B.on" "B"

# ── axis E: the same structural oracle on PE and x86 Mach-O ─────────────────────────────
ESKIP=""
_axis_e() {   # _axis_e FORMAT VAR=VAL
    _fmt=$1; _env=$2
    while IFS='|' read -r n cpu call fill kind exp; do
        _build on "$WORK/A_$n.cyr" "$WORK/E_$n.on" "$_env" || fail "axis E/$_fmt $n: did not compile (picker on)"
        _build off "$WORK/A_$n.cyr" "$WORK/E_$n.off" "$_env" || fail "axis E/$_fmt $n: did not compile (picker off)"
        _axis_c "$_fmt" "$WORK/E_$n.on" "$WORK/E_$n.off" "E/$_fmt/$n"
        _axis_d "$_fmt" "$WORK/E_$n.on" "$WORK/E_$n.off" "E/$_fmt/$n"
    done < "$WORK/rows.txt"
    _build on "$WORK/B.cyr" "$WORK/E_B.on" "$_env" || fail "axis E/$_fmt: filed repro did not compile (picker on)"
    _build off "$WORK/B.cyr" "$WORK/E_B.off" "$_env" || fail "axis E/$_fmt: filed repro did not compile (picker off)"
    _axis_c "$_fmt" "$WORK/E_B.on" "$WORK/E_B.off" "E/$_fmt/B"
    _axis_d "$_fmt" "$WORK/E_B.on" "$WORK/E_B.off" "E/$_fmt/B"
}
_build on "$WORK/A_f64v_dot.cyr" "$WORK/pe_probe" CYRIUS_TARGET_WIN=1 || fail "axis E/pe: probe did not compile"
# ⚠ Into a file, not `objdump | grep -q`: under `bash -o pipefail` grep's early exit SIGPIPEs
# objdump and the whole test reads false — measured, it turned this leg into a silent SKIP.
objdump -f "$WORK/pe_probe" > "$WORK/pe_probe.hdr" 2>/dev/null || true
if grep -q 'file format pei-x86-64' "$WORK/pe_probe.hdr"; then
    _axis_e pe CYRIUS_TARGET_WIN=1
else
    ESKIP="$ESKIP pe(objdump-cannot-read-PE)"
fi
if command -v llvm-objdump >/dev/null 2>&1; then
    _axis_e macho CYRIUS_MACHO=1
else
    ESKIP="$ESKIP macho(no-llvm-objdump)"
fi

# ── axis G: no x86 byte-pattern pass may scan cx BYTECODE ───────────────────────────────
# `_AARCH64_BACKEND == 0` is not an x86 test — the cx backend sets it to 0 too — so until 6.6.5
# the register picker, DSE, both LASE loops, the NOP compactor and `_ra_frame_trim` all walked cx
# bytecode hunting x86 ModRM bytes, and the four NOP-fillers among them WRITE on a match. They
# never matched (44 of 44 cx-compilable corpus files emit identical bytecode with the gates), so
# this is a latent hazard closed, not a live bug — and that is exactly why it needs a pin.
#
# ⛔ THIS LEG IS DELIBERATELY A SOURCE ASSERTION, AND THE OBVIOUS RUNTIME ONE IS VACUOUS.
# `_read_env` is a STUB on the cx driver (`fn _read_env(name): i64 { return 0; }`,
# src/backend/cx/emit.cyr) — main_cx.cyr reads NO environment at all. So "compile a cx probe with
# and without CYRIUS_REGALLOC_PICKER_CAP=0 and require identical .cyx" passes whatever the
# compiler does, `CYRIUS_FRAMETRIM=0` likewise, and `CYRIUS_REGALLOC_DUMP=1` prints nothing on cx
# even on a compiler where the picker runs there (measured: 0 `ra: fi=` lines over the entire cx
# corpus with the PRE-fix compiler). Each of those would be a check that shares its defect with
# the thing it checks. What is actually observable is the source shape, so that is what is pinned.
GF="src/frontend/parse_fn.cyr"
NBP=$(grep -c 'bp_x86 == 1' "$GF" || true)
[ "$NBP" -eq 4 ] || fail "axis G: $NBP byte-pattern passes in $GF are gated on \`bp_x86\`, expected 4 (DSE, the integer LASE loop, the SIMD SLASE loop, the NOP-compaction block that also carries _ra_frame_trim) — a pass has lost its cx gate and is scanning cx bytecode again"
grep -q 'if (_AARCH64_BACKEND == 0 && _TARGET_CX == 0) { bp_x86 = 1; }' "$GF" \
    || fail "axis G: \`bp_x86\` in $GF is no longer defined as \`_AARCH64_BACKEND == 0 && _TARGET_CX == 0\` — the four gates above it may now be true on cx"
grep -q '_cur_fn_has_closure == 0 && _TARGET_CX == 0' "$GF" \
    || fail "axis G: the register picker's enable test in $GF has lost its \`_TARGET_CX == 0\` gate — it is rewriting cx bytecode as if it were x86"

# ── floors: every axis ran as often as the table says it must ───────────────────────────
NE=$((NROW + 1))
NEFMT=2; case "$ESKIP" in *pe*) NEFMT=$((NEFMT - 1)) ;; esac; case "$ESKIP" in *macho*) NEFMT=$((NEFMT - 1)) ;; esac
[ "$NC" -eq $((NE + NE * NEFMT)) ] || fail "floor: axis C ran $NC times, expected $((NE + NE * NEFMT))"
[ "$ND" -eq "$NC" ] || fail "floor: axis D ran $ND times, axis C $NC"
# Derived from the table, not hand-set: F runs once per ELF build (every row + the filed repro),
# and each of those contributed at least one regalloc fn and at least one ref per fn (asserted
# per binary in _axis_f). A hand-set total is what let the census halve unnoticed.
[ "$CEN_N" -eq "$NE" ] || fail "floor: axis F censused $CEN_N binaries, expected $NE (one per axis-A row plus the filed repro)"
[ "$CEN_REFS" -ge "$CEN_FNS" ] || fail "floor: axis F saw $CEN_REFS local disp32 refs over $CEN_FNS regalloc fns"

[ -z "$NSKIP" ] || echo "SKIP (loud): axis A did not EXECUTE${NSKIP} — this host lacks the CPU feature; their C/D/F/E axes still ran"
[ -z "$ESKIP" ] || echo "SKIP (loud): axis E did not run for${ESKIP}"
echo "PASS: simd_intrinsic_operand_slots (axes 0-5; A: $NROW rows, $NEXEC executed; B filed repro; C/D: $NC builds each; E: $NEFMT extra formats; F: $CEN_N binaries, $CEN_FNS regalloc fns, $CEN_REFS disp32 local refs, 0 disp8/SIB; G: 4 cx gates)"
