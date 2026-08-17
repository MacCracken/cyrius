#!/bin/sh
# ref_directive_expands.sh — `#ref "file.toml"` must actually emit `var KEY = VALUE;`.
#
# v6.5.22. Found the hard way during the input_buf relocation: `PP_REF_PASS` calls
# `ISREF(S, ...)`, and `ISREF`'s first parameter is a SOURCE BASE, not the state
# pointer. When the source buffer moved off S+0, that one call site kept reading the
# old address, so `#ref` silently stopped expanding — the directive was ignored and
# the keys simply never appeared, surfacing only as `undefined variable 'K'` at the
# USE site with nothing pointing at the preprocessor.
#
# ⛔ THE WHOLE CORPUS MISSED IT: 271/271 tcyr passed against the broken compiler,
# because `#ref` needs an external .toml alongside the source and no .tcyr sets one
# up. That is why this is a shell gate and not a tcyr — the fixture is the point.
#
# Mutation-proven: against a compiler whose `ISREF(S + _SRCB, ...)` is reverted to
# `ISREF(S, ...)`, axis 1 fails with `undefined variable 'K'`.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT

pass=0; fail=0

# axis 1 — a scalar key expands and is readable
printf 'K = 7\n' > "$D/r.toml"
printf '#ref "r.toml"\nfn main() { syscall(60, K); return 0; }\n' > "$D/a.cyr"
RC=0
( cd "$D" && cat a.cyr | "$CC" > a.bin 2>a.err ) || RC=$?
if [ "$RC" -ne 0 ]; then
    printf '  FAIL: #ref scalar did not compile: %s\n' "$(grep -m1 error "$D/a.err" | cut -c1-70)"; fail=$((fail+1))
else
    chmod +x "$D/a.bin"; E=0; "$D/a.bin" || E=$?
    if [ "$E" = "7" ]; then printf '  ok: #ref scalar expands (exit=%s)\n' "$E"; pass=$((pass+1))
    else printf '  FAIL: #ref scalar exit=%s (want 7)\n' "$E"; fail=$((fail+1)); fi
fi

# axis 2 — multiple keys all expand, not just the first
printf 'A = 3\nB = 4\n' > "$D/m.toml"
printf '#ref "m.toml"\nfn main() { syscall(60, A * 10 + B); return 0; }\n' > "$D/b.cyr"
RC=0
( cd "$D" && cat b.cyr | "$CC" > b.bin 2>b.err ) || RC=$?
if [ "$RC" -ne 0 ]; then
    printf '  FAIL: #ref multi-key did not compile: %s\n' "$(grep -m1 error "$D/b.err" | cut -c1-70)"; fail=$((fail+1))
else
    chmod +x "$D/b.bin"; E=0; "$D/b.bin" || E=$?
    if [ "$E" = "34" ]; then printf '  ok: #ref multi-key expands (exit=%s)\n' "$E"; pass=$((pass+1))
    else printf '  FAIL: #ref multi-key exit=%s (want 34)\n' "$E"; fail=$((fail+1)); fi
fi

# axis 3 — a source with NO #ref is unaffected (guards against over-correction)
printf 'fn main() { syscall(60, 9); return 0; }\n' > "$D/c.cyr"
RC=0
( cd "$D" && cat c.cyr | "$CC" > c.bin 2>c.err ) || RC=$?
chmod +x "$D/c.bin" 2>/dev/null || true
E=0; "$D/c.bin" || E=$?
if [ "$E" = "9" ]; then printf '  ok: no-#ref source unaffected (exit=%s)\n' "$E"; pass=$((pass+1))
else printf '  FAIL: no-#ref source exit=%s (want 9)\n' "$E"; fail=$((fail+1)); fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: ref-directive-expands — %s assertion(s) failed\n' "$fail"; exit 1
fi
printf 'PASS: ref-directive-expands — %s/%s axes green\n' "$pass" "$pass"
