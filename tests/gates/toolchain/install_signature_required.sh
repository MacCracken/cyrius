#!/bin/sh
# install_signature_required.sh — 6.6.20 (SEC-07). With a trusted verifier on the machine, a
# release at or above the FIRST SIGNED RELEASE (6.2.31) that cannot be verified is REFUSED, by
# name, in every installer: scripts/install.sh, scripts/ci.sh and scripts/install.ps1.
#
# ⛔ THE DEFECT. Every release since 6.2.31 publishes SHA256SUMS + SHA256SUMS.sig (release.yml at
# that tag is the first to refuse an unsigned publish; the GitHub API lists the pair on all 243
# releases from 6.2.31 to 6.6.19 and on none below). But install.sh only REQUIRED a signature at or
# above its TOFU floor — `signed-since`, the highest version verified on THIS machine — and
# `_verify_signature` returned "skip" whenever SHA256SUMS could not be fetched. Measured against
# the 6.6.19 tree, hermetic (stub curl serving a fabricated tarball + its .sha256 and no
# SHA256SUMS; a trusted cyrsign present that would FAIL if asked; throwaway HOME):
#   * signed-since 6.6.19, CYRIUS_VERSION=6.6.15  -> rc 0, "signature check skipped", the tampered
#     bin/cycc ACTIVE, cyrsign called 0 times;
#   * no signed-since file, 6.6.19               -> rc 0, tampered and active;
#   * "latest" resolving to 6.2.30               -> rc 0, tampered and active (an attacker who can
#     mark an old release latest downgrades every plain `install.sh` to an unverifiable build);
#   * scripts/ci.sh, cyrsign on PATH, 6.6.19     -> rc 0, tampered cycc installed (no floor at all);
#   * install.ps1 (REAL cass, the real signed 6.6.19 Windows release with SHA256SUMS moved away, the
#     real cyrsign.exe in <home>\bin) -> rc 0, "signature check skipped", installed; and a tarball
#     NAMED 6.2.30 holding VERSION 6.6.19 installed as 6.6.19.
#
# WHAT IS PINNED
#   axis 1  install.sh, functional: the four refusal shapes above plus two malformed versions
#           (a leading-zero field, four fields) refuse, NAME the version, leave the active toolchain
#           where it was and put no binary under versions/<v>/bin.
#   axis 2  install.sh controls — ANTI-VACUOUS (refusing everything passes axis 1): an explicitly
#           requested pre-signing 6.2.30 installs; CYRIUS_ALLOW_UNSIGNED=1 installs; no verifier at
#           all (first install) installs; a served SHA256SUMS + .sig that the verifier ACCEPTS
#           installs ("signature verified"), and one it rejects is refused.
#   axis 3  ci.sh, functional: the stripped 6.6.19 and the auto-resolved 6.2.30 refuse before
#           anything is extracted; an explicit 6.2.30, the override and a verifier-less box proceed.
#   axis 4  the predicate: `_predates_signing` is the SAME function in install.sh and ci.sh, and a
#           truth table over 15 shapes holds for both (only a well-formed N.N.N below 6.2.31 earns
#           the skip — malformed is signed-era).
#   axis 5  install.ps1, static (no PowerShell on a check host): the same constant, the refusal in
#           the skip branch keyed on a present verifier, the -AllowUnsigned override, and the
#           name-vs-VERSION refusal. The functional half ran on cass (ledger below).
#   axis 6  the three installers carry ONE first-signed-release value.
#   axis 7  cyriusly (the compiled programs/cyriusly.cyr AND the shell twin): `install 6.6.15` with
#           a stripped signature, signed-since 6.6.19 and a verifier present is refused by name —
#           it runs the installer from tag max(<v>, _CY_INSTALLER_FLOOR), never <v>'s own pre-SEC-07
#           one (a stand-in serves every other tag and must never run for 6.6.15); the floor's
#           installer still installs a SIGNED 6.6.15; an upgrade past the floor runs the target's
#           own installer; an unfetchable installer is a failure (`curl | sh` was rc 0); one floor
#           value in both peers, never below 6.6.20.
#   axis 8  install.sh's source-bootstrap fallback (no tarball) refuses BEFORE `git clone` for a
#           signed-era release with a verifier present (no floor file, and below the floor), an
#           auto-resolved pre-signing 'latest', and a version at the TOFU floor; an explicit
#           pre-signing version, the override and a first install still bootstrap (Linux; on
#           macOS the fallback is refused outright and the axis checks only that nothing cloned).
#   Both verifier-discovery paths are exercised in each shell installer: install.sh with the
#   verifier on PATH only (axis 1) and in $CYRIUS_HOME/bin (axes 1-2, 8); ci.sh with it on PATH
#   (axis 3) and in $CYRIUS_HOME/bin only — a CI box with a cached ~/.cyrius (axis 3).
#
# cass (Windows Server, real hardware, 6.6.20 lane run): new install.ps1 — first install (no
# verifier) OK; upgrade with the real SHA256SUMS + .sig -> "signature verified (Ed25519)", OK;
# stripped -> rc 1 "refusing UNSIGNED tarball", nothing installed; -AllowUnsigned and
# CYRIUS_ALLOW_UNSIGNED=1 -> WARNING + installed; a 6.2.30 tarball (VERSION 6.2.30) -> skipped, OK;
# named 6.2.30 holding VERSION 6.6.19 -> rc 1 "names release 6.2.30 but its VERSION file says
# 6.6.19"; a renamed tarball (no version in the name) -> refused. Old install.ps1, same inputs:
# stripped and spoof both rc 0, installed. The verified upgrade then overwrites the cyrsign.exe it
# just ran: 2 of 27 died at that copy ("being used by another process"), so install.ps1's bin
# copies retry — 0 of 25 after, and with another bin file held open the old copy died while the
# retry finished after 17 attempts.
#
# MUTATIONS (each RED, measured in a scratch copy of the four files): `|| return 3` back to
# `|| return 2` in _verify_signature (axes 1 + 2); _signed_required_enforce's err line deleted
# (axis 1, five rows); its `_VERSION_FROM_LATEST` guard dropped (axis 1, the latest -> 6.2.30 row);
# `0[0-9]*|*.0[0-9]*` dropped from install.sh's predicate (axes 1 + 4); ci.sh's `exit 1` in the
# refusal deleted (axis 3); ci.sh's constant set to 6.6.0 (axis 6); install.ps1's throw turned into
# a Write-Host (axis 5); install.ps1's constant set to 6.2.30 (axis 6); install.sh refusing every
# unsigned install, pre-signing included (axis 2); install.ps1's active bin copy back to a bare
# Copy-Item (axis 5); the latest guard dropped in BOTH shell installers (axes 1 + 3).
# Review round 1 (same day), each RED: the compiled cyriusly's installer tag back to the TARGET
# (`|| ref=$1`) and the shell twin's (`|| ref=$2`) — axis 7, "ran 6.6.15's OWN installer"; the
# compiled floor set to 6.6.19 (axis 7, two values); the shell twin piped again (`curl | sh`) —
# axis 7, the unfetchable tag exits 0; install.sh's source-bootstrap rule disabled (`if false`) —
# axis 8, three rows clone; its `_signed_floor_enforce` dropped — axis 8, the floor row clones;
# ci.sh's `$CYRIUS_HOME/bin/cyrsign` discovery arm deleted (axis 3, the home-only row installs);
# install.sh ignoring `command -v cyrsign` (axis 1, the PATH-only row installs).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=install_signature_required

