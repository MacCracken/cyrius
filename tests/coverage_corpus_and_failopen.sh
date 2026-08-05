#!/bin/sh
# Gate: `cyrius coverage` measures the WHOLE test corpus, counts every public spelling,
# and never reports success for a measurement it did not make (v6.5.8).
#
# FOUR DEFECTS, ALL OF WHICH REPORTED A NUMBER AND EXITED 0:
#
#  1. FIXED 1 MiB CORPUS. Every tests/**/*.tcyr was concatenated into a fixed 1,048,576-byte
#     buffer. `file_read_all` returns exactly `maxlen` on truncation and 0 once the space
#     runs out, and `if (n > 0)` made truncation, a whole-file drop and a failed open
#     indistinguishable — all silent. Symbols referenced only in the discarded tail read as
#     unreferenced. ⭐ The failure is ANTI-CORRELATED with the signal: coverage degrades as
#     the suite GROWS, so it punishes the projects testing most and reads as "someone
#     deleted a test". It was mis-measuring THIS repo by 33 functions (179 -> 212).
#
#  2. OFF-BY-ONE at the corpus end (`ci < corpus_len - fname_len` should be `<=`), so a
#     symbol occurring at the very last byte was never found. Normally masked by trailing
#     newlines — but defect 1 made the corpus end at an arbitrary cut point, so the two
#     compounded.
#
#  3. `pub fn` WAS INVISIBLE. The scanner matched only a bare `fn ` at line start, so the
#     explicit-public spelling that shipped with file-scoped public/private at v6.5.0 was
#     not counted at all: a project that adopted `pub` got "0/0 public functions" from the
#     tool whose entire job is counting public functions. The native-header generator in
#     the same file already handled both spellings, so the two scanners disagreed.
#
#  4. FAIL-OPEN. "no public functions found" was a `note:` followed by exit 0, so
#     `cyrius coverage --min 80` in a directory with no sources — a mistyped path, a CI job
#     with the wrong working directory — reported a percentage computed from an empty set
#     and passed. Same green-placebo shape as `capacity` at v6.4.73.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }

mkdir -p "$D/p/src/sub" "$D/p/tests"
cd "$D/p" || exit 2
printf '[package]\nname = "cov"\nversion = "0.1.0"\n' > cyrius.cyml

# ── AXIS 1: a corpus LARGER than the old fixed 1 MiB. ⚠ ORDER-INDEPENDENT BY
# CONSTRUCTION: `dir_walk` gives no ordering guarantee, so an earlier version of this axis
# — one unique symbol in one "last" file — passed against the truncating build simply
# because that file happened to be read early. Mutation-verified: disabling grow-and-retry
# left it green. Instead give EVERY pad file its own unique symbol. With ~1.3 MB of corpus
# and a 1 MiB cap, roughly a quarter of the files fall in the discarded tail whatever the
# order, so some symbol must go missing.
echo "axis 1 — a >1 MiB test corpus is searched in full (order-independent):"
: > src/sub/mod.cyr
i=0
while [ "$i" -lt 40 ]; do
    printf 'fn sym_%02d(): i64 { return %d; }\n' "$i" "$i" >> src/sub/mod.cyr
    # ~32 KB of filler per file, then this file's own symbol reference.
    awk 'BEGIN{for(j=0;j<700;j++) print "# filler line to pad the corpus past one mebibyte ................"}' \
        > "tests/pad_$i.tcyr"
    printf 'var r%02d = sym_%02d();\n' "$i" "$i" >> "tests/pad_$i.tcyr"
    i=$((i + 1))
