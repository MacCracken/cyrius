#!/bin/sh
# embed_manifest_refusals.sh — 6.6.19 (P2, E1). `[embed] NAME = "path"` is the one manifest key
# that copies a file's bytes VERBATIM into a built artifact, so cbt reads it narrowly and refuses
# everything else BY NAME (`cyrius.cyml [embed] NAME`), before any compile.
#
# WHY: until 6.6.19 an `[embed]` section was ignored without a word — exit 0, no warning, no
# --print-config row. And cbt has to vet NAMES itself: the generated module sits before
# `#@srcline`, so a prelude parse error (`fn match()`) is blamed on the ENTRY file as
# `<source>:N`. The fixtures are written the way consumers write manifests (P1's lesson): a
# Windows path is a TOML LITERAL string ('C:\x') — in a basic string `\x` is an invalid escape
# and the refusal would come from the TOML reader, not from [embed].
#
# AXES (each refusal row: `cyrius build` exits 1 AND names `[embed] NAME`; a project whose build
# is otherwise valid, so on the pre-6.6.19 CLI every row exits 0 — RED)
#   1. paths: absolute, `../x`, `a/../../x`, 'C:\x', '\x', a `:` anywhere (the NTFS stream forms
#      `.git::$INDEX_ALLOCATION/config` and `.git:$I30:$INDEX_ALLOCATION/config` name the .git
#      directory on Windows; `file:stream`), an 8.3 short-name component (`x~1`), a code point
#      HFS+ ignores (U+200C, U+FEFF), a file with a second hard link, a committed link `data/k ->
#      /etc/hostname`, a path through a linked directory, `.git/config` and `.GIT/config`, a
#      missing file, a directory.
#   2. sizes, against cycc's pool (2,097,152 B; LEX refuses at `spos + 1 >= 2097152`, so it holds
#      2,097,151 bytes NULs included): one file of 2,097,151 B (cap + 1) is refused; two files
#      whose (len + 1) sum to 2,097,152 are refused WITH each entry's size listed; the exact caps
#      (2,097,150 alone; a pair summing to 2,097,151) are accepted. (The near-cap file is COMPILED
#      in embed_build.sh — accepted here only proves cbt's arithmetic, not cycc's.)
#   3. names: `a.b`, `"a b"`, `9x`, `a-b`; `X` alongside `X_len`; a duplicate.
#   4. values: an inline table (the {dir, glob} set form), an array, a `[embed.x]` section.
#   5. RESERVED NAMES, DERIVED from the compiler (not typed here): every TOKNAME_BUILTIN name,
#      every IS_KEYWORD_TOK statement keyword via TOKNAME (src/common/util.cyr), and the
#      identifier-spelled intrinsics PARSE_FACTOR lowers (_is_ident_intrinsic's `_is_X_word`
#      calls in src/frontend/parse.cyr; fncall0..8 from _IS_FNCALL_NAME) — `sizeof` is in
#      NEITHER util.cyr table. Each is refused by name; near-misses (`matches`, `sizeofx`,
#      `fncall9`) are accepted, so the check is not a prefix test.
#   6. positive: `--print-config` shows `embed = ["PRESET=data/x.json"]  (manifest: [embed])`,
#      and a valid [embed] warns nothing and builds.
#   7. (6.6.20, CBTB-07) what a refusal echoes — the NAME and the path, the manifest's own bytes —
#      is shown through `_shown` (`\xNN` below 32 and from 127): a path holding ESC/BEL (an OSC
#      title set, decoded from `\u001b` / `\u0007`) and a quoted NAME holding a raw ESC reach
#      the output escaped, never raw. Red on e696746d (raw ESC/BEL in the refusal line). Mutants:
#      the path echoed raw -> the two HFS rows and axis 7's path rows red; the NAME echoed raw ->
#      axis 7's name rows red.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: embed_manifest_refusals: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: embed_manifest_refusals: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: embed_manifest_refusals: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
mkdir -p "$W/home/bin"; cp "$CC" "$W/home/bin/cycc"

