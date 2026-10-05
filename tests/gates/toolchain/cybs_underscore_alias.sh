#!/bin/sh
# cybs_underscore_alias.sh — 6.6.17. No two names in the compiler's source may differ only by
# LEADING UNDERSCORES: within one fn (its parameters and locals), and among the top-level fns and
# globals. cybs, the bootstrap compiler the 29 KB seed assembles, does not start an identifier at
# `_` (its lexer dispatch takes a-z / A-Z only), so it reads `_fi` as `fi` and the two are ONE
# variable in the cybs-built cycc (gen1), while build/cycc keeps them apart.
#
# THE INCIDENT. `_PARSE_FN_DEF_IMPL` (src/frontend/parse_fn.cyr) had a local `fi` (the fn index)
# and, in its jump/fixup compaction loop, a counter `_fi`. In gen1 the loop overwrote the fn index,
# so SFNE recorded each fn's code end under the wrong fn and DCE saw no calls. It sat latent until
# 6.6.17 lane srca's growth made gen1 take a path that reads `fi` after the loop: seed-derive went
# RED (gen2 != build/cycc), measured by adding ANY function once the compiler held 2,049 — and it
# reproduces in a 10-fn cybs program (`var fi = x; var _fi = 9; return fi;` returns 9).
#
#   axis 1  the scan of src/main.cyr's include closure finds no such pair (a pair on the allowlist
#           must still exist — the list only shrinks).
#   axis 2  ANTI-VACUOUS: a fixture with a planted local pair and a planted global pair is caught.
#   axis 3  the mechanism, when bootstrap/asm is present: the seed-built cybs runs the 10-fn
#           program and returns 9 (the alias). If cybs ever learns `_`, this row says so — then
#           this gate can retire. SKIP (77) without the seed.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cybs_underscore_alias: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
fail=0

# Global pairs that exist today and are safe by ORDER (each call resolves to the most recently
# defined of the two, which is the one it means). One name per line; SHRINK ONLY.
cat > "$T/allow" <<'EOF'
fn:ir_set_bb
EOF

