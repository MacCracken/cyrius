> **RESOLVED v6.2.38** — Option 1 shipped: `panic(msg)` + `assert_fatal(cond, msg)`
> added to `lib/assert.cyr` (portable `sys_exit`; `tests/tcyr/assert_fatal.tcyr`).
> See CHANGELOG [6.2.38].

# stdlib `assert` is print-and-continue (test-only) — no fail-loud runtime panic primitive

**Filed:** 2026-06-22 (by a tarka consumer — tarka 0.8.0 hardening audit)
**Severity:** P3 — footgun / missing primitive; a ~6-line consumer workaround exists.
**Component:** `lib/assert.cyr` (stdlib).

## Observation

`lib/assert.cyr`'s `assert(cond, name)` prints `  FAIL: <name>` to stderr, increments a
failure counter, and **returns** — it does **not** abort:

```cyrius
fn assert(cond, name): i64 {
    _assert_total = _assert_total + 1;
    if (cond == 1) { _assert_pass = _assert_pass + 1; }
    else {
        _assert_fail = _assert_fail + 1;
        syscall(1, 2, "  FAIL: ", 8);
        syscall(1, 2, name, strlen(name));
        syscall(1, 2, "\n", 1);
    }
    return 0;                 # <-- continues regardless
}
```

This is **correct for its intended use** — the test harness (`assert_summary` tallies
`_assert_pass`/`_assert_fail`), where a run should report *all* failing checks rather than
abort on the first. The issue is not that `assert` is broken.

## The gap

There is **no stdlib fail-loud assertion / `panic(msg)`** for non-test (library/runtime)
code. A consumer that reasonably reaches for `assert(precondition, "...")` as a *runtime
guard* gets the test semantics: it prints a FAIL line and then **continues into the very code
the check was meant to prevent**. In a language with no bounds checking, that is dangerous —
e.g. a failed buffer-bounds or group-size precondition prints a warning and then performs the
out-of-range `store64` anyway, which is silent heap corruption rather than a clean abort.

## Concrete case (tarka 0.8.0)

tarka's 0.8.0 security/hardening audit needed fail-loud precondition guards on public entries
(beam width vs a fixed buffer cap, GRPO group size vs `GMAX`, count knobs ≥ 1). `assert`
could not be used — on a violated precondition it would print but then let the corrupting
write proceed. tarka instead rolled its own:

```cyrius
fn guard(cond, msg): i64 {
    if (cond == 0) {
        var n = 0; while (load8(msg + n) != 0) { n = n + 1; }
        syscall(1, 2, "tarka: precondition violated: ", 30);
        syscall(1, 2, msg, n);
        syscall(1, 2, "\n", 1);
        syscall(SYS_EXIT, 1);     # <-- the missing "stop"
    }
    return 0;
}
```

Every consumer doing runtime precondition checks (any subsystem that indexes raw buffers from
public arguments) will independently re-derive this. That is exactly the kind of primitive the
stdlib should own.

## Proposed resolution (pick one; not blocking)

1. **Add `panic(msg)` to the stdlib** — print `msg` to stderr (fd 2) + `SYS_EXIT(1)`. The
   canonical fail-loud primitive; consumers write `if (cond == 0) { panic("..."); }` or a
   thin `guard`/`assert_fatal` on top.
2. **Add `assert_fatal(cond, msg)`** alongside the test `assert` — same check, but aborts on
   failure. Keeps the test/runtime distinction explicit at the call site.
3. **At minimum, document** in `lib/assert.cyr` (and wherever `assert` is referenced) that
   `assert` is a *test-harness* assertion that prints-and-continues, and that runtime
   precondition checks must use a fail-loud path (panic) — so the footgun is signposted.

Option 1 (`panic`) is the smallest, most reusable addition and composes with the existing
`assert` family. `SYS_EXIT` already resolves on both host and agnos, so `panic` is portable.

## Workaround

Consumers can copy the 8-line `guard()` above (print + `SYS_EXIT`). No toolchain change
required to unblock; this issue tracks giving the ecosystem one canonical primitive instead of
N copies.
