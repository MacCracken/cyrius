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
# rebuilt from the same mutated tree), gate run with CC=it. Numbers are bad rows (of 66 for M*):
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
# bite 14b (rows 67-106, enum variants of 6..10 fields — one row per field):
#   B0 the pre-fix ctor total `0`                           -> RED  x86 10 (fields 7+) · aarch64 SIGILL (no R
#                                                                  line); cx + wine green, correctly: neither
#                                                                  formula reads the total
#   B1 total off by one (`ctor_arity + 1`)                  -> RED  x86 10 · aarch64 10
# bite 14a (rows 107-154, the struct-valued `var` receives; cx has only the 24 >16 B ones; the
# counts below were taken before 14b's rows existed, when these were rows 67-114):
#   A0 the pre-bite-14 frontend (HEAD 3e35aed2's parse_*)   -> RED  x86 48 · aarch64 48 · cx 24 · wine crash
#   A1 only the `asv` (>16 B) loop back to PCMPE+EPUSHR     -> RED  x86 24 · aarch64 24 · cx 24 · wine crash
#   A2 `_call_arg_one` loses its SIMD arm                   -> RED  x86 48 · aarch64 48 · cx 24 (wine green:
#                                                                  PE vectors go by pointer, mask is 0)
#   A3 `_call_arg_one` loses its struct-address arm         -> RED  wine only (crash) — the PE vector pointer
# bite 14c (rows 155-176, struct-valued calls outside a `var` initializer; cx rows 131-144):
#   C0 the pre-14c frontend (commit d68d6f15's parse_*)     -> RED  x86/aarch64 SIGSEGV · cx 14 · wine crash
#   C1 PARSE_FNCALL loses its retptr-temp path              -> RED  x86/aarch64 SIGSEGV · cx 6 · wine crash
#   C2 the tail-call path no longer diverts retptr calls    -> RED  x86 SIGSEGV · aarch64 2 · cx 4 · wine crash
#   C3 no `_try_struct_call_assign` (first word only)       -> RED  x86 8 · aarch64 8 · cx 4 · wine 8
#   C4 no struct-valued-call arm in the struct-param push   -> RED  x86/aarch64 SIGSEGV · cx 2 · wine crash
# bite 14 review (the refusal section at the end — x86 / aarch64 / win64 compilers):
#   R0 the four PE vector-retptr loops as committed in 14a (HEAD 76a5a614) -> RED [arity/win64] COMPILED
#   R1 only `_try_vector_call_assign` back to its own loop                 -> RED [arity/win64] 3 times, want 4
#   R2 the struct-param arm's top level back to a bare `return 0`         -> RED [toplevel-arg/x86,aarch64,win64]
#                                                                             1 times, want 2
# bite 14 review — method calls and overloaded operators returning a struct (rows 177-212, cx 145-167):
#   F0 the frontend as of 6d2f483f (no method/operator dest.)  -> RED  probe refused (return rows) · top-level
#                                                                  method/operator probe COMPILED
#   F1 `_sc_pre` never makes a temp                         -> RED  probe refused · top-level 4 of 7
#   F2 `x = <method/op>` back to the plain store            -> RED  x86 10 · aarch64 10 · cx 5 · wine 10
#   F3 struct-param arm pushes the value, not the temp       -> RED  x86/aarch64 SIGSEGV · cx 3 · wine crash
#   F4 `_sc_var_receive` never matches                      -> RED  probe refused (untyped `.z`)
#   F4c a typed `var` takes the first word                  -> RED  x86/aarch64 SIGSEGV · cx 7 · wine crash
#   F5 an 8 B by-value lhs not parked under the retptr      -> RED  x86 1 · cx 1 · wine 1 (aarch64 green:
#                                                                  its retptr is X8, nothing to park)
#   F6 a 9-16 B result never stored for a destination       -> RED  x86/aarch64 SIGSEGV · wine crash (cx has
#                                                                  no pair rows)
#   F7 no aarch64 X8 load                                   -> RED  aarch64 SIGSEGV only, correctly
#   F8 `_sc_global_receive` never refuses                   -> RED  [toplevel-method-op] 5 times, want 7
#   real tree                                              -> GREEN on all four legs (~5 s)
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: stack_param_homing_matrix: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
ulimit -c 0 2>/dev/null || true
ROWS_FLOOR=212      # every leg but cx
ROWS_CX_FLOOR=167   # cx: no 9-16 B rax:rdx rows (see gen)
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
    # 6.6.6 bite 14b — an enum variant constructor with 6..10 fields, every field read back.
    # The ctor homed its stack-passed fields with a caller total of 0, so on x86 SysV field 7
    # read the ctor frame slot of field 5 and on aarch64 the negative offset corrupted the `ldr`
    # encoding (SIGILL). A heap variant calls `alloc`: the probe brings a bump allocator, since it
    # has no stdlib. Values are distinct two-digit literals, so a field read from its neighbour
    # cannot match.
    split("11 23 35 47 59 62 74 86 98 13", ev, " ")
    p("var HEAP[1024];")
    p("var HP = 0;")
    p("fn alloc(n): i64 { var q = &HEAP + HP; HP = HP + ((n + 7) / 8) * 8; return q; }")
    for (n = 6; n <= 10; n++) {
      fl = ""; ea = ""
      for (i = 0; i < n; i++) { fl = fl (i ? ", " : "") "f" i; ea = ea (i ? ", " : "") ev[i + 1] }
      p("enum EW" n " { W" n "(" fl "); }")
      emk[n] = "var E" n " = W" n "(" ea ");"
      for (i = 0; i < n; i++) { row++; call[row] = "chk(" row ", load64(E" n " + " (8 + i * 8) "), " ev[i + 1] ");" }
    }
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
    # 6.6.6 bite 14c — a struct-valued call anywhere BUT a `var` initializer: only that form had a
    # destination, so a >16 B (retptr) callee called elsewhere wrote through argument 1 (x86
    # SIGSEGV; aarch64 through a stale X8) and a 9-16 B one lost rdx. Each shape at 2 and 7 int
    # args (7 + the x86 retptr puts two on the stack). A struct VALUE used as a scalar is its
    # first word, as a struct local is (`h(r)`, `var k = r`), so the i64 shapes read field x.
    p("var LAST = 0;")
    p("var GS = P3 { 0, 0, 0 };")
    p("var GQ = P2 { 0, 0 };")
    p("fn hs(q: P3): i64 { return q.z; }")
    if (pair) p("fn hy(q: P2): i64 { return q.y; }")   # the rdx half: what a lost pair drops
    p("fn hu(q): i64 { return q; }")
    for (ni = 1; ni <= 2; ni++) {
      n = (ni == 1) ? 2 : 7
      sig = ""; args = ""; body = "0"; want = ""
      for (i = 0; i < n; i++) {
        sig = sig (i ? ", " : "") "a" i; args = args (i ? ", " : "") dig[i + 1]
        body = body " + a" i " * " pow10(n - 1 - i); want = want dig[i + 1]
      }
      # x AND z carry the value: the i64 shapes read x (the first word), while the struct-valued
      # shapes read z — so an assignment that stored only the first word cannot pass.
      p("fn cq" n "(" sig "): P3 { var q: P3; q.x = " body "; q.y = 0; q.z = q.x; LAST = q.x; return q; }")
      p("fn rq" n "(): P3 { return cq" n "(" args "); }")
      p("fn ri" n "(): i64 { return cq" n "(" args "); }")
      row++; call[row] = "LAST = 0; cq" n "(" args "); chk(" row ", LAST, " want ");"
      row++; call[row] = "var T" row ": P3 = rq" n "(); chk(" row ", T" row ".z, " want ");"
      row++; call[row] = "chk(" row ", ri" n "(), " want ");"
      row++; call[row] = "chk(" row ", hs(cq" n "(" args ")), " want ");"
      row++; call[row] = "chk(" row ", hu(cq" n "(" args ")), " want ");"
      row++; call[row] = "var T" row ": P3 = cq" n "(" args "); T" row ".z = 0; T" row " = cq" n "(" args "); chk(" row ", T" row ".z, " want ");"
      row++; call[row] = "GS.z = 0; GS = cq" n "(" args "); chk(" row ", GS.z, " want ");"
      if (pair) {
        p("fn cp" n "(" sig "): P2 { var q: P2; q.x = 0; q.y = " body "; return q; }")
        p("fn rp" n "(): P2 { return cp" n "(" args "); }")
        row++; call[row] = "chk(" row ", hy(cp" n "(" args ")), " want ");"
        row++; call[row] = "var T" row ": P2 = cp" n "(" args "); T" row ".y = 0; T" row " = cp" n "(" args "); chk(" row ", T" row ".y, " want ");"
        row++; call[row] = "GQ.y = 0; GQ = cp" n "(" args "); chk(" row ", GQ.y, " want ");"
        row++; call[row] = "var T" row ": P2 = rp" n "(); chk(" row ", T" row ".y, " want ");"
      }
    }
    # 6.6.6 bite 14 review — a METHOD call and an overloaded OPERATOR returning a struct by value.
    # 14c gave every free-fn call a destination and missed the two paths that emit their own call:
    # the >16 B forms crashed with SIGSEGV (the callee took `self` / the lhs address as its retptr) and
    # `q = b.mp(..)` kept rax only. `self` carries a digit (MB0.v = 5), so a receiver displaced by
    # the retptr cannot pass; 7 args + self + the x86 retptr put three on the stack.
    p("struct MB { v; w; }")
    p("struct OV { x; y; z; }")
    p("struct ON { v; }")
    p("var MB0 = MB { 5, 0 };")
    p("var OA = OV { 0, 0, 7 };")
    p("var OB = OV { 0, 0, 3 };")
    p("var NA = ON { 4 };")
    p("var NB = ON { 2 };")
    p("fn OV_add(a, b): OV { var q: OV; q.x = load64(a + 16) * 10 + load64(b + 16); q.y = 0; q.z = q.x; return q; }")
    p("fn ON_add(a, b): OV { var q: OV; q.x = a * 10 + b; q.y = 0; q.z = q.x; return q; }")
    p("fn hov(q: OV): i64 { return q.z; }")
    p("fn rov(): OV { return OA + OB; }")
    if (pair) {
      p("struct OW { x; y; }")
      p("var WA = OW { 0, 9 };")
      p("var WB = OW { 0, 1 };")
      p("fn OW_add(a, b): OW { var q: OW; q.x = 0; q.y = load64(a + 8) * 10 + load64(b + 8); return q; }")
      p("fn how(q: OW): i64 { return q.y; }")
    }
    mimpl = "impl MkB for MB {"
    for (ni = 1; ni <= 2; ni++) {
      n = (ni == 1) ? 2 : 7
      sig = "self"; args = ""; body = "load64(self) * " pow10(n); want = "5"
      for (i = 0; i < n; i++) {
        sig = sig ", a" i; args = args (i ? ", " : "") dig[i + 1]
        body = body " + a" i " * " pow10(n - 1 - i); want = want dig[i + 1]
      }
      margs[n] = args; mwant[n] = want
      mimpl = mimpl " fn mk" n "(" sig "): P3 { var q: P3; q.x = " body "; q.y = 0; q.z = q.x; LAST = q.x; return q; }"
      if (pair) mimpl = mimpl " fn mp" n "(" sig "): P2 { var q: P2; q.x = 0; q.y = " body "; return q; }"
    }
    p(mimpl " }")
    for (ni = 1; ni <= 2; ni++) {
      n = (ni == 1) ? 2 : 7
      args = margs[n]; want = mwant[n]; mc = "MB0.mk" n "(" args ")"
      p("fn rm" n "(): P3 { return " mc "; }")
      row++; call[row] = "var T" row ": P3 = " mc "; chk(" row ", T" row ".z, " want ");"
      row++; call[row] = "LAST = 0; " mc "; chk(" row ", LAST, " want ");"
      row++; call[row] = "var T" row ": P3 = " mc "; T" row ".z = 0; T" row " = " mc "; chk(" row ", T" row ".z, " want ");"
      row++; call[row] = "chk(" row ", hs(" mc "), " want ");"
      row++; call[row] = "chk(" row ", hu(" mc "), " want ");"
      row++; call[row] = "var T" row " = " mc "; chk(" row ", T" row ".z, " want ");"
      row++; call[row] = "GS.z = 0; GS = " mc "; chk(" row ", GS.z, " want ");"
      row++; call[row] = "var T" row ": P3 = rm" n "(); chk(" row ", T" row ".z, " want ");"
      if (pair) {
        mc = "MB0.mp" n "(" args ")"
        p("fn rmp" n "(): P2 { return " mc "; }")
        row++; call[row] = "var T" row ": P2 = " mc "; chk(" row ", T" row ".y, " want ");"
        row++; call[row] = "var T" row ": P2 = " mc "; T" row ".y = 0; T" row " = " mc "; chk(" row ", T" row ".y, " want ");"
        row++; call[row] = "chk(" row ", hy(" mc "), " want ");"
        row++; call[row] = "GQ.y = 0; GQ = " mc "; chk(" row ", GQ.y, " want ");"
        row++; call[row] = "var T" row ": P2 = rmp" n "(); chk(" row ", T" row ".y, " want ");"
      }
    }
    row++; call[row] = "var T" row ": OV = OA + OB; chk(" row ", T" row ".z, 73);"
    row++; call[row] = "var T" row ": OV = OA + OB; T" row ".z = 0; T" row " = OA + OB; chk(" row ", T" row ".z, 73);"
    row++; call[row] = "chk(" row ", hov(OA + OB), 73);"
    row++; call[row] = "chk(" row ", hu(OA + OB), 73);"
    row++; call[row] = "var T" row ": OV = rov(); chk(" row ", T" row ".z, 73);"
    row++; call[row] = "var T" row " = OA + OB; chk(" row ", T" row ".z, 73);"
    row++; call[row] = "var T" row ": OV = NA + NB; chk(" row ", T" row ".z, 42);"   # an 8 B lhs by value, under the retptr
    if (pair) {
      row++; call[row] = "var T" row ": OW = WA + WB; chk(" row ", T" row ".y, 91);"
      row++; call[row] = "var T" row ": OW = WA + WB; T" row ".y = 0; T" row " = WA + WB; chk(" row ", T" row ".y, 91);"
      row++; call[row] = "chk(" row ", how(WA + WB), 91);"
    }
    p("fn main(): i64 {")
    for (c = 1; c <= nc; c++) {
      p("    var V" c ": " cls[c] ";")
      for (w = 0; w < cb[c]; w += 8) p("    store64(&V" c " + " w ", " cd[c] ");")
    }
    for (n = 6; n <= 10; n++) p("    " emk[n])
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