# The scratch project: a valid build (so the only possible failure is the [embed] refusal).
P="$W/p"
mkdir -p "$P/data" "$P/sub" "$P/.git" "$P/real"
printf 'syscall(60, 0);\n' > "$P/main.cyr"
printf '{"preset": "lean"}\n' > "$P/data/x.json"
printf 'a real file whose name holds a colon\n' > "$P/data/x.json:secret"
# real files for the rows the previous CLI ACCEPTED: an 8.3-shaped name, HFS+-ignorable code
# points (U+200C, U+FEFF), and a second hard link to an in-project file
ZWNJ=$(printf '\342\200\214'); BOM=$(printf '\357\273\277')
printf 'x\n' > "$P/data/x~1.json"; mkdir -p "$P/pr~2"; printf 'x\n' > "$P/pr~2/x.json"
printf 'x\n' > "$P/data/z$ZWNJ.json"; printf 'x\n' > "$P/data/b$BOM.json"
printf 'x\n' > "$P/data/h0.json"; ln "$P/data/h0.json" "$P/data/hard.json"
printf 'in-project\n' > "$P/real/x.json"
printf '[core]\n\textraheader = AUTHORIZATION: basic c2VjcmV0\n' > "$P/.git/config"
ln -s /etc/hostname "$P/data/k"
ln -s real "$P/lnk"
head -c 2097151 /dev/zero > "$P/over"
head -c 2097150 /dev/zero > "$P/cap"
head -c 1048575 /dev/zero > "$P/h1"
head -c 1048574 /dev/zero > "$P/h2"
head -c 1048575 /dev/zero > "$P/h3"
HDR='[package]
name = "p"
[build]
entry = "main.cyr"
output = "build/main"
'
cli() { ( cd "$P" && env -u CYRIUS_DCE -u CYRIUS_DEFINES CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ); }
# refused <label> <expected NAME as printed> <[embed] body line(s)> [<reason substring>]
refused() {
    rm -rf "$P/build"
    printf '%s[embed]\n%s\n' "$HDR" "$3" > "$P/cyrius.cyml"
    rc=0; cli build > "$W/out" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then fail "$1: exit 0 (the [embed] entry was accepted or ignored): $(head -2 "$W/out" | tr '\n' ' ')"; return; fi
    grep -qF "error: cyrius.cyml [embed] $2" "$W/out" || fail "$1: exit $rc but no 'error: cyrius.cyml [embed] $2' line: $(head -2 "$W/out" | tr '\n' ' ')"
    [ -z "$4" ] || grep -qF "$4" "$W/out" || fail "$1: refused, but not for the reason '$4': $(head -1 "$W/out")"
    [ -e "$P/build/main" ] && fail "$1: a binary was built anyway"
    rm -rf "$P/build"
}

# ── axis 1: paths ────────────────────────────────────────────────────────────────────────
x=$FAIL
refused "axis 1 absolute"        'ABS = "/etc/hostname"'   'ABS = "/etc/hostname"'
refused "axis 1 ../x"            'UP = "../x"'             'UP = "../x"'
refused "axis 1 a/../../x"       'UP2 = "a/../../x"'       "UP2 = 'a/../../x'"
refused "axis 1 drive"           'DRV = "C:\x"'            "DRV = 'C:\\x'"
refused "axis 1 ntfs stream"     'ADS = ".git::$INDEX_ALLOCATION/config"' "ADS = '.git::\$INDEX_ALLOCATION/config'" "holds a ':'"
refused "axis 1 ntfs I30"        'I30 = ".git:$I30:$INDEX_ALLOCATION/config"' "I30 = '.git:\$I30:\$INDEX_ALLOCATION/config'" "holds a ':'"
refused "axis 1 file:stream"     'STR = "data/x.json:secret"' "STR = 'data/x.json:secret'" "holds a ':'"
refused "axis 1 8.3 name"        'TIL = "data/x~1.json"'   'TIL = "data/x~1.json"' "8.3 short-name"
refused "axis 1 8.3 dir"         'TID = "pr~2/x.json"'     'TID = "pr~2/x.json"' "8.3 short-name"
# (shown escaped since 6.6.20 — axis 7 — so the invisible code point is visible in the refusal)
refused "axis 1 HFS ignorable"   'ZW = "data/z\xe2\x80\x8c.json"' "ZW = 'data/z$ZWNJ.json'" "HFS+ ignores"
refused "axis 1 HFS BOM"         'BOM = "data/b\xef\xbb\xbf.json"' "BOM = 'data/b$BOM.json'" "HFS+ ignores"
refused "axis 1 hard link"       'HARD = "data/hard.json"' 'HARD = "data/hard.json"' "more than one hard link"
refused "axis 1 backslash"       'BS = "\x"'               "BS = '\\x'"
refused "axis 1 committed link"  'LINK = "data/k"'         'LINK = "data/k"'
refused "axis 1 linked dir"      'VIA = "lnk/x.json"'      'VIA = "lnk/x.json"'
refused "axis 1 .git"            'GIT = ".git/config"'     'GIT = ".git/config"'
refused "axis 1 .GIT"            'GIT2 = ".GIT/config"'    'GIT2 = ".GIT/config"'
refused "axis 1 missing"         'MISS = "nope.json"'      'MISS = "nope.json"'
refused "axis 1 directory"       'DIR = "sub"'             'DIR = "sub"'
[ "$FAIL" = "$x" ] && echo "  ok axis 1: absolute, .., C:, any ':' (NTFS streams), \\, a committed link, a linked dir, .git (any case), missing and a directory are refused by name"

