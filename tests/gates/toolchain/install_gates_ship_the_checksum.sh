#!/bin/sh
# tests/gates/toolchain/install_gates_ship_the_checksum.sh — 6.6.6 (bite 25a)
#
# AN INSTALL GATE THAT STAGES A RELEASE TARBALL STAGES ITS .sha256 SIDECAR TOO.
#
# THE INCIDENT. `scripts/cass-install-gate.sh` is the Windows install pillar: it builds the
# real tarball, ships it to cass and runs the REAL `install.ps1`. install.ps1 has been
# FAIL-CLOSED on the tarball hash since CVE-21 (v6.2.30) — no `-Sha256`, no
# "<tarball>.sha256" beside it, and it throws "refusing to install unverified tarball"
# before extracting a single byte. The gate `scp`'d the tarball ALONE. So it was RED on its
# own terms, on every run, independently of anything in the tree: 3 MB of scp, then
# `INSTALL FAIL (1)` at the hash check, with the install it exists to prove never once
# executed. The builder was never the problem — `build-windows-tarball.sh` has always
# written the sidecar next to the tarball; only the staging dropped it.
#
# ⚠ AND THE SAME OMISSION IS SILENT ONE HOST OVER. `cross-os-selfhost.sh`'s `ecb-install`
# arm stages a macOS tarball for `install.sh`, whose explicit-local-tarball arm verifies the
# hash *if* a sidecar is present and proceeds if it is not (that hook points at a file the
# operator placed themselves). Staging the tarball alone therefore did not turn anything
# red — it just skipped the integrity leg of the install the gate claims to be running. Same
# root cause, opposite symptom, which is why axis 3 sweeps rather than pinning the one that
# shouted.
#
# ⛔ WHAT AXIS 3 ENFORCES, EXACTLY: every scp-a-release-tarball site in `scripts/`. That is
# TWO of the FOUR such sites in the tree, and the claim is written down narrowly because the
# other two are the LIVE ones. `cbt/commands.cyr`'s `_cross_os_selfhost()` — what
# `cyrius audit` actually runs — carries its own inline ecb and ach install pillars as shell
# strings (the `ecb-install` mode of `cross-os-selfhost.sh` is reachable by hand and is
# invoked by nothing in the repo, and there is no `ach-install` mode at all), and BOTH of
# those strings stage a macOS tarball with no sidecar. So the Intel-Mac install pillar has
# never verified a hash. They are not fixed here because `cbt/` belongs to another lane's
# bite this release; they are carried below as a RATCHET, not a tolerated list: axis 3
# requires the count of uncovered cbt sites to be exactly the 2 known ones and goes RED both
# if a third appears AND if they are fixed — in which case its message is "fold cbt into the
# enforced sweep and delete this carve-out". A carve-out that cannot outlive the defect.
#
# ANTI-VACUOUS: axis 0 proves the premise the whole gate rests on — that install.ps1 really
# is fail-closed and really does look for `<tarball>.sha256` — and DERIVES the sidecar
# suffix from install.ps1's own source rather than hard-coding ".sha256". If the consumer
# stops requiring a checksum, this gate should be re-derived, not quietly kept. Axis 1 runs
# the REAL builder and verifies the sidecar it writes actually matches the tarball, so
# "a sidecar exists" can never degrade into "a file with the right name exists".
#
# INDEPENDENT DERIVATION: axis 2 never spells the expected filename. It reads the path the
# gate passes to install.ps1 as `-Tarball` out of the recorded ssh argv, takes its Windows
# basename, appends the suffix axis 0 extracted from install.ps1, and requires THAT to be
# among the files the recorded scp argv copied — i.e. the expected value comes from the
# consumer's contract and the actual from the producer's behaviour.
#
# MUTATION PROOF (6.6.6, in $D scratch copies — never in the repo):
#   * the sidecar dropped from cass-install-gate.sh's scp list  -> axis 2 RED
#     ("install.ps1 will look for cyrius-6.6.5-x86_64-windows.tar.gz.sha256, scp copied:
#      install.ps1 cass-install-gate.ps1 tw.cyr cyrius-6.6.5-x86_64-windows.tar.gz")
#     and axis 3 RED (1 of 2 scp-tarball sites ship no sidecar).
#   * the sidecar dropped from cross-os-selfhost.sh's ecb-install scp -> axis 3 RED alone;
#     axes 0/1/2 GREEN. That is the silent instance, and it is the reason axis 3 exists.
#   * a sidecar ADDED to one of the two cbt strings -> axis 3 RED ("2 -> 1 ... fix the other
#     and retire this carve-out"); added to BOTH -> axis 3 RED telling you to fold cbt into
#     the enforced sweep. A third sidecar-less cbt scp site added -> axis 3 RED ("2 -> 3").
#     The carve-out is a ratchet in both directions; it cannot outlive the defect.
#   * the cbt scan's `.tar.gz` filter broken -> the >= 2 blindness floor RED.
#   * `sha256sum "$STAGE.tar.gz" > "$STAGE.tar.gz.sha256"` removed from
#     build-windows-tarball.sh -> axis 1 RED twice: no sidecar in the builder's out dir,
#     AND the OUT_DIR rot-guard that covers the two macOS builders this gate does not run.
#   * the sidecar written but with one hex digit flipped -> axis 1 RED on the CONTENT
#     comparison alone (the existence check stays green) — the reason axis 1 re-hashes.
#   * the `[ -f "$T/windist/${TB}.sha256" ]` guard removed from cass-install-gate.sh and
#     the stub builder told not to write a sidecar -> axis 2b RED (the gate scp'd an
#     unverifiable tarball to a real host instead of failing locally).
#   * install.ps1's "refusing to install unverified tarball" throw deleted -> axis 0 RED.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

