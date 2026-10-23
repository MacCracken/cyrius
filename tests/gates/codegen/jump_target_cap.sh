#!/bin/sh
# the jump-target table overflow bug (v6.3.21) regression: a function exceeding the 1023-entry x86 jump-target
# table MUST hard-error, not silently drop targets (which lets LASE — Load-After-
# Store Elim, CYRIUS_IR=3 — mis-eliminate a load that is live via the unrecorded
# target → wrong codegen). Also asserts the boundary: a function just UNDER the cap
# still compiles. The table + LASE are x86-only.
# 6.7.18 (H): every fn of cycc's OWN source stays under 3/4 of the three per-fn x86 tables (jump targets, jump
# sources, NOP runs), measured by a probe copy of the compiler — _PARSE_FN_DEF_IMPL had saturated its jump sources.
# Mutant: the 6.7.17 tree (src/ at l6718-integ) -> H RED, naming _PARSE_FN_DEF_IMPL (1024 sources) and
# _PARSE_FACTOR_IMPL (898).
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}   # 6.7.16: CYCC= a mutant's cycc, as the other gates take it
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
T=$(mktemp) && [ -f "$T" ] || { echo "FAIL: jump_target_cap: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: jump_target_cap: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -f "$T" "$E"' EXIT

gen() { # <n-branches>
    echo 'fn main(): i64 {'
    echo '  var x = 0;'
    i=0; while [ "$i" -lt "$1" ]; do echo "  if (x == $i) { x = x + 1; }"; i=$((i + 1)); done
    echo '  return x;'
    echo '}'
}

# >1023 jump targets → must hard-error (non-zero) with the cap message.
gen 1100 > "$T"
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: a >1023-jump-target function compiled — should hard-error (the jump-target table overflow bug)"; exit 1
fi
grep -q '1023 jump targets' "$E" || { echo "FAIL: overflow gave the wrong error:"; cat "$E"; exit 1; }

# Under the cap → must still compile clean (no false positive).
gen 1000 > "$T"
"$CC" < "$T" > /dev/null 2>&1 || { echo "FAIL: a 1000-branch function (under the cap) failed to compile"; exit 1; }

# 6.7.16 — the cap is a fn's OWN targets. A generic instance is emitted inline in the fn whose call reaches it, and its
# targets were merged into that fn's table: one fn calling 300 distinct generics at f64 (about 5 targets each) was
# refused here although it has no branch of its own. An instance's range is opaque to the enclosing fn now
# (`_jt_merge`, `_jir_in`, src/frontend/parse/fn/generic.cyr) and its targets stay its own; the program must run (300).
# Mutant (2026-10-20, CYCC= its cycc): the 6.3.35 merge back -> RED here ("1023 jump targets"). On every host:
# tests/tcyr/crossos/generic_forward_chain_deep.tcyr (W).
genw() { # <n distinct generics, each called once from main at f64>
    i=0; while [ "$i" -lt "$1" ]; do echo "fn w$i<T>(x: T): i64 { if (sizeof(T) == 8) { return 1; } return 0; }"; i=$((i + 1)); done
    echo 'fn main(): i64 {'
    echo '  var h: f64 = 1.5;'
    echo '  var s = 0;'
    i=0; while [ "$i" -lt "$1" ]; do echo "  s = s + w$i(h);"; i=$((i + 1)); done
    echo '  return s - 250;'
    echo '}'
}
genw 300 > "$T"
"$CC" < "$T" > "$T.bin" 2> "$E" || { echo "FAIL: one fn instantiating 300 generics was refused: $(grep -m1 error "$E")"; rm -f "$T.bin"; exit 1; }
chmod +x "$T.bin"
rc=0; "$T.bin" || rc=$?
rm -f "$T.bin"
[ "$rc" -eq 50 ] || { echo "FAIL: one fn instantiating 300 generics exited $rc, want 50"; exit 1; }

# 6.7.18 — H: cycc's OWN fns keep headroom under the three per-fn x86 tables: the jump targets (the cap above, a hard
# error past it), the jump sources and the NOP runs (past either, the fn's NOP compaction is skipped — correct code,
# unoptimised). At the 6.7.18 open _PARSE_FN_DEF_IMPL had SATURATED its jump sources (1024 of 1024: cycc skipped its
# compaction) and _PARSE_FACTOR_IMPL used 898; their arms are their own fns now. A probe copy of the tree's compiler
# prints each fn's three counts where the compaction reads them, compiles src/main.cyr, and every fn must stay under
# 3/4 of each cap. The caps are read from the source that enforces them. RED on the 6.7.17 tree (the two fns above).
HCAP_T=$(grep -oE 'if \(jtc < [0-9]+\)' "$ROOT/src/backend/x86/jump.cyr" | head -1 | grep -oE '[0-9]+' || true)
HCAP_S=$(grep -oE '_jsn < [0-9]+ &&' "$ROOT/src/frontend/parse/fn/def.cyr" | head -1 | grep -oE '[0-9]+' || true)
HCAP_N=$(grep -oE '_nrn < [0-9]+ &&' "$ROOT/src/frontend/parse/fn/def.cyr" | head -1 | grep -oE '[0-9]+' || true)
[ -n "$HCAP_T" ] && [ -n "$HCAP_S" ] && [ -n "$HCAP_N" ] || { echo "FAIL: H: a per-fn cap could not be read (jump targets [$HCAP_T], sources [$HCAP_S], NOP runs [$HCAP_N])"; exit 1; }
H=$(mktemp -d) && [ -d "$H" ] || { echo "FAIL: jump_target_cap H: mktemp -d failed"; exit 1; }
trap 'rm -f "$T" "$E"; rm -rf "$H"' EXIT
cp -R "$ROOT/src" "$ROOT/lib" "$H/"
HF="$H/src/frontend/parse/fn/def.cyr"
HA='                var _swn = L64(S + 0x1AC800);'
[ "$(grep -cxF "$HA" "$HF")" -eq 1 ] || { echo "FAIL: H: the compaction's read of the switch-table count is not one line of src/frontend/parse/fn/def.cyr — the probe has no anchor"; exit 1; }
awk -v a="$HA" '{ print } $0 == a { print "                PRSTR(\"fs: \"); PRSTR(S + 0xEC00000 + L64(_fnt_names + fi * 8)); PRSTR(\" \"); PRNUM(L64(S + 0x19E000)); PRSTR(\" \"); PRNUM(_jsn); PRSTR(\" \"); PRNUM(_nrn); PRSTR(\"\\n\");" }' "$HF" > "$HF.p" && mv "$HF.p" "$HF"
(cd "$H" && "$CC" < src/main.cyr > probe 2> probe.err) && [ -s "$H/probe" ] || { echo "FAIL: H: the probe compiler did not build: $(grep -m1 error "$H/probe.err")"; exit 1; }
chmod +x "$H/probe"
(cd "$H" && ./probe < src/main.cyr > /dev/null 2> fs.txt) || { echo "FAIL: H: the probe did not compile src/main.cyr"; exit 1; }
HR=$(awk -v ct="$HCAP_T" -v cs="$HCAP_S" -v cn="$HCAP_N" '
  $1 == "fs:" { n++; if ($2 == "_PARSE_FN_DEF_IMPL") seen = 1
    if ($3 > mt) { mt = $3; ft = $2 }  if ($4 > ms) { ms = $4; fs = $2 }  if ($5 > mn) { mn = $5; fn = $2 }
    if ($3 * 4 >= ct * 3 || $4 * 4 >= cs * 3 || $5 * 4 >= cn * 3) bad = bad sprintf(" %s (targets %d, sources %d, NOP runs %d)", $2, $3, $4, $5) }
  END { printf "%d|%d|%s|%s %d (%s), sources %d (%s), NOP runs %d (%s)\n", n, seen, bad, "targets", mt, ft, ms, fs, mn, fn }' "$H/fs.txt")
HN=${HR%%|*}; HR=${HR#*|}; HS=${HR%%|*}; HR=${HR#*|}; HB=${HR%%|*}; HM=${HR#*|}
[ "$HN" -ge 4000 ] && [ "$HS" -eq 1 ] || { echo "FAIL: H: the probe reported $HN fns (want >= 4000, _PARSE_FN_DEF_IMPL among them: $HS) — the anchor no longer runs for every fn"; exit 1; }
[ -z "$HB" ] || { echo "FAIL: H: cycc fns at 3/4 or more of a per-fn x86 table (caps: $HCAP_T targets, $HCAP_S sources, $HCAP_N NOP runs):$HB"; exit 1; }
echo "  ok   H: $HN fns of cycc's own source, each under 3/4 of the per-fn x86 tables — the most: $HM"

echo "PASS: >1023 jump targets hard-errors, 1000 compiles (the jump-target table overflow bug); 300 generic instances inside one fn are not its targets (6.7.16); every fn of cycc's own source stays under 3/4 of the per-fn x86 tables (6.7.18)"