for t in tar sort gzip; do
    command -v "$t" > /dev/null 2>&1 || { echo "SKIP: $NAME — no $t on this host"; exit 77; }
done
if command -v sha256sum > /dev/null 2>&1; then SHA="sha256sum"
elif command -v shasum > /dev/null 2>&1; then SHA="shasum -a 256"
else echo "SKIP: $NAME — no sha256sum or shasum"; exit 77; fi

W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0
bad() {
    echo "  FAIL $1"
    [ -f "$W/out" ] && sed -n '1,4p' "$W/out" | sed 's/\x1b\[[0-9;]*m//g' | LC_ALL=C tr -c '[:print:]\n' '?' | sed 's/^/    /'
    fail=1
}

ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) ARCH=x86_64 ;; aarch64|arm64) ARCH=aarch64 ;; esac
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    linux) OSS=linux ;;
    darwin) OSS=macos ;;
    *) echo "SKIP: $NAME — install.sh's tarball path is exercised on Linux / macOS hosts only"; exit 77 ;;
esac
# ci.sh names its tarball for ONE platform whatever the host (`TARBALL="cyrius-${VERSION}-x86_64-linux…"`):
# read that suffix out of ci.sh rather than assuming the host's.
CI_SUFFIX=$(sed -n 's/^TARBALL="cyrius-\${VERSION}-\(.*\)\.tar\.gz"$/\1/p' "$ROOT/scripts/ci.sh" | head -1)
[ -n "$CI_SUFFIX" ] || { echo "FAIL: $NAME — could not read ci.sh's TARBALL suffix"; exit 1; }
PUBKEY=$(sed -n 's/^CYRIUS_RELEASE_PUBKEY="\([0-9a-f]*\)".*/\1/p' "$ROOT/scripts/install.sh" | head -1)
[ -n "$PUBKEY" ] || { echo "FAIL: $NAME — could not read CYRIUS_RELEASE_PUBKEY from install.sh"; exit 1; }

