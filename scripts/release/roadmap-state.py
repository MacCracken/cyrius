#!/usr/bin/env python3
# scripts/release/roadmap-state.py — at a release's close: derive the tree's figures (corpus
# counts, compiler sizes, .text, api-surface, open issues / proposals, issues placed per release)
# and apply the release's prose template to docs/development/roadmap.md, state.md and
# completed-phases.md (the head stamp, the sequence table, the shipped section pruned, state's
# rows, the completed-phases line). With --derive it only prints the figures.
#
# usage:   python3 scripts/release/roadmap-state.py --ver X.Y.Z --derive [--repo <checkout>]
#          python3 scripts/release/roadmap-state.py --ver X.Y.Z [--template F] [--set key=value]...
#            [--date YYYY-MM-DD] [--dry] [--repo <checkout>] [--c6 <dir>]
#   --derive     print the derived figures (key=value) and exit; writes nothing, needs no template
#   --set k=v    a value the template uses that the tree cannot give (the gate head, the driver and
#                shell counts, the bench, the A/B figures, the archived count, ...); repeatable
#   --date       available to the template as {date}
#   --dry        print the unified diff it would apply; write nothing
# inputs:  the checkout: tests/tcyr, tests/gates, lib/*.cyr, docs/api-surface.snapshot,
#          docs/development/issues/*.md (their first **Placement:** line), docs/development/proposals,
#          build/cycc and build/cycc-native-aarch64 (readelf reads build/cycc's .text);
#          <template> (default <c6>/<tag>_roadmap_state.json): this release's prose as edit
#          operations with {placeholders} — schema in README.md
# outputs: --derive: the figures on stdout. Otherwise the three docs edited in place, the figures
#          and one line per operation (a "matched nothing" warning when one does). Exit 1, writing
#          nothing, when an issue is still placed in X.Y.Z, a placeholder has no value, or an
#          operation's row / marker is missing.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import collections
import difflib
import glob
import json
import os
import re
import shutil
import string
import subprocess
import sys

sys.dont_write_bytecode = True  # importing release_common leaves no __pycache__ in the tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from release_common import parser, finish, in_c6, rd, wr  # noqa: E402


def count_named(top, suffix):
    """find <top> -name '*<suffix>' | wc -l (files and directories, at any depth)."""
    n = 0
    for _, dirs, files in os.walk(top):
        n += sum(1 for x in dirs + files if x.endswith(suffix))
    return n


def text_size(elf):
    """build/cycc's .text size, as `readelf -S | awk '/ .text/{getline; print $1}'` reads it."""
    if not shutil.which('readelf'):
        sys.exit('roadmap-state.py: readelf not found (binutils) — it reads build/cycc\'s .text size')
    out = subprocess.run(['readelf', '-S', elf], capture_output=True, text=True, check=True).stdout.split('\n')
    for i, line in enumerate(out):
        if ' .text' in line:
            return int(out[i + 1].split()[0], 16)
    sys.exit(f'roadmap-state.py: readelf -S {elf} lists no .text section')


def derive(repo):
    j = lambda *p: os.path.join(repo, *p)  # noqa: E731
    v = {}
    v['n_tcyr'] = count_named(j('tests/tcyr'), '.tcyr')
    v['n_cross'] = count_named(j('tests/tcyr/crossos'), '.tcyr')
    v['n_lib'] = len(glob.glob(j('lib/*.cyr')))
    v['n_gates'] = count_named(j('tests/gates'), '.sh')
    v['n_api'] = f"{sum(1 for l in rd(j('docs/api-surface.snapshot')).splitlines() if not l.startswith('#')):,}"
    v['n_open'] = sum(1 for f in glob.glob(j('docs/development/issues/*.md')) if 'README.md' not in f)
    v['n_prop'] = sum(1 for f in glob.glob(j('docs/development/proposals/*.md')) if 'README' not in f)
    v['cyc'] = f"{os.path.getsize(j('build/cycc')):,}"
    v['arm'] = f"{os.path.getsize(j('build/cycc-native-aarch64')):,}"
    v['text'] = f"{text_size(j('build/cycc')):,}"
    placed = collections.Counter()
    for f in glob.glob(j('docs/development/issues/*.md')):
        for line in open(f, encoding='utf-8'):
            if line.startswith('**Placement:**'):
                m = re.match(r'\*\*Placement:\*\* (\d+\.\d+\.\d+) ', line)
                if m:
                    placed[m.group(1)] += 1
                break
    return v, placed


class Values(dict):
    def __missing__(self, k):
        sys.exit(f'the template uses {{{k}}}, which has no value (derive it, or pass --set {k}=...)')


