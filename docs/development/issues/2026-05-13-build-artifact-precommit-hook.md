# Build-artifact pre-commit hook — generalize v5.11.45 contamination gate

**Filed:** 2026-05-13 (during v5.11.49 vidya cleanup sweep)
**Severity:** Medium — has caught-after-the-fact safety net via v5.11.45 grep gate; pre-commit hook closes the surface entirely.
**Affects:** `build/cycc`, `build/cybs`, and any future committed `build/<binary>` artifact.

## Summary

`build/cycc` has been silently overwritten with non-cyrius binaries multiple times across the v5.11.x cycle:

- v5.11.28/29 — first occurrence; silently fixed at v5.11.30 with no postmortem
- v5.11.43 — recurrence; caught at v5.11.44 (a 1,389,776 B binary containing `mabda: gpu` / `wgpuDevice` / `compute_pipeline` strings — *not* the cyrius compiler)

Similar slip surfaced on `build/cybs` at v5.11.45 — had been replaced with the 12 KB bootstrap binary (no vet/deny dispatch); `install.sh --refresh-only` carried the contaminated copy into `~/.cyrius/bin/cybs`.

The pattern: a build script during release prep cp's another binary (often a mabda-built or sibling-repo binary that happened to be in the build directory) over `build/cycc` immediately before commit. `install.sh`'s mtime-based `_rebuild_stale` check skips the rebuild because the bad binary's mtime is newer than source.

## Current safety net (v5.11.45)

`programs/check.cyr::_cc5_contamination_gate()` greps `build/cycc` for `mabda: gpu` / `wgpuDevice` / `compute_pipeline` substrings — the v5.11.43-style slip signature. Fails `check.sh` fast. Negative-test verified.

**Limitation:** catches the contamination *after* it's been committed. Recovery still requires a hotfix commit (v5.11.44 was exactly this shape — restore canonical cycc, refresh install snapshots).

## Proposed fix

A `.git/hooks/pre-commit` script (installed by `scripts/install.sh` or `cyrius init`) that runs before any commit touching `build/<anything>`:

```sh
#!/bin/sh
# .git/hooks/pre-commit
# Refuse to commit a contaminated build artifact.

for bin in build/cycc build/cybs; do
    if [ ! -e "$bin" ]; then continue; fi
    if ! git diff --cached --quiet -- "$bin" 2>/dev/null; then
        # Staged for commit — verify
        if strings "$bin" 2>/dev/null | grep -qE "mabda: gpu|wgpuDevice|compute_pipeline"; then
            echo "error: $bin contains foreign-binary strings (mabda/wgpu/compute_pipeline)" >&2
            echo "  → likely contaminated; refusing commit" >&2
            echo "  → restore via: cat src/main.cyr | $bin > /tmp/canonical && cp /tmp/canonical $bin" >&2
            exit 1
        fi
        # Size sanity — cyrius cycc is in the 800 KB - 1 MB range; cycc_win in 600-700 KB
        size=$(stat -c %s "$bin" 2>/dev/null || echo 0)
        case "$bin" in
            build/cycc)
                if [ "$size" -lt 700000 ] || [ "$size" -gt 1200000 ]; then
                    echo "error: $bin size $size B is outside the expected 700K-1.2M range" >&2
                    echo "  → likely contaminated or truncated; refusing commit" >&2
                    exit 1
                fi
                ;;
        esac
    fi
done
```

Plus an ELF-magic check (first 4 bytes = `\x7fELF`) to catch wrong-platform binaries.

## Scope

Pure release-process hardening — no compiler change. Lands as part of `scripts/install.sh` updates + a one-time `cyrius` CLI verb (`cyrius hooks install`) that re-installs `.git/hooks/pre-commit` for the cyrius repo and downstream repos that opt in via `cyrius.cyml`.

## Pin

- **v6.0.0 closeout candidate** per the existing pin in `field_notes/compiler/gotchas.cyml::build_cc5_silent_contamination_recurrence_v51144` ("v6.0.0 closeout sweep candidate"). Folding this into the v6.0.0 closeout aligns with the broader "lift from gate-that-catches-it-after to pre-commit-that-refuses" rotation.

## Acceptance bar

1. `.git/hooks/pre-commit` script installed via `cyrius hooks install` (new verb).
2. Staging a contaminated `build/cycc` (any of the 3 signature strings present, OR size outside 700K-1.2M, OR ELF magic wrong) causes `git commit` to fail with a clear diagnostic.
3. Staging a canonical `build/cycc` passes.
4. `scripts/install.sh` re-installs the hook on every `--refresh-only` (so a fresh clone gets it).
5. v5.11.45 `_cc5_contamination_gate()` stays as the catch-after-the-fact safety net (defense in depth — pre-commit hook is bypassable via `--no-verify`).

## Related

- `field_notes/compiler/gotchas.cyml::build_cc5_silent_contamination_recurrence_v51144`
- `CHANGELOG.md` [5.11.44] — postmortem narrative
- `CHANGELOG.md` [5.11.45] — `_cc5_contamination_gate` introduction
