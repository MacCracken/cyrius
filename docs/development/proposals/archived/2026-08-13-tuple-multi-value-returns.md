# Tuples — lightweight multi-value returns — ✅ SHIPPED v6.5.21

> **✅ SHIPPED in v6.5.21** (CHANGELOG `[6.5.21]`). Gated by
> `tests/tcyr/crossos/multi_return.tcyr` (15 assertions, all four backends) and
> `tests/gates/codegen/cx_multi_return.sh` (4 axes, mutation-proven).
>
> ⛔ **THIS PROPOSAL'S CENTRAL CLAIM WAS WRONG, AND THE ERROR WAS OURS.**
> Two-value multi-value return with destructuring had shipped at **v3.7.2** —
> four majors before this was filed. `return (a, b);` + `var q, r = f();` worked
> at 6.5.20 and is documented in `docs/guides/cyrius-guide.md`. The proposal's
> "What Cyrius has today (verified against 6.5.20, not assumed)" table is correct
> only as *spelled*: it tested `return a, b;` and `var (x, y) = f();`, and those
> two spellings are indeed parse errors. The supported spellings differ only in
> where the parentheses go.
>
> **Root cause of the mis-filing is on our side, not the consumer's.** The vidya
> entry `language/features.cyml → ret2_rethi`, under a heading literally reading
> "ALTERNATIVE — NATIVE MULTI-RETURN", documented the form as
> `return a / b, a % b;` — no parens, a parse error — and had done so since
> v3.7.2. A consumer following CLAUDE.md's instruction to search vidya before
> reimplementing got the wrong syntax from the authoritative source. Corrected at
> v6.5.21.
>
> **What was genuinely missing, and what v6.5.21 shipped:**
> * **Arity 3** — the one real capability gap. `_dd_pow10` is genuinely
>   three-valued; it is now `fn f(): (i64, i64, i64)`. Third slot is r8 (x86/PE),
>   x3 (aarch64), r5 (cx).
> * **A declared return type** `fn f(a, b): (f64, f64)`, which is what makes
>   arity checkable at a FORWARD call and types the bindings from the signature.
> * **Three silent miscompiles the proposal did not know were there** — and these,
>   not the ergonomics, were the real content of this slot:
>   1. **cx returned the first value twice.** `EMOVRDXRAX`/`EMOVRA_RDX` were
>      `return 0;` stubs, so `return (5, 9)` scored 59 on x86/aarch64/PE and 55
>      on cx, exit 0, no diagnostic.
>   2. **A `: f64` fn returning a tuple lost its first value** on x86/PE — the
>      caller unboxed a stale `xmm0`. This is the *exact* Dekker shape the
>      proposal motivates: a consumer writing `two_product` would naturally
>      annotate `: f64` and get silently wrong numbers.
>   3. **f64 type was lost at the binding**, so arithmetic on a returned f64 was
>      an integer add over the bit pattern. Not destructure-specific — plain
>      `var p = f();` on a `: f64` callee lost it too, which is why the `: f64`
>      RETURN annotation had **two uses ecosystem-wide, both in our own tests**:
>      it was unusable, not unpopular.
> * **A destructure contract**, which did not exist at all. `var q, r = 42;`
>   compiled; `var q, r = dm(17,5) + (k/9) - 11;` put the **idiv remainder** in
>   `r`. Both now rejected.
>
> **Two factual corrections to the filing's evidence**, recorded so the next
> reader does not inherit them: the `_two_product(a, b, out)` row describes code
> that **does not exist in abaco** — there is no such function and no 16-byte
> buffer; the real primitive is single-return `_dd_prod_err`. And of the sites
> that do exist, two of three were already expressible with zero heap, plus two
> more 2-valued sites in `src/dsp.cyr` the filing did not list. The consumer-side
> facts (the `alloc(8)` per numeric literal, the negative-sentinel hazard, the six
> structs, the 6.5.20 pin) all check out.
>
> **Not shipped, deliberately:** tuples as first-class storable values. The
> proposal's own "Not asking for" section holds — this stays a call-boundary
> construct.

**Filed:** 2026-08-13 (by an abaco consumer, surfaced implementing Dekker
double-double arithmetic for `parse_number` during abaco 2.4.0 — every
error-compensated primitive in that family is intrinsically two-valued and had
to be routed through heap buffers)
**Status:** ✅ **SHIPPED in v6.5.21** — filed as an **ergonomics gap**; the
ergonomics half had largely shipped at v3.7.2 and the slot's real content turned
out to be three silent miscompiles underneath it (see the banner above).
**Placement:** **roadmap.md → Potential backlog**, candidate for the **v6.6.x
ergonomics list** alongside `CYRIUS_PKG_VERSION` and the `[embed]` manifest
section. Sequence it **after** those two — both are manifest/build-time
mechanisms with no type-system surface, whereas this one touches the type
checker and the calling convention, so it should not be first in the queue.
**Priority:** low / not a release-blocker. abaco 2.4.0 shipped with the
out-parameter workaround and pins cyrius 6.5.20.
**Siblings:** [`2026-07-05-const-eval-comptime.md`](../2026-07-05-const-eval-comptime.md)
— both are about expressing something at the language level that consumers
currently express by hand.

## Trigger (the concrete case)

abaco's `parse_number` needed correctly-rounded decimal→binary scaling to stop
literals within ~2 ulp of `DBL_MAX` saturating to `+Inf`. The standard remedy is
Dekker's error-compensated product: given `a` and `b`, produce **both** the
rounded product and the exact rounding error, so a second term can carry the
bits the first one dropped.

That primitive is two-valued by definition. In Cyrius today it must be written
as either an out-parameter or a heap record:

