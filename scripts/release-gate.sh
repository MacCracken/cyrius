#!/bin/sh
# scripts/release-gate.sh — THE consolidated pre-tag release gate.
#
# Run this and get GREEN before EVERY `.NN` version-bump + tag + handoff. It is the
# SINGLE source of truth for "what must pass before a release", so no individual gate
# gets run à la carte and skipped.
#
# Why this exists: the v6.3.0 seed break (2026-06-28). A compiler change passed the
# cycc self-host fixpoint + check.sh + cross-OS, so it looked release-ready — but
# `seed-derive-cycc.sh` was NOT run (it had only ever been framed as a minor/major
# *closeout* check). The change broke the seed -> cybs -> cycc chain; CI caught it,
# not us. KEY LESSON, baked in here: **the cycc self-host fixpoint does NOT cover the
# seed chain.** cybs (the hand-assembly bootstrap compiler the seed assembles) is far
# more limited than build/cycc and fails SILENTLY on things build/cycc compiles fine.
# So seed-derive is its own mandatory gate, EVERY release, for ANY src/ change.
# See: feedback_seed_derive_mandatory_cybs_limits.
#
# Gates (fail-fast — stops at the first RED):
#   1. self-host fixpoint   build/cycc reproduces itself + == cycc(src)
#  1b. ARM binary lockstep  build/cycc-native-aarch64 == what this tree cross-builds
#                           (the ONE tracked cross-bin; nothing checked it and it went
#                            ~60 releases stale — v6.6.6. Skipped under --quick.)
#   2. SEED DERIVE          seed -> cybs -> cycc byte-identical          [the critical one]
#   3. check.sh             all gates green; a SKIP fails unless RG_SKIP_ALLOW names it
#   4. cross-OS self-host   ecb (macOS-arm64) + ach (Intel-Mac) + cass (Windows) + pi
#                           (aarch64), REAL hardware
#   5. bench                record self_compile + cycc size              (non-blocking)
#
# Usage:
#   sh scripts/release-gate.sh            full gate (run before tag/handoff)
#   sh scripts/release-gate.sh --quick    steps 1-3 only (LOCAL ITERATION — NOT release-ready)
#   sh scripts/release-gate.sh --check-verdict <check.sh output> <its exit status>
#                                         step 3's verdict alone, over a saved run; runs
#                                         nothing (tests/gates/toolchain/release_gate_check_verdict.sh)

# Step 3 — the gates allowed to SKIP (exit 77, "could not run its check"), by exact path, one
# per line. ANY other SKIP fails the step. check.sh itself exits 0 over a SKIP ("GREEN, with N
# gate(s) SKIPPED"), and this gate used to take that 0, so the one mandated pre-tag gate went
# green over gates that never checked anything (CI runs its delegated rows under
# CYRIUS_CHECK_NO_SKIP=1; this did not). Each entry needs its reason; widening the list is a
# decision, not a fix. CHANGELOG [6.6.20]
#   agnos_monotonic_clock_rdtsc  axis 5's refused-calibration fallback is unreachable on a
#                                mirshi that answers #95 (the dev box's does)
#   agnos_sysinfo_tail_parity    its runtime axis's pre-1.57.9 path is unreachable on a mirshi
#                                that fills sched_kicks (the dev box's does)
RG_SKIP_ALLOW="tests/gates/platform/agnos_monotonic_clock_rdtsc.sh
tests/gates/platform/agnos_sysinfo_tail_parity.sh"

