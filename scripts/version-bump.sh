#!/bin/sh
# Version bump script — single source of truth for all version references
#
# Usage:
#   sh scripts/version-bump.sh <version>
#       Bump THIS tree: VERSION, the document anchors (CLAUDE.md, cyrius.cyml, CHANGELOG.md,
#       the roadmap `Current head:` stamp), src/version_str.cyr, rebuild build/cycc, refresh
#       the install snapshot, run the seed-derive gate.
#   sh scripts/version-bump.sh --docs-only <dir> <version>
#       Rewrite ONLY the document anchors of the copies under <dir> (same relative paths:
#       VERSION, CLAUDE.md, cyrius.cyml, CHANGELOG.md, docs/development/roadmap.md) and
#       verify each one. Nothing is regenerated, rebuilt or installed. This is how
#       tests/gates/toolchain/version_bump_doc_anchors.sh forecasts the NEXT bump over
#       scratch copies of the live docs. CHANGELOG [6.6.7]
#
# Every document step is VERIFIED after it runs. A step that did not take effect is named
# on stderr where it happens, and the script exits non-zero at the END (after the rebuild
# and the seed gate), so a bump never reports success over an anchor it failed to rewrite.

set -e

DOCS_ONLY=0
if [ "${1:-}" = "--docs-only" ]; then
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
        echo "Usage: $0 --docs-only <dir> <version>" >&2
        exit 2
    fi
    if [ ! -d "$2" ]; then
        echo "error: --docs-only: '$2' is not a directory" >&2
        exit 2
    fi
    cd "$2"
    DOCS_ONLY=1
    shift 2
fi

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <version>"
    echo "       $0 --docs-only <dir> <version>"
    echo "Current: $(cat VERSION)"
    exit 1
fi

NEW="$1"
OLD=$(cat VERSION | tr -d '[:space:]')

# Both versions are spliced into sed patterns and replacements below. Only [0-9A-Za-z.-]
# is accepted (5.6.29-1 hotfix suffixes included), so the one regex metacharacter a version
# can carry is `.` — escaped in *_RE, or `6.6.7` would also match `6x6x7`. CHANGELOG [6.6.7]
for _v in "$NEW" "$OLD"; do
    case "$_v" in
        ''|*[!0-9A-Za-z.-]*|[!0-9]*)
            echo "error: '$_v' is not a version (expected e.g. 6.6.8 or 5.6.29-1)" >&2
            exit 2 ;;
    esac
done
OLD_RE=$(printf '%s' "$OLD" | sed 's/\./\\./g')
NEW_RE=$(printf '%s' "$NEW" | sed 's/\./\\./g')
TODAY=$(date +%Y-%m-%d)

if [ "$DOCS_ONLY" = "1" ] && [ "$NEW" = "$OLD" ]; then
    echo "error: --docs-only: '$NEW' is already the VERSION in $(pwd) — nothing to rewrite" >&2
    exit 2
fi

# Regenerate src/version_str.cyr unconditionally — including same-version
# invocations. This file is the single source of truth for the cycc/cycc_win/
# cycc_aarch64 `--version` strings; if it drifts vs `VERSION`, `cycc
# --version` reports stale data. Same-version `version-bump.sh "$(cat
# VERSION)"` is the documented "regenerate without bumping" path.
if [ "$DOCS_ONLY" = "0" ] && [ -f src/main.cyr ]; then
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

