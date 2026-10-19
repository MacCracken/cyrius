#!/usr/bin/env python3
# scripts/dev/probe-split.py — split one file of `== name` blocks into one probe file per block.
#
# Usage:  python3 scripts/dev/probe-split.py <dir> <file>
#
# Input:  <file>, whose blocks each start with a line `== <name>`; the lines up to the next
#         `== ` line (or the end) are that probe's source. Lines before the first `== ` are ignored.
# Output: <dir>/<name>.cyr per block (<dir> created when missing). Every *.cyr / *.bin / *.err
#         already in <dir> is removed first, so the directory holds exactly this file's probes —
#         then `sh scripts/dev/probe.sh <dir>` compiles and runs them.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import os
import sys

if len(sys.argv) != 3:
    print('usage: python3 scripts/dev/probe-split.py <dir> <file>', file=sys.stderr)
    sys.exit(2)
d = sys.argv[1]
os.makedirs(d, exist_ok=True)
for f in os.listdir(d):
    if f.endswith(('.cyr', '.bin', '.err')):
        os.remove(os.path.join(d, f))
cur = None
buf = []


def flush():
    if cur:
        open(os.path.join(d, cur + '.cyr'), 'w').write('\n'.join(buf) + '\n')


for line in open(sys.argv[2]).read().split('\n'):
    if line.startswith('== '):
        flush()
        cur = line[3:].strip()
        buf = []
    else:
        buf.append(line)
flush()
