#!/bin/sh
# v6.3.24 regression: a NON-int global (string / expr / struct init) that shadows
# an ENUM CONSTANT of the same name must be a HARD ERROR. It was a silent
# miscompile: FINDVAR returns last-match, so the var rebinds the name for every
# later reference — including inside already-parsed library code that uses the
# constant as an ABI offset — and the wrong value is added as an offset → runtime
# SIGSEGV. This was the yeo-cy-test (SecureYeoman) crash: a consumer `var DB_PATH =
# "yeo.patra"` shadowing patra's `enum DbOff { DB_PATH = 16 }`, misfiled as a
# "string-literal global holds garbage at scale" codegen bug (the string value is
# fine — the NAME collides). An int-literal SAME-VALUE shadow stays allowed
# (chrono's `var CLOCK_MONOTONIC = 1` harmlessly aliasing the syscall enum).
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CYCC="${CYCC:-$ROOT/build/cycc}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# (1) string var shadowing an enum constant → MUST hard-error
printf 'enum E { DB_PATH = 16; }\nfn u(b): i64 { return b + DB_PATH; }\nvar DB_PATH = "x";\nfn main(): i64 { return u(1); }\n' > "$TMP/bad.cyr"
if "$CYCC" < "$TMP/bad.cyr" > "$TMP/bad.bin" 2>"$TMP/bad.err"; then
    echo "FAIL: a string var shadowing an enum constant COMPILED (should hard-error)"
    exit 1
fi
if ! grep -q "shadows an enum constant" "$TMP/bad.err"; then
    echo "FAIL: build failed but without the 'shadows an enum constant' diagnostic:"
    cat "$TMP/bad.err"
    exit 1
fi

# (2) int-literal SAME-VALUE shadow → must still COMPILE (no false positive)
printf 'enum E { CM = 1; }\nfn u(): i64 { return CM; }\nvar CM = 1;\nfn main(): i64 { return u(); }\n' > "$TMP/ok.cyr"
if ! "$CYCC" < "$TMP/ok.cyr" > "$TMP/ok.bin" 2>"$TMP/ok.err"; then
    echo "FAIL: a harmless int same-value enum shadow was rejected (false positive):"
    cat "$TMP/ok.err"
    exit 1
fi

echo "PASS: non-int var shadowing an enum constant hard-errors; int same-value shadow allowed (v6.3.24)"
exit 0
