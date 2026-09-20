#!/bin/sh
# tests/gates/toolchain/check_targeted_run_selects.sh — 6.6.6 (bite 27a)
#
# A TARGETED CHECK RUN RUNS THAT SUITE — AND AN UNKNOWN SELECTOR IS A LOUD ERROR.
#
# THE DEFECT. `sh scripts/check.sh <suite>` ran the WHOLE suite. check.sh forwarded the
# argument to the check binary — bite 25b even gated that it was forwarded — and
# programs/checks/main.cyr threw it away: it includes lib/args.cyr, never called
# args_init(), and no line of it read argv(n). `grep -n 'args_init()' programs/checks/*.cyr`
# returned nothing. So `sh scripts/check.sh nosuchsuitename` ran the driver's FULL nine-phase
# run — 130 registered gate rows at 70e4c200 — for thirteen minutes and reported on all of
# them; an unrecognised name was not an error, it was a full run. check.sh's own comment at
# the call site ("On a targeted run (a suite name was passed), run only the driver")
# described an intention. ⚠ Not "and the 60 shell gates too", which is what the first cut of
# this header and the CHANGELOG bullet both said: the pre-fix targeted block was
# `"$CHECK_BIN" "$@" || rc; exit rc`, so it exited BEFORE check.sh's own `_chk_gate` block
# and those 60 never ran on a targeted invocation at all. DERIVE both counts
# (`grep -cE '^_chk_gate' scripts/check.sh`, and the `_gate(…, "tests/gates/…")` literals in
# programs/checks/*.cyr) rather than quoting this line.
#
# WHAT IS PINNED. Selection on BOTH halves of a run, because a run is the cyrius driver AND
# the shell gates and covering one half silently means "all of the other":
#   axis 1  the driver's suite table answers --list-suites, and it is a real list
#   axis 2  an unknown suite is exit != 0, names the alternatives, and RUNS NOTHING
#   axis 3  a driver suite runs ITS rows and NOT another suite's -> strictly fewer than a
#           full run, proven from two cheap suites rather than by sitting through 13 minutes
#   axis 4  a gate selector registered ONLY in programs/checks/*.cyr resolves and runs
#           exactly that gate (the first cut of the fix read check.sh's own _chk_gate lines
#           only, so every gate registered in the DRIVER — the large majority of the
#           registry — answered "unknown")
#   axis 5  a gate selector registered ONLY in scripts/check.sh resolves the same way
#   axis 6  a bucket selector runs every gate in that bucket and nothing else, and the
#           end-of-run summary scopes NOT RUN to the selection instead of the other ~190
#   axis 7  a red gate in a targeted run still makes the run red
#   axis 8  ⭐ EVERY selector `--list` advertises resolves — and resolves to ONE kind. The
#           first cut of the fix refused a name two vocabularies claimed as "ambiguous", so
#           `check.sh heapmap` (a driver suite `--list` prints, and the very selector the
#           CHANGELOG measured at 25 ms against the 13-minute full run) exited 2 and could
#           not be run at all, while `--list` advertised it under BOTH headings with no
#           marker. Derived over all three vocabularies it was the ONLY collision — one
#           advertised selector made unreachable to guard against a case that does not
#           otherwise exist. Without this axis the next gate file named after a suite rots
#           the same way in silence: axis 3 runs `$D/drv heapmap` DIRECTLY and never goes
#           through check.sh's resolver.
#   axis 9  the CENSUS for the root cause, over the whole tree and not just the one file:
#           no entry program reads argv()/argc() without calling args_init(). The bite's
#           own grep was scoped to programs/checks/*.cyr and missed
#           programs/cyrius_type_audit.cyr, whose two documented flags (`--summary`,
#           `--module=`) had therefore never once worked.
#
# INDEPENDENT DERIVATION. Axes 4-6 never read check.sh's "-> N of M" line: each fake gate
# APPENDS ITS OWN NAME to a log when it runs, so the actual set comes from the filesystem,
# while the expected set is the one this gate wrote into the fake registry. Axis 3 counts
# rows out of the driver's own tally line and cross-checks them against the section headings
# in its output.
#
# MUTATION PROOF (6.6.6, in a git-archive scratch tree, never the repo):
#   * check.sh's targeted block restored to the pre-fix `"$CHECK_BIN" "$@"; exit $?` ->
#     15 assertions RED across axes 4, 5, 6, 7 and 7b (nothing is selected, no gate runs,
#     and an unknown selector exits 0).
#   * the driver half of the registry (_chk_driver_gate_manifest) dropped from
#     _chk_gate_registry -> 8 RED, ALL of them axes 4 and 6 for the zzdrv side; the zzsh
#     side stays green. That is exactly the shape of the first cut of this fix, which read
#     check.sh's own _chk_gate lines only and called every driver-registered gate unknown.
#   * _CHK_MANIFEST left at the full registry on a targeted run -> 5 RED on axis 6 (the
#     summary lists the whole rest of the registry as NOT RUN and the run exits 1 although
#     every selected gate passed).
#   * programs/checks/main.cyr reverted to HEAD (no args_init, no suite table) -> measured
#     UNDER `timeout 20`, because the whole point is that an unselective driver turns every
#     probe into a 13-minute full run: `--list-suites` printed 181 lines of audit output
#     instead of 9 names and had to be killed (rc 124), and `nosuchsuitename` likewise ran
#     the audit. Axes 1, 2 and 3 all RED; the gate itself is not run against that driver
#     because it would take over an hour to fail.
# MUTATION PROOF for axes 8 and 9 (added by bite 27's review, same scratch-tree recipe):
#   * the "ambiguous -> exit 2" refusal put back in _chk_resolve -> 1 RED on axis 8 ("1
#     advertised name(s) do not resolve when typed bare"). That is the shipped defect the
#     axis was added for.
#   * the suite:/bucket:/gate: qualifier parsing removed -> 3 RED on axis 8: all 210
#     advertised selectors unresolvable, all 210 mismatched, and the collision reachable by
#     neither spelling.
#   * the shadow marker dropped from _chk_annotate -> 1 RED ("'heapmap' is claimed by two
#     vocabularies and --list does not mark it"); everything else stays green, so the marker
#     and the resolution are proven independently.
#   * args_init() removed from programs/cyrius_type_audit.cyr -> 1 RED on axis 9, naming
#     that file. An invented probe (a new programs/*.cyr that includes lib/args.cyr and
#     calls argc() with no args_init anywhere) reddens it the same way, so the axis is
#     catching the SHAPE and not one path.
#   * ⚠ ANTI-VACUOUS, and it caught a real hole in this axis: with the `fn argv|argc|
#     args_init` definition lines NOT cut out of _c9_strip, the args_init-removed mutation
#     above stayed GREEN — lib/args.cyr's own `fn args_init() {` counted as a call for every
#     program that includes it, so every program looked initialised. Both numbers moved when
#     it was fixed (20 argv readers -> 18). The floors (>= 50 entries, >= 5 files reading
#     argv, >= 3 programs reaching argv through their closure) exist for the same reason.
#   * programs/checks/main.cyr reverted with args_init removed -> axis 9 cannot be measured
#     that way: axes 1-3 hang the gate for 13 minutes first (confirmed under `timeout 120`),
#     which is why that mutation is recorded above and not repeated here.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

