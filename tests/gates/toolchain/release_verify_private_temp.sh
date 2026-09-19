#!/bin/sh
# release_verify_private_temp.sh — v6.6.6 bite 17e, CVE-44. The release installer stages every
# downloaded artifact in a PRIVATE directory, so no other local user can steer the signature
# check that authorises the install.
#
# ⛔ CVE-44 (scripts/ci.sh, as of 6.6.5). Six fixed, world-writable paths:
#     /tmp/$TARBALL  /tmp/$TARBALL.sha256  /tmp/SHA256SUMS
#     /tmp/SHA256SUMS.sig  /tmp/cyrius-release.pub  /tmp/cyrius_tsum
# — the tarball being installed, AND the three inputs to the Ed25519 check that is supposed to
# authorise installing it. /tmp's sticky bit stops another user DELETING your file; it does not
# stop them CREATING a name that does not exist yet. A local user who creates those names first
# OWNS the files, so `curl -o` and `printf >` write into files they control and can rewrite at
# any moment — between the download and the verify, or between the verify and `tar xzf`. Most
# directly: they own `/tmp/cyrius-release.pub`, so the signature is checked against THEIR key
# and any tarball they put at `/tmp/$TARBALL` installs. A verification whose inputs another
# user can swap is not a verification.
#
# ⭐ THE FIX IS AN UNPREDICTABLE 0700 DIRECTORY, NOT A CHECK. There is no check that closes this:
# "is the file still the one I wrote?" is itself a TOCTOU. `mktemp -d` gives a name the attacker
# cannot guess and a mode they cannot enter, so there is nothing to pre-create and nothing to
# swap. A failed mktemp ABORTS — it never falls back to a shared directory.
#
# ⚠ HERMETIC, NO NETWORK. `curl`, `cyrsign`, `sha256sum` and `shasum` are stubbed on PATH ahead
# of the real ones, serving a fake release built here. The stub `cyrsign` records the pubkey it
# was handed and accepts ONLY the genuine key, so "which key reached the verifier" is directly
# observable — which is the whole question CVE-44 asks.
#
# AXES
#   1. ANTI-VACUOUS: a well-formed fake release installs — rc 0, "signature verified", the
#      payload lands under $CYRIUS_HOME, and the stub verifier saw the REAL pubkey.
#   2. THE ATTACK: another user's files are pre-created at the installer's fixed tarball names,
#      the tarball itself a SYMLINK out of the shared directory. The install must leave that
#      link target byte-for-byte, leave the planted files untouched, verify against the real key
#      and install the real payload. This is the DETERMINISTIC half of CVE-44 (`curl -o` and
#      `printf >` follow a symlink). ⚠ The four version-INDEPENDENT names (SHA256SUMS, .sig,
#      cyrius-release.pub, cyrius_tsum) are deliberately NOT planted: they are shared with every
#      process on the box and planting them would make this gate collide with a concurrent
#      check.sh. Same defect, same mechanism; axis 4 pins statically that the fixed installer
#      names none of them. The key-swap half is a race and the gate does not pretend to see one.
#   3. A `mktemp -d` that cannot produce a directory ABORTS with a non-zero status and installs
#      nothing — it must never fall back to a shared directory.
#   4. STATIC: scripts/ci.sh names no fixed "/tmp/<name>" path outside a comment, and its temp
#      dir is a CHECKED mktemp. (tests/gates/toolchain/gates_never_write_tree.sh carries the
#      tree-wide version of this axis over all of scripts/*.sh since bite 17f.)
#
# MUTATION LEDGER (measured 6.6.6, each against a COPY of scripts/ci.sh in the gate's scratch dir)
#   a. the 6.6.5 script verbatim (six fixed /tmp names)  -> axes 2, 3 and 4 FAIL. Axis 2 is the
#                                                           exploit: the victim file outside the
#                                                           shared dir is CLOBBERED through the
#                                                           planted symlink, and the planted
#                                                           files are written/removed.
#   b. `TD=$(mktemp -d)` with the [ -d ] check dropped   -> axis 3 FAIL (empty TD -> the script
#                                                           stages in "/" relative paths and
#                                                           reports success)
#   c. TD falling back to a SHARED staging dir when       -> axis 3 FAIL (rc 0, installed, no
#      mktemp fails ("${TMPDIR:-/tmp}/cyrius-ci-stage")      reason given)
#      ⚠ Do NOT write that mutant as a bare `TD=/tmp`: the script's own
#      `trap 'rm -rf "$TD"' EXIT` then runs `rm -rf /tmp`, which is a real hazard on a shared
#      box (it took this gate's own scratch dir, and every other process's, with it when it was
#      tried once). The fixed-subdirectory form is the same regression and is safe to run.
#   d. axis-4 fixed-/tmp detector disabled               -> axis 4 self-test FAIL
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: release_verify_private_temp: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
command -v sha256sum > /dev/null 2>&1 || { echo "FAIL: sha256sum missing — the fake release's checksums come from it"; exit 1; }

