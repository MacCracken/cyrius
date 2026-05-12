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
# invocations. This file is the single source of truth for the cc5/cc5_win/
# cc5_aarch64 `--version` strings; if it drifts vs `VERSION`, `cc5
# --version` reports stale data. Same-version `version-bump.sh "$(cat
# VERSION)"` is the documented "regenerate without bumping" path.
if [ -f src/main.cyr ]; then
    LEN_CC5=$((${#NEW} + 5))           # "cc5 " + version + "\n"
    LEN_CC5_WIN=$((${#NEW} + 9))       # "cc5_win " + version + "\n"
    LEN_CC5_AARCH64=$((${#NEW} + 13))  # "cc5_aarch64 " + version + "\n"
    cat > src/version_str.cyr <<EOF
# src/version_str.cyr — AUTO-GENERATED from \`VERSION\` by
# \`scripts/version-bump.sh\`. Do NOT edit by hand; the next bump
# will overwrite. To regenerate without bumping, run:
#
#   sh scripts/version-bump.sh "\$(cat VERSION)"
#
# Why this file exists: pre-v5.6.39, each \`main_*.cyr\` had its own
# hardcoded \`"cc5 X.Y.Z\\n"\` literal + a hardcoded byte length.
# \`version-bump.sh\`'s sed regex didn't handle \`-N\` hotfix suffixes
# (e.g. \`5.6.29-1\`), so once a hotfix shipped, every subsequent bump
# silently skipped the literal — \`cc5 --version\` got stuck at
# \`5.6.29-1\` for 9 releases. Centralising the strings here means
# version-bump.sh writes ONE file every time and the sources just
# reference these vars. No regex hunting; no drift.

var _VERSION_STR_CC5         = "cc5 $NEW\n";
var _VERSION_LEN_CC5         = $LEN_CC5;
var _VERSION_STR_CC5_WIN     = "cc5_win $NEW\n";
var _VERSION_LEN_CC5_WIN     = $LEN_CC5_WIN;
var _VERSION_STR_CC5_AARCH64 = "cc5_aarch64 $NEW\n";
var _VERSION_LEN_CC5_AARCH64 = $LEN_CC5_AARCH64;

# v5.11.25: bare-version string for cbt/cyrius.cyr's version-resolved
# dispatcher. Compared against cyrius.cyml's \`[package].cyrius\` field
# at every \`cyrius\` invocation; if pinned !=  this, re-exec the pinned
# binary. See \`_try_redirect_to_pinned()\` in cbt/cyrius.cyr.
var _VERSION_TOOLCHAIN       = "$NEW";
EOF
fi

if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD (regenerated src/version_str.cyr)"
    exit 0
fi

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

# 6. Install-snapshot refresh (v5.4.18): reconcile
# ~/.cyrius/versions/$NEW/ with the current repo so a dep bump or
# new tool appears immediately — no waiting for the next full install.
# install.sh --refresh-only skips tarball fetch / bootstrap and just
# re-copies build/ + scripts/ named in cyrius.cyml [release] + lib/.
# Skipped silently if install.sh is missing (shouldn't happen in a
# normal cyrius checkout).
if [ -x scripts/install.sh ]; then
    sh scripts/install.sh --refresh-only 2>/dev/null || \
        echo "  warning: install-snapshot refresh failed (non-fatal)" >&2
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
