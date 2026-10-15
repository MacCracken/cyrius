# header_spellings_and_size.sh: H8's preprocessor-guard rows and H11 / H11b are skipped silently on a host with cc that is not x86_64 (no SKIP named, the gate PASSes) — OPEN

**Status:** 🟡 **OPEN** — read 2026-10-14 in tests/gates/toolchain/header_spellings_and_size.sh at l6711-tools @
a3d9837d (lines 255 and 331).
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 tools review) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 tools lane's review of the header struct-return bite.
**Severity:** Low — not reachable today (check.sh runs on ubuntu x86_64 only), but the gate reads PASS on an aarch64
or macOS-arm host with cc while two of its legs never ran: a gate that cannot run a leg says so BY NAME (CLAUDE.md,
verification habits), never a silent skip read as coverage.
**Affects:** tests/gates/toolchain/header_spellings_and_size.sh.

## Reproduction

```sh
grep -n 'uname -m)" = x86_64' tests/gates/toolchain/header_spellings_and_size.sh
```

```
255:if command -v cc > /dev/null 2>&1 && [ "$(uname -m)" = x86_64 ]; then     # H8's guard rows (x86_64 SysV / clang targets)
331:if command -v cc > /dev/null 2>&1 && [ "$(uname -m)" = x86_64 ]; then     # H11 / H11b, the linked C callers
```

Neither `if` has an `else` arm. On a host where `cc` exists and `uname -m` is not `x86_64` (aarch64 Linux, arm64
macOS), the H11 section header prints and nothing follows, H8's guard rows are absent, `skips` stays 0, and the gate
prints `PASS: header-spellings-and-size — …` with exit 0. Only the no-cc case is named (H10's SKIP, exit 77).

```
expected: each skipped leg named on its own line ("SKIP (named): H8's guard rows / H11 — needs cc on x86_64; this
          host is <uname -m>") and counted in `skips`, so the gate exits 77 (a SKIP, not a PASS).
```

## Root cause

The two conditional sections were written for the one CI host; their `else` arms were never added (H10 has one).

## Proposed fix

An `else` arm on each that names the skipped leg and its reason and increments `skips`; a mutation row (force the
condition false on x86_64: the gate must exit 77 naming both legs, not PASS).
