# cass (Windows) full-corpus failures were never triaged into named skips vs real failures — the last count is v6.5.33's 32 of 282, the corpus is now 562, and no open issue tracks it — RESOLVED

> ✅ **RESOLVED in v6.7.12** (WN-2, `279b57fc`, and its review fix WN-2r, `03b28454`: measured on real hardware at the slot open (`7f57e532`, 589 tcyr, `CYRIUS_CROSS_OS_FULL=1`) — cass 563 / 589 with 0 timeouts, ecb and ach 585 / 589, pi 589 / 589 — and every failure classified from its own output re-run on the host: PE-inapplicable tests got a named `CYRIUS_TARGET_WIN` arm that still asserts its premise (socketpair + fork, POSIX fork + pipe, stdout / stderr capture, PROT_NONE, uname / sysinfo, /etc/passwd, the Win64 setjmp stub, /bin/echo); fixture defects were fixed (Linux /tmp paths, file-fed ws sockets, a getpid literal, an environment-sized trust-store floor, a one-time x509 build counted as per-call heap; on the Macs Linux's MAP_ANONYMOUS literal, LibreSSL's `s_server -accept`, missing kqueue rows, Darwin's gid 0 `wheel`); no hangs. The acceptance holds: cass 589 / 590, its one failure (`stdlib/result_stdlib.tcyr`) two filed PE defects — `2026-10-15-pe-open-failure-is-always-minus-one.md` and `2026-10-15-pe-read-failure-reads-as-eof.md` (6.7.14). The Macs' last failure, lib/pwd.cyr / lib/grp.cyr parsing Darwin's uid / gid -2 as 0, was fixed in WN-2r rather than filed: ecb, ach and pi 593 / 593 at the lane head. The cass line prints the count only, the stale 235 / 23 comment holds the measured figures, `CYRIUS_CROSS_OS_FULL=1` alone now starts the lib-test (the filed command ran none) and `docs/platform-status.md` carries dated per-host figures. The user's decision D8 (2026-10-15): ecb / ach / pi run the full corpus at the gate now (`CO_FULL_HOSTS` in `scripts/cross-os-selfhost.sh`, `CYRIUS_CROSS_OS_FULL=0` forces the subset), cass when its triage reaches zero — it joins when the two filed defects are fixed. Rows: the full-corpus legs themselves; NEW `crossos/pwd_grp_negative_id.tcyr` (45 rows; the old parsers fail 25). CLAUDE.md's Release Gate step 4 and cycle-discipline.md still describe the crossos subset (filed, `2026-10-15-process-docs-cross-os-leg-still-crossos-only.md`). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — NOT re-measured on hardware (this filing is from the scripts and docs; the planning lane was
told not to ssh to cass). Verified 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc`
2,057,744 B): `docs/platform-status.md:24` and `:41-46` state cass's full corpus as **250 pass / 32 fail of 282 at
v6.5.33** (2026-08-20) with "triaging them into named skips versus real failures is open"; the only filing,
`issues/archived/2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md`, was archived PREMISE OBSOLETE (ecb / ach /
pi went to zero) and handed the cass 32 to "the maintainer" without a file; no open issue or roadmap line names it
(`grep` of `docs/development/issues/*.md` and `roadmap*.md`). The full corpus is now **562** `.tcyr`
(`find tests/tcyr -name '*.tcyr' | wc -l`), the `crossos/` subset the release gate runs **267**, so the 32 is a
measurement of a corpus half today's size.
**Placement:** 6.7.12 — repair 2: the platform release (windows lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D8 — ecb / ach / pi full corpus now, cass when its triage reaches zero.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the `docs/platform-status.md` re-verification stated the 32 as open
and untriaged); filed by the 6.7.10 planning lane.
**Severity:** Medium — a coverage gap, not a known wrong result: about 295 `.tcyr` outside `crossos/` are never run on
Windows by any gate, and the residual that was last measured (32) is labelled by a guess, so a real PE regression in
that region is invisible.
**Affects:** the Windows (PE) leg of `scripts/cross-os-selfhost.sh` under `CYRIUS_CROSS_OS_FULL=1`; every release
since v6.5.33.

## Summary

`CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh <host>` runs the whole `tests/tcyr` corpus instead of the
`crossos/` subset. At v6.5.33 ecb, ach and pi were 282 / 282 and cass 250 / 32. The runner's failure line for cass
says `LIBTEST_FAIL: N test(s) on cass (PE-incompatible? fork/socketpair are POSIX-only)` — a question mark printed for
every failure, not a classification — and the docs and CHANGELOG [6.5.33] carried that guess forward as "the runner
labels these PE-incompatible". The archived issue's last instruction was to triage the cass residual into "genuinely
PE-inapplicable, so SKIPPED with a named reason" versus "real" before any decision on running the full corpus by
default; that triage never happened and nothing tracks it.

## Reproduction

Not run (no ssh to cass from the planning lane). The measurement the triage starts from, on the real host:

```sh
cd /home/macro/Repos/cyrius
CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh cass > /tmp/cass_full.out 2>&1; echo "rc=$?"
grep -E 'corpus:|ran [0-9]+ passed|TIMED OUT|failing:|LIBTEST_' /tmp/cass_full.out
```

What the repository says today (read-only, runnable anywhere):

```sh
cd /home/macro/Repos/cyrius
grep -n '250 pass / 32 fail' docs/platform-status.md
grep -n 'PE-incompatible' scripts/cross-os-selfhost.sh
find tests/tcyr -name '*.tcyr' | wc -l; find tests/tcyr/crossos -name '*.tcyr' | wc -l
grep -ln 'cass' docs/development/issues/*.md | xargs grep -l 'CROSS_OS_FULL'   # nothing open
```

```
actual:   platform-status.md:24 / :45 — 250 pass / 32 fail of 282 at v6.5.33, "triaging … is open"
          cross-os-selfhost.sh:750 — LIBTEST_FAIL: $cass_f test(s) on cass (PE-incompatible? fork/socketpair are POSIX-only)
          562 / 267
          (no open issue)
expected: a dated cass full-corpus figure with every failure named and classified, each class tracked
```

## Root cause

- `scripts/cross-os-selfhost.sh:746-752`: the cass leg's failure summary attaches the same speculative label to every
  failing test; nothing classifies them.
- `scripts/cross-os-selfhost.sh:606-613`: the comment justifying full-corpus as opt-in still cites "235 pass / 23
  fail" on ecb and "the open macOS-threading issue" — both obsolete since v6.5.33.
- No skip classification exists by design ("There is NO skip", `:7`); the corpus's per-target convention is in the
  test source — 90 `.tcyr` carry a `#ifdef CYRIUS_TARGET_WIN` arm (`grep -rl CYRIUS_TARGET_WIN tests/tcyr | wc -l`),
  e.g. `tests/tcyr/crossos/fork_refused_stays_negative.tcyr`.

## Proposed fix

The triage, in this order, on cass (wine — `docs/development/dev-tools-linux.md` — can pre-sort, but the verdicts
are cass's):
1. Measure: one `CYRIUS_CROSS_OS_FULL=1` run on cass at the lane's tree; record pass / fail / timeout and the
   `failing:` list with the tree's commit.
2. Classify each failure against its own output, never its name (the archived issue's lesson: "a plausible reading
   of the test NAMES … is wrong"): (a) PE-inapplicable — the test exercises a POSIX-only surface with no Windows route
   (`fork`, `socketpair`, POSIX signals, …): the TEST gains a `#ifdef CYRIUS_TARGET_WIN` arm that says so by name and
   still makes at least one assertion (the cass leg grades `N passed` with N ≥ 1); (b) a test-fixture portability
   defect (a Linux-only path or behaviour): fix the test; (c) a real PE defect: fixed in the lane if it is quicker
   than filing, else its own issue file with the repro; (d) a hang: classified the same way, with the timeout named.
3. Replace the cass leg's "(PE-incompatible? …)" label with the measured count only, and refresh the stale comment
   at `:606-613`.
4. Record the new full-corpus figure (dated, with its version) in `docs/platform-status.md`.
Acceptance: a cass full-corpus run whose every failure is in class (c) with an issue file, or zero failures. Whether
the release gate then runs the full corpus on any host by default is the user's call, asked once with the result
(the archived issue's open question: flip ecb / ach / pi now, or all four together).

## Consumer-side workaround

None needed by consumers; a Windows consumer meets only what its own tests exercise. Inside cyrius, until the
triage, a PE change outside `crossos/` is verified only by running the affected `.tcyr` on cass by hand.
