# A narrow parameter (`y: u8`, `y: i16`, `y: i32`) holds the caller's whole word, unnarrowed — `wid(0x1FF)` with `y: u8` reads 511, and `y += 1` of an `i16` 32767 is 32768 — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S5) while landing D21 (`*(&x)` of a narrow
integer x at its width): a narrow parameter's own read is its whole slot word, so `*(&y)` of one keeps the word too (as
y itself). Pre-existing: the same output on the lane's compiler before S5 (45135d7db) and after it; x86_64, aarch64
(qemu), cx (cxvm) and PE (wine) alike. Not D21's filed surface (D21 makes `*(&x)` read as x does), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Medium — a silent wrong value: a narrow parameter holds values outside its type (511 in a `u8`), and
arithmetic on it does not wrap at its width as a narrow local's does (`y += 1` of an `i16` 32767 is 32768 in a
parameter, -32768 in a local). Not a security id (the developer's own source).
**Kind:** bug, possibly a decision — where the narrowing happens (the callee's entry, every store into the parameter,
or every read of it) changes what a program computes.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
fn wid(y: u8): i64 { return y; }
fn w32(y: i32): i64 { return y; }
fn inc(y: i16): i64 { y += 1; return y; }
fn inc_l(a: i16): i64 { var y: i16 = a; y += 1; return y; }
fn main(): i64 {
    pr(wid(0x1FF));          # a u8 holds 0..255
    pr(w32(0x1FFFFFFFF));    # an i32 holds -2^31..2^31-1
    pr(inc(0x7FFF));         # i16 32767 + 1
    pr(inc_l(0x7FFF));       # the same through an i16 local
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < np.cyr > np; ./np          (rc 0, no diagnostic; aarch64 / cx / PE print the same)
511 8589934591 32768 -32768
                                          # the fourth, through an i16 local, wraps at 16 bits; the parameter does not
```

## Root cause

A parameter is registered with SLTYPE 0 (src/frontend/parse_fn_def.cyr, the parameter loop: `SLTYPE(S, li, 0)`, a
struct's sid only), so its read is the 8-byte slot load (`EFLLOAD`) and its stores (`y = v`, `y += 1`) are word stores;
nothing narrows the argument at the call or at the callee's entry. A narrow local carries SLTYPE 1 / 2 / 4 and the
signed slice-width mark (v6.3.35), so its read is `EFLLOAD_W` sign- or zero-extended and its stores write its width.

## Fix direction

The user's call if it changes what a program computes: give a narrow parameter its local's typing (SLTYPE width + the
sign mark, so reads extend and stores write its width — the argument's high bytes are then ignored), or narrow the
argument at the call. Rows: the four lines above, a `*(&y)` read and store (D21: as y), every width and sign, on
x86_64 / aarch64 / cx / PE (a register-passed and a stack-passed parameter).