command -v sha256sum > /dev/null 2>&1 || { echo "FAIL: sha256sum missing (the release builders need it)"; exit 1; }

# ── axis 0 — the premise, and the suffix every other axis uses ────────────────────────
echo "axis 0: install.ps1 is fail-closed on the tarball hash"
if ! grep -q 'refusing to install unverified tarball' scripts/install.ps1; then
    _fail "install.ps1 no longer refuses an unchecksummed tarball — re-derive this gate"
fi
# "$sidecar = "$Tarball.sha256"" -> ".sha256"
SUF=$(sed -n 's/.*\$sidecar *= *"\$Tarball\(\.[A-Za-z0-9]*\)".*/\1/p' scripts/install.ps1 | head -1)
case "$SUF" in
    .*) echo "  install.ps1 looks for <tarball>$SUF" ;;
    *)  _fail "could not derive the sidecar suffix from install.ps1 (got '$SUF')"; SUF=".sha256" ;;
esac
if ! grep -q '${CYRIUS_INSTALL_TARBALL}'"$SUF" scripts/install.sh; then
    _fail "install.sh no longer looks for a local <tarball>$SUF sidecar — re-derive this gate"
fi

# ── axis 1 — the BUILDER half: the sidecar exists and actually matches ────────────────
echo "axis 1: build-windows-tarball.sh writes a sidecar that verifies"
if [ ! -x build/cycc ]; then
    _fail "build/cycc missing — cannot run the real tarball builder"
