# A zero-size struct value into a struct-typed FIELD (`o.s = GP`, `o.s = gp()`, `o.s = (GP)`, `o.s = mk()`) or a zero-size `*p` used as a value still moves an 8-byte word: the field's neighbour is clobbered, and `take(*p)` reads 8 bytes past the object — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct` @ `d2dd38fa`), x86_64 and
aarch64 (a `cycc_aarch64` built from `src/main_aarch64.cyr`, run under qemu-aarch64), and against the lane base
(`5fb211da:build/cycc`): the same on every leg for the rows below, so it is **pre-existing**, not a lane regression.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane's review (the struct-field-destination and deref-store bites gave
their sibling arms `_agc_ptr_global` and `_dst_struct` a zero-size arm, `_ps_is_sz` (ac419c94), but not this one).
**Severity:** P2 — silent neighbour clobber (a field) or an 8-byte over-read (a dereference), zero-size structs only.
Not a security id: the developer's own source.

## Reproduction

```sh
cat > zs.cyr <<'X'
struct E { }
struct O { s: E; n: i64; }
var GE = E { };
var GP: *E = &GE;
fn gp(): *E { return &GE; }
fn mk(): E { var e: E; return e; }
X
row() { { cat zs.cyr; printf '%s\n' "$2"; } | build/cycc > zs.bin 2>/dev/null \
  && chmod +x zs.bin && { ./zs.bin; echo "$1: exit $?"; } }
row "o.s = GP                  " 'fn main(): i64 { var o: O; o.n = 77; o.s = GP; return o.n; } syscall(60, main());'
row "o.s = gp()                " 'fn main(): i64 { var o: O; o.n = 77; o.s = gp(); return o.n; } syscall(60, main());'
row "o.s = (GP)                " 'fn main(): i64 { var o: O; o.n = 77; o.s = (GP); return o.n; } syscall(60, main());'
row "o.s = mk()                " 'fn main(): i64 { var o: O; o.n = 77; o.s = mk(); return o.n; } syscall(60, main());'
row "control o.s = p (*E local)" 'fn main(): i64 { var o: O; o.n = 77; var p: *E = &GE; o.s = p; return o.n; } syscall(60, main());'
row "control o.s = *GP         " 'fn main(): i64 { var o: O; o.n = 77; o.s = *GP; return o.n; } syscall(60, main());'
row "control o.s = l (E local) " 'fn main(): i64 { var o: O; o.n = 77; var l: E; o.s = l; return o.n; } syscall(60, main());'
```

Actual (x86_64; aarch64 under qemu the same; the lane base the same except `o.s = *GP`, which the lane fixed):

```
o.s = GP                  : exit 0
o.s = gp()                : exit 0
o.s = (GP)                : exit 0
o.s = mk()                : exit 0
control o.s = p (*E local): exit 77
control o.s = *GP         : exit 77
control o.s = l (E local) : exit 77
```

Expected: 77 on every row — a zero-size struct copies no bytes, so `o.n` is untouched.

The dereference as a VALUE (an `E` that ends a mapping):

```sh
cat > zsd.cyr <<'X'
include "lib/syscalls.cyr"
struct E { }
fn take(e: E): i64 { return 65; }
fn pe(): *E {                                         # an E at the very end of a mapping
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    syscall(SYS_MUNMAP, m + 4096, 4096);
    return m + 4096;
}
fn run(): i64 { var p: *E = pe(); return take(*p); }
syscall(SYS_EXIT, run());
X
build/cycc < zsd.cyr > zsd.bin && chmod +x zsd.bin && ./zsd.bin; echo "exit $?"
```

Actual: `exit 139` (x86_64, aarch64 under qemu, and the lane base). Expected: 65. Control: `var l: E = *p; return 65;`
in the same `run` gives 65.

## Root cause

- **`o.s = GP` / `gp()` / `(GP)`** — `_fsc_psrc` (`src/frontend/parse_decl.cyr`, 6.7.11): after parsing the source it
  checks `if (_ps_step(GPSC(S)) != STRUCTSZ(S, ft - 1)) { return 2; }`, and 2 falls back to the VALUE store (the
  pointer's 8-byte word into the field). `_tn_ptr_step` steps a T of no bytes by 8, so for a zero-size struct the step
  is 8 and the size 0: the fallback is always taken. The sibling arms answer this with `_ps_is_sz(st, sz)`
  (`src/frontend/parse.cyr`: `sz`, or 8 for a zero-size one); this arm needs the same test.
- **`o.s = mk()`** — a by-value zero-size call result into a field takes a separate path (not `_fsc_psrc`), which also
  stores the word; not traced further here.
- **`*p` as a value** — `_deref_small` (`src/frontend/parse_expr.cyr`, 6.7.11) reads a struct byte-exact only for
  steps 1..7 (`if (st < 1) { return 0; }`); a zero-size struct's step is 8, so the operand stays the 8-byte word load
  at `p`.
