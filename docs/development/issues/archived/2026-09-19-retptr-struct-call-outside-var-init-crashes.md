# Calling a >16 B struct-returning fn anywhere but a `var` initializer passes no return pointer — SIGSEGV (or a garbage value) at any arity — ✅ FIXED in 6.6.6 (bite 14)

**Status:** ✅ **FIXED in 6.6.6 (bite 14)** — every struct-valued call now has a destination:
`_struct_call_emit` / `_agg_temp` (`src/frontend/parse_fn.cyr`) serve PARSE_VAR's two receives,
a frame temp in PARSE_FNCALL, the struct-param argument push, `x = f(..)` (`parse.cyr`) and
`return f(..)`; top level, which has no frame, is refused by name. Found during 6.6.6 bite 1's
review; re-measured on HEAD `bbc880a9` before the fix: exit 139, as filed.
**Placement:** the next 6.6.x repair release. Not parked to 7.x (nothing codegen is).
**Discovered:** 2026-09-19.
**Severity:** High — a crash on ordinary source (`return make_point(a, b);` in a fn that returns
the same struct), and on aarch64 one shape is a SILENT wrong value instead.
**Affects:** cycc 6.6.5 and 6.6.6-in-flight. Measured: x86_64 Linux (native), aarch64 (qemu-user,
NOT hardware), Win64 (wine, NOT hardware — the `return` shape). cx and Mach-O unmeasured.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
struct P3 { x; y; z; }
fn s2(a, b): P3 { var p: P3; p.x = a * 10 + b; p.y = 0; p.z = 0; return p; }
fn fwd(): P3 { return s2(1, 2); }
fn main(): i64 {
    alloc_init();
    var r: P3 = fwd();
    print_num(r.x); println(""); return 0;
}
var ec = main();
syscall(60, ec);
```

`cat r.cyr | ./build/cycc > r && ./r; echo $?` — want `12`, exit 0. Got **exit 139 (SIGSEGV)**, no
output, on x86_64. Under wine: `page fault on write access to 0x0000000000000001` at
`rep movsb (%rsi), (%rdi)` in `fwd` — the callee copying its result through `rdi = 1`, the first
ARGUMENT. On aarch64 (qemu) this one shape happens to work (`12`): the incoming X8 is still live.

The control `fn fwd(): P3 { var t: P3 = s2(1, 2); return t; }` prints `12` everywhere.

The whole surface, with `main`'s body replaced (x86_64 / aarch64-qemu):

| call site | x86_64 | aarch64 (qemu) |
|---|---|---|
| `var r: P3 = s2(1, 2);` (and untyped `var t = s2(1, 2);`) | ✅ | ✅ |
| `s2(1, 2);` — an expression statement | SIGSEGV | SIGSEGV |
| `return s2(1, 2);` in a `: P3` fn (above) | SIGSEGV | ✅ (X8 forwarded by accident) |
| `return s2(1, 2);` in an `: i64` fn | SIGSEGV | SIGSEGV |
| `h(s2(1, 2))` — as an argument | SIGSEGV | SIGSEGV |
| `r = s2(1, 2);` — assignment to an existing `r: P3` | SIGSEGV | **exit 0, `r.x` = a stack address** |

## Root cause (suspected — verify)

Only `PARSE_VAR`'s struct-valued-assign path (`src/frontend/parse_decl.cyr`, `asv_try`, ~2695-2877)
allocates a destination and passes it as the retptr (x86: int arg 0; aarch64: X8). The general call
path (`PARSE_FACTOR`'s fn call, `src/frontend/parse_expr.cyr`) never checks whether the callee
returns a >16 B struct, so it marshals the user's arguments as if there were no retptr: on x86 the
callee takes argument 1 as the destination and every other argument shifts by one; on aarch64 it
writes through whatever X8 holds. `PARSE_RETURN`'s forwarding branch (`src/frontend/parse_fn.cyr`
~1187, v6.4.31) covers only a Win64 value-form SIMD return.

## Proposed fix

Route every call to a retptr callee through a destination: an anonymous temp local of the struct's
size (the shape `PARSE_RETURN`'s PE-SIMD branch already builds), passed as the retptr. `return f()`
in a same-type fn can forward its own incoming retptr instead of copying. Where the result has no
meaningful use (`h(s2(1, 2))` into an untyped param), a named diagnostic is acceptable — a SIGSEGV
is not.

## Acceptance criteria

1. The repro prints `12` on x86_64, aarch64 and Win64.
2. Every row of the table either works (with the value checked) or is refused at compile time with a
   diagnostic naming the struct-returning callee — none crashes, none returns garbage.
3. A `tests/tcyr/crossos/` test with literal expectations covering each accepted row, 2 and 7+ args
   (x86's retptr is int arg 0, so 6+ user args reach the stack) — green on real ecb / ach / cass / pi.
4. `build/cycc` fixpoint + seed-derive GREEN; the `.tcyr` corpus byte-difference count reported.

## Corrections to this filing

- **Two call paths, not one.** The suspected root named PARSE_FNCALL; the `return f(..)` rows never
  reach it — `return IDENT(args);` takes the TAIL-CALL path in `PARSE_RETURN`, which pops the user
  args into the int registers and `jmp`s, so the callee wrote through argument 1 there too. It now
  diverts any retptr callee, and any call from a struct-returning fn, to the normal path.
- **The 9-16 B (rax:rdx) return had the same hole, unlisted.** `q = p2(3, 4)` kept rax and dropped
  rdx (`q.y` stale, exit 0), and `hp(p2(1, 2))` into a `q: P2` param pushed the first word where
  the callee dereferences an address (SIGSEGV). Same root — only `var p: S = f(..)` gave a struct
  result storage — and fixed by the same helpers.
- **Top level was not in the table and crashed in every form** (`s2(1, 2);`, `var t = s2(..)`,
  `var t: P3 = s2(..)`, and `var t: P2 = p2(..)`). Outside a fn there is no frame for the result;
  these are now compile errors naming the callee. Supporting them would need a global-storage
  receive path — a feature, not this fix. `var t = p2(1, 2)` (untyped, rax:rdx) still yields the
  first word, as it always has.
- **A non-struct `return g()` in a struct-returning fn was silently accepted** by the same tail
  path (the caller then read the retptr buffer it had never been given data for). With the divert
  it reaches the struct-return branch and is refused: "return must be a bare local identifier, or
  a call to a fn returning the same struct".
- **`h(s2(1, 2))` into an UNTYPED param is not refused** (the filing allowed a diagnostic): it
  passes the result's first word, which is what a struct local passed to an untyped param has
  always passed (`h(r)`), and what a 9-16 B call has always yielded as an rvalue. Refusing it
  would have made the call and the local disagree.
- `return f(..)` in a same-struct fn copies through a temp rather than forwarding the incoming
  retptr: it reuses `ESTRUCT_BYVAL_COPY`, which every backend has, instead of a new
  load-the-stash emitter per backend.