# scan FILE... -> one line per collision: "LOCAL <file> <fn> <a> <b>" or "GLOBAL <key> <a> <b>"
scan() {
    awk '
    function norm(n) { sub(/^_+/, "", n); return n }
    function flushfn(   k) {
        for (k in seen) delete seen[k]
    }
    function addloc(n,   k) {
        k = norm(n)
        if ((k in seen) && seen[k] != n) print "LOCAL " FILENAME " " fname " " seen[k] " " n
        else seen[k] = n
    }
    function addglob(kind, n,   k) {
        k = kind ":" norm(n)
        if ((k in g) && g[k] != n) print "GLOBAL " k " " g[k] " " n
        else g[k] = n
    }
    FNR == 1 { depth = 0; infn = 0 }
    {
        line = $0
        gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
        sub(/#.*/, "", line)
        if (depth == 0 && match(line, /^fn[ \t]+[A-Za-z_][A-Za-z_0-9]*/)) {
            fname = substr(line, RSTART, RLENGTH); sub(/^fn[ \t]+/, "", fname)
            addglob("fn", fname)
            flushfn(); infn = 1
            p = line; sub(/^[^(]*\(/, "", p); sub(/\).*/, "", p)
            np = split(p, ps, ",")
            for (i = 1; i <= np; i++) { q = ps[i]; sub(/:.*/, "", q); gsub(/[ \t*]/, "", q); if (q != "") addloc(q) }
        } else if (depth == 0 && match(line, /^(pub[ \t]+|public[ \t]+|private[ \t]+)?var[ \t]+[A-Za-z_][A-Za-z_0-9]*/)) {
            v = substr(line, RSTART, RLENGTH); sub(/.*var[ \t]+/, "", v); addglob("var", v)
        }
        if (infn) {
            rest = line
            while (match(rest, /(^|[^A-Za-z_0-9])var[ \t]+[A-Za-z_][A-Za-z_0-9]*/)) {
                v = substr(rest, RSTART, RLENGTH); sub(/.*var[ \t]+/, "", v); addloc(v)
                rest = substr(rest, RSTART + RLENGTH)
            }
        }
        o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line)
        depth += o - c
        if (infn && depth <= 0 && c > 0) { infn = 0; depth = 0 }
    }' "$@"
}

# The include closure of src/main.cyr — what cybs compiles in the seed chain.
closure() {
    todo=src/main.cyr; : > "$T/files"
    while [ -n "$todo" ]; do
        f=${todo%% *}; if [ "$f" = "$todo" ]; then todo=""; else todo=${todo#* }; fi
        grep -qxF "$f" "$T/files" && continue
        [ -f "$f" ] || continue
        echo "$f" >> "$T/files"
        for i in $(sed -n 's/^[ \t]*include[ \t]*"\([^"]*\)".*/\1/p' "$f"); do todo="$todo $i"; done
        todo=$(echo $todo)
    done
}

echo "axis 1 - the cybs-compiled source has no names that differ only by leading underscores:"
closure
n=$(wc -l < "$T/files" | tr -d ' ')
if [ "$n" -lt 20 ]; then echo "  FAIL axis 1: the include closure has only $n files (floor 20)"; fail=1; fi
# shellcheck disable=SC2046
scan $(cat "$T/files") > "$T/hits" || true
while read -r kind a b c d; do
    if [ "$kind" = GLOBAL ] && grep -qxF "$a" "$T/allow"; then continue; fi
    echo "  FAIL axis 1: $kind $a $b $c $d"; fail=1
done < "$T/hits"
while read -r key; do
    grep -q "^GLOBAL $key " "$T/hits" || { echo "  FAIL axis 1: '$key' is allowlisted but no longer collides - take it off"; fail=1; }
done < "$T/allow"
[ "$fail" -eq 0 ] && echo "  ok axis 1: $n files, no collision beyond the allowlist"

echo "axis 2 - a planted pair is caught:"
printf 'var gx = 1;\nvar _gx = 2;\nfn f(a, _b) {\n    var fi = a;\n    var _fi = 2;\n    var b = 3;\n    return fi;\n}\nfn g(x) { var _x = 1; return x; }\n' > "$T/fx.cyr"
scan "$T/fx.cyr" > "$T/fxh" || true
for want in "LOCAL $T/fx.cyr f fi _fi" "LOCAL $T/fx.cyr f _b b" "LOCAL $T/fx.cyr g x _x" "GLOBAL var:gx gx _gx"; do
    if grep -qxF "$want" "$T/fxh"; then echo "  ok axis 2: $want"; else echo "  FAIL axis 2: not reported: $want"; fail=1; fi
done

echo "axis 3 - the mechanism (the seed-built cybs aliases _fi to fi):"
if [ -x bootstrap/asm ] && [ -f bootstrap/cybs.cyr ]; then
    bootstrap/asm < bootstrap/cybs.cyr > "$T/cybs" 2> /dev/null && chmod +x "$T/cybs"
    printf 'fn d0(a) { return a; }\nfn t(x) { var fi = x; var y = 5; var _fi = 9; return fi; }\nsyscall(60, t(3));\n' > "$T/m.cyr"
    "$T/cybs" < "$T/m.cyr" > "$T/m" 2> /dev/null && chmod +x "$T/m"
    rc=0; "$T/m" || rc=$?
    if [ "$rc" -eq 9 ]; then echo "  ok axis 3: cybs reads _fi as fi (exit 9) - axis 1 is load-bearing"
    elif [ "$rc" -eq 3 ]; then echo "  NOTE axis 3: cybs now keeps _fi and fi apart (exit 3) - this gate can retire"
    else echo "  FAIL axis 3: the probe exited $rc (want 9, or 3 once cybs learns _)"; fail=1; fi
else
    echo "  SKIP axis 3: bootstrap/asm absent"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_underscore_alias"; exit 1; fi
echo "PASS: cybs_underscore_alias"
exit 0
