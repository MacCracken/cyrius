#!/bin/sh
# tracked_sources_canonically_formatted.sh — v6.6.6 (bite 23c).
#
# EVERY TRACKED .cyr THE PROJECT OWNS PASSES `cyrius fmt --check`, except a SMALL,
# NAMED, JUSTIFIED set — and the exceptions cannot rot.
#
# WHY. `cyrius fmt --check cbt/commands.cyr` exited 1 at 6.6.6's HEAD (an
# `if (_toml_section_at(...) == 1) {` whose body was never indented), and that same file
# was reported twice inside one release before anyone fixed it. Nothing ran the formatter
# over the tree, so "the tree is formatted" was a belief. The 6.6.6 sweep found 64 of 332
# tracked non-lib `.cyr` failing; 11 were fixed here (cbt/ + programs/ + tests/win), each
# proved logic-preserving by recompiling to a BYTE-IDENTICAL binary.
#
# ⛔ THE EXCLUSIONS ARE THE INTERESTING PART, and each is checked for rot: an excluded
# pattern that matches NOTHING, or a RATCHET whose real count has dropped below the
# ceiling, fails this gate. A stale exemption is how a "temporary" carve-out becomes
# permanent — and an exemption list nobody re-derives is the same self-drifting
# hand-maintained value this cycle keeps finding wrong.
#
# ⭐ THE POSITIVE CONTROL IS LOAD-BEARING. A sweep that runs a BROKEN checker reports
# every file clean and exits 0 — the exact green placebo this release is about. So a
# deliberately mis-indented file is checked every run and MUST be rejected, and a
# canonical one MUST be accepted; the sweep's verdict is only trusted after both.
#
# MUTATION LEDGER (applied to a staged copy of the tree, the gate re-run against it)
#   P1. cbt/commands.cyr's `_toml_section_at` body de-indented again   -> RED (sweep)
#   P2. an exclusion pattern that matches no tracked file             -> RED (rot)
#   P3. one more unformatted file under src/frontend/ (ratchet burst) -> RED (ratchet)
#   P4. the ratchet ceiling left high after the area was cleaned      -> RED (rot)
#   P5. the control's "must be rejected" file made canonical          -> RED (control)
#   P6. programs/cyrfmt.cyr absent (the checker cannot be built)      -> RED, by name
#   Real tree -> GREEN.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: tracked_sources_canonically_formatted: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0

# ⚠ BUILD cyrfmt FROM SOURCE, do not shell out to the installed `cyrius fmt`. Two reasons,
# both measured: the installed wrapper resolves `./build/cyrfmt`, which is gitignored and
# absent on a fresh checkout (the control caught exactly that, as `tool not found`), and a
# STALE build/cyrfmt would judge this tree by an older contract. The sibling gate
# `cyrfmt_string_continuation.sh` builds from source for the same reason.
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL tracked_sources_canonically_formatted: no build/cycc"; exit 1; }
[ -f programs/cyrfmt.cyr ] || { echo "FAIL tracked_sources_canonically_formatted: programs/cyrfmt.cyr is missing"; exit 1; }
cat programs/cyrfmt.cyr | "$CC" > "$D/cyrfmt" 2>"$D/cyrfmt.err" || true
[ -s "$D/cyrfmt" ] || { echo "FAIL tracked_sources_canonically_formatted: cyrfmt did not compile"; sed -n '1,10p' "$D/cyrfmt.err"; exit 1; }
chmod +x "$D/cyrfmt"

chk() { "$D/cyrfmt" --check "$1" >/dev/null 2>&1; }

# ── control — prove the checker is alive before believing a clean sweep ──────────────
printf 'fn main(): i64 {\n    var x = some_call(1,\n      2);\n    return x;\n}\n' > "$D/ctl_good.cyr"
printf 'fn main(): i64 {\nvar x = 1;\n        return x;\n}\n'                     > "$D/ctl_bad.cyr"
# ⚠ A control failure ABORTS. Sweeping 311 files with a broken checker prints 173 lines of
# noise naming innocent files, which is what the first cut did in a tree with no formatter.
if ! chk "$D/ctl_good.cyr"; then
  echo "FAIL control: a canonically formatted file was REJECTED — every verdict below would"
  echo "              be about the checker, not about the tree"
  "$D/cyrfmt" --check "$D/ctl_good.cyr" 2>&1 | sed 's/^/    /'
  echo "FAIL tracked_sources_canonically_formatted"
  exit 1
fi
if chk "$D/ctl_bad.cyr"; then
  echo "FAIL control: a deliberately mis-indented file was ACCEPTED — the checker is inert"
  echo "              here, so a green sweep would mean nothing"
  echo "FAIL tracked_sources_canonically_formatted"
  exit 1
fi

# ── the corpus, derived ──────────────────────────────────────────────────────────────
git ls-files '*.cyr' > "$D/all" 2>/dev/null || true
ntotal=$(grep -c . "$D/all" || true); [ -n "$ntotal" ] || ntotal=0
if [ "$ntotal" -lt 300 ]; then
  echo "FAIL corpus: only $ntotal tracked .cyr found (expected >= 300) — the sweep is vacuous"
  echo "FAIL tracked_sources_canonically_formatted"
  exit 1
fi

# ── hard exclusions: pattern|reason. Each MUST still match at least one tracked file ──
EXCL='archive/|frozen historical sources (seed examples, stage1a-e); reformatting rewrites history
bootstrap/cybs.cyr|compiled by the 29 KB seed — seed->cybs->cycc is byte-gated and cybs lexes far less than cycc
docs/development/issues/repros/|a filed repro is the spec, verbatim; one of these IS the cyrfmt repro
tests/fixtures/lint_|the bad indentation IS the input under test
src/main|the seven per-target compiler forks, deliberately unformatted (CLAUDE.md)'

