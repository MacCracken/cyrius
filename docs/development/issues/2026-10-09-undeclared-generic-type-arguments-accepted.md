# A non-generic fn's parameter type `Mp<K, V>` with `K` / `V` never declared compiles silently — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro builds rc 0.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) (the diagnostics lane) — placed 2026-10-09 — never 7.x.
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
