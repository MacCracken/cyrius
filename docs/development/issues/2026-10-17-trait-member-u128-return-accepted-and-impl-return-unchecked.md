# A trait member's `: u128` return is accepted while every body of it is refused; and an impl method's return type is never checked against its trait member's — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b, x86_64; the
frontend, every target). Half 1 is beside issues/2026-10-08-u128-params-returns-fields-captures.md (fixed in the lane
by 8d3f7caf, the user's decision D10 (a): a `u128` return is "`u128` is not supported as a fn return type yet"), whose
commit kept a trait member's `: u128` return compiling "as before (no decision covers it)". Same class as the
generics lane's staged 2026-10-16-trait-member-vec-return-accepted.md (`_trs_type` has no return-type vocabulary
check) — one fix can carry both. Half 2 is pre-existing (the slot-open compiler, 2600f67f's build/cycc, gives the
same). Met by the 6.7.14 frontend review.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — half 1: the trait declares a signature no impl can define, refused at the impl; half 2: an impl
whose return disagrees with its trait compiles silently, and a dyn / generic caller that trusts the trait's type reads
the wrong register class (an `f64` member implemented as `i64`).
**Kind:** half 1 bug (diagnostic); half 2 language (what an impl must match is the user's call: 6.7.x checks a
member's parameter count — issues/archived/2026-10-09-trait-signature-parameter-list-unparsed.md — not its types or
return).

## Reproduction

```sh
cd <the tree>
# half 1: the member compiles, its bodies are refused
printf 'struct P { x; }\ntrait T { fn n(self): u128; }\nsyscall(60, 4);\n' | build/cycc > /tmp/t1 && chmod +x /tmp/t1 && /tmp/t1; echo $?
# 4   (no diagnostic)
printf 'struct P { x; }\ntrait T { fn c(self): u128; }\nimpl T for P { fn c(self): u128 { return 4; } }\nsyscall(60, 4);\n' | build/cycc > /dev/null
# error:<source>:3:28: `u128` is not supported as a fn return type yet
printf 'struct P { x; }\ntrait T { fn c(self): u128 { return 4; } }\nimpl T for P { }\nsyscall(60, 4);\n' | build/cycc > /dev/null
# error:<source>:2:23: `u128` is not supported as a fn return type yet
# half 2: the impl's return disagrees with the member's, silently
printf 'struct P { x; }\ntrait T { fn c(self): f64; }\nimpl T for P { fn c(self): i64 { return 4; } }\nfn main(): i64 { var p: P = P { 1 }; return p.c(); }\nsyscall(60, main());\n' | build/cycc > /tmp/t4 && chmod +x /tmp/t4 && /tmp/t4; echo $?
# 4   (no diagnostic)
printf 'struct P { x; }\ntrait T { fn c(self): u128; }\nimpl T for P { fn c(self): i64 { return 4; } }\nfn main(): i64 { var p: P = P { 1 }; return p.c(); }\nsyscall(60, main());\n' | build/cycc > /tmp/t5 && chmod +x /tmp/t5 && /tmp/t5; echo $?
# 4   (no diagnostic)
```

tests/gates/frontend/type_name_refused.sh row `u128_trait_ret` (8d3f7caf) pins the last shape — a `: u128` member
implemented as `: i64` — as "runs" (exit 4).

## Root cause

Half 1: the trait-signature reader `_trs_type` (src/frontend/parse_fn.cyr) resolves a member's return name and has no
return-type vocabulary check; PARSE_FN_DEF's return reader refuses `u128` (`_ret_ann_alt`, 6.7.14) and `Vec`, so a
default body or an impl method spelled as the member says is refused. Half 2: the impl checker compares a method's
parameter COUNT with its member's ("method 'c' takes a different number of parameters than its declaration in trait
'T'"), not the parameter types (`a: f64` implementing `a: i64` compiles too) or the return annotation.

## Proposed fix

Half 1: in `_trs_type`'s return position refuse what a fn's return refuses, with the same words, once — the member
`fn n(self): u128;` is "`u128` is not supported as a fn return type yet" (and the Vec shape with it). The pinned row
`u128_trait_ret` moves to the refusal. Half 2 (after the user's decision): an impl method whose return type differs
from its member's is refused by name ("'P.c' returns i64, trait 'T' declares f64"). Rows: each repro; controls — a
member and impl agreeing (`: i64` / `: f64` / `: *u128`), a member with no return annotation.
