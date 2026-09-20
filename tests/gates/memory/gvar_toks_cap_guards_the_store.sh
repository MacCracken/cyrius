#!/bin/sh
# Gate: the gvar_toks cap error must STOP the store, not just report it (6.6.6 bite 19e).
#
# THE DEFECT (measured at 6.6.5). `ERR_MSG` sets `_had_error` and RETURNS — that is deliberate,
# so one run surfaces every violation. The three gvar_toks registration sites read the count,
# called `ERR_MSG` when it had reached 4096, and then stored anyway and bumped the count, so
# the next declaration stored one slot further out:
#
#     var g0 = f(0); ... var g4199 = f(4199);
#       -> error:<source>:4098:12: too many initialized globals (max 4096)     (reported ONCE)
#          ...and ~104 more entries written past the end of the buffer.
#
# gvar_toks is 32768 B at 0x729000 — exactly 4096 entries — so entry 4096 lands at 0x731000,
# the first byte after it, and the run walks on toward TS@0x800000 (reached at entry 110,080).
# Same shape as bite 2f.
#
# ⚠ WHY THE DETECTOR HERE IS STATIC, stated plainly rather than dressed up as a behavioural
# row. The bytes between 0x731000 and 0x800000 are documented FREE (the reclaimed v6.1.27
# output_buf gap), so an overflow of a few hundred entries changes NOTHING observable: measured
# at 4200, 6000, 10000 and 20000 deferred globals, the 6.6.5 compiler and the fixed one produce
# byte-identical stderr, the same exit code and the same (empty) output, within 5% of the same
# wall time. The first observable difference needs 110,080 entries, and the compile is
# quadratic in the global count (20,000 takes ~11 s here; 70,000 exceeds 120 s on BOTH
# compilers, so even that is not a discriminator). A behavioural row at that size would be a
# multi-minute gate that proves what axis 1 proves in milliseconds. So axis 1 is the detector
# and axes 2-4 are the guards that keep the diagnostic and the refusal honest.
#
# AXES
#   1. STATIC — every store into gvar_toks that REGISTERS an entry, and every bump of
#      gvar_cnt, sits inside an `if (_gv_tok_full(S) == 0)` block. The site count is DERIVED
#      from the source, so a fourth registration site added without the guard fails here.
#   2. STATIC — `_gv_tok_full` still REPORTS (calls ERR_MSG with the cap message) and returns
#      1, so the guard cannot be satisfied by silently dropping the diagnostic.
#   3. BEHAVIOURAL — each of the three registration SHAPES over the cap reports the error
#      exactly once, exits 1 and emits no binary: a plain deferred init, a byte-array literal
#      and a top-level destructure. Three sites, three shapes.
#   4. BEHAVIOURAL — the boundary: exactly 4096 deferred globals compiles clean and runs.
#
# MUTATION LEDGER (6.6.6):
#   1. one registration site's guard removed (the plain-init one, restored to the 6.6.5 shape)
#        -> RED axis 1: "unguarded gvar_toks store at parse_decl.cyr:1867", the matching count
#           bump, "2 guards for 3 stores", "2 unguarded sites" (4 checks)
#   2. `_gv_tok_full` returns 1 without calling ERR_MSG
#        -> RED axis 2's report check AND axis 3 for all three shapes (rc 0, a binary emitted
#           past the cap, 0 cap errors) — 10 checks
#   3. `_gv_tok_full`'s room test inverted so it is always full
#        -> RED axis 2's room-test check and all three axis-4 checks
#   4. real tree -> GREEN
# Each mutant is a scratch tree (`git archive HEAD src` + the working src overlaid + the edit)
# with this gate copied in and run with ROOT pointed at it, so axes 1-2 read the MUTATED source
# and axes 3-4 run a compiler built from it.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: gvar_toks_cap_guards_the_store: $CC missing"; exit 1; }
SRC="$ROOT/src/frontend/parse_decl.cyr"
[ -f "$SRC" ] || { echo "FAIL: $SRC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# ── axis 1: every registering store / count bump is guarded ───────────────────────────
# A REGISTERING store writes a token index into gvar_toks (`, sti);`); the two `gi`-indexed
# accesses in the replay loops are bounded by the count itself and are excluded by name below.
awk '
  { line[NR] = $0 }
  END {
    stores = 0; bumps = 0; unguarded = 0; guards = 0
    for (i = 1; i <= NR; i++) {
      if (line[i] ~ /^[ \t]*S64\(S \+ 0x729000 \+ [a-z_0-9]+ \* 8, sti\);/) {
        stores++
        ok = 0
        for (j = i - 6; j < i; j++) if (j > 0 && line[j] ~ /_gv_tok_full\(S\) == 0/) ok = 1
        if (!ok) { unguarded++; printf "  FAIL: unguarded gvar_toks store at parse_decl.cyr:%d\n", i }
      }
      if (line[i] ~ /^[ \t]*S64\(S \+ 0x19A000, /) {
        bumps++
        ok = 0
        for (j = i - 8; j < i; j++) if (j > 0 && line[j] ~ /_gv_tok_full\(S\) == 0/) ok = 1
        if (!ok) { unguarded++; printf "  FAIL: unguarded gvar_cnt bump at parse_decl.cyr:%d\n", i }
      }
      if (line[i] ~ /_gv_tok_full\(S\) == 0/) guards++
    }
    printf "AXIS1 stores=%d bumps=%d guards=%d unguarded=%d\n", stores, bumps, guards, unguarded
  }
' "$SRC" > "$WORK/a1.txt"
grep '^  FAIL' "$WORK/a1.txt" || true
A1=$(grep '^AXIS1' "$WORK/a1.txt")
A1_STORES=$(echo "$A1" | sed 's/.*stores=\([0-9]*\).*/\1/')
A1_BUMPS=$(echo "$A1" | sed 's/.*bumps=\([0-9]*\).*/\1/')
A1_GUARDS=$(echo "$A1" | sed 's/.*guards=\([0-9]*\).*/\1/')
A1_BAD=$(echo "$A1" | sed 's/.*unguarded=\([0-9]*\).*/\1/')
NF1=$(grep -c '^  FAIL' "$WORK/a1.txt" || true)
NFAIL=$((NFAIL + NF1))
# Anti-vacuity: the axis must have found the sites at all. Three registration sites exist
# (plain init, byte-array literal, top-level destructure); an awk regex that stopped matching
# would otherwise report "0 unguarded" and read green.
[ "$A1_STORES" -ge 3 ] || bad "axis 1 found only $A1_STORES gvar_toks registration stores; expected at least 3 (the regex has rotted)"
[ "$A1_BUMPS" -ge 3 ] || bad "axis 1 found only $A1_BUMPS gvar_cnt bumps; expected at least 3"
[ "$A1_GUARDS" -eq "$A1_STORES" ] || bad "axis 1: $A1_GUARDS guards for $A1_STORES stores — they must be 1:1"
[ "$A1_BAD" = "0" ] || bad "axis 1: $A1_BAD unguarded sites"

# ── axis 2: the guard still REPORTS, and says 1 when full ─────────────────────────────
GF=$(awk '/^fn _gv_tok_full\(S\): i64 \{/,/^\}/' "$SRC")
echo "$GF" | grep -q 'ERR_MSG(S, "too many initialized globals (max 4096)", 39);' \
    || bad "axis 2: _gv_tok_full no longer reports the cap error"
echo "$GF" | grep -q 'return 1;' || bad "axis 2: _gv_tok_full never returns 1"
echo "$GF" | grep -q 'if (L64(S + 0x19A000) < 4096) { return 0; }' \
    || bad "axis 2: _gv_tok_full's room test is not the gvar_cnt-vs-4096 one"

# ── axis 3: each registration SHAPE over the cap reports once and refuses ─────────────
gen() {
    _kind=$1; _n=$2; _out=$3
    : > "$_out"
    case "$_kind" in
      plain)  printf 'fn gtf(n: i64): i64 { return n + 1; }\n' >> "$_out"
              _i=0; while [ "$_i" -lt "$_n" ]; do printf 'var gtg%s = gtf(%s);\n' "$_i" "$_i" >> "$_out"; _i=$((_i + 1)); done ;;
      arr)    _i=0; while [ "$_i" -lt "$_n" ]; do printf 'var gta%s[4] = { 1, 2, 3, 4 };\n' "$_i" >> "$_out"; _i=$((_i + 1)); done ;;
      destr)  printf 'fn gtp(): (i64, i64) { return (1, 2); }\n' >> "$_out"
              _i=0; while [ "$_i" -lt "$_n" ]; do printf 'var gtd%s, gte%s = gtp();\n' "$_i" "$_i" >> "$_out"; _i=$((_i + 1)); done ;;
    esac
    printf 'syscall(60, 0);\n' >> "$_out"
}
for kind in plain arr destr; do
    gen "$kind" 4200 "$WORK/$kind.cyr"
    rm -f "$WORK/$kind.bin"
    set +e; "$CC" < "$WORK/$kind.cyr" > "$WORK/$kind.bin" 2> "$WORK/$kind.err"; rc=$?; set -e
    [ "$rc" = "1" ] || bad "axis 3 [$kind]: compiler exited $rc, want 1"
    [ -s "$WORK/$kind.bin" ] && bad "axis 3 [$kind]: a binary was emitted past the cap"
    n=$(grep -c 'too many initialized globals (max 4096)' "$WORK/$kind.err" || true)
    [ "$n" = "1" ] || bad "axis 3 [$kind]: $n cap errors, want exactly 1"
