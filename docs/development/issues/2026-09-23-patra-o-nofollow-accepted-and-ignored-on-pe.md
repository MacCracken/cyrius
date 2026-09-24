# `O_NOFOLLOW` is accepted and ignored on Windows — a symlink-refusal flag that fails open — OPEN

**Status:** 🟡 **OPEN**: from this repo's own CHANGELOG [6.6.6] (the PE `open` flag-translation entry)
and `lib/syscalls_windows.cyr:139` (`O_NOFOLLOW = 131072`). Found by reading; **not run on
Windows**. The measurement quoted below is cyrius's own, on real `cass`.
**Placement:** unpinned — `_pe_open_flags` (`src/backend/x86/emit.cyr`) or the PE `file_open` path.
**Discovered:** 2026-09-23 during patra's 1.15.0 cut.
**Severity:** Medium–High on Windows: a flag callers pass for safety is silently not applied. It is
security-relevant wherever an attacker can create a name in the target directory.
**Affects:** cyrius 6.6.6.

## Summary

CHANGELOG [6.6.6] states that `O_DIRECTORY` / `O_NOFOLLOW` *"stay ignored **deliberately**"* on PE,
because `FILE_FLAG_OPEN_REPARSE_POINT` opens a symlink where `O_NOFOLLOW` refuses one. It records the
cost, measured on real `cass`: *"creating over a dangling symlink SUCCEEDS and creates the symlink's
*target*, where the identical flags on Linux fail"*. It leaves the fix *"a semantics decision left
open, not a silent gap"*.

This filing is the consumer side of that open decision. For a caller, the flag is accepted, compiles,
and does nothing, so a planted symlink redirects the open. That is how a flag fails open.

## Consumers affected

- **patra** relies on the refusal at five opens: `_pt_file_create`
  (`O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW`, the exact `CREATE_NEW` case cyrius measured),
  `_pt_file_open`, `wal_start` (with `O_TRUNC`, so a planted `<db>.wal` link would truncate its target
  on Windows), `wal_recover`, and `jsonl_open`.
- **sigil**: `luks_write_keyfile`, named in the CHANGELOG entry.
- By grep of `~/Repos/*/src`, **22 repos** pass `O_NOFOLLOW`: aegis, agnoshi, akshara, attn11, chakshu,
  commandress, cyrius-doom, encom-hits, hapi, kavach, kriya, mihi, mirshi, patra, phylax, sankoch,
  shakti, sigil, stiva, thoth, whirl, yukti.

## Options (the maintainer's call)

1. **Refuse, as POSIX does**: fail the open with an ELOOP-equivalent when the final component is a
   reparse point. The CHANGELOG already sketches two ways, a stat for `FILE_ATTRIBUTE_REPARSE_POINT`
   or `FILE_FLAG_OPEN_REPARSE_POINT` plus a check on the opened handle. The handle-based one avoids a
   check-then-open race. For `O_CREAT | O_EXCL`, whether `CREATE_NEW` with
   `FILE_FLAG_OPEN_REPARSE_POINT` fails over an existing (dangling) link needs checking on real
   hardware; patra has not verified it. ⚠ **Behaviour change**: any of the 22 repos whose
   `O_NOFOLLOW` open currently goes through a reparse point on Windows starts failing there. That is
   the flag's meaning, but it is a visible change, so it deserves a grep of their Windows use first.
2. **Leave it ignored, and document the gap at `file_open` / `O_NOFOLLOW`**, not only in the
   CHANGELOG and the guide, so a caller reading the wrapper learns the flag is inert on PE.

patra's input to the decision: it needs the refusal and never wants the link opened itself.

## What patra does meanwhile

Nothing in code. patra documents the gap in `roadmap.md` *Platforms* and `SECURITY.md`: "Windows is
suitable only for single-process, non-durable use … `O_NOFOLLOW` is not enforced".