# ── ratchets: prefix|ceiling|reason. Failing count must be <= ceiling AND the ceiling
#    must not be stale (a count strictly below it means the ceiling was not lowered).
RATCHET='src/|16|compiler internals — 6.6.6 bite 23c scoped to cbt/ + programs/; reformatting src/ conflicts with every in-flight compiler lane. Lower this as they are fixed.
lib/|2|VENDORED folds (sigil, mabda). CLAUDE.md: fix the SOURCE repo and re-vendor — a fix applied to the fold evaporates at the next `cyrius deps`.'

# ⚠ Both helpers loop over a WORD LIST, never `printf | while`: a `while` on the right of
# a pipe runs in a SUBSHELL, so its `exit 0` / `break` cannot answer for the caller. The
# first cut did exactly that and `is_excluded` returned 0 for EVERY path — the sweep
# reported "0 files were actually checked", which is why the corpus floor exists.
EXCL_PATS=$(printf '%s\n' "$EXCL" | cut -d'|' -f1 | tr '\n' ' ')
RATCHET_PRE=$(printf '%s\n' "$RATCHET" | cut -d'|' -f1 | tr '\n' ' ')
is_excluded() {   # <path> -> 0 if hard-excluded
  for _pat in $EXCL_PATS; do
    case "$1" in "$_pat"*) return 0 ;; esac
  done
  return 1
}
ratchet_of() {    # <path> -> the ratchet prefix owning it, or empty
  for _pre in $RATCHET_PRE; do
    case "$1" in "$_pre"*) printf '%s' "$_pre"; return 0 ;; esac
  done
  return 1
}

# exclusion rot: every hard pattern must still match a tracked file
printf '%s\n' "$EXCL" | while IFS='|' read -r pat reason; do
  [ -n "$pat" ] || continue
  if ! grep -q "^$(printf '%s' "$pat" | sed 's/[.[\*^$]/\\&/g')" "$D/all"; then
    echo "ROT $pat" >> "$D/rot"
  fi
done
if [ -s "$D/rot" ] 2>/dev/null; then
  while read -r _t pat; do
    echo "FAIL exclusions: '$pat' matches no tracked .cyr any more — remove the exemption"
  done < "$D/rot"
  fail=1
fi

# ── the sweep ────────────────────────────────────────────────────────────────────────
: > "$D/dirty"; : > "$D/checked"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if is_excluded "$f"; then continue; fi
  echo "$f" >> "$D/checked"
  chk "$f" || echo "$f" >> "$D/dirty"
done < "$D/all"
nchecked=$(grep -c . "$D/checked" || true); [ -n "$nchecked" ] || nchecked=0
if [ "$nchecked" -lt 250 ]; then
  echo "FAIL sweep: only $nchecked files were actually checked (expected >= 250) — the exclusions swallowed the corpus"
  fail=1
fi

# Split the dirty list into ratcheted areas and "must be clean".
: > "$D/mustclean"
printf '%s\n' "$RATCHET" | while IFS='|' read -r pre ceil reason; do
  [ -n "$pre" ] || continue
  : > "$D/r_$(printf '%s' "$pre" | tr -d '/')"
done
while IFS= read -r f; do
  [ -n "$f" ] || continue
  pre=$(ratchet_of "$f" || true)
  if [ -n "$pre" ]; then
    echo "$f" >> "$D/r_$(printf '%s' "$pre" | tr -d '/')"
  else
    echo "$f" >> "$D/mustclean"
  fi
done < "$D/dirty"

nmust=$(grep -c . "$D/mustclean" 2>/dev/null || true); [ -n "$nmust" ] || nmust=0
if [ "$nmust" -ne 0 ]; then
  echo "FAIL sweep: $nmust tracked .cyr are not canonically formatted and are in no exempt area:"
  sed 's/^/        /' "$D/mustclean"
  echo "        run: cyrius fmt <file>   (rewrites in place; verify the binary is byte-identical)"
  fail=1
fi

printf '%s\n' "$RATCHET" | while IFS='|' read -r pre ceil reason; do
  [ -n "$pre" ] || continue
  lf="$D/r_$(printf '%s' "$pre" | tr -d '/')"
  n=$(grep -c . "$lf" 2>/dev/null || true); [ -n "$n" ] || n=0
  if [ "$n" -gt "$ceil" ]; then
    echo "RATCHETUP $pre $n $ceil" >> "$D/rverdict"
  elif [ "$n" -lt "$ceil" ]; then
    echo "RATCHETSTALE $pre $n $ceil" >> "$D/rverdict"
  else
    echo "  ok: $pre at its recorded ceiling of $ceil unformatted file(s) — $reason"
  fi
done
if [ -s "$D/rverdict" ] 2>/dev/null; then
  while read -r kind pre n ceil; do
    if [ "$kind" = "RATCHETUP" ]; then
      echo "FAIL ratchet: $pre now has $n unformatted files, above its ceiling of $ceil —"
      echo "              format the new one, do not raise the number"
    else
      echo "FAIL ratchet: $pre has $n unformatted files but the ceiling still says $ceil —"
      echo "              LOWER it to $n in this gate, or the exemption silently re-opens"
    fi
  done < "$D/rverdict"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL tracked_sources_canonically_formatted"
  exit 1
fi
echo "PASS tracked_sources_canonically_formatted: $nchecked of $ntotal tracked .cyr swept, 0 unexpected, ratchets at their ceilings, checker proved live both ways"
exit 0