```cyr
# What it is mathematically:  two_product(a, b) -> (p, err)
# What it has to be in Cyrius:
fn _two_product(a, b, out) {       # out = alloc(16)
    var p = f64_mul(a, b);
    ...
    store64(out, p);
    store64(out + 8, err);
    return 0;
}
```

The double-double scale factor is worse: it is a *three*-valued quantity
(`hi`, `lo`, and a binary exponent kept separately so intermediates cannot
overflow), so it travels as a 24-byte buffer that every call site must allocate,
pass, and read back field by field:

```cyr
var dd = alloc(24);
_dd_pow10(k, dd);
var hi   = load64(dd);
var lo   = load64(dd + 8);
var bexp = load64(dd + 16);
```

Nothing here is *hard*. It is that a value with a two-line lifetime costs a heap
allocation, three `load64`s at every use, and an entirely positional contract
between caller and callee that the compiler cannot check.

## Where this already shows up in a shipped consumer

Not hypothetical — these are the out-parameter sites in abaco 2.4.0:

| site | shape it wants | what it does instead |
|---|---|---|
| `parse_number(input, start, len, out_end)` | `(value, end_index)` | writes the index through `out_end`; every caller allocates an 8-byte cell first |
| `_two_product(a, b, out)` | `(product, error)` | 16-byte buffer |
| `_dd_pow10(k, out)` | `(hi, lo, bexp)` | 24-byte buffer |
| `tokenize` | `(count, overflow_flag)` | overloads the return: a **negative sentinel** (`ABACO_TOK_OVERFLOW = -1`) smuggled into an otherwise-unsigned count |

The tokenizer row is the interesting one. Because there was no way to return
"count **and** did-it-overflow", the overflow condition was encoded as a
negative count — and the 2026-08-13 audit found that a caller which forgot to
check the sentinel would use `-1` as a length. It is a small hazard, and abaco
handles it, but the reason it exists at all is the missing return shape.

The `alloc` cost is not free either: abaco's `tokenize` calls `alloc(8)` once per
numeric literal purely to receive `parse_number`'s end index, from a bump
allocator with no free. A 500-token expression leaks a few hundred bytes of
scratch per parse for want of a second return slot.

## What Cyrius has today (verified against 6.5.20, not assumed)

| mechanism | works? | note |
|---|---|---|
| `struct Name { a; b; }` | ✅ | abaco uses six of them; the right tool for a *named, persistent* record |
| out-parameter + `store64` | ✅ | the working idiom for transient multi-values |
| negative / sentinel return values | ✅ | works, but overloads one channel and the checker cannot enforce the discipline |
| `return a, b;` | ❌ | parse error |
| `var (x, y) = f();` | ❌ | no destructuring syntax |
| anonymous multi-value type | ❌ | every multi-value must be a declared `struct` or a raw buffer |

Structs cover the *persistent* case well. What is missing is the transient one:
a value that exists only to cross a single function boundary and be immediately
destructured, where declaring a named type and heap-allocating an instance are
both disproportionate.

## Sketch

Two pieces, and the second is the one that actually matters:

```cyr
# 1. Multi-value return
fn two_product(a, b) -> (f64, f64) {
    var p = f64_mul(a, b);
    ...
    return p, err;
}

# 2. Destructuring at the call site
var (prod, err) = two_product(x, y);
```

Deliberately **not** proposed: tuples as first-class storable values — no tuple
fields inside structs, no tuples in `vec`, no tuple-typed globals. Those raise
layout, aliasing and ABA questions that a purely call-boundary construct does
not. If a value needs to persist, `struct` already exists and is the honest
declaration. Restricting tuples to "returned, then immediately destructured"
keeps the feature inside the calling convention, where it can be lowered to
multiple registers with no heap traffic at all.

Interaction worth flagging: Cyrius `var` bindings are **function-scoped**, so
`var (a, b) = f();` in two branches of one function collides the way plain `var`
does today. The destructuring form should follow the existing rule rather than
invent a second scoping story — consumers already hoist declarations for this
reason, and the fix (if one is wanted) is block scoping, which is a separate
proposal.

## Why it is worth doing at all

The honest case is narrow. Most consumer code does not need this, and abaco
shipped without it.

Where it earns its place is **numeric** code, which is the domain Cyrius already
serves with `f64`-only arithmetic and no FMA intrinsic. Error-compensated
algorithms — two-product, two-sum, double-double, compensated summation,
correctly-rounded decimal conversion — are *all* built from two-valued
primitives. Every one of them is currently a heap buffer and a positional
contract. If Cyrius wants `lib/math.cyr` and `lib/ganita.cyr` to reach
correctly-rounded results rather than 1–3 ulp, this is the shape that work is
written in.

A smaller supporting point: `lib/math.cyr`'s own float parser and abaco's are
both ~1 ulp short at the top of the f64 range for exactly this reason. The
remedy is known and standard; the language makes it verbose enough that both
implementations chose the approximation instead.

## Alternatives considered

- **Do nothing.** Defensible. The out-parameter idiom works, and consumers that
  need it have written it. The cost is per-consumer verbosity and the sentinel
  hazard above.
- **Small fixed-size value types** (a `pair`/`triple` builtin). Less general,
  but covers the numeric cases and avoids a variadic type constructor. Might be
  the cheaper first step if a full tuple type is too much surface.
- **Multiple return without destructuring** (`return a, b;` assigned
  positionally). Half the ergonomics for most of the implementation cost; not
  recommended on its own.

## Not asking for

- Tuple types in struct fields, `vec`, `hashmap`, or globals.
- Named tuple fields (that is a `struct`).
- Variadic or generic tuple arity beyond a small fixed maximum — 2 and 3 cover
  every case abaco encountered; 4 would be generous.
