# A non-generic fn's parameter type `Mp<K, V>` with `K` / `V` never declared compiles silently — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro builds rc 0.
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
