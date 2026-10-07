#!/bin/sh
# Gate: `cyrius coverage` measures the WHOLE test corpus, counts every public spelling,
# and never reports success for a measurement it did not make (v6.5.8; 6.6.8).
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
#     tool whose entire job is counting public functions. (This header used to add that
#     "the native-header generator already handled both spellings". It never did — it
#     matched `pub fn ` alone — and that false claim is how the two scanners' drift
#     survived. 6.6.8 gave them one shared rule, and `cyrius header` its own gate.)
#
#  4. FAIL-OPEN. "no public functions found" was a `note:` followed by exit 0, so
#     `cyrius coverage --min 80` in a directory with no sources — a mistyped path, a CI job
#     with the wrong working directory — reported a percentage computed from an empty set
#     and passed. Same green-placebo shape as `capacity` at v6.4.73.
#
# 6.6.8 — FIVE MORE, ALL OF WHICH READ HIGHER THAN THE TRUTH (axes 7-13; 14 pins no. 10):
#
#  5. SUBSTRING + COMMENT REFERENCES (issue 2026-09-23-samay-…). A raw `memeq` at every
#     corpus offset counted `check_due` as referenced by `check_due_at(` and `str_lt` by a
#     comment naming it; `--min 100` passed at 3/3 with one fn referenced. The match is now
#     whole-identifier over a corpus whose comments, strings and char literals are BLANKED
#     in place (length-preserving, so axis 1's comment-padded corpus still exercises the
#     grow path).
#  6. SPELLINGS. `public fn` (the same token as `pub`), `fn<TAB>`, `pub  fn`, an indented
#     fn and an attributed `#inline fn` were all invisible.
#  7. THE FILE-SCOPE `private` RULE. In a `private` file only `pub`/`public` fns are
#     exported; the tool counted exactly the other set — hisab's whole `public fn` API was
#     invisible and it read 1/1 = 100%.
#  8. A FIXED 256 KiB READ PER SOURCE. Every fn past the cut was never counted (bayan's
#     399,907-byte pdf.cyr: 114 of 152 fns).
#  9. A lib/ OR dist/ AT ANY DEPTH WAS PRUNED BY NAME. src/lib/ projects (nein, hoosh,
#     kriya, kybernet) had their whole tree dropped; nein read 1/1 and passed --min 80.
# 10. (The first cut of 6.6.8's spelling fix, caught in its review, never released:) a fn
#     INSIDE an `impl S { … }` block was read as a top-level fn by its bare name — a
#     false miss for `S_m`, a false hit for a method called `get`. Only brace depth 0 is
#     public surface, as cyrius_api_surface counts it (axis 14). 6 also gained
#     `pub #inline fn`, `#deprecated ("x") fn` and `async fn` (axis 9).
# Every unreferenced fn is now NAMED under -v and whenever --min fails.
#
# 6.6.10 (bite 15) — THREE MORE, AND THE SPEED (axes 15-19):
# 11. AN UNREADABLE .tcyr WAS SKIPPED IN SILENCE (`if (n > 0)`), so the fns only it
#     referenced read as misses: 50 % → 25 %, no diagnostic. It is an error by name.
# 12. AN UNREADABLE DIRECTORY VANISHED. lib/fs.cyr's dir_walk folded an open/getdents error
#     into "empty", and is_dir answered 0 for a directory it could not read. An unreadable
#     tests/ subdir LOWERED the figure; an unreadable src/ subdir left the DENOMINATOR and
#     RAISED it — 50 % → 100 %, `--min 60` passed (fail-OPEN). Both exit 1, naming the dir.
# 13. THE IDENTIFIER SET must not saturate: distlib's `_dl_ids_*` answered PRESENT for every
#     name once half full (safe for distlib, fail-open for coverage). The shared `_src_ids_*`
#     grows and confirms every hit byte for byte (axis 18: thousands of distinct identifiers
#     and one fn that none of them is).
# 14. O(corpus × fns): one memeq scan of the whole corpus per public fn — 78 s on this repo's
#     --full (now ~0.4 s, byte-identical report; agnosai 8.5 s → 0.1 s). Axis 19 is the
#     timing row.
# The chmod rows (15-17) SKIP by name under uid 0, which reads a mode-000 file or directory.
#
# MUTATION LEDGER (6.6.8; build/cyrius rebuilt from each mutant, gate re-run):
#   M1 _src_refs_ident's boundary checks removed (a raw substring)       → axes 7, 13 FAIL
#      (6.6.10: that fn is gone; the rule is now the tokeniser's maximal identifier run)
#   M2 _src_blank_noncode made a no-op                                  → axes 7, 8, 9, 13 FAIL
#   M3 _src_blank_noncode's char-literal arm removed                    → axis 8 FAIL
#   M4 _src_decl_at back to column-0 `fn `/`pub fn ` only                → axes 9, 10 FAIL
#   M5 _src_file_private forced to 0                                    → axis 10 FAIL
#   M6 per-source read truncated at 256 KiB again                       → axis 11 FAIL
#   M7 the by-name lib/ + dist/ prune restored for a named root         → axis 12 FAIL
#   M8 the miss list never printed                                      → axes 7-13 FAIL
#   M9 the '.' fallback's top-level lib/ + dist/ skip removed           → axis 12 FAIL
#   M10 _src_brace_delta made to count nothing (impl methods top-level) → axis 14 FAIL
#   M11 no whitespace skipped between an attribute and its `(`           → axis 9 FAIL
#   M12 the optional `async` before `fn` not accepted                   → axis 9 FAIL
#   M13 `pub` / `public` must follow every attribute (no interleave)     → axis 9 FAIL
#   M14 `private;` followed by an item on the same line rejected        → axis 10c FAIL
#   M15 _src_str_end ignores `\` escapes                                → axis 8b FAIL
#   M16 the `#define`/`#if`/`#elif` code-line arm removed from the blanker → axis 8b FAIL
#   M17 (6.6.10) the unreadable-.tcyr arm removed (n < 0 folded into empty) → axis 15 FAIL
#   M18 (6.6.10) coverage back on unchecked dir_walk                     → axes 16, 17 FAIL
#   M19 (6.6.10) _src_ids_add stops growing and answers PRESENT when full → axis 18 FAIL
#   M20 (6.6.10) the per-fn corpus scan restored (the 6.6.9 CLI: 38 s)    → axis 19 FAIL
#   M21 (6.6.11) the entry-point exclusion removed from cmd_coverage      → axis 20 FAIL
#   real tree → every axis green
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: coverage_corpus_and_failopen: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