# ── refusals — every gap is a diagnostic, never a quiet miscompile ───────────────────────
# Run against EVERY compiler above (x86 native, aarch64, Win64 — whichever built). Each probe
# must be refused (non-zero exit) with the named diagnostic exactly `want` times, so one
# refused site cannot hide a silent one beside it.
nrefuse=0
refuse_on() {   # refuse_on <label> <compiler> <probe> <needle> <want-count>
    [ -s "$2" ] || return 0
    _rc=0; "$2" < "$3" > "$T/rf.out" 2> "$T/rf.err" || _rc=$?
    _n=$(grep -c "$4" "$T/rf.err" || true)
    if [ "$_rc" = 0 ]; then echo "  FAIL: [$1] COMPILED — it must be refused ('$4' x$5)"; fail=1; return; fi
    if [ "$_n" != "$5" ]; then
        echo "  FAIL: [$1] refused with '$4' $_n times, want $5:"; grep -m4 '^error' "$T/rf.err" | sed 's/^/      /'; fail=1; return
    fi
    nrefuse=$((nrefuse + 1))
}
refuse_all() {  # refuse_all <label> <probe> <needle> <want-count>
    refuse_on "$1/x86" "$CC" "$2" "$3" "$4"
    refuse_on "$1/aarch64" "$T/cc_a64" "$2" "$3" "$4"
    refuse_on "$1/win64" "$T/cc_win" "$2" "$3" "$4"
}
# 6.6.6 bite 14 review — the four Win64-only own-calls (a 16/32-byte vector returned through a
# retptr: `var v: f64v2 = f(..)`, `v = f(..)`, `var w: f64v4 = f(..)`, `return f(..)` in a vector
# fn) marshalled their arguments in a private loop with NO arity check, so all four built clean
# on PE while x86/aarch64 refused them. Mutation: route any one back to its old loop -> RED
# [arity/win64] ("... 3 times, want 4").
cat > "$T/ra.cyr" <<'EOF'
fn vf(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn vf4(a, b): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, a); store64(&v + 24, b); return v; }
fn vr(a): f64v2 { return vf(a); }
fn main(): i64 {
    var v: f64v2 = vf(1);
    v = vf(3);
    var w: f64v4 = vf4(1);
    return load64(&v);
}
var e = main();
syscall(60, e);
EOF
refuse_all arity "$T/ra.cyr" "expects 2 arguments, got 1" 4
# 6.6.6 bite 14 review — a struct-valued call passed to a by-value struct param at TOP LEVEL,
# where there is no frame to hold the result. The retptr (>16 B) form was refused; the rax:rdx
# (9-16 B) form fell through the same arm and compiled clean — SIGSEGV. Mutation: the nx==10
# arm's top-level `return 0` without `_refuse_toplevel_pair_arg` -> RED ("1 times, want 2").
cat > "$T/rt.cyr" <<'EOF'
struct P3 { x; y; z; }
struct P2 { x; y; }
fn p2(a, b): P2 { var q: P2; q.x = a; q.y = b; return q; }
fn s3(a, b): P3 { var q: P3; q.x = a; q.y = b; q.z = a + b; return q; }
fn hy(q: P2): i64 { return q.y; }
fn hs(q: P3): i64 { return q.z; }
var k = hy(p2(1, 2));
var j = hs(s3(1, 2));
syscall(60, k + j);
EOF
refuse_all toplevel-arg "$T/rt.cyr" "returns a struct by value" 2
# 6.6.6 bite 14 review — the METHOD and OPERATOR forms at top level: a >16 B result is refused by
# the call itself (`_sc_pre`), a 9-16 B one by each destination that needs storage (typed `var`,
# assignment, struct param). Untyped `var u = b.mp(6)` keeps the first word and must NOT count.
# Mutation: `_sc_global_receive` never refuses -> RED ("6 times, want 7").
cat > "$T/rm.cyr" <<'EOF'
struct P3 { x; y; z; }
struct P2 { x; y; }
struct B { v; w; }
struct V3 { x; y; z; }
struct V2 { x; y; }
impl Mk for B {
  fn mk(self, a): P3 { var p: P3; p.x = load64(self) + a; p.y = 0; p.z = p.x; return p; }
  fn mp(self, a): P2 { var p: P2; p.x = 1; p.y = load64(self) + a; return p; }
}
fn V3_add(a, b): V3 { var p: V3; p.x = 0; p.y = 0; p.z = load64(a + 16) + load64(b + 16); return p; }
fn V2_add(a, b): V2 { var p: V2; p.x = 0; p.y = load64(a + 8) + load64(b + 8); return p; }
fn hy(q: P2): i64 { return q.y; }
var bb = B { 40, 0 };
var A = V3 { 1, 2, 3 };
var E = V2 { 1, 2 };
var GQ = P2 { 0, 0 };
bb.mk(1);
var G1: P3 = bb.mk(2);
var G2: P2 = bb.mp(3);
GQ = bb.mp(4);
var k = hy(bb.mp(5));
var C: V3 = A + A;
var D: V2 = E + E;
var u = bb.mp(6);
syscall(60, u);
EOF
refuse_all toplevel-method-op "$T/rm.cyr" "returns a struct by value" 7
# Floor: the x86 compiler always runs, so every probe above must have counted at least once.
REFUSE_FLOOR=3
if [ "$nrefuse" -lt "$REFUSE_FLOOR" ]; then echo "  FAIL: only $nrefuse refusal cases ran (floor $REFUSE_FLOOR)"; fail=1; fi
echo "  ok:   refusals — $nrefuse compiler x probe cases named their diagnostic"

if [ "$fail" != 0 ]; then echo "FAIL stack_param_homing_matrix"; exit 1; fi
echo "PASS stack_param_homing_matrix: $(cat "$T/rows") generated rows ($ROWS_CX on cx) — 4 vector classes x 3 positions x 5..9 int args, 2 vectors + 7 ints, struct return x 5..9, vector args into struct-valued var receives, enum variants of 6..10 fields, struct-valued calls outside a var initializer, method calls and overloaded operators returning a struct — bind every argument on every leg that ran; $nrefuse refusal cases named"
