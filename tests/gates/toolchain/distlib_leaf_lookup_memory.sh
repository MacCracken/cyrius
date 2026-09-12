#!/bin/sh
# Gate: `cyrius distlib`'s leaf lookup does not re-read the whole stdlib snapshot per symbol.
#
# THE DEFECT (v6.6.3). `_distlib_leaf_defining` `dir_list`ed the stdlib snapshot and
# `alloc` + read EVERY `.cyr` file on EVERY call, and the verify fixpoint calls it ONCE PER
# UNDEFINED SYMBOL. cyrius's allocator is an arena that never frees, so the cost was
# O(symbols x snapshot bytes) in RETAINED memory:
#
#     110 files / 7 MB snapshot  x  ~2,900 undefined symbols  =  ~20 GB
#
# Measured on bote 3.3.8's full profile: peak RSS 20,320 MB under a 20 GB cap (rc=139),
# 31,214 MB uncapped on a 59 GB box. A GitHub runner has ~7 GB, so the KERNEL OOM-KILLER
# takes the runner down mid-step and GitHub reports it as `Error: The operation was
# canceled` — an infrastructure hiccup, two steps before any assertion runs. It cost a
# release cut to diagnose, and bote shipped a `ulimit -v` workaround in both workflows.
#
# ⭐ Why it tracked the LEAF GRAPH and not module count: what scales is the number of
# symbols left UNDEFINED, not the number of modules. kavach (44 modules), sankhya (36) and
# hisab (35) all completed while bote's 30-module full profile died — and bote's own `core`
# profile, same repo and fewer leaves, finished in 2 GB.
#
# WHAT THIS GATE MEASURES. Peak RSS of `cyrius distlib` on a fixture that leaves ~160 real
# stdlib symbols undefined. Measured on this fixture: OLD 772 MB, FIXED under the 0.2 s
# sampling floor. The threshold sits between with wide margin in both directions.
#
# ⚠ rc IS DELIBERATELY IGNORED. The fixture's generated calls do not match real arities, so
# the bundle self-check refuses it and distlib exits 1 — BOTH before and after the fix. The
# memory path under test runs to completion first, which is what the `dist/*.deps` check
# below proves. Asserting rc=0 here would test the fixture, not the defect.
#
# ⛔ THE SIDECAR CHECK IS THE ANTI-VACUOUS HALF: without it a fixture that failed to run at
# all would report ~0 MB and PASS while guarding nothing.
#
# Mutation-proven: restoring the per-call read (drop `_distlib_snap_cache`) takes this
# fixture to 772 MB and reddens the threshold.
#
# See docs/development/issues/2026-09-11-distlib-leaf-validation-oom.md
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: distlib_leaf_lookup_memory: build/cycc missing"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_leaf_lookup_memory: $1"; exit 1; }

V=$(cat "$ROOT/VERSION")
SNAP="$HOME/.cyrius/versions/$V/lib"
[ -d "$SNAP" ] || { echo "SKIP: no stdlib snapshot for $V (install not refreshed)"; exit 0; }

( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$WORK/cyrius" ) 2>/dev/null \
    || fail "could not build cbt/cyrius.cyr with build/cycc"
chmod +x "$WORK/cyrius"

# Fixture: reference ~160 REAL stdlib fn names with NO leaves declared, so each one comes
# back undefined and drives one _distlib_leaf_defining lookup.
P="$WORK/proj"; mkdir -p "$P/src"
grep -hoE '^(pub |public )?fn [a-z_][a-z_0-9]*' "$SNAP"/*.cyr \
    | awk '{print $NF}' | sort -u | head -160 > "$WORK/syms"
NSYM=$(wc -l < "$WORK/syms")
[ "$NSYM" -ge 100 ] || fail "fixture generator found only $NSYM stdlib fns — too few to load the lookup"

{ echo 'fn dlgate_touch(): i64 {'; echo '    var acc = 0;'
  while read -r s; do echo "    acc = acc + $s();"; done < "$WORK/syms"
  echo '    return acc;'; echo '}'; } > "$P/src/mod.cyr"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "dlgate"
version = "0.1.0"
language = "cyrius"
cyrius = "$V"

[lib]
modules = ["src/mod.cyr"]

[deps]
stdlib = []
EOF

( cd "$P" && "$WORK/cyrius" distlib > "$WORK/dl.log" 2>&1 ) &
DLPID=$!
PEAK=0
while kill -0 "$DLPID" 2>/dev/null; do
    CUR=$(ps -eo rss,comm --no-headers 2>/dev/null | awk '$2=="cyrius"{s+=$1} END{print s+0}')
    [ "${CUR:-0}" -gt "$PEAK" ] && PEAK=$CUR
    sleep 0.2
done
wait "$DLPID" 2>/dev/null || true
PEAK_MB=$((PEAK / 1024))

# anti-vacuous: the verify pass must actually have run and emitted its sidecar
[ -f "$P/dist/dlgate.deps" ] \
    || { sed 's/^/    /' "$WORK/dl.log"; fail "no dist/dlgate.deps — the verify path never ran, so the memory number guards nothing"; }

LIMIT=256
[ "$PEAK_MB" -lt "$LIMIT" ] \
    || fail "peak RSS ${PEAK_MB} MB exceeds ${LIMIT} MB on ${NSYM} undefined symbols — the per-symbol snapshot re-read is back"

echo "PASS: distlib_leaf_lookup_memory (${NSYM} undefined symbols, peak ${PEAK_MB} MB < ${LIMIT} MB)"