# ── the fake release host ───────────────────────────────────────────────────────────────────
# One stub curl for every installer. It serves whatever $W/rel holds (a tarball, its .sha256 and,
# when a case puts them there, SHA256SUMS + .sig), the "latest" lookup from $W/latest, an
# installer for each tag $W/raw/<tag>.sh names (axis 7: what cyriusly fetches), and 22 for
# everything else — so a missing SHA256SUMS is exactly a stripped signature.
mkdir -p "$W/fakebin" "$W/nobin" "$W/pathbin" "$W/cwd" "$W/raw"
cat > "$W/fakebin/curl" <<EOF
#!/bin/sh
out=""; url=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out=\$2; shift 2 ;; -*) shift ;; *) url=\$1; shift ;; esac; done
printf '%s\n' "\$url" >> "$W/curl.log"
case "\$url" in
    */releases/latest) [ -f "$W/latest" ] || exit 22; printf '{"tag_name": "%s"}\n' "\$(cat "$W/latest")"; exit 0 ;;
    https://raw.githubusercontent.com/MacCracken/cyrius/*/scripts/install.sh)
        t=\${url#https://raw.githubusercontent.com/MacCracken/cyrius/}; t=\${t%%/*}
        f="$W/raw/\$t.sh"
        [ -f "\$f" ] || exit 22
        if [ -n "\$out" ]; then cp "\$f" "\$out"; else cat "\$f"; fi
        exit 0 ;;
    */releases/download/*)
        f="$W/rel/\${url##*/}"
        [ -f "\$f" ] || exit 22
        if [ -n "\$out" ]; then cp "\$f" "\$out"; else cat "\$f"; fi
        exit 0 ;;
esac
exit 22
EOF
chmod +x "$W/fakebin/curl"
# The trusted verifier: logs every call; `verify` exits 0 only in "accept" mode AND only when the
# key it was handed is the pinned release key (so an accepted run proves the real plumbing).
cat > "$W/cyrsign" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/cyrsign.log"
[ "\$1" = verify ] || exit 1
[ "\$(cat "$W/cyrsign.mode" 2>/dev/null)" = accept ] || exit 1
[ "\$(tr -d '[:space:]' < "\$4")" = "$PUBKEY" ] || exit 1
exit 0
EOF
chmod +x "$W/cyrsign"

# mkrel <version> <layout: sh|ci> [signed] — a fabricated release whose binaries say TAMPERED.
mkrel() {
    rm -rf "$W/rel" "$W/stage"
    mkdir -p "$W/rel" "$W/stage"
    if [ "$2" = sh ]; then _tb="cyrius-$1-$ARCH-$OSS.tar.gz"; else _tb="cyrius-$1-$CI_SUFFIX.tar.gz"; fi
    if [ "$2" = sh ]; then _top="$W/stage/cyrius-$1-$ARCH-$OSS"; else _top="$W/stage/versions/$1"; fi
    mkdir -p "$_top/bin" "$_top/lib"
    for _b in cycc cyrius cyriusly; do
        printf '#!/bin/sh\necho TAMPERED-%s\n' "$1" > "$_top/bin/$_b"
        chmod +x "$_top/bin/$_b"
    done
    echo 'fn x() {}' > "$_top/lib/x.cyr"
    if [ "$2" = sh ]; then ( cd "$W/stage" && tar czf "$W/rel/$_tb" "cyrius-$1-$ARCH-$OSS" )
    else ( cd "$W/stage" && tar czf "$W/rel/$_tb" versions ); fi
    ( cd "$W/rel" && $SHA "$_tb" > "$_tb.sha256" )
    if [ "${3:-}" = signed ]; then
        cp "$W/rel/$_tb.sha256" "$W/rel/SHA256SUMS"
        echo "sig" > "$W/rel/SHA256SUMS.sig"
    fi
}