# ── AXIS 7: the filed repro (issue 2026-09-23-samay-coverage-counts-substrings-and-
# comments-as-references), VERBATIM. Expected 1/3, gate FAILED, exit 1, misses named.
echo "axis 7 — the samay repro: a longer identifier and a comment are not references:"
mkdir -p "$D/samay/src" "$D/samay/tests" && cd "$D/samay" || exit 2
cat > src/sched.cyr <<'EOF'
fn check_due(x) { return x; }
fn check_due_at(x) { return x; }
fn str_lt(a, b) { return 0; }
EOF
cat > tests/sched.tcyr <<'EOF'
# str_lt() is only ever named in this comment.
fn main() { return check_due_at(1); }
EOF
"$CY" coverage --min 100 > "$D/o9" 2>&1; rc9=$?
check "exit 1 (the gate FAILS)" 1 "$rc9"
check "1/3 referenced" 1 "$(grep -c 'Functions referenced: 1/3 (33%)' "$D/o9" || true)"
check "gate FAILED is reported" 1 "$(grep -c 'coverage gate FAILED: 33% < --min 100%' "$D/o9" || true)"
check "the miss list names check_due" 1 "$(grep -cx '  src/sched.cyr: check_due' "$D/o9" || true)"
check "the miss list names str_lt" 1 "$(grep -cx '  src/sched.cyr: str_lt' "$D/o9" || true)"
check "the miss list does NOT name check_due_at" 0 "$(grep -c 'check_due_at' "$D/o9" || true)"

