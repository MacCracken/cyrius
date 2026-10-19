# scripts/release/release_common.py — the helpers the release steps share (imported by place.py,
# briefs.py, archive.py, assemble.py and roadmap-state.py; not run on its own): the common
# arguments (--repo, --ver, --c6, --date, --dry), the repo root taken from this file's location,
# the scratch default, and UTF-8 reads and dry-run-aware writes.
#
# inputs:  none of its own. outputs: none of its own.
#   --repo  default: $CYRIUS_REPO, else the checkout this file lives in (two levels up)
#   --c6    default: $CYRIUS_SCRATCH, else ${XDG_CACHE_HOME:-$HOME/.cache}/c6 — the release's
#           scratch directory, where every step's <tag>_* inputs and outputs live
#           (<tag> = the version without dots: X.Y.Z -> XYZ)
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def default_scratch():
    s = os.environ.get('CYRIUS_SCRATCH')
    if s:
        return s
    cache = os.environ.get('XDG_CACHE_HOME') or os.path.join(os.path.expanduser('~'), '.cache')
    return os.path.join(cache, 'c6')


def parser(description, date=False, dry=False):
    ap = argparse.ArgumentParser(description=description)
    ap.add_argument('--repo', help='the cyrius checkout to read / edit (default: $CYRIUS_REPO, else the checkout '
                                   'this script lives in)')
    ap.add_argument('--ver', required=True, help='the release, X.Y.Z')
    ap.add_argument('--c6', help='the release scratch dir (default: $CYRIUS_SCRATCH, else '
                                 '${XDG_CACHE_HOME:-~/.cache}/c6)')
    if date:
        ap.add_argument('--date', required=True, help='YYYY-MM-DD')
    if dry:
        ap.add_argument('--dry', action='store_true', help='report what would change; write nothing')
    return ap


def finish(args):
    """Resolve the defaults that depend on the environment; add args.tag."""
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.ver):
        sys.exit(f'--ver must be X.Y.Z, got {args.ver!r}')
    if getattr(args, 'date', None) is not None and not re.fullmatch(r'\d{4}-\d{2}-\d{2}', args.date):
        sys.exit(f'--date must be YYYY-MM-DD, got {args.date!r}')
    args.repo = os.path.abspath(args.repo or os.environ.get('CYRIUS_REPO') or str(ROOT))
    args.c6 = os.path.abspath(args.c6 or default_scratch())
    args.tag = args.ver.replace('.', '')
    return args


def in_c6(args, name):
    """<c6>/<tag>_<name>"""
    return os.path.join(args.c6, f'{args.tag}_{name}')


def rd(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def wr(path, text, dry):
    if dry:
        return
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
