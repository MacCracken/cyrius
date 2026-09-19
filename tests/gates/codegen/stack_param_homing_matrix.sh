#!/bin/sh
# tests/gates/codegen/stack_param_homing_matrix.sh — 6.6.6
#
# ⛔ THE DEFECT CLASS. A call has two halves that must agree on where every argument is. The
# CALLER counts int-class arguments (`_fc_int_argc`, `m_int_argc`, `asv_argc`) and marshals
# that many into the int registers + stack; value-form vectors go to XMM/V (SysV/aarch64) or
# BY POINTER into an int slot (Win64). The CALLEE's parameter loop homes the in-register ones
# and, past the register ceiling, must home each remaining int parameter from (its int-class
# ordinal) into (its own frame slot), with the stack position counted down from (the caller's
# int-class TOTAL). Until 6.6.6 that last step re-derived all three from `pc`, the ALL-class
# parameter count, so every vector parameter and every x86 retptr desynchronised it:
#   `n6(v, 1,2,3,4,5,6)` -> 123406, `f7(0,1,2,v,3,4,5,6)` -> 9123060, `mk6(1..6)` -> 4379076
# (the sixth parameter read the return address). Silent — exit 0, no diagnostic.
#
# ⭐ WHY A GENERATED MATRIX. The drift is a property of (vector class x vector position x int
# count x retptr), and a hand-picked list is exactly what the pre-fix corpus was: 323 .tcyr
# files, none of which put a vector next to six ints. Every row here is generated, and every
# expected value is built by awk as a STRING OF DIGITS — the literals written side by side —
# while the compiled callee computes it ARITHMETICALLY (sum of digit * 10^k). The two paths
# share nothing but the literals.
#
# ⭐ WHY EVERY BACKEND. The convention past the ceiling is different on each: SysV (vector in
# XMM, ints on an 8-byte stack counted from the total), aarch64 (V-regs, cyrius's 6 int regs,
# 16-byte stack slots), Win64 (vector by pointer IN an int slot, so it shifts the ints; stack
# read at a fixed shadow offset that ignores the total), cx (every int arg in r3.., vectors in
# r16..). x86 runs natively; aarch64 under qemu-user and PE under wine are EMULATION, NOT
# hardware (SKIP when absent); cx runs on cxvm. The hardware legs are
# tests/tcyr/crossos/simd_param_int_stack_args.tcyr on ecb / ach / cass / pi.
#
# ⚠ ANTI-VACUOUS FLOORS: the generated row count must clear ROWS_FLOOR, and each leg's program
# must PRINT that same count at runtime (a probe that stops early or never runs its rows cannot
# pass). A leg whose compiler or program fails to build is a FAIL, never a skip.
#
# MUTATION LEDGER — each mutant a cycc BUILT from mutated source (the per-target compilers
# rebuilt from the same mutated tree), gate run with CC=it. Numbers are bad rows of 66:
#   M0 the pre-6.6.6 PARSE_FN_DEF (6.6.5 as tagged)       -> RED  x86 53 · aarch64 49 · cx 45 · wine 49
#   M1 `_stkp_flush(S, int_pc)` — retptr dropped from the
#      int-class total                                     -> RED  x86 4 (the 6..9-arg struct returns);
#                                                                  the other legs stay green, correctly:
#                                                                  aarch64's retptr is X8, Win64's stack
#                                                                  formula ignores the total, cx is regs
#   M2 the SysV/aarch64 vector branch also bumps `int_pc`
#      (callee counts the vector, caller does not)         -> RED  x86 53 · aarch64 53 · cx 41 (wine
#                                                                  green: its vector IS an int slot)
#   M3 drop the `_stkp_defer` call (never home the stack)  -> RED  x86 40 · aarch64 38 · cx 39 · wine 48
#   M4 the Win64 vector branch forgets `int_pc + 1`        -> RED  wine only (probe crashes, no R line)
# bite 14a (rows 67-114, the struct-valued `var` receives; cx has only the 24 >16 B ones):
#   A0 the pre-bite-14 frontend (HEAD 3e35aed2's parse_*)   -> RED  x86 48 · aarch64 48 · cx 24 · wine crash
#   A1 only the `asv` (>16 B) loop back to PCMPE+EPUSHR     -> RED  x86 24 · aarch64 24 · cx 24 · wine crash
#   A2 `_call_arg_one` loses its SIMD arm                   -> RED  x86 48 · aarch64 48 · cx 24 (wine green:
#                                                                  PE vectors go by pointer, mask is 0)
#   A3 `_call_arg_one` loses its struct-address arm         -> RED  wine only (crash) — the PE vector pointer
#   real tree                                              -> GREEN on all four legs (~5 s)
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
ulimit -c 0 2>/dev/null || true
ROWS_FLOOR=114      # every leg but cx
ROWS_CX_FLOOR=90    # cx: no 9-16 B rax:rdx rows (see gen)
fail=0

