#!/bin/sh
# VR-02 (v6.3.22): mutation-fuzz cycc's stdin parser with byte-mutated valid
# sources. cycc parses UNTRUSTED source from stdin (`cat foo.cyr | cycc`), so a
# parser bug on hostile input is a real crash surface. A parser bug = cycc dies by
# SIGNAL or HANGS; a clean compile OR a graceful `error: …` (exit 1) is a PASS.
# Deterministic (fixed LCG seed) so any crash reproduces. Complements `cyrius fuzz`
# (stdlib property tests).
#
# ⛔ v6.5.19 — THIS GATE'S SIGNAL BRANCH HAD NEVER ONCE BEEN REACHABLE, AND IT WAS
# HIDING 40 CRASHES. From v6.3.22 to v6.5.18 the test was `if r.returncode >= 128`,
# written to the SHELL convention (128+N). **Python's `subprocess.run` reports a
# child killed by signal N as a NEGATIVE returncode (-N)** — `-11` for SIGSEGV, never
# 139 — so the comparison was false for every crash that ever occurred, and only the
# TimeoutExpired branch was live. The gate printed "0 crashes" and passed GREEN for
# three minors while `enum` (4 bytes) and `fn` (2 bytes) segfaulted the compiler.
#
# Correct predicate: `r.returncode < 0`. The `>= 128` arm is KEPT alongside it, not
# because Python emits it, but so the check stays correct if this is ever driven
# through a shell wrapper. The first run after the fix found 2 SIGSEGVs at the gate's
# own default ITERS=15, i.e. it would have been RED from the day it was written.
#
# Every crash it found is fixed in v6.5.19 (CVE-39): the unconditional EOF clamp in
# PEEKT, `_wd_eof_tick`, the enum/struct/union/generics/match EOF guards, and
# `_ends_guard`. Companion gate: tests/gates/diagnostics/truncated_input_terminates.sh
# covers the truncation axis deterministically rather than by chance.
#
# LESSON WORTH KEEPING, because it is the third of its kind this release: a gate that
# can only ever report success is indistinguishable from a gate that works. Assume
# every gate is vacuous until a SEMANTIC mutation makes it go RED.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
# CYCC_FUZZ_CC overrides the binary under test. It exists so THIS GATE'S OWN
# PREDICATE can be mutation-proven: point it at a program that dies by SIGSEGV and
# the gate must report a crash. Without the override the predicate is untestable
# except by breaking the real compiler — which is precisely how a dead signal branch
# survived from v6.3.22 to v6.5.18. Verified: a null-store stub gives Python
# returncode -11 (the shell would say 139), `>= 128` alone reports 0 crashes and the
# fixed predicate reports it.
CC="${CYCC_FUZZ_CC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; exit 0; }

# Iterations per corpus file. The check.sh gate runs a cheap smoke (default 15);
# a real fuzz run is CYCC_FUZZ_ITERS=300 sh tests/gates/diagnostics/cycc_parser_fuzz.sh.
ITERS="${CYCC_FUZZ_ITERS:-15}"

python3 - "$CC" "$ITERS" <<'PY'
import sys, subprocess, os
cc = sys.argv[1]
iters = int(sys.argv[2])
# Diverse valid seeds: closures, generics, structs, a real program, compiler src.
corpus = [
    "tests/tcyr/lang/closures.tcyr", "tests/tcyr/codegen/struct_local_codegen.tcyr",
    "tests/tcyr/lang/element_typed_array.tcyr", "programs/calc.cyr", "src/common/ir.cyr",
]
seed = 0x2545F4914F6CDD1D
def rnd():
    global seed
    seed = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
    return seed >> 33

runs = 0; crashes = []
for path in corpus:
    if not os.path.exists(path):
        continue
    data = open(path, "rb").read()
    if not data:
        continue
    for _ in range(iters):
        b = bytearray(data)
        for _ in range(rnd() % 12 + 1):
            op = rnd() % 3
            if op == 0 and b:            # bit flip
                p = rnd() % len(b); b[p] ^= (1 << (rnd() % 8))
            elif op == 1 and b:          # byte set
                p = rnd() % len(b); b[p] = rnd() % 256
            elif op == 2:                # truncate
                b = b[:rnd() % (len(b) + 1)]
        runs += 1
        try:
            r = subprocess.run([cc], input=bytes(b), stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=15)
            # Python reports signal death as NEGATIVE (-N); 128+N is the SHELL
            # convention and never appears here. Testing only `>= 128` made this
            # branch dead code from v6.3.22 to v6.5.18. Both arms, deliberately.
            if r.returncode < 0 or r.returncode >= 128:
                crashes.append((path, r.returncode, len(bytes(b))))
        except subprocess.TimeoutExpired: # hang on hostile input = DoS bug
            crashes.append((path, "TIMEOUT", len(bytes(b))))

print(f"cycc_parser_fuzz: {runs} mutated-input parses; {len(crashes)} crashes")
if crashes:
    for c in crashes[:12]:
        print("  CRASH", c)
    sys.exit(1)
PY