# ── the driver half: build the check binary from the tree, into $D ────────────────────
# Never build/cyrius_check: this gate must test the source in the tree, and it must not
# write the tree (tests/gates/toolchain/gates_never_write_tree.sh).
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }
if ! cat programs/checks/main.cyr | "$CC" > "$D/drv" 2>"$D/drv.err"; then
    echo "FAIL: the check driver did not compile"
    cat "$D/drv.err"
    exit 1
fi
chmod +x "$D/drv"
[ -s "$D/drv" ] || { echo "FAIL: the check driver compiled to an EMPTY binary"; exit 1; }

echo "axis 1: the driver names its own suites"
"$D/drv" --list-suites > "$D/suites" 2>&1 || _fail "--list-suites exited non-zero"
NSUITE=$(grep -c . "$D/suites" || true)
[ "$NSUITE" -ge 5 ] || _fail "--list-suites printed $NSUITE name(s); expected >= 5 — the suite table is not being read"
NUNIQ=$(sort -u "$D/suites" | grep -c . || true)
[ "$NUNIQ" = "$NSUITE" ] || _fail "the suite list has duplicates ($NSUITE rows, $NUNIQ distinct)"
# Names, not pointers: the first cut printed nine pool addresses because `println` is
# overloaded and an untyped i64 resolves to the numeric printer.
if grep -qE '^[0-9]+$' "$D/suites"; then
    _fail "--list-suites printed bare numbers — the names are being printed as integers"
