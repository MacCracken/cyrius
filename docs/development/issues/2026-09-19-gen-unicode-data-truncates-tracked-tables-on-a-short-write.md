# `programs/gen_unicode_data.cyr` truncates the three TRACKED `lib/unicode/_*_data.cyr` tables on a short write and exits 0 — OPEN

**Status:** 🟡 open — found during 6.6.6 bite 12 (the same write-path defect bite 12 fixed in
`gen_syscall_xlat.cyr`); reconfirmed at the bite-12 tree in a scratch copy.
**Placement:** unpinned — 6.x-line backlog (the next repair batch).
**Discovered:** 2026-09-19
**Severity:** High — silent corruption of tracked stdlib data on any full disk: all three tables
are truncated in place, the tool says `wrote … (2048 bytes)` and exits 0.
**Affects:** `programs/gen_unicode_data.cyr` (all versions with the `file_write_all` writes).

## Reproduction (run in a SCRATCH copy — it writes lib/ in its cwd)

```sh
U=$(mktemp -d); git archive HEAD lib tests/data/ucd programs/gen_unicode_data.cyr cyrius.cyml cyrius.lock VERSION | tar -x -C "$U"
mkdir "$U/build"; cp build/cycc build/cyrius "$U/build/"
( cd "$U" && ./build/cyrius build programs/gen_unicode_data.cyr "$U/gen" &&
  ( trap '' XFSZ; ulimit -f 4; exec "$U/gen" ); echo rc=$?; wc -c lib/unicode/_*_data.cyr )
```

Actual:

```
wrote lib/unicode/_categories_data.cyr (2048 bytes, 4144 merged ranges)
wrote lib/unicode/_casefold_data.cyr (2048 bytes)
wrote lib/unicode/_normalize_data.cyr (2048 bytes)
rc=0
  2048 lib/unicode/_categories_data.cyr      # committed: 59010
  2048 lib/unicode/_casefold_data.cyr        # committed: 96988
  2048 lib/unicode/_normalize_data.cyr       # committed: 156750
```

(`RLIMIT_FSIZE` with SIGXFSZ ignored gives the writer exactly a full disk's sequence: a short count,
then EFBIG.) Expected: a non-zero exit naming the file, and each table left as it was.

## Root cause

Lines ~405, ~719, ~1135: `var n_written = file_write_all("lib/unicode/…", out_buf, oo);` — the
result is printed, never checked (not even the `<= 0` the pre-6.6.6 `gen_syscall_xlat` had), and
`file_write_all` is a single `write` after an `O_TRUNC` open, so a short write both truncates the
target and reports a positive count.

## Proposed fix

The bite-12 fix for `gen_syscall_xlat.cyr`: `file_write_atomic` (temp + fsync + rename, loops to
completion, errors on a short write) and `return 1` with a stderr message when it fails. Optionally
an OUT-dir argument so a gate can regenerate into a temp dir and diff (as `syscall_xlat_generated.sh`
now does) — today nothing re-derives these tables at all.

## Related sites (same write shape, READ only — not run)

- `programs/cyrfmt.cyr` ~390: the in-place `--write` path uses `file_write_all`; it does detect
  `w != _out_pos` but has already truncated the user's source by then. Its header comment
  ("cyrius doesn't expose sys_rename yet") is stale — `file_write_atomic` exists since v6.4.57.
- `programs/cyriusly.cyr` ~271 and ~382: `file_write_all("cyrius.cyml", …)` and the `current`
  pointer, results unchecked.

## Acceptance criteria

- The repro above exits non-zero and leaves all three tables byte-identical.
- A gate pins it (RLIMIT_FSIZE, no mount), mutation-proven by reverting to `file_write_all`.
