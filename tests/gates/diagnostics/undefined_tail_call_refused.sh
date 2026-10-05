#!/bin/sh
# undefined_tail_call_refused.sh — 6.6.9 bite 2. A REACHABLE call to an undefined function is
# refused on every backend, whatever its shape, and every fork prints the same pre-pass
# "undefined function" warning for the ones DCE judges unreachable.
#
# ⛔ WHY. Three holes, each silent, each measured before 6.6.9:
#   1. aarch64 records a tail call (`return nosuchfn(x);`) as fixup type 4 — a `B rel26`
#      patched to UDF #0 when the target is undefined — and its reachable-undefined check
#      examined types 2 and 3 only. The build exited 0 with no diagnostic, and the binary died
#      SIGILL (qemu rc 132) at the first call. x86's tail calls are type 2, so x86 refused.
#   2. A reference from an UNREACHABLE fn that happened to come first in the fixup table marked
#      the fn "reported" without reporting it, so every later REACHABLE call of the same fn was
#      skipped. `fn dead() { return nope(1); }` above `main` calling `nope(2)` built rc 0 on
#      x86, aarch64 and PE — v6.3.2's refusal only held when the live call came first.
#   3. The four aarch64 / Mach-O forks never called `_warn_undefined_prepass`, so an undefined
#      call in an unreachable fn warned on x86 and was silent on aarch64 — and the reachable
#      form printed only the suffixed reachability line there (it read "(call site may be
#      unreachable)" — inverted, since it only ever fires for REACHABLE sites; 6.6.10 made it
#      "(reachable call site)").
#
# Anti-vacuous rows: the non-tail form is refused; `--allow-undef` still EMITS a binary; an
# undefined tail call inside an UNREACHABLE fn is NOT refused (it warns). A gate that refused
# everything, or nothing, fails one of them.
#
# The compilers are built FROM SOURCE (stage1 → cross forks), so reverting a fix turns this RED
# instead of being masked by a stale build/ binary. The two Mach-O forks cannot run on Linux;
# they share aarch64/fixup.cyr (arm64) and x86/fixup.cyr (x86) with forks measured here, and
# carry the prepass call checked structurally below. Real-hardware coverage is ecb/ach.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: undefined_tail_call_refused: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL undefined_tail_call_refused: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
"$CC" < src/main.cyr > "$T/x86" 2>"$T/eb" || { echo "FAIL undefined_tail_call_refused: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
for f in aarch64 win cx; do
  "$T/x86" < "src/main_$f.cyr" > "$T/$f" 2>"$T/eb" || { echo "FAIL undefined_tail_call_refused: could not build src/main_$f.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
  chmod +x "$T/$f"
done
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# ── structural: every fork that runs PARSE_PROG runs the pre-pass before it ───────────────
for f in src/main*.cyr; do
  if ! grep -q '^_warn_undefined_prepass(S);' "$f"; then _bad "$f never calls _warn_undefined_prepass (aarch64 is silent where x86 warns)"; continue; fi
  pp=$(grep -n '^_warn_undefined_prepass(S);' "$f" | head -1 | cut -d: -f1)
  pg=$(grep -n '^PARSE_PROG(S);\|^    PARSE_PROG(S);' "$f" | tail -1 | cut -d: -f1)
  if [ -z "$pg" ] || [ "$pp" -gt "$pg" ]; then _bad "$f: _warn_undefined_prepass is not before the top-level PARSE_PROG"; else pass=$((pass + 1)); fi
done

# ── fixtures ──────────────────────────────────────────────────────────────────────────────
# The filed repro, verbatim (docs/development/issues/repros/2026-09-22-aarch64-undefined-tail-call.cyr).
cat > "$T/tail.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { return no_such_fn(2); }
var r = main();
sys_exit(r);
EOF
cat > "$T/nontail.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { var x = no_such_fn(2); return x + 1; }
var r = main();
sys_exit(r);
EOF
# the dead reference comes FIRST in the fixup table
cat > "$T/deadfirst.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn dead(): i64 { return no_such_fn(1) + 1; }
fn main(): i64 { var x = no_such_fn(2); return x; }
var r = main();
sys_exit(r);
EOF
cat > "$T/deadtail.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn dead(): i64 { return no_such_fn(1); }
fn main(): i64 { return 7; }
var r = main();
sys_exit(r);
EOF

# refuse <compiler> <fixture> <needle> — rc 1, the needle on stderr, no output
refuse() {
  "$T/$1" < "$T/$2.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -ne 1 ]; then _bad "$1 $2: rc $rc, expected 1 (a reachable undefined call must be refused)"; sed 's/^/      /' "$T/e" | grep -v '^      note\|routes n=' | head -3; return; fi
  if ! grep -q "$3" "$T/e"; then _bad "$1 $2: refused without naming it ('$3' missing)"; sed 's/^/      /' "$T/e" | head -3; return; fi
  pass=$((pass + 1))
}
for c in x86 aarch64 win; do
  refuse "$c" tail      'refusing to emit binary with 1 reachable undefined function'
  refuse "$c" nontail   'refusing to emit binary with 1 reachable undefined function'
  refuse "$c" deadfirst 'refusing to emit binary with 1 reachable undefined function'
done
# cx has its own refusal wording (and no --allow-undef)
refuse cx tail      'undefined function(s) called (cx backend)'
refuse cx nontail   'undefined function(s) called (cx backend)'
refuse cx deadfirst 'undefined function(s) called (cx backend)'

# ── the pre-pass warning: the SAME unsuffixed line on every fork ──────────────────────────
# (cx has no reachability pass — it refuses every undefined call — so it is checked for the
# warning line only.)
for c in x86 aarch64 win cx; do
  "$T/$c" < "$T/deadtail.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$c" != cx ]; then
    if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then _bad "$c deadtail: rc $rc — an undefined call in an UNREACHABLE fn must still build"; continue; fi
  fi
  if ! grep -qx "warning: undefined function 'no_such_fn'" "$T/e"; then _bad "$c deadtail: no pre-pass 'undefined function' warning (x86 prints it)"; continue; fi
  pass=$((pass + 1))
done

# ── --allow-undef still downgrades (the refusal is not unconditional) ──────────────────────
for c in x86 aarch64; do
  "$T/$c" --allow-undef < "$T/tail.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then _bad "$c --allow-undef tail: rc $rc, expected a binary"; else pass=$((pass + 1)); fi
done

# ── the old aarch64 behaviour, observed: the binary it USED to emit dies SIGILL ─────────────
# Only where qemu-aarch64 exists; the rows above are the gate, this one shows what it prevents.
if command -v qemu-aarch64 >/dev/null 2>&1; then
  # ⛔ 6.6.17: compiled from the ROOT like every row above. It used to compile inside $T, where
  # `include "lib/syscalls.cyr"` resolves through cycc's $CYRIUS_HOME / $HOME/.cyrius fallback —
  # the live store's lib, not this tree's — and failed under a store-less HOME. CHANGELOG [6.6.17]
  ( ulimit -c 0 && "$T/aarch64" --allow-undef < "$T/tail.cyr" > "$T/tail_a64" 2>/dev/null && chmod +x "$T/tail_a64" && cd "$T" && sh -c 'qemu-aarch64 ./tail_a64' >/dev/null 2>&1 ) 2>/dev/null; rc=$?
  if [ "$rc" -eq 132 ] || [ "$rc" -eq 139 ]; then pass=$((pass + 1)); else _bad "aarch64 --allow-undef tail binary exited $rc under qemu, expected the UDF trap (132)"; fi
fi

if [ "$fail" -ne 0 ]; then echo "FAIL undefined_tail_call_refused: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS undefined_tail_call_refused: $pass rows — tail/non-tail/dead-first refused on x86+aarch64+PE+cx, pre-pass warning on all four, --allow-undef honoured"
exit 0
