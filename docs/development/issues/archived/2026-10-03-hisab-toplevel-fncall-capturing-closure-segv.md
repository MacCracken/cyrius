# `fncallN` at top level SIGSEGVs on a capturing closure that a fn built and returned — ✅ RESOLVED in 6.6.16

**Status:** ✅ **RESOLVED in 6.6.16** (lane srca, bite srca-2) — a top-level indirect call opens its own
micro-frame, so `fncall0..8` and `callptr` take the closure-aware lowering at every depth; the filed repro
exits 0 on x86_64, and compiled natively on ecb (macOS arm64), ach (Intel macOS), pi (aarch64 Linux) and
cass (Windows), and on cx under cxvm. See CHANGELOG [6.6.16].
**Placement:** **6.6.16** (placed 2026-10-04 at the slot open; the user listed the open issues for this
release). The crash is silent — the build prints no warning or error — so it is a patch-release fix,
not backlog.
**Discovered:** 2026-10-03 from hisab, during its 3.3.4 release work (the 6.6.12 → 6.6.14 bump).
**Severity:** Medium. A documented feature (a capturing closure, returned from a fn) compiles clean
and SIGSEGVs at run time, with no diagnostic. A workaround exists (call it from inside any fn).
**Affects:** cycc **6.6.0 – 6.6.14**. Each pin was run from a scratch dir whose `cyrius.cyml` pins it,
and `cyrius build -v` printed `compiler: /home/macro/.cyrius/versions/<v>/bin/cycc`. The aarch64 row
printed `.../6.6.14/bin/cycc_aarch64`. No 6.5.x is installed on this box, so the first-bad version
is unknown. It is at or below 6.6.0, and that bound is evidence about visibility only, not origin.

## Resolution (6.6.16)

