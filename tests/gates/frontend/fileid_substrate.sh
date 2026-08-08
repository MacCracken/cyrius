#!/bin/sh
# tests/gates/frontend/fileid_substrate.sh — v6.5.0 Phase 1 (public/private visibility)
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
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: fileid-substrate — %s not built\n" "$CC"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib"

# THE FIXTURE DELIBERATELY USES THE TWO SHAPES THAT BREAK A NAIVE MAP.
# The first cut of this gate used a FLAT, includes-first main source with no nested
# include — the one arrangement where the partition holds even when the underlying
# marker stream is wrong. It passed while `alloc_init` and `atomic_cas` (different
# files) shared an id in cycc's own build. Same class as the v6.4.80 finding that
# 251/251 byte-identical meant the corpus had ZERO coverage of the failing shape.
#
#   (a) NESTED include  — one.cyr includes two.cyr and then defines a fn AFTER it.
#                         Without a resume marker, one.cyr's tail inherits two.cyr's id.
#   (b) CODE BEFORE the first include — main source defines a fn, then includes, then
#                         defines more. Without resume markers the main source splits.
cat > "$T/lib/two.cyr" <<'EOF'
fn fid_two_gamma(): i64 { return 3; }
EOF
cat > "$T/lib/one.cyr" <<'EOF'
fn fid_one_alpha(): i64 { return 1; }
include "lib/two.cyr"
fn fid_one_beta(): i64 { return 2; }
EOF
cat > "$T/m.cyr" <<'EOF'
fn fid_main_zeta(): i64 { return 0; }
include "lib/one.cyr"
fn fid_main_delta(): i64 { return 4; }
fn fid_main_eps(): i64 { return 5; }
fn main(): i64 { return fid_one_alpha() + fid_two_gamma() + fid_main_delta() + fid_main_eps() + fid_main_zeta(); }
EOF

# The dump prints "<fileid> <fnname>" per definition, to stderr.
( cd "$T" && cat m.cyr | CYRIUS_FILEID_DUMP=1 "$CC" >/dev/null 2>dump.txt ) || true
D="$T/dump.txt"
[ -s "$D" ] || { echo "  FAIL: fileid-substrate — CYRIUS_FILEID_DUMP produced no output"; exit 1; }

# Dump format is `<fileid> <P|-> <name>`: the visibility column was added in Phase 2
# and this matcher was not updated with it, so every lookup silently returned empty.
fid() { grep -E "^-?[0-9]+ [P-] $1\$" "$D" | awk '{print $1}' | head -1; }

A=$(fid fid_one_alpha);  B=$(fid fid_one_beta)
G=$(fid fid_two_gamma)
Z=$(fid fid_main_zeta)
Dl=$(fid fid_main_delta); E=$(fid fid_main_eps)

for v in "one_alpha:$A" "one_beta:$B" "two_gamma:$G" "main_zeta:$Z" "main_delta:$Dl" "main_eps:$E"; do
    [ -n "${v#*:}" ] || { echo "  FAIL: fileid-substrate — no id recorded for ${v%%:*}"; exit 1; }
done

fail=0
# 1. Same file => same id. This is the assertion a broken stamp breaks first.
# (a) one.cyr's fns straddle a NESTED include — this is the assertion the flat
#     fixture could never make, and the one that was live-broken.
[ "$A" = "$B" ]   || { echo "  FAIL: fileid-substrate — one.cyr split across a NESTED include ($A vs $B)"; fail=1; }
[ "$Dl" = "$E" ]  || { echo "  FAIL: fileid-substrate — same-file fns disagree (main: $Dl vs $E)"; fail=1; }
# (b) the main source straddles its include — zeta is before it, delta/eps after.
[ "$Z" = "$Dl" ]  || { echo "  FAIL: fileid-substrate — main source split across its include ($Z before vs $Dl after)"; fail=1; }

# 2. Different file => different id. A stamp that returns a constant passes (1) and
#    fails here, which is why both directions are asserted.
[ "$A" != "$G" ]  || { echo "  FAIL: fileid-substrate — one.cyr and two.cyr share id $A"; fail=1; }
[ "$A" != "$Dl" ] || { echo "  FAIL: fileid-substrate — one.cyr and the main source share id $A"; fail=1; }
[ "$G" != "$Dl" ] || { echo "  FAIL: fileid-substrate — two.cyr and the main source share id $G"; fail=1; }
# The leak direction: one.cyr's tail must NOT inherit the id of the file it included.
[ "$B" != "$G" ]  || { echo "  FAIL: fileid-substrate — one.cyr's post-include tail LEAKED two.cyr's id ($B)"; fail=1; }

# 3. Nothing may be unrecorded. -1 is the fail-closed value for an overflowed file map
#    (see FM_FILEID); a plain definition must never produce it.
for v in "$A" "$B" "$G" "$Z" "$Dl" "$E"; do
    [ "$v" -ge 0 ] 2>/dev/null || { echo "  FAIL: fileid-substrate — unrecorded/overflowed id '$v' for a plain definition"; fail=1; }
done

# 4. Exactly three distinct files are involved, so exactly three distinct ids.
DISTINCT=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$A" "$B" "$G" "$Z" "$Dl" "$E" | sort -u | wc -l | tr -d ' ')
[ "$DISTINCT" = "3" ] || { echo "  FAIL: fileid-substrate — expected 3 distinct file ids, got $DISTINCT"; fail=1; }

if [ "$fail" = "0" ]; then
    printf "  PASS: fileid-substrate — fns partition by origin file (one.cyr=%s two.cyr=%s main=%s)\n" "$A" "$G" "$Dl"
fi
exit $fail