fi

echo "axis 2: an unknown suite is a loud error that runs nothing"
RC2=0
"$D/drv" nosuchsuitename > "$D/unk.out" 2>"$D/unk.err" || RC2=$?
[ "$RC2" != "0" ] || _fail "the driver exited 0 on an unknown suite name"
grep -q "nosuchsuitename" "$D/unk.err" || _fail "the driver's error does not name the selector it rejected"
# It must name the alternatives, and they must be the real ones.
while read -r s; do
    [ -n "$s" ] || continue
    grep -q "^  $s$" "$D/unk.err" || _fail "the unknown-selector error does not list the valid suite '$s'"
done < "$D/suites"
grep -q "Cyrius v2.0 Audit" "$D/unk.out" && _fail "the driver STARTED the audit after rejecting the selector"
[ ! -s "$D/unk.out" ] || _fail "an unknown selector produced $(wc -c < "$D/unk.out") bytes of run output"

echo "axis 3: a suite runs its own rows and not another suite's"
_total_of() {  # last "N passed, M failed (T total)" line -> T
    sed -n 's/.*(\([0-9][0-9]*\) total).*/\1/p' "$1" | tail -1
}
"$D/drv" heapmap > "$D/heapmap.out" 2>&1 || _fail "the heapmap suite exited non-zero"
"$D/drv" idpool  > "$D/idpool.out"  2>&1 || _fail "the idpool suite exited non-zero"
TH=$(_total_of "$D/heapmap.out")
TI=$(_total_of "$D/idpool.out")
[ -n "$TH" ] && [ "$TH" -ge 1 ] || _fail "the heapmap suite reported no rows at all (total='$TH')"
[ -n "$TI" ] && [ "$TI" -ge 1 ] || _fail "the idpool suite reported no rows at all (total='$TI')"
# Disjoint: each run must carry its own section heading and NOT the other's. Two suites
# that both produce rows and share none means a full run (which is every suite, in order)
# has at least TH+TI rows — strictly more than either. That is the "strictly fewer rows
# than a full run" property, without spending 13 minutes measuring a full run.
grep -q "Heap Map" "$D/heapmap.out" || _fail "the heapmap suite did not run the heap-map section"
grep -q "Heap Map" "$D/idpool.out"  && _fail "the idpool suite ALSO ran the heap map — the selector is not selecting"
grep -q "Self-Hosting" "$D/heapmap.out" && _fail "the heapmap suite ALSO ran the self-host gate — the selector is not selecting"
grep -q "identifier program" "$D/idpool.out" || _fail "the idpool suite did not run the identifier-pool rows"
SUM=$((TH + TI))
[ "$SUM" -gt "$TH" ] || _fail "heapmap ($TH rows) + idpool ($TI rows) is not more than heapmap alone — the suites are not disjoint"
echo "  heapmap=$TH row(s), idpool=$TI row(s), a full run is at least $SUM"

# ── the shell-gate half: the REAL check.sh over a FAKE registry ───────────────────────
# Fake bucket names (zzdrv/zzsh) so nothing here can select, or be selected by, one of the
# real registrations. The registry has two halves and both are exercised: zzdrv is
# registered ONLY in programs/checks/main.cyr (the driver's `_gate(...)` rows) and zzsh
# ONLY in scripts/check.sh (`_chk_gate`).
W="$D/w"
mkdir -p "$W/root/scripts" "$W/root/build" "$W/root/programs/checks" "$W/root/lib" \
         "$W/root/tests/gates/zzdrv" "$W/root/tests/gates/zzsh" "$W/tmp" "$W/home"
cp "$ROOT/scripts/check.sh" "$W/root/scripts/check.sh"
cp VERSION "$W/root/"
: > "$W/root/lib/placeholder.cyr"
printf '#!/bin/sh\nexit 0\n' > "$W/root/build/cycc"
chmod +x "$W/root/build/cycc"
printf '#!/bin/sh\nmkdir -p "$CYRIUS_HOME/bin"\nexit 0\n' > "$W/root/scripts/install.sh"
chmod +x "$W/root/scripts/install.sh"
cat > "$W/root/build/cyrius_check" <<STUB
#!/bin/sh
if [ "\$1" = "--list-suites" ]; then printf 'alpha\nbeta\n'; exit 0; fi
echo "DRIVER \$*" >> "$W/ran.log"
exit 0
STUB
chmod +x "$W/root/build/cyrius_check"
touch -d '2038-01-01' "$W/root/build/cyrius_check"

