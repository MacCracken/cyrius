#!/bin/sh
# Stand-in cxvm (the checkout's programs/cxvm.cyr in the xb golden): runs a stub/main_cx.sh
# "bytecode" from stdin.
read -r tag code
[ "$tag" = CYX ] || exit 99
exit "$code"
