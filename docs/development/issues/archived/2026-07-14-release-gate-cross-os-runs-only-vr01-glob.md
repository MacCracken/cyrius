# Release gate's cross-OS leg runs only the `vr01_` glob — CI runs the full corpus, so the gate can be green while CI is red

**Status:** ✅ **SHIPPED v6.5.8** — the two defects are fixed: the per-test SSH loop is
batched into one connection per POSIX host (cass keeps its per-test loop; cmd.exe quoting
does not transfer safely), and the gate now PRINTS its own coverage ("34 of 258 … 224 NOT
run") so a subset can no longer read as authoritative. Full-corpus running is available
via `CYRIUS_CROSS_OS_FULL=1` — 75 s on ecb, affordable only because of the batching.
⛔ It is opt-in rather than default because the first measurement found **23 of 258**
failing on ecb, pre-existing and mostly downstream of the open macOS-threading issue;
those are filed separately as
[`2026-08-05-cross-os-full-corpus-23-failures-on-ecb`](2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md)
with the measured list. Flip the default when that count reaches zero.
**Filed as:** systemic gate gap; **re-verified live at the v6.4.82 closeout** (the gate
still passes the glob, and the counts below are re-derived, not carried over).
**Placement:** unpinned — 6.x-line release-engineering backlog, no dedicated slot; option (3) below
is a one-line change that folds into any release. Never 7.x.
**Filed:** 2026-07-14 at the v6.4.64 close.
**Severity:** Medium (no wrong code ships *from* this — but it lets a real regression pass the check
we treat as authoritative). **Deferred to follow-up by the user.**

## The gap

`scripts/release-gate.sh:92-94` invokes, for each of the four hosts:

```sh
for H in ecb ach cass pi; do
    sh scripts/cross-os-selfhost.sh "$H" "vr01_"
```

so on ecb / ach / cass / pi it runs the compiler self-host plus **only the `vr01_*.tcyr` subset**.
At v6.4.82 that is **30 of 251** `.tcyr` files (`ls tests/tcyr/vr01_*.tcyr | wc -l` = 30;
`ls tests/tcyr/*.tcyr | wc -l` = 251). CI's `aarch64 Native` job runs the **full corpus** on real
hardware (`.github/workflows/ci.yml:623`, *"Test suite (.tcyr) — full corpus on NATIVE arm64
(VR-01)"*).

**The gate therefore cannot see a regression in any non-`vr01_` tcyr on a non-x86 target** — 221 of
251 files, on three of the four gated targets. check.sh's **150** gates run the full corpus, but on
**x86 only**.

*(The 221 figure is unchanged from this file's original 248/27 arithmetic purely by coincidence: the
corpus grew by 3 and the glob by 3. It was re-derived, not carried forward.)*

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
3. **Accept it and make the gate SAY so.** Print `cross-OS: vr01_ subset only (N of M) — CI runs
   the full corpus` in the summary, deriving both counts from the globs so they cannot go stale.
   Cheapest, and strictly better than the status quo, because the gate currently *reads* as
   authoritative. Pair with any of the above.
4. **Mirror CI's aarch64-native job into the gate.** Most faithful, most expensive.

**Recommendation: (3) immediately + (1).** The gate calling itself GREEN while blind to 221 of 251
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