done

# ── axis 4: the boundary — exactly 4096 deferred globals still compiles and runs ──────
gen plain 4096 "$WORK/edge.cyr"
rm -f "$WORK/edge.bin"
set +e; "$CC" < "$WORK/edge.cyr" > "$WORK/edge.bin" 2> "$WORK/edge.err"; erc=$?; set -e
[ "$erc" = "0" ] || bad "axis 4: 4096 deferred globals should compile, got rc=$erc"
if [ -s "$WORK/edge.bin" ]; then
    chmod +x "$WORK/edge.bin"
    set +e; "$WORK/edge.bin" > /dev/null 2>&1; err=$?; set -e
    [ "$err" = "0" ] || bad "axis 4: the 4096-global program exited $err, want 0"
else
    bad "axis 4: no binary for a program exactly at the cap"
fi
en=$(grep -c 'too many initialized globals' "$WORK/edge.err" || true)
[ "$en" = "0" ] || bad "axis 4: the cap fired at exactly 4096 (off by one)"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: gvar_toks_cap_guards_the_store: $NFAIL checks"
    exit 1
fi
echo "PASS: the gvar_toks cap stops the store ($A1_STORES registration sites + $A1_BUMPS count bumps, all guarded; 3 shapes refused at 4200; 4096 still compiles)"
exit 0
