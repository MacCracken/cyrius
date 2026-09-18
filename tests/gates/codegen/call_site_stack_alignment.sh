#!/bin/sh
# 6.6.5 regression gate — rsp is 16-byte aligned at EVERY call, in every expression position.
#
# THE BUG. cycc's expression codegen is a stack machine: each pending value is a `push rax`
# (8 bytes), and nothing padded for those pending values when a CALL was emitted. The only
# alignment invariant was the frame rounding `fsz = (flc*8+15) & -16`, which makes rsp
# 16-aligned BETWEEN statements. So `f(0, c())` entered its callee 8 bytes off and
# `var t = c(); f(0, t);` did not — and SysV requires rsp ≡ 0 at the call instruction. A C
# callee that spills SSE with `movaps`/`movdqa`, which gcc emits for ordinary code, takes a
# #GP there. Filed from mabda 4.1.3 after a SIGSEGV inside NVK's `create_buffer`; the shift
# is also INHERITED, so any cyrius fn reached from a nested position calls C misaligned too.
# See docs/development/issues/archived/2026-09-16-mabda-cycc-nested-call-stack-misalignment.md.
#
# WHY A C LEAF AND NOT A CYRIUS ONE. The fix added a compile-time depth counter (`_xdepth`).
# A gate that asked that counter would share the model it is meant to check — the exact
# shape of "a check that shares a defect with the thing it checks reads GREEN". Here the
# expected value is the SysV ABI constant 0, and the actual value is computed by the CPU
# inside a gcc-assembled leaf (`lea 8(%rsp),%rax; and $15,%rax`) from the frame the caller
# really built. Two different derivations.
#
# ANTI-VACUOUS AXIS. One row puts a raw `push rax` in an inline-asm block the compiler
# cannot account for, then calls the leaf at statement level: it MUST read 8. If it reads 0
# the probe is measuring nothing and every "expected 0" row above it is worthless, so the
# driver adds 100 to its exit code and this gate fails.
#
# FAULT-CLASS AXIS. The last rows call `sse_leaf`, which does `movaps` on its own stack.
# Misaligned, that is a #GP — the driver exits 139 rather than printing a count, which is
# what 6.6.4 did. A gate that only counted rows could be satisfied by a leaf that never
# faults; this one carries the real failure.
#
# MUTATION LEDGER. Each mutant is a one-edit scratch copy of src/ compiled by build/cycc
# (so the binary IS the mutant emitter), run against this driver, and separately asked to
# self-compile so the compile-time `_xd_check` count can be read. Measured 2026-09-17 at
# 6.6.5 on x86_64 Linux; "rows" is the driver's own misaligned count.
#
#   mutation                                          this gate            _xd_check on a
#                                                                          cycc self-compile
#   drop the SysV ECALLPOPS parity `push rax`         29 rows, SIGSEGV     0 reports
#   drop the ESPILL depth increment                    5 rows, SIGSEGV     200 reports
#   revert the >6-arg parity to `nextra & 1`           6 rows, exit 6      0 reports
#   ECALLCLEAN emits no `pop rcx` but STILL            24 rows, SIGSEGV    0 reports
#     decrements `_xdepth` (delete `EB(S, 0x59)` only)
#   delete that whole ECALLCLEAN line (byte AND        24 rows, SIGSEGV    200 reports
#     decrement)
#   the 6.6.4 compiler                                35 rows, SIGSEGV     (no checker)
#
# AXIS (B), the `await` driver at the end, measured separately because axis (A) faults
# first on a broken compiler and the script stops there: built and run on its own, the
# 6.6.4 compiler exits **128** (odd-depth row 8, statement-level control 0) and 6.6.5
# exits 0.
#
# ⭐ READ THE FOURTH ROW. It is the case for a CPU-measured gate: the model stays
# self-consistent (ECALLPOPS increments, ECALLCLEAN decrements) while the EMITTED code leaks
# 8 bytes per padded call, so `_xd_check` reports nothing and only the CPU can tell. ⚠ An
# earlier version of this header attributed that zero-desync result to the fifth row — the
# whole-line deletion — which does NOT reproduce: it gives 200 reports, because ECALLPOPS's
# increment is then unmatched. Both mutants were rebuilt and re-measured.
#
# DEAD-ROW AUDIT (rerun when a row is added): rebuild leaf.c with every `rsp_mod*` returning
# a constant 8, drop the three `sse_leaf` rows (they fault rather than return), and every
# remaining row must report. Measured at 6.6.5: 56 of 56. THREE rows failed that audit on
# the first cut and are fixed here — two `f2(rsp_mod(), 0)` rows (f2 returns its SECOND
# argument, so they were the constant 0) and `if (zero < rsp_mod() + 1)` (true for a probe
# reading 0 AND for one reading 8).
#
# ROW FLOOR (6.6.5, second cut). That audit is MANUAL, so until now nothing enforced it at
# run time: the driver kept a row counter and never returned it, so deleting rows from
# run() left this gate printing PASS with the same message. It now asserts two independently
# derived counts — the probe call sites grepped STATICALLY out of the driver source, and the
# `ROWS nnn` line the driver prints at RUNTIME — against each other and against the 56 floor
# above. Mutants, both built and run (2026-09-17):
#   six rows deleted from run()           → FAIL "carries only 50 probe rows"
#   one row wrapped in `if (one == 0)`    → FAIL "55 of 56 probe rows actually executed"
# ⚠ The first cut counted comment lines too, and this header's own new text names the probe
# — 58 sites against 56 rows, an instant self-inflicted FAIL. Comments are stripped now.
#
# ────────────────────────────────────────────────────────────────────────────────────────
# AXIS (C) — THE ENTRY BASE, SWEPT OVER argv/env. AXIS (D) — THE Mach-O LANDING BYTES.
#
# Everything above measures a SHAPE relative to the body's base. Both of these measure THE
# BASE, and they exist because 6.6.5 shipped a shape fix on top of an entry assumption that
# was false on a third target.
#
# ⛔ WHAT HAPPENED. Bite 2 seeded the PE and UEFI landings (Windows/firmware enter at
# rsp ≡ 8) and its premise-check recorded the x86 Mach-O entry as "kernel-aligned", so it
# was left alone. MEASURED ON ach (real Intel-Mac, Darwin 22.6.0 x86_64): XNU's entry rsp
# parity VARIES WITH THE BYTE COUNT OF THE argv/env STRING AREA. One binary, renamed:
#     ./_l -> misaligned   ./_lt -> misaligned   ./_ltxx -> aligned   /tmp/csa2 -> aligned
#     PADVAR=x ./_lt -> misaligned      PADVAR=xxxxxxx ./_lt -> aligned
# A 20-argv0-length x 16-env-pad sweep of a naked `(rsp+8)&15` probe splits 160/160, and it
# tracks the PARKED entry rsp (`r15 & 15`) row for row. So `tests/tcyr/crossos/
# call_site_stack_alignment.tcyr` passed or failed BY PROCESS NAME — and the cross-OS
# runner always names the binary `./_lt`, i.e. it samples exactly ONE parity. A single run
# under a single name is NOT a verification on Darwin.
#
# AXIS (C) runs that sweep here, on ELF, where SysV amd64 §3.4.1 makes rsp ≡ 0 at _start a
# guarantee: it pins the guarantee and it is the recipe. It CANNOT catch the Darwin defect
# from Linux — only axis (D) can — but it is the axis a future entry change gets measured
# with, on whichever host it is run.
#
#   MANUAL DARWIN RECIPE (no `timeout`, no GNU coreutils needed; ~40 s on ach):
#     scp the probe + sweeper to the host, then, from ~/_cyaud after a cross-OS leg:
#       cat entry_parity_both.cyr | ./r1 > b && chmod +x b && mkdir -p d && cp b d/
#       sh sweep.sh $HOME/_cyaud/d b | awk '{print $3}' | sort | uniq -c
#     Every row must be 16 (probe 0, control 8). 8 = misaligned. 0 or 24 = dead probe.
#     `sweep.sh` renames the binary to argv0 lengths 1..20 and runs each under 0..15 bytes
#     of PADVAR. On ecb (arm64) add `CYSIGN=1` — AMFI needs each copy re-codesigned.
#     Sources: scratch of the 6.6.5 bite-2 Mach-O fix; the probe is the same two #naked
#     fns as tests/tcyr/crossos/call_site_stack_alignment.tcyr's ENTRY row.
#   MEASURED 2026-09-17, every target this box can reach:
#     ach   (REAL Intel Mac, x86_64 Mach-O)  320/320 aligned WITH the fix,
#                                            160/320 WITHOUT it (mutant compiler, same
#                                            host, same ssh session)
#     ecb   (REAL macOS arm64)               320/320 aligned, control 320/320 = 8
#     this box (x86_64 ELF)                  320/320 aligned  <- axis (C) itself
#     aarch64 ELF under qemu-aarch64         320/320 aligned
#     PE under wine                          96/96 aligned (12 argv0 x 8 env)
#   ⭐ The raw kernel parity probe (`r15 & 15`) STILL splits 160/160 on ach with the fix
#   in — the kernel has not changed, the landing absorbs it. That is the measurement that
#   distinguishes "fixed" from "got lucky", and it is worth re-taking after any landing
#   change.
#
# AXIS (D) is the one that WOULD HAVE CAUGHT THIS WITHOUT A MAC. `CYRIUS_MACHO=1 build/cycc`
# cross-builds Mach-O from Linux, so the landing it emits can be read here as bytes:
# `mov r15, rsp` (49 89 E7) IMMEDIATELY followed by `and rsp, -16` (48 83 E4 F0). Plus a
# fork-parity axis, because `src/main.cyr` and `src/main_x86_macho.cyr` both carry that
# landing and a partial fork edit is the trap this release keeps hitting.
#
# MUTATION LEDGER FOR (C) AND (D) — every mutant BUILT AND RUN, 2026-09-17 at 6.6.5.
# Each is a scratch tree (`build/cycc` + `src/` + a copy of this gate) so the gate's own
# $ROOT resolution picks the mutant up exactly as it would a real regression.
#
#   mutant                                                     result
#   src/main.cyr landing gets an unconditional `sub rsp,8`     axis (C) FAIL, 320 of 320
#     (the Mach-O defect reproduced on a target the dev box      combinations misaligned
#     can run; it is what the ENTRY row in the .tcyr sees)       (the gate stops at axis (B)
#                                                                first — (C) measured
#                                                                standalone for this row)
#   the anti-vacuous twin made identical to the probe          axis (C) FAIL, "the probe is
#     (`lea rax,[rsp+16]` -> `[rsp+8]`)                          dead", 320 of 320 exit 0
#   src/main.cyr drops `EALIGN_RSP_16` (cross fork)            axis (D) FAIL, bytes
#   src/main_x86_macho.cyr drops it (NATIVE fork only —        axis (D) FAIL, fork parity,
#     the partial fork edit; the cross build still has it        NAMING main_x86_macho.cyr
#     so the BYTE axis alone stays GREEN)                        (⭐ this is why the source
#                                                                axis exists next to the
#                                                                byte axis)
#   the align emitted BEFORE the r15 park                      axis (D) FAIL, ordering,
#                                                                "park line 413, align 412"
#   `mo_need` set to a needle both builds carry                axis (D) FAIL, vacuous
#   unmutated tree                                             PASS, 320 runs, 0 misaligned
# ────────────────────────────────────────────────────────────────────────────────────────
#
# Skips gracefully off Linux/x86_64, or without gcc / build/cycc.
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CYCC="$ROOT/build/cycc"

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)
if [ "$uname_s" != "Linux" ] || [ "$uname_m" != "x86_64" ]; then
    echo "SKIP: call-site alignment gate is Linux/x86_64 only (host: $uname_s/$uname_m)"
    exit 0
