#!/bin/sh
# Version bump script — single source of truth for all version references
# Usage: ./scripts/version-bump.sh 1.9.0

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Current: $(cat VERSION)"
    exit 1
fi

NEW="$1"
OLD=$(cat VERSION | tr -d '[:space:]')

# Regenerate src/version_str.cyr unconditionally — including same-version
# invocations. This file is the single source of truth for the cycc/cycc_win/
# cycc_aarch64 `--version` strings; if it drifts vs `VERSION`, `cycc
# --version` reports stale data. Same-version `version-bump.sh "$(cat
# VERSION)"` is the documented "regenerate without bumping" path.
if [ -f src/main.cyr ]; then
    # v6.0.0: renamed CC5 → CYCC variables + binary names.
    # Byte-length calcs: "cycc " (5) + ver + "\n" (1) = ver + 6, etc.
    LEN_CYCC=$((${#NEW} + 6))            # "cycc " + version + "\n"
    LEN_CYCC_WIN=$((${#NEW} + 10))       # "cycc_win " + version + "\n"
    LEN_CYCC_AARCH64=$((${#NEW} + 14))   # "cycc_aarch64 " + version + "\n"
    cat > src/version_str.cyr <<EOF
# src/version_str.cyr — AUTO-GENERATED from \`VERSION\` by
# \`scripts/version-bump.sh\`. Do NOT edit by hand; the next bump
# will overwrite. To regenerate without bumping, run:
#
#   sh scripts/version-bump.sh "\$(cat VERSION)"
#
# Why this file exists: pre-v5.6.39, each \`main_*.cyr\` had its own
# hardcoded \`"cycc X.Y.Z\\n"\` literal + a hardcoded byte length.
# \`version-bump.sh\`'s sed regex didn't handle \`-N\` hotfix suffixes
# (e.g. \`5.6.29-1\`), so once a hotfix shipped, every subsequent bump
# silently skipped the literal — \`cycc --version\` got stuck at
# \`5.6.29-1\` for 9 releases. Centralising the strings here means
# version-bump.sh writes ONE file every time and the sources just
# reference these vars. No regex hunting; no drift.

var _VERSION_STR_CYCC          = "cycc $NEW\n";
var _VERSION_LEN_CYCC          = $LEN_CYCC;
var _VERSION_STR_CYCC_WIN      = "cycc_win $NEW\n";
var _VERSION_LEN_CYCC_WIN      = $LEN_CYCC_WIN;
var _VERSION_STR_CYCC_AARCH64  = "cycc_aarch64 $NEW\n";
var _VERSION_LEN_CYCC_AARCH64  = $LEN_CYCC_AARCH64;

# v5.11.25: bare-version string for cbt/cyrius.cyr's version-resolved
# dispatcher. Compared against cyrius.cyml's \`[package].cyrius\` field
# at every \`cyrius\` invocation; if pinned !=  this, re-exec the pinned
# binary. See \`_try_redirect_to_pinned()\` in cbt/cyrius.cyr.
var _VERSION_TOOLCHAIN       = "$NEW";
EOF
fi

# v6.5.3 — the same-version path must NOT exit here.
#
# It used to `exit 0` right after regenerating src/version_str.cyr. That is exactly
# half the job: version_str.cyr is only a SOURCE file, and every binary built from it
# — the seven src/main*.cyr forks and the cbt/cyrius.cyr CLI wrapper — kept whatever
# version string it was last compiled with. Result observed at 6.5.2:
#
#     $ cyrius --version
#     cyrius 6.5.1
#     manifest-pin: 6.5.2 (drift — wrapper is 6.5.1)
#
# i.e. the wrapper's own drift detector firing on drift this script caused. This is the
# SAME papercut v5.11.58 fixed for the version-CHANGE path (it added the touch loop
# below); the same-version path was left exiting before ever reaching it.
#
# It also silently falsified CLAUDE.md's snapshot-ping-pong remedy, which tells you to
# run `version-bump.sh "$(cat VERSION)"` "which re-runs install.sh --refresh-only" —
# it never got there, so the documented fix for a `lib/` edit reverting under you did
# nothing.
#
# So: only the steps that genuinely require a version CHANGE are skipped (the VERSION
# file and the four doc/CHANGELOG rewrites, all of which are no-ops or actively wrong
# when NEW == OLD). Everything from the force-rebuild onward runs unconditionally,
# because "regenerate the version string" without "rebuild its consumers" is not a
# meaningful operation.
if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD — regenerating src/version_str.cyr and REBUILDING its consumers"
else

# 1. VERSION file (source of truth)
echo "$NEW" > VERSION

# 2. install.sh fallback version
sed -i "s/VERSION=\"$OLD\"/VERSION=\"$NEW\"/" scripts/install.sh 2>/dev/null || true

# 3. CLAUDE.md
sed -i "s/- \*\*Version\*\*: $OLD/- **Version**: $NEW/" CLAUDE.md 2>/dev/null || true

# 4. CHANGELOG.md — add unreleased section if not present
#
# v5.8.49 hardening: anchor on `^## \[Unreleased\]$` (start-of-line
# through end-of-line) instead of bare `## \[Unreleased\]`. The
# previous loose pattern matched ANY line containing the substring
# — including narrative body text in the CHANGELOG that quotes
# `## [Unreleased]` (e.g. the v5.8.48 entry's anchor-restoration
# section). At the v5.8.49 bump that loose pattern fired 4 times,
# inserting 3 spurious version headers inside the v5.8.48 body
# before being cleaned up by hand. Anchored pattern matches ONLY
# the literal Unreleased header line.
if ! grep -q "## \[$NEW\]" CHANGELOG.md 2>/dev/null; then
    # Insert new version header after the [Unreleased] header line
    sed -i "/^## \[Unreleased\]$/a\\
\\
## [$NEW] — $(date +%Y-%m-%d)" CHANGELOG.md 2>/dev/null || true
fi

# 5. Roadmap header
sed -i "s/> \*\*v$OLD\.\*\*/> **v$NEW.**/" docs/development/roadmap.md 2>/dev/null || true

fi   # end version-CHANGE-only steps (1-5); everything below runs for both paths

# v5.11.58: force-rebuild binaries whose version_str.cyr dep
# install.sh::_rebuild_stale can't see. The `-nt source` check
# only looks at the direct source file; it misses transitive
# includes. Without this, every bump since 2026-05-12 propagated
# a stale `cyrius` wrapper (the iron-boot papercut filing Item 1
# observed `cyrius --version: 5.11.25` despite consumers pinning
# 5.11.55).
#
# Two-step:
#   (a) `touch` every consumer source of version_str.cyr so
#       install.sh's `binary -nt source` check fails and triggers
#       rebuild. Captures all main_*.cyr cross-compilers + cbt/
#       cyrius.cyr wrapper.
#   (b) Rebuild cycc explicitly — install.sh skips cycc entirely
#       per its "seed-bootstrapped" contract (line 158), so the
#       touch alone wouldn't restore it.
for _f in src/main.cyr src/main_aarch64.cyr src/main_win.cyr \
          src/main_cx.cyr src/main_aarch64_native.cyr \
          src/main_aarch64_macho.cyr cbt/cyrius.cyr; do
    [ -f "$_f" ] && touch "$_f"
done
if [ -x build/cycc ]; then
    if cat src/main.cyr | ./build/cycc > build/cycc.new 2>/tmp/cycc-rebuild.err; then
        mv build/cycc.new build/cycc
        chmod +x build/cycc
        echo "  > cycc rebuilt for $NEW"
    else
        echo "  ! cycc rebuild failed (non-fatal):" >&2
        sed 's/^/    /' /tmp/cycc-rebuild.err >&2
        rm -f build/cycc.new
    fi
    rm -f /tmp/cycc-rebuild.err
fi

# 6. Install-snapshot refresh (v5.4.18): reconcile
# ~/.cyrius/versions/$NEW/ with the current repo so a dep bump or
# new tool appears immediately — no waiting for the next full install.
# install.sh --refresh-only skips tarball fetch / bootstrap and just
# re-copies build/ + scripts/ named in cyrius.cyml [release] + lib/.
# Skipped silently if install.sh is missing (shouldn't happen in a
# normal cyrius checkout).
if [ -x scripts/install.sh ]; then
    # v6.5.3: do NOT swallow stderr. This suppression is why an ETXTBSY `cp` failure
    # that stranded all 17 installed binaries went unseen across multiple releases.
    sh scripts/install.sh --refresh-only || \
        echo "  warning: install-snapshot refresh failed (non-fatal)" >&2
fi

# 6b. SEED-DERIVE GATE (v6.3.0 lesson — never tag a broken seed). The cycc
# self-host fixpoint does NOT cover the seed -> cybs -> cycc chain: cybs (the
# hand-assembly bootstrap compiler) is far more limited than build/cycc and fails
# SILENTLY on things build/cycc compiles fine. version-bump runs at EVERY slot, so
# wiring the critical gate here makes it impossible to miss. Verifies the
# just-rebuilt build/cycc is still machine-derivable from the 29KB seed. Set
# CYRIUS_SKIP_SEED_GATE=1 only for a KNOWN doc/lib-only bump (src/ untouched).
# See: scripts/release-gate.sh, feedback_seed_derive_mandatory_cybs_limits.
if [ "${CYRIUS_SKIP_SEED_GATE:-0}" != "1" ] && [ -x scripts/seed-derive-cycc.sh -o -f scripts/seed-derive-cycc.sh ]; then
    echo "  > seed-derive gate (seed -> cybs -> cycc)..."
    if sh scripts/seed-derive-cycc.sh > /tmp/_vb_seed.out 2>&1 && grep -q "machine-derivable from the" /tmp/_vb_seed.out; then
        echo "  > seed-derive OK (build/cycc is machine-derivable from the seed)"
    else
        tail -6 /tmp/_vb_seed.out >&2
        echo "" >&2
        echo "  ************************************************************" >&2
        echo "  SEED DERIVE FAILED after the $NEW rebuild — DO NOT TAG $NEW." >&2
        echo "  cybs cannot reproduce build/cycc from the seed: a src/ change" >&2
        echo "  broke the seed chain (the cycc self-host fixpoint misses this)." >&2
        echo "  Fix, then re-run version-bump (same-version regenerate path)." >&2
        echo "  See feedback_seed_derive_mandatory_cybs_limits." >&2
        echo "  ************************************************************" >&2
        exit 1
    fi
fi

echo "$OLD -> $NEW"
echo ""
echo "Updated:"
echo "  VERSION"
echo "  CLAUDE.md"
echo "  CHANGELOG.md"
echo "  docs/development/roadmap.md"
echo "  scripts/install.sh"
echo "  ~/.cyrius/versions/$NEW/ (install snapshot refreshed)"
echo ""
echo "Still manual:"
echo "  - CHANGELOG.md entries (add Fixed/Changed/Added sections)"
echo "  - vidya version references (language.toml)"
echo "  - Compiler binary size in CLAUDE.md if changed"
