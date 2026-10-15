# A by-value `self` from a `*S` receiver, and a `*S` into a by-value `S` parameter, of a 3 / 5 / 6 / 7-byte struct carry FRAME GARBAGE in the word's padding (`_hl_pval_ra`'s temp is not zeroed) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct`, `42a0b63a`), x86_64:
both rows exit 255 (the 0xFF a previous call left in the frame); the dereference control exits 0.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S1). The dereference fix
(issues/archived/2026-10-12-small-struct-dereference-reads-past-the-object.md) reads a 3 / 5 / 6 / 7 B struct through
`_hl_pval_ra` — a byte copy into a frame temp, whose word is loaded — and found the temp's other bytes are whatever
the frame held. It added a `z` flag that zeroes the temp for the dereference (and its operator-operand reload); the
two other callers pass 0, unchanged, because changing what they compute was outside that issue's surface.
**Severity:** Low — no byte past the object is read (6.7.10 fixed that); the struct's own fields are right. The
padding is visible only to code that reads the word past `sizeof(S)` — `load8(&self + 3)`, `load64(&s)`, a hash or a
`memeq` over the 8-byte cell — and it is nondeterministic (whatever the frame held). Not a security id.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/pg.cyr <<'X'
struct S3 { a: i8; b: i8; c: i8; }
fn S3_pad(self: S3): i64 { return load8(&self + 3); }   # the byte after the struct, in the word it travels in
fn bs3(s: S3): i64 { return load8(&s + 3); }
fn dirty(): i64 { var a: i64[16]; var i = 0; while (i < 16) { a[i] = 0 - 1; i = i + 1; } return a[15]; }
fn r1(p: *S3): i64 { return p.pad(); }    # a by-value self from a *S3 receiver
fn r2(p: *S3): i64 { return bs3(p); }     # a *S3 into a by-value S3 parameter (6.7.10 decision 7)
fn r3(p: *S3): i64 { return bs3(*p); }    # control: a dereference (6.7.11: its padding 0)
fn main(): i64 {
    var s: S3; s.a = 1; s.b = 2; s.c = 3;
    dirty(); var x = r1(&s);
    dirty(); var y = r2(&s);
    dirty(); var z = r3(&s);
    return x * 10000 + y * 10 + z;
}
var m = main();
X
for e in 'm / 10000' '(m / 10) % 1000' 'm % 10'; do
  { cat /tmp/pg.cyr; printf 'syscall(60, %s);\n' "$e"; } | build/cycc > /tmp/pg 2>/dev/null && chmod +x /tmp/pg
  /tmp/pg; echo "$e: exit $?"
done
```

Actual: `m / 10000: exit 255` (self), `(m / 10) % 1000: exit 255` (the by-value parameter), `m % 10: exit 0` (the
dereference). Expected: 0 on every row — the word a struct under 8 bytes travels in has no bytes but the struct's.

## Root cause

`_hl_pval_ra(S, sid, z)` (`src/frontend/parse_decl.cyr`): at 3 / 5 / 6 / 7 B it copies the struct byte-exact into a
frame temp (`_agg_temp`) and loads the temp's WORD; the temp is never cleared, so bytes `sizeof(S)..7` are the frame's
previous contents. At top level the temp is a fresh hidden global (zero). 6.7.11 passes `z = 1` (an `EMOVI 0;
EFLSTORE` before the copy) from `_deref_small` and `_opd_operand`; `_self_value_ra` (the by-value receiver) and
`_hl_byval_arg` (a pointer into a by-value parameter) pass 0.

## Proposed fix

Pass `z = 1` from `_self_value_ra` and `_hl_byval_arg` too (then drop the flag: every caller zeroes). Rows: the two
above at 3 / 5 / 6 / 7 B after a frame-dirtying call (the `zdirty` pattern of
tests/tcyr/crossos/struct_deref_whole_operand.tcyr), a mutant RED.

## A third site (added 2026-10-14 by the 6.7.11 struct lane, unit S3)

`return q;` with `q: *S3` a PARAMETER in a fn returning `S3` (6.6.17's `_ret_small_ptrp`, parse_fn.cyr) copies the
struct through `_sptr_param_temp` — an `_agg_temp` that is never cleared — so the returned word's padding is frame
garbage too. Measured on `l6711-struct` (x86_64), before and after unit S3 (unchanged by it):

```sh
cat > /tmp/pad.cyr <<'X'
struct Z3 { a: i8; b: i8; c: i8; }
var ZL[2];
fn fw3(q: *Z3): Z3 { return q; }
fn zdirty(): i64 { var a: i64[16]; var i = 0; while (i < 16) { a[i] = 0 - 1; i = i + 1; } return a[15]; }
fn t(): i64 { store64(&ZL, 0x4847464544434241); zdirty(); var l: Z3 = fw3(&ZL); return load8(&l + 3); }
syscall(60, t());
X
build/cycc < /tmp/pad.cyr > /tmp/pad && chmod +x /tmp/pad && /tmp/pad; echo $?    # 255 (want 0)
```

Unit S3's NEW `return` paths (a `*S3` LOCAL, and a `*S3` global / `: *S3` call / `*S3` field) read through
`_hl_pval_ra(S, sid, 1)` and zero the temp (exit 0); the parameter path above was left as it was (changing it changes
what an existing program computes). The fix: zero `_ret_small_ptrp`'s temp too (or route the parameter through
`_hl_pval_ra(.., 1)`), with this row beside the two above.
