# `CYRIUS_IR=3`: an f64 field store through a `*T` (`q.f = 2.5;`) SIGSEGVs — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-1, `b22a650bf`: under `CYRIUS_IR=3`, a float literal's `movabs` (`EMIT_FLOAT_LIT`, src/backend/x86/float.cyr) records `IR_RAW_EMIT`, as `EF32_FROM` / `EF32_TO` have since 6.7.6, so LASE no longer drops the reload after it. No decision needed (a codegen defect). The filed repro exits 1 under IR=3 (was 139); `g(2.5, a)` 7 (was 0); `g2(a, 0.5, a)` 44 (was 40); IR=0 / IR=1 1 as before. The root cause was the literal, not a field emit as this file guessed. The default pipeline is byte-identical (the 635-file corpus at IR=0). Rows: `struct_value_codegen.sh` IF1 / IF2 (the filed repros verbatim, under IR=3) and the values file's group V (V1 - V5) on every A leg (FLOORA 235 -> 240); `call_ptr_field_store.sh`'s IR=3 leg runs the whole values file (its `IR3-PRE` exclusion removed). Mutation (the fix reverted): RED IF1, IF2, A3 and R1's IR=3 leg. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 structs lane (unit S4): the new
tests/tcyr/crossos/call_ptr_field_store.tcyr's f64 row (`gp().f = 2.5;`) faults under `CYRIUS_IR=3` only; the same store
through a `*H` local faults the same way with the lane's base compiler (44ab2052, before this unit's changes), so it is
pre-existing. The gate (tests/gates/frontend/call_ptr_field_store.sh) leaves that row (marked `IR3-PRE`) out of its
IR=3 leg. x86_64 only (IR=3 is an x86 pipeline).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — a SIGSEGV on valid code, but only under the opt-in `CYRIUS_IR=3` (no release build uses it).
**Kind:** codegen (IR=3).

## Repro

```cyrius
struct H { n; m; f: f64; }
var buf[32];
fn go(): i64 { var q: *H = &buf; q.f = 2.5; return 1; }
syscall(60, go());
```

```
CYRIUS_IR=3 build/cycc < r.cyr > r && ./r; echo $?    # 139 (SIGSEGV); want 1
            build/cycc < r.cyr > r && ./r; echo $?    # 1
CYRIUS_IR=1 build/cycc < r.cyr > r && ./r; echo $?    # 1
```

The same with the lane's base compiler (44ab2052). `q.n = 2;` (an i64 field) in its place exits 1 under IR=3, as does
`var x: f64 = 2.5; store64(&buf, x);`.

## Root cause (not yet traced)

Likely the class of issues/archived/2026-10-08-ir3-drops-unrecorded-field-emits.md: IR=3's passes patch the emitted code from the
IR record, and a field-store emit without a record (here the f64 constant's move into the store through the parked
pointer, or the `EFLADDR_X1`-style address set-up) is removed or misplaced, so the store goes through a stale register.
