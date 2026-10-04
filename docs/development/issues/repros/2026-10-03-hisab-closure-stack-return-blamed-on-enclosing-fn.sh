#!/bin/sh
# Repro: a `return <call of a : stack fn>` INSIDE A CLOSURE BODY is booked against
# the ENCLOSING fn. The enclosing fn is flagged pair-returning (fn flag 256), so
#   - its own `return g;` draws "`mk` returns a `: stack` pair on another path but
#     a SINGLE value here" (a warning), and
#   - every `var g = mk(...)` inside a fn is REFUSED: "a `: stack` enum returns two
#     values — bind both" (an error), although mk returns one value, the closure.
# Filed with: docs/development/issues/2026-10-03-hisab-closure-stack-return-blamed-on-enclosing-fn.md
# Discovered from hisab (roadmap D082), 2026-09-30; filed 2026-10-03.
#
# Usage:   sh 2026-10-03-hisab-closure-stack-return-blamed-on-enclosing-fn.sh <pin>
#          e.g. `... .sh 6.6.14`. The pin is REQUIRED: the script builds in a
#          throwaway project whose cyrius.cyml pins it, so `cyrius` re-execs to
#          that toolchain (each build's `compiler:` line is printed).
#
# Self-proving -- the exit code is the verdict:
#   0     fixed: D1-D3 build with no `: stack` diagnostic and run to exit 0
#   1..3  defect present: the number of D rows that drew a `: stack` diagnostic
#         or failed to build or run
#   99    a CONTROL failed (C1-C3), so the `: stack` checks themselves changed
#         and no verdict on D1-D3 is possible -- or setup failed
#
#   D1  closure built in a helper; the helper's result bound INSIDE a fn
#                                     -> error "bind both" + warning on `mk`
#   D2  the same helper, bound at TOP LEVEL
#                                     -> warning on `mk` only (the single-bind
#                                        refusal applies inside fns only)
#   D3  closure built inline in a fn that returns 0
#                                     -> warning on `run`
#   C1  a fn that REALLY mixes a pair return and a plain return -> must warn
#   C2  a REAL single-variable bind of a pair, inside a fn      -> must be refused
#   C3  the workaround: the closure binds both halves and returns 0 -> clean, exit 0
#
# Measured 2026-10-03 (x86_64): exit 3 on every installed pin 6.6.0 through 6.6.14,
# each with C1-C3 passing. A user-declared `enum R: stack { A(v); B(e); }` in
# place of Result gives the same diagnostics, so it is not Result-specific.
set -u
PIN="${1:-}"
[ -n "$PIN" ] || { echo "usage: $0 <cyrius pin, e.g. 6.6.14>"; exit 99; }
CY="${CYRIUS:-cyrius}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 99
cat > cyrius.cyml <<EOF
[package]
name = "d082"
version = "0.0.1"
language = "cyrius"
cyrius = "$PIN"

[deps]
stdlib = ["syscalls", "string", "alloc", "fmt", "tagged", "result", "fnptr"]
EOF
"$CY" lib sync >/dev/null 2>&1 || { echo "lib sync failed for $PIN"; exit 99; }
"$CY" deps >/dev/null 2>&1 || { echo "deps failed for $PIN"; exit 99; }

H='fn h(x) { return Ok(x); }'
MK='fn mk(b) { var g = |x| { return h(x + b); }; return g; }'

printf '%s\n%s\n%s\n' "$H" "$MK" \
  'fn main() { var g = mk(41); var t = fncall1(g, 1); return t; }
var r = main();
sys_exit_group(r);' > D1.cyr
printf '%s\n%s\n%s\n' "$H" "$MK" \
  'var g = mk(41);
sys_exit_group(0);' > D2.cyr
printf '%s\n%s\n' "$H" \
  'fn run(b) { var g = |x| { return h(x + b); }; return 0; }
var r = run(41);
sys_exit_group(r);' > D3.cyr
printf '%s\n%s\n' "$H" \
  'fn bad(x) { if (x > 0) { return h(x); } return 0; }
fn main() { var t, v = bad(1); return 0; }
var r = main();
sys_exit_group(r);' > C1.cyr
printf '%s\n%s\n' "$H" \
  'fn main() { var t = h(1); return 0; }
var r = main();
sys_exit_group(r);' > C2.cyr
printf '%s\n%s\n' "$H" \
  'fn mk(b) { var g = |x| { var t, v = h(x + b); return 0; }; return g; }
fn main() { var g = mk(41); return fncall1(g, 1); }
var r = main();
sys_exit_group(r);' > C3.cyr

# build <case>: sets OUT (compiler output), BRC (build status), RRC (run status or -)
build() {
    OUT="$("$CY" build -v "$1.cyr" "./$1.out" 2>&1)"
    BRC=$?
    RRC=-
    if [ "$BRC" -eq 0 ] && [ -x "./$1.out" ]; then "./$1.out" >/dev/null 2>&1; RRC=$?; fi
    printf '%s: build=%s run=%s %s\n' "$1" "$BRC" "$RRC" \
      "$(printf '%s\n' "$OUT" | grep -o 'compiler: .*' | head -1)"
    printf '%s\n' "$OUT" | grep -F ': stack' | sed 's/^/    /' | cut -c1-150
}
has_stack_diag() { printf '%s\n' "$OUT" | grep -qF ': stack'; }

bad=0
for c in D1 D2 D3; do
    build "$c"
    if has_stack_diag || [ "$BRC" -ne 0 ] || [ "$RRC" != 0 ]; then bad=$((bad + 1)); fi
done

ctl=0
build C1; has_stack_diag || { echo "  CONTROL C1 FAILED: a real mixed return no longer warns"; ctl=1; }
build C2; if [ "$BRC" -eq 0 ] || ! has_stack_diag; then echo "  CONTROL C2 FAILED: a real lossy bind is no longer refused"; ctl=1; fi
build C3; if has_stack_diag || [ "$BRC" -ne 0 ] || [ "$RRC" != 0 ]; then echo "  CONTROL C3 FAILED: the workaround form no longer builds clean"; ctl=1; fi
[ "$ctl" -eq 0 ] || exit 99

echo "D rows with the defect: $bad of 3"
exit "$bad"