fi
if ! command -v gcc >/dev/null 2>&1; then
    echo "SKIP: gcc not available (needed to assemble the alignment leaf)"
    exit 0
fi
if [ ! -x "$CYCC" ]; then
    echo "SKIP: build/cycc not built"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/leaf.c" <<'CEOF'
extern void _cyrius_init(void);
extern long run(void);
long rsp_mod(void);
long rsp_mod7(long,long,long,long,long,long,long);
long rsp_mod8(long,long,long,long,long,long,long,long);
long rsp_mod9(long,long,long,long,long,long,long,long,long);
long sse_leaf(void);
/* Each returns (rsp + 8) & 15 measured at its own entry: 0 == ABI-correct.
   The arity variants exist so the >6-arg marshalling path is measured at ITS
   OWN call, not at a 0-arg leaf nested inside it. sse_leaf carries the fault
   class: `movaps` on its own stack #GPs when entered misaligned. */
__asm__(".globl rsp_mod\nrsp_mod:\n lea 8(%rsp),%rax\n and $15,%rax\n ret\n"
        ".globl rsp_mod7\nrsp_mod7:\n lea 8(%rsp),%rax\n and $15,%rax\n ret\n"
        ".globl rsp_mod8\nrsp_mod8:\n lea 8(%rsp),%rax\n and $15,%rax\n ret\n"
        ".globl rsp_mod9\nrsp_mod9:\n lea 8(%rsp),%rax\n and $15,%rax\n ret\n"
        ".globl sse_leaf\nsse_leaf:\n sub $24,%rsp\n xorps %xmm0,%xmm0\n"
        " movaps %xmm0,(%rsp)\n add $24,%rsp\n xor %eax,%eax\n ret\n");
