#!/bin/sh
# tests/gates/toolchain/check_sh_targeted_path_cleans_up.sh — 6.6.6 (bite 25b)
#
# check.sh CLEANS UP THE THROWAWAY CYRIUS_HOME IT STAGED — ON BOTH PATHS.
#
# THE DEFECT. Since v6.6.4 `scripts/check.sh` stages its own throwaway CYRIUS_HOME
# (`mktemp -d "$TMPDIR/cyrius-check-home.XXXXXX"`, populated from the working tree) so the
# suite never writes the live store, and removes it from `_chk_finish`, its EXIT trap. The
# TARGETED path — `sh scripts/check.sh <suite>` — ended in `exec "$CHECK_BIN" "$@"`, and
# **exec does not run the EXIT trap**: the process is REPLACED, so `_chk_finish` never ran
# and the staged tree survived. 19 MB per targeted invocation, for ever; four of them were
# sitting in /tmp when this was written. The full-run path had always been correct, which
# is exactly why it went unnoticed — the leak only happens when you pass a suite name.
# exec's only virtue there was propagating the driver's exit code, which a plain `exit`
# does while still going through the trap.
#
# ANTI-VACUOUS, and it is a BEFORE/AFTER pair rather than a single assertion: the stub
# driver records `$CYRIUS_HOME` and whether that directory EXISTED while it ran, so axis 0
# proves a home really was staged under the harness's own TMPDIR. A check.sh that stopped
# staging anything would make "nothing survives" trivially true; it cannot pass axis 0.
#
# INDEPENDENT DERIVATION: the survivor count is taken by the GATE, from the filesystem
# (`ls -d "$W/tmp/cyrius-check-home.*"`), while the staged path is reported by the DRIVER
# out of its own environment. Neither number comes from check.sh's own output.
#
# ⚠ The harness stubs exactly two things and nothing else: `scripts/install.sh` (the
# stager — this gate is about the CLEANUP, and running the real refresh would take a full
# toolchain pass and must never point at a live store) and `build/cyrius_check` (a real run
# is the whole 13-minute suite). `scripts/check.sh` itself is the REAL file under test,
# copied byte-for-byte.
#
# MUTATION PROOF (6.6.6, in $W scratch copies of check.sh — never the repo):
#   * `exec "$CHECK_BIN" "$@"` restored -> 3 assertions RED: axis 1 (1 staged home
#     survived) and axis 3 twice (the cross names `scripts/check.sh:248: exec "$CHECK_BIN"
#     "$@"`, and the check.sh-specific census counts 1 site). Axes 0 and 2 stay GREEN,
#     which is the shape of the original bug: the full run was always fine.
#   * the driver run but its status discarded (`"$CHECK_BIN" "$@"; exit 0`) -> axis 1 RED
#     on the exit code alone; the cleanup assertions stay green. A cleanup that loses the
#     verdict is not a fix.
#   * the selector dropped from the driver invocation -> axis 1 RED on the forwarded argv.
#   * `rm -rf "$_CHK_STAGED_DIR"` deleted from `_chk_finish` -> axes 1 AND 2 RED (both
#     paths leak), axis 0 GREEN.
#   * the scanner pointed at a tree with no top-level `exec` anywhere -> axis 3's
#     non-blindness floor RED (it refuses to certify a scan that finds nothing at all).
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