# ── axis 2: sizes ────────────────────────────────────────────────────────────────────────
x=$FAIL
refused "axis 2 cap+1" 'OVER = "over"' 'OVER = "over"'
printf '%s[embed]\nH1 = "h1"\nH3 = "h3"\n' "$HDR" > "$P/cyrius.cyml"
rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -qF 'error: cyrius.cyml [embed]: together the embeds need 2097152 bytes' "$W/out" \
    && grep -qF '[embed] H1 = "h1": 1048575 bytes' "$W/out" && grep -qF '[embed] H3 = "h3": 1048575 bytes' "$W/out" \
    || fail "axis 2 pool: two files summing to the pool + 1 were not refused with each size listed (exit $rc): $(head -3 "$W/out" | tr '\n' ' ')"
printf '%s[embed]\nCAP = "cap"\n' "$HDR" > "$P/cyrius.cyml"
rc=0; cli build --print-config > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qF 'embed = ["CAP=cap"]' "$W/out" || fail "axis 2: a 2,097,150-byte file (the per-file cap) was refused: $(grep error: "$W/out" | head -1)"
printf '%s[embed]\nH1 = "h1"\nH2 = "h2"\n' "$HDR" > "$P/cyrius.cyml"
rc=0; cli build --print-config > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qF 'embed = ["H1=h1", "H2=h2"]' "$W/out" || fail "axis 2: a pair summing to exactly the pool (2,097,151) was refused: $(grep error: "$W/out" | head -1)"
[ "$FAIL" = "$x" ] && echo "  ok axis 2: cap + 1 and pool + 1 refused (each size listed); the exact caps accepted"

# ── axis 3: names ────────────────────────────────────────────────────────────────────────
x=$FAIL
refused "axis 3 a.b"    'a.b:'     'a.b = "data/x.json"'
refused "axis 3 a b"    '"a b":'   '"a b" = "data/x.json"'
refused "axis 3 9x"     '9x:'      '9x = "data/x.json"'
refused "axis 3 a-b"    'a-b:'     'a-b = "data/x.json"'
refused "axis 3 X_len"  'X_len: collides with [embed] X' 'X = "data/x.json"
X_len = "data/x.json"'
refused "axis 3 dup"    'X: is declared twice' 'X = "data/x.json"
X = "data/x.json"'
[ "$FAIL" = "$x" ] && echo "  ok axis 3: a.b, \"a b\", 9x, a-b, X beside X_len and a duplicate are refused by name"

# ── axis 4: values ───────────────────────────────────────────────────────────────────────
x=$FAIL
refused "axis 4 inline table" 'TBL: is an inline table' 'TBL = { dir = "data", glob = "*.json", prefix = "P_" }'
refused "axis 4 array"        'ARR: is an array'        'ARR = ["data/x.json"]'
printf '%s[embed]\nX = "data/x.json"\n[embed.presets]\ndir = "data"\n' "$HDR" > "$P/cyrius.cyml"
rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -qF 'error: cyrius.cyml: [embed] is one table' "$W/out" || fail "axis 4: an [embed.presets] section was not refused (exit $rc)"
rm -rf "$P/build"
[ "$FAIL" = "$x" ] && echo "  ok axis 4: an inline table, an array and an [embed.X] section are refused by name"

# ── axis 5: reserved names, derived from the compiler ────────────────────────────────────
x=$FAIL
U=src/common/util.cyr
awk '/^fn TOKNAME_BUILTIN\(/,/^}/' "$U" | grep -o 'return "[^"]*"' | sed 's/return "//; s/"$//' > "$W/rsv"
awk '/^fn IS_KEYWORD_TOK\(/,/^}/' "$U" | grep -o 'typ == [0-9]*' | awk '{ print $3 }' > "$W/kwtyp"
nkt=$(wc -l < "$W/kwtyp" | tr -d ' ')
while read -r t; do
    awk -v T="$t" '/^fn TOKNAME\(/,/^}/ { if ($0 ~ "typ == " T "\\)") { match($0, /return "[^"]*"/); print substr($0, RSTART + 8, RLENGTH - 9) } }' "$U"
