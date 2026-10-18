#!/bin/sh
# DX-01 (v6.3.23) rot-guard: the CYRIUS_SYMS function-symbol dump must emit on
# BOTH x86 and aarch64. The dump was x86-ELF-only for many minors and the aarch64
# path silently emitted nothing — exactly the "found by ports" rot CLAUDE.md warns
# about. v6.3.23 hoisted the emit into the shared _emit_sym_dump(S, base) called
# from both backends; this gate proves the parity holds so it can't rot again.
#
# Mechanism: compile a one-function program with CYRIUS_SYMS set, once with the
# native x86 build/cycc and once with an x86-hosted aarch64 cross-compiler built
# from src/main_aarch64.cyr, and assert each writes a "<16-hex VA> <name>" line for
# the function. The cross-compiler runs on x86 (it only EMITS aarch64), so the file
# write happens host-side with aarch64 VAs — no ARM hardware needed for this check.
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || { echo "FAIL: dx01_syms_parity: cannot cd to $ROOT"; exit 1; }
CYCC="${CYCC:-$ROOT/build/cycc}"
TMP=$(mktemp -d) && [ -d "$TMP" ] || { echo "FAIL: dx01_syms_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

printf 'fn dx01_helper(x) { return x + 1; }\nvar r = dx01_helper(41);\n' > "$TMP/p.cyr"

# ── x86 (native) ──
CYRIUS_SYMS="$TMP/x86.syms" "$CYCC" < "$TMP/p.cyr" > "$TMP/x86.bin" 2>/dev/null
if ! grep -Eq '^[0-9a-f]{16} dx01_helper$' "$TMP/x86.syms"; then
    echo "FAIL: x86 CYRIUS_SYMS did not emit a 'VA dx01_helper' line"
    exit 1
fi

# ── aarch64 (x86-hosted cross-compiler, built from source) ──
"$CYCC" < "$ROOT/src/main_aarch64.cyr" > "$TMP/cc_a64"
chmod +x "$TMP/cc_a64"
CYRIUS_SYMS="$TMP/a64.syms" "$TMP/cc_a64" < "$TMP/p.cyr" > "$TMP/a64.bin"
if ! grep -Eq '^[0-9a-f]{16} dx01_helper$' "$TMP/a64.syms"; then
    echo "FAIL: aarch64 CYRIUS_SYMS did not emit a 'VA dx01_helper' line (parity regression)"
    exit 1
fi

# ── 6.7.14: under CYRIUS_DCE=1 the map describes the COMPACTED image ──
# The dump ran before the dead-code sweep and compaction, so the filed sy.cyr's map named the
# removed dead_a at live_fn's address and put live_fn and main 84 bytes high — the plain build's
# addresses. Each listed address must be a `push %rbp` (55) in .text that some call (e8 rel32)
# reaches, dead_a must be absent, and live_fn / main must sit exactly ELIM bytes below the plain
# build's — on W^X and CYRIUS_WX=0. Without CYRIUS_DCE the map is the plain build's, dead_a
# included. Mutations (6.7.14): the second dump dropped -> RED (dead_a listed, every address 84 B
# high); its skip bitmap dropped -> RED (dead_a listed at live_fn's address).
# issues/archived/2026-10-13-cyrius-syms-pre-compaction-addresses-under-dce.md
cat > "$TMP/sy.cyr" <<'EOF'
fn dead_a(x): i64 { var q = x * 3; return q + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
symcheck() {   # <map> <elf>: every listed VA is a push %rbp in .text that an e8 call reaches
    set -- "$1" "$2" $(readelf -SW "$2" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == ".text") { print $(i + 2), $(i + 3), $(i + 4); exit } }')
    [ -n "${5:-}" ] || { echo "no .text in $2"; return 1; }
    od -An -tx1 -v -j $((0x$4)) -N $((0x$5)) "$2" | tr -s ' ' '\n' | grep -v '^$' > "$TMP/text.hex"
    awk -v base=$((0x$3)) -v map="$1" '
        function hex(h,   i, v) { v = 0; h = tolower(h); for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1; return v }
        { b[n++] = $1 }
        END {
            for (p = 0; p + 5 <= n; p++) if (b[p] == "e8") {
                r = 0; for (k = 4; k >= 1; k--) r = r * 256 + hex(b[p + k])
                if (r >= 2147483648) r -= 4294967296
                called[p + 5 + r] = 1
            }
            bad = 0
            while ((getline line < map) > 0) {
                split(line, f, " "); va = hex(f[1]); off = va - base
                if (off < 0 || off >= n || b[off] != "55") { print f[2] " at " f[1] " is not a push %rbp"; bad = 1 }
                else if (!(off in called)) { print f[2] " at " f[1] " is reached by no call"; bad = 1 }
            }
            exit bad
        }' "$TMP/text.hex"
}
va_of() { awk -v n="$2" '$2 == n { print $1 }' "$1"; }
for WX in 1 0; do
    CYRIUS_WX=$WX CYRIUS_SYMS="$TMP/p$WX.syms" "$CYCC" < "$TMP/sy.cyr" > "$TMP/p$WX.bin" 2>/dev/null
    CYRIUS_DCE=1 CYRIUS_WX=$WX CYRIUS_SYMS="$TMP/d$WX.syms" "$CYCC" < "$TMP/sy.cyr" > "$TMP/d$WX.bin" 2> "$TMP/d$WX.err"
    ELIM=$(grep 'bytes of dead code eliminated' "$TMP/d$WX.err" | grep -o '[0-9][0-9]*' | head -1)
    [ "${ELIM:-0}" -gt 0 ] || { echo "FAIL: sy.cyr no longer compacts under CYRIUS_DCE=1 CYRIUS_WX=$WX — the row proves nothing"; exit 1; }
    grep -q ' dead_a$' "$TMP/p$WX.syms" || { echo "FAIL: the plain (CYRIUS_WX=$WX) map lost dead_a"; exit 1; }
    out=$(symcheck "$TMP/p$WX.syms" "$TMP/p$WX.bin" | grep -v '^dead_a ') || true
    [ -z "$out" ] || { echo "FAIL: the plain (CYRIUS_WX=$WX) map: $out"; exit 1; }
    if grep -q ' dead_a$' "$TMP/d$WX.syms"; then echo "FAIL: CYRIUS_DCE=1 (CYRIUS_WX=$WX) lists the removed dead_a: $(tr '\n' ' ' < "$TMP/d$WX.syms")"; exit 1; fi
    out=$(symcheck "$TMP/d$WX.syms" "$TMP/d$WX.bin") || { echo "FAIL: CYRIUS_DCE=1 (CYRIUS_WX=$WX) map: $out"; exit 1; }
    for fnn in live_fn main; do
        p=$(va_of "$TMP/p$WX.syms" $fnn); d=$(va_of "$TMP/d$WX.syms" $fnn)
        [ -n "$p" ] && [ -n "$d" ] && [ $((0x$p - 0x$d)) = "$ELIM" ] \
            || { echo "FAIL: CYRIUS_DCE=1 (CYRIUS_WX=$WX) puts $fnn at ${d:-nothing}, want the plain ${p:-?} - $ELIM"; exit 1; }
    done
done

echo "PASS: CYRIUS_SYMS symbol dump emits on x86 + aarch64 (DX-01 parity, v6.3.23); under CYRIUS_DCE=1 it maps the compacted image (W^X and CYRIUS_WX=0)"
exit 0