int main(void) { _cyrius_init(); return (int)run(); }
CEOF
if ! gcc -c "$TMP/leaf.c" -o "$TMP/leaf.o" 2>"$TMP/gcc.err"; then
    echo "SKIP: gcc could not assemble the alignment leaf"
    sed 's/^/  /' "$TMP/gcc.err" 2>/dev/null | head -5
    exit 0
fi

cat > "$TMP/drv.cyr" <<'EOF'
object;
include "lib/fnptr.cyr"

var BAD = 0;
var ROW = 0;
var CTRL = 0 - 1;

fn emit_row(): i64 {
    var d[4];
    store8(&d, 32);
    store8(&d + 1, 48 + ROW / 10);
    store8(&d + 2, 48 + ROW - (ROW / 10) * 10);
    store8(&d + 3, 10);
    syscall(1, 2, &d, 4);
    return 0;
}

# 6.6.5 — report the TOTAL number of rows that actually executed, so the driver's count can
# be cross-checked against a count derived a different way (the shell counts the probe call
# sites out of this very source). Without it the gate had no row floor at all: deleting rows
# from run() left it printing PASS with the same message, which is the "a green gate
# measuring nothing" shape the rest of this file exists to prevent.
fn emit_total(): i64 {
    var d[16];
    store8(&d,     82);   # 'R'
    store8(&d + 1, 79);   # 'O'
    store8(&d + 2, 87);   # 'W'
    store8(&d + 3, 83);   # 'S'
    store8(&d + 4, 32);
    store8(&d + 5, 48 + ROW / 100);
    store8(&d + 6, 48 + ROW / 10 - (ROW / 100) * 10);
    store8(&d + 7, 48 + ROW - (ROW / 10) * 10);
    store8(&d + 8, 10);
    syscall(1, 2, &d, 9);
    return 0;
}