# --- document-step bookkeeping (v6.6.7) --------------------------------------------------
# Each step reports through _vb_result, which (a) names a step that did not take effect on
# stderr AT THE STEP, (b) counts it in _VB_FAIL for the non-zero exit at the END, and (c)
# records what actually happened for the summary. The summary used to print VERSION,
# CLAUDE.md and CHANGELOG.md under "Updated:" unconditionally — on the same-version path
# too — and never listed cyrius.cyml, which step 3b does rewrite. CHANGELOG [6.6.7]
_VB_FAIL=0
_VB_DOCS=""
_vb_sum() { if [ -f "$1" ]; then cksum < "$1"; else echo missing; fi; }
_vb_line() { _VB_DOCS="$_VB_DOCS
  $1"; }
# _vb_result <file> <cksum-before> <took-effect 1|0> [reason]
_vb_result() {
    if [ "$3" = "1" ]; then
        if [ "$(_vb_sum "$1")" = "$2" ]; then
            _vb_line "$1  (already $NEW — unchanged)"
        else
            _vb_line "$1  (updated)"
        fi
    else
        echo "  version-bump: $1 NOT UPDATED — $4" >&2
        _vb_line "$1  <-- NOT UPDATED: $4 — fix by hand"
        _VB_FAIL=$((_VB_FAIL + 1))
    fi
}

# 1. VERSION file (source of truth)
_vb_step_version() {
    _b=$(_vb_sum VERSION)
    if printf '%s\n' "$NEW" > VERSION && [ "$(tr -d '[:space:]' < VERSION)" = "$NEW" ]; then
        _vb_result VERSION "$_b" 1
    else
        _vb_result VERSION "$_b" 0 "could not write $NEW into it"
    fi
}

# 2. (retired v6.5.4) install.sh no longer carries a hardcoded fallback version.
# It reads the VERSION file or resolves the latest tag, so there is no constant to rewrite.
# The old `s/VERSION="$OLD"/VERSION="$NEW"/` matched nothing for an unknown number of
# releases while the summary still printed "scripts/install.sh" under "Updated:" — a step
# that silently does nothing and then reports success is worse than no step.

# 3. CLAUDE.md's `- **Version**:` line. Anchored to the whole line (`6.6.7` must not match
# `6.6.70`), OLD's dots escaped, and verified: the NEW line present, no OLD line left.
_vb_step_claude() {
    _f=CLAUDE.md
    if [ ! -f "$_f" ]; then _vb_result "$_f" missing 0 "the file is missing"; return 0; fi
    _b=$(_vb_sum "$_f")
    sed -E -i "s/^- \*\*Version\*\*: ${OLD_RE}([[:space:]]*)\$/- **Version**: ${NEW}\1/" "$_f" 2>/dev/null || true
    if grep -qE "^- \*\*Version\*\*: ${NEW_RE}[[:space:]]*\$" "$_f" \
       && ! grep -qE "^- \*\*Version\*\*: ${OLD_RE}[[:space:]]*\$" "$_f"; then
        _vb_result "$_f" "$_b" 1
    else
        _vb_result "$_f" "$_b" 0 "no line reading exactly \`- **Version**: $OLD\` was rewritten"
    fi
}

# 3b. cyrius.cyml's OWN [package].cyrius pin (added v6.6.3).
#
# This file was never maintained here and drifted: at the 6.6.3 cut it still read 6.6.1
# while VERSION was 6.6.2, so every `cyrius` invocation in this repo warned of toolchain
# drift and tests/gates/frontend/pkgver_visible_in_includes.sh (which asserts on exact
# diagnostic output) FAILED. It is the repo's own self-pin, not a dependency version.
_vb_step_cyml() {
    _f=cyrius.cyml
    if [ ! -f "$_f" ]; then _vb_result "$_f" missing 0 "the file is missing"; return 0; fi
    _b=$(_vb_sum "$_f")
    sed -E -i "s/^cyrius = \"${OLD_RE}\"/cyrius = \"${NEW}\"/" "$_f" 2>/dev/null || true
    if grep -qE "^cyrius = \"${NEW_RE}\"" "$_f" && ! grep -qE "^cyrius = \"${OLD_RE}\"" "$_f"; then
        _vb_result "$_f" "$_b" 1
    else
        _vb_result "$_f" "$_b" 0 "its self-pin is not \`cyrius = \"$NEW\"\` (expected to rewrite \`cyrius = \"$OLD\"\`)"
    fi
}

# 4. CHANGELOG.md — the `## [NEW]` section header.
#
# v5.8.49: anchored at the start of the line — the loose pattern matched narrative body text
# quoting `## [Unreleased]` and inserted 3 spurious headers. v6.5.28: the in-flight header is
# `## [Unreleased] — \`.NN\` in flight`, which an exact `^...$` anchor never matched, so the
# block was a silent no-op for every release that used the suffix. Now: RENAME the in-flight
# header in place when one exists (that is what a cut means), else insert a fresh section
# before the newest version header (`0,/re/` bounds both to the FIRST match — `1,/^$/a`
# double-inserted). Verified: exactly ONE `## [NEW]` header afterwards.
_vb_step_changelog() {
    _f=CHANGELOG.md
    if [ ! -f "$_f" ]; then _vb_result "$_f" missing 0 "the file is missing"; return 0; fi
    _b=$(_vb_sum "$_f")
    if ! grep -qE "^## \[${NEW_RE}\]" "$_f"; then
        if grep -qE "^## \[Unreleased\]" "$_f"; then
            sed -i "0,/^## \[Unreleased\].*$/s||## [$NEW] — $TODAY|" "$_f" 2>/dev/null || true
        else
            sed -i "0,/^## \[[0-9]/s||## [$NEW] — $TODAY\n\n&|" "$_f" 2>/dev/null || true
        fi
    fi
    _n=$(grep -cE "^## \[${NEW_RE}\]" "$_f" || true)
    if [ "$_n" = "1" ]; then
        _vb_result "$_f" "$_b" 1
    else
        _vb_result "$_f" "$_b" 0 "it has $_n \`## [$NEW]\` section headers, not 1 (no \`## [Unreleased]\` or \`## [<version>]\` header to anchor on?)"
    fi
}

# 5. Roadmap `Current head:` stamp — the anchor `_doc_stamp_currency_gate` keys on.
#
# The live stamp is `**Current head: vX.Y.Z** (<parenthetical>) — <figures>`, and people
# ANNOTATE the parenthetical by hand: at 6.6.6 it read `(2026-09-20, bump commit; tag
# pending)`. The pattern used to admit only a date (`([0-9-]*)`, basic regex) with OLD's dots
# unescaped, so it matched nothing, exited 0, and the stamp was hand-fixed after the 6.6.7
# bump. Now any parenthetical is replaced (it describes the previous head) — but only one
# with NO nested parentheses: `[^()]*` refuses `(… (x) …)` rather than cutting it at the
# first `)` and leaving the tail behind as garbage. Only a stamp at the START of its line is
# rewritten; the verification is file-wide — exactly one NEW stamp, and no OLD stamp left
# anywhere, so a mid-line quote of the old stamp is left untouched and reported.
# tests/gates/toolchain/version_bump_doc_anchors.sh runs this over copies of the LIVE docs,
# so an unrewritable stamp goes red when it is written, not at the bump. CHANGELOG [6.6.7]
_vb_step_roadmap() {
    _f=docs/development/roadmap.md
    if [ ! -f "$_f" ]; then _vb_result "$_f" missing 0 "the file is missing"; return 0; fi
    _b=$(_vb_sum "$_f")
    sed -E -i "s/^\*\*Current head: v${OLD_RE}\*\*[[:space:]]*\([^()]*\)/**Current head: v${NEW}** (${TODAY})/" "$_f" 2>/dev/null || true
    _n=$(grep -cE "^\*\*Current head: v${NEW_RE}\*\* \([^()]*\)" "$_f" || true)
    if grep -qE "\*\*Current head: v${OLD_RE}\*\*" "$_f"; then
        _vb_result "$_f" "$_b" 0 "a \`**Current head: v$OLD**\` stamp is still present — one that is not at the start of its line, or not followed by a \`(...)\` with no nested parentheses — so it was not rewritten (doc-stamp gate will be RED)"
    elif [ "$_n" = "1" ]; then
        _vb_result "$_f" "$_b" 1
    else
        _vb_result "$_f" "$_b" 0 "found $_n \`**Current head: v$NEW** (...)\` stamps, not 1, and no \`**Current head: v$OLD**\` stamp to rewrite (doc-stamp gate will be RED)"
    fi
}

# v6.5.3 — the same-version path must NOT exit here.
#
# It used to `exit 0` right after regenerating src/version_str.cyr, so every binary built from
# it — the seven src/main*.cyr forks and the cbt/cyrius.cyr CLI wrapper — kept a stale version
# string (at 6.5.2 the wrapper's own drift detector fired on drift this script caused). Only
# the steps that genuinely require a version CHANGE are skipped (the VERSION file and the
# document anchors); everything from the force-rebuild onward runs for both paths, because
# "regenerate the version string" without "rebuild its consumers" is not a meaningful
# operation.
if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD — regenerating src/version_str.cyr and REBUILDING its consumers"
    _VB_DOCS="
  (SKIPPED — same-version path: VERSION, CLAUDE.md, cyrius.cyml, CHANGELOG.md and
   docs/development/roadmap.md are left as they are)"
else
    _vb_step_version
    _vb_step_claude
    _vb_step_cyml
    _vb_step_changelog
    _vb_step_roadmap
fi

if [ "$DOCS_ONLY" = "1" ]; then
    echo "$OLD -> $NEW (--docs-only, in $(pwd))"
    echo ""
    echo "Document anchors:$_VB_DOCS"
    if [ "$_VB_FAIL" -gt 0 ]; then
        echo "" >&2
        echo "version-bump: $_VB_FAIL document step(s) did NOT take effect (named above)" >&2
        exit 1
    fi
    exit 0
fi

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
_VB_CYCC="build/cycc  (NOT rebuilt — there is no executable build/cycc)"
if [ -x build/cycc ]; then
    # v6.6.6: CHECKED private temps, not /tmp/cycc-rebuild.err + /tmp/_vb_seed.out — fixed names
    # in a world-writable directory, carrying the diagnostics that decide whether a release is
    # tagged. CHANGELOG [6.6.6]
    _vb_d=$(mktemp -d) && [ -d "$_vb_d" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
    trap 'rm -rf "$_vb_d"' EXIT
    if cat src/main.cyr | ./build/cycc > build/cycc.new 2>"$_vb_d/cycc-rebuild.err"; then
        mv build/cycc.new build/cycc
        chmod +x build/cycc
        echo "  > cycc rebuilt for $NEW"
        _VB_CYCC="build/cycc  (rebuilt for $NEW)"
    else
        _VB_CYCC="build/cycc  (NOT rebuilt — the rebuild failed, see above; it still reports the old version)"
        echo "  ! cycc rebuild failed (non-fatal):" >&2
        sed 's/^/    /' "$_vb_d/cycc-rebuild.err" >&2
        rm -f build/cycc.new
    fi
    rm -f "$_vb_d/cycc-rebuild.err"
fi

# 6. Install-snapshot refresh (v5.4.18): reconcile
# ~/.cyrius/versions/$NEW/ with the current repo so a dep bump or
# new tool appears immediately — no waiting for the next full install.
# install.sh --refresh-only skips tarball fetch / bootstrap and just
# re-copies build/ + scripts/ named in cyrius.cyml [release] + lib/.
# Skipped silently if install.sh is missing (shouldn't happen in a
# normal cyrius checkout).
_SNAP_RESULT="(install snapshot NOT refreshed — scripts/install.sh is missing or not executable)"
if [ -x scripts/install.sh ]; then
    # v6.5.3: do NOT swallow stderr. This suppression is why an ETXTBSY `cp` failure
    # that stranded all 17 installed binaries went unseen across multiple releases.
    # v6.6.4: CAPTURE the result. install.sh now REFUSES to write a released version's
    # slot from a drifted tree (the same-version regenerate path at a tagged VERSION is
    # exactly that shape), and the summary below used to print "refreshed" regardless.
    if sh scripts/install.sh --refresh-only; then
        _SNAP_RESULT="(install snapshot refreshed)"
    else
        _SNAP_RESULT="(install snapshot NOT refreshed — see the refusal/error above; a released slot is only rewritten from its tag)"
        echo "  warning: install-snapshot refresh did not run (see above)" >&2
    fi
fi

# 6b. SEED-DERIVE GATE (v6.3.0 lesson — never tag a broken seed). The cycc
# self-host fixpoint does NOT cover the seed -> cybs -> cycc chain: cybs (the
# hand-assembly bootstrap compiler) is far more limited than build/cycc and fails
# SILENTLY on things build/cycc compiles fine. version-bump runs at EVERY slot, so
# wiring the critical gate here makes it impossible to miss. Verifies the
# just-rebuilt build/cycc is still machine-derivable from the 29KB seed. Set
# CYRIUS_SKIP_SEED_GATE=1 only for a KNOWN doc/lib-only bump (src/ untouched).
# See: scripts/release-gate.sh, feedback_seed_derive_mandatory_cybs_limits.
_VB_SEED="seed-derive  (NOT run — scripts/seed-derive-cycc.sh is missing)"
[ "${CYRIUS_SKIP_SEED_GATE:-0}" = "1" ] && _VB_SEED="seed-derive  (SKIPPED — CYRIUS_SKIP_SEED_GATE=1)"
if [ "${CYRIUS_SKIP_SEED_GATE:-0}" != "1" ] && [ -x scripts/seed-derive-cycc.sh -o -f scripts/seed-derive-cycc.sh ]; then
    echo "  > seed-derive gate (seed -> cybs -> cycc)..."
    if [ -z "${_vb_d:-}" ]; then
        _vb_d=$(mktemp -d) && [ -d "$_vb_d" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
        trap 'rm -rf "$_vb_d"' EXIT
    fi
    if sh scripts/seed-derive-cycc.sh > "$_vb_d/seed.out" 2>&1 && grep -q "machine-derivable from the" "$_vb_d/seed.out"; then
        echo "  > seed-derive OK (build/cycc is machine-derivable from the seed)"
        _VB_SEED="seed-derive  (OK — build/cycc is machine-derivable from the seed)"
    else
        tail -6 "$_vb_d/seed.out" >&2
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
echo "Document anchors:$_VB_DOCS"
echo ""
echo "Build + install:"
[ -f src/main.cyr ] && echo "  src/version_str.cyr  (regenerated for $NEW)"
echo "  $_VB_CYCC"
echo "  ~/.cyrius/versions/$NEW/ $_SNAP_RESULT"
echo "  $_VB_SEED"
echo ""
echo "Still manual (version-bump does not touch these):"
echo "  - CHANGELOG.md entries under ## [$NEW] (Fixed / Changed / Added)"
echo "  - docs/development/state.md: the Version row, and the \`| **cycc** |\` row's byte count"
echo "    (the check driver's doc-stamp row compares it with build/cycc)"
echo "  - docs/development/roadmap.md: the figures beside the \`Current head:\` stamp (sizes,"
echo "    counts, bench) — re-derive them; only the version token and date were rewritten"
echo "  - vidya version references (vidya/content/cyrius/language/, types.cyml)"

# The END: a document step that did not take effect fails the bump — AFTER the rebuild and
# the seed gate have run, so one hand-fixable anchor does not strand a half-built tree.
if [ "$_VB_FAIL" -gt 0 ]; then
    echo "" >&2
    echo "version-bump: $_VB_FAIL document step(s) did NOT take effect (named above) — fix them by hand before tagging $NEW" >&2
    exit 1
fi
