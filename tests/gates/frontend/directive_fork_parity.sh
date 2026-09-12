#!/bin/sh
# directive_fork_parity.sh — v6.6.3. A directive must be handled by EVERY compiler fork,
# and must not be INERT on any of them.
#
# WHY THIS GATE EXISTS. cyrius has seven per-target forks of the entry point
# (src/main.cyr + main_aarch64{,_macho,_native}.cyr, main_win.cyr, main_x86_macho.cyr,
# main_cx.cyr). Each carries its OWN copy of the top-level directive dispatch, in TWO
# regions: a pass-1 declaration scan that must CONSUME the token, and a pass-2 dispatch
# that ARMS the pending flag. A new directive needs BOTH halves in ALL forks, and the
# failure modes of missing each half are different and BOTH silent-ish:
#
#   missing CONSUME -> the pass-1 scan falls into its catchall else and TERMINATES, so
#                      every declaration after the directive is unregistered. Surfaces as
#                      a nonsense diagnostic pointing at an innocent later line
#                      ("unexpected struct"), hundreds of lines from the real trigger.
#   missing ARM     -> the directive compiles cleanly and DOES NOTHING, forever, on that
#                      target only. No error, no warning, correct results. This is the
#                      v6.5.63 defect (#inline had no handler at all and silently did
#                      nothing while consumers wrote it and recorded measuring it).
#
# v6.6.3 shipped #inline's pass-1 consume into all seven forks and its pass-2 ARM into
# ONE (main.cyr). Result: CI red on native aarch64 (compile failure from the missing
# consume at the SECOND region in four forks) and — underneath that, invisible — #inline
# INERT on aarch64, aarch64-macho, x86-macho and PE. Measured before the fix: the emitted
# binary was BYTE-IDENTICAL with and without the directive on every one of those targets.
#
# ⭐ Axis 2 is the one that cannot be faked. A static grep can be satisfied by adding a
# token to a guard list while arming nothing — which is exactly the half-fix that makes
# CI green and leaves the feature dead. So axis 2 does not read the source at all: it
# COMPILES the same fixture twice through each fork's own compiler, once with the
# directive and once without, and requires the two outputs to DIFFER. Byte-identical
# output is proof the directive is inert. No disassembler needed, so it cannot degrade
# into a skip.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL directive_fork_parity: no build/cycc"; exit 1; }
cd "$R" || exit 1

FORKS="main.cyr main_aarch64.cyr main_aarch64_macho.cyr main_aarch64_native.cyr main_win.cyr main_x86_macho.cyr main_cx.cyr"

# ── axis 1 — CONSUME parity: a guard list that handles #naked must handle #inline ──────
# Both are "arm for the next fn" directives dispatched from the same chain, so a region
# that knows about one and not the other is drift by construction. This is the exact
# shape that went red on aarch64: 133 present, 163 absent, at the SECOND region only.
miss=""
armless=""
for f in $FORKS; do
  # 1a — GUARD LISTS. A directive-dispatch guard is identified by PEEKT(S) == 127 (#alloc),
  # present in every fork's chain. If such a guard admits #naked it must admit #inline.
  # The guard CONDITION only — everything up to the first ") {" — because the arming
  # code later on the SAME line also mentions 163, and matching the whole line makes the
  # check pass on a guard that no longer admits the token. (Measured: that blind spot let
  # the exact CI-red mutation read GREEN.)
  awk -v F="src/$f" '
    /PEEKT\(S\) == 127/ {
      p = index($0, ") {"); if (p == 0) next
      g = substr($0, 1, p)
      if (g ~ /PEEKT\(S\) == 133/ && g !~ /PEEKT\(S\) == 163/) print F ":" NR
    }' "src/$f" > "$T/miss_$f"
  if [ -s "$T/miss_$f" ]; then miss="$miss $(tr '\n' ' ' < "$T/miss_$f")"; fi
  # 1b — ARMING SITES. Wherever a fork arms _naked_pending it must also arm
  # _inline_pending, within a 4-line window (main_win.cyr splits the chain across lines).
  # Missing this half is the SILENT one: it compiles and the directive does nothing.
  awk -v F="src/$f" '
    /_naked_pending = 1;/ { nl[NR] = 1 }
    /_inline_pending = 1;/ { il[NR] = 1 }
    END {
      for (k in nl) {
        ok = 0
        for (d = -4; d <= 4; d++) if (k + d in il) ok = 1
        if (!ok) print F ":" k
      }
    }' "src/$f" > "$T/armless_$f"
  if [ -s "$T/armless_$f" ]; then armless="$armless $(tr '\n' ' ' < "$T/armless_$f")"; fi
done
if [ -n "$miss" ]; then
  echo "FAIL directive_fork_parity axis1a: a directive guard list admits #naked (133) but not #inline (163):"
  for m in $miss; do echo "    $m"; done
  echo "  An unconsumed directive terminates the pass-1 scan — every later declaration goes unregistered."
  exit 1