**Root cause confirmed as filed, plus one site the filing did not name.** Option (a) of the filing. The
fncallN lowering in `_PARSE_FACTOR_IMPL` was gated on `_cur_fn_ix >= 0` because `PINDIRECT_CALL` spills the
callee to frame slots and top-level code has no frame — and so was the STATEMENT-position lowering in
`_PARSE_STMT_IMPL` (`fncall1(g, 1);` as a bare statement, the filing's table row that also crashed).
`PINDIRECT_CALL` itself refused top level, which is where `callptr`'s error came from. At top level fncallN
fell through to `lib/fnptr.cyr`, whose asm calls the raw bit-63-tagged value.

**cx was worse than the filing could see.** `lib/fnptr.cyr` has no cx arm, so on cx EVERY top-level fncallN
returned 0 — the filing's controls 2 and 3 (a non-capturing closure, a plain `&add41`) included. Three
existing crossos/stdlib files failed on cxvm for that reason (no gate runs cx there); they pass now.

**Fix.** `PINDIRECT_CALL` is a small wrapper: inside a fn it calls `_PINDIRECT_CALL_IN` (the old body, minus
the refusal) and nothing changes; at top level it saves and zeroes the frame-slot counter and its high-water
mark, opens a micro-frame (`ETLFRAME_OPEN`), runs the same body, closes it sized from the larger of the two
(`ETLFRAME_CLOSE`), and restores both. Backends: x86 (ELF, PE, EFI, agnos, x86 Mach-O) `push rbp; mov rbp,
rsp; sub rsp, imm32` … `leave`, the size rounded so rsp keeps its parity; aarch64 the ordinary prologue pair
(`stp x29, x30` / two patchable `sub sp` slots) … `mov sp, x29; ldp`; cx `pushc fp; mov fp, sp; movi r15;
sub sp` … `mov sp, fp; popc fp`. On PE the open carries the page-walk stack probe (size in r10, rax
untouched). Both lowering gates and the refusal are removed; the result rides in rax / x0 / r0 across the
close, and a nested top-level indirect call nests its frame.

**Verified.** The filed repro VERBATIM exits 0 on x86_64, aarch64/qemu, PE/wine, cx/cxvm, and compiled
NATIVELY on ecb, ach, pi and cass (cross-built == natively built, byte for byte). The same repro built by
the slot-open compiler still exits 139. In-fn codegen is byte-identical: across all 439 `.tcyr`, only the six files with a
top-level indirect call (and the extended gate file) change bytes, with 0 exit-status changes (x86 and
aarch64). `ffi_stack_protected_extern_c.sh` (top-level fncall4..7 into stack-protected C, now through the
lowered path) and `call_site_stack_alignment.sh` stay green.

**The filing's recipe note can go.** "Call it from inside a fn" is no longer needed on 6.6.16; hisab's own
code was never exposed (all 96 of its indirect calls are in fns).

**Not covered (backlog, roadmap.md):** an ADDRESS-TAKEN `&fncallN` that is then called still runs
`lib/fnptr.cyr`'s asm — no closure dispatch, and 0 on cx.

## Summary

A fn builds a capturing closure and returns it. Calling that value with `fncallN` at **true top
level** (outside every fn body) SIGSEGVs. The same value works when called from inside any fn, and
so does a non-capturing closure called at top level. `callptr` at top level is refused at compile
time (`error: an indirect call (callptr / fncallN) must be inside a function, not at top level`).
`fncall1`, which that message also names, compiles clean and crashes.

This is not the 6.5.17 defect regressing (`archived/hisab-capturing-closure-segv-across-fn-boundary.md`).
It is a shape that the 6.5.17 fix exempted on purpose, on a premise that does not hold. See *Root
cause*.

## Reproduction

`docs/development/issues/repros/2026-10-03-hisab-toplevel-fncall-capturing-closure-segv.cyr` is
self-proving. Its exit code is the verdict: 0 when fixed, 139 while the defect is present. Exits 1–3
mean the call returned a wrong value or a control failed (see its header).

```
cyrius build docs/development/issues/repros/2026-10-03-hisab-toplevel-fncall-capturing-closure-segv.cyr /tmp/r
/tmp/r; echo "exit=$?"
```

The minimal form (3 lines, no includes beyond the manifest's stdlib):

```cyrius
fn mk(b) { return |x| b + x; }          # captures the parameter b
var r = fncall1(mk(41), 1);             # TOP LEVEL -> SIGSEGV (139); expected 42
sys_exit_group(r);
```

| program (6.6.14, x86_64) | exit |
|---|---|
| `fncall1(mk(41), 1)` at top level (above) | **139** |
| the same with `g0 = mk(41)` bound first, then `fncall1(g0, 1)` at top level | **139** |
| `fncall0` / `fncall2` on 0- and 2-parameter capturing closures, at top level | **139**, **139** |
| a fn stores the closure in a global `G`, and top level calls `fncall1(G, 1)` | **139** |
| `fncall1(g, 1);` as a bare top-level **statement** (closure writes a global) | **139** |
| `callptr(g0, 1)` at top level | compile **error** (the top-level refusal) |
| **control 1**: `g0` passed to `fn call1(f, a) { return fncall1(f, a); }` at top level | 42 |
| **control 2**: a NON-capturing closure returned the same way, `fncall1`'d at top level | 42 |
| **control 3**: `fncall1(&add41, 1)` (a plain fn pointer) at top level | 42 |
| **control 4**: `fn main() { return fncall1(mk(41), 1); }` | 42 |

The filed repro on every installed pin. Its controls-only variant (the top-level call replaced by
the control-1 wrapper) exits 0 on every pin, so the closure itself is sound:

| pin | repro | controls-only |
|---|---|---|
| 6.6.0, 6.6.1, 6.6.2, 6.6.3, 6.6.4, 6.6.5, 6.6.6, 6.6.7 | 139 | 0 |
| 6.6.8, 6.6.9, 6.6.10, 6.6.11, 6.6.12, 6.6.13, 6.6.14 | 139 | 0 |
| 6.6.14 `--aarch64`, under `qemu-aarch64` | 139 (`uncaught target signal 11`) | 0 |

The faulting instruction on 6.6.14 x86_64 (gdb), inside `lib/fnptr.cyr`'s `fncall1` asm:

```
rax            0x80007fffe7e00000      <- the closure value: env object 0x7fffe7e00000 | bit 63
=> 0x40db40:   call   *%rax            <- fnptr.cyr:170, `0xFF; 0xD0; # call rax`
   0x40db42:   mov    %rax,-0x18(%rbp)
```

## Root cause (read from the source, then confirmed by the run above)

1. Since v6.5.17, `fncall0..8` are lowered by the compiler to `PINDIRECT_CALL`, the closure-aware
   sequence (`ECLENV`/`ECLNORM`: strip bit 63, pass the env as a trailing argument). The lowering
   is gated on `_cur_fn_ix >= 0` (`src/frontend/parse_expr.cyr:1547`), because it spills the
   callee to a frame slot and top-level code has no frame.
2. At top level, `fncallN` therefore stays an ordinary call into `lib/fnptr.cyr`. Its asm does
   `mov rax, [rbp-8]; call rax` on the raw value (`lib/fnptr.cyr:163-172` for `fncall1`). A
   capturing closure's value is its heap env object with **bit 63 set**, so this is a jump to a
   non-canonical address, which faults as #GP and then SIGSEGV on x86_64. The aarch64 asm does the same
   `blr x9` on the raw value, and qemu reports signal 11.
3. The gate's comment (`parse_expr.cyr:1538-1546`) gives the reason this was thought safe: *"At
   top level `fncallN` therefore keeps its pre-v6.5.17 meaning … which is the only thing that ever
   worked there anyway (a closure literal needs a frame too …)"*. **That premise is false for an
   escaped closure.** The literal is built inside a fn, which has a frame. Only the CALL is at top
   level. The value reaches top level by `return` or through a global, which are two of the routes
   the 6.5.17 note lists as the ones that defeated the old compile-time test.

The same class as 6.6.2's bare SIMD intrinsic at top level: top-level code has no frame, and a
lowering that needs one silently does something else. 6.6.2 resolved that one by refusing at
compile time, and `callptr` here is refused too. `fncallN` alone falls back without a word.
`tests/tcyr/crossos/closure_escape_dispatch.tcyr` (the 6.5.17 gate) makes every call from inside
a fn, so it cannot see this shape.

## Proposed fix

Speculative. The lowering internals are cyrius's. Options visible from outside:

- (a) Give the top-level lowering somewhere to spill the callee, such as a hidden global or a
  synthesised top-level frame. `fncallN` and `callptr` would then take the closure-aware path at
  top level too, and the `callptr` refusal could go.
- (b) Make `lib/fnptr.cyr`'s `fncallN` closure-aware: test bit 63, strip it, load the code pointer
  from `env[0]`, and pass the env as the trailing argument. The v6.5.17 note explains why this is
  awkward for the higher arities (the cybs 6-argument limit). Asm can avoid that limit, and a
  capturing closure is capped at 5 parameters anyway.
- (c) At minimum, fail loudly: have the library `fncallN` exit with a message when bit 63 is set,
  instead of jumping. A compile-time refusal like `callptr`'s would break
  `tests/gates/platform/ffi_stack_protected_extern_c.sh`, which calls `fncall4..7` at top level on
  plain pointers.

Whatever lands, the gate wants a top-level row for each route a closure value can arrive by
(`return`, global, `load64`), next to the existing in-fn rows.

## Consumer-side workaround

Call the closure from inside a fn. A one-line `fn call1(f, a) { return fncall1(f, a); }` is enough
(control 1). Passing the closure to a library fn that calls it is also fine, because that call
happens inside the library fn.

## hisab's exposure

**Nil in-tree, verified rather than assumed.** hisab is a library. Its only indirect calls are 96
`fncallN`/`callptr` sites in `src/`, all inside fn bodies, plus 1 in `tests/modules.tcyr` (inside
`_ot_drive`), and none at top level in `src/`, `tests/` or `examples/`. That count comes from a
brace-depth scan with comments and strings stripped, positive-controlled on this repro, which it
reports at depth 0. hisab builds exactly one closure (`tests/modules.tcyr`,
`_ot_make_closure_grad`), and it is only ever called inside a fn.

The exposure is a **consumer's** own code. hisab's autodiff recipe (`src/autodiff.cyr`, "Pairing
with optimize.cyr") builds a capturing gradient closure. Built by a helper fn and run against the
3.3.4 bundle on 6.6.3, 6.6.12, 6.6.13 and 6.6.14:

| recipe use | exit (all four pins) |
|---|---|
| closure passed to `opt_lbfgs` **at top level** (the solver calls it inside itself) | 0, converges to (1, 2) |
| closure passed to `opt_lbfgs` inside a fn | 0 |
| the caller's own `fncall2(grad, x, g)` **at top level** | **139** |
| the caller's own `fncall2(grad, x, g)` inside a fn | 0, gradient (4, 6) at (3, 5) |

hisab 3.3.4's recipe note now tells callers to invoke such a closure from inside a fn. hisab
records its exposure as `hisab/docs/development/issues/2026-10-03-cyrius-toplevel-fncall-capturing-closure-segv.md`.
