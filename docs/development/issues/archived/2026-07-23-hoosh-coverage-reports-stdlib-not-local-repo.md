# `cyrius coverage` reports on the vendored stdlib, not the local repo — FIXED (6.4.72)

**Fixed 2026-07-20 (6.4.72)** in `cbt/quality.cyr`. `cyrius coverage` now defaults to the
**project's own `src/`** (recursive), with `lib/` + `dist/` excluded; `--full` gives the old
vendored-stdlib behaviour; `--min <pct>` gates CI (non-zero exit below the floor); the **mode is
stated** in the summary and the number carries a `[reference coverage — a floor, not a correctness
proof]` caveat; and the module-name column is padded (the old `22 - llen` went negative for long
names, running the count into the name). The test **corpus now walks `tests/` recursively** (was
hardcoded `tests/tcyr/`), so projects whose suite lives at `tests/<name>.tcyr` (like hoosh) are
picked up. Verified: cyrius reports `183/1188 (15%)` over its own `src/`; hoosh reports `12/365 (3%)`
over its own `src/` (honest reference coverage — low because its suite is mostly a mirror; hoosh does
`include` a few src files, hence non-zero). The linked-vs-mirror distinction the issue raised is moot
for reference coverage — a referenced symbol is a watched symbol regardless of whether the test calls
or re-implements it; line coverage (where that distinction bites) is a separate future thing.
**Found in passing + filed separately:** `lib/fs.cyr`'s `find_files`/`find_files_with_prunes`
silently return 0 matches (the coverage rewrite works around them with `dir_walk` + inline
`str_ends_with`); those helpers back the TS-corpus release gates, so that's its own investigation.

---


**Discovered:** 2026-07-23 during **hoosh** v2.5.10 (scaffolding-parity band of its
rust-old port), while replacing the Rust project's codecov gate with a Cyrius one.
**Severity:** Medium — the subcommand runs and prints a confident summary, but the
number describes `lib/` rather than the project being built. Unusable as a project
gate, and actively misleading if trusted.
**Affects:** cycc **6.4.62** (the version hoosh pins; not bisected further back).

## Summary

`cyrius coverage`, run from a project root, reports coverage of the **vendored stdlib in
`lib/`** rather than the project's own sources. hoosh's ~465 functions across
`src/lib/*.cyr` + `src/main.cyr` do not appear in the output at all, and the headline
"Functions: 0/1097" counts stdlib functions — so the number is both wrong for the project
and permanently near zero for any project that does not exercise the whole stdlib (i.e.
all of them). "Libraries: 67/68 covered" reads like good news about the project; it is a
statement about which stdlib modules were touched.

## Reproduction

Any project with a vendored `lib/`. Using hoosh at v2.5.9
(`github.com/MacCracken/hoosh`, pin `cyrius.cyml` → 6.4.62):

```bash
cd hoosh
cyrius lib sync && cyrius deps
cyrius coverage
```

Actual:

```
  fs.cyr                0/13 fns
  io.cyr                0/31 fns
  hashmap.cyr           0/32 fns
  syscalls_linux_common.cyr0/61 fns
  ... (67 more stdlib modules)

-- Summary --
  Libraries: 67/68 covered
  Functions: 0/1097
```

Expected: a report over `src/lib/*.cyr` and `src/main.cyr`, with `lib/` excluded unless
asked for.

Note the cosmetic defect visible above too: `syscalls_linux_common.cyr0/61 fns` — the
name column is not padded for the longest module name, so the count runs into it.

## Root cause (speculation — Cyrius side to confirm)

The module walk appears to enumerate the resolved dependency/stdlib set (what
`cyrius lib sync` materialises into `lib/`) rather than the manifest's own source roots.
A project's `[package]` sources look like they are either not enumerated or are filtered
out as "not a library". Flagging as speculation; I did not read the coverage
implementation.

## Proposed fix

1. **Default to local-repo sources.** Everything under the project root that is not a
   vendored dependency — exclude `lib/` and whatever `cyrius deps` materialises.
2. **Add `--full`** for the current whole-world behaviour. That output is legitimately
   useful when working *on* cyrius itself, which is plausibly why it is today's default.
3. **Add `--min <pct>`** so it can gate CI directly (non-zero exit below the floor).
4. **State the mode in the summary** so a stdlib figure cannot be mistaken for a project
   figure.
5. Pad the module-name column.

```
cyrius coverage              # local repo sources only (new default)
cyrius coverage --full       # local + vendored stdlib/deps (today's behaviour)
cyrius coverage --min 80     # CI gate
```

## Design question worth settling first

Whether a local-repo number is even achievable depends on how the project's tests are
built, and this affects what mode 1 should report.

Projects whose suites are **self-contained mirrors** never execute the code under test.
hoosh's `tests/hoosh.tcyr` re-implements the logic it tests with stdlib-only includes,
because `src/main.cyr` is a *program*, not a library — including it drags in the whole
gateway's globals and background threads. For that shape, line coverage of `src/` is
structurally 0% regardless of test quality.

So the local mode probably wants to distinguish:

- **linked suites** — real line/function coverage; and
- **mirror-style suites** — an honest `0% (no test links src/)` with that explanation,
  rather than a bare 0 that reads as a failing project.

## Consumer stopgap

hoosh gates on its own `scripts/coverage.sh` instead. It measures **symbol** coverage —
is every function defined in `src/` at least *referenced* by the suites — and documents
plainly that this is a floor against unwatched code, not a correctness proof. Its stated
limitation: because the mirror re-implements rather than calls, it cannot catch **mirror
drift**, where `src/` and its mirror diverge while both stay internally consistent. That
has bitten hoosh twice (v2.5.6 pricing local-provider ordering, v2.5.7 audit chain-link
verification — in both cases the mirror was correct, `src/` was wrong, and the suite
stayed green).

Every first-party project wanting a coverage gate currently has to grow its own variant
of this script, which is the duplication this issue is asking to remove.
