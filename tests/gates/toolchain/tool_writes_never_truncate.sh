#!/bin/sh
# tool_writes_never_truncate.sh — v6.6.6. A tool that REPLACES a file the user or the tree owns
# writes it crash-safe (temp + fsync + rename), and a short write is an ERROR — never a truncated
# file and an exit 0.
#
# ⛔ THE DEFECT (found by 6.6.6 bite 12, reproduced at the bite-12 tree). programs/
# gen_unicode_data.cyr wrote the three TRACKED lib/unicode/_*_data.cyr tables with
# `file_write_all` — open(O_TRUNC), then ONE write — and printed the count without checking it.
# On a full disk all three tables were truncated to 2048 bytes and the tool said
# `wrote … (2048 bytes)` and exited 0 (committed sizes 59010 / 96988 / 156750).
#
# ⚠ HOW A FULL DISK IS REPRODUCED WITHOUT A MOUNT. RLIMIT_FSIZE with SIGXFSZ ignored (a shell
# `trap ''` survives exec) gives the writer exactly a full disk's sequence: the write that
# crosses the limit comes back SHORT, the next one fails EFBIG. `ulimit -f` counts 512-byte
# blocks under /bin/sh-as-bash (POSIX mode) and 1024-byte blocks under bash proper; every limit
# below is chosen to hold under BOTH units.
#
# AXES
#   1. gen_unicode_data, unconstrained, regenerates the three committed tables byte-for-byte
#      into an OUTDIR (anti-vacuous: the rows below would otherwise test a tool that writes
#      nothing, and this is also the only place anything re-derives these tables).
#   2. Under a 4-block limit (every table is larger) it exits NON-ZERO, names the file, leaves
#      all three seeded tables byte-for-byte, and leaves no temp behind.
#   3. Under a 150-block limit (76,800 or 153,600 bytes — above the first table, below the
#      third) it fails PART-WAY: every table is either complete or exactly as seeded, never a
#      prefix, and at least one is left as seeded.
#
# MUTATION LEDGER (measured 6.6.6, each in a scratch copy of the tree):
#   a. _ucd_write back to `file_write_all`, result unchecked   -> axis 2 FAIL (rc 0, 2048-byte
#                                                                 tables) and axis 3 FAIL
#   b. programs/gen_unicode_data.cyr as of 6.6.5                -> axis 1 FAIL (no OUTDIR: writes
#                                                                 lib/unicode under its cwd)
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: tool_writes_never_truncate: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }
TABLES="_categories_data.cyr _casefold_data.cyr _normalize_data.cyr"
for t in $TABLES; do
    [ -s "lib/unicode/$t" ] || { echo "FAIL: lib/unicode/$t missing or empty — the committed tables are the expected values"; exit 1; }
done

# ── build the generator from the tree (raw cycc: includes resolve against $ROOT) ──
GEN="$D/gen_unicode_data"
"$CC" < programs/gen_unicode_data.cyr > "$GEN" 2> "$D/build.err"; brc=$?
if [ "$brc" -ne 0 ] || [ ! -s "$GEN" ]; then
    echo "FAIL: programs/gen_unicode_data.cyr does not build (rc=$brc):"; tail -3 "$D/build.err" | sed 's/^/      /'; exit 1
fi
chmod +x "$GEN"
# The generator reads tests/data/ucd/ relative to its cwd. It runs in $D/run over a COPY of
# those inputs, never in $ROOT: a regressed tool that ignored OUTDIR would otherwise rewrite
# the tree's lib/unicode under the size limit — the very damage this gate exists to catch.
mkdir -p "$D/run/tests/data" && cp -R tests/data/ucd "$D/run/tests/data/ucd" \
  || { echo "FAIL: cannot stage the UCD inputs into $D/run"; exit 1; }

# _seed <dir> — a copy of the committed tables with a sentinel line appended, so "left as it
# was" (== seed) is distinguishable from "rewritten with the same content" (== committed)
_seed() {
    mkdir -p "$1" || return 1
    for t in $TABLES; do
        { cat "lib/unicode/$t" && echo "# SENTINEL — must survive a failed regeneration"; } > "$1/$t" || return 1
    done
}

