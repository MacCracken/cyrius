#!/bin/sh
# build_log_informative.sh — v6.5.50. `cyrius build` must say what it produced, why it
# failed, and where its paths came from.
#
# WHAT THIS PINS, and why each row is a real defect and not a cosmetic preference:
#   1. SUCCESS REPORTS A SIZE. `OK` alone cannot distinguish a real build from one that
#      produced a do-nothing binary — precisely the failure v6.5.7 had to add a
#      source-existence guard for, where a missing entry file still yielded a valid
#      translation unit of pure stdlib, printed OK and exited 0.
#   2. FAILURE NAMES THE EXIT STATUS. The old output was a bare `FAIL`: not which stage
#      failed, not the compiler's status, not where its diagnostics went.
#   3. FAILURE STILL EXITS NON-ZERO. A log change must not swallow the status — that would
#      turn a broken build green in every CI that checks `$?`.
#   4. MANIFEST PROVENANCE IS DECLARED. v6.5.49 let `src`/`output` be omitted and taken from
#      [build] in ./cyrius.cyml, so the log can name files the user never typed. Without the
#      note, a wrong path in a stale manifest reads as a compiler bug.
#   5. -v DOES NOT RUN THE HEADER INTO THE TRACE. The header is intentionally unterminated so
#      the result lands on the same line, which collided with compile()'s [verbose] lines.
#
# ⚠ ROW 4 IS ASSERTED IN ALL THREE LADDER POSITIONS, not just the interesting one. The
# provenance flag is set by three separate assignments in the argument ladder (both-from-
# manifest, src-given, both-given) and an edit that fixes one can silently invert another —
# a build with BOTH paths explicit claiming "(from cyrius.cyml)" is exactly as wrong as the
# omission this row exists to catch.
#
# ⚠ NO `set -e`: a FAILING build is the DATA in rows 2/3.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CY="$ROOT/build/cyrius"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
FAIL=0
r() { if [ "$1" != "$2" ]; then echo "FAIL: $3 — expected '$2', got '$1'"; FAIL=1; else echo "  ok: $3"; fi; }

mkdir -p "$D/src" "$D/build"
printf '[package]\nname = "logdemo"\nversion = "0.1.0"\n\n[build]\nsrc = "src/main.cyr"\noutput = "build/logdemo"\n' > "$D/cyrius.cyml"
printf 'fn main(): i64 { return 7; }\nvar r = main();\n' > "$D/src/main.cyr"
printf 'fn main(): i64 { return zzz_undefined_thing(); }\nvar r = main();\n' > "$D/src/bad.cyr"

# 1 + 4a — no args: both paths from the manifest, and a size is reported.
OUT=$( cd "$D" && "$CY" build 2>&1 )
r "$(echo "$OUT" | grep -c 'OK ([0-9]* bytes)')"           1 "success reports the artifact size"
r "$(echo "$OUT" | grep -c '(src+output from cyrius.cyml)')" 1 "no-arg build declares BOTH paths came from the manifest"

# 4b — src given, output still from the manifest.
OUT=$( cd "$D" && "$CY" build src/main.cyr 2>&1 )
r "$(echo "$OUT" | grep -c '(output from cyrius.cyml)')"   1 "src-only build declares the OUTPUT came from the manifest"

# 4c — both explicit: it must claim NOTHING about the manifest.
OUT=$( cd "$D" && "$CY" build src/main.cyr build/explicit 2>&1 )
r "$(echo "$OUT" | grep -c 'from cyrius.cyml')"            0 "fully explicit build claims no manifest provenance"

# 2 + 3 — a failing build names the exit status AND still exits non-zero.
OUT=$( cd "$D" && "$CY" build src/bad.cyr build/bad 2>&1 )
( cd "$D" && "$CY" build src/bad.cyr build/bad > /dev/null 2>&1 )
RC=$?
r "$(echo "$OUT" | grep -c 'FAILED (compiler exit [0-9]*)')" 1 "failure names the compiler exit status"
r "$(echo "$OUT" | grep -c '^FAIL$')"                        0 "failure is no longer a bare 'FAIL'"
if [ "$RC" = 0 ]; then echo "FAIL: a failing build exited 0 — the log change swallowed the status"; FAIL=1
else echo "  ok: failing build still exits non-zero ($RC)"; fi

# 5 — under -v the header does not run into the [verbose] trace.
OUT=$( cd "$D" && "$CY" build -v src/main.cyr build/v 2>&1 )
r "$(echo "$OUT" | grep -c 'x86_64\] \[verbose\]')"        0 "-v header does not collide with the verbose trace"
r "$(echo "$OUT" | grep -c '^\[verbose\] compiler:')"      1 "-v still emits its trace"

if [ "$FAIL" != 0 ]; then echo "FAIL: cyrius build's log is not informative"; exit 1; fi
echo "PASS build_log_informative (build reports size, failure status, and path provenance)"