H="$W/home/.cyrius"
# store <verifier: yes|no> <floor|-> — a live-looking store: 6.6.18 active (a version no case
# installs, so "nothing landed" is checkable), its bin/ holding the verifier when asked for, and
# signed-since when a floor is given.
store() {
    rm -rf "$W/home" "$W/curl.log" "$W/cyrsign.log" "$W/latest" "$W/out" "$W/cyrsign.mode"
    mkdir -p "$H/versions/6.6.18/bin" "$H/versions/6.6.18/lib"
    printf '#!/bin/sh\necho GOOD-6.6.18\n' > "$H/versions/6.6.18/bin/cycc"
    chmod +x "$H/versions/6.6.18/bin/cycc"
    [ "$1" = yes ] && cp "$W/cyrsign" "$H/versions/6.6.18/bin/cyrsign"
    ln -s "$H/versions/6.6.18/bin" "$H/bin"
    ln -s "$H/versions/6.6.18/lib" "$H/lib"
    echo 6.6.18 > "$H/current"
    [ "$2" = - ] || echo "$2" > "$H/signed-since"
}
# run_sh <CYRIUS_VERSION or ""> [ENV=VAL] — install.sh against the fake host, never the network.
run_sh() {
    _v=$1; shift
    RC=0
    if [ -n "$_v" ]; then set -- "CYRIUS_VERSION=$_v" "$@"; fi
    ( cd "$W/cwd" && env -i HOME="$W/home" CYRIUS_HOME="$H" PATH="$W/fakebin:${XPATH:+$XPATH:}/usr/bin:/bin" \
        TMPDIR="$W" "$@" sh "$ROOT/scripts/install.sh" ) > "$W/out" 2>&1 || RC=$?
}
active() { "$H/bin/cycc" 2>/dev/null; }
# refused_sh <label> <version> <pattern> — refused, named, nothing activated or installed.
refused_sh() {
    _ok=1
    [ "$RC" -ne 0 ] || _ok=0
    grep -q "$3" "$W/out" || _ok=0
    [ "$(active)" = GOOD-6.6.18 ] || { echo "  (active toolchain now says: $(active))"; _ok=0; }
    [ -e "$H/versions/$2/bin/cycc" ] && { echo "  (a binary landed under versions/$2/bin)"; _ok=0; }
    [ -s "$W/cyrsign.log" ] && { echo "  (the verifier was asked to vouch: $(head -1 "$W/cyrsign.log"))"; _ok=0; }
    [ "$_ok" -eq 1 ] && return 0
    bad "$1: rc $RC"
    return 1
}
installed_sh() {   # installed_sh <label> <version> <pattern>
    if [ "$RC" -eq 0 ] && grep -q "$3" "$W/out" && [ "$(active)" = "TAMPERED-$2" ]; then return 0; fi
    bad "$1: rc $RC, active says '$(active)'"
    return 1
}

# ── axis 1: install.sh refuses ──────────────────────────────────────────────────────────────
a1=0
mkrel 6.6.15 sh; store yes 6.6.19; run_sh 6.6.15
refused_sh "axis 1 explicit 6.6.15 below signed-since 6.6.19" 6.6.15 "refusing UNSIGNED 6.6.15" || a1=1
mkrel 6.6.19 sh; store yes -; run_sh 6.6.19
refused_sh "axis 1 6.6.19 with no signed-since file" 6.6.19 "refusing UNSIGNED 6.6.19" || a1=1
mkrel 6.2.30 sh; store yes 6.6.19; echo 6.2.30 > "$W/latest"; run_sh ""
refused_sh "axis 1 latest -> 6.2.30" 6.2.30 "latest release resolved to 6.2.30" || a1=1
mkrel 6.6.19 sh; store yes 6.6.19; echo 6.6.19 > "$W/latest"; run_sh ""
refused_sh "axis 1 latest -> 6.6.19" 6.6.19 "refusing UNSIGNED 6.6.19" || a1=1
for v in 06.2.30 6.2.30.1; do
    mkrel "$v" sh; store yes -; run_sh "$v"
    refused_sh "axis 1 malformed explicit '$v'" "$v" "refusing UNSIGNED $v" || a1=1
done
# The OTHER discovery path: the rows above find the verifier in $CYRIUS_HOME/bin; here it is on
# PATH only (no cyrsign under the store), which `command -v cyrsign` must still find.
mkrel 6.6.19 sh; store no -; cp "$W/cyrsign" "$W/pathbin/cyrsign"; XPATH="$W/pathbin" run_sh 6.6.19; rm -f "$W/pathbin/cyrsign"
refused_sh "axis 1 6.6.19, the verifier on PATH only" 6.6.19 "refusing UNSIGNED 6.6.19" || a1=1
[ "$a1" -eq 0 ] && echo "  ok axis 1: install.sh refuses a stripped signature at/above 6.2.31 (below the TOFU floor, with no floor, via 'latest', with the verifier on PATH only), an auto-resolved pre-signing 'latest', and two malformed versions — named, nothing installed or activated, the verifier never asked"

# ── axis 2: install.sh controls ─────────────────────────────────────────────────────────────
a2=0
mkrel 6.2.30 sh; store yes 6.6.19; run_sh 6.2.30
installed_sh "axis 2 explicit pre-signing 6.2.30" 6.2.30 "pre-signing release 6.2.30, requested by name" || a2=1
mkrel 6.6.15 sh; store yes 6.6.19; run_sh 6.6.15 CYRIUS_ALLOW_UNSIGNED=1
installed_sh "axis 2 CYRIUS_ALLOW_UNSIGNED=1" 6.6.15 "allowed via CYRIUS_ALLOW_UNSIGNED=1" || a2=1
mkrel 6.6.15 sh; store no -; run_sh 6.6.15
installed_sh "axis 2 no verifier (first install)" 6.6.15 "no prior cyrsign" || a2=1
mkrel 6.6.15 sh signed; store yes 6.6.19; echo accept > "$W/cyrsign.mode"; run_sh 6.6.15
installed_sh "axis 2 signed + verifier accepts" 6.6.15 "signature verified" || a2=1
mkrel 6.6.15 sh signed; store yes 6.6.19; run_sh 6.6.15
if [ "$RC" -ne 0 ] && grep -q "signature verification FAILED" "$W/out" && [ "$(active)" = GOOD-6.6.18 ]; then :; else
    bad "axis 2 signed + verifier rejects: rc $RC, active '$(active)'"; a2=1; fi