# ── AXIS 8: strings and char literals. A string-only mention is not a reference; a `'"'`
# or `'#'` char literal must NOT be read as opening a string / comment and hide the real
# call after it on the same line.
echo "axis 8 — strings are not references; char literals hide nothing:"
mkdir -p "$D/str/src" "$D/str/tests" && cd "$D/str" || exit 2
printf 'fn spaced(): i64 { return 1; }\nfn after_dq(): i64 { return 2; }\nfn after_hash(): i64 { return 3; }\nfn in_ml(): i64 { return 4; }\n' > src/m.cyr
printf 'var s = "spaced";\nvar q = %s; var a = after_dq();\nvar h = %s; var b = after_hash();\nvar m = "one\nin_ml\ntwo";\n' "'\"'" "'#'" > tests/t.tcyr
"$CY" -v coverage > "$D/o10" 2>&1
check "2/4: only the two calls after the char literals count" 1 "$(grep -c 'Functions referenced: 2/4' "$D/o10" || true)"
check "a string-only name is a miss" 1 "$(grep -cx '  src/m.cyr: spaced' "$D/o10" || true)"
check "a name inside a multi-line string is a miss" 1 "$(grep -cx '  src/m.cyr: in_ml' "$D/o10" || true)"
check "the call after the '\"' char literal is found" 0 "$(grep -c ': after_dq$' "$D/o10" || true)"
check "the call after the '#' char literal is found" 0 "$(grep -c ': after_hash$' "$D/o10" || true)"
# 8b: a `\"` inside a string is an ESCAPE, not its end — so a name after it is still
# string, and a real call after the string's true end is still code. And a `#define` line
# is CODE (its body is the macro), not a comment: a fn referenced only through a macro is
# referenced.
printf 'fn esc_hidden(): i64 { return 1; }\nfn esc_after(): i64 { return 2; }\nfn via_macro(): i64 { return 3; }\n' > src/e.cyr
printf 'var s = "a \\" esc_hidden("; var c = esc_after();\n#define M via_macro()\n' > tests/e.tcyr
"$CY" -v coverage > "$D/o10b" 2>&1
check "8b: the escape fixture is what the axis means" 1 "$(grep -c 'a \\" esc_hidden' tests/e.tcyr || true)"
check "8b: a name after an escaped quote is still string (a miss)" 1 "$(grep -cx '  src/e.cyr: esc_hidden' "$D/o10b" || true)"
check "8b: the call after the string's real end is found" 0 "$(grep -c ': esc_after$' "$D/o10b" || true)"
check "8b: a #define body is code — the macro's fn is referenced" 0 "$(grep -c ': via_macro$' "$D/o10b" || true)"

# ── AXIS 9: every declaration spelling the compiler accepts is counted; `_` names, and a
# "declaration" inside a comment or a string, are not.
echo "axis 9 — every public spelling is counted:"
mkdir -p "$D/sp/src" "$D/sp/tests" && cd "$D/sp" || exit 2
printf 'public fn s_public(): i64 { return 1; }\nfn\ts_tab(): i64 { return 1; }\npub  fn s_twosp(): i64 { return 1; }\n    fn s_indent(): i64 { return 1; }\n#inline fn s_attr(): i64 { return 1; }\n#deprecated("use (x)") pub fn s_dep(): i64 { return 1; }\n#deprecated ("old") fn s_depsp(): i64 { return 1; }\nasync fn s_async(x) { return x; }\npub async fn s_pasync(x) { return x; }\npub #inline fn s_pubattr(): i64 { return 1; }\npublic #inline fn s_publicattr(): i64 { return 1; }\nfn _s_private(): i64 { return 1; }\n# fn s_comment(): i64 { return 1; }\nvar t = "\nfn s_string(): i64 {\n";\n' > src/m.cyr
printf 'var z = 0;\n' > tests/t.tcyr
"$CY" -v coverage > "$D/o11" 2>&1
check "11 declarations counted (0/11)" 1 "$(grep -c 'Functions referenced: 0/11' "$D/o11" || true)"
for n in s_public s_tab s_twosp s_indent s_attr s_dep s_depsp s_async s_pasync s_pubattr s_publicattr; do
    check "$n is in the denominator" 1 "$(grep -cx "  src/m.cyr: $n" "$D/o11" || true)"
done
check "no comment / string / _ name counted" 0 "$(grep -cE 's_comment|s_string|_s_private' "$D/o11" || true)"