fi
if [ -n "$armless" ]; then
  echo "FAIL directive_fork_parity axis1b: a fork ARMS _naked_pending but never _inline_pending nearby:"
  for m in $armless; do echo "    $m"; done
  echo "  That fork consumes #inline and ignores it — it compiles clean and does NOTHING on that target."
  exit 1
fi

# ── axis 2 — the directive must not be INERT on any fork buildable here ────────────────
# The two macho forks cannot RUN on Linux (they abort with 'mmap heap init failed'), so
# they are covered by the cross-OS leg on ecb/ach, not here. Everything else is measured.
cat > "$T/tmpl.cyr" <<'EOF'
include "lib/syscalls.cyr"
var ST = 0;
MARK
fn A_f0(s) { return load64(s + 0); }
MARK
fn A_f1(s) { return load64(s + 8); }
MARK
fn A_f2(s) { return load64(s + 16); }
MARK
fn A_f3(s) { return load64(s + 24); }
fn main(): i64 {
    var b[32];
    var i = 0;
    while (i < 4) { store64(&b + i * 8, i + 1); i = i + 1; }
    ST = &b;
    var acc = 0;
    var k = 0;
    while (k < 1000) { acc = acc + A_f0(ST) + A_f1(ST) + A_f2(ST) + A_f3(ST); k = k + 1; }
    return acc & 0xFF;
}
var e = main();
EOF
sed 's/^MARK$/#inline/' "$T/tmpl.cyr" > "$T/yes.cyr"
sed 's/^MARK$//'        "$T/tmpl.cyr" > "$T/no.cyr"

# The SHAPE that actually trips the second dispatch region: an #inline followed LATER by a
# #derive'd struct. A fixture with #inline before plain fns alone is NOT enough — measured:
# it still compiles and still differs when the second region's guard drops 163, so a gate
# built on it reads GREEN on the exact defect that turned CI red.
cat > "$T/shape.cyr" <<'EOF'
include "lib/syscalls.cyr"
#inline
fn sh_helper(a): i64 { return a + 1; }
#derive(accessors)
struct AfterInline { gamma; delta; }
fn main(): i64 { return sh_helper(1); }
var e = main();
EOF

RUNNABLE="main.cyr main_aarch64.cyr main_win.cyr main_cx.cyr"
checked=0
for f in $RUNNABLE; do
  "$CC" < "src/$f" > "$T/cc_$f" 2>/dev/null || { echo "FAIL directive_fork_parity axis2: could not build src/$f"; exit 1; }
  chmod +x "$T/cc_$f"
  # 2a — SURVIVAL. #inline followed by a #derive'd struct must still compile. A directive
  # the second region does not consume terminates the pass-1 scan, and the struct after it
  # is never registered: "error: unexpected struct", pointing at an innocent later line.
  "$T/cc_$f" < "$T/shape.cyr" > "$T/o_shape" 2>"$T/e_shape"
  if [ ! -s "$T/o_shape" ]; then
    echo "FAIL directive_fork_parity axis2a: src/$f cannot compile #inline followed by #derive"
    sed 's/^/      /' "$T/e_shape" | head -3
    echo "  A directive region is not consuming 163 — the pass-1 scan terminated and every"
    echo "  declaration after the #inline went unregistered."
    exit 1
  fi
  # 2b — NON-INERTNESS.
  "$T/cc_$f" < "$T/yes.cyr" > "$T/o_yes" 2>/dev/null
  "$T/cc_$f" < "$T/no.cyr"  > "$T/o_no"  2>/dev/null
  [ -s "$T/o_yes" ] && [ -s "$T/o_no" ] || { echo "FAIL directive_fork_parity axis2b: src/$f emitted nothing for the fixture"; exit 1; }
  if cmp -s "$T/o_yes" "$T/o_no"; then
    echo "FAIL directive_fork_parity axis2b: #inline is INERT in src/$f"
    echo "  The fixture compiled to a BYTE-IDENTICAL binary with and without the directive."
    echo "  The token is being consumed and ignored — the pass-2 region arms no flag."
    echo "  This is the v6.5.63 defect (a directive that silently does nothing), per-target."
    exit 1
  fi
  checked=$((checked + 1))
done

# Anti-vacuous: if the fork list ever shrinks to nothing, the loop above passes trivially.
[ "$checked" -ge 4 ] || { echo "FAIL directive_fork_parity axis2: only $checked fork(s) measured, expected >= 4"; exit 1; }

echo "PASS directive_fork_parity: 7 forks consume-parity on #naked/#inline · #inline non-inert on $checked buildable forks (macho pair covered by the ecb/ach cross-OS leg)"
exit 0