[ "$a2" -eq 0 ] && echo "  ok axis 2: an explicit pre-signing version, the override, a verifier-less first install and a verified signature still install; a rejected signature is still refused"

# ── axis 3: ci.sh ───────────────────────────────────────────────────────────────────────────
run_ci() {   # run_ci <verifier: yes (on PATH) | home (in $CYRIUS_HOME/bin only) | no> <arg or ""> [ENV=VAL]
    _vf=$1; _a=$2; shift 2
    rm -rf "$W/home" "$W/curl.log" "$W/cyrsign.log" "$W/out" "$W/cyrsign.mode"
    mkdir -p "$H/bin"
    _p="$W/nobin:/usr/bin:/bin"
    if [ "$_vf" = yes ]; then cp "$W/cyrsign" "$W/nobin/cyrsign"; else rm -f "$W/nobin/cyrsign"; fi
    [ "$_vf" = home ] && cp "$W/cyrsign" "$H/bin/cyrsign"
    RC=0
    ( cd "$W/cwd" && env -i HOME="$W/home" CYRIUS_HOME="$H" PATH="$W/fakebin:$_p" TMPDIR="$W" "$@" \
        sh "$ROOT/scripts/ci.sh" $_a ) > "$W/out" 2>&1 || RC=$?
}
a3=0
mkrel 6.6.19 ci; rm -f "$W/latest"; run_ci yes 6.6.19
if [ "$RC" -ne 0 ] && grep -q "refusing UNSIGNED 6.6.19" "$W/out" && [ ! -e "$H/versions/6.6.19" ]; then :; else
    bad "axis 3 ci.sh stripped 6.6.19: rc $RC"; a3=1; fi
mkrel 6.2.30 ci; echo 6.2.30 > "$W/latest"; run_ci yes ""
if [ "$RC" -ne 0 ] && grep -q "latest release resolved to 6.2.30" "$W/out" && [ ! -e "$H/versions/6.2.30" ]; then :; else
    bad "axis 3 ci.sh latest -> 6.2.30: rc $RC"; a3=1; fi
# the other discovery path: a CI box with a cached ~/.cyrius whose bin/ is not on PATH yet
mkrel 6.6.19 ci; rm -f "$W/latest"; run_ci home 6.6.19
if [ "$RC" -ne 0 ] && grep -q "refusing UNSIGNED 6.6.19" "$W/out" && [ ! -e "$H/versions/6.6.19" ] && [ ! -s "$W/cyrsign.log" ]; then :; else
    bad "axis 3 ci.sh stripped 6.6.19, the verifier in \$CYRIUS_HOME/bin only: rc $RC"; a3=1; fi
mkrel 6.2.30 ci; rm -f "$W/latest"; run_ci yes 6.2.30
if [ "$RC" -eq 0 ] && grep -q "pre-signing release 6.2.30" "$W/out" && [ "$("$H/bin/cycc")" = TAMPERED-6.2.30 ]; then :; else
    bad "axis 3 ci.sh explicit 6.2.30 (control): rc $RC"; a3=1; fi
mkrel 6.6.19 ci; run_ci yes 6.6.19 CYRIUS_ALLOW_UNSIGNED=1
if [ "$RC" -eq 0 ] && grep -q "allowed via CYRIUS_ALLOW_UNSIGNED=1" "$W/out"; then :; else
    bad "axis 3 ci.sh override (control): rc $RC"; a3=1; fi
mkrel 6.6.19 ci; run_ci no 6.6.19
if [ "$RC" -eq 0 ] && grep -q "no prior cyrsign" "$W/out"; then :; else
    bad "axis 3 ci.sh no verifier (control): rc $RC"; a3=1; fi
[ "$a3" -eq 0 ] && echo "  ok axis 3: ci.sh refuses a stripped 6.6.19 (verifier on PATH, and in \$CYRIUS_HOME/bin only) and an auto-resolved pre-signing 'latest' before extracting; an explicit 6.2.30, the override and a verifier-less box proceed"