# Three gates in zzdrv, two in zzsh. Each records THAT IT RAN, in the gate's own words.
: > "$W/ran.log"
DRV_GATES="one two three"
SH_GATES="four five"
for g in $DRV_GATES; do
    printf '#!/bin/sh\necho "GATE zzdrv/%s" >> "%s"\nexit 0\n' "$g" "$W/ran.log" \
        > "$W/root/tests/gates/zzdrv/$g.sh"
done
for g in $SH_GATES; do
    printf '#!/bin/sh\necho "GATE zzsh/%s" >> "%s"\nexit 0\n' "$g" "$W/ran.log" \
        > "$W/root/tests/gates/zzsh/$g.sh"
done
# The driver-side registry: literal paths inside a _gate(...) call, as main.cyr spells them.
{
    for g in $DRV_GATES; do
        printf '    _gate("fake %s", "tests/gates/zzdrv/%s.sh");\n' "$g" "$g"
    done
} > "$W/root/programs/checks/main.cyr"
# The check.sh-side registry: appended _chk_gate lines, as check.sh spells them.
for g in $SH_GATES; do
    printf '_chk_gate "$ROOT/tests/gates/zzsh/%s.sh"\n' "$g" >> "$W/root/scripts/check.sh"
done

# Expected counts, known because this gate WROTE the registry — never read back out of
# check.sh's own output.
EXP_DRV=$(echo $DRV_GATES | wc -w)
EXP_SH=$(echo $SH_GATES | wc -w)