# v is 0 exactly when the probed call was 16-byte aligned at its `call`.
fn chk(v): i64 {
    ROW = ROW + 1;
    if (v != 0) {
        BAD = BAD + 1;
        syscall(1, 2, "  MISALIGNED row", 16);
        emit_row();
    }
    return 0;
}

fn id1(a): i64 { return a; }
fn f2(a, b): i64 { return b; }
# ⚠ A row only reports if the callee returns the argument the probe sits in. `f2` returns
# its SECOND argument, so `f2(rsp_mod(), 0)` is the constant 0 — two rows of this driver
# were dead that way until 6.6.5. `f2a` returns the FIRST.
fn f2a(a, b): i64 { return a; }
fn f3(a, b, c): i64 { return b + c; }
fn f4(a, b, c, d): i64 { return b + c + d; }
fn f6(a, b, c, d, e, f): i64 { return e + f; }
fn f7(a, b, c, d, e, f, g): i64 { return g; }
fn f8(a, b, c, d, e, f, g, h): i64 { return g + h; }
fn f9(a, b, c, d, e, f, g, h, i): i64 { return i; }

# A fn entered misaligned runs its whole body misaligned, so this statement-level
# call inherits the caller's shift.
fn hop(): i64 { var q = rsp_mod(); return q; }
# The same fn nesting its own probe: two shifts cancel.
fn hop2(): i64 { return f2(0, rsp_mod()); }