# ── axis 4: the predicate, one function in both shell installers ───────────────────────────
a4=0
fn_of() { sed -n '/^_predates_signing() {$/,/^}$/p' "$1"; }
fn_of "$ROOT/scripts/install.sh" > "$W/p_install"
fn_of "$ROOT/scripts/ci.sh" > "$W/p_ci"
[ -s "$W/p_install" ] && [ -s "$W/p_ci" ] || { bad "axis 4: _predates_signing not found in install.sh and ci.sh"; a4=1; }
cmp -s "$W/p_install" "$W/p_ci" || { bad "axis 4: install.sh and ci.sh carry DIFFERENT _predates_signing bodies"; a4=1; }
for f in install ci; do
    # rows: <version>:<1 predates | 0 signed-era>
    for row in 6.2.30:1 6.2.3:1 5.99.99:1 0.9.0:1 6.1.99:1 6.2.31:0 6.2.32:0 6.10.0:0 7.0.0:0 \
               06.2.30:0 6.2.030:0 6.2.30.1:0 6.2:0 v6.2.30:0 6.2.30-rc1:0 :0 6..30:0; do
        v=${row%:*}; want=${row##*:}
        got=$( _FIRST_SIGNED_RELEASE=6.2.31; . "$W/p_$f"; if _predates_signing "$v"; then echo 1; else echo 0; fi )
        [ "$got" = "$want" ] || { bad "axis 4 [$f] _predates_signing '$v' = $got, want $want"; a4=1; }
    done
done
[ "$a4" -eq 0 ] && echo "  ok axis 4: one _predates_signing in install.sh and ci.sh; only a well-formed N.N.N below 6.2.31 predates signing (17 rows)"

# ── axis 5: install.ps1 (static — the functional matrix ran on cass, ledger in the header) ──
a5=0
PS="$ROOT/scripts/install.ps1"
grep -q '^\$FirstSignedRelease = "' "$PS" || { bad "axis 5: install.ps1 has no \$FirstSignedRelease"; a5=1; }
grep -q '\[switch\]\$AllowUnsigned' "$PS" || { bad "axis 5: install.ps1 has no -AllowUnsigned switch"; a5=1; }
# the skip branch: a present verifier and a signed-era name must reach a throw, not a Write-Host
sed -n '/elseif (\$cyrsign -and -not \$predatesSigning)/,/^    } else {/p' "$PS" > "$W/ps_branch"
grep -q 'throw "refusing UNSIGNED tarball' "$W/ps_branch" || { bad "axis 5: install.ps1's skip branch no longer THROWS for a present verifier and a signed-era tarball"; a5=1; }
grep -q 'CYRIUS_ALLOW_UNSIGNED' "$W/ps_branch" || { bad "axis 5: install.ps1's override does not read CYRIUS_ALLOW_UNSIGNED"; a5=1; }
grep -q 'names release \$tarVer but its VERSION file says' "$PS" || { bad "axis 5: install.ps1 no longer holds the tarball name against its VERSION file"; a5=1; }
LC_ALL=C grep -q '[^ -~	]' "$PS" && { bad "axis 5: install.ps1 is no longer ASCII-only (PowerShell 5.1 reads it as the ANSI codepage)"; a5=1; }
# every copy into a bin\ goes through the retry: the verified upgrade overwrites the cyrsign.exe it
# just ran, and a bare Copy-Item died on Windows' brief hold of that image (2 of 27 on cass)
if grep -n 'Copy-Item ' "$PS" | grep -v 'Copy-Item \$From \$To' | grep -q 'bin\\'; then
    bad "axis 5: install.ps1 copies into a bin\\ with a bare Copy-Item: $(grep -n 'Copy-Item ' "$PS" | grep -v 'Copy-Item \$From \$To' | grep 'bin\\' | head -1)"; a5=1
fi
[ "$(grep -c '^Copy-BinWithRetry "' "$PS")" -ge 2 ] || { bad "axis 5: install.ps1's two bin copies no longer go through Copy-BinWithRetry"; a5=1; }
[ "$a5" -eq 0 ] && echo "  ok axis 5: install.ps1 throws for a stripped signed-era tarball with a verifier present, honours -AllowUnsigned / CYRIUS_ALLOW_UNSIGNED, refuses a name/VERSION mismatch, and stays ASCII"

# ── axis 6: one value ───────────────────────────────────────────────────────────────────────
v_sh=$(sed -n 's/^_FIRST_SIGNED_RELEASE="\([^"]*\)"$/\1/p' "$ROOT/scripts/install.sh")
v_ci=$(sed -n 's/^_FIRST_SIGNED_RELEASE="\([^"]*\)"$/\1/p' "$ROOT/scripts/ci.sh")
v_ps=$(sed -n 's/^\$FirstSignedRelease = "\([^"]*\)"\r*$/\1/p' "$ROOT/scripts/install.ps1")
if [ -n "$v_sh" ] && [ "$v_sh" = "$v_ci" ] && [ "$v_sh" = "$v_ps" ] && [ "$v_sh" = 6.2.31 ]; then
    echo "  ok axis 6: install.sh, ci.sh and install.ps1 all name 6.2.31 as the first signed release"
else
    bad "axis 6: first signed release — install.sh '$v_sh', ci.sh '$v_ci', install.ps1 '$v_ps' (want 6.2.31 in all three)"
fi

# ── axis 7: cyriusly runs an installer that carries the rule, whatever it installs ───────────
# `cyriusly install <v>` fetched the installer from <v>'s own tag, so every release from 6.2.31 to
# 6.6.19 was installed by its pre-SEC-07 installer. It now runs the tag max(<v>, floor). The fake
# host serves the TREE's install.sh for the floor's tag (what that tag carries) and a STAND-IN for
# any other tag that records it ran and exits 0 — the old installers' "signature check skipped".
a7=0
CC=${CYCC:-"$ROOT/build/cycc"}
FL_BIN=$(sed -n 's/^var _CY_INSTALLER_FLOOR = "\([^"]*\)";$/\1/p' "$ROOT/programs/cyriusly.cyr")
FL_SH=$(sed -n 's/^_CY_INSTALLER_FLOOR="\([^"]*\)"$/\1/p' "$ROOT/scripts/cyriusly")
if [ -z "$FL_BIN" ] || [ "$FL_BIN" != "$FL_SH" ]; then
    bad "axis 7: the installer floor — programs/cyriusly.cyr '$FL_BIN', scripts/cyriusly '$FL_SH' (one value, in both)"; a7=1
elif [ "$(printf '%s\n%s\n' "$FL_BIN" 6.6.20 | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" != 6.6.20 ]; then
    bad "axis 7: the installer floor $FL_BIN is below 6.6.20, the first install.sh that refuses a stripped signature"; a7=1
fi
if ! { [ -x "$CC" ] && ( cd "$ROOT" && "$CC" < programs/cyriusly.cyr > "$W/cyriusly" 2> /dev/null ) && chmod +x "$W/cyriusly"; }; then
    bad "axis 7: could not build programs/cyriusly.cyr with $CC"; a7=1
fi
FL=${FL_BIN:-6.6.20}
rm -rf "$W/raw"; mkdir -p "$W/raw"
cp "$ROOT/scripts/install.sh" "$W/raw/$FL.sh"
for t in 6.6.15 6.6.99; do
    printf 'printf "STAND-IN %s %%s\\n" "$CYRIUS_VERSION" > "%s/standin"\nexit 0\n' "$t" "$W" > "$W/raw/$t.sh"
done
run_cy() {   # run_cy <peer: bin|sh> <version>
    RC=0
    rm -f "$W/standin"
    if [ "$1" = bin ]; then set -- "$W/cyriusly" install "$2"; else set -- sh "$ROOT/scripts/cyriusly" install "$2"; fi
    ( cd "$W/cwd" && env -i HOME="$W/home" CYRIUS_HOME="$H" PATH="$W/fakebin:/usr/bin:/bin" TMPDIR="$W" "$@" ) \
        > "$W/out" 2>&1 || RC=$?
}
for P in bin sh; do
    [ "$P" = bin ] && [ ! -x "$W/cyriusly" ] && continue
    # the report's parameters: a stripped 6.6.15, signed-since 6.6.19, a trusted verifier present
    mkrel 6.6.15 sh; store yes 6.6.19; run_cy "$P" 6.6.15
    if [ -e "$W/standin" ]; then bad "axis 7 [$P] install 6.6.15: ran 6.6.15's OWN installer ($(cat "$W/standin"))"; a7=1
    elif refused_sh "axis 7 [$P] install 6.6.15 (stripped, signed-since 6.6.19)" 6.6.15 "refusing UNSIGNED 6.6.15"; then
        { grep -qx "https://raw.githubusercontent.com/MacCracken/cyrius/$FL/scripts/install.sh" "$W/curl.log" \
            && ! grep -q '/cyrius/6\.6\.15/scripts/install\.sh' "$W/curl.log"; } \
            || { bad "axis 7 [$P] install 6.6.15: fetched $(grep raw.githubusercontent "$W/curl.log" | head -1), want the $FL tag's installer"; a7=1; }
    else a7=1; fi
    # control: the floor's installer still installs an OLDER signed release (CYRIUS_VERSION reached it)
    mkrel 6.6.15 sh signed; store yes 6.6.19; echo accept > "$W/cyrsign.mode"; run_cy "$P" 6.6.15
    installed_sh "axis 7 [$P] install a signed 6.6.15 through the $FL installer" 6.6.15 "signature verified" || a7=1
    # control: an upgrade past the floor runs the target's own installer (its tag — never main)
    store yes 6.6.19; run_cy "$P" 6.6.99
    { [ "$RC" -eq 0 ] && [ "$(cat "$W/standin" 2>/dev/null)" = "STAND-IN 6.6.99 6.6.99" ] \
        && ! grep -q '/cyrius/main/' "$W/curl.log"; } \
        || { bad "axis 7 [$P] install 6.6.99 (control): rc $RC, the installer that ran said '$(cat "$W/standin" 2>/dev/null)'"; a7=1; }
    # a tag whose installer cannot be fetched is a failure, not a silent success (`curl | sh` was rc 0)
    store yes 6.6.19; run_cy "$P" 6.6.98
    { [ "$RC" -ne 0 ] && grep -q "could not fetch scripts/install.sh from tag 6.6.98" "$W/out"; } \
        || { bad "axis 7 [$P] install 6.6.98 (no installer at that tag): rc $RC"; a7=1; }
done
[ "$a7" -eq 0 ] && echo "  ok axis 7: cyriusly (both peers) runs the $FL installer for an older release — a stripped 6.6.15 refused by name, the verifier never asked — the target's own for a newer one, and fails when the installer cannot be fetched"

# ── axis 8: install.sh's source-bootstrap fallback obeys the same rule ───────────────────────
# A tarball that cannot be fetched sent install.sh to `git clone --branch <v>` + the clone's
# bootstrap.sh with no signature or floor check. A stub git creates a bootstrap.sh that records it
# ran; no row may reach it unless the rule allows the install.
a8=0
cat > "$W/fakebin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/git.log"
mkdir -p cyrius/bootstrap
printf 'echo RAN > "%s/bootstrapped"; exit 1\n' "$W" > cyrius/bootstrap/bootstrap.sh
exit 0
EOF
chmod +x "$W/fakebin/git"
norel() { rm -rf "$W/rel" "$W/git.log" "$W/bootstrapped"; mkdir -p "$W/rel"; }
cloned() { [ -s "$W/git.log" ] && [ -e "$W/bootstrapped" ]; }
if [ "$OSS" = linux ]; then
    # the verifier rows carry no floor that could refuse them instead: no signed-since file, and
    # one below it (the report's signed-since 6.6.19 with 6.6.15)
    for row in "-|6.6.19" "6.6.19|6.6.15"; do
        _fl=${row%|*}; _v=${row#*|}
        norel; store yes "$_fl"; run_sh "$_v"
        { [ "$RC" -ne 0 ] && grep -q "refusing UNSIGNED $_v: every Cyrius release since" "$W/out" \
            && grep -q "cyrius-$_v-$ARCH-linux.tar.gz could not be fetched" "$W/out" \
            && [ ! -s "$W/git.log" ] && [ ! -e "$W/bootstrapped" ] && [ ! -s "$W/cyrsign.log" ]; } \
            || { bad "axis 8 no tarball, verifier present, signed-since '$_fl', $_v: rc $RC, git: $(head -1 "$W/git.log" 2>/dev/null)"; a8=1; }
    done
    norel; store yes 6.6.19; echo 6.2.30 > "$W/latest"; run_sh ""
    { [ "$RC" -ne 0 ] && grep -q "latest release resolved to 6.2.30" "$W/out" && [ ! -s "$W/git.log" ]; } \
        || { bad "axis 8 no tarball, latest -> 6.2.30: rc $RC, git: $(head -1 "$W/git.log" 2>/dev/null)"; a8=1; }
    norel; store no 6.6.19; run_sh 6.6.19
    { [ "$RC" -ne 0 ] && grep -q "anti-downgrade (CVE-21): refusing UNSIGNED 6.6.19" "$W/out" && [ ! -s "$W/git.log" ]; } \
        || { bad "axis 8 no tarball, no verifier, signed-since 6.6.19: rc $RC, git: $(head -1 "$W/git.log" 2>/dev/null)"; a8=1; }
    # controls — ANTI-VACUOUS: the fallback is still reachable where the rule allows it
    norel; store yes 6.6.19; run_sh 6.2.30
    cloned || { bad "axis 8 explicit pre-signing 6.2.30 (control): the source bootstrap never ran (rc $RC)"; a8=1; }
    norel; store yes 6.6.19; run_sh 6.6.19 CYRIUS_ALLOW_UNSIGNED=1
    cloned || { bad "axis 8 CYRIUS_ALLOW_UNSIGNED=1 (control): the source bootstrap never ran (rc $RC)"; a8=1; }
    norel; store no -; run_sh 6.6.19
    cloned || { bad "axis 8 first install, no verifier (control): the source bootstrap never ran (rc $RC)"; a8=1; }
    [ "$a8" -eq 0 ] && echo "  ok axis 8: with no tarball, install.sh refuses to clone and bootstrap a signed-era release (verifier present), an auto-resolved pre-signing 'latest' and a version at the TOFU floor; an explicit pre-signing version, the override and a first install still bootstrap"
else
    norel; store yes 6.6.19; run_sh 6.6.19
    { [ "$RC" -ne 0 ] && [ ! -s "$W/git.log" ]; } \
        || { bad "axis 8 [$OSS] no tarball: rc $RC, git: $(head -1 "$W/git.log" 2>/dev/null)"; a8=1; }
    [ "$a8" -eq 0 ] && echo "  ok axis 8 [$OSS]: with no tarball install.sh refuses before any clone (source bootstrap is Linux-only)"
fi
rm -f "$W/fakebin/git"

if [ "$fail" -ne 0 ]; then echo "FAIL: $NAME"; exit 1; fi
echo "PASS: $NAME — a stripped signature at or above 6.2.31 is refused by name in install.sh, ci.sh and install.ps1 whenever a trusted verifier is present, and cyriusly runs an installer that refuses it"
exit 0
