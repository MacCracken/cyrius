# `defer` is skipped by ANY `return f(...)` in tail position — not only value-form pairs — OPEN

**Status:** 🟡 **OPEN** — filed by agnostic while designing its 0.1.4 store lock. Consumer-side
workaround in place (agnostic uses no `defer`); the compiler defect is untouched.
**Related:** [`2026-09-22-agnodrm-defer-skipped-on-value-form-result-return.md`](2026-09-22-agnodrm-defer-skipped-on-value-form-result-return.md).
That issue attributes the skip to value-form pair returns and states that a `defer` "runs when its fn
returns a single value". **The single-value case is only safe when the return expression is not a
direct call.** The trigger reproduced here is the tail-call return path itself, whatever the callee
returns — which likely makes the two issues one root cause.
**Discovered:** 2026-09-26. A probe written to check whether `lock(); defer { unlock(); }` was safe for
a store mutex left the lock held after `return some_query();`.
**Severity:** High — silent, with no diagnostic. A deferred unlock that is skipped is a **deadlock** on
the next acquire rather than a leak, and the construct's main uses (close an fd, release a lock, unlink
a temp file) all fail the same way.
**Affects:** cycc 6.6.6 — x86_64, `CYRIUS_DCE=1`, and `--aarch64` run under qemu, identical output.
Earlier releases not bisected.

## Summary

A `defer { ... }` block does not run when the fn leaves through `return <call>(...);`. It does run
for `return <literal>;`, `return <local>;`, and `return <call>() + 0;` — any return whose expression is
not *just* a call. The callee's return type does not matter: a plain `fn _value(): i64 { return 42; }`
triggers it.

## Reproduction

[`repros/2026-09-26-defer-skipped-on-tail-call-return.cyr`](repros/2026-09-26-defer-skipped-on-tail-call-return.cyr)

```cyr
var ran = 0;
fn _mark(): i64 { ran = ran + 1; return 0; }
fn _value(): i64 { return 42; }
fn _plus(n): i64 { return n + 1; }

fn tail_zero_arg(): i64         { defer { _mark(); } return _value(); }          # SKIPPED
fn local_first(): i64           { defer { _mark(); } var r = _value(); return r; } # runs
fn tail_with_arg(): i64         { defer { _mark(); } return _plus(41); }         # SKIPPED
fn arithmetic_after_call(): i64 { defer { _mark(); } return _value() + 0; }      # runs
```

```
$ cyrius build repro.cyr out && ./out
0 1 0 1          # expected 1 1 1 1
```

A longer probe (a lock counter) also showed that the call in tail position **observes the lock still
held** and the caller returns with it **still held** — the deferred block is not reordered, it is
dropped.

## Root cause (speculation — flagged)

`return f(...)` takes the tail-call emitter (the 6.6.6 CHANGELOG's `#deprecated` entry names this path:
"`return olde();` takes the tail-call path"). A jump into the callee cannot run the caller's
epilogue-walked deferred blocks (`src/frontend/parse_fn.cyr` ~6260–6300 per the related issue) after
the callee returns, because the callee returns straight to the caller's caller. Unverified.

## Proposed fix

Disable the tail-call lowering in any fn that has at least one `defer` (or whose flagged-defer set is
non-empty at the return site), and emit a normal call + epilogue instead. The same rule covers the
related issue's pair tail calls. A gate running this repro per target would pin it.

## Exposure seen in one consumer's vendored `lib/` (agnostic, 2026-09-26)

A scan for fns that reach `return <call>(...)` after a `defer`: **sigil — 8 fns** (e.g. `tpm_seal`,
`ima_get_status`, `ima_read_measurements`) and **kavach — 4 fns**, including
`security_apply_landlock`, whose deferred `SYS_CLOSE` of the ruleset fd is skipped on five of its exit
paths. Most of those return value-form pairs, so they overlap the related issue.

## Consumer-side workaround

Do not use `defer` for anything that must happen. agnostic's store lock is released by a wrapper
(`lock; var r = body(...); unlock; return r;`), which returns a local and cannot hit this path.
