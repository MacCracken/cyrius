#!/usr/bin/env python3
# scripts/dev/ab.py — A/B self-compile timing of two refs: each ref's committed compiler compiling
# each ref's sources, interleaved on one box (the CHANGELOG's bench delta).
#
# Usage:  python3 scripts/dev/ab.py <old_ref> <new_ref> [--runs N] [--repo DIR]
#
# Input:  the two refs of the cyrius checkout (this file's ../.., or --repo / CYRIUS_REPO): each
#         ref's compiler from `git show <ref>:build/cycc`, its sources from `git archive <ref> src lib`,
#         both staged in a private temp dir under CYRIUS_SCRATCH (default
#         ${XDG_CACHE_HOME:-$HOME/.cache}/c6), removed at the end.
# Output: the min over N runs (default 6) of `<cc> < src/main.cyr > /dev/null`, run from each source
#         tree, all four pairs interleaved run by run:
#           own sources  old cc on old src vs new cc on new src: old ms, new ms, pct
#           same input   old cc vs new cc on old src, and on new src: old ms, new ms, pct
#         and every run's time per pair. A pair whose compile exits non-zero (the old compiler may
#         refuse the new sources) prints `n/a (rc=<rc>)` in place of its time.
# The compilers run in the DEFAULT mode: CYRIUS_BOUNDS / CYRIUS_POISON / CYRIUS_COVERAGE /
# CYRIUS_COVERAGE_FILE are dropped from their environment (an inherited mode would time a
# bounds-checked, poison or instrumented compile).
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MODE_VARS = ('CYRIUS_BOUNDS', 'CYRIUS_POISON', 'CYRIUS_COVERAGE', 'CYRIUS_COVERAGE_FILE')


def die(msg):
    print('ab: ' + msg, file=sys.stderr)
    sys.exit(2)


def git(root, *args, **kw):
    return subprocess.run(['git', '-C', root] + list(args), check=False, **kw)


def stage(root, ref, d):
    """<d>/cycc = <ref>:build/cycc, <d>/src + <d>/lib = <ref>'s trees."""
    os.makedirs(d)
    p = git(root, 'show', ref + ':build/cycc', capture_output=True)
    if p.returncode != 0 or not p.stdout:
        die(f"git show {ref}:build/cycc failed: {p.stderr.decode(errors='replace').strip()}")
    cc = os.path.join(d, 'cycc')
    with open(cc, 'wb') as f:
        f.write(p.stdout)
    os.chmod(cc, 0o755)
    arc = subprocess.Popen(['git', '-C', root, 'archive', ref, 'src', 'lib'], stdout=subprocess.PIPE)
    tar = subprocess.run(['tar', '-x', '-C', d], stdin=arc.stdout)
    arc.stdout.close()
    if arc.wait() != 0 or tar.returncode != 0:
        die(f"git archive {ref} src lib | tar -x failed")
    if not os.path.isfile(os.path.join(d, 'src', 'main.cyr')):
        die(f"{ref} has no src/main.cyr")
    return cc


def run(cc, d, env):
    with open(os.path.join(d, 'src', 'main.cyr'), 'rb') as src:
        t = time.perf_counter()
        r = subprocess.run([cc], stdin=src, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=d, env=env)
        ms = (time.perf_counter() - t) * 1000
    return ms, r.returncode


def main():
    ap = argparse.ArgumentParser(description='A/B self-compile timing of two refs.')
    ap.add_argument('old_ref')
    ap.add_argument('new_ref')
    ap.add_argument('--runs', type=int, default=6, help='runs per pair (default 6); the min is reported')
    ap.add_argument('--repo', help='the cyrius checkout (default: this script\'s ../.., or CYRIUS_REPO)')
    a = ap.parse_args()
    if a.runs < 1:
        die('--runs must be at least 1')
    root = a.repo or os.environ.get('CYRIUS_REPO') or str(Path(__file__).resolve().parents[2])
    for ref in (a.old_ref, a.new_ref):
        if git(root, 'rev-parse', '--verify', '--quiet', ref + '^{commit}', capture_output=True).returncode != 0:
            die(f"{ref}: not a commit in {root}")
    scratch = os.environ.get('CYRIUS_SCRATCH') or os.path.join(
        os.environ.get('XDG_CACHE_HOME') or os.path.join(os.path.expanduser('~'), '.cache'), 'c6')
    os.makedirs(scratch, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='ab.', dir=scratch)
    env = {k: v for k, v in os.environ.items() if k not in MODE_VARS}
    try:
        old_cc = stage(root, a.old_ref, os.path.join(tmp, 'old'))
        new_cc = stage(root, a.new_ref, os.path.join(tmp, 'new'))
        old_d, new_d = os.path.join(tmp, 'old'), os.path.join(tmp, 'new')
        pairs = {  # (compiler, source tree)
            'old cc / old src': (old_cc, old_d),
            'new cc / new src': (new_cc, new_d),
            'new cc / old src': (new_cc, old_d),
            'old cc / new src': (old_cc, new_d),
        }
        times = {k: [] for k in pairs}
        rcs = {k: 0 for k in pairs}
        for _ in range(a.runs):
            for k, (cc, d) in pairs.items():
                ms, rc = run(cc, d, env)
                times[k].append(ms)
                if rc != 0:
                    rcs[k] = rc
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    def best(k):
        return None if rcs[k] else min(times[k])

    def fmt(k):
        return f"n/a (rc={rcs[k]})" if rcs[k] else f"{best(k):.0f} ms"

    def line(title, ko, kn):
        s = f"{title:<34} old {fmt(ko):>14}   new {fmt(kn):>14}"
        if best(ko) is not None and best(kn) is not None:
            s += f"   delta {(best(kn) / best(ko) - 1) * 100:+.1f}%"
        print(s)

    o, n = a.old_ref, a.new_ref
    print(f"old = {o}, new = {n}; min of {a.runs} run(s) each")
    line('own sources (each on its own src)', 'old cc / old src', 'new cc / new src')
    line(f'same input ({o} src)', 'old cc / old src', 'new cc / old src')
    line(f'same input ({n} src)', 'old cc / new src', 'new cc / new src')
    for k in pairs:
        print(f"all {k}: {[round(x) for x in times[k]]}" + (f"  (rc={rcs[k]})" if rcs[k] else ''))


if __name__ == '__main__':
    main()