else
    if ! sh scripts/build-windows-tarball.sh "$D/out" > "$D/build.log" 2>&1; then
        _fail "build-windows-tarball.sh failed:"; sed 's/^/    /' "$D/build.log"
    else
        NTB=$(ls "$D/out"/*.tar.gz 2>/dev/null | wc -l)
        [ "$NTB" = "1" ] || _fail "expected exactly 1 tarball in the builder out dir, found $NTB"
        TBP=$(ls "$D/out"/*.tar.gz 2>/dev/null | head -1)
        TBSZ=$(wc -c < "$TBP" 2>/dev/null || echo 0)
        [ "$TBSZ" -gt 100000 ] || _fail "tarball is $TBSZ bytes — too small to be a real release artifact"
        if [ ! -f "$TBP$SUF" ]; then
            _fail "the builder wrote no $TBP$SUF — install.ps1 is fail-closed and would refuse it"
        else
            # Expected and actual derived two different ways: the sidecar's recorded hash
            # vs a fresh hash taken over stdin (so the filename cannot leak into either).
            SIDE=$(tr -s ' ' < "$TBP$SUF" | cut -d' ' -f1)
            FRESH=$(sha256sum < "$TBP" | cut -d' ' -f1)
            if [ "$SIDE" != "$FRESH" ]; then
                _fail "sidecar hash $SIDE != the tarball's actual $FRESH"
            else
                echo "  $(basename "$TBP")$SUF verifies ($TBSZ bytes)"
            fi
        fi
    fi
fi

# Rot guard on the builders this gate does not run (each takes a cross-compile toolchain
# pass of its own). Derived from the filesystem, not a hand-written list.
BLDRS=$(ls scripts/build-*-tarball.sh 2>/dev/null)
NB=$(printf '%s\n' "$BLDRS" | grep -c . || true)
[ "$NB" -ge 3 ] || _fail "found only $NB release tarball builders (expected >= 3) — is the glob still right?"
for b in $BLDRS; do
    grep -q 'STAGE.tar.gz'"$SUF"'" "$OUT_DIR/"' "$b" \
        || _fail "$b does not place its <tarball>$SUF alongside the tarball in OUT_DIR"
done

# ── axis 2 — the SHIPPING half: run the REAL cass gate with ssh/scp shimmed ───────────
echo "axis 2: cass-install-gate.sh stages the sidecar next to the tarball"
mkdir -p "$D/root/scripts" "$D/root/build" "$D/bin" "$D/tmp"
cp scripts/cass-install-gate.sh scripts/install.ps1 scripts/cass-install-gate.ps1 "$D/root/scripts/"
cp VERSION "$D/root/"
printf '#!/bin/sh\nexit 0\n' > "$D/root/build/cycc"
chmod +x "$D/root/build/cycc"

# A STUB builder — the real one is already proven by axis 1 and costs a full PE
# cross-compile pass. It produces a real .tar.gz and a real sidecar, fast.
cat > "$D/root/scripts/build-windows-tarball.sh" <<'STUB'
#!/bin/sh
set -e
OUT="$1"
R=$(cd "$(dirname "$0")/.." && pwd)
V=$(tr -d '[:space:]' < "$R/VERSION")
S="cyrius-${V}-x86_64-windows"
mkdir -p "$OUT" "$OUT/.stage/$S"
echo stub > "$OUT/.stage/$S/marker"
( cd "$OUT/.stage" && tar czf "$OUT/$S.tar.gz" "$S" )
if [ -z "${STUB_NO_SIDECAR:-}" ]; then
    ( cd "$OUT" && sha256sum "$S.tar.gz" > "$S.tar.gz.sha256" )
fi
STUB
chmod +x "$D/root/scripts/build-windows-tarball.sh"

cat > "$D/bin/ssh" <<SHIM
#!/bin/sh
{ printf 'ssh'; for a in "\$@"; do printf ' %s' "\$a"; done; printf '\n'; } >> "$D/calls.log"
exit 0
SHIM
cat > "$D/bin/scp" <<SHIM
#!/bin/sh
{ printf 'scp'; for a in "\$@"; do printf ' %s' "\$a"; done; printf '\n'; } >> "$D/calls.log"
exit 0
SHIM
chmod +x "$D/bin/ssh" "$D/bin/scp"

: > "$D/calls.log"
CIG_RC=0
( cd "$D/root" && PATH="$D/bin:$PATH" TMPDIR="$D/tmp" sh scripts/cass-install-gate.sh ) \
    > "$D/cig.out" 2>&1 || CIG_RC=$?
[ "$CIG_RC" = "0" ] || { _fail "cass-install-gate.sh exited $CIG_RC under the shims:"; sed 's/^/    /' "$D/cig.out"; }

# What install.ps1 will be pointed at, straight out of the recorded ssh argv.
TBARG=$(sed -n 's/.*-Tarball \([^ ]*\).*/\1/p' "$D/calls.log" | head -1)
TBBASE=$(printf '%s' "$TBARG" | sed 's/.*\\//')
if [ -z "$TBBASE" ]; then
    _fail "no -Tarball argument was ever passed to install.ps1 (calls.log: $(cat "$D/calls.log"))"
else
    WANT="$TBBASE$SUF"
    SCPLINE=$(grep '^scp ' "$D/calls.log" | head -1)
    GOT=""
    for a in $SCPLINE; do
        case "$a" in
            scp|-q|-o|cass:*|*:*/) continue ;;
        esac
        GOT="$GOT $(basename "$a")"
    done
    case " $GOT " in
        *" $WANT "*) echo "  install.ps1 wants $WANT; scp staged it" ;;
        *) _fail "install.ps1 will look for $WANT, scp staged:$GOT" ;;
    esac
    case " $GOT " in
        *" $TBBASE "*) : ;;
        *) _fail "scp did not even stage the tarball $TBBASE — the shim harness is wrong" ;;
    esac