done
corpus_bytes=$(cat tests/*.tcyr | wc -c)
check "corpus exceeds the old 1 MiB cap" 1 "$([ "$corpus_bytes" -gt 1048576 ] && echo 1 || echo 0)"
"$CY" coverage src/sub > "$D/o1" 2>&1
rc=$?
check "exit 0 on a real measurement" 0 "$rc"
check "ALL 40 symbols found, none lost to truncation" 1 \
    "$(grep -c 'Functions referenced: 40/40' "$D/o1" || true)"

# ── AXIS 2: the very last byte of the corpus. ⚠ Runs in its OWN project with exactly ONE
# test file, so the corpus provably ends at that symbol — with padding present the file
# order decides where the corpus ends and the `<` vs `<=` bound is never exercised
# (mutation-verified: the padded form stayed green against the off-by-one).
echo "axis 2 — a symbol at the very last byte of the corpus is found:"
mkdir -p "$D/tail/src" "$D/tail/tests" && cd "$D/tail" || exit 2
printf '[package]\nname = "t"\nversion = "0.1.0"\n' > cyrius.cyml
printf 'fn omega_tail(): i64 { return 1; }\n' > src/mod.cyr
printf 'omega_tail' > tests/only.tcyr        # no trailing newline: the symbol ends the corpus
"$CY" coverage src > "$D/o2" 2>&1
check "symbol flush against the corpus end is found" 1 "$(grep -c 'Functions referenced: 1/1' "$D/o2" || true)"
cd "$D/p" || exit 2

# ── AXIS 3: `pub fn` counts. This is the v6.5.0 explicit-public spelling.
echo "axis 3 — pub fn is counted, mixed with bare fn:"
rm -f tests/pad_*.tcyr
printf 'pub fn pub_one(): i64 { return 1; }\nfn bare_two(): i64 { return 2; }\n' > src/sub/mod.cyr
printf 'var a = pub_one();\n' > tests/only.tcyr
"$CY" coverage src/sub > "$D/o3" 2>&1
check "both spellings counted, one referenced" 1 "$(grep -c 'Functions referenced: 1/2' "$D/o3" || true)"

# ── AXIS 4: the subfolder callout is HONOURED, not ignored. It used to be dropped and the
# scan ran against ./ regardless — an argument accepted and not acted on is worse than one
# rejected, because the output looks like an answer to the question asked.
echo "axis 4 — a subfolder callout scans that directory:"
printf 'fn top_only(): i64 { return 3; }\n' > src/top.cyr
"$CY" coverage src/sub > "$D/o4a" 2>&1
"$CY" coverage src     > "$D/o4b" 2>&1
check "src/sub sees 2 fns"        1 "$(grep -c 'Functions referenced: 1/2' "$D/o4a" || true)"
check "src sees 3 (callout differs from default)" 1 "$(grep -c 'Functions referenced: 1/3' "$D/o4b" || true)"

# ── AXIS 5: fail-open. Measuring nothing is not passing, with or without --min.
echo "axis 5 — an empty measurement FAILS instead of reporting 100%:"
mkdir -p "$D/empty" && cd "$D/empty" || exit 2
printf '[package]\nname = "e"\nversion = "0.1.0"\n' > cyrius.cyml
"$CY" coverage > "$D/o5" 2>&1; rc5=$?
check "empty project exits non-zero" 1 "$([ "$rc5" -ne 0 ] && echo 1 || echo 0)"
check "and says so as an error:" 1 "$(grep -c 'error: no public functions found' "$D/o5" || true)"
"$CY" coverage --min 80 > "$D/o5b" 2>&1; rc5b=$?
check "--min on an empty project also fails" 1 "$([ "$rc5b" -ne 0 ] && echo 1 || echo 0)"

# ── AXIS 6: argument hygiene — an unknown option must not be silently ignored.
echo "axis 6 — bad arguments are rejected, not absorbed:"
cd "$D/p" || exit 2
"$CY" coverage --bogus > "$D/o6" 2>&1; rc6=$?
check "unknown option exits non-zero" 1 "$([ "$rc6" -ne 0 ] && echo 1 || echo 0)"
check "and names it" 1 "$(grep -c 'unknown option' "$D/o6" || true)"
"$CY" coverage no_such_dir > "$D/o7" 2>&1; rc7=$?
check "nonexistent callout exits non-zero" 1 "$([ "$rc7" -ne 0 ] && echo 1 || echo 0)"
"$CY" coverage --min > "$D/o8" 2>&1; rc8=$?
check "--min without a value exits non-zero" 1 "$([ "$rc8" -ne 0 ] && echo 1 || echo 0)"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: coverage-corpus-and-failopen — whole corpus searched, pub fn counted, empty measurement fails"
    exit 0
fi
echo "FAIL: coverage-corpus-and-failopen — $fails assertion(s) failed"
exit 1
