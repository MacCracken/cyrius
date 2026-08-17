#!/bin/sh
# err_msg_lengths_match.sh — every `ERR_MSG(S, "text", N)` must declare N == strlen(text).
#
# v6.5.24. The audit that prompted this found **49 of 104 sites wrong — 47 %**. Both
# directions are real defects, and neither is visible by reading the output:
#   * N too SMALL  -> the message is TRUNCATED. Measured: "multi-value destructure needs a
#     call on the right-hand side" printed as "...right-hand sid", silently losing its last
#     character. A truncated diagnostic still looks like a diagnostic.
#   * N too LARGE  -> `sys_write` reads PAST the literal into whatever bytes follow it.
#
# ⛔ WHY A GATE AND NOT JUST THE SWEEP. This is a hand-maintained value that duplicates a
# fact the compiler already has (the string's own length), so it drifts every time anyone
# edits a message — and it had drifted to nearly half the corpus with nothing detecting it.
# Four of the 49 were introduced in v6.5.23, days before the audit, by the same author who
# then wrote the sweep. A one-off correction of a self-drifting value is not a fix.
#
# This is the third value of that shape found in one cycle: heap-map sizes vs actual
# regions, gate-script counts vs files on disk, and now string lengths vs strings. All
# three are mechanically derivable and all three were wrong. Derive, never restate.
#
# ⛔ v6.5.25 — THE GATE ITSELF HAD THE SAME DISEASE IT WAS BUILT TO CURE: it was scoped to
# `ERR_MSG` under `src/` only, so the entire CLI (`cbt/`, which does all its diagnostics via
# `sys_write`) was invisible to it — and it compared CHARACTERS where `sys_write` counts
# BYTES. Widening to both trees, both call forms and byte-length comparison turned up
# **16 more wrong sites**, 13 of them in `cbt/` and 3 in `src/` that only the byte
# comparison can see (a `—` em-dash is 3 bytes, so a visually-correct count is short by 2).
# Two of the 16 were added by v6.5.24 itself and shipped truncated: `cbt/deps.cyr` printed
# `(looked in./lib)` with its trailing space eaten, measured on the real bote tree.
# Scanning only the directory where a class was first found is how it returns next door.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

python3 - "$ROOT" <<'PY'
import glob, re, sys, os
root = sys.argv[1]
# THREE literal-with-declared-length forms. All three have shipped truncating messages, and
# each was found only after the previous one was gated -- so the scan covers all of them and
# every tree that has them.
#   ERR_MSG(S, "text", N)                the compiler's diagnostic helper
#   sys_write(FD, "text", N)             the CLI's writes (cbt/)
#   syscall(SYS_WRITE, FD, "text", N)    the DOMINANT form in src/ and programs/
#
# SCANNED WHOLE-FILE, NOT LINE-BY-LINE. Every long message in this tree is wrapped across
# source lines, so a per-line regex silently skips exactly the messages most likely to have a
# miscounted length. That blind spot hid the biggest one in the tree: the PE syscall routes
# warning declared 617 bytes for a 1233-byte string, i.e. it had been printing HALF of itself
# and cutting off mid-word at "0xF01F-0xF021 (IOCP: Create" -- visible in every Windows
# build's output for releases, and read past by everyone, including the author of the first
# two versions of this gate.
#
# History of this one check, which is the argument for scanning broadly the first time:
#   v6.5.24   ERR_MSG under src/, per line                     -> found 49 of 104
#   v6.5.25a  + sys_write, + cbt/, byte-accurate               -> found 16 more
#   v6.5.25b  + syscall(SYS_WRITE,..), + programs/, whole-file -> found 12 more
PATS = [
    re.compile(r'ERR_MSG\(\s*S\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*(\d+)\s*\)', re.S),
    re.compile(r'sys_write\(\s*[A-Za-z0-9_]+\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*(\d+)\s*\)', re.S),
    re.compile(r'syscall\(\s*SYS_WRITE\s*,\s*[A-Za-z0-9_]+\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*(\d+)\s*\)', re.S),
]
TREES = ['src/**/*.cyr', 'cbt/**/*.cyr', 'programs/**/*.cyr']
bad, tot = [], 0
files = []
for t in TREES:
    files += glob.glob(os.path.join(root, t), recursive=True)
for path in sorted(set(files)):
    rel = os.path.relpath(path, root)
    txt = open(path).read()
    for pat in PATS:
        for m in pat.finditer(txt):
            tot += 1
            lit = (m.group(1).replace('\\n', '\n').replace('\\t', '\t')
                             .replace('\\"', '"').replace('\\\\', '\\'))
            # BYTES, not characters: an em-dash is 3 bytes and sys_write counts bytes.
            if len(lit.encode('utf-8')) != int(m.group(2)):
                ln = txt[:m.start()].count('\n') + 1
                bad.append((rel, ln, len(lit.encode('utf-8')), int(m.group(2)), lit[:50]))

# axis 0 -- anti-vacuous: a regex that matches nothing reports nothing wrong and PASSES.
FLOOR = 950
if tot < FLOOR:
    print("  FAIL: only %d declared-length sites parsed (floor %d) - the scanner is blind, not the source clean" % (tot, FLOOR))
    sys.exit(1)
print("  ok: scanner sees %d declared-length sites across 3 call forms in src/ cbt/ programs/ (floor %d)" % (tot, FLOOR))

if bad:
    for rel, ln, act, dec, txt2 in bad:
        kind = "TRUNCATES" if dec < act else "OVER-READS"
        print('  FAIL: %s:%d declared=%d actual=%d (%s) "%s"' % (rel, ln, dec, act, kind, txt2))
    print("FAIL: err-msg-lengths-match - %d of %d declared lengths wrong" % (len(bad), tot))
    sys.exit(1)
print("  ok: all %d declared lengths equal their byte length" % tot)
print("PASS: err-msg-lengths-match - %d/%d sites consistent" % (tot, tot))
PY
