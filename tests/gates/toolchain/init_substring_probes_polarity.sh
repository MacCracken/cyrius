#!/bin/sh
# Gate: cyrius-init's "is it already there?" probes read `strstr` as an INDEX, not as a
# C pointer — so the integrations the tool REPORTS writing are actually written.
#
# ⛔ THE DEFECT (found 6.6.6 bite 6, shipped since the probes were written). `strstr`
# (lib/string.cyr) returns the match INDEX or -1. Both probes in programs/cyrius-init.cyr
# tested it as if it were C's pointer-returning strstr:
#
#   _cmtools_starship:  if (strstr(buf, "custom.cyrius") != 0)  → "already configured"
#   _run_port .gitignore: if (strstr(gbuf, markerc) == 0)       → append the port lines
#
# `!= 0` is TRUE for "not found" (-1), so `cyrius init --cmtools=starship` printed
# "starship: Cyrius segment already configured" and wrote NOTHING for every config that
# did not literally begin with the 13 bytes "custom.cyrius" — i.e. for every real user,
# for the flag's entire life. `== 0` is the same error inverted: an existing .gitignore
# only got the `/rust-old/` + `/build/` lines when the marker was already its first bytes,
# so in practice `cyrius port` never appended them.
#
# Measured on HEAD before the fix: a starship.toml of "# existing starship config\n
# add_newline = false\n" came back byte-identical with the tool reporting success, and a
# .gitignore of "/target\n" came back byte-identical with no report at all.
#
# The two polarities are why axes 3 and 5 exist: a fix that just flips the comparison to
# "always write" is also wrong (it duplicates the segment on every init). Each probe is
# checked in BOTH directions — absent → written, present → skipped.
#
# Axis 6 is the census that makes this gate cover the SHAPE rather than the two lines:
# no `strstr(...) == 0` / `!= 0` anywhere in the shipped source. A prefix test is
# `memeq(s, p, n)`; a presence test is `>= 0`; an absence test is `< 0`.
# ⚠ It MASKS double-quoted string literals first. Its own registration line in
# programs/checks/main.cyr QUOTES the defect it describes, and unmasked the census
# reported that description as a live site — a confident false positive from a gate
# reading its own docstring. Same masking the raw-syscall-literal gate needs, and for
# the same reason: in-tree text that talks about code is not code.
#
# MUTATION LEDGER (6.6.6 bite 6a, run on this host against the pre-fix tree, both probes
# restored at once — 11 checks RED, real tree 0 RED):
#   * `!= 0` in _cmtools_starship → axis 1 RED x4 (nothing written, no "added" report),
#     axis 2 RED (no section to be idempotent about), axis 3 RED x2 (the marker at offset
#     0 read as ABSENT, so the segment was appended to the one config it should skip).
#   * `== 0` in the port .gitignore probe → axis 4 RED x3 (lines not appended).
#     ⚠ Axis 5 stays GREEN under this mutation and that is expected: with the marker at a
#     non-zero offset `== 0` is false, so the buggy probe skips for the wrong reason and
#     lands on the right answer. Axis 5's job is the OTHER wrong fix — an unconditional
#     append — which it catches.
#   * axis 6 RED x1, naming both source lines.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: init_substring_probes_polarity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$ROOT/build/cycc" ] || { echo "FAIL: init_substring_probes_polarity: build/cycc missing"; exit 1; }
[ -f "$ROOT/programs/cyrius-init.cyr" ] || { echo "FAIL: programs/cyrius-init.cyr missing"; exit 1; }

# Build the scaffolder the way the release does, into a <root>/bin/ so its own
# templates resolution (<root>/programs/cyrius-init-templates) lands inside $D.
mkdir -p "$D/root/bin" "$D/root/programs"
BIN="$D/root/bin/cyrius-init"
if ! "$ROOT/build/cycc" < "$ROOT/programs/cyrius-init.cyr" > "$BIN" 2> "$D/build.err"; then
    echo "FAIL: init_substring_probes_polarity: programs/cyrius-init.cyr did not compile"
    sed 's/^/    /' "$D/build.err"
    exit 1
fi
chmod +x "$BIN"
SZ=$(wc -c < "$BIN")
if [ "$SZ" -lt 4096 ]; then
    echo "FAIL: init_substring_probes_polarity: cyrius-init compiled to $SZ bytes (empty/short binary)"
    exit 1
fi
echo "built cyrius-init: $SZ bytes"
cp -r "$ROOT/programs/cyrius-init-templates" "$D/root/programs/"
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")

run_init() {   # run_init <workdir> <xdg> <args...>
    w=$1; x=$2; shift 2
    ( cd "$w" && XDG_CONFIG_HOME="$x" HOME="$D/home" CYRIUS_VER="$VER" "$BIN" "$@" ) > "$D/out" 2>&1
}

mkdir -p "$D/home"

# ── AXIS 1: --cmtools=starship on a config that does NOT carry the segment.
echo "axis 1 — the starship segment is written when it is absent:"
mkdir -p "$D/a/xdg" "$D/a/work"
CONF="$D/a/xdg/starship.toml"
printf '# existing starship config\nadd_newline = false\n' > "$CONF"
BEFORE=$(wc -c < "$CONF")
run_init "$D/a/work" "$D/a/xdg" --cmtools=starship demo
check "init exits 0" 0 "$?"
check "the tool reports it ADDED the segment" 1 "$(grep -c 'starship: added Cyrius segment' "$D/out")"
check "exactly one [custom.cyrius] section in the config" 1 "$(grep -c '^\[custom\.cyrius\]$' "$CONF")"
AFTER=$(wc -c < "$CONF")
check "the config grew" yes "$([ "$AFTER" -gt "$BEFORE" ] && echo yes || echo no)"
check "the pre-existing content is still the file's prefix" yes \
    "$([ "$(head -2 "$CONF")" = "$(printf '# existing starship config\nadd_newline = false')" ] && echo yes || echo no)"
