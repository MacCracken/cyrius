# cycc_aarch64 does not refuse a reachable undefined **tail** call — it emits a SIGILL binary with no diagnostic — OPEN

**Status:** 🟡 **OPEN** — a cross-arch gap in the v6.3.2 fix of
`archived/2026-06-25-undefined-fn-reachable-call-hard-error.md`, which made a reachable undefined
call a hard error by default.
**Placement:** unpinned — 6.6.x-line backlog.
**Discovered:** 2026-09-22, during agnodrm's 1.6.2 harness work. A fuzz harness missing an include
built clean on `--aarch64` but warned on x86_64; the tail-call shape was then isolated.
**Severity:** Medium — a hard failure on x86_64 / agnos ships silently on aarch64 as a crashing binary.
Workaround: build the same sources for x86_64 too, which refuses.
**Affects:** cycc_aarch64 6.6.0, 6.6.2, 6.6.4, 6.6.5, 6.6.6 (every 6.6.x tested; not bisected further).

## Summary

On aarch64, a reachable call to an undefined fn is refused exactly as on x86_64 **unless the call is a
tail call** (`return undefined_fn(...)`). Then the aarch64 build prints nothing, not even the
`warning: undefined function` line, exits 0, and the binary dies with SIGILL at the `UDF #0` stub.

## Reproduction

[`repros/2026-09-22-aarch64-undefined-tail-call.cyr`](repros/2026-09-22-aarch64-undefined-tail-call.cyr):

```cyr
include "lib/syscalls.cyr"
fn main(): i64 { return no_such_fn(2); }
var r = main();
sys_exit(r);
```

| build (6.6.6) | result |
|---|---|
| `cyrius build` | `warning: undefined function 'no_such_fn'` + `error: refusing to emit binary with 1 reachable undefined function(s)`; exit 1 |
| `cyrius build --agnos` | same; exit 1 |
| `cyrius build --aarch64` | no diagnostic, `OK (…)`, exit 0; `qemu-aarch64 ./out` → SIGILL (exit 132) |
| `--aarch64`, non-tail body `var x = no_such_fn(2); return x + 1;` | refused like x86_64; exit 1 |

With or without `CYRIUS_DCE=1` the result is the same.

## Root cause (reading of the source — the Cyrius agent should confirm)

`src/backend/aarch64/fixup.cyr` emits a tail call as fixup **type 4** and patches it as `B rel26`
(the `ftype == 4` arm near line 186, which also writes the `UDF #0` sentinel for an undefined target).
The reachability-filtered undefined-fn check that follows (near lines 543–571) only examines
`u59_uftype == 2 || u59_uftype == 3`. So an undefined tail-call target is patched to `UDF` but never
counted into `undef_count`, and neither the warning nor the v6.3.2 refusal can fire. The x86_64
backend refuses the same program, so its tail-call fixups are evidently covered by its check.

## Proposed fix

Include `ftype == 4` in the aarch64 undef check (and audit any other backend with a separate
tail-call fixup type), plus a gate that builds the repro above with `--aarch64` and expects exit 1.

## Consumer-side workaround

agnodrm builds every source for x86_64 and agnos as well as aarch64, and gates all three logs, so the
x86_64 / agnos refusal catches the class. It has no aarch64-only code. A consumer with an
`#ifdef CYRIUS_ARCH_AARCH64` branch has no such cover and should run its aarch64 binary (e.g. under
`qemu-aarch64`), not just build it.