def row_re(name, group=False):
    body = r' \| (.*) \|$' if group else r' \|.*\|$'
    return re.compile(r'^\| \*\*' + re.escape(name) + r'\*\*' + body, re.M)


def apply(s, op, fill, log):
    if 'sub' in op:
        flags = 0
        for ch in op.get('flags', ''):
            flags |= {'S': re.S, 'M': re.M, 'I': re.I}[ch]
        s2, n = re.subn(op['sub'], fill(op['to']), s, count=op.get('count', 0), flags=flags)
        log(f"sub {op['sub'][:60]!r}: {n}")
        return s2
    if 'replace' in op:
        n = s.count(op['replace'])
        if op.get('must') and n == 0:
            sys.exit(f"replace: {op['replace']!r} is not in the file — nothing written")
        log(f"replace {op['replace'][:60]!r}: {n}")
        return s.replace(op['replace'], fill(op['to']))
    if 'cut' in op:
        a, b = op['cut']
        if a not in s or b not in s:
            sys.exit(f'cut: {a!r} or {b!r} is not in the file — nothing written')
        i = s.index(a)
        j = s.index(b)
        log(f'cut {a!r} .. {b!r}: {s[i:j].count(chr(10))} lines')
        return s[:i] + s[j:]
    if 'row' in op:
        name = op['row']
        if 'keep_from' in op:
            m = row_re(name, group=True).search(s)
            if not m or op['keep_from'] not in m.group(1):
                sys.exit(f"row {name!r}: no such row, or no {op['keep_from']!r} in it — nothing written")
            body = m.group(1)
            body = fill(op['to']) + body[body.index(op['keep_from']):]
        else:
            m = row_re(name).search(s)
            if not m:
                sys.exit(f'row {name!r}: no such row — nothing written')
            body = fill(op['to'])
        log(f'row {name!r}')
        return s[:m.start()] + f'| **{name}** | {body} |' + s[m.end():]
    if 'insert_after_row' in op:
        m = row_re(op['insert_after_row']).search(s)
        if not m:
            sys.exit(f"insert_after_row {op['insert_after_row']!r}: no such row — nothing written")
        log(f"insert after row {op['insert_after_row']!r}")
        return s[:m.end()] + '\n' + fill(op['to']) + s[m.end():]
    sys.exit(f'unknown operation: {op}')


def main():
    ap = parser('Derive the tree\'s figures and apply the release\'s roadmap / state / completed-phases template.',
                dry=True)
    ap.add_argument('--derive', action='store_true', help='print the derived figures and exit')
    ap.add_argument('--template', help='default: <c6>/<tag>_roadmap_state.json')
    ap.add_argument('--set', action='append', default=[], metavar='KEY=VALUE')
    ap.add_argument('--date')
    a = finish(ap.parse_args())
    v, placed = derive(a.repo)
    print('derived:', ' '.join(f'{k}={x}' for k, x in v.items()),
          ' placed:', ' '.join(f'{k}={placed[k]}' for k in sorted(placed, key=lambda r: [int(x) for x in r.split('.')])))
    if a.derive:
        return
    if placed[a.ver]:
        sys.exit(f'{placed[a.ver]} issue(s) still placed {a.ver} — place them before the close (nothing written)')
    vals = Values(v)
    vals['placed'] = collections.defaultdict(int, placed)
    vals['ver'] = a.ver
    if a.date:
        vals['date'] = a.date
    for kv in a.set:
        k, sep, x = kv.partition('=')
        if not sep:
            sys.exit(f'--set wants KEY=VALUE, got {kv!r}')
        vals[k] = x
    fmt = string.Formatter()

    def fill(t):
        return fmt.vformat(t, (), vals)

    T = json.loads(rd(a.template or in_c6(a, 'roadmap_state.json')))
    new = {}
    for rel, ops in T['files'].items():
        p = os.path.join(a.repo, rel)
        s = new.get(p) or rd(p)
        for op in ops:
            def log(msg, rel=rel):
                print(f'  {rel}: {msg}' + ('   <- matched nothing' if msg.endswith(': 0') else ''))
            s = apply(s, op, fill, log)
        new[p] = s
    for p, s in new.items():
        if a.dry:
            old = rd(p)
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), s.splitlines(True),
                                                       os.path.relpath(p, a.repo), os.path.relpath(p, a.repo)))
        wr(p, s, a.dry)
    print('(dry) ' if a.dry else '', 'roadmap / state / completed-phases ', 'checked' if a.dry else 'written', sep='')


main()