REALKEY="adbde6b11ccf8d86dc760387fa7f4dfbe3942fa318e459fb6e62d1536e254008"
grep -q "CYRIUS_RELEASE_PUBKEY=\"$REALKEY\"" scripts/ci.sh || { echo "FAIL: the pinned release pubkey in scripts/ci.sh is not the one this gate stubs against — update the gate"; exit 1; }
# The SHARED directory whose fixed names CVE-44 is about, named once rather than spelled inline:
# the gate must plant the installer's own literal paths, and a `/tmp/<name>` literal is exactly
# what tests/gates/toolchain/gates_never_write_tree.sh axis 5 forbids in a gate — rightly, since
# two concurrent check.sh runs would collide. Both concerns are met by naming it here and making
# every planted path UNIQUE PER RUN: the fake version carries this process's pid, so the tarball
# names below cannot be shared with another run, and no other fixed name is planted at all.
SHARED_TMP="${CYR_SHARED_TMP:-/tmp}"
VER="9.9.9-probe$$"
TARBALL="cyrius-${VER}-x86_64-linux.tar.gz"

# ── the fake release: a tarball with one identifiable payload file ──
mkdir -p "$D/rel/versions/$VER/bin" "$D/rel/versions/$VER/lib" "$D/release"
# ci.sh ends by requiring an executable bin/cycc and bin/cyrius, so the fake payload is two
# tiny executables whose OUTPUT identifies which tarball won.
printf '#!/bin/sh\necho "the genuine payload"\n' > "$D/rel/versions/$VER/bin/cycc"
printf '#!/bin/sh\necho "the genuine payload"\n' > "$D/rel/versions/$VER/bin/cyrius"
chmod +x "$D/rel/versions/$VER/bin/cycc" "$D/rel/versions/$VER/bin/cyrius"
( cd "$D/rel" && tar czf "$D/release/$TARBALL" versions )
( cd "$D/release" && sha256sum "$TARBALL" > "${TARBALL}.sha256" && sha256sum "$TARBALL" > SHA256SUMS )
printf 'not-a-real-signature\n' > "$D/release/SHA256SUMS.sig"

# ── stubs on PATH: curl serves $D/release, cyrsign records the key it was handed ──
mkdir -p "$D/stub"
cat > "$D/stub/curl" <<'SH'
#!/bin/sh
url=""; out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
name="${url##*/}"
[ -n "$out" ] || { cat "$STUB_RELEASE/$name" 2>/dev/null; exit $?; }
[ -f "$STUB_RELEASE/$name" ] || exit 22
cp "$STUB_RELEASE/$name" "$out"
SH
cat > "$D/stub/cyrsign" <<'SH'
#!/bin/sh
# cyrsign verify <sums> <sig> <pub> — record the key we were handed, accept only the real one.
[ "$1" = verify ] || exit 2
cat "$4" >> "$STUB_SEEN_KEYS" 2>/dev/null
grep -qx "$STUB_REAL_KEY" "$4" 2>/dev/null || exit 1
exit 0
SH
chmod +x "$D/stub/curl" "$D/stub/cyrsign"
STUB_RELEASE="$D/release"; export STUB_RELEASE
STUB_REAL_KEY="$REALKEY"; export STUB_REAL_KEY

