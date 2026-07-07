#!/bin/sh
# cx arc A: the `cyrius build --target=cx` + `cyrius run *.cyx` CLI path, end-to-end.
# The 5 internal cx gates prove src/main_cx.cyr self-hosts, NOT that the installed
# CLI reaches the same emit — so without this gate --target=cx can rot behind a
# green check (the macOS-CI-rot pattern). Builds the cyrius CLI, then:
#   (1) build --target=cx an integer program -> a valid CYX (format version byte
#       = 1) that `cyrius run` executes with the correct exit code;
#   (2) a float program hard-errors (the A5 EMIT_FLOAT_LIT footgun guard).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f src/main_cx.cyr ] || { echo "SKIP: src/main_cx.cyr missing"; exit 0; }

CYR=$(mktemp)
cat cbt/cyrius.cyr | "$CC" > "$CYR" 2>/dev/null || { echo "FAIL: cyrius CLI build"; rm -f "$CYR"; exit 1; }
chmod +x "$CYR"
T=$(mktemp -d)
trap 'rm -f "$CYR"; rm -rf "$T"' EXIT

# (1) integer build --target=cx -> versioned .cyx -> run
printf 'fn f(): i64 { return 33; }\nsyscall(60, f());\n' > "$T/i.cyr"
"$CYR" build --target=cx "$T/i.cyr" "$T/i.cyx" >/dev/null 2>&1 || { echo "FAIL: cyrius build --target=cx"; exit 1; }
[ -f "$T/i.cyx" ] || { echo "FAIL: no .cyx produced"; exit 1; }
v=$(od -An -j3 -N1 -tu1 "$T/i.cyx" | tr -d ' ')
[ "$v" = "1" ] || { echo "FAIL: .cyx format version byte = $v (want 1)"; exit 1; }
# NB: `cyrius run` exits with the guest's code (33), which is nonzero — capture it
# via `|| rc=$?` so `set -e` doesn't abort before the assertion (the CI-loop trap).
rc=0
"$CYR" run "$T/i.cyx" >/dev/null 2>&1 || rc=$?
[ "$rc" = "33" ] || { echo "FAIL: cyrius run *.cyx exited $rc (want 33)"; exit 1; }

# (2) float program must hard-error on cx (no silent garbage)
printf 'fn main(): i64 { var x = 3.14; var y = f64_add(x, x); return 0; }\nvar e = main();\nsyscall(60, e);\n' > "$T/f.cyr"
if "$CYR" build --target=cx "$T/f.cyr" "$T/f.cyx" >/dev/null 2>"$T/f.err"; then
    echo "FAIL: float program compiled on cx target — must hard-error"; exit 1
fi
grep -q "not yet supported on the cx bytecode target" "$T/f.err" || { echo "FAIL: wrong/missing float error:"; cat "$T/f.err"; exit 1; }

echo "PASS: cyrius build --target=cx -> versioned .cyx -> run (exit 33); float hard-errors (cx arc A)"
