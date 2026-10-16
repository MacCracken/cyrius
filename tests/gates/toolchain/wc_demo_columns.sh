#!/bin/sh
# wc_demo_columns.sh — 6.7.12. programs/wc.cyr (a demo) prints its three counts so they always
# parse back, and splits words on the C `isspace` set.
#
# THE DEFECT (issues/archived/2026-10-12-wc-demo-columns-run-together-and-whitespace-set.md): `print_num`
# padded each count to 8 columns and wrote no separator, so a count of 8 or more digits fused with
# the one before it — a 10,000,000-byte one-word input printed `       0       110000000` — and
# `is_ws` took space, tab, LF and CR only, so `a\vb\fc\n` counted 1 word (GNU `wc`: 3).
#
# ROWS
#   W1  a 10,000,000-byte one-word input (no newline): the fields read back as 0 1 10000000
#   W2  `a\vb\fc\n`: 1 line, 3 words, 6 bytes (VT and FF separate words)
#   W3  every one of the six C `isspace` bytes separates words, and a non-space byte (0xA0) does not
#   W4  the counts are right-justified to the widest, one space apart (GNU's layout:
#       `       0        1 10000000`, `1 3 6`)
# No gate ran the demos before this one.
#
# PROVEN RED (run when written, `WC_SRC=<file>` builds another source): the 6.7.11 programs/wc.cyr
# fails W1 (`0 110000000`), W2 (1 word), W3 (5 words) and W4; this tree with the separator dropped
# fails all four (the fields fuse); with is_ws back to 32 / 9 / 10 / 13, W2, W3 and W4.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=wc_demo_columns
CC=${CYCC:-"$ROOT/build/cycc"}
SRC=${WC_SRC:-"$ROOT/programs/wc.cyr"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
"$CC" < "$SRC" > "$W/wc" 2> "$W/cc.err" && [ -s "$W/wc" ] \
  || { echo "FAIL: $G: $SRC does not build:"; tail -3 "$W/cc.err"; exit 1; }
chmod +x "$W/wc"
FAIL=0
ok() { echo "  ok: $*"; }
fail() { echo "  FAIL: $*"; FAIL=1; }

head -c 10000000 /dev/zero | tr '\0' a > "$W/big"
"$W/wc" < "$W/big" > "$W/o1"
F=$(awk '{ print $1 " " $2 " " $3 " " NF }' "$W/o1")
if [ "$F" = "0 1 10000000 3" ]; then ok "W1 a 10,000,000-byte word: the fields read back as 0 1 10000000"
else fail "W1 the fields read back as '$F' (output: '$(cat "$W/o1")')"; fi

printf 'a\vb\fc\n' | "$W/wc" > "$W/o2"
F=$(awk '{ print $1 " " $2 " " $3 }' "$W/o2")
if [ "$F" = "1 3 6" ]; then ok "W2 a<VT>b<FF>c<LF>: 1 line, 3 words, 6 bytes"
else fail "W2 a<VT>b<FF>c<LF> counted '$F'"; fi

printf 'a b\tc\nd\ve\ff\rg\240h' | "$W/wc" > "$W/o3"
F=$(awk '{ print $2 }' "$W/o3")
if [ "$F" = 7 ]; then ok "W3 space, tab, LF, VT, FF and CR each separate words; 0xA0 does not (7 words)"
else fail "W3 counted '$F' words, not 7 ('$(cat "$W/o3")')"; fi

if [ "$(cat "$W/o1")" = "       0        1 10000000" ] && [ "$(cat "$W/o2")" = "1 3 6" ]; then
    ok "W4 right-justified to the widest count, one space apart"
else fail "W4 the layout is '$(cat "$W/o1")' / '$(cat "$W/o2")'"; fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G"; exit 1; }
echo "PASS: $G"
exit 0
