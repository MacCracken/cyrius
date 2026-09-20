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
#   2b. …AND THE STATUS IT NAMES IS THE COMPILER'S REAL ONE (v6.6.6, bite 24 review).
#      `compile()` returns a flat 1 for EVERY failure, so the number printed was that 1
#      and not the child's status at all — and cycc itself exits 1 for every compile
#      error, so row 2 alone can never tell the two apart. This row puts a STUB compiler
#      that exits 42 beside a copy of the CLI and requires the log to say 42. The
#      expected value is obtained a different way from the CLI's report — by RUNNING the
#      stub and reading its `$?` — so a stub that did not build is loud rather than
#      vacuous, and a CLI that goes back to printing a constant is RED.
#   2c. …AND IT IS NOT PRINTED AT ALL WHEN THE COMPILER IS NOT WHAT FAILED (v6.6.6, bite
#      24 review). `cyrius build a.cyr <an existing directory>` fails on bite 24a's
#      rename, having already said so by name; the CLI then printed `FAILED (compiler
#      exit 1)` and "the compiler's diagnostics are above" for a compiler that exited 0
#      and wrote nothing. A verdict that blames the wrong component sends the reader to
#      the wrong place, which is the same defect as row 2 with the sign flipped — so the
#      two rows are asserted in the same run: a fix that silences the attribution
#      everywhere passes 2c and fails 2.
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
# MUTATION LEDGER for rows 2b/2c (measured at v6.6.6; each mutant is a `git archive HEAD
# cbt lib src/version_str.cyr` copy with the working cbt/ overlaid, the CLI rebuilt from
# it, and this gate re-run against a tree whose build/cyrius is that CLI)
#   M1. the whole bite-24-review fix reverted (`fmt_int(r)`, no `_err_count` sample)
#       -> RED: 2b and both 2c attribution rows.
#   M2. `_cc_last_exit` kept, the `_err_count` discriminator neutered
#       -> RED: 2c only. 2b stays green — the number is right, the blame is not.
#   M3. the discriminator kept, `fmt_int(_cc_last_exit)` back to `fmt_int(r)`
#       -> RED: 2b only. The flat 1 reads as a plausible status until it is 42.
#   M4. the over-fix — always print a bare `FAILED`
#       -> RED: row 2 AND 2b. This is why rows 2 and 2c run together: silencing the
#          attribution everywhere satisfies 2c and throws away v6.5.50's whole point.
#   Real tree -> GREEN.
#
# ⚠ NO `set -e`: a FAILING build is the DATA in rows 2/3.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CY="$ROOT/build/cyrius"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: build_log_informative: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$D"' EXIT
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

# 2b — v6.6.6 (bite 24 review): the status it names is the COMPILER'S, not a constant.
# A stub compiler that exits 42 is placed BESIDE a copy of the CLI, so `_wrapper_dir()`'s
# sibling branch resolves it as `cycc` (argv(0)-derived — the copy is what makes this work,
# and it is why the stub cannot simply be dropped into $ROOT/build). The expected 42 is
# read back by RUNNING the stub, not typed, so a stub that failed to build is loud.
mkdir -p "$D/bin" "$D/proj"
cp "$CY" "$D/bin/cyrius" || { echo "FAIL: could not copy the CLI for the stub-compiler row"; FAIL=1; }
printf 'fn main(): i64 { return 42; }\nvar r = main();\n' > "$D/stub.cyr"
"$ROOT/build/cycc" < "$D/stub.cyr" > "$D/bin/cycc" 2>/dev/null
chmod +x "$D/bin/cycc" 2>/dev/null
( ulimit -c 0; "$D/bin/cycc" >/dev/null 2>&1 ); STUB_RC=$?
if [ ! -s "$D/bin/cycc" ] || [ "$STUB_RC" = 0 ]; then
  echo "FAIL: the stub compiler did not build or does not exit non-zero (rc=$STUB_RC) — row 2b would be vacuous"
  FAIL=1
else
  printf 'fn main(): i64 { return 0; }\n' > "$D/proj/m.cyr"
  OUT=$( cd "$D/proj" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/bin/cyrius" build m.cyr out.bin 2>&1 )
  r "$(echo "$OUT" | grep -c "FAILED (compiler exit $STUB_RC)")" 1 \
    "failure names the compiler's REAL exit status ($STUB_RC), not compile()'s flat 1"
fi

# 2c — v6.6.6 (bite 24 review): a failure the CLI raised ITSELF is not blamed on the
# compiler. `build a.cyr <existing directory>` fails on bite 24a's rename check, by name,
# with the compiler having exited 0 and written nothing. Anti-vacuous: the named error
# must be PRESENT, or a build that printed nothing would satisfy both negative rows.
mkdir -p "$D/build/blocking.d"
OUT=$( cd "$D" || exit 1; ulimit -c 0; "$CY" build src/main.cyr build/blocking.d 2>&1 )
( cd "$D" && "$CY" build src/main.cyr build/blocking.d > /dev/null 2>&1 ); RC2=$?
r "$(echo "$OUT" | grep -c 'error: could not rename the temp output onto')" 1 \
  "the CLI-raised rename failure is still named (row 2c is not vacuous)"
r "$(echo "$OUT" | grep -c 'compiler exit')"                 0 \
  "a failure the CLI named itself does not claim a compiler exit status"
r "$(echo "$OUT" | grep -c "the compiler's diagnostics are above")" 0 \
  "…and does not point at compiler diagnostics that do not exist"
if [ "$RC2" = 0 ]; then echo "FAIL: a CLI-raised build failure exited 0"; FAIL=1
else echo "  ok: a CLI-raised build failure still exits non-zero ($RC2)"; fi

# 5 — under -v the header does not run into the [verbose] trace.
OUT=$( cd "$D" && "$CY" build -v src/main.cyr build/v 2>&1 )
r "$(echo "$OUT" | grep -c 'x86_64\] \[verbose\]')"        0 "-v header does not collide with the verbose trace"
r "$(echo "$OUT" | grep -c '^\[verbose\] compiler:')"      1 "-v still emits its trace"

if [ "$FAIL" != 0 ]; then echo "FAIL: cyrius build's log is not informative"; exit 1; fi
echo "PASS build_log_informative (build reports size, failure status, and path provenance)"
