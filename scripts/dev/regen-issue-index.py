#!/usr/bin/env python3
# scripts/dev/regen-issue-index.py — regenerate docs/development/issues/README.md § Open queue.
#
# Usage:  python3 scripts/dev/regen-issue-index.py [--repo DIR | DIR]
#
# Input:  every docs/development/issues/*.md except README.md — its title is the first heading
#         (a trailing " — OPEN" dropped), its group the text of its `**Placement:**` line; and the
#         README's own § Open queue, whose existing `**<label>** (N)` lines name the groups.
# Output: the § Open queue section of that README, rewritten in place (the rest of the file is kept
#         byte for byte); one summary line on stdout.
#
# Groups, in the README's order:
#   * a release group per `**<label>** (N)` line whose label starts with a release number
#     (`**X.Y.Z — …** (N)`): it collects every file whose placement starts with that number
#     followed by a space or `(`;
#   * a placement whose leading release number has no label gets the automatic label `**<rel>**`,
#     inserted before the first labelled release that sorts after it; an automatic group left
#     empty (its last issue re-placed or archived) is dropped, a hand-written label is kept at (0);
#   * `**Open by design …** (N)` collects placements starting `open by design` (always printed);
#   * `**Unplaced** (N)` collects the rest (printed only when non-empty).
# The text between the `## Open queue` heading and the first group line is kept as written.
#
# The repo root is this file's ../.. unless --repo DIR, a bare DIR argument or CYRIUS_REPO names one.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import argparse
import glob
import os
import re
import sys
from pathlib import Path

LABEL = re.compile(r'^\*\*(.+)\*\* \((\d+)\)$')
REL = re.compile(r'^(\d+(?:\.\d+)+)')
PLACED_REL = re.compile(r'^(\d+(?:\.\d+)+)(?=[ (])')
OBD_DEFAULT = 'Open by design — placed arcs, not bugs'


def die(msg):
    print('regen-issue-index: ' + msg, file=sys.stderr)
    sys.exit(2)


def relkey(v):
    return tuple(int(x) for x in v.split('.'))


def main():
    ap = argparse.ArgumentParser(description='Regenerate docs/development/issues/README.md § Open queue.')
    ap.add_argument('repo', nargs='?', help='the cyrius checkout (default: this script\'s ../..)')
    ap.add_argument('--repo', dest='repo_flag', metavar='DIR', help='the cyrius checkout')
    a = ap.parse_args()
    root = a.repo_flag or a.repo or os.environ.get('CYRIUS_REPO') or str(Path(__file__).resolve().parents[2])
    idir = os.path.join(root, 'docs', 'development', 'issues')
    readme = os.path.join(idir, 'README.md')
    if not os.path.isfile(readme):
        die(readme + ' not found (is ' + root + ' a cyrius checkout?)')

    items = []
    for f in sorted(glob.glob(idir + '/*.md')):
        if f.endswith('README.md'):
            continue
        s = open(f, encoding='utf-8').read()
        t = re.sub(r' — OPEN$', '', s.splitlines()[0].lstrip('# '))
        m = re.search(r'^\*\*Placement:\*\* (.*)$', s, re.M)
        p = m.group(1) if m else ''
        items.append((os.path.basename(f), t, p))

    r = open(readme, encoding='utf-8').read()
    try:
        a0 = r.index('## Open queue')
        b0 = r.index('\n## ', a0 + 5)
    except ValueError:
        die(readme + ' has no `## Open queue` section followed by another `## ` heading')
    section = r[a0:b0 + 1]

    # The existing group lines name the groups; the text above the first one is kept.
    rel_groups = []  # [(release, label)] in the README's order
    obd_label = None
    head = None
    pos = 0
    for line in section.splitlines(keepends=True):
        m = LABEL.match(line.rstrip('\n'))
        if m:
            if head is None:
                head = section[:pos]
            lab = m.group(1)
            if lab.startswith('Open by design'):
                obd_label = lab
            elif lab == 'Unplaced':
                pass
            else:
                v = REL.match(lab)
                if not v:
                    die('group label has no leading release number and is not Open by design / Unplaced: **' + lab + '**')
                rel_groups.append((v.group(1), lab))
        pos += len(line)
    if head is None:
        head = section.rstrip('\n') + '\n\n'
    if obd_label is None:
        obd_label = OBD_DEFAULT

    # A placement release with no label gets `**<rel>**`, before the first labelled release after it.
    labelled = {v for v, _ in rel_groups}
    auto = []
    for _, _, p in items:
        m = PLACED_REL.match(p)
        if m and m.group(1) not in labelled and m.group(1) not in auto:
            auto.append(m.group(1))
    for v in sorted(auto, key=relkey):
        at = len(rel_groups)
        for i, (w, _) in enumerate(rel_groups):
            if relkey(w) > relkey(v):
                at = i
                break
        rel_groups.insert(at, (v, v))

    seen = set()
    out = head

    def group(lab, xs):
        for x in xs:
            seen.add(x[0])
        return f"**{lab}** ({len(xs)})\n\n" + ''.join(f"- [{t}]({fn})\n" for fn, t, _ in xs) + "\n"

    for v, lab in rel_groups:
        xs = [x for x in items if x[0] not in seen and (x[2].startswith(v + ' ') or x[2].startswith(v + '('))]
        if not xs and lab == v:
            continue  # an automatic `**<rel>**` group whose last issue moved on is dropped
        out += group(lab, xs)
    out += group(obd_label, [x for x in items if x[0] not in seen and x[2].startswith('open by design')])
    xs = [x for x in items if x[0] not in seen]
    if xs:
        out += group('Unplaced', xs)

    open(readme, 'w', encoding='utf-8').write(r[:a0] + out + r[b0 + 1:])
    msg = f"{len(items)} open; unplaced {len(xs)}"
    if auto:
        msg += '; new group label(s): ' + ', '.join(sorted(auto, key=relkey))
    print(msg)


if __name__ == '__main__':
    main()
