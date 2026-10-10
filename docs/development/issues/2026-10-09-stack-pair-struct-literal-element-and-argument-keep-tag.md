# A `: stack` pair in a struct-literal element or passed as a plain argument keeps the tag and drops the payload, silently — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B). The repro compiles with no diagnostic and exits 30 where every shape should be refused. Each element
or argument received the tag (0 for `Ok`) and not the payload (7). Same result on aarch64 (a cross compiler built
from the merged tree, run under qemu-aarch64) and on the 6.7.6 tag. The positional element and the free-call
argument give the same result on 6.6.0, 6.6.10 and 6.7.0. The stores 6.7.7 closed (`h.n = f(7);`, `a[0] = f(7);`,
`*p = f(7);`, `x += f(7);`, `var t = (f(7), 3);`) are refused on the same tip, and so are `var r = f(7);` and
`r = f(7);`.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
This is the user's decision (2026-10-09, "File for later"): the guide's refusal is extended to these contexts in a
repair release, not in 6.7.7. The call-arguments lane owns the argument pushes and the struct-literal stores.
**Discovered:** 2026-10-09 by the 6.7.7 B4 (tuples) review. It predates B4 and was out of scope for the T5b bite,
which closed the field / element / `*p` / `OP=` stores.
**Severity:** High — a silent miscompile: the payload (for an `Err`, the error code) is lost with no diagnostic, in
contexts the guide says are compile errors.
**Affects:** cycc ≤ 6.7.6 and the merged 6.7.7 (measured 6.6.0, 6.6.10, 6.7.0, 6.7.6 tag, 6.7.7 tip). A `: stack`
pair has existed since v6.5.67.

## Summary

The guide (`docs/guides/cyrius-guide.md` § *Bind the pair as a pair — the refusals*) says a value-form Result is two
values, and that "any context that keeps only one would silently discard the payload … so each is a compile
error". The refusal (`_refuse_lossy_pair`) runs at a `var` bind and at an assignment. It runs at `store8..64`, at a
field, an element and `*p` store, at every compound `OP=`, and at a tuple-literal element (6.7.7). It does not run in
two other one-slot contexts, which compile clean and keep only the tag:

1. **A struct-literal element**: `P { f(7), 3 }` and `P { a: f(7), b: 3 }`, in a fn or as a global initialiser
   (`var G = P { f(7), 3 };`).
2. **A plain argument**: `g(f(7))`, at any position, through a free call or a method call (`b.m(f(7))`), and at top
   level (`syscall(60, g(f(7)))`).

`f(7)?` consumes the pair in both contexts, as it does elsewhere: `P { f(x)?, 3 }` and `g(f(x)?)` pass the payload
(verified on the same tip). `return f(7);` forwards the pair, as documented.

Also met while verifying, and not covered by the user's 2026-10-09 decision, which names the element and the
argument: an **operand** (`return f(7) + 1;` exits 1) keeps the tag too. Whether a tag test such as
`if (f(7) == 0)` stays legal is a question for the open. Fold it into the same ask, or leave it.

## Reproduction

`docs/development/issues/repros/2026-10-09-stack-pair-struct-literal-element-and-argument.cyr`:

```cyrius
enum Res: stack { Ok(v); Err(e); }
fn f(x) { return Ok(x); }
struct P { a; b; }
struct B { z; }
impl B { fn m(self, v): i64 { return v; } }
fn g(v): i64 { return v; }
fn lit_positional(): i64 { var p = P { f(7), 3 }; return p.a; }        # 0, the tag
fn lit_named(): i64 { var p = P { a: f(7), b: 3 }; return p.a; }       # 0
fn arg_free(): i64 { return g(f(7)); }                                  # 0
fn arg_method(): i64 { var b = B { 0 }; return b.m(f(7)); }             # 0
var G = P { f(7), 3 };                                                  # G.a is 0
syscall(60, G.b * 10 + lit_positional() + lit_named() + arg_free() + arg_method());
```

```sh
cat docs/development/issues/repros/2026-10-09-stack-pair-struct-literal-element-and-argument.cyr | build/cycc > /tmp/sp \
  && chmod +x /tmp/sp && /tmp/sp; echo $?
# actual:   compiles clean, exit 30
# expected: one "a `: stack` enum returns two values — bind both: `var tag, val = f();`" per fn
#           (and one for the global initialiser); no binary
```

## Root cause

`_refuse_lossy_pair` (`src/frontend/parse.cyr:853`) runs right before the value's PCMPE at each refused store. Line
numbers are from the merged tree:

- The variable assignment: `parse.cyr:4700`.
- `_asg_compound_op`: `parse.cyr:3163`.
- `_deref_store`: `parse.cyr:3201`.
- The field stores: `src/frontend/parse_decl.cyr:1817`, `:1844`, `:1958`.
- The tuple element: `parse_decl.cyr:2654`.
- The subscript store: `src/frontend/parse_expr.cyr:2676`.
- The `store8..64` builtins: `parse_expr.cyr:4201`–`4234`.
- The if-expression branch and the classic-for step: `src/frontend/parse_ctrl.cyr:328`, `:777`.

It is not called at these two places:

- **The struct-literal field store**: `EMIT_STRUCT_FIELD_W` (`parse_decl.cyr:2021`) parses the element with a bare
  `PCMPE` (`:2028`). Every positional, named and nested literal reaches it (`:2109`, `:2382`), in a frame or a
  global.
- **The argument push**: `_bx_pcmpe_arg` (`parse_expr.cyr:1600`) is the scalar argument's PCMPE. Three callers reach
  it: the one marshaller (`_call_arg_one`, `src/frontend/parse_fn.cyr:4168`), the tail-call arm (`parse_fn.cyr:948`)
  and the inline replay (`parse_fn.cyr:5908`). None of the three tests the pair. Calls outside these arms (an indirect
  `fncallN`, a builtin's own arguments) need checking when the fix is written.

## Proposed fix

Call `_refuse_lossy_pair(S)` before the element's PCMPE in `EMIT_STRUCT_FIELD_W` (the `_sfw_have == 0` arm), and before
the PCMPE in `_bx_pcmpe_arg`. That is the same one-line placement T5b used, so `f(7)?` keeps working through
`_call_is_propagated`. Before landing, measure the corpus (every `.cyr` / `.tcyr` / `.fcyr` / `.bcyr`, `lib/`
included, as T5b did): a `: stack` call passed straight to a helper (`is_ok(f())`-style) would start failing, and each
such site is a payload the program never sees.

Update the guide's *Bind the pair as a pair* block with the two new rows. Add a gate row per shape (positional and
named element, global initialiser, free, method and top-level argument, the `?` forms accepted) to
`tests/gates/frontend/stack_enum_lossy_context.sh`, with a mutation per call site.

## Consumer-side workaround

Bind both halves first: `var t, v = f(7); var p = P { v, 3 }; g(v);`. Or use `f(7)?` where propagating the `Err` is
intended.
