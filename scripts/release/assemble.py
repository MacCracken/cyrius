#!/usr/bin/env python3
# scripts/release/assemble.py — at a release's close, after the release gate: assemble the
# CHANGELOG entry and the ecosystem-migration section from the drafts in the docs dir. The
# CHANGELOG's placeholder header for the release ("## [X.Y.Z] — <date>", written by
# version-bump.sh) is replaced by the dated header and the entry: the head (its @GATEHEAD@,
# @DRIVER@, @SHELL@ and @BENCH@ filled from the gate), each lane's section, then the extra parts.
# The migration section (the intro, then each lane's notes) goes above "### <prev>" in
# docs/development/ecosystem-migration.md.
#
# usage:   python3 scripts/release/assemble.py --ver X.Y.Z --prev X.Y.W --date YYYY-MM-DD
#            --lanes a,b,... [--extra p,q,...] [--mig-extra r,...] [--gatehead SHA] [--driver N]
#            [--shell N] [--bench MS] [--dry] [--repo <checkout>] [--c6 <dir>] [--docs DIR]
#            [--intro FILE]
#   --lanes      in CHANGELOG order; each has <docs>/changelog_<lane>.md and migration_<lane>.md
#   --extra      CHANGELOG-only parts after the lanes, <docs>/changelog_<part>.md
#                (default: integration,filed)
#   --mig-extra  migration-only parts after the lanes, <docs>/migration_<part>.md (default: none)
#   --gatehead / --driver / --shell / --bench  fill @GATEHEAD@ / @DRIVER@ / @SHELL@ / @BENCH@ in
#                the head (each is required when the head carries its placeholder)
#   --dry        print the line counts; write nothing
# inputs:  <docs>/changelog_head.md, changelog_<part>.md, migration_<part>.md (default <docs>:
#          <c6>/<tag>_docs/ — scripts/release/docs.js writes the lane drafts, the release writes the
#          head, integration and filed parts); <intro> (default <docs>/migration_intro.md: the
#          "### X.Y.Z" heading and the paragraph under it); the checkout's CHANGELOG.md and
#          docs/development/ecosystem-migration.md
# outputs: those two files, edited in place; "CHANGELOG +N lines, migration +M lines" on stdout.
#          Exit 1, writing nothing, when the placeholder header or the "### <prev>" anchor is not
#          there exactly once, the header is not the EMPTY placeholder (header, blank line, the
#          previous "## [" — so a second run refuses), "### X.Y.Z" is already in the migration
#          doc, or a placeholder is left unfilled.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import os
import re
import sys

sys.dont_write_bytecode = True  # importing release_common leaves no __pycache__ in the tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from release_common import parser, finish, in_c6, rd, wr  # noqa: E402


def names(s):
    return [x.strip() for x in (s or '').split(',') if x.strip()]


ap = parser('Assemble the CHANGELOG entry and the ecosystem-migration section from the docs drafts.',
            date=True, dry=True)
ap.add_argument('--prev', required=True, help='the previous release, X.Y.W (the migration anchor "### X.Y.W")')
ap.add_argument('--lanes', required=True, help='comma list, in CHANGELOG order')
ap.add_argument('--extra', default='integration,filed', help='CHANGELOG-only parts after the lanes')
ap.add_argument('--mig-extra', default='', help='migration-only parts after the lanes')
for k in ('gatehead', 'driver', 'shell', 'bench'):
    ap.add_argument('--' + k)
ap.add_argument('--docs', help='default: <c6>/<tag>_docs')
ap.add_argument('--intro', help='default: <docs>/migration_intro.md')
a = finish(ap.parse_args())
repo = a.repo
D = a.docs or in_c6(a, 'docs')


def part(f):
    return rd(os.path.join(D, f)).rstrip('\n') + '\n'


head = part('changelog_head.md')
for k in ('gatehead', 'driver', 'shell', 'bench'):
    ph = '@' + k.upper() + '@'
    v = getattr(a, k)
    if ph in head:
        if v is None:
            sys.exit(f'changelog_head.md carries {ph}: pass --{k}')
        head = head.replace(ph, v)
parts = [head]
lanes = names(a.lanes)
for l in lanes + names(a.extra):
    parts.append(part('changelog_%s.md' % l))
body = '\n'.join(parts)
p = os.path.join(repo, 'CHANGELOG.md')
s = rd(p)
hdr = re.compile(r'^## \[' + re.escape(a.ver) + r'\] — \d{4}-\d{2}-\d{2}\n', re.M)
n = len(hdr.findall(s))
if n != 1:
    sys.exit(f'CHANGELOG.md: the "## [{a.ver}] — <date>" placeholder header appears {n} times (want 1)')
# only the EMPTY placeholder version-bump.sh writes (the header, a blank line, the previous "## ["):
# an assembled header matches hdr too, and a second run would insert the whole entry again
m = hdr.search(s)
if not re.match(r'\s*## \[', s[m.end():]):
    sys.exit(f'CHANGELOG.md: [{a.ver}] is not the empty placeholder (already assembled?) — nothing written')
s = s[:m.start()] + '## [%s] — %s\n\n' % (a.ver, a.date) + body + s[m.end():]
intro = rd(a.intro or os.path.join(D, 'migration_intro.md')).rstrip('\n') + '\n\n'
mparts = [intro]
for l in lanes + names(a.mig_extra):
    mparts.append(part('migration_%s.md' % l))
mig = '\n'.join(mparts) + '\n'
pm = os.path.join(repo, 'docs/development/ecosystem-migration.md')
sm = rd(pm)
anchor = '### %s\n' % a.prev
if sm.count(anchor) != 1:
    sys.exit(f'ecosystem-migration.md: "### {a.prev}" appears {sm.count(anchor)} times (want 1)')
if re.search(r'^### ' + re.escape(a.ver) + r'\n', sm, re.M):
    sys.exit(f'ecosystem-migration.md already has "### {a.ver}" (already assembled?) — nothing written')
sm = sm.replace(anchor, mig + anchor, 1)
wr(p, s, a.dry)
wr(pm, sm, a.dry)
print('%sCHANGELOG +%d lines, migration +%d lines' % ('(dry) ' if a.dry else '', body.count('\n'), mig.count('\n')))