# ── axis 1: anti-vacuous — unconstrained, the committed tables come back exactly ──
mkdir -p "$D/ok"
rc=0; ( cd "$D/run" && exec "$GEN" "$D/ok" ) > "$D/a1.out" 2>&1 || rc=$?
a1=0
[ "$rc" -eq 0 ] || { fail "axis 1: the generator failed unconstrained (rc=$rc):"; tail -3 "$D/a1.out" | sed 's/^/      /'; a1=1; }
for t in $TABLES; do
    cmp -s "$D/ok/$t" "lib/unicode/$t" || { fail "axis 1: $t regenerated into OUTDIR differs from the committed table ($(wc -c < "$D/ok/$t" 2>/dev/null || echo 0) vs $(wc -c < "lib/unicode/$t") bytes) — tables stale, or OUTDIR ignored"; a1=1; }
done
[ -e "$D/run/lib" ] && { fail "axis 1: the generator wrote lib/ under its cwd although OUTDIR was given"; a1=1; }
[ "$a1" = 0 ] && echo "  ok: axis 1: unconstrained, gen_unicode_data reproduces all 3 committed tables into OUTDIR"

# ── axis 2: every table larger than the limit -> non-zero, all three kept, no temp left ──
_seed "$D/fsz" || { echo "FAIL: cannot seed $D/fsz"; exit 1; }
_seed "$D/seed" || { echo "FAIL: cannot seed $D/seed"; exit 1; }
rc=0; ( cd "$D/run" && trap '' XFSZ && ulimit -f 4 && exec "$GEN" "$D/fsz" ) > "$D/a2.out" 2>&1 || rc=$?
a2=0
[ "$rc" -ne 0 ] || { fail "axis 2: a SHORT write was reported as success (rc 0):"; sed 's/^/      /' "$D/a2.out" | head -3; a2=1; }
grep -q "write failed: $D/fsz/_categories_data.cyr" "$D/a2.out" || { fail "axis 2: the failure does not name the file it could not write:"; sed 's/^/      /' "$D/a2.out" | head -3; a2=1; }
for t in $TABLES; do
    cmp -s "$D/fsz/$t" "$D/seed/$t" || { fail "axis 2: $t was CHANGED by a failed regeneration ($(wc -c < "$D/fsz/$t") bytes, seeded $(wc -c < "$D/seed/$t"))"; a2=1; }
done
left=$(ls -A "$D/fsz" | LC_ALL=C sort | tr '\n' ' ')
[ "$left" = "_casefold_data.cyr _categories_data.cyr _normalize_data.cyr " ] || { fail "axis 2: a failed write left files behind: $left"; a2=1; }
[ "$a2" = 0 ] && echo "  ok: axis 2: under RLIMIT_FSIZE (4 blocks) the generator exits $rc, names the file, keeps all 3 tables, leaves no temp"

# ── axis 3: fails PART-WAY -> each table complete or untouched, never a prefix ──
_seed "$D/mid" || { echo "FAIL: cannot seed $D/mid"; exit 1; }
rc=0; ( cd "$D/run" && trap '' XFSZ && ulimit -f 150 && exec "$GEN" "$D/mid" ) > "$D/a3.out" 2>&1 || rc=$?
a3=0; nkept=0; nnew=0
[ "$rc" -ne 0 ] || { fail "axis 3: a part-way failure was reported as success (rc 0)"; a3=1; }
for t in $TABLES; do
    if cmp -s "$D/mid/$t" "$D/seed/$t"; then nkept=$((nkept + 1))
    elif cmp -s "$D/mid/$t" "lib/unicode/$t"; then nnew=$((nnew + 1))
    else fail "axis 3: $t is neither the old table nor the new one ($(wc -c < "$D/mid/$t") bytes) — a partial write replaced it"; a3=1
    fi
done
cmp -s "$D/mid/_categories_data.cyr" "lib/unicode/_categories_data.cyr" || { fail "axis 3: the first table (59,010 B, under the limit in both units) was not written — the limit did not land part-way"; a3=1; }
[ "$nkept" -ge 1 ] || { fail "axis 3: no table was left as seeded — the limit did not bite"; a3=1; }
[ "$(ls -A "$D/mid" | wc -l)" -eq 3 ] || { fail "axis 3: a failed write left files behind: $(ls -A "$D/mid" | tr '\n' ' ')"; a3=1; }
[ "$a3" = 0 ] && echo "  ok: axis 3: a part-way failure (150 blocks) leaves $nnew table(s) complete and $nkept exactly as they were, rc $rc"

if [ "$FAIL" != 0 ]; then echo "FAIL: tool_writes_never_truncate"; exit 1; fi
echo "PASS tool_writes_never_truncate (gen_unicode_data: a short write fails loudly and leaves every table whole)"
