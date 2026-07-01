#!/bin/sh
# VR-02 (v6.3.22): mutation-fuzz cycc's stdin parser with byte-mutated valid
# sources. cycc parses UNTRUSTED source from stdin (`cat foo.cyr | cycc`), so a
# parser bug on hostile input is a real crash surface. A parser bug = cycc dies by
# SIGNAL (exit >= 128: SIGSEGV 139 / SIGABRT 134 / SIGILL 132) or HANGS; a clean
# compile OR a graceful `error: …` (exit 1) is a PASS. Deterministic (fixed LCG
# seed) so any crash reproduces. Complements `cyrius fuzz` (stdlib property tests).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; exit 0; }

# Iterations per corpus file. The check.sh gate runs a cheap smoke (default 15);
# a real fuzz run is CYCC_FUZZ_ITERS=300 sh tests/cycc_parser_fuzz.sh.
ITERS="${CYCC_FUZZ_ITERS:-15}"

python3 - "$CC" "$ITERS" <<'PY'
import sys, subprocess, os
cc = sys.argv[1]
iters = int(sys.argv[2])
# Diverse valid seeds: closures, generics, structs, a real program, compiler src.
corpus = [
    "tests/tcyr/closures.tcyr", "tests/tcyr/struct_local_codegen.tcyr",
    "tests/tcyr/element_typed_array.tcyr", "programs/calc.cyr", "src/common/ir.cyr",
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
            if r.returncode >= 128:      # killed by a signal
                crashes.append((path, r.returncode))
        except subprocess.TimeoutExpired: # hang on hostile input = DoS bug
            crashes.append((path, "TIMEOUT"))

print(f"cycc_parser_fuzz: {runs} mutated-input parses; {len(crashes)} crashes")
if crashes:
    for c in crashes[:12]:
        print("  CRASH", c)
    sys.exit(1)
PY
