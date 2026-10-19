#!/usr/bin/env python3
# scripts/release/place.py — at a release's slot open, after the user has answered the open's
# decisions: rewrite each planned issue's **Placement:** line to name its wave and unit, add a
# **Decision** line under it for each decision on that issue, then apply the open's special
# re-placements (an issue decided as a whole, an issue moved to a later release).
#
# usage:   python3 scripts/release/place.py --ver X.Y.Z --date YYYY-MM-DD [--dry]
#            [--repo <checkout>] [--c6 <dir>] [--units F] [--decisions F] [--plan F]
#   --date   the day the user answered the decisions (written into each line)
#   --dry    print what would change; write nothing
# inputs:  <c6>/<tag>_units.json      {"W<n>": {"<lane>": {"<unit>": ["<issue>.md", ...]}}}; wave 0
#                                     (lane "main") runs on main before the lanes fork
#          <c6>/<tag>_decisions.json  [{"id", "issue", "question", "options": [{"label", "effect"}],
#                                     "rec_label", "why", ...}] — the answered decisions (the answer
#                                     is the option whose label is rec_label)
#          <c6>/<tag>_place.json      optional, this release's literal content — schema in README.md
#          docs/development/issues/<issue>.md, each holding a "**Placement:** X.Y.Z — <label> (...) —
#          never 7.x." line for this release (<label> on the first line; the parenthetical may wrap
#          onto continuation lines; text may follow "never 7.x." and is kept)
# outputs: those issue files, edited in place; a count line on stdout. Exit 1 when a planned
#          issue has no Placement line for this release (nothing is written then).
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import json
import os
import re
import sys

sys.dont_write_bytecode = True  # importing release_common leaves no __pycache__ in the tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from release_common import parser, finish, in_c6, rd, wr  # noqa: E402


def ids(spec):
    """"1-40,45" or [1, 2] -> a set of ints."""
    if isinstance(spec, list):
        return set(spec)
    out = set()
    for part in str(spec).split(','):
        part = part.strip()
        if '-' in part:
            a, b = part.split('-', 1)
            out.update(range(int(a), int(b) + 1))
        elif part:
            out.add(int(part))
    return out


def main():
    ap = parser('Write the slot open\'s Placement and Decision lines into the issue files.', date=True, dry=True)
    ap.add_argument('--units', help='default: <c6>/<tag>_units.json')
    ap.add_argument('--decisions', help='default: <c6>/<tag>_decisions.json')
    ap.add_argument('--plan', help='default: <c6>/<tag>_place.json (optional)')
    a = finish(ap.parse_args())
    U = json.loads(rd(a.units or in_c6(a, 'units.json')))
    D = json.loads(rd(a.decisions or in_c6(a, 'decisions.json')))
    plan_path = a.plan or in_c6(a, 'place.json')
    P = json.loads(rd(plan_path)) if os.path.exists(plan_path) else {}
    I = os.path.join(a.repo, 'docs/development/issues')
    ver, date = a.ver, a.date

    place = {}
    for w, lanes in U.items():
        wave = int(w.lstrip('Ww'))
        for lane, units in lanes.items():
            for u, xs in units.items():
                for x in xs:
                    if wave == 0:
                        place[x] = f'on main, wave 0, before the lanes fork; placed at the {ver} open, {date}'
                    else:
                        place[x] = f'{lane} lane, wave {wave}, unit {u}; placed at the {ver} open, {date}'
    keep = ids(P['decision_ids']) if 'decision_ids' in P else None
    dec = {}
    for d in D:
        if keep is None or d['id'] in keep:
            dec.setdefault(d['issue'], []).append(
                f"**Decision (user, {date}, at the {ver} open):** D{d['id']} — {d['rec_label']}.")

    # this release's Placement line; the label (e.g. "repair M") is kept as it stands. The
    # parenthetical may wrap onto continuation lines (never across a blank line or into the next
    # "**Field:**" line), and text may follow "— never 7.x." on its line: only the matched span
    # is replaced, so that text is kept
    pat = re.compile(r'^\*\*Placement:\*\* ' + re.escape(ver) +
                     r' — (?P<label>[^(\n]*?) \((?:(?!\n\n|\n\*\*)[\s\S])*?\) — never 7\.x\.(?=[ \n]|$)', re.M)

    def sub_place(f, s, line):
        s2, n = pat.subn(lambda m: line.replace('{label}', m.group('label')), s, count=1)
        if n != 1:
            sys.exit(f'{f}: no "**Placement:** {ver} — … — never 7.x." line — nothing written')
        return s2

    def add_after(s, lines, prefix):
        # after the whole field line: its wrapped continuation lines (non-blank, not "**") too
        m = re.search(r'^' + re.escape(prefix) + r'.*(?:\n(?!\*\*)[^\n]+)*', s, re.M)
        if not m:
            sys.exit(f'no line starting {prefix!r} to add the Decision lines after — nothing written')
        return s[:m.end()] + ''.join('\n' + l for l in lines) + s[m.end():]

    out = {}
    nd = 0
    for f, p in place.items():
        s = out.get(f) or rd(os.path.join(I, f))
        s = sub_place(f, s, f'**Placement:** {ver} — {{label}} ({p}) — never 7.x.')
        if f in dec:
            s = add_after(s, dec[f], '**Placement:**')
            nd += len(dec[f])
        out[f] = s
    for sp in P.get('special', []):
        f = sp['file']
        s = out.get(f) or rd(os.path.join(I, f))
        s = sub_place(f, s, sp['placement'])
        if sp.get('decisions'):
            s = add_after(s, sp['decisions'], sp.get('decisions_after', '**Placement:**'))
            nd += sp.get('decision_count', len(sp['decisions']))
        out[f] = s
    changed = []
    for f, s in out.items():
        if s != rd(os.path.join(I, f)):
            changed.append(f)
        wr(os.path.join(I, f), s, a.dry)
    print(('would place' if a.dry else 'placed'), len(place), 'from the units +', len(P.get('special', [])),
          'special; decision lines', nd, '; files changed', len(changed))
    if a.dry:
        for f in changed:
            print('  ', f)


main()
