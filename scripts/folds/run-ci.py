#!/usr/bin/env python3
"""scripts/folds/run-ci.py — run a fold's GitHub workflow `run:` steps locally, with GitHub's
shell semantics. scripts/folds/sibci.sh calls it inside an isolated copy; run it by hand only on a
throwaway copy (it runs the workflow's steps in the copy, with the caller's HOME and CYRIUS_HOME).

usage: python3 scripts/folds/run-ci.py <repo-copy> [--include-release] [--list]
       (--list: print the steps and shells, run nothing)
inputs: <repo-copy>/.github/workflows/*.yml and *.yaml (no yaml dependency: parsed by indentation)
env:   REPO_NAME   substituted for ${{ github.event.repository.name }} (default: basename of the copy)
       CI_TIMEOUT  per-step seconds (default 1500)
       RUNNER_TEMP (default: <copy>/../runner_tmp)
       CI_JOB      run only the job with this id
       CI_VERBOSE  set: print the last 40 output lines of each failing step
outputs: stdout, one line per step (below); exit 1 if any gating step FAILs, else 0.
converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md

Shell selection follows GitHub on ubuntu: a step's own `shell:`, else the job's
`defaults.run.shell`, else the workflow's; `bash` means `bash --noprofile --norc -eo pipefail`,
an unspecified shell means `bash -e` (NO pipefail), `sh` means `sh -e`. The previous runner
forced `-eo pipefail` everywhere, which failed steps that are green on GitHub.
Steps are skipped only when they cannot run here: `uses:` actions (no run:), and the
toolchain-install / checkout / upload / cache steps (the caller provides a throwaway
CYRIUS_HOME instead). Release workflows are skipped unless --include-release.
Output: one line per step, OK/FAIL (SKIP only for a step that fails because sudo needs a password —
a runner package install that cannot run here; named, never counted as a pass), [workflow] [job] name | last output line; exit 1 if any FAIL.
"""
import os, re, subprocess, sys, glob

repo = os.path.abspath(sys.argv[1])
incl_release = '--include-release' in sys.argv[2:]
list_only = '--list' in sys.argv[2:]
os.chdir(repo)
SKIP = ('Install Cyrius toolchain', 'Install cyrius', 'Install Cyrius', 'Checkout', 'Upload', 'Cache', 'Set up', 'Setup ')
SHELLS = {'bash': ['bash', '--noprofile', '--norc', '-eo', 'pipefail', '-c'], None: ['bash', '-e', '-c'], 'sh': ['sh', '-e', '-c']}
repo_name = os.environ.get('REPO_NAME', os.path.basename(repo.rstrip('/')))
rt = os.environ.get('RUNNER_TEMP', os.path.join(os.path.dirname(repo), 'runner_tmp'))
os.makedirs(rt, exist_ok=True)
timeout = int(os.environ.get('CI_TIMEOUT', '1500'))
fails = 0


def indent(l):
    return len(l) - len(l.lstrip(' '))


