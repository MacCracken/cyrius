#!/bin/sh
# write_literal_lengths.sh — v6.5.47
#
# ⛔ EVERY `syscall(1, fd, "…", N)` / `sys_write(fd, "…", N)` DECLARES ITS OWN LENGTH, AND THE
# TWO DRIFT. cyrius has no `strlen` at these call sites — the byte count is written by hand next
# to the literal — so an edit to the message that does not touch the number silently changes what
# is printed:
#   * over-declared  -> the write runs PAST the literal and leaks whatever bytes follow it;
#   * under-declared -> the message is TRUNCATED, most often losing its trailing newline.
# Found at v6.5.47 by scanning the tree: **24** mismatches in cyrius-owned code, every one in
# `programs/` — `cyriusly` alone had 16, so most of its `--help` was leaking or losing a byte,
# and `ark` was printing "system backend: pacman" with the newline cut off.
# ⭐ `src/` was clean: the compiler is fine, the tooling around it was not.
#
# ⚠ THE USUAL CAUSE IS A MULTI-BYTE CHARACTER. An em-dash is THREE bytes in UTF-8 and one
# character on screen, so a count written by eye is short by two. CLAUDE.md already records this
# as a rule; this gate is what makes it enforceable rather than remembered — the author got it
# wrong three separate times in the session that added this.
#
# ⚠ SCOPE IS DELIBERATELY NARROW: only the two write-call shapes, where the trailing number is
# unambiguously a byte length. A looser "string followed by a number" scan reports dozens of
# false positives — `("Predictor", 1)` is a key/arity pair, `("cycc", 3)` an index. Measured: the
# loose version flagged 70 and meant about 24.
#
# ⚠ ESCAPES MUST BE RESOLVED LEFT-TO-RIGHT, NOT WITH INDEPENDENT SUBSTITUTIONS. The first cut of
# this gate used `sed 's/\n/…/; s/\t/…/'`, which does not handle `\"` or `\\` and therefore
# reported 19 FALSE positives in `src/frontend/lex.cyr` and `cbt/` — every one a literal that
# legitimately contains an escaped quote or backslash. A gate that cries wolf is how a real
# finding gets ignored.
#
# ⚠ lib/*.cyr IS EXCLUDED: those are VENDORED copies of sibling repos, so a fix applied here
# evaporates at the next re-vendor. `lib/sigil.cyr` carries one mismatch; it belongs upstream.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)

python3 - "$ROOT" <<'PY'
import re, sys, glob, os
root = sys.argv[1]
os.chdir(root)

def unesc(lit):
    out = []; i = 0
    while i < len(lit):
        c = lit[i]
        if c == '\\' and i + 1 < len(lit):
            n = lit[i+1]
            out.append({'n':'\n','t':'\t','0':'\0','\\':'\\','"':'"','r':'\r'}.get(n, '\\' + n))
            i += 2
        else:
            out.append(c); i += 1
    return ''.join(out)

# ⚠ v6.5.49: ERR_MSG / WARN carry the same hand-written length and were NOT covered when this
# gate landed at v6.5.47 — which is how two `WARN(S, "...", 45)` sites for a 41-byte literal
# survived it, each leaking 4 bytes past the string. The roadmap had carried an "ERR_MSG
# hardcoded-length audit" as an open item since v6.4.57 for exactly this; adding the two
# patterns closes it. If a new diagnostic helper takes a literal and a length, add it here.
PATS = [
    re.compile(r'syscall\(\s*(?:1|SYS_WRITE)\s*,\s*[0-9A-Za-z_]+\s*,\s*"((?:[^"\\\n]|\\.)*)"\s*,\s*(\d+)\s*\)'),
    re.compile(r'sys_write\(\s*[0-9A-Za-z_]+\s*,\s*"((?:[^"\\\n]|\\.)*)"\s*,\s*(\d+)\s*\)'),
    re.compile(r'ERR_MSG\(\s*S\s*,\s*"((?:[^"\\\n]|\\.)*)"\s*,\s*(\d+)\s*\)'),
    re.compile(r'WARN\(\s*S\s*,\s*"((?:[^"\\\n]|\\.)*)"\s*,\s*(\d+)\s*\)'),
]

files = sorted(set(sum([glob.glob(p, recursive=True)
                        for p in ('src/**/*.cyr', 'programs/**/*.cyr', 'cbt/*.cyr')], [])))
bad, total = [], 0
for f in files:
    try:
        s = open(f, encoding='utf-8').read()
    except OSError:
        continue
    for pat in PATS:
        for m in pat.finditer(s):
            total += 1
            real = len(unesc(m.group(1)).encode('utf-8'))
            if real != int(m.group(2)):
                bad.append((f, s[:m.start()].count('\n') + 1, int(m.group(2)), real, m.group(1)[:52]))

# Anti-vacuous: a regex that matches nothing reports nothing wrong and PASSES.
if total < 400:
    print(f"FAIL write_literal_lengths: only {total} write-with-length call sites found "
          f"(expected 400+) — the scan is reading almost nothing, which would pass for the wrong reason",
          file=sys.stderr)
    sys.exit(1)

if bad:
    for f, ln, dec, real, lit in bad:
        print(f"  {f}:{ln} declared {dec}, actual {real} — {lit!r}", file=sys.stderr)
    print(f"FAIL write_literal_lengths: {len(bad)} declared write length(s) disagree with their "
          f"literal. Over-declared LEAKS the bytes after the string; under-declared TRUNCATES the "
          f"message (usually its newline).", file=sys.stderr)
    sys.exit(1)

print(f"PASS write_literal_lengths ({total} declared write lengths across src/ programs/ cbt/, all matching their literals)")
PY