# ── harness ───────────────────────────────────────────────────────────────────────────
# $1 = the check.sh to run, $2 = the run dir, remaining args = check.sh's own argv.
_stand_up() {
    _w=$1
    _cs=$2
    mkdir -p "$_w/root/scripts" "$_w/root/build" "$_w/root/programs/checks" \
             "$_w/root/lib" "$_w/tmp" "$_w/home"
    cp "$_cs" "$_w/root/scripts/check.sh"
    cp VERSION "$_w/root/"
    : > "$_w/root/programs/checks/main.cyr"
    : > "$_w/root/lib/placeholder.cyr"
    printf '#!/bin/sh\nexit 0\n' > "$_w/root/build/cycc"
    chmod +x "$_w/root/build/cycc"
    cat > "$_w/root/scripts/install.sh" <<'STUB'
#!/bin/sh
mkdir -p "$CYRIUS_HOME/bin" "$CYRIUS_HOME/versions"
echo stub > "$CYRIUS_HOME/bin/cyrius"
exit 0
STUB
    chmod +x "$_w/root/scripts/install.sh"
    cat > "$_w/root/build/cyrius_check" <<STUB
#!/bin/sh
# v6.6.6 (bite 27a): check.sh now RESOLVES the selector before running anything, and asks
# the driver for its own suite names to do it. The stub answers that question and logs
# every OTHER invocation, so the argv assertion below still sees the real run's argv.
if [ "\$1" = "--list-suites" ]; then printf 'alpha\nbeta\n'; exit 0; fi
{ printf 'ARGV'; for a in "\$@"; do printf ' %s' "\$a"; done; printf '\n'; } >> "$_w/driver.log"
echo "HOME_SEEN=\${CYRIUS_HOME:-<unset>}" >> "$_w/driver.log"
if [ -d "\${CYRIUS_HOME:-/nonexistent}" ]; then
    echo "HOME_EXISTED=yes" >> "$_w/driver.log"
else
    echo "HOME_EXISTED=no" >> "$_w/driver.log"
fi
exit 7
STUB
    chmod +x "$_w/root/build/cyrius_check"
    # Newest of all the rebuild-trigger inputs, so check.sh runs the stub instead of
    # compiling the empty placeholder with the stub compiler.
    touch -d '2038-01-01' "$_w/root/build/cyrius_check"
    : > "$_w/driver.log"
}

# Runs the harness; sets RC and LEFT.
_run() {
    _w=$1
    shift
    RC=0
    # ⛔ `env -u CYRIUS_HOME`, added 6.6.6 with bite 27a. check.sh EXPORTS the home it
    # stages, so inside a real check.sh run every gate inherits CYRIUS_HOME — and the
    # nested check.sh here then took the "caller supplied a home" branch and staged
    # NOTHING, making axes 0-2 fail on the harness rather than on the tree. Measured on
    # HEAD before this line existed: the gate passed standalone and was RED in the full
    # run it is part of. The harness must control its own home.
    ( cd "$_w/root" && env -u CYRIUS_HOME HOME="$_w/home" TMPDIR="$_w/tmp" \
        sh scripts/check.sh "$@" ) > "$_w/out" 2>&1 || RC=$?
    LEFT=$(ls -d "$_w"/tmp/cyrius-check-home.* 2>/dev/null | wc -l)
}

# ── axis 0 + 1 — the TARGETED path ────────────────────────────────────────────────────
echo "axis 0/1: sh check.sh <suite> stages a home, uses it, and removes it"
W1="$D/w1"
mkdir -p "$W1"
_stand_up "$W1" "$ROOT/scripts/check.sh"
_run "$W1" alpha

HOME_SEEN=$(sed -n 's/^HOME_SEEN=//p' "$W1/driver.log" | head -1)
HOME_EXISTED=$(sed -n 's/^HOME_EXISTED=//p' "$W1/driver.log" | head -1)
ARGV=$(sed -n 's/^ARGV //p' "$W1/driver.log" | head -1)

# axis 0 — a home really was staged, under the harness TMPDIR, and was live at driver time.
case "$HOME_SEEN" in
    "$W1/tmp/cyrius-check-home."*) echo "  staged $HOME_SEEN" ;;
    *) _fail "the driver saw CYRIUS_HOME='$HOME_SEEN' — no home was staged under the harness TMPDIR, so the cleanup assertions below would be vacuous" ;;
esac
[ "$HOME_EXISTED" = "yes" ] || _fail "the staged CYRIUS_HOME did not exist while the driver ran (HOME_EXISTED=$HOME_EXISTED)"

# axis 1 — it is gone afterwards, the exit code survived, the argv was forwarded.
[ "$LEFT" = "0" ] || _fail "$LEFT staged CYRIUS_HOME tree(s) survived the targeted run — the EXIT trap did not run"
[ "$RC" = "7" ] || _fail "check.sh exited $RC, not the driver's 7 — the targeted path lost the verdict"
[ "$ARGV" = "alpha" ] || _fail "the driver received argv '$ARGV', expected 'alpha'"

