# A trait member's `: u128` return is accepted while every body of it is refused; and an impl method's return type is never checked against its trait member's — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-11, `d9273ec38` (the user's decision D3 (a), 2026-10-18), and GN-12, `13fd8844d`, with its review fix GN-12r, `c82edcbb1` (the user's decision D4 (a), 2026-10-18). Half 1: `trait T { fn n(self): u128; }`, which exited 4, is refused once at 2:23, "`u128` is not supported as a fn return type yet" — with a `: i64` impl too (the pinned row `u128_trait_ret` moves to the refusal) and under --syntax-only; `: *u128` and a `*fn(..): u128` type's own return are unchanged (`_trs_ret_refused`, not `_trs_u128` as planned: that test would have refused a fn pointer's return). Half 2: the filed shape (`fn c(self): i64` for a member declared `: f64`), which exited 4, is refused at the impl, "'P.c' returns i64, trait 'T' declares f64" (3:28), and the bounded generic caller that read the integer bits (exit 2) with it; the returns are compared as forming a dyn compares them, each side read as an annotation is (GN-12r: `Box<i64>` and `Box`, `Box<Box<i64>>` and `Box<Box<i64> >` are one type), an omitted return is i64, and forming a dyn from such an impl adds no second line. Parameter types are not compared — D4 left them out, though this file's root cause names them. The dyn pair check still compares spellings token by token (filed: docs/development/issues/archived/2026-10-18-dyn-pair-check-compares-type-spellings-token-by-token.md, 6.7.16). Rows: `type_name_refused.sh` `u128_trait_ret`, `u128_trait_ret1`, `u128_trait_ret2`, `u128_trait_ptr`; `traits_checked.sh` TR1 - TR8b, TRK, TRS1 - TRS7; `dyn_checked.sh` F8b; mutations RED (the u128 arm 14 checks; MTR1 - MTR4; MTRS1 - MTRS3). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b, x86_64; the
frontend, every target). Half 1 is beside issues/archived/2026-10-08-u128-params-returns-fields-captures.md (fixed in the lane
by 8d3f7caf, the user's decision D10 (a): a `u128` return is "`u128` is not supported as a fn return type yet"), whose
commit kept a trait member's `: u128` return compiling "as before (no decision covers it)". Same class as the
generics lane's staged 2026-10-16-trait-member-vec-return-accepted.md (`_trs_type` has no return-type vocabulary
check) — one fix can carry both. Half 2 is pre-existing (the slot-open compiler, 2600f67f's build/cycc, gives the
same). Met by the 6.7.14 frontend review.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D3 — (a) Refused by name, as a fn's u128 return is.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D4 — (a) Refused by name at the impl.
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