def parse(path):
    """Return (workflow_shell, [job dicts]) using indentation only (no yaml dependency)."""
    lines = open(path).read().split('\n')
    wf_shell = None
    jobs = []
    job = None
    step = None
    in_run = False
    run_ind = 0
    jobs_ind = None
    ctx = []  # stack of (indent, key)
    for raw in lines:
        l = raw.rstrip('\n')
        s = l.strip()
        if in_run:
            if s == '':
                step['run'].append('')
                continue
            if indent(l) >= run_ind:
                step['run'].append(l[run_ind:])
                continue
            in_run = False
        if s == '' or s.startswith('#'):
            continue
        ind = indent(l)
        while ctx and ctx[-1][0] >= ind:
            ctx.pop()
        keys = [k for _, k in ctx]
        m = re.match(r'^(\s*)(-\s+)?([A-Za-z_][\w-]*):\s*(.*)$', l)
        if not m:
            continue
        dash, key, val = m.group(2), m.group(3), m.group(4).strip()
        if key == 'jobs' and ind == 0:
            jobs_ind = None
            ctx.append((ind, 'jobs'))
            continue
        if keys == ['jobs'] and not dash:
            job = {'name': key, 'shell': None, 'steps': []}
            jobs.append(job)
            ctx.append((ind, 'job'))
            continue
        if key == 'shell' and keys == ['defaults', 'run']:
            wf_shell = val
            continue
        if key == 'shell' and keys == ['jobs', 'job', 'defaults', 'run'] and job:
            job['shell'] = val
            continue
        if job and 'steps' in keys and dash:
            step = {'name': val if key == 'name' else '', 'run': [], 'shell': None, 'uses': key == 'uses', 'coe': False}
            job['steps'].append(step)
            if key == 'run':
                step['run'] = [] if val in ('|', '>') else [val]
                if val in ('|', '|-', '>'):
                    in_run = True
                    run_ind = ind + (len(dash) if dash else 0) + 2
            ctx.append((ind, 'step'))  # properties sit deeper than the dash, so they never pop it
            continue
        if step is not None and keys and keys[-1] == 'step':
            if key == 'name':
                step['name'] = val
            elif key == 'uses':
                step['uses'] = True
            elif key == 'shell':
                step['shell'] = val
            elif key == 'continue-on-error':
                step['coe'] = val.strip().lower() == 'true'
            elif key == 'run':
                if val in ('|', '|-', '>'):
                    in_run = True
                    run_ind = ind + 2
                else:
                    step['run'] = [val]
            continue
        if not val:
            ctx.append((ind, key))
    return wf_shell, jobs


for wf in sorted(glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml')):
    base = os.path.basename(wf)
    if 'release' in base and not incl_release:
        continue
    wf_shell, jobs = parse(wf)
    for job in jobs:
        if os.environ.get('CI_JOB') and job['name'] != os.environ['CI_JOB']:
            continue
        for st in job['steps']:
            if not st['run'] or any(st['name'].startswith(p) for p in SKIP):
                continue
            sh = st['shell'] or job['shell'] or wf_shell
            key = 'bash' if sh and sh.startswith('bash') else ('sh' if sh and sh.startswith('sh') else None)
            argv = SHELLS[key]
            if list_only:
                print(f"[{base}] [{job['name']}] [{key or 'bash -e'}] {st['name'][:60]}  ({len(st['run'])} lines)")
                continue
            script = '\n'.join(st['run']).replace('${{ github.event.repository.name }}', repo_name)
            script = re.sub(r'\$\{\{[^}]*\}\}', '', script)  # GitHub renders an undefined expression (an action output, a secret) as empty
            env = dict(os.environ)
            env['RUNNER_TEMP'] = rt
            env.setdefault('GITHUB_ENV', os.path.join(rt, 'github_env'))
            env.setdefault('GITHUB_PATH', os.path.join(rt, 'github_path'))
            env.setdefault('GITHUB_OUTPUT', os.path.join(rt, 'github_output'))
            env.setdefault('GITHUB_STEP_SUMMARY', os.path.join(rt, 'github_summary'))
            try:
                r = subprocess.run(argv + [script], capture_output=True, text=True, timeout=timeout, env=env)
                rc = r.returncode
                out = (r.stdout + r.stderr).strip()
                tail = out.split('\n')[-1][:110] if out else ''
            except subprocess.TimeoutExpired:
                rc, tail, out = 'TO', 'timeout', ''
            ok = rc == 0
            sudo_blocked = (not ok) and 'sudo: a password is required' in out
            if sudo_blocked:
                print(f"SKIP [{base}] [{job['name']}] [{key or 'bash -e'}] {st['name'][:50]:50} | needs sudo (a CI-runner package install) — cannot run here", flush=True)
                continue
            if (not ok) and st.get('coe'):
                print(f"FAIL [{base}] [{job['name']}] [{key or 'bash -e'}] {st['name'][:50]:50} | NON-GATING (continue-on-error: true) — {tail}", flush=True)
                continue
            fails += 0 if ok else 1
            print(f"{'OK  ' if ok else 'FAIL'} [{base}] [{job['name']}] [{key or 'bash -e'}] {st['name'][:50]:50} | {tail}", flush=True)
            if not ok and os.environ.get('CI_VERBOSE'):
                print('\n'.join('    ' + x for x in out.split('\n')[-40:]))
sys.exit(1 if fails else 0)
