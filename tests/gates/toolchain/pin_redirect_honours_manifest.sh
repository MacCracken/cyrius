#!/bin/sh
# Gate: a consumer's `cyrius = "X.Y.Z"` pin is HONOURED even when src/main.cyr exists (v6.5.37).
#
# THE DEFECT. `_try_redirect_to_pinned()` decided "am I the cyrius source repo?" with
# `file_exists("src/main.cyr")` and returned early — skipping the pin redirect — when that
# file was present. But `src/main.cyr` is the entry point `cyrius init` GENERATES, so the
# test was true for essentially every cyrius project and the manifest pin was silently
# ignored ecosystem-wide. Measured on 6.5.36, one file's difference in the same repo:
#
#     pinned 6.3.35, no src/main.cyr  ->  cyrius 6.3.35                              (honoured)
#     pinned 6.3.35, + src/main.cyr   ->  cyrius 6.5.36
#                                          "manifest-pin: 6.3.35 (drift — wrapper is 6.5.36)"
#
# ⭐ WHY IT SURVIVED SO LONG: the tool PRINTED the pin it was ignoring, and labelled the
# mismatch "drift". Drift reads as a stale manifest — a consumer problem — so every symptom
# pointed away from the redirect. A gate that only checked `--version` in the cyrius repo
# would never see it; the bug needs a CONSUMER tree with the generated entry point present.
#
# ⚠ THIRD OCCURRENCE OF ONE SHAPE. The same `src/main.cyr` ≠ cyrius-repo conflation was
# fixed in `cyrius audit` (v6.0.1, again v6.4.63) and in `_dep_find_stdlib_dir` (v6.5.25,
# the bote/agnosai/majra filing). The v6.5.25 fix note said outright that
# `_dep_is_cyrius_source_repo()` "exists precisely for this ... never a filename probe" —
# and it was still not applied here. This gate exists so the shape cannot come back a
# fourth time in this function.
#
# Blast radius measured before landing: of ~180 sibling repos, 94 begin honouring a pin
# they had been ignoring and all 94 have that version installed; 0 would hit the
# "pinned version is not installed" hard error.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: pin_redirect_honours_manifest: $1"; exit 1; }

# Pick any installed version that is NOT the current one. Without a second version there is
# nothing to redirect TO, so axes 1 and 3 cannot run — announced by name, never silent.
OTHER=""
if [ -d "$HOMEDIR/versions" ]; then
    for d in "$HOMEDIR"/versions/*/; do
        v=$(basename "$d")
        [ "$v" = "$VER" ] && continue
        [ -x "$d/bin/cyrius" ] || continue
        OTHER="$v"; break
    done
fi

mk() {  # mk <dir> <package-name> <pin> <with-src-main>
    mkdir -p "$WORK/$1"
    printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n' "$2" "$3" > "$WORK/$1/cyrius.cyml"
    if [ "$4" = "yes" ]; then
        mkdir -p "$WORK/$1/src"
        echo 'fn main() { return 0; }' > "$WORK/$1/src/main.cyr"
    fi
}

if [ -z "$OTHER" ]; then
    echo "  axes 1+3 SKIPPED: no second cyrius version installed under $HOMEDIR/versions"
else
    # ── axis 1: THE FIX — a consumer WITH src/main.cyr honours its pin ───────────────
    mk a probe "$OTHER" yes
    GOT=$(cd "$WORK/a" && "$CYRIUS" --version 2>/dev/null | head -1 | awk '{print $2}')
    [ "$GOT" = "$OTHER" ] || fail "axis 1: consumer with src/main.cyr reported '$GOT', expected the pinned '$OTHER' — the redirect was skipped"

    # ── axis 1b: control — the same tree WITHOUT src/main.cyr already worked ─────────
    # If this ever diverges from axis 1, the identity test has started depending on a
    # file again, which is the whole defect class.
    mk b probe "$OTHER" no
    GOTB=$(cd "$WORK/b" && "$CYRIUS" --version 2>/dev/null | head -1 | awk '{print $2}')
    [ "$GOTB" = "$OTHER" ] || fail "axis 1b: control reported '$GOTB', expected '$OTHER'"
    [ "$GOT" = "$GOTB" ] || fail "axis 1b: presence of src/main.cyr changed the result ($GOT vs $GOTB) — the conflation is back"

    # ── axis 3: exact-name match — `cyrius-x` must NOT count as the cyrius repo ──────
    # _dep_is_cyrius_source_repo matches [package].name exactly. A prefix/substring test
    # would silently exempt every cyrius-* project from pinning.
    mk c cyrius-x "$OTHER" yes
    GOTC=$(cd "$WORK/c" && "$CYRIUS" --version 2>/dev/null | head -1 | awk '{print $2}')
    [ "$GOTC" = "$OTHER" ] || fail "axis 3: 'cyrius-x' reported '$GOTC' — it was wrongly treated as the cyrius source repo"
fi

# ── axis 2: ANTI-VACUOUS — a repo named `cyrius` still SKIPS the redirect ────────────
# This is what fails if the guard is deleted rather than corrected. It must run even with
# no second version installed, because it asserts the redirect does NOT happen.
mk d cyrius "0.0.1-absent" yes
set +e
OUT=$(cd "$WORK/d" && "$CYRIUS" --version 2>&1); RC=$?
set -e
[ "$RC" -eq 0 ] || fail "axis 2: a repo named 'cyrius' tried to redirect (exit $RC): $OUT"
GOTD=$(printf '%s' "$OUT" | head -1 | awk '{print $2}')
[ "$GOTD" = "$VER" ] || fail "axis 2: repo named 'cyrius' reported '$GOTD', expected the running $VER"

if [ -z "$OTHER" ]; then
    echo "PASS: pin_redirect_honours_manifest (axis 2 only — no second version installed)"
else
    echo "PASS: pin_redirect_honours_manifest (4 axes: pin honoured with src/main.cyr, control, exact-name, cyrius-repo exempt)"
fi
