# A trait member's `: Vec<..>` return compiles, while a fn's `: Vec<..>` return is refused "type 'Vec' cannot be a fn return type" — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-10, `64c2fc8eb` (the user's decision D9 (a), 2026-10-18: refuse it at the trait, once, with the fn's words): `_tr_sig_check` holds a member's own return to a fn's return set (`_trs_ret_refused` -> `_tn_ret_report`). The filed repro, which exited 4, is refused once at 2:24, "type 'Vec' cannot be a fn return type", with the fn's note; silent under --syntax-only, as a fn's is. A bare `: Vec` member return is refused with it — beyond D9's text, the lane's judgement call for the user to confirm (a fn's bare `: Vec` already is). `: i64`, `: *Vec<i64>`, a parameter `v: Vec<i64>` and `(Vec<i64>, i64)` are unchanged. Rows: `traits_checked.sh` TV1 (the filed repro verbatim), TV2, TV2b, TV3, TV4 and TVK; mutations MTV1 RED 5, MTV2 RED 1. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G3), applying D4 (a) to the trait
signature reader (issues/archived/2026-10-14-vec-type-argument-unread-outside-annotations.md). Pre-existing: identical on the
slot-open compiler (2600f67f's build/cycc) and on the lane tree after G3 (fce26f17).
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D9 — (a) Refuse it at the trait, once, with the fn's words.
**Severity:** Low — the trait accepts a signature no impl can define (an impl's `fn a(self): Vec<i64>` is refused).
**Kind:** language (a refusal the fn form already has; the trait form's words are the user's call).

## Reproduction

```cyrius
include "lib/vec.cyr"
trait Sh { fn a(self): Vec<i64>; }
fn main(): i64 { return 4; }
syscall(60, main());
```

```
$ build/cycc < n3.cyr > n3 && ./n3; echo $?
4
```

The same return on a fn:

```
$ printf 'include "lib/vec.cyr"\nfn f(): Vec<i64> { return 0; }\nsyscall(60, 4);\n' | build/cycc > /dev/null
error:<source>:2:9: type 'Vec' cannot be a fn return type
```

Since 6.7.14 the trait reader checks the Vec's element (`fn a(self): Vec<nosuch>;` is "unknown type 'nosuch' as a
Vec element"), but the Vec return itself is still accepted.

## Root cause

`_trs_type` (src/frontend/parse_fn.cyr) resolves the return's name with `_trs_name` (`_tn_resolve_at`: `Vec` is a
handle name) and has no return-type vocabulary check; PARSE_FN_DEF's return reader refuses `Vec`
(`_bx_ret_or_refuse` / the return vocabulary).

## Fix direction

In `_trs_type`'s return position (`nm < 0`, the member's `: T`), refuse what a fn's return refuses, with the same
words, once. Rows: the repro refused once; controls `fn a(self): i64;`, `: *Vec<i64>` (a pointer return is a return
type), a parameter `v: Vec<i64>`.
