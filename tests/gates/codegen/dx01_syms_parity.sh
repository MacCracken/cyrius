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
CYCC="${CYCC:-$ROOT/build/cycc}"
TMP="$(mktemp -d)"
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

echo "PASS: CYRIUS_SYMS symbol dump emits on x86 + aarch64 (DX-01 parity, v6.3.23)"
exit 0