fn run(): i64 {
    var zero = 0;
    var one = 1;
    var slot[8];
    var fp1 = &id1;
    var fp2 = &f2;
    var t = 0;

    # --- statement / left-operand positions (aligned before 6.6.5 too) ---
    t = rsp_mod();                                 chk(t);
    t = f2a(rsp_mod(), 0);                         chk(t);
    t = rsp_mod() + zero;                          chk(t);

    # --- direct call, argument k of n: k-1 values pending ---
    t = f2(0, rsp_mod());                          chk(t);
    t = f3(0, rsp_mod(), 0);                       chk(t);
    t = f3(0, 0, rsp_mod());                       chk(t);
    t = f4(0, 0, 0, rsp_mod());                    chk(t);
    t = f6(0, 0, 0, 0, rsp_mod(), 0);              chk(t);
    t = f6(0, 0, 0, 0, 0, rsp_mod());              chk(t);

    # --- a cyrius callee with >6 args, probed at its last argument ---
    t = f7(0, 0, 0, 0, 0, 0, rsp_mod());           chk(t);
    t = f2(0, f7(0, 0, 0, 0, 0, 0, rsp_mod()));    chk(t);
    t = f8(0, 0, 0, 0, 0, 0, rsp_mod(), 0);        chk(t);
    t = f8(0, 0, 0, 0, 0, 0, 0, rsp_mod());        chk(t);
    t = f9(0, 0, 0, 0, 0, 0, 0, 0, rsp_mod());     chk(t);
    t = f2(0, f9(0, 0, 0, 0, 0, 0, 0, 0, rsp_mod())); chk(t);
    t = f3(0, f9(0, 0, 0, 0, 0, 0, 0, 0, rsp_mod()), 0); chk(t);

    # --- THE CALLER'S OWN >6-ARG MARSHALLING, measured at ITS call. v5.6.41 padded on
    #     `nextra & 1` alone: at depth 0 that rule is right, one level in it is inverted.
    t = rsp_mod7(1, 2, 3, 4, 5, 6, 7);             chk(t);
    t = f2(0, rsp_mod7(1, 2, 3, 4, 5, 6, 7));      chk(t);
    t = f3(0, rsp_mod7(1, 2, 3, 4, 5, 6, 7), 0);   chk(t);
    t = f3(0, 0, rsp_mod7(1, 2, 3, 4, 5, 6, 7));   chk(t);
    t = rsp_mod8(1, 2, 3, 4, 5, 6, 7, 8);          chk(t);
    t = f2(0, rsp_mod8(1, 2, 3, 4, 5, 6, 7, 8));   chk(t);
    t = rsp_mod9(1, 2, 3, 4, 5, 6, 7, 8, 9);       chk(t);
    t = f2(0, rsp_mod9(1, 2, 3, 4, 5, 6, 7, 8, 9)); chk(t);
    t = f4(0, 0, 0, rsp_mod9(1, 2, 3, 4, 5, 6, 7, 8, 9)); chk(t);
    store64(&slot, rsp_mod7(1, 2, 3, 4, 5, 6, 7)); chk(load64(&slot));

    # --- store64 argument 2 (the shape the mabda filing crashed on) ---
    store64(&slot, rsp_mod());                     chk(load64(&slot));

    # --- every binary operator class, right operand ---
    t = zero + rsp_mod();                          chk(t);
    t = zero - rsp_mod();                          chk(0 - t);
    t = one * rsp_mod();                           chk(t);
    t = 16 / (rsp_mod() + 8);                      chk(t - 2);
    t = 16 % (rsp_mod() + 16);                     chk(t);
    t = one << rsp_mod();                          chk(t - 1);
    t = 15 & rsp_mod();                            chk(t);
    t = zero | rsp_mod();                          chk(t);
    t = zero ^ rsp_mod();                          chk(t);
    t = 0 - rsp_mod();                             chk(0 - t);
    t = -rsp_mod();                                chk(0 - t);

    # --- comparison operands ---
    t = 8; if (zero == rsp_mod()) { t = 0; }       chk(t);
    t = 8; if (rsp_mod() == zero) { t = 0; }       chk(t);
    # ⚠ NOT `if (zero < rsp_mod() + 1)`: that is true for a probe reading 0 AND for one
    #   reading 8, so the row was dead (caught by the dead-row audit above).
    t = 8; if (rsp_mod() < one) { t = 0; }         chk(t);

    # --- a call emitted AFTER f64_exp in the SAME expression. The x87 +/-inf guard emits
    #     its two arms out of execution order, so the depth model needs a branch restore;
    #     without it every f64_exp/f64_exp2 site pads the rest of its statement wrongly.
    t = f2(f64_exp(f64_from(0)), rsp_mod());       chk(t);
    t = f3(f64_exp(f64_from(1)), 0, rsp_mod());    chk(t);

    # --- nesting: 1, 2 and 3 values pending from enclosing expressions ---
    t = f2(0, f2(0, rsp_mod()));                   chk(t);
    t = f2(0, f2a(rsp_mod(), 0));                  chk(t);
    t = f2(0, f4(0, 0, rsp_mod(), 0));             chk(t);
    t = f2(0, f2(0, f2(0, rsp_mod())));            chk(t);

    # --- an intermediate cyrius frame (the inherited shift) ---
    t = hop();                                     chk(t);
    t = f2(0, hop());                              chk(t);
    t = f2(0, hop2());                             chk(t);
    t = f4(0, 0, 0, hop());                        chk(t);

    # --- fncallN and callptr, expression position ---
    t = fncall1(fp1, rsp_mod());                   chk(t);
    t = fncall2(fp2, 0, rsp_mod());                chk(t);
    t = f2(0, fncall1(fp1, rsp_mod()));            chk(t);
    t = callptr(fp1, rsp_mod());                   chk(t);
    t = f2(0, callptr(fp2, 0, rsp_mod()));         chk(t);

    # --- ANTI-VACUOUS CONTROL: a raw `push rax` the compiler cannot see makes the next
    #     statement-level call odd. It MUST read 8.
    asm { 0x50; }
    CTRL = rsp_mod();
    asm { 0x58; }

    # --- the fault class: a C leaf doing `movaps` on its own stack. 6.6.4 exited 139 here.
    store64(&slot, sse_leaf());
    t = f2(0, sse_leaf());
    t = zero + sse_leaf();

    if (CTRL != 8) { BAD = BAD + 100; }
    emit_total();
    return BAD;
}
EOF

if ! "$CYCC" < "$TMP/drv.cyr" > "$TMP/drv.o" 2>"$TMP/drv.err"; then
    echo "FAIL: could not compile the alignment driver"
    sed 's/^/  /' "$TMP/drv.err" | head -8
    exit 1
fi
if [ ! -s "$TMP/drv.o" ]; then
    echo "FAIL: the alignment driver compiled to an EMPTY object (cycc exits 0 on empty input)"
    exit 1
fi
# The driver must actually contain the probe rows; an object that lost them would link and
# exit 0 with nothing measured.
if ! gcc "$TMP/leaf.o" "$TMP/drv.o" -o "$TMP/drv" 2>"$TMP/link.err"; then
    echo "FAIL: could not link the alignment driver against the C leaf"
    sed 's/^/  /' "$TMP/link.err" | head -8
    exit 1
fi

