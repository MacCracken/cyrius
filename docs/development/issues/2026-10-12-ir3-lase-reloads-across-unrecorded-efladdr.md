# Under `CYRIUS_IR=3`, LASE drops the reload of a just-stored local across an unrecorded `EFLADDR` (`lea rax, [rbp+d]`): a method's argument, a by-value struct argument or a struct-returning call's argument receives the struct's ADDRESS — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the merged 6.7.10 tree (9c066967, `build/cycc` 2,106,040 B)
on x86_64. `o.with2(x)` right after `var x = 5;` exits 35 with the default pipeline, `CYRIUS_IR=1` and `CYRIUS_IR=2`.
Under `CYRIUS_IR=3` it exits 30 plus the low byte of `&o`. Six runs of one binary gave 126, 190, 222, 158, 110 and 174;
with ASLR off (`setarch -R`) it gives 238 every time. A probe method `same(self, n)` returns 1 under `CYRIUS_IR=3` and 0
by default: `n == self`, so the argument IS the receiver's address. The installed 6.7.9 compiler gives the same answer
(94 on one run; the filing's 142 and "30 after B7" are other values of the same ASLR-dependent byte). Two more shapes
fail the same way, and both are older:
- a by-value 16 B struct argument followed by the local: `bs(h, x)`;
- a >16 B struct-returning call's argument: `var b: B = mk(x);`.

The installed 6.6.0, 6.6.10, 6.6.20, 6.7.0 and 6.7.9 compilers give the same wrong result for the second; the first
gives 238 on 6.6.0 and 54 on 6.6.20. aarch64 (qemu) and cx (cxvm) give 35: the IR passes run on x86 only.
**Placement:** 6.7.11 — repair 1, the call-arguments / struct operators lanes (roadmap.md § *6.7.11*) — placed
2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.10 B7 lane (its review ran the method repro under `CYRIUS_IR=3`); re-measured and
widened here.
**Severity:** Medium. A silent wrong value on valid code, but only under the opt-in `CYRIUS_IR=3`, which no release
build uses.
**Affects:** x86_64 under `CYRIUS_IR=3`: ELF, and PE by the same code (`src/main_win.cyr:498` runs `ir_lase`; PE was
not measured). The method form exists since inherent `impl` blocks (6.7.0), measured at 6.7.0, 6.7.5, 6.7.9 and the
tree. The by-value argument and the retptr call forms were measured from 6.6.0 to the tree; not bisected further.

## Summary

`CYRIUS_IR=3` runs LASE (load-after-store elimination). The pass removes a `LOAD_LOCAL x` that follows a
`STORE_LOCAL x` when no recorded node between them writes rax. It sees only what was recorded. `EFLADDR` emits
`lea rax, [rbp+disp32]` (the address of a frame aggregate) and records no IR node. A `STORE_LOCAL x`, then an
`EFLADDR`, then `PUSH`, then `LOAD_LOCAL x` therefore looks like a redundant reload, because `PUSH` reads rax without
writing it. The reload is NOP-filled. The next `push rax` then pushes the aggregate's address as x. Three argument
sequences have that shape:

1. a method call on an inline struct local, whose receiver `self` is `EFLADDR`: `o.with2(x)`;
2. a by-value struct argument over 8 B, address-passed via `EFLADDR`: `bs(h, x)`;
3. a call returning a struct over 16 B, whose hidden result buffer is `EFLADDR`: `mk(x)`.

`&o` passed explicitly (`w2(&o, x)`) is right (35). Its `lea` comes from `ELOAD_LOCAL_ADDR`, which records
`IR_RAW_EMIT`.

This is the class of
[`2026-10-08-ir3-drops-unrecorded-field-emits.md`](2026-10-08-ir3-drops-unrecorded-field-emits.md): bytes emitted
without an IR record, placed 6.7.13. That issue names `EFIELD_LOAD_W`'s negative widths and `EFLADDR_X1` (under the
dead-store pass), and adds "audit the other x86 emitters". Its named fixes do not reach `EFLADDR`, and the pass here
is LASE. This file records the measured shapes so they ship with a row each. The two fixes can land together.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/ir3m.cyr <<'EOF'
struct S8 { v; }
impl S8 { fn with2(self: *S8, n): i64 { return self.v * 10 + n; } }
fn a2(): i64 { var o: S8; o.v = 3; var x = 5; return o.with2(x); }
syscall(60, a2());
EOF
cat /tmp/ir3m.cyr | build/cycc > /tmp/m0 && chmod +x /tmp/m0 && /tmp/m0; echo $?                 # 35
cat /tmp/ir3m.cyr | CYRIUS_IR=3 build/cycc > /tmp/m3 && chmod +x /tmp/m3 && /tmp/m3; echo $?    # 30 + (&o & 0xFF), varies
cat > /tmp/ir3s.cyr <<'EOF'
struct S8 { v; }
impl S8 { fn same(self: *S8, n): i64 { if (n == self) { return 1; } return 0; } }
fn a2(): i64 { var o: S8; o.v = 3; var x = 5; return o.same(x); }
syscall(60, a2());
EOF
cat /tmp/ir3s.cyr | CYRIUS_IR=3 build/cycc > /tmp/s3 && chmod +x /tmp/s3 && /tmp/s3; echo $?    # 1 (0 by default)
cat > /tmp/ir3b.cyr <<'EOF'
struct H { a; b; }
fn bs(h: H, n): i64 { return h.a * 10 + n; }
fn g(): i64 { var h: H; h.a = 3; h.b = 0; var x = 5; return bs(h, x); }
syscall(60, g());
EOF
cat /tmp/ir3b.cyr | CYRIUS_IR=3 build/cycc > /tmp/b3 && chmod +x /tmp/b3 && /tmp/b3; echo $?    # varies (35 by default)
cat > /tmp/ir3r.cyr <<'EOF'
struct B { a; b; c; }
fn mk(n): B { var k: B; k.a = n; k.b = 0; k.c = 0; return k; }
fn g(): i64 { var x = 5; var b: B = mk(x); return b.a; }
syscall(60, g());
EOF
cat /tmp/ir3r.cyr | CYRIUS_IR=3 build/cycc > /tmp/r3 && chmod +x /tmp/r3 && /tmp/r3; echo $?    # varies (5 by default)
```

Measured on the tree:

- `return o.with2(x + 0);` is wrong too (78): the `+`'s first operand is the eliminated load.
- `return o.with2(7);` is right (37).
- Declaring `x` before `o` (`var x = 5; var o: S8; o.v = 3;`) is right (35): the store to `o.v` breaks the
  store → load pair.

`a2`'s code, default pipeline vs `CYRIUS_IR=3` (x in rbx):

```
default:  mov rbx,rax ; lea rax,[rbp-0x30] ; push rax ; mov rax,rbx ; push rax ; pop rsi ; pop rdi ; call with2
IR=3:     mov rbx,rax ; lea rax,[rbp-0x30] ; push rax ;              push rax ; pop rsi ; pop rdi ; call with2
```

The 3-byte `mov rax,rbx` is the eliminated reload; the IR summary line reads "1 LASE (3B applied)".

## Root cause

- `EFLADDR` (`src/backend/x86/emit.cyr:5267`) emits `48 8D 85 <disp32>` (and the coroutine arm, `_ECORO_LEA`)
  with no `_IR_REC*` call. Its sibling `ELOAD_LOCAL_ADDR` (`:3726`) records `_IR_REC0(S, IR_RAW_EMIT)` first
  (`:3727`), and `IR_RAW_EMIT` is in LASE's clobber set.
- `ir_lase` (`src/common/ir.cyr:488`) keeps `last_store_idx` across `IR_PUSH` / `IR_MOV_CA`, which read rax and do
  not write it. It resets only on an op in `_ir_clobbers_rax` (`:449`). With nothing recorded for the `lea`, the
  following `IR_LOAD_LOCAL x` matches and becomes `IR_ELIMINATED`. `ir_apply_lase` (`:541`) then NOP-fills its bytes,
  and whole-program compaction reclaims them.
- The three measured callers: the method receiver (`src/frontend/parse_decl.cyr:1847`), the by-value struct argument
  (`src/frontend/parse_fn.cyr:1644`) and the retptr call's hidden buffer (`_sc_pre`, `parse_fn.cyr:4589`). The
  frontend calls `EFLADDR` from 23 sites.

## Proposed fix

1. `EFLADDR` records `_IR_REC0(S, IR_RAW_EMIT);` at its head, before the coroutine arm, as `ELOAD_LOCAL_ADDR` does.
   The return value is ignored, as there, so mode 2 still emits the bytes. The default pipeline records nothing
   (`IR_ENABLED == 0`), so `build/cycc` must stay byte-identical: self-host fixpoint plus seed-derive. The same audit
   applies to `EFLADDR_X1` and the other unrecorded emitters named by the class issue; land the two together.
2. Rows: the three shapes above (and `x + 0`) in `tests/tcyr/crossos/struct_value_codegen.tcyr`, which
   `tests/gates/codegen/struct_value_codegen.sh` row A3 already runs under `CYRIUS_IR=3`. Mutation-prove them: remove
   the record and the rows go red under A3 only.

## Consumer-side workaround

Do not build with `CYRIUS_IR=3`; the default pipeline and `CYRIUS_IR=1` / `2` are right. Under it, any statement
between the store and the call that reloads or overwrites rax breaks the pattern. Passing the receiver as `&o` to a
free fn does too.
