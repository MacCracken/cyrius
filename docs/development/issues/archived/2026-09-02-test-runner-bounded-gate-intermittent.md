# `test_runner_bounded` axis 1b went red once under load and I could not reproduce it

**Status:** ✅ **CLOSED at v6.5.50 — and the leading hypothesis below was TESTED AND REFUTED.**

⛔ **The zombie theory is WRONG.** This file proposed that `orphan_pids` counts a SIGKILLed-but-unreaped
child, and flagged it as "the kind that is comfortable to believe". Measured 2026-09-04: a zombie's argv
collapses to `[test_bin] <defunct>`, so it **cannot match the `/cyrius-NNN/test_bin` PATH pattern** the
sampler greps for — a zombie is structurally invisible to this gate. Adding a process-state filter, the
fix this file recommends, would have changed nothing.

What a single sample CAN legitimately catch is the window between `kill(pid, 9)` and the kernel finishing
teardown, during which the dying child still carries its full argv — measured at **under 0.2 s**, against
a 0.5 s sample interval. That transient is not what the row is about: the property is "the deadline KILLS
rather than ABANDONS", and an abandoned child lives for the rest of the suite. Axis 1b now samples at
0.25 s and requires **two consecutive** samples at 2+ children. The abandon-mutation
(`sys_kill(pid,9)` -> `sys_kill(pid,0)`, rebuilt CLI) holds the overlap for **19 consecutive** samples,
so sensitivity is unchanged.

⭐ The file's own warning — that this gate exists because a flaky-looking red got dismissed — is why the
hypothesis was measured instead of adopted. A state filter would have been a plausible-looking no-op.
**Placement:** unpinned — 6.x-line backlog. Test-infrastructure reliability.
**Discovered:** 2026-09-02 during the v6.5.42 slot, on an otherwise-green `scripts/check.sh` run.
**Severity:** Low as a defect, **Medium as a signal** — see *Why this is filed rather than shrugged off*.
**Affects:** `tests/gates/toolchain/test_runner_bounded.sh` axis 1b, cyrius 6.5.42.

## What happened

A full `sh scripts/check.sh` reported:

```
FAIL: never more than the one child it is currently running — expected 1, got 2
FAIL: test runner is BOUNDED: ...
```

Immediately afterwards, with no code change: the gate passed **3/3 standalone** and then **1/1
inside a full `check.sh`**. Final state 220/0. Machine load at the time of the failure was
`load average: 2.64` on a 16-core box, with several backgrounded compiles from the same session
having recently finished. No stray `test_bin` processes existed before or after (`ps` checked).

## Why this is filed rather than shrugged off

⚠ **`max 2` is the exact signature of this gate's own MUTATED state.** Its header records the
mutation proof as *"pristine max 1, `sys_kill(pid,9)`→`sys_kill(pid,0)`+WNOHANG max 2"*. So the
value observed is not a generic wobble — it is the number the gate was designed to distinguish.

⛔ **And this gate exists precisely because a flaky-looking red got dismissed.** Its own header:
19 leaked test children were found on the maintainer's box, the oldest at 1h42m, together ~13 of
16 cores; they flipped the release gate's `alloc_via_no_plumbing` 14 ns tripwire RED, and **two
implementers wrote that off as "environmental load"**. Writing this one off the same way, in the
gate built to stop that happening, would be the same mistake at one remove.

## Leading hypothesis (UNPROVEN — do not act on it without evidence)

The sampler at `tests/gates/toolchain/test_runner_bounded.sh:110` counts by argv match:

```sh
ps -eo pid=,args= | grep '/cyrius-[0-9]*/[t]est_bin' | awk '{print $1}' | sort
```

It applies **no process-state filter**. A child that has been SIGKILLed but not yet reaped stays
visible with intact argv for a short window, so a sample landing between "kill child A" and
"child A fully torn down / child B started" could legitimately see two. Under load that window
widens, which fits the one observation.

⚠ **This is a guess and it is the kind that is comfortable to believe**, because it makes the
gate wrong instead of the runner. It has NOT been demonstrated. Do not "fix" it by making the
sampler tolerant — requiring two consecutive over-count samples, or filtering `stat=Z` — until
the second process has actually been identified. A real leak persists and would survive either
change; a gate loosened on an unproven theory stops distinguishing the two.

## Acceptance

1. The sampler records **what the second process was** (pid, ppid, state, argv, and whether the
   runner had already SIGKILLed it) rather than only a count, so the next occurrence is
   diagnosable from its output instead of irreproducible.
2. Reproduce under deliberate load (e.g. the gate run concurrently with a `-j16` build) — either
   the transient appears, confirming the sampling hypothesis, or it does not, which points back
   at the runner.
3. Only then, if it is a sampling artefact, tighten the sampler — and record in the gate why the
   count was previously trusted raw.