set +e
"$TMP/drv" > "$TMP/out" 2>"$TMP/rows"
rc=$?
set -e
# ⚠ `grep -c` exits 1 on zero matches, and this script runs under `set -e`: written as a
# bare command substitution it kills the gate on the GREEN path. (CLAUDE.md, verification
# habits: "var=$(failing_cmd) trips set -e before the bookkeeping".)
rows=$(grep -c 'MISALIGNED' "$TMP/rows" 2>/dev/null || true)
[ -n "$rows" ] || rows=0

if [ "$rc" = "139" ]; then
    echo "FAIL: the driver took SIGSEGV — a misaligned call into a C leaf that uses aligned SSE"
    sed 's/^/  /' "$TMP/rows" | head -12
    echo "  ($rows rows reported misaligned before the fault)"
    exit 1
fi
if [ "$rc" -ge 100 ] 2>/dev/null; then
    echo "FAIL: the anti-vacuous control read 0 instead of 8 — the probe measures nothing,"
    echo "      so every aligned row above it is meaningless. Check that inline asm still"
    echo "      emits its bytes and that the C leaf is the one being called."
    exit 1
fi
if [ "$rc" != "0" ]; then
    echo "FAIL: $rc call site(s) entered a C leaf with rsp 8 bytes off 16-byte alignment"
    sed 's/^/  /' "$TMP/rows" | head -20
    exit 1
fi
if [ "$rows" != "0" ]; then
    echo "FAIL: exit 0 but $rows misaligned rows were reported — the counter and the exit"
    echo "      code disagree, which means the driver's own bookkeeping is broken"
    exit 1
fi

# ── ROW FLOOR. Two derivations, neither of them the exit code:
#   expect_rows — counted STATICALLY out of the driver source this script just wrote
#                 (`chk(` call sites minus the one definition). Deleting rows from run()
#                 moves this number, so a trimmed driver can no longer report PASS.
#   rowtot      — counted at RUNTIME by the driver itself and printed as `ROWS nnn`.
# They must agree (a row that never executes is a dead row) and the static count must clear
# the DEAD-ROW AUDIT floor in the header. The .tcyr sibling floors the same way with
# assert_gte(NCHK, 64); this is that assertion for the shell half.
# ⚠ Comment lines are stripped first. The first cut counted them too, and this gate's own
# new header comment mentioned the probe's name — 58 sites against 56 rows, an instant
# self-inflicted FAIL.
chk_sites=$(grep -v '^[[:space:]]*#' "$TMP/drv.cyr" | grep -o 'chk(' | wc -l)
chk_defs=$(grep -c '^fn chk(' "$TMP/drv.cyr" 2>/dev/null || true)
[ -n "$chk_defs" ] || chk_defs=0
expect_rows=$((chk_sites - chk_defs))
rowtot=$(sed -n 's/^ROWS 0*\([0-9][0-9]*\)$/\1/p' "$TMP/rows" | tail -1)
[ -n "$rowtot" ] || rowtot=0
if [ "$expect_rows" -lt 56 ]; then
    echo "FAIL: the driver carries only $expect_rows probe rows — the DEAD-ROW AUDIT in this"
    echo "      gate's header measured 56 of 56 at 6.6.5. Rows were deleted, or \`chk(\` was"
    echo "      renamed; re-run the audit and update the floor deliberately, do not lower it"
    exit 1
fi
if [ "$rowtot" != "$expect_rows" ]; then
    echo "FAIL: $rowtot of $expect_rows probe rows actually executed — the rest are"
    echo "      unreachable, so they prove nothing (the gate would stay green if the"
    echo "      compiler broke exactly there). Re-run the DEAD-ROW AUDIT in the header."
    exit 1
fi

# ── AXIS (B): `await`, which needs CYRIUS_ASYNC=1 and so cannot live in a .tcyr (the corpus
# runner does not set it). `future_force` was one of the four ECALLPOPS-without-ECALLCLEAN
# sites this release fixed, and `await` at odd depth is the shape that exercises it. Pure
# cyrius with the same #naked probe — no C leaf — because the point is the pending depth, not
# the callee's ABI. Ledger: the 6.6.4 compiler exits 128 here (8 at odd depth, 0 at statement
# level); 6.6.5 exits 0. CHANGELOG [6.6.5]
cat > "$TMP/aw.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
#naked
fn P(): i64 {
    asm {
        0x48; 0x8D; 0x44; 0x24; 0x08;   # lea rax, [rsp+8]
        0x48; 0x83; 0xE0; 0x0F;         # and rax, 15
        0xC3;                            # ret
    }
}
fn snd(x, y): i64 { return y; }
async fn ap(): i64 { return P(); }
alloc_init();
fn main(): i64 {
    var nested = snd(0, await ap());     # odd depth
    var stmt = await ap();               # statement level (a control)
    return nested * 16 + stmt;
}
var rr = main();
syscall(60, rr);
EOF
if ! CYRIUS_ASYNC=1 "$CYCC" < "$TMP/aw.cyr" > "$TMP/aw" 2>"$TMP/aw.err"; then
    echo "FAIL: could not compile the await alignment driver"
    sed 's/^/  /' "$TMP/aw.err" | head -8
    exit 1
