# A chain of more than ~120 generics forwarding their `T`, called at a non-i64 type, is refused "nesting too deep (over 256 levels)" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-2, `10afe6e68` — no decision needed (a compiler limit refusing valid source). An instance's body counts its own nesting levels and `_rd_enter` bounds the compiler's native stack (6 MB below the parse's first frame); lexical nesting keeps the 256-level counter and its message. A second limit of the same class, met fixing the first, is fixed in the bite: on x86 an instance's jump targets were merged into the enclosing fn's 1023-entry LASE table (~190 links, and one fn calling ~210 generics at f64); the instance's code range is now opaque to the enclosing walks (792 corpus files byte-identical). The filed 122-link chain exits 5 (it was "nesting too deep (over 256 levels)"); 200 bounded links exit 5 and 200 unbounded 8 on every host; 300 links compile on x86 Linux, pi, ecb and ach, 290 on cass; a longer chain is one refusal, "nesting too deep (N generic instances, each parsed inside the call that reaches it, used over 6 MB of the compiler's stack)". Rows: `trait_bounds_checked.sh` F14d (updated), F14e (the filed repro verbatim), F14f, F14g; `bound_forward_chain_scale.sh` T3; `recursion_depth_bounded.sh` axis 4 (100000 nested parens still the 256-level refusal); `jump_target_cap.sh` (300 generics in one fn); `tests/tcyr/crossos/generic_forward_chain_deep.tcyr`; three mutations each RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 generics lane (issues/2026-10-17-bounded-forward-
judgement-capped-at-64-deep.md, which removed the 64-deep cap on the bounded-forward JUDGEMENT). The call that
instantiates the chain is still held to the parser's recursion bound: each forwarder's instance is parsed nested inside
its caller's call. Pre-existing for an unbounded chain (the slot-open compiler b2e1f4c48 refuses it at the same depth);
for a bounded chain the slot-open compiler refused from 65 forwards (the judgement cap), the lane from 122.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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