# ── AXIS 10: the file-scope `private` rule. In a `private` file an untested bare helper
# is NOT public surface — even one written ABOVE the marker, which applies to the whole
# file — and an untested `public fn` IS. (10a is 100% only if the helper is excluded AND
# `public fn` is counted; the pre-6.6.8 tool read it as 1/2.)
echo "axis 10 — in a private file only pub/public fns count:"
mkdir -p "$D/pv/src" "$D/pv/tests" && cd "$D/pv" || exit 2
printf 'fn helper(): i64 { return 7; }\nprivate\npublic fn exported(): i64 { return helper(); }\npub fn exported2(): i64 { return 1; }\n' > src/m.cyr
printf 'var e = exported() + exported2();\n' > tests/t.tcyr
"$CY" coverage --min 100 > "$D/o12" 2>&1; rc12=$?
check "10a: 2/2 — the untested bare helper is not public surface" 1 "$(grep -c 'Functions referenced: 2/2' "$D/o12" || true)"
check "10a: --min 100 passes" 0 "$rc12"
printf 'public fn exported3(): i64 { return 3; }\n' >> src/m.cyr
"$CY" coverage --min 100 > "$D/o12b" 2>&1; rc12b=$?
check "10b: an untested public fn is counted (2/3)" 1 "$(grep -c 'Functions referenced: 2/3' "$D/o12b" || true)"
check "10b: and fails --min 100" 1 "$rc12b"
check "10b: and is named" 1 "$(grep -cx '  src/m.cyr: exported3' "$D/o12b" || true)"
check "10b: the helper is not named" 0 "$(grep -c ': helper$' "$D/o12b" || true)"

# 10c: `private;` closes the file marker and an item may follow ON THE SAME LINE. That
# line both makes the file private AND declares its item: `private; pub fn` is exported,
# `private; fn` is file-private.
mkdir -p "$D/pvs/src" "$D/pvs/tests" && cd "$D/pvs" || exit 2
printf 'private; pub fn pvs_x(): i64 { return 1; }\nprivate; fn pvs_y(): i64 { return 2; }\n' > src/m.cyr
printf 'var z = 0;\n' > tests/t.tcyr
"$CY" -v coverage > "$D/o12c" 2>&1
check "10c: \`private; pub fn\` is counted, \`private; fn\` is not (0/1)" 1 "$(grep -c 'Functions referenced: 0/1' "$D/o12c" || true)"
check "10c: pvs_x is named" 1 "$(grep -cx '  src/m.cyr: pvs_x' "$D/o12c" || true)"
check "10c: pvs_y is not" 0 "$(grep -c 'pvs_y' "$D/o12c" || true)"

# ── AXIS 11: a source larger than the old fixed 256 KiB read, with an UNTESTED fn after
# the cut. The old build read 1/1 and passed --min 100.
echo "axis 11 — a >256 KiB source is read whole:"
mkdir -p "$D/big/src" "$D/big/tests" && cd "$D/big" || exit 2
{ echo 'fn head_fn(): i64 { return 1; }'
  awk 'BEGIN{for(j=0;j<4500;j++) print "# filler line to push the next fn past the old 256 KiB source cap ....."}'
  echo 'fn tail_fn(): i64 { return 2; }'; } > src/big.cyr
check "source exceeds the old 256 KiB cap" 1 "$([ "$(wc -c < src/big.cyr)" -gt 262144 ] && echo 1 || echo 0)"
printf 'var h = head_fn();\n' > tests/t.tcyr
"$CY" coverage --min 100 > "$D/o13" 2>&1; rc13=$?
check "the tail fn is counted (1/2)" 1 "$(grep -c 'Functions referenced: 1/2' "$D/o13" || true)"
check "--min 100 fails on it" 1 "$rc13"
check "and names it" 1 "$(grep -cx '  src/big.cyr: tail_fn' "$D/o13" || true)"

