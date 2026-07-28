#!/bin/sh
# tests/fileid_substrate.sh — v6.5.0 Phase 1 (public/private visibility)
#
# Asserts the per-fn ORIGIN-FILE substrate is correct: every `fn` is attributed to the
# source file its `fn` keyword appears in. Phase 2 turns that into a visibility
# boundary, so if this partitioning is wrong, `private` silently mis-scopes — a fn
# would be judged same-file as one it has never shared a file with.
#
# WHY THIS GATE EXISTS AT PHASE 1, before anything reads the table for a decision:
# a "recorded, not enforced" phase is exactly how a table becomes write-only. The
# v6.4.82 closeout audit found `_fnt_is_async` had one occurrence of its getter
# repo-wide — its own definition — lazily allocating 256 KB that nothing ever read.
# So the substrate ships with its own reader (`CYRIUS_FILEID_DUMP=1`) and its own
# gate rather than being justified retroactively by a later phase.
#
# THE ASSERTIONS ARE RELATIONAL, not absolute. File ids are assigned in include order
# and would shift the moment anything about the preprocessor's marker emission
# changes; pinning literal ids would make this a brittle test of an implementation
# detail. What must hold is the PARTITION: same file => same id, different file =>
# different id. That is the property visibility actually depends on.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: fileid-substrate — %s not built\n" "$CC"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib"

cat > "$T/lib/one.cyr" <<'EOF'
fn fid_one_alpha(): i64 { return 1; }
fn fid_one_beta(): i64 { return 2; }
EOF
cat > "$T/lib/two.cyr" <<'EOF'
fn fid_two_gamma(): i64 { return 3; }
EOF
cat > "$T/m.cyr" <<'EOF'
include "lib/one.cyr"
include "lib/two.cyr"
fn fid_main_delta(): i64 { return 4; }
fn fid_main_eps(): i64 { return 5; }
fn main(): i64 { return fid_one_alpha() + fid_two_gamma() + fid_main_delta() + fid_main_eps(); }
EOF

# The dump prints "<fileid> <fnname>" per definition, to stderr.
( cd "$T" && cat m.cyr | CYRIUS_FILEID_DUMP=1 "$CC" >/dev/null 2>dump.txt ) || true
D="$T/dump.txt"
[ -s "$D" ] || { echo "  FAIL: fileid-substrate — CYRIUS_FILEID_DUMP produced no output"; exit 1; }

fid() { grep -E "^-?[0-9]+ $1\$" "$D" | awk '{print $1}' | head -1; }

A=$(fid fid_one_alpha);  B=$(fid fid_one_beta)
G=$(fid fid_two_gamma)
Dl=$(fid fid_main_delta); E=$(fid fid_main_eps)

for v in "one_alpha:$A" "one_beta:$B" "two_gamma:$G" "main_delta:$Dl" "main_eps:$E"; do
    [ -n "${v#*:}" ] || { echo "  FAIL: fileid-substrate — no id recorded for ${v%%:*}"; exit 1; }
done

fail=0
# 1. Same file => same id. This is the assertion a broken stamp breaks first.
[ "$A" = "$B" ]   || { echo "  FAIL: fileid-substrate — same-file fns disagree (one.cyr: $A vs $B)"; fail=1; }
[ "$Dl" = "$E" ]  || { echo "  FAIL: fileid-substrate — same-file fns disagree (main: $Dl vs $E)"; fail=1; }

# 2. Different file => different id. A stamp that returns a constant passes (1) and
#    fails here, which is why both directions are asserted.
[ "$A" != "$G" ]  || { echo "  FAIL: fileid-substrate — one.cyr and two.cyr share id $A"; fail=1; }
[ "$A" != "$Dl" ] || { echo "  FAIL: fileid-substrate — one.cyr and the main source share id $A"; fail=1; }
[ "$G" != "$Dl" ] || { echo "  FAIL: fileid-substrate — two.cyr and the main source share id $G"; fail=1; }

# 3. Nothing may be unrecorded. -1 is the fail-closed value for an overflowed file map
#    (see FM_FILEID); a plain definition must never produce it.
for v in "$A" "$B" "$G" "$Dl" "$E"; do
    [ "$v" -ge 0 ] 2>/dev/null || { echo "  FAIL: fileid-substrate — unrecorded/overflowed id '$v' for a plain definition"; fail=1; }
done

# 4. Exactly three distinct files are involved, so exactly three distinct ids.
DISTINCT=$(printf '%s\n%s\n%s\n%s\n%s\n' "$A" "$B" "$G" "$Dl" "$E" | sort -u | wc -l | tr -d ' ')
[ "$DISTINCT" = "3" ] || { echo "  FAIL: fileid-substrate — expected 3 distinct file ids, got $DISTINCT"; fail=1; }

if [ "$fail" = "0" ]; then
    printf "  PASS: fileid-substrate — fns partition by origin file (one.cyr=%s two.cyr=%s main=%s)\n" "$A" "$G" "$Dl"
fi
exit $fail