# ── axis 2 — the FULL path keeps the property ─────────────────────────────────────────
echo "axis 2: a full run cleans up too"
W2="$D/w2"
mkdir -p "$W2"
_stand_up "$W2" "$ROOT/scripts/check.sh"
_run "$W2"
[ "$LEFT" = "0" ] || _fail "$LEFT staged CYRIUS_HOME tree(s) survived the FULL run"
H2=$(sed -n 's/^HOME_SEEN=//p' "$W2/driver.log" | head -1)
case "$H2" in
    "$W2/tmp/cyrius-check-home."*) : ;;
    *) _fail "the full run staged no home either (CYRIUS_HOME='$H2') — axis 2 is vacuous" ;;
esac
# Not asserted: the exit code. With no gate scripts in the harness root every registered
# shell gate is MISSING, so a nonzero verdict here is correct and says nothing.

# ── axis 3 — the census: no EXIT-trap script terminates through exec ───────────────────
echo "axis 3: no trap-installing shell script replaces itself with exec"
cat > "$D/execscan.awk" <<'AWK'
BEGIN { hd = "" }
FNR == 1 { hd = "" }
{
    line = $0
    if (hd != "") {
        s = line
        sub(/^[ \t]*/, "", s)
        if (s == hd) { hd = "" }
        next
    }
    if (match(line, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
        tag = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", tag)
        gsub(/['"]/, "", tag)
        hd = tag
    }
    c = line
    sub(/^[ \t]*#.*$/, "", c)
    if (c == "") next
    # `exec` in COMMAND position only: start of line, or after ; & | { or then/else/do.
    # Without this, prose containing the word ("the exec scanner") matches and the census
    # flags its own error messages — measured on this gate's first run.
    if (!match(c, /(^|[;&|{]|[ \t](then|else|do))[ \t]*exec[ \t]/)) next
    pos = RSTART + RLENGTH - 1
    pre = substr(c, 1, pos - 1)
    if (index(pre, "(") > 0) next
    rest = substr(c, pos + 1)
    sub(/^[ \t]+/, "", rest)
    if (rest ~ /^[0-9]*[<>]/) next
    printf "%s:%d:%s\n", FILENAME, FNR, c
}
AWK

: > "$D/shfiles"
for f in $(find scripts tests/gates bootstrap -type f 2>/dev/null); do
    head -1 "$f" 2>/dev/null | grep -q '^#!.*sh' || continue
    echo "$f" >> "$D/shfiles"
done
NSH=$(grep -c . "$D/shfiles" || true)
[ "$NSH" -ge 150 ] || _fail "only $NSH shell scripts found to scan (expected >= 150) — the scan is not seeing the tree"

awk -f "$D/execscan.awk" $(cat "$D/shfiles") > "$D/execs" 2>/dev/null || true
NEX=$(grep -c . "$D/execs" || true)
# Non-blindness: the tree DOES contain legitimate top-level execs (thin shims with no
# cleanup to skip). A scanner that finds none is broken, not reassuring.
[ "$NEX" -ge 1 ] || _fail "the exec scanner found 0 top-level exec sites in $NSH scripts — it is blind, so its 0-violations verdict means nothing"

: > "$D/trapped"
while IFS= read -r f; do
    grep -qE "^[[:space:]]*trap .*(EXIT|INT|TERM)" "$f" && echo "$f" >> "$D/trapped"
done < "$D/shfiles"
NTR=$(grep -c . "$D/trapped" || true)
[ "$NTR" -ge 20 ] || _fail "only $NTR trap-installing scripts found (expected >= 20) — the cross is not seeing them"

VIOL=0
while IFS= read -r line; do
    f=${line%%:*}
    if grep -qx "$f" "$D/trapped"; then
        echo "    $line"
        VIOL=$((VIOL + 1))
    fi
done < "$D/execs"
[ "$VIOL" = "0" ] || _fail "$VIOL script(s) install a cleanup trap and then exec past it (listed above)"

# check.sh specifically has no business exec'ing at all any more.
CEX=$(awk -f "$D/execscan.awk" scripts/check.sh | grep -c . || true)
[ "$CEX" = "0" ] || _fail "scripts/check.sh still has $CEX top-level exec site(s)"
[ "$FAILS" = "0" ] && echo "  $NSH scripts, $NTR with cleanup traps, $NEX top-level exec site(s), $VIOL violations"

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: check.sh cleans up its staged CYRIUS_HOME on both paths"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