# ── AXIS 12: a lib/ or dist/ INSIDE the measured tree is the project's code. Only the '.'
# fallback skips its own top-level ./lib and ./dist.
echo "axis 12 — no nested lib/ prune; the '.' fallback skips only top-level lib/ dist/:"
mkdir -p "$D/nl/src/lib" "$D/nl/src/dist" "$D/nl/tests" && cd "$D/nl" || exit 2
printf 'fn top_fn(): i64 { return 1; }\n' > src/main.cyr
printf 'fn nested_lib(): i64 { return 1; }\n' > src/lib/x.cyr
printf 'fn nested_dist(): i64 { return 1; }\n' > src/dist/y.cyr
printf 'var t = top_fn();\n' > tests/t.tcyr
"$CY" coverage --min 80 > "$D/o14" 2>&1; rc14=$?
check "src/lib and src/dist are measured (1/3)" 1 "$(grep -c 'Functions referenced: 1/3' "$D/o14" || true)"
check "--min 80 fails instead of reading a vacuous 1/1" 1 "$rc14"
mkdir -p "$D/flat/lib" "$D/flat/dist" "$D/flat/sub/lib" "$D/flat/tests" && cd "$D/flat" || exit 2
printf 'fn flat_top(): i64 { return 1; }\n' > a.cyr
printf 'fn vendored(): i64 { return 1; }\n' > lib/v.cyr
printf 'fn generated(): i64 { return 1; }\n' > dist/g.cyr
printf 'fn deep_lib(): i64 { return 1; }\n' > sub/lib/d.cyr
printf 'var t = flat_top();\n' > tests/t.tcyr
"$CY" -v coverage > "$D/o15" 2>&1
check "'.': top-level lib/ + dist/ skipped, sub/lib measured (1/2)" 1 "$(grep -c 'Functions referenced: 1/2' "$D/o15" || true)"
check "'.': sub/lib's fn is named" 1 "$(grep -c ': deep_lib$' "$D/o15" || true)"

# ── AXIS 13: the miss list appears under -v, and stays out of a passing non-verbose run.
echo "axis 13 — misses are listed under -v, not on a quiet pass:"
cd "$D/samay" || exit 2
"$CY" coverage > "$D/o16" 2>&1
"$CY" -v coverage > "$D/o17" 2>&1
check "no list without -v when no gate failed" 0 "$(grep -c 'Unreferenced' "$D/o16" || true)"
check "-v lists both misses" 1 "$(grep -c -- '-- Unreferenced (2) --' "$D/o17" || true)"

# ── AXIS 14: only TOP-LEVEL fns are public surface. A fn inside an `impl S { … }`
# block is a METHOD, emitted as `S_m` and called as `S_m(x)` — it used to be counted by its
# bare name, so `norm` was a false miss when its test called `Pt_norm(q)`, and a method
# named `get` was "covered" by any unrelated `get`. Depth must also come BACK to 0 after
# the block, or every later fn would vanish.
echo "axis 14 — impl methods are not top-level fns; depth recovers after the block:"
mkdir -p "$D/im/src" "$D/im/tests" && cd "$D/im" || exit 2
printf 'fn top_m(): i64 { return 1; }\nimpl Show for Pt {\n    fn norm(self) { return 1; }\n    fn get(self) { return 2; }\n}\nfn after_impl(): i64 { return 3; }\n' > src/p.cyr
printf 'var a = top_m(); var b = Pt_norm(q);\n' > tests/t.tcyr
"$CY" -v coverage > "$D/o18" 2>&1
check "14: 1/2 — the two methods are not in the denominator" 1 "$(grep -c 'Functions referenced: 1/2' "$D/o18" || true)"
check "14: the fn after the impl block is still counted and named" 1 "$(grep -cx '  src/p.cyr: after_impl' "$D/o18" || true)"
check "14: no method is named as a miss" 0 "$(grep -cE ': (norm|get)$' "$D/o18" || true)"

# ── AXES 15-17 (6.6.10): an unreadable test, test directory or source directory FAILS,
# by name. The fixture reads 50 % when readable, so a dropped test LOWERS it and a dropped
# source directory RAISES it (the fail-open direction) — the verdict must be an error.
ROOTSKIP=0
if [ "$(id -u)" = "0" ]; then
    echo "  SKIP: axes 15-17 — running as root (uid 0 reads a mode-000 file or directory)"
    ROOTSKIP=1
