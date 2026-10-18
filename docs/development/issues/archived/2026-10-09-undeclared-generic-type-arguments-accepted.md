# A non-generic fn's parameter type `Mp<K, V>` with `K` / `V` never declared compiles silently — RESOLVED

> ✅ **RESOLVED in v6.7.14** (GN-11 (`fce26f17`; the user's decision D6 (a), 2026-10-16: refuse it, once, naming the type): PARSE_FN_DEF's pass-2 parameter and return sites read a generic struct's type arguments with the reader a local's annotation uses (`_gtype_sid_def` → `_targ_chk`). The filed repro is refused once, "2:14: unknown type 'K' as a type argument" (it built), on x86_64 and the aarch64, cx and PE compilers, called or not; `m: Mp<Nonexist, i64>`, `m: *Mp<K, V>`, `: Mp<K, V>` and `m: Box<Zork>` likewise; a generic's own `fn gm<K, V>(m: Mp<K, V>)` and a `Box<Pt>` parameter with Pt declared below the fn are unchanged. Rows: `frontend/generic_type_arg_unknown_refused.sh` SG0 (the repro verbatim) – SG7 and SGK; mutation MSG1 RED SG0 – SG7. Not closed here (filed, 6.7.15): a multi-value return element `(Box<Zork>, i64)`, a trait member's `b: Box<nosuch>` and a `*fn(Box<Zork>)` parameter are still unread, and a struct field `p: *Box<Zork>` is read only at a use. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro builds rc 0.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D6 — (a).
**Discovered:** the 6.7.7 filing step (met while choosing a tools repro); filed 2026-10-09.
**Severity:** Low — an unknown type name is otherwise an error since v6.6.10
**Affects:** cycc ≤ 6.7.7

## Reproduction

```
struct Mp<K, V> { k: K; v: V; }
fn gm(m: Mp<K, V>, b) { return b; }
syscall(60, 0);
```
Builds (rc 0). `gm` is not generic, so `K` and `V` name nothing.

## Proposed fix

Resolve a generic struct's type arguments in a parameter annotation; an unknown name is refused naming the type, as
an unknown field type is (v6.6.10).