# Step 3's verdict over a check.sh output file <$1> and its exit status <$2>. Prints what it
# read; returns 1 with the reason in _RG_WHY. A function so a gate can drive it with fixtures.
_rg_check_verdict() {
    _RG_WHY=""
    # The DRIVER's tally — the check binary prints it on the line after its ════ rule, as
    # `N passed, M failed, K skipped (T total)`. The old `grep "passed, N failed" | tail -1`
    # took the LAST such line, which in a full run is a shell gate's own count. Exactly one
    # line may match, or the verdict says it cannot tell which is the driver's.
    _rg_dl=$(awk -v rule='════════════════════════' \
        'prev == rule && /^[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped \([0-9]+ total\)/ { print } { prev = $0 }' "$1")
    _rg_dn=$(printf '%s\n' "$_rg_dl" | grep -c . || true)
    echo "  driver: ${_rg_dl:-<no tally line>}"
    # v6.6.6: check.sh prints its own end-of-run summary naming what failed and what NEVER RAN
    # — the actionable part, and "NOT RUN" is not a pass.
    sed -n '/check.sh summary/,$p' "$1" | sed 's/^/  /'
    if [ "$2" != "0" ]; then
        grep -E "^  FAIL|^  SKIP|NOT RUN" "$1" | tail -12
        # 6.7.7: the driver's own failing rows, named — check.sh's summary says only "the cyrius check
        # binary", so a RED test suite never named its file (the first 6.7.7 gate run).
        _rg_tf=$(grep -E '^  [A-Za-z0-9_./-]+ +(FAIL|TIMEOUT)' "$1" | head -20 || true)
        if [ -n "$_rg_tf" ]; then echo "  driver rows that failed:"; printf '%s\n' "$_rg_tf" | sed 's/^/  /'; fi
        _RG_WHY="check.sh exited $2 — see its summary above (the binary's 'N passed, M failed' line does NOT cover the shell gates)"
        return 1
    fi
    if [ "$_rg_dn" != "1" ]; then
        _RG_WHY="cannot identify the check driver's tally line (found $_rg_dn lines of the shape 'N passed, M failed, K skipped (T total)' after its rule; expected exactly 1)"
        return 1
    fi
    case "$_rg_dl" in
        *", 0 failed,"*) ;;
        *) _RG_WHY="the check driver reports failures: $_rg_dl"; return 1 ;;
    esac
    # Every SKIP check.sh lists (shell gates and the driver's own rows) must be allowlisted,
    # and the list must agree with its own `skipped:` count — a summary we cannot parse is red.
    _rg_ns=$(sed -n '/check.sh summary/,$p' "$1" | sed -n 's/^  skipped: *\([0-9][0-9]*\) .*/\1/p' | head -1)
    if [ -z "$_rg_ns" ]; then
        _RG_WHY="check.sh's summary carries no 'skipped: N' count — cannot tell what was skipped"
        return 1
    fi
    _rg_sk=$(sed -n '/check.sh summary/,$p' "$1" | awk '
        /^  SKIPPED / { inl = 1; next }
        inl && /^    / { sub(/^    /, ""); sub(/^\(driver row\) /, ""); print; next }
        { inl = 0 }')
    _rg_skn=$(printf '%s\n' "$_rg_sk" | grep -c . || true)
    if [ "$_rg_skn" != "$_rg_ns" ]; then
        _RG_WHY="check.sh says $_rg_ns skipped but lists $_rg_skn — cannot tell what was skipped"
        return 1
    fi
    _rg_bad=""
    if [ -n "$_rg_sk" ]; then
        _rg_bad=$(printf '%s\n' "$_rg_sk" | while IFS= read -r _rg_s; do
            if printf '%s\n' "$RG_SKIP_ALLOW" | grep -qxF -e "$_rg_s"; then
                echo "  allowed SKIP: $_rg_s" >&2
            else
                printf ' %s' "$_rg_s"
            fi
        done)
    fi
    if [ -n "$_rg_bad" ]; then
        _RG_WHY="check.sh SKIPPED gate(s) not on RG_SKIP_ALLOW:$_rg_bad — a gate that could not run its check is not a pass"
        return 1
    fi
    return 0
}

if [ "${1:-}" = "--check-verdict" ]; then
    [ -f "${2:-}" ] && [ -n "${3:-}" ] ||
        { echo "usage: sh scripts/release-gate.sh --check-verdict <check.sh output> <its exit status>" >&2; exit 2; }
    if _rg_check_verdict "$2" "$3"; then echo "STEP 3: GREEN"; exit 0; fi
    echo "STEP 3: RED — $_RG_WHY"
    exit 1
fi

