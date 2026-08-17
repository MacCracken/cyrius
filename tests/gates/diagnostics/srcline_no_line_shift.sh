#!/bin/sh
# v6.5.24 — `<source>` diagnostic line numbers must match the ENTRY FILE's own numbering,
# no matter what `cyrius build` prepends in front of it.
#
# THE BUG. cbt prepends `#@incdir`, `#@pkgver`, one `include` per `[deps].stdlib` module,
# one `#define` per `-D`, and the entire text of every `[build].modules` file. Only
# `#@incdir` was ever compensated, so every `<source>` diagnostic was reported one line
# late PER PREPENDED LINE. Measured at 6.5.21 on abaco (18 stdlib modules): every
# diagnostic off by +17, and on a 23-line file that pointed to line 30 — PAST EOF, which
# reads as a compiler fault rather than a source defect, so the reader stops trusting line
# numbers instead of adjusting them.
# Filed: 2026-08-13-source-diag-line-shift-scales-with-deps-stdlib.
#
# THE FIX. cbt writes `#@srcline` as the last thing before the entry file, and cycc
# re-anchors the `<source>` span to line 1 there. The marker carries NO count — cycc
# derives the bias from the marker's own position — because a count would drift, and
# because `[build].modules` splices in whole files of unknown length.
#
# ⭐ AXIS 3 IS THE POINT OF THE GATE. The changelog had framed this as a "+1" rounding
# error; the filing's contribution was that it SCALES. Axis 3 uses three times the modules
# of axis 2 and demands the SAME reported line, so a fix that merely shifted the constant
# by one cannot pass.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
command -v cyrius >/dev/null 2>&1 || { echo "SKIP: cyrius CLI not on PATH"; exit 0; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# The probe's error is on ITS OWN line 3, in every variant below.
mkprobe() {
    printf 'fn main(): i64 {\n'                        >  "$1"
    printf '    var a = 1;\n'                          >> "$1"
    printf '    a = nonexistent_variable_xyz;\n'       >> "$1"
    printf '    return a;\n'                           >> "$1"
    printf '}\n'                                       >> "$1"
    printf 'var ec = main();\n'                        >> "$1"
    printf 'syscall(60, ec);\n'                        >> "$1"
}
EXPECT=3
fail=0

# Report the line cycc attributed the error to, or "none".
reported() {
    ln=$(cd "$1" && cyrius build "$2" out 2>&1 \
         | grep -o "<source>:[0-9]*" | head -1 | cut -d: -f2)
    [ -n "$ln" ] || ln="none"
    echo "$ln"
}

check() {
    if [ "$2" = "none" ]; then
        echo "  FAIL $1: no <source> diagnostic was produced — the probe stopped erroring, so this axis proves nothing"
        fail=1
    elif [ "$2" != "$EXPECT" ]; then
        echo "  FAIL $1: error is on entry-file line $EXPECT but was reported at line $2 (shift +$(( $2 - EXPECT )))"
        fail=1
    else
        echo "  ok $1: reported line $2 == entry-file line $EXPECT"
    fi
}

# --- axis 1: no manifest at all (nothing prepended) — the always-correct baseline ---
mkdir -p "$W/bare" && mkprobe "$W/bare/probe.cyr"
check "axis 1 (no manifest)" "$(reported "$W/bare" probe.cyr)"

# --- axis 2: a modest [deps].stdlib list ---
mkdir -p "$W/six" && mkprobe "$W/six/probe.cyr"
cat > "$W/six/cyrius.cyml" <<'EOF'
[package]
name = "six"
version = "0.1.0"

[deps]
stdlib = ["syscalls", "str", "vec", "io", "alloc", "assert"]
EOF
check "axis 2 (6 stdlib modules)" "$(reported "$W/six" probe.cyr)"

# --- axis 3: 3x the modules must give the SAME answer (the scaling claim) ---
mkdir -p "$W/many" && mkprobe "$W/many/probe.cyr"
cat > "$W/many/cyrius.cyml" <<'EOF'
[package]
name = "many"
version = "0.1.0"

[deps]
stdlib = ["syscalls", "str", "vec", "io", "alloc", "assert", "fmt", "string",
          "fs", "math", "hashmap", "chrono", "random", "flags", "result",
          "process", "tagged", "bounds"]
EOF
check "axis 3 (18 stdlib modules — must NOT scale)" "$(reported "$W/many" probe.cyr)"

# --- axis 4: entry file in a SUBDIRECTORY, which adds the `#@incdir` prepend too ---
mkdir -p "$W/sub/src" && mkprobe "$W/sub/src/probe.cyr"
cat > "$W/sub/cyrius.cyml" <<'EOF'
[package]
name = "sub"
version = "0.1.0"

[deps]
stdlib = ["syscalls", "str", "vec"]
EOF
check "axis 4 (subdir entry: #@incdir + #@pkgver + 3 includes)" "$(reported "$W/sub" src/probe.cyr)"

[ "$fail" -eq 0 ] || { echo "FAIL: srcline-no-line-shift"; exit 1; }
echo "PASS: srcline-no-line-shift — <source> line numbers match the entry file across 0/6/18 modules and a subdir entry"
