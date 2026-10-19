#!/usr/bin/env python3
# scripts/release/briefs.py — at a release's slot open: write one brief per lane unit (the file
# each implementing agent of scripts/release/lanes.js reads first): per issue its triage (title,
# severity, status and evidence, fix plan, touches, rows, targets, hosts, risk) and the user's
# final decisions with the chosen answer; then the lane's triage notes (groups, ordering,
# cross-lane). Wave 0 (on main, before the lanes fork) gets no brief.
#
# usage:   python3 scripts/release/briefs.py --ver X.Y.Z --date YYYY-MM-DD [--dry]
#            [--repo <checkout>] [--c6 <dir>] [--units F] [--triage F] [--decisions F]
#            [--notes F] [--out DIR]
#   --date   the day the user answered the decisions (written into each brief)
#   --dry    list the briefs it would write; write nothing
# inputs:  <c6>/<tag>_units.json      {"W<n>": {"<lane>": {"<unit>": ["<issue>.md", ...]}}}
#          <c6>/<tag>_triage.json     scripts/release/triage.js's result: [{"lane": "<name> …",
#                                     "items": [...], "groups", "ordering_constraints", "cross_lane"}]
#          <c6>/<tag>_decisions.json  the answered decisions (see place.py)
#          <c6>/<tag>_brief_notes.json  optional, this release's literal content (a preamble, the
#                                     unit notes, extra decisions per unit, cross-lane notes) —
#                                     schema in README.md
# outputs: <out>/<lane>_<unit>.md (default <out>: <c6>/<tag>_briefs/); a count on stdout. Exit 1
#          when a unit names an issue the triage does not have.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import json
import os
import sys

sys.dont_write_bytecode = True  # importing release_common leaves no __pycache__ in the tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from release_common import parser, finish, in_c6, rd, wr  # noqa: E402


def listed(v, sep):
    return sep.join(v) if isinstance(v, list) else v


def main():
    ap = parser('Write the lane briefs for a release\'s units.', date=True, dry=True)
    ap.add_argument('--units', help='default: <c6>/<tag>_units.json')
    ap.add_argument('--triage', help='default: <c6>/<tag>_triage.json')
    ap.add_argument('--decisions', help='default: <c6>/<tag>_decisions.json')
    ap.add_argument('--notes', help='default: <c6>/<tag>_brief_notes.json (optional)')
    ap.add_argument('--out', help='default: <c6>/<tag>_briefs')
    a = finish(ap.parse_args())
    U = json.loads(rd(a.units or in_c6(a, 'units.json')))
    T = json.loads(rd(a.triage or in_c6(a, 'triage.json')))
    D = json.loads(rd(a.decisions or in_c6(a, 'decisions.json')))
    notes_path = a.notes or in_c6(a, 'brief_notes.json')
    N = json.loads(rd(notes_path)) if os.path.exists(notes_path) else {}
    out_dir = a.out or in_c6(a, 'briefs')
    ver, date = a.ver, a.date

    items = {}
    lanemeta = {}
    for g in T:
        ln = g['lane'].split(' ')[0]
        lanemeta[ln] = g
        for i in g['items']:
            items[i['issue']] = (ln, i)
    dec = {}
    for d in D:
        dec.setdefault(d['issue'], []).append(d)
    by_id = {d['id']: d for d in D}
    preamble = N.get('preamble')
    unit_notes = N.get('unit_notes', {})
    extra = N.get('extra_decisions', {})
    cross = N.get('cross_lane', {})

    def answer(d):
        return next(o for o in d['options'] if o['label'] == d['rec_label'])

    if not a.dry:
        os.makedirs(out_dir, exist_ok=True)
    n = 0
    for w, lanes in U.items():
        wave = int(w.lstrip('Ww'))
        if wave == 0:
            continue
        for lane, units in lanes.items():
            meta = lanemeta[lane]
            for u, xs in units.items():
                key = f'{lane}/{u}'
                out = [f"# {ver} brief — lane {lane}, unit {u} (wave {wave})\n"]
                if preamble:
                    out.append(preamble)
                if key in unit_notes:
                    out.append(f"**UNIT NOTE:** {unit_notes[key]}\n")
                for x in xs:
                    if x not in items:
                        sys.exit(f'{key}: {x} is not in the triage')
                    ol, i = items[x]
                    out.append(f"## {x}")
                    out.append(f"**Title:** {i['title']}")
                    out.append(f"**Severity:** {i['severity']} · **Kind:** {i['kind']} · **Size:** {i['size']}"
                               + (f" · triaged in the {ol} lane" if ol != lane else ''))
                    out.append(f"**Triage status:** {i['status']} — {i['evidence']}")
                    if x in dec:
                        out.append(f"**USER DECISIONS (final, {date} — implement exactly the answer):**")
                        for d in dec[x]:
                            ans = answer(d)
                            out.append(f"- **D{d['id']}** — {d['question']}\n  **ANSWER: {ans['label']}** => {ans['effect']}")
                    else:
                        out.append("**USER DECISIONS:** none needed (a fix to what the source says / a codegen or tooling defect).")
                    out.append(f"**Fix plan (triage, verify line numbers):** {i['fix_plan']}")
                    out.append(f"**Touches:** {listed(i.get('touches'), ', ')}")
                    out.append(f"**Rows:** {listed(i.get('rows'), ' | ')}")
                    for k, lab in (('targets', 'Targets'), ('hosts', 'Hosts')):
                        out.append(f"**{lab}:** {listed(i.get(k), ', ')}")
                    out.append(f"**Risk:** {i['risk']}\n")
                for did in extra.get(key, []):
                    d = by_id[did]
                    ans = answer(d)
                    out.append(f"## {d['issue']} — D{did}\n**USER DECISION (final, {date}):** {d['question']}\n"
                               f"**ANSWER: {ans['label']}** => {ans['effect']}\n**Why:** {d['why']}\n")
                out.append(f"## Lane notes (from the {lane} triage)\n**Groups:** {meta['groups']}\n\n"
                           f"**Ordering constraints:** {meta['ordering_constraints']}\n\n**Cross-lane:** {meta['cross_lane']}\n")
                for c in cross.get(lane, []):
                    out.append(f"**{c['label']}:** {lanemeta[c['from']]['cross_lane']}\n")
                path = os.path.join(out_dir, f"{lane}_{u}.md")
                wr(path, '\n'.join(out), a.dry)
                if a.dry:
                    print('  would write', path)
                n += 1
    print('briefs', n)


main()
