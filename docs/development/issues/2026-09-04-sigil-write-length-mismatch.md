# OUTBOUND → sigil: one `sys_write` declares 25 bytes for a 26-byte literal

**Status:** 🟠 **OPEN — outbound. Must be fixed in the sigil SOURCE repo, not in cyrius.**
**Found by:** cyrius v6.5.47, `tests/gates/frontend/write_literal_lengths.sh`
**Affects:** `lib/sigil.cyr:242` in cyrius's vendored copy — i.e. sigil's own source.

## The defect

```cyrius
sys_write(2, "kernel module not loaded: ", 25);
```

`"kernel module not loaded: "` is **26** bytes including its trailing space. The write is
under-declared by one, so the message prints as `kernel module not loaded:` — the separating
space before whatever is written next is lost.

## Why cyrius is not fixing it here

`lib/sigil.cyr` is a **vendored** copy produced by `cyrius deps`. A fix applied to the fold
evaporates at the next re-vendor — CLAUDE.md's *"Fix the SOURCE repo, not the fold"*. This needs:

1. the fix in sigil's own source,
2. a sigil version bump + `cyrius distlib` regen (**all** profiles, not just the main bundle —
   see the v6.4.79 note about nine sub-profiles keeping stale code),
3. a re-vendor into cyrius.

That is cross-repo coordination, which is a named reason to file rather than fix.

## The class, which is worth carrying upstream

cyrius found **24** of these in its own `programs/` at v6.5.47 and now gates the pattern. Every
`sys_write(fd, LITERAL, N)` carries a hand-written byte count with no `strlen` at the call site,
so any edit to the message that leaves the number alone silently truncates or over-reads. The
usual cause is a multi-byte character — an em-dash is **three** bytes and one glyph.

`tests/gates/frontend/write_literal_lengths.sh` is small, has no cyrius-specific dependencies
beyond `python3`, and is worth porting into sigil (and the other stdlib siblings) directly.
