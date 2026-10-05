#!/bin/sh
# manifest_key_inventory.sh — 6.6.17 (P1 item 0). Every cyrius.cyml key the docs, the init
# templates or the ecosystem use is DECLARED in the CLI's vocabulary (`cyrius help manifest`,
# cbt/manifest.cyr) with a status — read / held / dropped / info — and the guide's table says the
# same thing the CLI says.
#
# WHY: `[build] test` (41 manifests) and `[build] defines` (3) were declared and read by nothing,
# and v6.5.49's `[build]` fallback shipped inert because its gate's fixture used the key spelling
# the code read (`src`) while 120 of 125 manifests wrote `entry`. So the expected key set here is
# NOT the vocabulary's own: it is tests/fixtures/manifest/ecosystem_keys.txt (measured from what
# consumers write), the init templates and docs/architecture/package-format.md.
#
# Re-measure the census (read-only) with:
#   awk -f <the census awk in the fixture's header> ~/Repos/*/cyrius.cyml
# i.e. TOML header only (stop at a `---` line), skip comments, [deps.NAME] -> deps.*,
# [lib.PROFILE] -> lib.*, count each (section, key) once per manifest.
#
# AXES
#   1. the vocabulary is well-formed: every status is read/held/dropped/info, no duplicate key.
#   2. every key the ecosystem census names is in the vocabulary.
#   3. every key the init templates and package-format.md write is in the vocabulary.
#   4. the guide's "Manifest keys" table equals the vocabulary (section, key, status, synonyms,
#      environment, argument) — in both directions.
#   5. self-test: a census row the vocabulary lacks IS reported (the detector is not blind).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: manifest_key_inventory: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: manifest_key_inventory: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=1; }

"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: manifest_key_inventory: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
"$W/cyrius" help manifest > "$W/help.out" 2>&1 || { echo "FAIL: manifest_key_inventory: cyrius help manifest exited non-zero"; exit 1; }
# section key status synonyms environment argument
awk '$1 ~ /^\[/ { s=$1; gsub(/[][]/, "", s); print s, $2, $3, $4, $5, $6 }' "$W/help.out" > "$W/vocab"
nv=$(wc -l < "$W/vocab" | tr -d ' ')
[ "$nv" -ge 30 ] || { echo "FAIL: manifest_key_inventory: only $nv vocabulary rows in 'cyrius help manifest' (floor 30) — the listing read nothing"; exit 1; }

# ── axis 1: well-formed ──────────────────────────────────────────────────────────────────
bad=$(awk '$3 != "read" && $3 != "held" && $3 != "dropped" && $3 != "info"' "$W/vocab")
[ -z "$bad" ] || fail "axis 1: a vocabulary row has an unknown status: $bad"
dup=$(awk '{ print $1, $2 }' "$W/vocab" | sort | uniq -d)
[ -z "$dup" ] || fail "axis 1: a key is declared twice: $dup"
[ "$FAIL" = 0 ] && echo "  ok axis 1: $nv vocabulary rows, each read/held/dropped/info, none duplicated"

# in_vocab <section> <key> — a declared synonym counts, and a `*` row matches any key of its section
cat > "$W/lookup.awk" <<'AWK'
NR == FNR { v[$1 " " $2] = 1; if ($4 != "-") { n = split($4, syn, ","); for (i = 1; i <= n; i++) v[$1 " " syn[i]] = 1 }; next }
/^#/ || NF < 2 { next }
{ s = $(NF-1); k = $NF; if (!((s " " k) in v) && !((s " *") in v)) print s, k }
AWK
missing_from() { awk -f "$W/lookup.awk" "$W/vocab" "$1"; }

