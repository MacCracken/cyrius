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
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CLI="$ROOT/build/cyrius"
[ -x "$CLI" ] || CLI="$HOME/.cyrius/bin/cyrius"
[ -x "$CLI" ] || { echo "SKIP: cyrius CLI missing"; exit 0; }
cd "$ROOT"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/src" "$W/pkg/dist" "$W/home/bin"
cp "$ROOT/build/cycc" "$W/home/bin/cycc"; chmod +x "$W/home/bin/cycc"
cp -R "$ROOT/lib" "$W/home/lib"
CYRIUS_HOME="$W/home"; export CYRIUS_HOME
cd "$W/pkg"
fail=0

# The manifest shape that triggers it: `stdlib` inside a quoted description, ABOVE the key.
cat > cyrius.cyml <<'EOF'
[package]
name = "qz"
version = "0.1.0"
description = "qz — a thing; foldable into stdlib per sandhi pattern"

[deps]
stdlib = ["syscalls", "string"]

[lib]
modules = ["src/a.cyr"]
EOF
cat > src/a.cyr <<'EOF'
fn qz_one(): i64 { return 1; }
EOF
cat > src/lib.cyr <<'EOF'
include "src/a.cyr"
EOF

"$CLI" distlib > "$W/log" 2>&1 || true

# PREMISE — without a bundle every axis below is vacuous.
if [ ! -f dist/qz.cyr ]; then
    echo "  FAIL premise: no bundle produced; axes would pass vacuously"
    sed -n '1,4p' "$W/log" | sed 's/^/    /'
    echo "FAIL: stdlib-key-scan-quoted"; exit 1
fi
echo "  ok premise: bundle built"

# --- axis 1: THE FILED SYMPTOM — a sidecar must exist ---
if [ ! -f dist/qz.deps ]; then
    echo "  FAIL axis 1: no dist/qz.deps — the scan matched 'stdlib' inside the description and returned no leaves"
    fail=1
else
    echo "  ok axis 1: sidecar emitted despite the quoted 'stdlib' above the key"
fi

# --- axis 2 (ANTI-VACUOUS): it must carry the DECLARED leaves, not just exist ---
# Emitting an empty sidecar would satisfy axis 1 while leaving the consumer with nothing.
if [ -f dist/qz.deps ]; then
    L=$(grep -v '^#' dist/qz.deps | grep -v '^$' | sort | tr '\n' ' ')
    case " $L " in
        *" syscalls "*) case " $L " in
            *" string "*) echo "  ok axis 2: both declared leaves present [$L]" ;;
            *) echo "  FAIL axis 2 (anti-vacuous): 'string' missing from [$L]"; fail=1 ;;
        esac ;;
        *) echo "  FAIL axis 2 (anti-vacuous): 'syscalls' missing from [$L] — sidecar exists but is empty/wrong"; fail=1 ;;
    esac
fi

# --- axis 3 (STRUCTURAL — the "grep the shape" axis) ---
# Every `"stdlib", 6` scan must go through the shared `_toml_key_at` helper. This is what
# stops the fix regressing in ONE copy again: a hand-rolled boundary check reintroduced
# anywhere fails here even if axes 1-2 stay green (they only exercise the distlib path).
cd "$ROOT"
scans=$(grep -c '"stdlib", 6' cbt/commands.cyr cbt/deps.cyr | awk -F: '{s+=$2} END{print s}')
keyed=$(grep -A1 '"stdlib", 6' cbt/commands.cyr cbt/deps.cyr | grep -c '_toml_key_at' || true)
if [ "$scans" -lt 3 ]; then
    echo "  FAIL axis 3: expected at least 3 'stdlib' key scans, found $scans — the search is wrong, not the tree"
    fail=1
elif [ "$keyed" -lt "$scans" ]; then
    echo "  FAIL axis 3 (structural): $scans stdlib key-scan site(s) but only $keyed guarded by _toml_key_at — a hand-rolled boundary check has been reintroduced"
    fail=1
else
    echo "  ok axis 3: all $scans stdlib key-scan sites route through _toml_key_at"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: stdlib-key-scan-quoted"; exit 1; }
echo "PASS: stdlib-key-scan-quoted — a quoted 'stdlib' never masquerades as the key, in every copy of the scan"