check "the appended block carries its detect_files key" 1 "$(grep -c '^detect_files = \["cyrius.cyml", "cyrius.toml"\]$' "$CONF")"

# ── AXIS 2: a second run must not append it twice (the probe must still DETECT).
echo "axis 2 — a second init leaves the config alone (idempotent):"
BEFORE2=$(wc -c < "$CONF")
run_init "$D/a/work" "$D/a/xdg" --cmtools=starship demo2
check "init exits 0" 0 "$?"
check "the tool reports it as already configured" 1 "$(grep -c 'starship: Cyrius segment already configured' "$D/out")"
check "still exactly one [custom.cyrius] section" 1 "$(grep -c '^\[custom\.cyrius\]$' "$CONF")"
check "the config is byte-identical to before the second run" "$BEFORE2" "$(wc -c < "$CONF")"

# ── AXIS 3: the one input the BUGGY probe handled — the marker at offset 0.
# A fix that just flips to "always append" fails here.
echo "axis 3 — a config whose FIRST bytes are the marker is detected, not duplicated:"
mkdir -p "$D/b/xdg" "$D/b/work"
CONF3="$D/b/xdg/starship.toml"
printf 'custom.cyrius is mentioned on line one\n' > "$CONF3"
BEFORE3=$(wc -c < "$CONF3")
run_init "$D/b/work" "$D/b/xdg" --cmtools=starship demo
check "init exits 0" 0 "$?"
check "the tool reports it as already configured" 1 "$(grep -c 'starship: Cyrius segment already configured' "$D/out")"
check "the config is untouched" "$BEFORE3" "$(wc -c < "$CONF3")"

# ── AXIS 4: `cyrius port` appends to an existing .gitignore that lacks the marker.
mkrs() { mkdir -p "$1/src"; printf '[package]\nname = "demo"\n' > "$1/Cargo.toml"; printf 'fn main() {}\n' > "$1/src/main.rs"; }
echo "axis 4 — port appends its lines to a .gitignore that lacks the marker:"
mkrs "$D/p1"
printf '/target\n' > "$D/p1/.gitignore"
run_init "$D" "$D/a/xdg" --__mode=port p1
check "port exits 0" 0 "$?"
check "the tool reports the append" 1 "$(grep -c 'Appended /rust-old/ and /build/ to existing .gitignore' "$D/out")"
check "the port ignore line is present" 1 "$(grep -c '^/rust-old/target/$' "$D/p1/.gitignore")"
check "/build/ is present" 1 "$(grep -c '^/build/$' "$D/p1/.gitignore")"
check "the user's own line survived" 1 "$(grep -c '^/target$' "$D/p1/.gitignore")"

# ── AXIS 5: the marker already present (at a NON-zero offset) → no second append.
echo "axis 5 — port leaves a .gitignore that already carries the marker alone:"
mkrs "$D/p2"
printf '/target\n/rust-old/target/\n' > "$D/p2/.gitignore"
BEFORE5=$(wc -c < "$D/p2/.gitignore")
run_init "$D" "$D/a/xdg" --__mode=port p2
check "port exits 0" 0 "$?"
check "the tool reports no append" 0 "$(grep -c 'Appended /rust-old/' "$D/out")"
check "the .gitignore is byte-identical" "$BEFORE5" "$(wc -c < "$D/p2/.gitignore")"
check "still exactly one /rust-old/target/ line" 1 "$(grep -c '^/rust-old/target/$' "$D/p2/.gitignore")"

# ── AXIS 6: the census — no strstr result compared against 0 for truth, anywhere.
echo "axis 6 — census: no strstr(...) == 0 / != 0 in the shipped source:"
# The sed pass deletes every "…" span (escapes honoured) BEFORE the census looks at the
# line — see the header. Comment-only lines are dropped too.
SITES=$(grep -rn 'strstr(' --include='*.cyr' --include='*.tcyr' --include='*.fcyr' --include='*.bcyr' \
    "$ROOT/lib" "$ROOT/src" "$ROOT/programs" "$ROOT/cbt" "$ROOT/tests" 2>/dev/null \
    | grep -v 'fn strstr' | grep -v ':[0-9]*:[[:space:]]*#' || true)
NSITES=$(printf '%s\n' "$SITES" | grep -c . || true)
check "strstr call sites found (anti-vacuous floor >= 6)" yes "$([ "$NSITES" -ge 6 ] && echo yes || echo no)"
MASKED=$(printf '%s\n' "$SITES" | sed 's/"\(\\.\|[^"\\]\)*"//g')
check "masking kept every site line (no line lost to the sed pass)" "$NSITES" "$(printf '%s\n' "$MASKED" | grep -c . || true)"
BAD=$(printf '%s\n' "$MASKED" | grep -E 'strstr\(.*\)[^;]*(==|!=)[[:space:]]*0' || true)
check "sites that compare a strstr INDEX against 0 for truth" 0 "$(printf '%s' "$BAD" | grep -c . || true)"
[ -n "$BAD" ] && printf '%s\n' "$BAD" | sed 's/^/    /'
[ -n "$BAD" ] && echo "    (presence is >= 0, absence is < 0; a prefix test is memeq(s, p, n))"

echo ""
if [ "$fails" -eq 0 ]; then
    echo "PASS: init_substring_probes_polarity — both probes read strstr as an index, both polarities"
    exit 0
fi
echo "FAIL: init_substring_probes_polarity — $fails check(s) failed"
exit 1
