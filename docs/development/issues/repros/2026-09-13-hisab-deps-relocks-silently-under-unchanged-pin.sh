#!/bin/sh
# Repro: `cyrius build` (via its implicit `deps` step) silently RE-LOCKS a stdlib
# file whose content changed in the pinned snapshot while the manifest pin did
# not change — and `deps --verify` then reports the mutated content as verified.
#
# Proves itself:
#   exit 0  -> fixed: the lock hash is untouched (build refused, or warned and
#              left cyrius.lock alone)
#   exit 1  -> bug present: the lock hash moved with no diagnostic
#
# Self-contained: stages a THROWAWAY CYRIUS_HOME copied from the installed pin,
# so nothing under ~/.cyrius is touched. Needs network once (the sakshi git dep —
# a lock is only written when a git dep exists, which is every real consumer).
#
# Filed 2026-09-13 by hisab (3.0.1 bump). See
# docs/development/issues/2026-09-13-hisab-deps-relocks-silently-under-unchanged-pin.md
set -eu
PIN="${PIN:-6.6.3}"
SRC="$HOME/.cyrius/versions/$PIN"
[ -d "$SRC/lib" ] || { echo "no installed toolchain at $SRC"; exit 2; }
T="$(mktemp -d)"
H="$T/home"; P="$T/consumer"
mkdir -p "$H/versions" "$P"
cp -r "$SRC" "$H/versions/$PIN"
echo "$PIN" > "$H/current"
ln -sfn "versions/$PIN/bin" "$H/bin"
ln -sfn "versions/$PIN/lib" "$H/lib"
export CYRIUS_HOME="$H"
CY="$H/bin/cyrius"

cd "$P"
cat > cyrius.cyml <<EOF
[package]
name = "relock"
version = "0.0.1"
language = "cyrius"
cyrius = "$PIN"

[build]
src = "main.cyr"
output = "out"

[deps]
stdlib = ["syscalls", "math"]

[deps.sakshi]
git = "https://github.com/MacCracken/sakshi.git"
tag = "2.5.2"
modules = ["dist/sakshi.cyr"]
EOF
printf 'fn main() { return 0; }\nvar rc = main();\nsys_exit_group(rc);\n' > main.cyr

# 1. resolve + lock, and confirm the lock verifies
"$CY" deps >/dev/null 2>&1
before="$(grep ' lib/math.cyr$' cyrius.lock | cut -d' ' -f1)"
[ -n "$before" ] || { echo "no lib/math.cyr entry in cyrius.lock"; exit 2; }
"$CY" deps --verify >/dev/null 2>&1 || { echo "fresh lock does not verify"; exit 2; }

# 2. mutate ONE comment line of the pinned snapshot; the manifest pin is unchanged
sed -i '1s/^/# snapshot mutated under an unchanged pin\n/' "$H/versions/$PIN/lib/math.cyr"

# 3. an ordinary build — no manifest edit, no `deps` asked for
out="$("$CY" build main.cyr ./out 2>&1)" || true
after="$(grep ' lib/math.cyr$' cyrius.lock | cut -d' ' -f1)"

echo "lock hash for lib/math.cyr:  before=$before"
echo "                              after =$after"
echo "build output:"; printf '%s\n' "$out" | sed 's/^/    /'

# 4. verdict
if [ "$before" = "$after" ]; then
    echo "OK: lock untouched under an unchanged pin"
    rm -rf "$T"; exit 0
fi
# The routine "cyrius.lock: N deps locked" line is NOT a diagnostic — exclude it.
if printf '%s\n' "$out" | grep -v 'deps locked' | grep -qiE 'hash|changed|mutat|differ|mismatch|stale|shadow'; then
    echo "PARTIAL: lock moved but a diagnostic named it (acceptable only if it is loud)"
    rm -rf "$T"; exit 1
fi
"$CY" deps --verify >/dev/null 2>&1 && v="verify PASSES on the mutated content" || v="verify fails"
echo "BUG: lock re-written silently under an unchanged pin ($v)"
rm -rf "$T"; exit 1