# ── generate the probe ────────────────────────────────────────────────────────────────────
# Vector classes: name, bytes. Every 8-byte word of a vector holds the same digit, and each
# callee leads with (first word, last word) — so a lost upper half (f64v4's second XMM) shows.
# `pair=1` adds the rows whose callee returns a 9-16 B struct in rax:rdx — cx refuses that ABI
# outright (a compile error, not a miscompile), so the cx leg runs the `pair=0` variant.
gen() {
awk -v out="$1" -v rowsf="$2" -v pair="$3" '
function p(s) { print s > out }
BEGIN {
    nc = 4
    cls[1] = "f64v2"; cb[1] = 16; cd[1] = 3
    cls[2] = "f32v4"; cb[2] = 16; cd[2] = 4
    cls[3] = "i32v4"; cb[3] = 16; cd[3] = 5
    cls[4] = "f64v4"; cb[4] = 32; cd[4] = 6
    split("7 3 9 1 8 2 6 4 5", dig, " ")
    p("struct P3 { x; y; z; }")
    p("struct P2 { x; y; }")
    p("var BAD = 0;")
    p("var RAN = 0;")
    # write `tag` then a 3-digit number and a newline (no stdlib: this runs on cx too)
    p("fn wr(tag, k): i64 { var d[8]; store8(&d, tag); store8(&d + 1, 48 + k / 100); store8(&d + 2, 48 + k / 10 - (k / 100) * 10); store8(&d + 3, 48 + k - (k / 10) * 10); store8(&d + 4, 10); syscall(1, 1, &d, 5); return 0; }")
    p("fn chk(row, got, want): i64 { RAN = RAN + 1; if (got != want) { BAD = BAD + 1; wr(70, row); } return 0; }")
    row = 0
    # vector rows: class x position x int count
    for (c = 1; c <= nc; c++) {
      for (pos = 0; pos < 3; pos++) {
        for (n = 5; n <= 9; n++) {
          row++
          vp = (pos == 0) ? 0 : (pos == 1) ? 2 : n      # first / after int 2 / after every int
          sig = ""; body = ""; args = ""; want = ""
          last = cb[c] - 8
          lead = "(load64(&v) * 10 + load64(&v + " last "))"
          k = 0
          for (i = 0; i <= n; i++) {
            if (i == vp) {
              sig = sig (sig == "" ? "" : ", ") "v: " cls[c]
              args = args (args == "" ? "" : ", ") "V" c
            }
            if (i < n) {
              sig = sig (sig == "" ? "" : ", ") "a" i
              args = args (args == "" ? "" : ", ") dig[i + 1]
            }
          }
          # callee: lead * 10^n + sum a_i * 10^(n-1-i)   (arithmetic)
          body = lead " * " pow10(n)
          for (i = 0; i < n; i++) body = body " + a" i " * " pow10(n - 1 - i)
          p("fn r" row "(" sig "): i64 { return " body "; }")
          # expected: the digits written side by side   (string)
          want = cd[c] "" cd[c]
          for (i = 0; i < n; i++) want = want dig[i + 1]
          call[row] = "chk(" row ", r" row "(" args "), " want ");"
        }
      }
    }
    # two vectors, 7 ints, interleaved
    row++
    p("fn r" row "(a0, v: f64v2, a1, a2, u: f64v4, a3, a4, a5, a6): i64 { return load64(&v + 8) * 1000000000 + load64(&u + 24) * 100000000 + a0 * 1000000 + a1 * 100000 + a2 * 10000 + a3 * 1000 + a4 * 100 + a5 * 10 + a6; }")
    call[row] = "chk(" row ", r" row "(" dig[1] ", V1, " dig[2] ", " dig[3] ", V4, " dig[4] ", " dig[5] ", " dig[6] ", " dig[7] "), " cd[1] "" cd[4] "0" dig[1] dig[2] dig[3] dig[4] dig[5] dig[6] dig[7] ");"
    # retptr rows: struct return, 5..9 int args (x86 SysV puts the retptr in int arg 0)
    for (n = 5; n <= 9; n++) {
      row++
      sig = ""; args = ""; body = "0"; want = ""
      for (i = 0; i < n; i++) {
        sig = sig (i ? ", " : "") "a" i
        args = args (i ? ", " : "") dig[i + 1]
        body = body " + a" i " * " pow10(n - 1 - i)
        want = want dig[i + 1]
      }
      p("fn r" row "(" sig "): P3 { var q: P3; q.x = " body "; q.y = 0; q.z = 0; return q; }")
      sret[row] = n; sargs[row] = args; swant[row] = want
    }
    # 6.6.6 bite 14a — a vector argument to a STRUCT-VALUED `var` receive (`var s: P3 = f(..)`,
    # the >16 B retptr path, and `var s: P2 = f(..)`, the 9-16 B rax:rdx path). Those two loops
    # pushed every argument as an int, so the vector shifted the ints and the callee read a stale
    # XMM0/V0. `clob` loads every vector register with 8s first, so a stale read cannot pass by
    # luck (without it XMM0 often still holds the right vector). 2 and 7 ints: with the x86 retptr
    # as int arg 0, 7 user ints put two on the stack.
    p("fn clob(a: f64v4, b: f64v4, c: f64v4, d: f64v4): i64 { return 0; }")
    for (k = 1; k <= 1 + pair; k++) {
      st = (k == 1) ? "P3" : "P2"
      for (c = 1; c <= nc; c++) {
        for (pos = 0; pos < 3; pos++) {
          for (ni = 1; ni <= 2; ni++) {
            n = (ni == 1) ? 2 : 7
            row++
            vp = (pos == 0) ? 0 : (pos == 1) ? int(n / 2) : n
            sig = ""; args = ""
            for (i = 0; i <= n; i++) {
              if (i == vp) { sig = sig (sig == "" ? "" : ", ") "v: " cls[c]; args = args (args == "" ? "" : ", ") "V" c }
              if (i < n) { sig = sig (sig == "" ? "" : ", ") "a" i; args = args (args == "" ? "" : ", ") dig[i + 1] }
            }
            body = "(load64(&v) * 10 + load64(&v + " (cb[c] - 8) ")) * " pow10(n)
            for (i = 0; i < n; i++) body = body " + a" i " * " pow10(n - 1 - i)
            p("fn r" row "(" sig "): " st " { var q: " st "; q.x = " body "; q.y = 0; " (k == 1 ? "q.z = 0; " : "") "return q; }")
            want = cd[c] "" cd[c]
            for (i = 0; i < n; i++) want = want dig[i + 1]
            recv[row] = st; rargs[row] = args; rwant[row] = want
          }
        }
      }
    }
    p("fn main(): i64 {")
    for (c = 1; c <= nc; c++) {
      p("    var V" c ": " cls[c] ";")
      for (w = 0; w < cb[c]; w += 8) p("    store64(&V" c " + " w ", " cd[c] ");")
    }
    p("    var J: f64v4;")
    for (w = 0; w < 32; w += 8) p("    store64(&J + " w ", 8);")
    for (r = 1; r <= row; r++) {
      if (r in call) p("    " call[r])
      else if (r in recv) {
        p("    clob(J, J, J, J);")
        p("    var S" r ": " recv[r] " = r" r "(" rargs[r] ");")
        p("    chk(" r ", S" r ".x, " rwant[r] ");")
      }
      else { p("    var S" r ": P3 = r" r "(" sargs[r] ");"); p("    chk(" r ", S" r ".x, " swant[r] ");") }
    }
    p("    wr(82, RAN);")
    p("    return BAD;")
    p("}")
    p("var e = main();")
    p("syscall(60, e);")
    print row > rowsf
}
function pow10(k,   s, j) { s = "1"; for (j = 0; j < k; j++) s = s "0"; return s }
'
}
gen "$T/probe.cyr" "$T/rows" 1
gen "$T/probe_cx.cyr" "$T/rows_cx" 0
ROWS=$(cat "$T/rows")
ROWS_CX=$(cat "$T/rows_cx")
if [ "$ROWS" -lt "$ROWS_FLOOR" ] || [ "$ROWS_CX" -lt "$ROWS_CX_FLOOR" ]; then
    echo "  FAIL: stack_param_homing: generated only $ROWS / $ROWS_CX rows (floors $ROWS_FLOOR / $ROWS_CX_FLOOR) — the matrix shrank"; exit 1
