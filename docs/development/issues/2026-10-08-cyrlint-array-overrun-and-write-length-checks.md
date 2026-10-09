# cyrlint has neither of its two planned checks: a bare-local-array overrun and a write-length / literal mismatch — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: cyrlint built from `programs/cyrlint.cyr` by the
tree's `build/cycc` reports `0 warnings` (rc 0) on
[`repros/2026-10-08-cyrlint-array-overrun-and-write-length-checks.cyr`](repros/2026-10-08-cyrlint-array-overrun-and-write-length-checks.cyr);
cycc builds it (rc 0) and the binary writes `hello` (no newline) and `abc\n\0\0\0`. A census of the tree found one LIVE
write-length mismatch (below).
**Placement:** unpinned — 6.x-line backlog — never 7.x (one cyrlint bite; the overrun half may fold into C2, the
bounds-checked mode, per roadmap.md).
**Discovered:** v6.5.30–.33 (the write-length off-by-ones) and the 6.6.20 re-triage (roadmap-future.md § *DX / cyrlint
tooling*, commit f9f6bfd6); filed 2026-10-08 from roadmap.md.
**Severity:** Low — preventive lint; the one live mismatch truncates a SKIP message.
**Affects:** cyrlint through 6.7.6.

## Summary

1. **Bare-local-array overrun.** A bare local `var a[N]` is N BYTES (rounded to 8), not N slots. Since 6.6.12 the
   compiler refuses `a[i]` on a bare array by name (`cannot subscript 'a': … a bare var a[N] states no element width`),
   so the remaining shape is the explicit offset: `var a[16]; store64(&a + 16, 3);` writes past the array with no
   diagnostic from cycc or cyrlint. The lint compares each constant `&a + K` load/store (plus its width) against the
   declared byte size. roadmap-future.md recorded "~21 intentional sites in-tree" (not re-counted here).
2. **Write length vs literal.** `syscall(SYS_WRITE, fd, "literal", LEN)` / `sys_write(fd, "literal", LEN)` with LEN ≠
   the literal's byte length truncates or over-reads silently. Census 2026-10-08 (a scratch scanner over `src cbt
   programs lib tests bootstrap`, matching `syscall(SYS_WRITE|1, fd, "…", N)`, `sys_write(fd, "…", N)` and
   `_aw_write(fd, "…", N)`; raw bytes, two-character backslash escapes counted as one): **1,767 sites, 1 mismatch** —
   `tests/tcyr/platform/shadow_pam.tcyr:55`, `"  SKIP: unix_chkpwd not installed — skipping auth tests\n"` is 58
   bytes, LEN is 56 (the em dash counted as one character), so the SKIP line loses `s\n`. (v6.5.33's count was 532
   sites, 0 mismatches, with a narrower pattern.)

## Reproduction

```sh
cat programs/cyrlint.cyr | build/cycc > /tmp/cyrlint && chmod +x /tmp/cyrlint
/tmp/cyrlint docs/development/issues/repros/2026-10-08-cyrlint-array-overrun-and-write-length-checks.cyr
# === cyrlint: … ===  0 untracked deferrals  0 warnings   (rc 0)
printf '  SKIP: unix_chkpwd not installed — skipping auth tests\n' | wc -c     # 58, the call says 56
```

Expected: a warning on each `BAD` line of the repro (two overruns, two length mismatches). Actual: none.

## Root cause

`programs/cyrlint.cyr` implements neither check (re-checked at the 6.6.20 re-triage and again here).

## Proposed fix

One cyrlint bite with both rules, each with a gate over the tree: (1) per fn, record bare `var a[N]` sizes and warn on
a constant-offset `load*/store*(&a + K)` whose `K + width > N` (an allowlist comment for the intentional sites);
(2) warn when a write call's literal length ≠ LEN. ⚠ Implementation trap from roadmap-future.md: count raw bytes and
collapse only two-character backslash escapes — round-tripping through a `unicode_escape`-style decoder double-decodes
every em dash (23 false mismatches at v6.5.33). Fixing `shadow_pam.tcyr:55` (56 → 58) belongs with the gate that
catches it.
