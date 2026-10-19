#!/usr/bin/env python3
# scripts/release/archive.py — at a release's close: archive each issue the release resolved. Each
# file's title gets " — RESOLVED" (or " — CLOSED (not a cyrius bug)" when its banner says NOT A
# CYRIUS BUG), its banner goes under the title, its **Status:** line is rewritten, and it is
# `git mv`'d into docs/development/issues/archived/; then every link to it in every tracked text
# file (build/ excepted) is repointed to the archived path.
#
# usage:   python3 scripts/release/archive.py --ver X.Y.Z [--dry] [--repo <checkout>] [--c6 <dir>]
#            [--docs DIR]
#   --dry    rewrite nothing and move nothing: print the count and the files it would repoint
# inputs:  <docs>/banners_*.json (default <docs>: <c6>/<tag>_docs/), each a JSON array of
#          {"file": "<issue>.md", "banner": "> ✅ **RESOLVED in vX.Y.Z** (…)"} written by
#          scripts/release/docs.js (two entries for one file are both kept); the open issue files
#          they name; `git ls-files` of the checkout (it must be a git checkout)
# outputs: the archived issue files (git mv, so the move is staged) and the repointed files; on
#          stdout "<N> archived; <M> files repointed" and the repointed paths. Exit 1, writing
#          nothing, when a banner names a file that is not open on disk.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import glob
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True  # importing release_common leaves no __pycache__ in the tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from release_common import parser, finish, in_c6, rd, wr  # noqa: E402

ap = parser('Archive the issues a release resolved, with their banners, and repoint every link.', dry=True)
ap.add_argument('--docs', help='default: <c6>/<tag>_docs')
a = finish(ap.parse_args())
repo = a.repo
dry = a.dry
D = a.docs or in_c6(a, 'docs')
ISS = os.path.join(repo, 'docs/development/issues')

banners = {}
for p in sorted(glob.glob(os.path.join(D, 'banners_*.json'))):
    for e in json.loads(rd(p)):
        f = e['file']
        if f in banners:
            banners[f] += '\n' + e['banner']  # two lanes closed one file: keep both
        else:
            banners[f] = e['banner']

missing = [f for f in banners if not os.path.exists(os.path.join(ISS, f))]
if missing:
    print('MISSING (not open on disk):', missing)
    sys.exit(1)


def rewrite(f, banner):
    s = rd(os.path.join(ISS, f)).split('\n')
    t = s[0]
    end = ' — CLOSED (not a cyrius bug)' if 'NOT A CYRIUS BUG' in banner else ' — RESOLVED'
    t2 = re.sub(r'\s*—\s*(OPEN|PARTIAL)\s*$', end, t)
    if t2 == t and not t.rstrip().endswith('RESOLVED'):
        t2 = t.rstrip() + ' — RESOLVED'
    out = [t2, '', banner.strip()]
    rest = s[1:]
    while rest and rest[0].strip() == '':
        rest = rest[1:]
    done = False
    for i, l in enumerate(rest):
        if l.startswith('**Status:**') and not done:
            word = f'CLOSED — NOT A CYRIUS BUG (v{a.ver})' if 'NOT A CYRIUS BUG' in banner else f'RESOLVED in v{a.ver}'
            rest[i] = '**Status:** ✅ **' + word + '** (see the banner). Was: ' + l[len('**Status:**'):].strip()
            done = True
    if not done:
        print('NO STATUS LINE:', f)
    return '\n'.join(out + [''] + rest)


for f, b in banners.items():
    txt = rewrite(f, b)
    if dry:
        continue
    wr(os.path.join(ISS, f), txt, False)
    subprocess.check_call(['git', '-C', repo, 'mv', os.path.join('docs/development/issues', f),
                           os.path.join('docs/development/issues/archived', f)])

# Repoint links in every tracked text file.
files = subprocess.check_output(['git', '-C', repo, 'ls-files'], text=True).split('\n')
names = list(banners)
changed = []
for rel in files:
    if not rel or rel.startswith('build/'):
        continue
    p = os.path.join(repo, rel)
    if not os.path.isfile(p):
        continue
    try:
        s = rd(p)
    except UnicodeDecodeError:
        continue
    o = s
    d = os.path.dirname(rel)
    for f in names:
        if f not in s:
            continue
        esc = re.escape(f)
        # any path spelling ending in issues/<f> that is not already archived/
        s = re.sub(r'(?<!archived/)issues/' + esc, 'issues/archived/' + f, s)
        if d == 'docs/development/issues':
            # an open issue / the index linking a sibling by bare name
            s = re.sub(r'(?<![/\w.-])' + esc, 'archived/' + f, s)
        elif d == 'docs/development/issues/archived':
            # an archived issue linking the formerly-open file as ../<f>
            s = re.sub(r'\.\./' + esc, f, s)
    if s != o:
        changed.append(rel)
        wr(p, s, dry)
print(len(banners), 'would be archived;' if dry else 'archived;', len(changed),
      'files would be repointed' if dry else 'files repointed')
for c in changed:
    print('  ', c)