fi
if [ ! -s "$TMP/aw" ]; then
    echo "FAIL: the await alignment driver compiled to an EMPTY binary"
    exit 1
fi
chmod +x "$TMP/aw"
set +e
"$TMP/aw"
awrc=$?
set -e
if [ "$awrc" != "0" ]; then
    echo "FAIL: await reached a call at the wrong alignment (exit $awrc; high nibble = the"
    echo "      odd-depth row, low nibble = the statement-level control; 6.6.4 gives 128)"
    exit 1
fi

# ── AXIS (C): THE ENTRY BASE, SWEPT OVER argv0 LENGTH AND ENV SIZE. See the header block.
# The probe and its anti-vacuous twin live in ONE binary so nothing about the file (size,
# name, path) can differ between the two readings — measured on ach, two separate binaries
# disagree on 40 of 320 rows purely from their own load layout, which would have looked
# like nondeterminism. exit = probe + 2*twin: 16 == aligned and live, 8 == MISALIGNED,
# 0 or 24 == the probe is dead and this axis proves nothing. CHANGELOG [6.6.5]
cat > "$TMP/ep.cyr" <<'EOF'
#naked
fn align_probe(): i64 {
    asm { 0x48; 0x8D; 0x44; 0x24; 0x08; 0x48; 0x83; 0xE0; 0x0F; 0xC3; }
}
#naked
fn align_probe_8(): i64 {
    asm { 0x48; 0x8D; 0x44; 0x24; 0x10; 0x48; 0x83; 0xE0; 0x0F; 0xC3; }
}
var a = align_probe();
var b = align_probe_8();
var r = a + b + b;
EOF
if ! "$CYCC" < "$TMP/ep.cyr" > "$TMP/ep" 2>"$TMP/ep.err"; then
    echo "FAIL: could not compile the entry-base probe"
    sed 's/^/  /' "$TMP/ep.err" | head -8
    exit 1
fi
if [ ! -s "$TMP/ep" ]; then
    echo "FAIL: the entry-base probe compiled to an EMPTY binary"
    exit 1
fi
mkdir -p "$TMP/epd"
chmod +x "$TMP/ep"
sw_runs=0; sw_bad=0; sw_dead=0; sw_first=""
i=1
while [ "$i" -le 20 ]; do
    # A name of exactly $i bytes: argv[0] is copied onto the initial stack, so its LENGTH is
    # one of the two inputs that move the entry rsp on Darwin. ⚠ `printf 'p%.0s'` repeats the
    # format once per argument, which is what makes the length track $i.
    nm=$(printf 'p%.0s' $(seq 1 "$i"))
    [ -n "$nm" ] || nm="p"
    cp "$TMP/ep" "$TMP/epd/$nm"
    chmod +x "$TMP/epd/$nm"
    j=0
    while [ "$j" -le 15 ]; do
        pad=""
        # ⚠ if/else, not `[ ] && pad=...`: an AND-list whose FIRST command fails is exempt
        # from `set -e` but the idiom is one edit away from not being, and this gate is run
        # under `bash -eo pipefail`.
        if [ "$j" -gt 0 ]; then pad=$(printf 'x%.0s' $(seq 1 "$j")); fi
        set +e
        ( cd "$TMP/epd" && PADVAR="$pad" "./$nm" >/dev/null 2>&1 )
        eprc=$?
        set -e
        sw_runs=$((sw_runs + 1))
        if [ "$eprc" = "16" ]; then
            :
        elif [ "$eprc" = "8" ]; then
            sw_bad=$((sw_bad + 1))
            [ -z "$sw_first" ] && sw_first="argv0 length $i, PADVAR $j byte(s)"
        else
            sw_dead=$((sw_dead + 1))
            [ -z "$sw_first" ] && sw_first="argv0 length $i, PADVAR $j byte(s) -> exit $eprc"
        fi
        j=$((j + 1))
    done
    rm -f "$TMP/epd/$nm"
    i=$((i + 1))
done
if [ "$sw_runs" -lt 320 ]; then
    echo "FAIL: the entry-base sweep ran only $sw_runs of 320 argv0/env combinations"
    exit 1
fi
if [ "$sw_dead" != "0" ]; then
    echo "FAIL: $sw_dead of $sw_runs entry-base runs reported neither 16 nor 8 — the probe is"
    echo "      dead or the binary faulted, so this axis proves nothing (first: $sw_first)"
    exit 1
fi
if [ "$sw_bad" != "0" ]; then
    echo "FAIL: THE ENTRY BASE IS MISALIGNED in $sw_bad of $sw_runs argv0/env combinations"
    echo "      (first: $sw_first). The process entry landing did not establish 16-byte"
    echo "      alignment — this is the BASE, not a call-site shape, so every row above is"
    echo "      downstream of it. SysV amd64 guarantees rsp = 0 (mod 16) at _start, so on"
    echo "      Linux this means the landing itself moved rsp by an odd number of slots."
    exit 1