fi

# run_leg <label> <program-file> <rows> <runner...>: the program must print exactly R<rows> and exit 0
run_leg() {
    _l=$1; _b=$2; ROWS=$3; RAN_WANT=$(printf 'R%03d' "$3"); shift 3
    if [ ! -s "$_b" ]; then echo "  FAIL: [$_l] the probe did not build (empty output)"; fail=1; return; fi
    _rc=0; "$@" "$_b" > "$T/out.$_l" 2>/dev/null < /dev/null || _rc=$?
    _ran=$(tr -d '\r' < "$T/out.$_l" | grep '^R[0-9][0-9][0-9]$' | tail -1 || true)
    _bad=$(tr -d '\r' < "$T/out.$_l" | grep -c '^F[0-9][0-9][0-9]$' || true)
    if [ "$_ran" != "$RAN_WANT" ]; then
        echo "  FAIL: [$_l] the probe reported '${_ran:-nothing}', want $RAN_WANT — rows did not all run (exit $_rc)"; fail=1; return
    fi
    if [ "$_rc" != 0 ] || [ "$_bad" != 0 ]; then
        echo "  FAIL: [$_l] $_bad of $ROWS rows bound an argument to the wrong parameter (exit $_rc); rows: $(grep '^F' "$T/out.$_l" | tr -d '\rF' | tr '\n' ' ' || true)"
        fail=1; return
    fi
    echo "  ok:   [$_l] $ROWS rows"
}
direct() { "$1"; }

