#!/bin/sh
# Gate: `cyrius deps` reports failure as a BOOLEAN exit status, not an error count (v6.5.37).
#
# THE DEFECT. `cmd_deps` / `cmd_update` returned the raw error COUNT, which becomes the
# process exit status — and a wait status carries only the low 8 bits. Measured at 6.5.36:
#
#     1 bad leaf  -> exit 1      255 -> exit 255      256 -> exit 0      512 -> exit 0
#
# So a manifest broken badly enough reported SUCCESS, and every error count that is a
# multiple of 256 was a silent green. `_auto_deps` propagated the same value, so
# `cyrius build` exited 0 too.
#
# ⭐ WHY THIS IS THE GATE THE OTHER SIDECAR GATES DEPEND ON: it is the reason a defective
# sidecar could pass CI at all, and the failure is ANTI-CORRELATED with severity — the more
# leaves a bundle got wrong, the likelier the resolve looked clean. A 256-leaf sidecar is not
# exotic; the largest ecosystem sidecars carry 38 leaves and the resolver expands families
# and transitive closures on top of that.
#
# ⛔ THE COUNT MUST BE 256, NOT 1. A "fix" that preserves the count (say, returning
# `errors` capped at 255) passes a 1-error test and every small-N test, while leaving the
# exact wrap that caused the bug. Axis 2 is the only axis that fails against the real defect.
# Axis 4 is anti-vacuous: a CLEAN resolve must still exit 0, or a guard that simply returns 1
# unconditionally would pass axes 1-3.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
VER=$(cat "$ROOT/VERSION")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: deps_exit_code_clamped: $1"; exit 1; }

# Build a manifest whose [deps] stdlib names N leaves that cannot resolve.
mk_bad() {
    n="$1"; d="$WORK/bad$n"; mkdir -p "$d"
    {
        printf '[package]\nname = "probe"\nversion = "0.1.0"\ncyrius = "%s"\n[deps]\nstdlib = [' "$VER"
        i=0
        while [ "$i" -lt "$n" ]; do
            [ "$i" -gt 0 ] && printf ','
            printf '"nosuchleaf%d"' "$i"
            i=$((i + 1))
        done
        printf ']\n'
    } > "$d/cyrius.cyml"
    echo "$d"
}

run_rc() { set +e; ( cd "$1" && "$CYRIUS" deps >/dev/null 2>&1 ); rc=$?; set -e; echo "$rc"; }

# ── axis 1: a single failure is still a failure ─────────────────────────────────────
RC1=$(run_rc "$(mk_bad 1)")
[ "$RC1" -ne 0 ] || fail "axis 1: 1 unresolvable leaf exited 0"

# ── axis 2: THE DEFECT — 256 failures must not wrap to 0 ────────────────────────────
RC256=$(run_rc "$(mk_bad 256)")
[ "$RC256" -ne 0 ] || fail "axis 2: 256 unresolvable leaves exited 0 — the count is being returned as the exit status and wrapped"

# ── axis 3: a second multiple of 256, so a 256-specific special-case cannot pass ────
RC512=$(run_rc "$(mk_bad 512)")
[ "$RC512" -ne 0 ] || fail "axis 3: 512 unresolvable leaves exited 0"

# ── axis 4: ANTI-VACUOUS — a clean resolve still succeeds ───────────────────────────
# Without this, `return 1` unconditionally passes every axis above.
CLEAN="$WORK/clean"; mkdir -p "$CLEAN"
cat > "$CLEAN/cyrius.cyml" <<EOF
[package]
name = "probe"
version = "0.1.0"
cyrius = "$VER"
[deps]
stdlib = ["alloc", "io"]
EOF
RCOK=$(run_rc "$CLEAN")
[ "$RCOK" -eq 0 ] || fail "axis 4: a CLEAN resolve exited $RCOK — the clamp is failing valid manifests"
COUNT=$(ls "$CLEAN"/lib/*.cyr 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -gt 0 ] || fail "axis 4: clean resolve vendored 0 files — exit 0 was vacuous"

echo "PASS: deps_exit_code_clamped (4 axes: 1, 256, 512 all non-zero; clean resolve still 0)"