done < "$W/kwtyp" | sed "s#'/'#\\
#g" >> "$W/rsv"
# identifier-spelled intrinsics: the `_is_X_word` calls in _is_ident_intrinsic, and fncall0..8
awk '/^fn _is_ident_intrinsic\(/,/^}/' src/frontend/parse.cyr | grep -o '_is_[a-z0-9]*_word' | sed 's/^_is_//; s/_word$//' > "$W/ident"
ni=$(wc -l < "$W/ident" | tr -d ' ')
[ "$ni" -ge 2 ] || fail "axis 5: found $ni identifier intrinsics in _is_ident_intrinsic (floor 2: sizeof, mulh64)"
cat "$W/ident" >> "$W/rsv"
grep -q 'if (d > 56) { return 0; }' src/frontend/parse_expr.cyr || fail "axis 5: _IS_FNCALL_NAME no longer reads fncall0..fncall8 — re-derive the fncallN names"
for d in 0 1 2 3 4 5 6 7 8; do echo "fncall$d"; done >> "$W/rsv"
sort -u "$W/rsv" | grep -v '^$' > "$W/rsv.u"
nr=$(wc -l < "$W/rsv.u" | tr -d ' ')
[ "$nr" -ge 110 ] || fail "axis 5: only $nr reserved names derived (floor 110; $nkt keyword typs) — the derivation read nothing"
{ printf '%s[embed]\n' "$HDR"; while read -r w; do printf '%s = "data/x.json"\n' "$w"; done < "$W/rsv.u"; } > "$P/cyrius.cyml"
rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "axis 5: a manifest of $nr reserved names exited 0"
miss=""
while read -r w; do
    grep -qF "error: cyrius.cyml [embed] $w: is a reserved word" "$W/out" || miss="$miss $w"
done < "$W/rsv.u"
[ -z "$miss" ] || fail "axis 5: reserved names cbt accepts (a prelude 'fn NAME()' that cycc blames on <source>):$miss"
for w in matches sizeofx fncall9 f64_addx var_ default_x; do
    printf '%s[embed]\n%s = "data/x.json"\n' "$HDR" "$w" > "$P/cyrius.cyml"
    rc=0; cli build --print-config > "$W/out" 2>&1 || rc=$?
    [ "$rc" = 0 ] || fail "axis 5: the near-miss name $w was refused (a prefix test?): $(grep error: "$W/out" | head -1)"
done
[ "$FAIL" = "$x" ] && echo "  ok axis 5: all $nr reserved names derived from util.cyr + parse.cyr are refused by name; near-misses are accepted"

# ── axis 6: positive ─────────────────────────────────────────────────────────────────────
x=$FAIL
printf '%s[embed]\nPRESET = "data/x.json"\n' "$HDR" > "$P/cyrius.cyml"
rc=0; cli build --print-config > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qF '  embed = ["PRESET=data/x.json"]  (manifest: [embed])' "$W/out" \
    || fail "axis 6: --print-config does not show the [embed] row (exit $rc): $(grep -E 'embed|error' "$W/out" | head -2)"
rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "axis 6: a valid [embed] project does not build (exit $rc): $(grep error: "$W/out" | head -2)"
grep -qE '^(warn|error):' "$W/out" && fail "axis 6: a valid [embed] warned: $(grep -E '^(warn|error):' "$W/out" | head -1)"
printf '%s' "$HDR" > "$P/cyrius.cyml"
cli build --print-config > "$W/out" 2>&1 || true
grep -qF '  embed = []  (default)' "$W/out" || fail "axis 6: with no [embed] the row is not '[]  (default)'"
[ "$FAIL" = "$x" ] && echo "  ok axis 6: --print-config shows the [embed] row from the manifest; a valid entry builds and warns nothing"

# ── axis 7: what a refusal ECHOES is shown escaped (6.6.20, CBTB-07) ──────────────────────
# The NAME and path are the manifest's bytes. A path refused for holding a control character
# was echoed RAW — `\u001b` decodes to ESC since 6.6.17 — so the refusal itself carried the
# escape sequence (here an OSC window-title set) to the terminal. Shown as \xNN, nothing raw.
x=$FAIL
ESC=$(printf '\033'); BEL=$(printf '\007')
refused "axis 7 control path"  'CTL = "a\x1b]0;pwned\x07b"' 'CTL = "a\u001b]0;pwned\u0007b"' "holds a control character"
grep -qF "$ESC" "$W/out" && fail "axis 7: the refused path's ESC reached the output raw"
grep -qF "$BEL" "$W/out" && fail "axis 7: the refused path's BEL reached the output raw"
refused "axis 7 control name"  '"k\x1b[2J":' "\"k${ESC}[2J\" = \"data/x.json\"" "is not a valid name"
grep -qF "$ESC" "$W/out" && fail "axis 7: the refused NAME's ESC reached the output raw"
[ "$FAIL" = "$x" ] && echo "  ok axis 7: a path holding ESC/BEL and a quoted NAME holding ESC are refused and SHOWN escaped (\\x1b, \\x07), never raw"

[ "$FAIL" = 0 ] || { echo "FAIL: embed_manifest_refusals ($FAIL)"; exit 1; }
echo "PASS: embed_manifest_refusals"
