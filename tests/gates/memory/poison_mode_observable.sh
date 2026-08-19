#!/bin/sh
# v6.5.29 — `cyrius fuzz --poison` must make an out-of-bounds READ and a use-after-free
# OBSERVABLE, and must change NOTHING when it is off.
#
# ⛔ THE FILED GAP (sit v1.4.0). sit's `.git` packfile delta interpreter bounds-checked its
# destination but not its source, so a crafted delta copied 127 bytes of adjacent heap into
# the reconstructed object — including a live heap pointer, an ASLR-defeating disclosure. The
# module had 10 MILLION rounds/run of fuzzing over it and passed, for three minor versions.
# It was found by reading the code.
#
# The reason no harness could see it: the read landed in MAPPED memory. `alloc` is a bump
# allocator with no redzones, so a 127-byte overread off a small allocation is an ordinary
# load with no fault to catch. Generalised: an out-of-bounds WRITE is caught only if it
# reaches an unmapped page, and an out-of-bounds READ essentially never is. Every
# `fuzz: no crashes` line in every consumer's CI carries that asterisk.
#
# ⚠ WHY THIS IS A GATE AND NOT ONLY A .tcyr. The .tcyr
# (tests/tcyr/memory/fl_redzone_quarantine.tcyr) proves the ALLOCATOR behaves. This proves the
# TOOLCHAIN delivers it: that the compile-time predefine reaches a harness the CLI compiles,
# which is the part that was missing — consumers' existing harnesses do not call
# `fl_poison_enable()` themselves, and a mode nobody switches on is not a mode.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CLI="$ROOT/build/cyrius"
[ -x "$CLI" ] || CLI="$HOME/.cyrius/bin/cyrius"
[ -x "$CLI" ] || { echo "SKIP: cyrius CLI missing"; exit 0; }
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
fail=0

# A harness that reports the MODE through its exit code: 0 = poison on, 9 = off.
cat > "$D/mode.fcyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/freelist.cyr"
alloc_init();
if (fl_poison_active() == 1) { syscall(60, 0); }
syscall(60, 9);
EOF

# A harness that OVERREADS past a request, exactly the sit shape: it exits 0 only if the
# bytes it read back are the poison pattern rather than live heap.
cat > "$D/overread.fcyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/freelist.cyr"
alloc_init();
var p = fl_alloc(32);
var i = 0;
while (i < 32) { store8(p + i, 0x11); i = i + 1; }
# Read 8 bytes PAST the request — the disclosure shape. Under poison this is the pattern.
var leaked = 0;
i = 32;
while (i < 40) { if (load8(p + i) != fl_poison_byte()) { leaked = 1; } i = i + 1; }
syscall(60, leaked);
EOF

# A harness that OVERWRITES by one byte; the violation counter must see it.
cat > "$D/overwrite.fcyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/freelist.cyr"
alloc_init();
fl_poison_reset();
var p = fl_alloc(64);
var i = 0;
while (i < 65) { store8(p + i, 0x37); i = i + 1; }
fl_free(p);
if (fl_poison_violations() == 1) { syscall(60, 0); }
syscall(60, 7);
EOF

run() { "$CLI" fuzz "$1" ${2-} > "$D/out.txt" 2>&1 || true; }
verdict() { grep -cE "^  .*(PASS)$|PASS$" "$D/out.txt" >/dev/null 2>&1 && grep -q "1 passed, 0 failed" "$D/out.txt" && echo pass || echo fail; }

# --- axis 1: the mode is OFF by default ---
run "$D/mode.fcyr"
if [ "$(verdict)" = "fail" ]; then echo "  ok axis 1: poison is OFF for a plain \`cyrius fuzz\` run"
else echo "  FAIL axis 1: poison is ON without --poison — the mode is not opt-in"; fail=1; fi

# --- axis 2: --poison turns it on, all the way through to the compiled harness ---
run "$D/mode.fcyr" --poison
if [ "$(verdict)" = "pass" ]; then echo "  ok axis 2: --poison reaches the harness the CLI compiled"
else echo "  FAIL axis 2: --poison did not reach the harness — the predefine is not being injected"; fail=1; fi

# --- axis 3 (THE FILED DEFECT): an overread returns poison, not live heap ---
run "$D/overread.fcyr" --poison
if [ "$(verdict)" = "pass" ]; then echo "  ok axis 3: a read past the request yields the poison pattern"
else echo "  FAIL axis 3: an out-of-bounds READ still returned non-poison bytes — the disclosure stays invisible"; fail=1; fi

# --- axis 4 (ANTI-VACUOUS for axis 3): the SAME overread is invisible without the mode ---
# Without this, a build with poison permanently on would satisfy axes 2 and 3 while destroying
# the property that makes the mode acceptable — that it costs nothing in a normal run.
run "$D/overread.fcyr"
if [ "$(verdict)" = "fail" ]; then echo "  ok axis 4: the same overread is NOT flagged without --poison (mode is genuinely opt-in)"
else echo "  FAIL axis 4 (anti-vacuous): the overread was flagged with poison OFF — poison is always on"; fail=1; fi

# --- axis 5: an out-of-bounds WRITE is counted by the redzone check ---
run "$D/overwrite.fcyr" --poison
if [ "$(verdict)" = "pass" ]; then echo "  ok axis 5: a one-byte overflow is caught by the redzone at free"
else echo "  FAIL axis 5: a one-byte overflow was not counted — the redzone is not armed or not checked"; fail=1; fi

# --- axis 6: the flag is positional-independent and not eaten as the path argument ---
"$CLI" fuzz --poison "$D/mode.fcyr" > "$D/out.txt" 2>&1 || true
if grep -q "1 passed, 0 failed" "$D/out.txt"; then echo "  ok axis 6: --poison before the path works too"
else echo "  FAIL axis 6: --poison before the path broke the run (flag consumed as the path)"; fail=1; fi

[ "$fail" -eq 0 ] || { echo "FAIL: poison-mode-observable"; exit 1; }
echo "PASS: poison-mode-observable — overreads and overflows are observable under --poison, invisible without it"