fi

# ── axis 2b — no sidecar from the builder must fail LOCALLY, before any scp ───────────
echo "axis 2b: a builder that writes no sidecar fails the gate locally"
: > "$D/calls.log"
B2_RC=0
( cd "$D/root" && PATH="$D/bin:$PATH" TMPDIR="$D/tmp" STUB_NO_SIDECAR=1 sh scripts/cass-install-gate.sh ) \
    > "$D/cig2.out" 2>&1 || B2_RC=$?
[ "$B2_RC" != "0" ] || _fail "cass-install-gate.sh exited 0 with no checksum sidecar to ship"
if grep -q '^scp ' "$D/calls.log"; then
    _fail "cass-install-gate.sh scp'd an unverifiable tarball to a real host instead of failing locally"
fi

# ── axis 3 — the SWEEP: every scp of a release tarball in scripts/ carries its sidecar ─
echo "axis 3: every scp site in scripts/ AND cbt/ that stages a release tarball stages its sidecar"
SITES=0
BAD=0
# v6.6.6 INTEGRATION: cbt/*.cyr is in the ENFORCED sweep now. It sat in a separate
# ratchet (axis 3b) only because the two install pillars lived in another lane this
# release; bite 26a fixed them, the ratchet went red the way it was built to, and the
# two halves are one claim again. CHANGELOG [6.6.6]
for f in scripts/*.sh cbt/*.cyr; do
    # Join backslash continuations so a multi-line scp is one record.
    sed -e 's/^[[:space:]]*#.*$//' -e :a -e '/\\$/N; s/\\\n//; ta' "$f" | grep -E '(^|[;&|"[:space:]])scp ' | while IFS= read -r line; do
        case "$line" in
            *.tar.gz*|*'${TB}'*|*'$TB'*) ;;
            *) continue ;;
        esac
        case "$line" in
            *"$SUF"*) echo "OK $f" ;;
            *) echo "BAD $f :: $line" ;;
        esac
    done
done > "$D/sweep.log"
SITES=$(grep -c . "$D/sweep.log" || true)
BAD=$(grep -c '^BAD ' "$D/sweep.log" || true)
[ "$SITES" -ge 4 ] || _fail "the sweep found only $SITES scp-a-release-tarball site(s) (expected >= 4: 2 in scripts/, 2 cbt/ install pillars) — the scan is not seeing them"
if [ "$BAD" != "0" ]; then
    _fail "$BAD of $SITES scp-a-release-tarball site(s) ship no sidecar:"
    grep '^BAD ' "$D/sweep.log" | sed 's/^/    /'
else
    echo "  $SITES scripts/ + cbt/ site(s), all shipping a$SUF sidecar"
fi

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: install gates ship the checksum ($SITES scp sites enforced across scripts/ and cbt/, builder sidecar verified)"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