# ── x86_64 SysV (native) ──────────────────────────────────────────────────────────────────
"$CC" < "$T/probe.cyr" > "$T/p.x86" 2> "$T/e.x86" || true
if grep -q '^error' "$T/e.x86"; then echo "  FAIL: [x86] probe refused:"; grep -m3 '^error' "$T/e.x86" | sed 's/^/      /'; fail=1
else chmod +x "$T/p.x86"; run_leg x86 "$T/p.x86" "$(cat "$T/rows")" direct; fi

# ── aarch64 (qemu-user — NOT hardware) ────────────────────────────────────────────────────
if command -v qemu-aarch64 > /dev/null 2>&1; then
    "$CC" < "$ROOT/src/main_aarch64.cyr" > "$T/cc_a64" 2> /dev/null && chmod +x "$T/cc_a64" || true
    if [ ! -s "$T/cc_a64" ]; then echo "  FAIL: [aarch64] could not build the aarch64 cross-compiler"; fail=1
    else "$T/cc_a64" < "$T/probe.cyr" > "$T/p.a64" 2> /dev/null || true; chmod +x "$T/p.a64"
         qa() { timeout 60 qemu-aarch64 "$1"; }; run_leg aarch64-qemu "$T/p.a64" "$(cat "$T/rows")" qa; fi
else echo "  SKIP: qemu-aarch64 not installed (aarch64 leg — pi/ecb hardware legs still cover it)"; fi

# ── cx (cxvm) ─────────────────────────────────────────────────────────────────────────────
"$CC" < "$ROOT/src/main_cx.cyr" > "$T/cc_cx" 2> /dev/null && chmod +x "$T/cc_cx" || true
"$CC" < "$ROOT/programs/cxvm.cyr" > "$T/cxvm" 2> /dev/null && chmod +x "$T/cxvm" || true
if [ ! -s "$T/cc_cx" ] || [ ! -s "$T/cxvm" ]; then echo "  FAIL: [cx] could not build cycc_cx / cxvm"; fail=1
else "$T/cc_cx" < "$T/probe_cx.cyr" > "$T/p.cyx" 2> /dev/null || true
     cxr() { timeout 60 "$T/cxvm" < "$1"; }; run_leg cx "$T/p.cyx" "$(cat "$T/rows_cx")" cxr; fi

# ── Win64 PE (wine — NOT hardware) ────────────────────────────────────────────────────────
if command -v wine > /dev/null 2>&1; then
    # A throwaway prefix, so nothing of the user's ~/.wine is read or written.
    export WINEPREFIX="$T/wine" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    "$CC" < "$ROOT/src/main_win.cyr" > "$T/cc_win" 2> /dev/null && chmod +x "$T/cc_win" || true
    if [ ! -s "$T/cc_win" ]; then echo "  FAIL: [win64] could not build the PE cross-compiler"; fail=1
    else "$T/cc_win" < "$T/probe.cyr" > "$T/p.exe" 2> /dev/null || true
         if [ "$(head -c 2 "$T/p.exe")" != "MZ" ]; then echo "  FAIL: [win64] probe is not a PE file"; fail=1
         else wr_() { timeout 180 wine "$1"; }; run_leg win64-wine "$T/p.exe" "$(cat "$T/rows")" wr_; fi
         wineserver -k > /dev/null 2>&1 || true
    fi
else echo "  SKIP: wine not installed (Win64 leg — the cass hardware leg still covers it)"; fi

if [ "$fail" != 0 ]; then echo "FAIL stack_param_homing_matrix"; exit 1; fi
echo "PASS stack_param_homing_matrix: $(cat "$T/rows") generated rows ($ROWS_CX on cx) — 4 vector classes x 3 positions x 5..9 int args, 2 vectors + 7 ints, struct return x 5..9, vector args into struct-valued var receives — bind every argument on every leg that ran"
