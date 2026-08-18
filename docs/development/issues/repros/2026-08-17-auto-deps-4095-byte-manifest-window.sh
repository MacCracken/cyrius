#!/usr/bin/env bash
# Repro: `_auto_deps` reads only the first 4095 bytes of cyrius.cyml, so a
# `[deps]` section pushed past that byte is INVISIBLE to `cyrius build`.
# No warning is printed; nothing is prepended; the build dies on undefined
# stdlib symbols in the consumer's own source.
#
# Two builds. IDENTICAL manifest content. Only the length of a COMMENT
# ABOVE `[deps]` differs, which moves the marker across byte 4095.
#
# Usage: ./2026-08-17-auto-deps-4095-byte-manifest-window.sh [cycc-version]
set -u
V="${1:-6.5.27}"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/src"

cat > "$D/src/main.cyr" <<'EOF'
fn main(): i64 {
    var v = vec_new();
    vec_push(v, 1);
    return vec_len(v) - 1;
}
var r = main();
syscall(60, 0);
EOF

# Build a manifest whose `[deps]` marker starts at approximately $1 bytes.
case_run() {
    local label="$1" target="$2"
    python3 - "$D" "$V" "$target" <<'PY'
import sys, io, os
d, v, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
head = f'''[package]
name = "winrepro"
version = "0.1.0"
language = "cyrius"
cyrius = "{v}"

[build]
entry = "src/main.cyr"
output = "build/winrepro"

'''
tail = '''[deps]
stdlib = ["syscalls", "alloc", "vec"]
'''
pad = target - len(head)
filler = ''
if pad > 0:
    line = '# ' + 'x' * 76 + '\n'          # 79 bytes
    filler = line * (pad // len(line))
    rem = pad - len(filler)
    if rem >= 3:
        filler += '# ' + 'y' * (rem - 3) + '\n'
    else:
        filler += ' ' * rem
io.open(os.path.join(d, 'cyrius.cyml'), 'w').write(head + filler + tail)
PY
    rm -rf "$D/lib" "$D/build"; mkdir -p "$D/build"
    local off out
    off=$(python3 -c "
b=open('$D/cyrius.cyml','rb').read()
c=[x for x in (b.find(b'[deps]'), b.find(b'[deps.')) if x>=0]
print(min(c) if c else -1)")
    out=$(cd "$D" && CYRIUS_NO_WARN_SHADOW_LIB=1 cyrius build src/main.cyr build/winrepro 2>&1)
    echo "$label"
    echo "    '[deps]' starts at byte : $off"
    echo "    lib/ populated by build : $([ -d "$D/lib" ] && ls "$D/lib" | wc -l || echo 0) module(s)"
    echo "    any mention of the manifest in output: $(printf '%s' "$out" | grep -ci 'cyrius.cyml\|\[deps\]')"
    echo "    binary emitted          : $([ -f "$D/build/winrepro" ] && echo YES || echo NO)"
}

echo "=== cycc $V ==="
case_run "CASE A — [deps] at ~4000 bytes (inside the window)" 4000
echo
case_run "CASE B — [deps] at ~4200 bytes (past the window)"   4200
