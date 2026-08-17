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
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

python3 - "$ROOT" <<'PY'
import glob, re, sys, os
root = sys.argv[1]
pat = re.compile(r'ERR_MSG\(S,\s*"((?:[^"\\]|\\.)*)"\s*,\s*(\d+)\)')
bad, tot = [], 0
for p in sorted(glob.glob(os.path.join(root, 'src/**/*.cyr'), recursive=True)):
    rel = os.path.relpath(p, root)
    for i, l in enumerate(open(p).read().split('\n')):
        for m in pat.finditer(l):
            tot += 1
            s = (m.group(1).replace('\\n', '\n').replace('\\t', '\t')
                            .replace('\\"', '"').replace('\\\\', '\\'))
            if len(s) != int(m.group(2)):
                bad.append((rel, i + 1, len(s), int(m.group(2)), s[:50]))

# axis 0 — anti-vacuous: the scanner must actually be finding sites. A regex that matches
# nothing reports nothing wrong and PASSES, which is how a static check rots invisibly.
FLOOR = 90
if tot < FLOOR:
    print(f"  FAIL: only {tot} ERR_MSG sites parsed (floor {FLOOR}) — the scanner is blind, not the source clean")
    sys.exit(1)
print(f"  ok: scanner sees {tot} ERR_MSG sites (floor {FLOOR})")

if bad:
    for rel, ln, act, dec, txt in bad:
        kind = "TRUNCATES" if dec < act else "OVER-READS"
        print(f'  FAIL: {rel}:{ln} declared={dec} actual={act} ({kind}) "{txt}"')
    print(f"FAIL: err-msg-lengths-match — {len(bad)} of {tot} declared lengths wrong")
    sys.exit(1)
print(f"  ok: all {tot} declared lengths equal their string length")
print(f"PASS: err-msg-lengths-match — {tot}/{tot} sites consistent")
PY
