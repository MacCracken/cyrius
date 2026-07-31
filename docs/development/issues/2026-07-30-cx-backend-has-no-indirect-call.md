# The cx backend has no indirect call, so every fn-pointer stdlib path is dead there

**Filed:** 2026-07-30
**Reporter:** cyrius (surfaced building `vec_sort_by` for v6.5.4)
**Cyrius version:** 6.5.4
**Affected:** `src/backend/cx/emit.cyr` (`ECALLIND`), `programs/cxvm.cyr`, `lib/fnptr.cyr`
**Severity:** Medium — cx is the portable bytecode target, not a shipping-consumer target today,
but the breakage is silent and its blast radius is the whole allocator/callback layer.
**Status:** open

## 1. Summary

cx cannot make an indirect call, and the two mechanisms that *want* to fail in opposite,
equally unhelpful ways:

| mechanism | behaviour on cx |
|-----------|-----------------|
| `callptr(fp, a, b)` (builtin) | **hard compile error**, and it fires when the *uncalled* body is emitted |
| `fncall2(fp, a, b)` (`lib/fnptr.cyr`) | **silently returns 0** — every `#ifdef` arm is Linux/macOS/agnos/Win, there is no cx arm |

`src/backend/cx/emit.cyr:408`:

```
fn ECALLIND(S, idx): i64 {
    syscall(SYS_WRITE, 2, "error: callptr (indirect call) is not supported on the cx backend\n", 66);
    syscall(SYS_EXIT, 1);
    return 0;
}
```

Its comment still reads *"callptr targets native COM/DXGI; it is not expressible in cx."* That
was true at v6.0.70, when `callptr` existed for COM vtables. It is no longer the shape of the
problem: fn pointers are now how the stdlib does allocators, hashmap iteration, reduce/fold,
predicate matchers, async dispatch, and (as of 6.5.4) ordering.

## 2. The consequence that matters: vec is already broken on cx

`lib/alloc.cyr:399` is `alloc_via(a, size) → fncall2(allocator_alloc_fn(a), ...)`. On cx that
returns **0**. So:

```
vec_new_a():  var v = alloc_via(a, 24);  if (v == 0) { return 0; }   # → 0
```

`vec_new()` returns 0 on cx, and every subsequent vec operation dereferences null. Reproduced:

```bash
cat > /tmp/cxvec.cyr <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
alloc_init();
var v = vec_new();
vec_push(v, 42);
var r = vec_get(v, 0);
EOF
build/cycc_cx < /tmp/cxvec.cyr > /tmp/cxvec.cyx   # exit 0, 34343 bytes
build/cxvm /tmp/cxvec.cyx                          # HANGS (timed out at 120 s)
```

It compiles clean and then hangs. Nothing in the suite catches it, because there is no cx
test that uses a vec.

## 3. Why v6.5.4 worked around it rather than fixing it

`lib/vec.cyr` is auto-prepended into every build via `cyrius.cyml [deps].stdlib`. Using
`callptr` for `vec_sort_by`'s comparator would therefore have broken **every cx program in the
ecosystem**, including ones that never sort — the error fires at emit time for the unreachable
body. Confirmed with a minimal probe:

```bash
printf 'fn helper(a,b): i64 { return a+b; }\nfn never_called(fp): i64 { return callptr(fp,1,2); }\nvar r = helper(3,4);\n' \
  | build/cycc_cx > /dev/null
# error: callptr (indirect call) is not supported on the cx backend   (exit 1)
```

So 6.5.4 used `fncall2`, matching `lib/alloc.cyr` and `lib/hashmap.cyr`. That keeps
`vec_sort_by` exactly as broken on cx as `vec_new` already is — no new regression — but it does
not fix the hole.

## 4. Why this was filed rather than packed into 6.5.4

Per CLAUDE.md, a filing needs a named reason. This one is **a compiler-backend feature plus a
bytecode-ISA design decision that is the maintainer's call**, not a change that packs into a
patch:

1. **A new cxvm opcode.** cx is a register VM whose call op (96) takes a *relative code offset*.
   An indirect call needs a new opcode taking a target in a register, plus dispatch in
   `programs/cxvm.cyr`. Opcode numbering is ISA surface — once allocated it is permanent for
   every `.cyx` artifact.
2. **What a cx fn pointer even IS has to be decided.** `&helper` already compiles on cx (exit 0),
   but nothing pins down whether the value is a bytecode offset, a fn-table index, or a tagged
   handle — and the choice interacts with the fixup table and with how `cxvm` validates a call
   target (an unvalidated code offset from a data word is an arbitrary-jump primitive in the VM).
3. **Cross-target verification.** cx artifacts are portable across all four hosts, so a new op
   needs the cxvm change verified on ecb / ach / cass / pi, not just Linux.

None of that is a two-line change, and (2) is a decision, not an implementation detail.

## 5. Proposed shape

1. Decide the fn-pointer representation for cx (recommend: index into the existing fn table,
   which `cxvm` can bounds-check — a raw offset cannot be validated).
2. Add `ECALLIND` for real: emit `<newop> reg` after the existing `ECALLPOPS` arg marshalling,
   mirroring `ECALLTO`/`ECALLFIX`'s structure.
3. Add the missing `#ifdef CYRIUS_TARGET_CX` arms to `fncall0..fncall8` in `lib/fnptr.cyr` —
   or, better, make `fncallN` lower to the same new op so there is one mechanism, not two.
4. **Add a cx test that uses a vec**, which is what would have caught this years ago. The
   existing cx harness has no allocator-dependent case at all.
5. Re-check the silent-zero paths that this unblocks: `alloc_via`, `hashmap` iteration,
   `vec_fold` (`lib/callback.cyr:52`), `lib/shadow.cyr`, `lib/grp.cyr`, `lib/pwd.cyr`,
   `lib/async.cyr`, `lib/bench.cyr`.

## 6. Related

- v6.4.32 cx SIMD codegen — the precedent for a real cx emitter arc (13 stubs → real).
- v6.4.54 cx finish-outs — both filed cx bugs were misdiagnosed; expect the same care here.
- CHANGELOG [6.5.4] — the `vec_sort_by` comparator-mechanism rationale.
