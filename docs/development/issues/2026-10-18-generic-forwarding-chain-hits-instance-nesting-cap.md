# A chain of more than ~120 generics forwarding their `T`, called at a non-i64 type, is refused "nesting too deep (over 256 levels)" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 generics lane (issues/2026-10-17-bounded-forward-
judgement-capped-at-64-deep.md, which removed the 64-deep cap on the bounded-forward JUDGEMENT). The call that
instantiates the chain is still held to the parser's recursion bound: each forwarder's instance is parsed nested inside
its caller's call. Pre-existing for an unbounded chain (the slot-open compiler b2e1f4c48 refuses it at the same depth);
for a bounded chain the slot-open compiler refused from 65 forwards (the judgement cap), the lane from 122.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a valid program is refused at compile time (no miscompile); a real chain of 120+ forwarders is rare.
The lane's guide sentence ("through any number of forwards", § Trait bounds) was corrected in the review fix commit to
name this cap.
**Kind:** bug (a limit of the compiler, not of the language).

## Reproduction

Generated: `o0` calls a bounded `describe`, each `o<i>` forwards to `o<i-1>`, `main` calls the top one with an f64.

```sh
gen() { n=$1; { echo 'trait Show { fn show(self): i64; }'
  echo 'fn describe<T: Show>(x: T): i64 { return x.show(); }'
  echo 'impl Show for f64 { fn show(self): i64 { return 5; } }'
  echo 'fn o0<T>(x: T): i64 { return describe(x); }'
  i=1; while [ $i -lt $n ]; do echo "fn o$i<T>(x: T): i64 { return o$((i-1))(x); }"; i=$((i+1)); done
  echo "fn main(): i64 { var h: f64 = 1.5; return o$((n-1))(h); }"; } > ch$n.cyr; }
gen 121; gen 122
```

```
$ build/cycc < ch121.cyr > b && ./b; echo $?
5
$ build/cycc < ch122.cyr > b
error:<source>:2:42: nesting too deep (over 256 levels — truncated or hostile source)
```

An unbounded chain (`fn o0<T>(x: T): i64 { return sizeof(T); }`, no trait) at f64: 122 forwarders compile (exit 8),
123 are refused the same way — on the lane and on b2e1f4c48 alike. A 170-deep chain: the same refusal (at 46:1 /
43:1).

## Root cause

`_rd_enter` (src/common/util.cyr) bounds the PARSE_STMT / PEXPR recursion at 256 levels (a stack guard against
hostile input). A generic call's instance is parsed when first reached, nested inside the call being parsed, so a
chain of N forwarders nests about 2N levels; the bound trips near N = 122-123.

## Fix direction

Either instantiate a reached generic after the current fn's body (a work queue, not nested parsing), or count only
lexical nesting in `_rd_enter` (an instance's parse starts its own depth, with the stack sized for the chain). A row
in bound_forward_chain_scale.sh / trait_bounds_checked.sh: a 200-deep chain at f64 exits 5.
