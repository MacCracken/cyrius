# Permanent syscall-write byte-length gate (DOTALL) — follow-on

> **CONSOLIDATED — v6.4.15 hygiene pass.** Folded into the "DX / cyrlint tooling
> (watching)" list in [roadmap-future.md](../../roadmap-future.md) (batched with the
> bare-local-array slot-write lint as one cyrlint slot). Archived; no consumer blocked.

> **Filed 2026-06-25, not yet scheduled.** Carried from the v6.2.44 reactive
> slot; pulled out of the cut because it's a new cyrlint rule / gate with real
> false-positive exposure that needs careful iteration, and it prevents *future*
> regressions rather than fixing a live bug (the v6.2.39 audit already cleaned
> the existing mismatches). Land on a bug-bandwidth line or fold into the next
> tooling change.

**Filed:** 2026-06-25 · **Status:** open / unscheduled · **Severity:** P3 (DX/hardening)

## What

A standing gate that flags `syscall(SYS_WRITE | 1, fd, "literal", LEN)` where
`LEN != ` the literal's byte length, **including multi-line calls**. The v6.2.39
diagnostic-byte audit used a single-line regex and missed a multi-line syscall;
this makes the check permanent and DOTALL-aware. A wrong length over-reads
adjacent rodata (garbage tail) or truncates the message — silent and easy to
introduce.

## Why it's medium, not small (false-positive exposure)

- **543** single-line `syscall(SYS_WRITE/1, 2, …)` sites in `src/`+`lib/` today;
  the gate must validate all of them as correct without a single false positive,
  or it breaks the lint gate.
- Multi-line `syscall( … )` calls exist in every `src/main*.cyr` (the cmdline
  parse blocks) — the gate must scan forward to the closing `)`, not assume one
  line.
- It must compute the literal's true byte length with escape handling (`\n`,
  `\t`, `\0`, `\\`, `\"` each = 1 byte) — the place a naive implementation
  miscounts and false-positives.

## Suggested approach

Add it as a `cyrlint` rule (cyrlint already understands string literals and
runs in check.sh + ci.yml), not a separate program. Honor `#skip-lint`. Match
`syscall(` → first arg is `1`/`SYS_WRITE` → a string-literal arg → a trailing
integer-literal arg; compute escaped byte length; warn on mismatch. Build a
corpus probe (a deliberately-wrong length) to prove it fires, and run it over
all 543 sites to prove zero false positives before wiring into the gate.