# _install <script> <home> <seenkeys> — run the installer hermetically
_install() {
    STUB_SEEN_KEYS="$3"; export STUB_SEEN_KEYS
    : > "$STUB_SEEN_KEYS"
    ( PATH="$D/stub:$PATH" CYRIUS_HOME="$2" exec sh "$1" "$VER" ) > "$4" 2>&1
}

# ── axis 1: ANTI-VACUOUS — a well-formed release installs and verifies against the real key ──
rc=0; _install scripts/ci.sh "$D/home1" "$D/keys1" "$D/a1.out" || rc=$?
x=0
[ "$rc" -eq 0 ] || { fail "axis 1: the hermetic install failed (rc=$rc):"; sed 's/^/      /' "$D/a1.out" | head -6; x=1; }
grep -q 'signature verified' "$D/a1.out" || { fail "axis 1: the signature was not verified:"; sed 's/^/      /' "$D/a1.out" | head -6; x=1; }
[ "$("$D/home1/versions/$VER/bin/cycc" 2>/dev/null)" = "the genuine payload" ] || { fail "axis 1: the payload did not land under CYRIUS_HOME"; x=1; }
grep -qx "$REALKEY" "$D/keys1" || { fail "axis 1: the verifier was handed '$(cat "$D/keys1")', not the pinned key"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: a well-formed release installs, verifies against the pinned key, payload in place"

# ── axis 2: THE ATTACK — every fixed /tmp name pre-created by another user ──
# Two of them are SYMLINKS into a directory the installer has no business writing, which is the
# DETERMINISTIC half of CVE-44: `curl -o` and `printf >` follow a symlink, so a name the
# attacker created first redirects the installer's write anywhere the installing user can write.
# (The other half — swapping SHA256SUMS/.sig/cyrius-release.pub between the write and the verify
# so the signature is checked against the attacker's key — is a race, and this gate does not
# pretend to observe a race; both halves close for the same reason, an unguessable 0700 dir.)
ATTACKKEY="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
mkdir -p "$D/evil/versions/$VER/bin" "$D/victim"
printf '#!/bin/sh\necho "the ATTACKER payload"\n' > "$D/evil/versions/$VER/bin/cycc"
cp "$D/evil/versions/$VER/bin/cycc" "$D/evil/versions/$VER/bin/cyrius"
chmod +x "$D/evil/versions/$VER/bin/cycc" "$D/evil/versions/$VER/bin/cyrius"
( cd "$D/evil" && tar czf "$D/evil/$TARBALL" versions )
printf 'a file the installer must never write\n' > "$D/victim/precious_tarball"
PLANTED="$SHARED_TMP/$TARBALL $SHARED_TMP/${TARBALL}.sha256"
plant() {
    rm -f $PLANTED 2>/dev/null
    ln -s "$D/victim/precious_tarball" "$SHARED_TMP/$TARBALL" 2>/dev/null || return 1
    ( cd "$D/evil" && sha256sum "$TARBALL" ) > "$SHARED_TMP/${TARBALL}.sha256" 2>/dev/null || return 1
    # The four version-INDEPENDENT names the 6.6.5 script also used ($SHARED_TMP/SHA256SUMS,
    # .sig, cyrius-release.pub, cyrius_tsum) are deliberately NOT planted: they are shared with
    # every other process on the box, so planting them would make this gate collide with a
    # concurrent run. They are the same defect through the same mechanism — a name another user
    # can create first — and the fixed installer touches none of them, which axis 4 pins
    # statically. The pubkey's victim file below stands in for that half.
}
if plant; then
    cksum < "$D/victim/precious_tarball" > "$D/victim.before"
    for f in $PLANTED; do cksum < "$f" 2>/dev/null || echo UNREADABLE; done > "$D/planted.before"
    rc=0; _install scripts/ci.sh "$D/home2" "$D/keys2" "$D/a2.out" || rc=$?
    x=0
    [ "$rc" -eq 0 ] || { fail "axis 2: the install failed although the real release is available (rc=$rc):"; sed 's/^/      /' "$D/a2.out" | head -6; x=1; }
    cksum < "$D/victim/precious_tarball" > "$D/victim.after"
    cmp -s "$D/victim.before" "$D/victim.after" || { fail "axis 2: the installer wrote THROUGH a planted /tmp symlink and clobbered a file outside its own staging area — arbitrary-file overwrite as the installing user (CVE-44)"; x=1; }
    grep -qx "$REALKEY" "$D/keys2" || { fail "axis 2: the verifier was handed '$(cat "$D/keys2")', not the pinned key"; x=1; }
    got2=$("$D/home2/versions/$VER/bin/cycc" 2>/dev/null || echo "<nothing installed>")
    [ "$got2" = "the genuine payload" ] || { fail "axis 2: '$got2' was installed — the planted /tmp tarball won"; x=1; }
    for f in $PLANTED; do cksum < "$f" 2>/dev/null || echo UNREADABLE; done > "$D/planted.after"
    cmp -s "$D/planted.before" "$D/planted.after" || { fail "axis 2: the installer WROTE or REMOVED another user's /tmp files — it is still staging there"; x=1; }
    rm -f $PLANTED
    [ "$x" = 0 ] && echo "  ok: axis 2: with the installer's fixed tarball names pre-planted (the tarball a symlink out of $SHARED_TMP), the link target is byte-for-byte, the planted files untouched and the genuine payload installs"
else
    fail "axis 2: could not plant the installer's fixed names under $SHARED_TMP — it is not writable here, so the exploit axis cannot run and must not read green"
    rm -f $PLANTED
fi

# ── axis 3: a temp dir that cannot be created ABORTS, it does not fall back ──
cat > "$D/stub/mktemp" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$D/stub/mktemp"
rc=0; _install scripts/ci.sh "$D/home3" "$D/keys3" "$D/a3.out" || rc=$?
x=0
[ "$rc" -ne 0 ] || { fail "axis 3: with mktemp failing the install still exited 0:"; sed 's/^/      /' "$D/a3.out" | head -4; x=1; }
[ -e "$D/home3/versions/$VER/bin/cycc" ] && { fail "axis 3: it installed something although it had nowhere private to stage"; x=1; }
grep -qi 'private temp' "$D/a3.out" || { fail "axis 3: the abort does not say why:"; sed 's/^/      /' "$D/a3.out" | head -4; x=1; }
rm -f "$D/stub/mktemp"
[ "$x" = 0 ] && echo "  ok: axis 3: mktemp failing aborts the install (rc $rc) with no fallback to a shared directory"

# ── axis 4: STATIC — no fixed /tmp name, and the temp dir is a checked mktemp ──
_fixed_tmp() { grep -n '"/tmp/\|[^A-Za-z_]/tmp/[A-Za-z0-9_$]' "$1" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v 'TMPDIR:-/tmp'; }
x=0
hits=$(_fixed_tmp scripts/ci.sh)
[ -z "$hits" ] || { fail "axis 4: scripts/ci.sh still names a fixed /tmp path:"; printf '%s\n' "$hits" | sed 's/^/      /'; x=1; }
grep -qE '^TD=\$\(mktemp -d' scripts/ci.sh || { fail "axis 4: scripts/ci.sh has no mktemp -d for its staging dir"; x=1; }
grep -qE '\[ ! -d "\$TD" \]|\[ -d "\$TD" \]' scripts/ci.sh || { fail "axis 4: scripts/ci.sh does not CHECK that its temp dir exists"; x=1; }
# self-test: the 6.6.5 shape must be reported
# built from $SHARED_TMP rather than spelled out, for the same reason the planted paths are:
# a literal "/tmp/<name>" in a gate is what gates_never_write_tree.sh axis 5 refuses.
printf 'curl -sfL "$URL" -o "%s/$TARBALL"\nprintf x > %s/cyrius-release.pub\n# %s/commented is not a use\n' \
    "$SHARED_TMP" "$SHARED_TMP" "$SHARED_TMP" > "$D/old.sh"
[ "$(_fixed_tmp "$D/old.sh" | wc -l | tr -d ' ')" = "2" ] || { fail "axis 4 self-test: the detector saw $(_fixed_tmp "$D/old.sh" | wc -l | tr -d ' ') of the 2 fixed /tmp uses in the pre-fix shape (and must ignore the comment)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: scripts/ci.sh names no fixed /tmp path and checks its mktemp -d (detector self-tested)"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: release_verify_private_temp (4 axes, CVE-44)"