else
    echo "axes 15-17 — an unreadable test / tests dir / src dir is an ERROR, not a percentage:"
    mkdir -p "$D/ur/src/sub" "$D/ur/tests/sub" && cd "$D/ur" || exit 2
    printf '[package]\nname = "ur"\nversion = "0.1.0"\n' > cyrius.cyml
    printf 'fn alpha(): i64 { return 1; }\nfn beta(): i64 { return 2; }\n' > src/m.cyr
    printf 'fn gamma(): i64 { return 3; }\nfn delta(): i64 { return 4; }\n' > src/sub/u.cyr
    printf 'var a = alpha();\n' > tests/a.tcyr
    printf 'var b = beta();\n' > tests/sub/b.tcyr
    "$CY" coverage --min 40 > "$D/o19" 2>&1; rc19=$?
    check "15 premise: the readable tree reads 2/4 (50%) and passes --min 40" "1 0" "$(grep -c 'Functions referenced: 2/4 (50%)' "$D/o19") $rc19"
    chmod 000 tests/sub/b.tcyr
    "$CY" coverage --min 40 > "$D/o20" 2>&1; rc20=$?
    chmod 644 tests/sub/b.tcyr
    check "15 an unreadable .tcyr: exit 1" 1 "$rc20"
    check "15 …and it is named" 1 "$(grep -c 'coverage: cannot read test: tests/sub/b.tcyr' "$D/o20" || true)"
    check "15 …and no percentage is reported as the answer" 0 "$(grep -c 'Functions referenced' "$D/o20" || true)"
    chmod 000 tests/sub
    "$CY" coverage --min 40 > "$D/o21" 2>&1; rc21=$?
    chmod 755 tests/sub
    check "16 an unreadable tests/ SUBDIRECTORY: exit 1" 1 "$rc21"
    check "16 …and it is named" 1 "$(grep -c 'cannot list directory: tests/sub' "$D/o21" || true)"
    chmod 000 src/sub
    "$CY" coverage --min 60 > "$D/o22" 2>&1; rc22=$?
    chmod 755 src/sub
    check "17 an unreadable src/ SUBDIRECTORY (was 100%, passing --min 60): exit 1" 1 "$rc22"
    check "17 …and it is named" 1 "$(grep -c 'cannot list directory: src/sub' "$D/o22" || true)"
    check "17 …and never 'gate OK'" 0 "$(grep -c 'gate OK' "$D/o22" || true)"
fi

# ── AXIS 18 (6.6.10): the identifier set grows — it never saturates into "present".
# Every 3-letter identifier (17,576 of them, 4 bytes each with the space) and one public fn
# none of them is. The set is sized from the corpus length (a slot per 4 bytes, rounded up to
# a power of 2), so only a corpus this dense in DISTINCT short tokens drives it past half
# full — exactly where distlib's old set started answering PRESENT for every name.
echo "axis 18 — 17,576 distinct short test identifiers do not make an unreferenced fn 'referenced':"
mkdir -p "$D/sat/src" "$D/sat/tests" && cd "$D/sat" || exit 2
printf '[package]\nname = "sat"\nversion = "0.1.0"\n' > cyrius.cyml
printf 'fn sat_used(): i64 { return 1; }\nfn sat_never(): i64 { return 2; }\n' > src/m.cyr
awk 'BEGIN { a = "abcdefghijklmnopqrstuvwxyz"; print "var u = sat_used();"
    for (i = 1; i <= 26; i++) for (j = 1; j <= 26; j++) { for (k = 1; k <= 26; k++) printf "%s%s%s ", substr(a, i, 1), substr(a, j, 1), substr(a, k, 1); print "" } }' > tests/t.tcyr
"$CY" -v coverage > "$D/o23" 2>&1
check "18 1/2 — sat_never is still a miss" 1 "$(grep -c 'Functions referenced: 1/2' "$D/o23" || true)"
check "18 …and named" 1 "$(grep -cx '  src/m.cyr: sat_never' "$D/o23" || true)"