fi

# ── AXIS (D): THE Mach-O LANDING BYTES, CROSS-BUILT FROM LINUX. The axis that would have
# caught the 6.6.5 Mach-O defect without an Intel Mac. Two derivations, neither of them the
# CPU: the emitted bytes, and the two source forks that emit them.
mo_need="4989e74883e4f0"     # mov r15, rsp ; and rsp, -16
if ! CYRIUS_MACHO=1 "$CYCC" < "$TMP/ep.cyr" > "$TMP/ep_macho" 2>"$TMP/ep_macho.err"; then
    echo "FAIL: could not cross-build the entry probe for Mach-O (CYRIUS_MACHO=1)"
    sed 's/^/  /' "$TMP/ep_macho.err" | head -8
    exit 1
fi
if [ ! -s "$TMP/ep_macho" ]; then
    echo "FAIL: the Mach-O cross build produced an EMPTY binary"
    exit 1
fi
mo_hex=$(od -An -tx1 -v "$TMP/ep_macho" | tr -d ' \n')
elf_hex=$(od -An -tx1 -v "$TMP/ep" | tr -d ' \n')
case "$mo_hex" in
    *"$mo_need"*) ;;
    *)
        echo "FAIL: the x86 Mach-O entry landing does not establish 16-byte alignment."
        echo "      Expected the r15 park immediately followed by \`and rsp,-16\` ($mo_need),"
        echo "      which is what makes the base independent of the entry rsp parity XNU"
        echo "      hands over — and on Darwin x86_64 that parity VARIES WITH THE argv/env"
        echo "      BYTE COUNT (measured on ach: 160 of 320 combinations misaligned without"
        echo "      it). See src/main.cyr and src/main_x86_macho.cyr, EALIGN_RSP_16."
        exit 1 ;;
esac
# Anti-vacuous: the ELF build of the SAME source must NOT carry that pair, or the axis is
# matching an instruction sequence the compiler emits everywhere and would pass on a
# compiler with no Mach-O landing at all.
case "$elf_hex" in
    *"$mo_need"*)
        echo "FAIL: the ELF build carries the Mach-O landing pair too — axis (D) is vacuous"
        echo "      (it would pass without any Mach-O-specific landing). Pick a needle that"
        echo "      is specific to the Mach-O entry."
        exit 1 ;;
esac
# Fork parity: BOTH x86 sources that carry a Mach-O landing must call the helper, and each
# call must come AFTER that fork's r15 park (0xE78949). A partial fork edit is the trap this
# release keeps hitting — main.cyr is the cross path, main_x86_macho.cyr the native one, and
# only the native one ships to Intel Macs.
for f in src/main.cyr src/main_x86_macho.cyr; do
    n=$(grep -c 'EALIGN_RSP_16(S)' "$ROOT/$f" 2>/dev/null || true)
    [ -n "$n" ] || n=0
    if [ "$n" -lt 1 ]; then
        echo "FAIL: $f never calls EALIGN_RSP_16 — its Mach-O landing inherits the entry"
        echo "      alignment instead of establishing it. Both x86 forks carry this landing"
        echo "      and only src/main_x86_macho.cyr is the compiler Intel Macs actually run."
        exit 1
    fi
    # `|| true` on both: under `bash -eo pipefail` a grep that matches nothing fails the
    # whole pipeline and would abort the gate with NO diagnostic — a silent red is worse
    # than the FAIL below, which names the file and the two line numbers.
    park=$(grep -n '0xE78949' "$ROOT/$f" 2>/dev/null | head -1 | cut -d: -f1 || true)
    alg=$(grep -n 'EALIGN_RSP_16(S)' "$ROOT/$f" 2>/dev/null | head -1 | cut -d: -f1 || true)
    if [ -z "$park" ] || [ -z "$alg" ] || [ "$alg" -lt "$park" ]; then
        echo "FAIL: $f aligns rsp BEFORE parking it in r15 (park line ${park:-none}, align"
        echo "      line ${alg:-none}). The park is what preserves the kernel's argc/argv"
        echo "      block; aligning first hands argc() a pointer 8 bytes below argc."
        exit 1
    fi
done

echo "PASS: all $rowtot call-site rows are 16-byte aligned (direct args 1-9, >6-arg marshalling at both"
echo "      parities, store64, every operator class, f64_exp, nesting, an inherited frame,"
echo "      fncallN/callptr, and \`await\` under CYRIUS_ASYNC=1); the deliberately-misaligned"
echo "      control still reads 8; the ENTRY BASE holds across all $sw_runs argv0-length/env-size"
echo "      combinations; and the x86 Mach-O landing establishes alignment rather than"
echo "      inheriting it, in BOTH forks, after the r15 park (6.6.5)"
exit 0
