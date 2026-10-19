#!/usr/bin/env python3
# scripts/folds/cymlcheck.py — CYML validator: a TOML preamble, then [[entries]] blocks; each
# block's TOML part ends at a line that is exactly '---' (the markdown body follows, up to the
# next '[[entries]]' line). Every TOML part is parsed with tomllib.
#
# usage:   python3 scripts/folds/cymlcheck.py <root> [<file>...]
#   <root> is a DIRECTORY and each <file> is a path RELATIVE to it; with no <file>, every .cyml
#   tracked under <root>/content at any depth (`git -C <root> ls-files 'content/*.cyml'` —
#   vidya's layout). A lone file path is read as the root and checks 0 files: read the TOTAL
#   line's file count.
#   e.g. cymlcheck.py . cyrius.cyml   ·   cymlcheck.py ../vidya   (every vidya entry file)
# inputs:  the .cyml files; Python 3.11+ (tomllib).
# outputs: stdout — an `ERR <file>:<line>: <error>` per failing part, a per-file count line (for
#   every file named explicitly, or any file with errors), then
#   `TOTAL errors: N (E entries, F files)`. Exit 0 whatever the count: compare the count before
#   and after an edit.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import sys
if sys.version_info < (3, 11):
    sys.exit(f"cymlcheck.py: needs Python 3.11+ (tomllib); this is Python {sys.version.split()[0]}")
import tomllib, subprocess, os
root = sys.argv[1] if len(sys.argv) > 1 else '.'
files = sys.argv[2:] or subprocess.run(['git','-C',root,'ls-files','content/*.cyml'],capture_output=True,text=True).stdout.split()
total = 0; nent = 0
for f in files:
    d = open(os.path.join(root, f), encoding='utf-8').read()
    lines = d.split('\n')
    chunks = []; cur = []; start = 1
    for i, l in enumerate(lines, 1):
        if l.strip() == '[[entries]]':
            chunks.append((start, cur)); cur = [l]; start = i
        else:
            cur.append(l)
    chunks.append((start, cur))
    errs = []
    for k, (st, ch) in enumerate(chunks):
        toml = ch
        for j, l in enumerate(ch):
            if l.rstrip() == '---':
                toml = ch[:j]; break
        try:
            tomllib.loads('\n'.join(toml))
        except Exception as e:
            errs.append(f"{f}:{st}: {e}")
        if k > 0: nent += 1
    total += len(errs)
    for e in errs: print("  ERR", e)
    if errs or len(sys.argv) > 2: print(f"{f}: {len(errs)} errors, {len(chunks)-1} entries")
print(f"TOTAL errors: {total} ({nent} entries, {len(files)} files)")
