# Release gate's cross-OS leg runs only the `vr01_` glob — CI runs the full corpus, so the gate can be green while CI is red

**Status:** 🟡 **OPEN** — systemic gate gap. **Filed:** 2026-07-14 at the v6.4.64 close.
**Severity:** Medium (no wrong code ships *from* this — but it lets a real regression pass the check
we treat as authoritative). **Deferred to follow-up by the user.**

## The gap

`scripts/release-gate.sh` step 4 invokes:

```sh
sh scripts/cross-os-selfhost.sh "$H" "vr01_"
```

so on ecb / ach / cass / pi it runs the compiler self-host plus **only the ~27 `vr01_*.tcyr`**.
CI's `aarch64 Native` job runs the **full 248-tcyr corpus** on real hardware
(*"the first on-hardware tcyr coverage beyond self-host + funcgate"*).

**The gate therefore cannot see a regression in any non-`vr01_` tcyr on a non-x86 target.**
check.sh's 147 gates run the full corpus, but on **x86 only**.

## How it bit (v6.4.64, the reason this is filed)

An ESYSXLAT entry for x86-52 (getpeername) collided with the aarch64 peer's own `SYS_FCHMOD = 52`
and remapped **fchmod → getpeername** on aarch64. Result:

- `sh scripts/release-gate.sh` → **GREEN** (147/147, all four hosts `SELFHOST_OK` + `LIBTEST_OK`)
- CI `aarch64 Native` → **RED**: `FAIL: sandbox_syscalls (1)` — 246 pass / 1 fail (of 248)

`sandbox_syscalls.tcyr` is not a `vr01_` file, so the gate never ran it on aarch64. The gate was
green on a tree with a broken syscall. (Fixed in v6.4.64 by dropping the ESYSXLAT approach for
per-arch wrappers — but the gate's blindness is the durable problem.)

This is the same *shape* as the v6.4.59 finding — "ach was never in the release gate", which was
closed by the systemic fix of adding ach to it. Here the host is present; its **coverage** is the
subset.

## Why `vr01_` exists (do not just delete the filter)

The glob is a deliberate cost control: each host leg tars the tree, ships it, builds a native
compiler, and runs the tests over SSH. Running 248 tcyr × 4 hosts every release is a real
wall-clock and flakiness bill, and `cross-os-selfhost.sh` must stay one-host-at-a-time (fixed
`/tmp` + remote paths clobber under concurrency — see CLAUDE.md).

So the fix is a **coverage decision**, not a one-word change.

## Options (decide at pickup)

1. **Full corpus on one host, `vr01_` on the rest.** pi is the cheapest aarch64 and is where the
   syscall-translation class bites. Catches this bug; adds one host's full run to the gate.
2. **Widen the glob to the classes that translate syscalls** (e.g. `vr01_` + `sandbox_` + `io_` +
   `net_`). Cheaper, but it is a guess about where the next gap is — the same reasoning that left
   arity 5–8 in the Win64 CI gate while the bug sat at 10.
3. **Accept it and make the gate SAY so.** Print `cross-OS: vr01_ subset only (N of 248) — CI runs
   the full corpus` in the summary. Cheapest, and strictly better than the status quo, because the
   gate currently *reads* as authoritative. Pair with any of the above.
4. **Mirror CI's aarch64-native job into the gate.** Most faithful, most expensive.

**Recommendation: (3) immediately + (1).** The gate calling itself GREEN while blind to 221 of 248
tests on three targets is the actual defect; saying so costs nothing. Then buy back real coverage on
pi, where the per-arch syscall numbers make regressions most likely.

## Acceptance criteria

- A regression in a non-`vr01_` tcyr on aarch64 (e.g. re-introduce the fchmod/getpeername collision)
  turns `release-gate.sh` **RED**, not green.
- The gate's own output states what its cross-OS leg did and did not run.
- One host at a time preserved; wall-clock increase recorded in the CHANGELOG.

## Notes

- CLAUDE.md already warns "**A green CI checkmark is NOT verification**" — this issue is the mirror
  image, and worth adding once fixed: *a green release gate is not a green CI either.*
- Related: `feedback_dont_encode_codegen_bugs_as_language_rules` ("our gate can't see this" is a
  P0 smell, not a caveat).