# ── AXIS 19 (6.6.10): ONE pass over the corpus. 3,000 public fns against a ~3 MB test corpus
# is 9 G byte-compares for the per-fn scan (minutes); the set answers it in well under a
# second. The bound is generous (a loaded box) and still far below the quadratic cost.
echo "axis 19 — coverage is linear in corpus + fns (timing row):"
mkdir -p "$D/fast/src" "$D/fast/tests" && cd "$D/fast" || exit 2
printf '[package]\nname = "fast"\nversion = "0.1.0"\n' > cyrius.cyml
awk 'BEGIN { for (i = 0; i < 3000; i++) printf "fn fast_fn_%d(): i64 { return %d; }\n", i, i }' > src/m.cyr
awk 'BEGIN { for (i = 0; i < 60000; i++) printf "var filler_line_%d = fast_fn_%d() + %d; # padding the corpus\n", i, i % 1500, i }' > tests/t.tcyr
check "19 premise: the corpus is over 2.5 MB" 1 "$([ "$(wc -c < tests/t.tcyr)" -gt 2621440 ] && echo 1 || echo 0)"
T0=$(date +%s)
"$CY" coverage > "$D/o24" 2>&1
EL=$(( $(date +%s) - T0 ))
check "19 the report is right (1500/3000)" 1 "$(grep -c 'Functions referenced: 1500/3000 (50%)' "$D/o24" || true)"
check "19 …in under 10 s (took ${EL} s)" 1 "$([ "$EL" -lt 10 ] && echo 1 || echo 0)"

# ── AXIS 20 (6.6.11, S7): the ENTRY POINT is not in the denominator. A depth-0 `main` is
# invoked by its own file's `syscall(60, main())`, never named by a test, so it could never
# count: ganita read 139/141 and bayan 501/503 with `main` the only misses, and both held
# their CI floors below 100. `cyrius header` has skipped it since 6.6.8 (the same helper,
# `_src_is_entry_fn`). ⚠ The loop advances only at its bottom, so a `continue` there would
# spin forever — the timeout is part of the axis.
echo "axis 20 — coverage does not count the entry point 'main':"
mkdir -p "$D/ent/src" "$D/ent/tests" && cd "$D/ent" || exit 2
printf '[package]\nname = "ent"\nversion = "0.1.0"\n' > cyrius.cyml
printf 'fn helper(): i64 { return 1; }\nfn main(): i64 { return helper(); }\nsyscall(60, main());\n' > src/main.cyr
printf 'var a = helper();\n' > tests/t.tcyr
timeout 60 "$CY" coverage --min 100 > "$D/o25" 2>&1; rc25=$?
check "20a main + a referenced helper reads 1/1 (100%)" 1 "$(grep -c 'Functions referenced: 1/1 (100%)' "$D/o25" || true)"
check "20b …and --min 100 passes" 0 "$rc25"
check "20c …and main is not named as a miss" 0 "$(grep -c ': main$' "$D/o25" || true)"
# Only the exact name: `mainx` and `domain` are ordinary fns and still count (and miss).
printf 'fn helper(): i64 { return 1; }\nfn mainx(): i64 { return 2; }\nfn domain(): i64 { return 3; }\nfn main(): i64 { return helper(); }\n' > src/main.cyr
timeout 60 "$CY" -v coverage > "$D/o26" 2>&1
check "20d mainx and domain are still counted (1/3)" 1 "$(grep -c 'Functions referenced: 1/3' "$D/o26" || true)"
check "20e …and named as misses" 2 "$(grep -cE '^  src/main.cyr: (mainx|domain)$' "$D/o26" || true)"
# A src/ whose only public fn is main has nothing to measure — the existing error, not 100%.
printf 'fn main(): i64 { return 0; }\nsyscall(60, main());\n' > src/main.cyr
timeout 60 "$CY" coverage > "$D/o27" 2>&1; rc27=$?
check "20f only main: 'no public functions found', exit 1" "1 1" "$(grep -c 'no public functions found' "$D/o27") $rc27"

cd "$ROOT" || exit 2
echo ""
# 6.6.11: axes that could not run make the verdict a SKIP (exit 77), never a PASS.
if [ "$fails" = "0" ] && [ "$ROOTSKIP" = "1" ]; then
    echo "SKIP: coverage-corpus-and-failopen — every axis that ran is green; axes 15-17 cannot run as root"
    exit 77
fi
if [ "$fails" = "0" ]; then
    echo "PASS: coverage-corpus-and-failopen — whole corpus + whole sources, code-only whole-identifier refs, every spelling + the private rule, no nested prune, misses named, empty measurement fails"
    exit 0
fi
echo "FAIL: coverage-corpus-and-failopen — $fails assertion(s) failed"
exit 1