cd "$(dirname "$0")/.." || exit 2
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# $2 (optional) is a file holding the failed command's stderr, printed with the verdict.
# v6.6.6: every compile below used to send stderr to /dev/null, so a failing one printed
# a one-line verdict and threw the compiler's own diagnostic away — the operator is then
# told WHAT failed and nothing about WHY, which is the swallowed-compile-error shape
# check.sh's v6.5.40 note exists to prevent. CHANGELOG [6.6.6]
# v6.6.6: CHECKED — an unchecked mktemp leaves the variable EMPTY on a full or unwritable
# temp dir, and every "$V/x" below then becomes "/x". CHANGELOG [6.6.6]
T=$(mktemp -d) && [ -d "$T" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
fail() {
    echo ""
    echo "================================================================"
    echo "RELEASE GATE: RED — $1"
    if [ -n "${2:-}" ] && [ -s "$2" ]; then
        echo "---------------- stderr from the failed command -----------------"
        sed 's/^/  /' "$2"
        echo "----------------------------------------------------------------"
    fi
    echo "Do NOT version-bump / tag / hand off until this is GREEN."
    echo "================================================================"
    # 6.7.0: cross-OS legs still running in the background (the parallel gate) are stopped; each
    # removes its own local and remote staging on the way out (cross-os-selfhost.sh's trap).
    if [ -n "${_RG_LEG_PIDS:-}" ]; then kill -TERM $_RG_LEG_PIDS 2>/dev/null || true; wait $_RG_LEG_PIDS 2>/dev/null || true; fi
    # 6.7.7: check.sh's full output outlives a RED run (in a private mktemp file, never a fixed
    # name) — it was removed with $T, so the first 6.7.7 run's failing test could not be named.
    if [ -s "$T/check.out" ]; then
        _rg_kd=$(mktemp -d) && [ -d "$_rg_kd" ] || { echo "error: mktemp -d failed — check.sh's output stays in $T"; exit 1; }
        cp "$T/check.out" "$_rg_kd/check.out" && echo "check.sh's full output is kept at $_rg_kd/check.out"
    fi
    rm -rf "$T"
    exit 1
}
step() { echo ""; echo "=== [$1] $2 ==="; }

chmod +x bootstrap/asm build/cycc 2>/dev/null

# 1. self-host fixpoint -------------------------------------------------------
step "1/5" "self-host fixpoint (build/cycc reproduces itself byte-identical)"
cat src/main.cyr | ./build/cycc > "$T/g1" 2> "$T/g1.err" || fail "cycc failed to compile src/main.cyr" "$T/g1.err"
chmod +x "$T/g1"
cat src/main.cyr | "$T/g1" > "$T/g2" 2> "$T/g2.err" || fail "gen1 (cycc's self-build) crashed compiling src/main.cyr" "$T/g2.err"
cmp -s "$T/g1" "$T/g2" || fail "self-host fixpoint broken (gen1 != gen2)"
cmp -s "$T/g1" build/cycc || fail "build/cycc is NOT cycc(src) — rebuild build/cycc, it's stale or wrong"
echo "  OK: byte-identical ($(wc -c < build/cycc) B)"

# 1b. TRACKED ARM BINARY IN LOCKSTEP WITH THE TREE ---------------------------
#
# build/cycc-native-aarch64 is the ONE cross-binary this repo tracks, because it is the
# only one that cannot be regenerated by cross-compiling on the target: ARM hardware
# self-host needs a binary that already runs on ARM. Everything downstream trusts it —
# install.sh --refresh-only copies it into versions/<v>/bin/, verify-store.sh restores
# it from the tag, and an ARM install falls back to it.
#
# ⛔ NOTHING CHECKED IT. Not check.sh, not this gate, not CI: the pi leg builds its own
# compilers fresh from source, so a stale tracked binary is invisible everywhere. It sat
# at a 2026-07-02 build for ~60 releases and 2.5 months (940,536 B against a tree that
# produced 1,505,480 B) and by the end it was not merely old but WRONG — 6.6.5 moved the
# aarch64 peer's SYS_UNLINKAT from 35 to 263, so the stale emitter had no 263->35 row and
# `sys_unlink` compiled against the 6.6.5 stdlib traced as `fanotify_mark`. 6.6.5 bite 5
# regenerated it BY HAND; this is the gate that makes the next drift impossible.
#
# The derivation is deterministic, local and ~1 s — no ARM hardware needed. It is NOT in
# check.sh deliberately: it needs a full cross-build of two compilers and check.sh is the
# fast inner loop. CHANGELOG [6.6.6]
step "1b/5" "tracked build/cycc-native-aarch64 == what this tree cross-builds"
if [ "$QUICK" = "1" ]; then
    echo "  SKIPPED under --quick (it goes stale on every compiler bite; --quick is not release-ready anyway)"
elif [ ! -f build/cycc-native-aarch64 ]; then
    fail "build/cycc-native-aarch64 is MISSING — it is tracked; restore it (git checkout build/cycc-native-aarch64) or regenerate it, see below"
else
    ./build/cycc < src/main_aarch64.cyr > "$T/xa64" 2> "$T/xa64.err" || fail "cycc could not cross-build src/main_aarch64.cyr" "$T/xa64.err"
    chmod +x "$T/xa64"
    "$T/xa64" < src/main_aarch64_native.cyr > "$T/nat" 2> "$T/nat.err" || fail "the aarch64 cross-compiler could not build src/main_aarch64_native.cyr" "$T/nat.err"
    if ! cmp -s "$T/nat" build/cycc-native-aarch64; then
        _lsd=$(git log -1 --format=%ad --date=short -- build/cycc-native-aarch64 2>/dev/null)
        echo "  tracked:   $(wc -c < build/cycc-native-aarch64) B${_lsd:+  (last committed $_lsd)}"
        echo "  this tree: $(wc -c < "$T/nat") B"
        # SAY WHERE, and say it from cmp — equal sizes with different bytes is the common
        # case (a changed instruction, not a changed layout), and a size line alone reads
        # like a false positive when the two numbers match.
        echo "  $(cmp "$T/nat" build/cycc-native-aarch64 2>&1 | head -1 | sed 's/^.*differ/differ/')"
        echo ""
        echo "  WHAT THIS MEANS: the committed ARM compiler was built from OLDER sources than"
        echo "  the ones in this tree, so ARM users would install a compiler that does not"
        echo "  contain this release's backend/stdlib changes. It is a stale ARTEFACT, not a"
        echo "  broken build — nothing else is wrong."
        echo "  HOW TO FIX (deterministic, local, no ARM hardware — then re-run this gate):"
        echo "      cyrius pulsar                      # the supported way (CLAUDE.md)"
        echo "  or, equivalently, by hand:"
        echo "      ./build/cycc < src/main_aarch64.cyr > build/cycc_aarch64"
        echo "      chmod +x build/cycc_aarch64"
        echo "      build/cycc_aarch64 < src/main_aarch64_native.cyr > build/cycc-native-aarch64"
        echo "      chmod +x build/cycc-native-aarch64"
        fail "build/cycc-native-aarch64 is STALE — it is not what this tree cross-builds"
    fi
    echo "  OK: in lockstep ($(wc -c < build/cycc-native-aarch64) B)"
fi

# 2. SEED DERIVE — the gate v6.3.0 missed ------------------------------------
step "2/5" "seed -> cybs -> cycc derivation (the cycc fixpoint does NOT cover this)"
sh scripts/seed-derive-cycc.sh > "$T/seed.out" 2>&1
if ! grep -q "machine-derivable from the" "$T/seed.out"; then
    tail -8 "$T/seed.out"
    fail "SEED DERIVATION BROKEN — cybs cannot reproduce build/cycc from the 29KB seed. NEVER tag this."
fi
echo "  OK: build/cycc is machine-derivable from the seed"

# 3. check.sh -----------------------------------------------------------------
# 6.7.0 — THE FOUR CROSS-OS LEGS RUN ALONGSIDE check.sh. They were walked one by one AFTER it, so
# the gate took ~46 minutes: check.sh, then ecb, ach, cass and pi in turn. cross-os-selfhost.sh has
# been safe to run concurrently since 6.6.6 (private local + remote staging per run) and its work
# is mostly on the remote host, so the legs start here and are WAITED FOR, in host order, at step
# 4. CYRIUS_GATE_SERIAL=1 keeps the old walk. CHANGELOG [6.7.0]
_RG_PAR=1
if [ "${CYRIUS_GATE_SERIAL:-0}" = "1" ]; then _RG_PAR=0; fi
_RG_LEG_PIDS=""
if [ "$QUICK" != "1" ] && [ "$_RG_PAR" = "1" ]; then
    for H in ecb ach cass pi; do
        sh scripts/cross-os-selfhost.sh "$H" "crossos" > "$T/co.$H.out" 2>&1 &
        eval "_RG_PID_$H=\$!"
        _RG_LEG_PIDS="$_RG_LEG_PIDS $!"
    done
    echo "  (the cross-OS legs ecb ach cass pi started in the background — step 4 waits for them)"
fi

step "3/5" "check.sh (full gate suite)"
# v6.5.0: capture the EXIT STATUS, not just the printed summary.
#
# This step used to grep only for "N passed, 0 failed" — the count emitted by the
# cyrius check BINARY. But check.sh also runs shell gates AFTER that binary
# (qemu-boot, sign-efi, and the v6.5.0 valform-simd / fileid-substrate /
# visibility-private gates). A failure in any of those aborts check.sh with a
# non-zero exit while the earlier summary line still says "0 failed" — so the
# release gate reported GREEN over a red gate. Found when the fileid-substrate
# matcher broke and the release gate did not notice.
#
# 6.6.20: the verdict is `_rg_check_verdict` (top of this file): check.sh's exit status, the
# DRIVER's tally line (not the last "passed, N failed" a shell gate printed), and every SKIP
# on RG_SKIP_ALLOW — check.sh exits 0 over a SKIP, and that 0 used to be taken as green.
#
# `|| rc=$?` keeps this working under `set -e`.
rc=0
sh scripts/check.sh > "$T/check.out" 2>&1 || rc=$?
_rg_check_verdict "$T/check.out" "$rc" || fail "$_RG_WHY"

if [ "$QUICK" = "1" ]; then
    rm -rf "$T"
    echo ""
    echo "RELEASE GATE: --quick PASSED steps 1-3."
    echo "*** NOT RELEASE-READY *** — cross-OS (4) + bench (5) were SKIPPED."
    echo "Run without --quick before version-bump / tag / handoff."
    exit 0
fi

# 4. cross-OS self-host + cross-host platform LIBTEST. Walked SEQUENTIALLY for load and for
# readable output — NOT for safety any more: v6.6.6 gave cross-os-selfhost.sh per-run local
# and remote staging, so concurrent runs no longer clobber (the old reason written here). v6.3.43 promoted LIBTEST from an opt-in fallback to a
# STANDING per-host gate — the platform-variant tcyr (fs/thread/sync/alloc/args/process/
# syscalls on cass+ecb) run on real hardware every release, so macOS/Windows stdlib rot
# is caught here, not by ports.
#
# v6.5.11: the selector is the SUBDIRECTORY tests/tcyr/crossos (it was the filename
# prefix "vr01_"). A directory is checked for existence and cannot silently under-match;
# cross-os-selfhost.sh additionally cross-checks the remote's ran-count against the count
# selected locally, closing the "LIBTEST_OK: <host> (0 tests)" green-over-nothing path.
step "4/5" "cross-OS self-host + cross-host platform tcyr: ecb (macOS-arm64) + ach (Intel-Mac x86-macho) + cass (Windows) + pi (aarch64) — REAL hardware"
# v6.4.59: ach (Intel Mac, x86_64 Mach-O) added — its compiler self-hosts + the
# usable toolchain works (wrapper argv/env/arch via r15). Without it in this
# ONE mandated pre-tag gate, x86-macho could rot green behind a CI check exactly
# like macOS-arm64 did for ~9 minors (the found-by-ports incident). The ach recipe
# has the exit-42 rot-guard + the crossos subdir fires its platform libtest.
for H in ecb ach cass pi; do
    echo "  --- $H ---"
    if [ "$_RG_PAR" = "1" ]; then
        eval "_rg_p=\$_RG_PID_$H"
        wait "$_rg_p" 2>/dev/null || true
        cp "$T/co.$H.out" "$T/co.out"
    else
        sh scripts/cross-os-selfhost.sh "$H" "crossos" > "$T/co.out" 2>&1
    fi
    if ! grep -q "SELFHOST_OK: $H" "$T/co.out"; then
        tail -8 "$T/co.out"
        fail "cross-OS self-host FAILED on $H (a green CI check is NOT this — run the compiler on the hardware)"
    fi
    if ! grep -q "LIBTEST_OK: $H" "$T/co.out"; then
        tail -8 "$T/co.out"
        fail "cross-host platform tcyr FAILED on $H (found-by-ports stdlib rot — see the failing tests/tcyr/crossos test)"
    fi
    echo "  OK: $H SELFHOST_OK + crossos LIBTEST_OK"
done

# 5. bench (non-blocking — record the delta, triage per the growth-tax rule) ---
step "5/5" "bench (self_compile + cycc size — record in CHANGELOG; non-blocking)"
sh scripts/bench-history.sh 2>&1 | grep -iE "self_compile|size/cycc" | head || echo "  (bench ran)"

rm -rf "$T"
echo ""
echo "================================================================"
# v6.6.4: the install store must equal its tags. Advisory here (the release gate runs BEFORE
# the tag, so the slot about to be cut is untagged and not judged); what it catches is the
# PREVIOUS releases' slots having been written from a drifted tree — the shape that made the
# installed "6.6.2" stdlib 6.6.3's. Repair with `sh scripts/verify-store.sh --restore <v>`.
step "store" "verify-store (every tagged install slot == its tag; advisory)"
if ! sh scripts/verify-store.sh; then
    echo "  warning: the install store does not match its tags — run scripts/verify-store.sh --restore <v> before handing off"
fi

echo ""
echo "RELEASE GATE: GREEN — safe to version-bump + tag + hand off."
echo "  Then, AFTER the tag: sh scripts/install.sh --refresh-only   (tree == tag → the new slot is written from the tag; stamped)"
echo "  Record the bench self_compile + cycc-size delta in the CHANGELOG."
echo "================================================================"
