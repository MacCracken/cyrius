# `cyrius deps --verify` fails every file on a CRLF checkout of a committed `lib/` (`core.autocrlf=true`) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the CLI built from `cbt/cyrius.cyr` by
the tree's `build/cycc` and a throwaway `HOME` / `CYRIUS_HOME`: a project committing `lib/` and `cyrius.lock` verifies
`2 verified, 0 failed` on its LF clone and `0 verified, 2 failed` (`hash mismatch`, rc 1) on a
`git -c core.autocrlf=true clone`; with `lib/** -text` committed in `.gitattributes` the autocrlf clone verifies again.
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.6.20 (2026-10-07, the CRLF-lock work behind CYRIUS-2026-0032); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — a hard CI failure on every Windows checkout of a project that commits `lib/` (Git for Windows
defaults to `core.autocrlf=true`); the `.gitattributes` workaround exists but nothing tells the user.
**Affects:** `cyrius deps --verify` through 6.7.6 (the lock has always hashed the bytes on disk).

## Summary

`cyrius.lock` records the SHA-256 of each `lib/` file as `cyrius deps` wrote it — LF bytes. With `core.autocrlf=true`
git converts those files to CRLF in the working tree, so `deps --verify` hashes different bytes and reports every
file as a mismatch. The lock FILE itself is already CRLF-tolerant (6.6.20 strips the `\r` from each path,
`cbt/deps.cyr:6607-6610`), so the lock parses and only the content check fails. `deps --locked` holds `lib/` to the
same bytes and fails the same way (`differs: lib/alpha.cyr: its bytes do not match cyrius.lock`, rc 1) — and its
remedy, "run `cyrius deps` and commit the result", would re-lock the CRLF hashes and churn the lock between a
Windows and a Linux checkout.

## Reproduction

```sh
cat cbt/cyrius.cyr | build/cycc > $S/cyrius && chmod +x $S/cyrius
mkdir -p $S/up/lib $S/up/src && cd $S/up
printf '[package]\nname = "demo"\nversion = "0.1.0"\n' > cyrius.cyml
printf 'fn a() {\n    return 1;\n}\n' > lib/alpha.cyr; printf 'fn c() {\n    return 3;\n}\n' > lib/beta.cyr
printf 'fn main() { return 0; }\n' > src/main.cyr
{ sha256sum lib/alpha.cyr lib/beta.cyr; printf 'cyrius\t6.7.6\n'; } > cyrius.lock
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
HOME=$S/h CYRIUS_HOME=$S/h/.cyrius $S/cyrius deps --verify            # 2 verified, 0 failed
cd $S && git -c core.autocrlf=true clone -q up co && cd co
HOME=$S/h CYRIUS_HOME=$S/h/.cyrius $S/cyrius deps --verify            # see below
```

Expected (or at least): a verdict that names the line-ending conversion. Actual:

```
  FAIL: lib/alpha.cyr (hash mismatch)
  FAIL: lib/beta.cyr (hash mismatch)
0 verified, 2 failed            (rc 1)
```

Committing `.gitattributes` with `lib/** -text` before the clone: `2 verified, 0 failed`.

## Root cause

`cmd_deps_verify` (`cbt/deps.cyr:6554`) hashes each path with `_sha256sum_file` (`:6615`) and compares it to the
locked hash (`:6623`); `_deps_locked_compare` (`:3826`, the kept-file arm `:3882-3884`) does the same for `--locked`. The working-tree bytes are
CRLF, the locked hash is of LF bytes.

## Proposed fix

The user's call between the two the roadmap names:
1. **Normalise** — hash with CRLF folded to LF. ⚠ This changes what `--verify` proves: a CRLF-only rewrite of a locked
   file would then pass (the laundering `cbt/deps.cyr:5354-5357` describes for git's own end-of-line hashing).
2. **Document and diagnose** — keep the exact-bytes check; `cyrius init`'s templates ship a `.gitattributes` with
   `lib/** -text`, and `--verify` / `--locked`, when a mismatching file hashes to its locked value with CRLF → LF,
   say so by name ("CRLF checkout: add `lib/** -text` to .gitattributes") instead of a bare `hash mismatch`.

Default if the user does not choose: 2 (no change to what verifies). Gate row either way: an autocrlf clone of a
committed `lib/`.