# ── axis 2: the ecosystem census ─────────────────────────────────────────────────────────
CENSUS=tests/fixtures/manifest/ecosystem_keys.txt
nc=$(grep -vc '^#' "$CENSUS")
[ "$nc" -ge 20 ] || fail "axis 2: the census has only $nc rows (floor 20)"
m=$(missing_from "$CENSUS")
[ -z "$m" ] && echo "  ok axis 2: all $nc keys the ecosystem writes are declared" || fail "axis 2: keys consumers write that the vocabulary does not declare: $m"

# ── axis 3: the init templates and package-format.md ─────────────────────────────────────
cat > "$W/keys.awk" <<'AWK'
FNR == 1 { sec = "" }
/^---/ { nextfile }
/^[ \t]*#/ { next }
/^[ \t]*\[\[/ { next }
/^[ \t]*\[[^\]]*\]/ { s = $0; sub(/^[ \t]*\[/, "", s); sub(/\].*/, "", s); gsub(/[ \t]/, "", s); sec = s
    if (sec ~ /^deps\./) sec = "deps.*"; if (sec ~ /^lib\./) sec = "lib.*"; next }
sec != "" && /^[ \t]*[A-Za-z_][A-Za-z0-9_-]*[ \t]*=/ { k = $0; sub(/^[ \t]*/, "", k); sub(/[ \t]*=.*/, "", k); print sec, k }
AWK
for t in programs/cyrius-init-templates/cyrius-cyml-*; do awk -f "$W/keys.awk" "$t"; done > "$W/tmpl"
# package-format.md: only its cyrius.cyml block (the first ```toml block; the second is a zugot recipe)
awk '/^```toml/ { n++; on = (n == 1); next } /^```/ { on = 0 } on' docs/architecture/package-format.md | awk -f "$W/keys.awk" >> "$W/tmpl"
nt=$(sort -u "$W/tmpl" | wc -l | tr -d ' ')
[ "$nt" -ge 8 ] || fail "axis 3: only $nt template / package-format keys read (floor 8)"
m=$(sort -u "$W/tmpl" | missing_from /dev/stdin)
[ -z "$m" ] && echo "  ok axis 3: all $nt keys the init templates and package-format.md write are declared" || fail "axis 3: documented keys the vocabulary does not declare: $m"

# ── axis 4: the guide's table == the vocabulary ─────────────────────────────────────────
awk -F'|' '/^\| `\[/ {
    for (i = 2; i <= 7; i++) { f = $i; gsub(/^[ \t]+|[ \t]+$/, "", f); gsub(/`/, "", f); if (f == "—") f = "-"; c[i] = f }
    s = c[2]; gsub(/[][]/, "", s); print s, c[3], c[4], c[5], c[6], c[7] }' docs/guides/cyrius-guide.md | sort > "$W/guide"
sort "$W/vocab" > "$W/vocab.s"
ng=$(wc -l < "$W/guide" | tr -d ' ')
only_cli=$(comm -23 "$W/vocab.s" "$W/guide")
only_doc=$(comm -13 "$W/vocab.s" "$W/guide")
if [ -n "$only_cli$only_doc" ]; then
    [ -n "$only_cli" ] && fail "axis 4: in 'cyrius help manifest' but not (or not so) in the guide's table: $(printf '%s' "$only_cli" | tr '\n' ';')"
    [ -n "$only_doc" ] && fail "axis 4: in the guide's table but not (or not so) in 'cyrius help manifest': $(printf '%s' "$only_doc" | tr '\n' ';')"
else
    echo "  ok axis 4: the guide's table and 'cyrius help manifest' agree on all $ng rows"
fi

# ── axis 5: self-test ────────────────────────────────────────────────────────────────────
printf '# probe\n1 build entry\n1 build no_such_key\n1 features anything\n' > "$W/probe"
got=$(missing_from "$W/probe")
[ "$got" = "build no_such_key" ] && echo "  ok axis 5: the detector reports an undeclared key and only that one" || fail "axis 5 self-test: expected exactly 'build no_such_key', got '$got'"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: manifest_key_inventory (vocabulary vs census vs templates vs guide)"
