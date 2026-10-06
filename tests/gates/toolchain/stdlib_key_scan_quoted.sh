#!/bin/sh
# v6.5.30 — the `[deps] stdlib` key scan must not match the word inside a QUOTED VALUE,
# in EVERY copy of the scan — not just the one that was filed.
#
# ⛔ THE DEFECT, AND WHY IT IS HERE TWICE. niyama's `[package] description` reads
# "...foldable into stdlib per sandhi pattern", eleven lines above its real `[deps] stdlib`
# key. The identifier-boundary guard passes (preceded by a space) and the comment-line guard
# passes (not a `#` line), so `_distlib_union_declared_stdlib` locked onto the DESCRIPTION,
# `_parse_toml_str_array` walked forward to the next `[` — a section header — and returned
# empty. Zero leaves meant the `vec_len(req_leaves) > 0` guard was false and `cyrius distlib`
# wrote **no sidecar at all**, silently, for a bundle that was otherwise correct.
#
# ⚠ THIS IS THE SAME BUG, THE SAME PHRASE, AND THE SAME MANIFEST SHAPE AS THE bayan DEFECT
# FIXED AT v6.5.17 — bayan's description says "foldable into stdlib per the sandhi pattern"
# too. That fix corrected `cmd_deps` and introduced the shared `_toml_key_at` helper. It did
# NOT sweep the other two copies of the scan, so the identical defect sat in
# `_distlib_union_declared_stdlib` and `_libsync_declared_mods` for thirteen releases and
# re-surfaced through a different consumer. The lesson is the one the `_cfo` family taught
# four times over: GREP THE SHAPE, NOT THE SITE. Hence axis 3 — a STRUCTURAL axis that fails
# if any copy of the scan drifts back to a hand-rolled guard.
#
# ⭐ 6.6.18 (D4, P4 option 2): `cyrius distlib` no longer reads `[deps] stdlib` at all — its
# union was removed and the sidecar is compile-verified — so the behavioural axes moved to
# `cyrius deps`, the scan that still reads the key (it vendors the declared leaves into ./lib).
# Axis 4 pins the other half: the published sidecar is byte-identical with and without the key.
# Axis 3's floor dropped from 3 scan sites to 2 (the distlib union's copy is gone).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CLI=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CLI" ] || CLI="$HOME/.cyrius/bin/cyrius"
[ -x "$CLI" ] || { echo "SKIP: cyrius CLI missing"; exit 77; }
CC=${CYCC:-"$ROOT/build/cycc"}
cd "$ROOT"
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: stdlib_key_scan_quoted: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/src" "$W/pkg/dist" "$W/home/bin"
# The CLI resolves its tools from its own directory; distlib's verify (axis 4) also needs the
# aarch64 cross compiler, built from this tree.
cp "$CC" "$W/home/bin/cycc" && cp "$CLI" "$W/home/bin/cyrius" \
    && "$CC" < src/main_aarch64.cyr > "$W/home/bin/cycc_aarch64" 2>/dev/null \
    && chmod +x "$W/home/bin/cycc" "$W/home/bin/cyrius" "$W/home/bin/cycc_aarch64" \
    || { echo "SKIP: stdlib_key_scan_quoted: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CLI="$W/home/bin/cyrius"
cp -R "$ROOT/lib" "$W/home/lib"
CYRIUS_HOME="$W/home"; export CYRIUS_HOME
cd "$W/pkg"
fail=0

# The manifest shape that triggers it: `stdlib` inside a quoted description, ABOVE the key.
manifest() {  # manifest <with-stdlib-key: 1|0>
    printf '[package]\nname = "qz"\nversion = "0.1.0"\ndescription = "qz — a thing; foldable into stdlib per sandhi pattern"\n\n' > cyrius.cyml
    [ "$1" = 1 ] && printf '[deps]\nstdlib = ["syscalls", "string"]\n\n' >> cyrius.cyml
    printf '[lib]\nmodules = ["src/a.cyr"]\n' >> cyrius.cyml
}
manifest 1
printf 'fn qz_one(): i64 { return strlen("q"); }\n' > src/a.cyr
printf 'include "src/a.cyr"\n' > src/lib.cyr

# ── axes 1-2: `cyrius deps` finds the REAL key below the quoted 'stdlib' ─────────────────
rc=0; CYRIUS_RESOLVED=1 "$CLI" deps > "$W/log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  FAIL premise: cyrius deps exited $rc; axes would pass vacuously"
    sed -n '1,4p' "$W/log" | sed 's/^/    /'
    echo "FAIL: stdlib-key-scan-quoted"; exit 1
fi
echo "  ok premise: cyrius deps ran"
if [ -f lib/syscalls.cyr ]; then
    echo "  ok axis 1: the declared leaves were vendored despite the quoted 'stdlib' above the key"
else
    echo "  FAIL axis 1: no lib/syscalls.cyr — the scan matched 'stdlib' inside the description and resolved nothing"
    fail=1
fi
if [ -f lib/string.cyr ]; then
    echo "  ok axis 2: both declared leaves present (syscalls, string)"
else
    echo "  FAIL axis 2 (anti-vacuous): lib/string.cyr missing — the key parsed short"; fail=1
fi

# ── axis 4: the published sidecar does not depend on the key ─────────────────────────────
D4=0; CYRIUS_RESOLVED=1 "$CLI" distlib > "$W/d1.log" 2>&1 || D4=$?
if [ "$D4" -eq 0 ] && [ -f dist/qz.deps ]; then cp dist/qz.deps "$W/with.deps"
else echo "  FAIL axis 4 premise: distlib exited $D4 / no sidecar: $(head -3 "$W/d1.log" | tr '\n' ' ')"; fail=1; fi
manifest 0
CYRIUS_RESOLVED=1 "$CLI" distlib > "$W/d2.log" 2>&1 || true
if [ -f "$W/with.deps" ] && cmp -s "$W/with.deps" dist/qz.deps; then
    echo "  ok axis 4: the sidecar is byte-identical with and without a [deps] stdlib key [$(grep -v '^#' dist/qz.deps | tr '\n' ' ')]"
else
    echo "  FAIL axis 4: the sidecar changed when the [deps] stdlib key was removed — declared leaves are being published"; fail=1
fi

cd "$ROOT"
scans=$(grep -c '"stdlib", 6' cbt/commands.cyr cbt/deps.cyr | awk -F: '{s+=$2} END{print s}')
keyed=$(grep -A1 '"stdlib", 6' cbt/commands.cyr cbt/deps.cyr | grep -c '_toml_key_at' || true)
if [ "$scans" -lt 2 ]; then
    echo "  FAIL axis 3: expected at least 2 'stdlib' key scans (cmd_deps, lib-sync), found $scans — the search is wrong, not the tree"
    fail=1
elif [ "$keyed" -lt "$scans" ]; then
    echo "  FAIL axis 3 (structural): $scans stdlib key-scan site(s) but only $keyed guarded by _toml_key_at — a hand-rolled boundary check has been reintroduced"
    fail=1
else
    echo "  ok axis 3: all $scans stdlib key-scan sites route through _toml_key_at"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: stdlib-key-scan-quoted"; exit 1; }
echo "PASS: stdlib-key-scan-quoted — a quoted 'stdlib' never masquerades as the key, in every copy of the scan; the sidecar never depends on the key"
