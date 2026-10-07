#!/bin/sh
# v6.5.28 — `_distlib_named_deps` must recognise a `[deps.X]` SECTION HEADER only, never the
# same text appearing in comment prose.
#
# THE BUG. The exclude-set scan matched the literal `[deps.` ANYWHERE in the manifest buffer
# with no line anchoring (`cbt/commands.cyr`), so a comment explaining the layout registered
# its example dep as a real one. Because that set means "this is a fold, not a stdlib leaf",
# the named leaf was then EXCLUDED from the generated `.deps` sidecar. Filed from patra
# (11 leaves emitted against 12 declared, `sakshi` missing) and confirmed in libro.
# Silent packaging corruption: the BUNDLE stays correct, so nothing fails — only a clean-room
# consumer resolving from the sidecar comes up short, which is what the sidecar is FOR.
#
# ⚠ THE UPSTREAM SYMPTOM NO LONGER REPRODUCES. At patra 1.13.8 the manifest contains no
# `[deps.` text at all (the triggering comment was removed upstream), so the end-to-end
# repro in the filing is gone. This gate therefore tests the PARSER RULE directly rather than
# re-staging a consumer tree — a defect whose only witness has been edited away still needs a
# regression test, and one that depends on a third-party file staying wrong is not a test.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
fail=0
#
# 6.6.20 — axes 1-3 were GREPS FOR THE OLD SCANNER'S TEXT (`bol == 1 && ndi + 6 …`, `in_cmt = 1`,
# `vec_push(named_deps, nd)`), so they pinned an implementation, not the rule — and the rule had
# a hole they could not see: a `[deps.X]` at the start of a line INSIDE a `"""` value registered
# X. `_distlib_named_deps` now reads headers through the resolver's own rule (`_dep_hdr_name` on
# `_toml_line`, cbt/deps.cyr), and these axes test the RULE: a built CLI, a manifest, and the
# `--modular` index it writes (a named dep's leaf is left out of the index; any other is listed).
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: distlib-named-deps-anchored: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: distlib-named-deps-anchored: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
if [ -n "${CYRIUS_GATE_CLI:-}" ]; then cp "$CYRIUS_GATE_CLI" "$W/cyrius"
else cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null || { echo "FAIL: distlib-named-deps-anchored: cbt/cyrius.cyr does not build"; exit 1; }
fi
chmod +x "$W/cyrius"
P="$W/q"; mkdir -p "$P/src"
cat > "$P/cyrius.cyml" <<'EOF'
[package]
name = "q"
version = "0.0.1"
language = "cyrius"
description = """
To vendor us, write:
[deps.fmt]
"""

# [deps.math] — layout notes: a comment that BEGINS with a header
  # [deps.alloc] — and an indented one

[lib]
modules = ["src/a.cyr"]

  [deps.str]
path = "../nowhere"
modules = []

[ deps.vec ]
path = "../nowhere"
modules = []
EOF
printf 'include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/math.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
fn q_a(): i64 { return 4; }
' > "$P/src/a.cyr"
rc=0; ( cd "$P" && "$W/cyrius" distlib --modular > "$W/out" 2>&1 ) || rc=$?
IDX="$P/dist/q/index.cyml"
row=$(grep '^a = ' "$IDX" 2>/dev/null || true)
# axis 1 — comment prose (at column 0 and indented) does not register a dep.
case "$row" in
    *'"lib:math"'*'"lib:alloc"'*) echo "  ok axis 1: a commented [deps.math] / indented # [deps.alloc] register nothing (both leaves listed)" ;;
    *) echo "  FAIL axis 1: a commented [deps.X] excluded its leaf (rc=$rc): [$row] $(head -2 "$W/out")"; fail=1 ;;
esac
# axis 2 — a `[deps.X]` line inside a multi-line string value is not a header.
case "$row" in
    *'"lib:fmt"'*) echo "  ok axis 2: a [deps.fmt] inside a \"\"\" description registers nothing (lib:fmt listed)" ;;
    *) echo "  FAIL axis 2: a [deps.fmt] inside a multi-line string excluded its leaf: [$row]"; fail=1 ;;
esac
# axis 3 (ANTI-VACUOUS) — real headers, indented or spaced, ARE collected.
if [ "$rc" -eq 0 ] && [ -n "$row" ] && ! printf '%s' "$row" | grep -q 'lib:str"\|lib:vec"'; then
    echo "  ok axis 3: the real '  [deps.str]' and '[ deps.vec ]' headers exclude their leaves"
else
    echo "  FAIL axis 3 (anti-vacuous): rc=$rc, a real [deps.X] header was not collected: [$row]"; fail=1
fi

# axis 4 (BEHAVIOURAL) — a real consumer's sidecar must still be complete.
# patra declares its stdlib leaves and is the tree the defect was filed from.
P="$HOME/Repos/patra"
if [ -f "$P/dist/patra.deps" ]; then
    n=$(grep -cv '^#' "$P/dist/patra.deps" || true)
    if [ "$n" -ge 12 ]; then
        echo "  ok axis 4: patra's sidecar carries $n leaves (>= 12)"
    else
        echo "  FAIL axis 4: patra's sidecar carries only $n leaves — a leaf is being excluded again"
        fail=1
    fi
else
    echo "  note axis 4: ~/Repos/patra/dist/patra.deps absent — skipped"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: distlib-named-deps-anchored"; exit 1; }
echo "PASS: distlib-named-deps-anchored — only real [deps.X] section headers register, comment prose does not"
