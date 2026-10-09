#!/bin/sh
# HEAP-12 repro — the IR family lives in fixed S + 0x… bands with fixed caps, so CYRIUS_IR stops a build
# that the default pipeline compiles.
# Generates a ~3.0 MB program (400 fns x 500 statements) on stdout:
#   sh this > /tmp/big.cyr
#   build/cycc < /tmp/big.cyr > /tmp/big                         # rc 0 (runs, exit 203)
#   CYRIUS_IR=1 build/cycc < /tmp/big.cyr > /dev/null            # rc 1: "error: IR node buffer full"
# Measured 2026-10-08 on 6.7.6 @ 2fb6ad8b; 200 fns pass under CYRIUS_IR=1, 400 do not.
awk 'BEGIN {
  print "var x = 0;"
  for (f = 0; f < 400; f++) {
    printf "fn f%d(a) { var y = a;\n", f
    for (i = 0; i < 500; i++) printf "    y = y + %d;\n", i % 7 + 1
    print "    return y; }"
  }
  print "x = f0(1);"
  print "syscall(60, x & 255);"
}'