_run() {  # $1 = selector (or empty); sets RC, and $W/ran.log records what really ran
    : > "$W/ran.log"
    RC=0
    if [ $# -gt 0 ] && [ -n "$1" ]; then
        ( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" \
            sh scripts/check.sh "$1" ) > "$W/out" 2>&1 || RC=$?
    else
        ( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" \
            sh scripts/check.sh ) > "$W/out" 2>&1 || RC=$?
    fi
}
_ran() { grep -c "^GATE " "$W/ran.log" || true; }

echo "axis 4: a gate registered only in the DRIVER resolves and runs alone"
_run one
[ "$(_ran)" = "1" ] || _fail "selector 'one' ran $(_ran) gate(s), expected 1"
grep -qx "GATE zzdrv/one" "$W/ran.log" || _fail "selector 'one' did not run tests/gates/zzdrv/one.sh"
grep -q "^DRIVER " "$W/ran.log" && _fail "a gate selector also ran the check driver"

echo "axis 5: a gate registered only in check.sh resolves the same way"
_run four
[ "$(_ran)" = "1" ] || _fail "selector 'four' ran $(_ran) gate(s), expected 1"
grep -qx "GATE zzsh/four" "$W/ran.log" || _fail "selector 'four' did not run tests/gates/zzsh/four.sh"

echo "axis 6: a bucket runs that bucket, and the summary is scoped to it"
_run zzdrv
NRAN=$(_ran)
[ "$NRAN" = "$EXP_DRV" ] || _fail "bucket 'zzdrv' ran $NRAN gate(s), expected $EXP_DRV"
grep -q "GATE zzsh/" "$W/ran.log" && _fail "bucket 'zzdrv' also ran gates from zzsh"
# The count line, not the word: "0 NOT RUN" is what the summary prints when the manifest
# was narrowed, and the "NOT RUN — these did NOT execute" block is what it prints when it
# was not. A bare grep for "NOT RUN" matches the count line itself (measured).
grep -q "NOT RUN — these did NOT execute" "$W/out" && _fail "a targeted run listed gates as NOT RUN — the manifest was not narrowed to the selection"
grep -q "0 NOT RUN" "$W/out" || _fail "the targeted run's summary does not report 0 NOT RUN"
grep -q "$EXP_DRV of $EXP_DRV produced a result" "$W/out" || _fail "the summary does not scope its total to the $EXP_DRV selected gates"
grep -q "ALL GREEN" "$W/out" || _fail "a green targeted bucket run did not report ALL GREEN"
[ "$RC" = "0" ] || _fail "a green targeted bucket run exited $RC"
_run zzsh
[ "$(_ran)" = "$EXP_SH" ] || _fail "bucket 'zzsh' ran $(_ran) gate(s), expected $EXP_SH"

echo "axis 7: a red gate keeps a targeted run red"
printf '#!/bin/sh\necho "GATE zzdrv/two" >> "%s"\nexit 3\n' "$W/ran.log" > "$W/root/tests/gates/zzdrv/two.sh"
_run zzdrv
[ "$RC" != "0" ] || _fail "a targeted bucket run with a failing gate exited 0"
[ "$(_ran)" = "$EXP_DRV" ] || _fail "the failing gate stopped the other gates in the bucket ($(_ran) of $EXP_DRV ran)"

echo "axis 7b: an unknown selector through check.sh runs nothing and stages no home"
_run definitely-not-a-selector
[ "$RC" = "2" ] || _fail "check.sh exited $RC on an unknown selector, expected 2"
[ "$(_ran)" = "0" ] || _fail "an unknown selector still ran $(_ran) gate(s)"
grep -q "definitely-not-a-selector" "$W/out" || _fail "check.sh's error does not name the rejected selector"
grep -q "gate buckets" "$W/out" || _fail "check.sh's error does not list the valid selectors"
LEFT=$(ls -d "$W"/tmp/cyrius-check-home.* 2>/dev/null | wc -l)
[ "$LEFT" = "0" ] || _fail "$LEFT staged CYRIUS_HOME tree(s) left behind by a rejected selector"

echo "axis 8: every selector --list advertises resolves, to exactly one kind"
# The REAL vocabularies, in a scratch root, so nothing here can rebuild build/cyrius_check,
# stage a home, or reap another lane's. check.sh derives its gate names by grepping
# scripts/check.sh and programs/checks/*.cyr, so those two are all that has to be real —
# the driver binary is the one this gate already compiled from the tree.
R8="$D/r8"
mkdir -p "$R8/scripts" "$R8/build" "$R8/programs/checks" "$R8/lib" "$R8/tmp"
cp "$ROOT/scripts/check.sh" "$R8/scripts/check.sh"
cp "$ROOT"/programs/checks/*.cyr "$R8/programs/checks/"
cp VERSION "$R8/"
: > "$R8/lib/placeholder.cyr"
printf '#!/bin/sh\nexit 0\n' > "$R8/build/cycc"
chmod +x "$R8/build/cycc"
cp "$D/drv" "$R8/build/cyrius_check"
touch -d '2038-01-01' "$R8/build/cyrius_check"
_r8() { ( cd "$R8" && env -u CYRIUS_HOME TMPDIR="$R8/tmp" sh scripts/check.sh "$@" ); }

_r8 --list > "$D/list" 2>"$D/list.err" || _fail "check.sh --list exited non-zero"
# Qualify each advertised name with the heading it was printed under. That heading is the
# CLAIM ("this is a driver suite"); --resolve is the behaviour. Comparing them is the point.
awk '/^driver suites/{k="suite";next} /^gate buckets/{k="bucket";next} /^gates \(/{k="gate";next} /^  [^ ]/{ if(k!=""){print k":"$1} }' \
    "$D/list" > "$D/qual"
NQ=$(grep -c . "$D/qual" || true)
# Floor: a --list that printed almost nothing would make this axis vacuously green. The
# registry is ~200 gates plus 9 suites plus 9 buckets; 100 is a floor, not a count.
[ "$NQ" -ge 100 ] || _fail "--list advertised only $NQ selector(s) — too few to be the real registry; axis 8 would be vacuous"
RC8=0
# shellcheck disable=SC2046  # the selectors are shell words by construction
_r8 --resolve $(cat "$D/qual") > "$D/res" 2>"$D/res.err" || RC8=$?
[ "$RC8" = "0" ] || _fail "$(grep -c '^UNRESOLVED' "$D/res" || true) selector(s) --list advertises do NOT resolve (rc $RC8)"
NR=$(grep -c . "$D/res" || true)
[ "$NR" = "$NQ" ] || _fail "--resolve answered for $NR of the $NQ advertised selectors"
# Every answer must be the kind its heading claimed, and name the same thing.
paste -d' ' "$D/qual" "$D/res" \
    | awk '{ split($1, a, ":"); if (a[1] != $2 || a[2] != $3) print }' > "$D/mism"
NM=$(grep -c . "$D/mism" || true)
[ "$NM" = "0" ] || { _fail "$NM advertised selector(s) resolve to a different kind than the heading they are printed under"; head -3 "$D/mism" | sed 's/^/      /'; }
# And the BARE name has to resolve too — that is the spelling a human types.
sed 's/^[a-z]*://' "$D/qual" | sort -u > "$D/bare"
RC8B=0
# shellcheck disable=SC2046
_r8 --resolve $(cat "$D/bare") > "$D/resb" 2>/dev/null || RC8B=$?
[ "$RC8B" = "0" ] || _fail "$(grep -c '^UNRESOLVED' "$D/resb" || true) advertised name(s) do not resolve when typed bare — the refusal this axis exists for"
# A name two vocabularies claim must be MARKED where it is advertised, and BOTH spellings
# must work and disagree. Derived here by counting duplicates, never read out of check.sh.
sed 's/^[a-z]*://' "$D/qual" | sort | uniq -d > "$D/dups"
while read -r dn; do
    [ -n "$dn" ] || continue
    grep -q "^  $dn  *\[" "$D/list" || _fail "'$dn' is claimed by two vocabularies and --list does not mark it"
    K1=$(_r8 --resolve "suite:$dn" 2>/dev/null | awk '{print $1}')
    K2=$(_r8 --resolve "gate:$dn"  2>/dev/null | awk '{print $1}')
    [ "$K1" = "suite" ] && [ "$K2" = "gate" ] || _fail "the collision '$dn' is not reachable as both suite:$dn ($K1) and gate:$dn ($K2)"
done < "$D/dups"
NDUP=$(grep -c . "$D/dups" || true)
# A qualifier that names nothing in THAT vocabulary is an explicit request and must fail.
RC8C=0
_r8 "suite:$(head -1 "$D/bare")zzz" > "$D/badq" 2>&1 || RC8C=$?
[ "$RC8C" = "2" ] || _fail "a qualified selector naming nothing exited $RC8C, expected 2"
echo "  $NQ advertised selector(s) all resolve; $NDUP collision(s), each reachable both ways"

echo "axis 9: no entry program reads argv()/argc() without calling args_init()"
# The root cause, censused as a SHAPE. Per PROGRAM, not per file: cbt/build.cyr reads argv
# and cbt/cyrius.cyr calls args_init, and that is correct — what must never happen is a
# program whose whole include closure reads argv and never initialises it. Entry points are
# DERIVED (every .cyr under programs/ and cbt/ that nothing includes), comments and string
# literals are stripped first (the check driver's own regression suite talks ABOUT argc() in
# its messages), and an include that cannot be resolved is a FAILURE, not a silent skip —
# a resolver that quietly loses files reports zero offenders because it looked at nothing.
#
# ⛔ A DEFINITION IS NOT A CALL, and getting that wrong makes this axis VACUOUS. The first
# cut matched `args_init(` anywhere, so lib/args.cyr's own `fn args_init() {` counted — and
# since every program that reads argv includes lib/args.cyr, EVERY program looked
# initialised and EVERY program looked like an argv reader. Measured: with the fix removed
# from programs/cyrius_type_audit.cyr the axis still passed. So `fn`-headed lines for these
# three names are cut before matching, and the mutation ledger records the re-measurement.
_c9_strip() {
    sed 's/#.*//' "$1" | sed 's/"[^"]*"//g' \
        | grep -vE '^[[:space:]]*(pub[[:space:]]+|public[[:space:]]+|private[[:space:]]+)*fn[[:space:]]+(argv|argc|args_init)[[:space:]]*\('
}
find programs cbt -name '*.cyr' | LC_ALL=C sort > "$D/c9.all"
find programs cbt lib src -name '*.cyr' -exec sed 's/#.*//' {} + \
    | grep -oE 'include[[:space:]]+"[^"]+"' | sed 's/.*"\(.*\)"/\1/' | LC_ALL=C sort -u > "$D/c9.inc"
LC_ALL=C comm -23 "$D/c9.all" "$D/c9.inc" > "$D/c9.entries"
NE=$(grep -c . "$D/c9.entries" || true)
[ "$NE" -ge 50 ] || _fail "the census found only $NE entry program(s) — too few to be programs/ + cbt/; axis 9 would be vacuous"
# One pass over every source file: who reads argv, who calls args_init, and who includes
# what (resolved once, here — not 86 times inside the closure walk below).
: > "$D/c9.uses"; : > "$D/c9.init"; : > "$D/c9.edges"
for f in $(find programs cbt lib src -name '*.cyr' | LC_ALL=C sort); do
    _c9_strip "$f" > "$D/c9.s"
    grep -qE '(^|[^_A-Za-z0-9])arg[vc][[:space:]]*\(' "$D/c9.s" && echo "$f" >> "$D/c9.uses"
    grep -qE '(^|[^_A-Za-z0-9])args_init[[:space:]]*\(' "$D/c9.s" && echo "$f" >> "$D/c9.init"
    _dir=$(dirname "$f")
    sed 's/#.*//' "$f" | grep -oE 'include[[:space:]]+"[^"]+"' | sed 's/.*"\(.*\)"/\1/' \
        | while read -r i; do
            if   [ -f "$i" ];       then printf '%s %s\n' "$f" "$i"
            elif [ -f "$_dir/$i" ]; then printf '%s %s\n' "$f" "$_dir/$i"
            else printf '%s UNRESOLVED:%s\n' "$f" "$i"
            fi
          done >> "$D/c9.edges"
done
# `join` below needs both sides ordered the same way; C collation, field 1, no exceptions.
LC_ALL=C sort -k1,1 "$D/c9.edges" > "$D/c9.edges.s"
LC_ALL=C sort -u -o "$D/c9.uses" "$D/c9.uses"
LC_ALL=C sort -u -o "$D/c9.init" "$D/c9.init"
NUSES=$(grep -c . "$D/c9.uses" || true)
[ "$NUSES" -ge 5 ] || _fail "only $NUSES file(s) in the tree read argv()/argc() — the scanner is blind, not the tree clean"
C9_UNRES=0
C9_ARGV=0
C9_BAD=""
for e in $(cat "$D/c9.entries"); do
    printf '%s\n' "$e" > "$D/c9.cl"
    while : ; do
        _n=$(grep -c . "$D/c9.cl" || true)
        join -j 1 -o 1.2 "$D/c9.edges.s" "$D/c9.cl" > "$D/c9.new" 2>/dev/null || : > "$D/c9.new"
        LC_ALL=C sort -u "$D/c9.cl" "$D/c9.new" > "$D/c9.cl2"; mv "$D/c9.cl2" "$D/c9.cl"
        [ "$(grep -c . "$D/c9.cl" || true)" = "$_n" ] && break
    done
    _u=$(grep -c '^UNRESOLVED:' "$D/c9.cl" || true)
    if [ "$_u" != "0" ]; then
        C9_UNRES=$((C9_UNRES + _u))
        grep '^UNRESOLVED:' "$D/c9.cl" | sed "s|^|      $e -> |"
    fi
    grep -v '^UNRESOLVED:' "$D/c9.cl" | LC_ALL=C sort -u > "$D/c9.files"
    if [ -n "$(LC_ALL=C comm -12 "$D/c9.files" "$D/c9.uses")" ]; then
        C9_ARGV=$((C9_ARGV + 1))
        [ -n "$(LC_ALL=C comm -12 "$D/c9.files" "$D/c9.init")" ] || C9_BAD="$C9_BAD $e"
    fi
done
[ "$C9_UNRES" = "0" ] || _fail "$C9_UNRES include(s) could not be resolved — the census cannot claim to have looked at every file"
[ "$C9_ARGV" -ge 3 ] || _fail "only $C9_ARGV program(s) were found to read argv at all; the closure walk is not working"
if [ -n "$C9_BAD" ]; then
    for b in $C9_BAD; do _fail "$b reads argv()/argc() and nothing in its include closure calls args_init() — every argument it is handed is discarded"; done
fi
if [ -z "$C9_BAD" ]; then
    echo "  $NE entry program(s), $C9_ARGV of them read argv; all initialise it"
else
    echo "  $NE entry program(s), $C9_ARGV of them read argv; $(printf '%s' "$C9_BAD" | wc -w) do NOT initialise it"
fi

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: a targeted check run runs that suite ($NSUITE driver suites, $((EXP_DRV + EXP_SH)) fake gates across both registries, $NQ advertised selectors all reachable, $NE entry programs censused)"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
