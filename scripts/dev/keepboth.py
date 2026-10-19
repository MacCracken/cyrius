#!/usr/bin/env python3
# scripts/dev/keepboth.py — resolve every merge-conflict block in a file by keeping BOTH sides,
# ours then theirs (the two lanes each appended a row at the same place: scripts/check.sh's
# `_chk_gate` list, a CHANGELOG section, a gate registry).
#
# Usage:  python3 scripts/dev/keepboth.py [--sep] <file>
#
# Input:  <file> holding `<<<<<<< <label>` / `=======` / `>>>>>>> <label>` blocks; the labels may be
#         anything (HEAD, a branch, a lane name). A diff3-style `||||||| base` section is not
#         recognised: it would be kept as part of "ours".
# Output: <file> rewritten in place, each block replaced by its first side followed by its second.
#         --sep puts one blank line between the two sides (the first side's trailing newlines
#         folded into one blank line); without it the sides are joined as they are.
#         Prints `resolved <N> block(s) in <file>`. Exit 0 when at least one block was resolved and
#         no marker remains; 1 when the file had no conflict block (nothing written) or a marker is
#         left after resolving (an unmatched or nested block; nothing written); 2 on a usage error.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import argparse
import re
import sys

BLOCK = re.compile(r'<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', re.S)


def main():
    ap = argparse.ArgumentParser(description='Resolve merge-conflict blocks by keeping both sides.')
    ap.add_argument('--sep', action='store_true', help='one blank line between the two sides')
    ap.add_argument('file')
    a = ap.parse_args()
    s = open(a.file).read()
    if a.sep:
        s2, n = BLOCK.subn(lambda m: m.group(1).rstrip('\n') + '\n\n' + m.group(2), s)
    else:
        s2, n = BLOCK.subn(lambda m: m.group(1) + m.group(2), s)
    if n == 0:
        print(f"keepboth: no conflict block in {a.file}", file=sys.stderr)
        sys.exit(1)
    if '<<<<<<<' in s2 or '>>>>>>>' in s2:
        print(f"keepboth: a conflict marker is left in {a.file} after resolving {n} block(s) — not written",
              file=sys.stderr)
        sys.exit(1)
    open(a.file, 'w').write(s2)
    print(f"resolved {n} block(s) in {a.file}")


if __name__ == '__main__':
    main()
