#!/bin/sh
# scripts/verify-store.sh — does every RELEASED slot of the install store equal its tag?
#
# v6.6.4. `~/.cyrius/versions/<v>` is what a consumer pin MEANS. Four writers keyed that
# slot on the working-tree VERSION with no notion of "released" (install.sh --refresh-only,
# `cyrius pulsar`, `cyrius lsp`, and the CLAUDE.md hand-copy recipe), so a slot could go
# stale in BOTH directions and nothing would notice:
#   - in-progress content under a released name (the installed "6.6.2" stdlib was 6.6.3's,
#     byte for byte; "6.6.1" carried three 6.6.2 files);
#   - pre-fix content under a re-cut tag (the "6.6.3" cross-compilers were built from the
#     bump commit — the tag's direct parent — and carried the very defect the tag fixed).
# `deps --verify` cannot see either: it trusts the slot. This script trusts the TAG.
#
# For each versions/<v> whose tag exists in this repo:
#   lib/    every file compared byte-for-byte against `git show <v>:lib/<rel>`, both ways
#   bin/    the TRACKED binaries (build/cycc, build/cycc-native-aarch64 when tracked at <v>)
#           compared against the tag; untracked cross-bins are judged by SOURCE_COMMIT
#   SOURCE_COMMIT   (written by install.sh since 6.6.4) must be the tag's commit and clean
# Untagged slots (an in-flight bump) are reported, not judged.
#
#   sh scripts/verify-store.sh                 # report; exit 1 on any mismatch
#   sh scripts/verify-store.sh --restore 6.6.2 # rewrite lib/ + tracked bins of that slot
#                                               #   from the tag, and rebuild its cross-bins
#                                               #   from the tag's sources with the tag's cycc
# CYRIUS_HOME overrides the store (default $HOME/.cyrius). --restore never touches a slot
# whose tag does not exist, and prints every file it changes.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
STORE="${CYRIUS_HOME:-$HOME/.cyrius}"
MODE=report; RESTORE_V=""
[ "${1:-}" = "--restore" ] && { MODE=restore; RESTORE_V="${2:-}"; [ -n "$RESTORE_V" ] || { echo "usage: $0 --restore <version>" >&2; exit 2; }; }
command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 2; }
[ -d "$STORE/versions" ] || { echo "error: no store at $STORE" >&2; exit 2; }

bad=0; slots=0; judged=0

# tracked bins per tag: whatever build/* the tag tracks, minus nothing (all are executables)
_tag_tracked_bins() { git ls-tree --name-only "refs/tags/$1" build/ 2>/dev/null | sed 's|^build/||'; }
_cross_bins() { awk '/^\[release\]/{f=1;next} /^\[/{f=0} f && /^cross_bins/ {gsub(/.*=|\[|\]|"|,/," "); print}' cyrius.cyml; }

verify_slot() {   # $1 = version
    v=$1; slot="$STORE/versions/$v"; slots=$((slots+1))
    if ! git rev-parse -q --verify "refs/tags/$v" >/dev/null 2>&1; then
        printf '  %-8s untagged (in flight) — not judged\n' "$v"; return 0
    fi
    judged=$((judged+1)); n_lib=0; n_bad=0; n_missing=0; n_extra=0; n_bin_bad=0
    # lib: every file at the tag must be in the slot and identical; every slot file must be at the tag
    for rel in $(git ls-tree -r --name-only "refs/tags/$v" lib/ 2>/dev/null | grep '\.cyr$'); do
        n_lib=$((n_lib+1)); f="$slot/${rel}"
        if [ ! -f "$f" ]; then n_missing=$((n_missing+1)); [ "$MODE" = report ] && printf '    MISSING   %s\n' "$rel"; continue; fi
        if ! git show "refs/tags/$v:$rel" | cmp -s - "$f"; then n_bad=$((n_bad+1)); [ "$MODE" = report ] && printf '    DIFFERS   %s\n' "$rel"; fi
    done
    for f in $(find "$slot/lib" -type f -name '*.cyr' 2>/dev/null); do
        rel="lib/${f#$slot/lib/}"
        git cat-file -e "refs/tags/$v:$rel" 2>/dev/null || { n_extra=$((n_extra+1)); [ "$MODE" = report ] && printf '    NOT-AT-TAG %s\n' "$rel"; }
    done
    # tracked bins
    for b in $(_tag_tracked_bins "$v"); do
        [ -f "$slot/bin/$b" ] || continue
        if ! git show "refs/tags/$v:build/$b" | cmp -s - "$slot/bin/$b"; then n_bin_bad=$((n_bin_bad+1)); [ "$MODE" = report ] && printf '    DIFFERS   bin/%s (tracked at the tag)\n' "$b"; fi
    done
    # provenance stamp. The slot is the release when its inputs equal the tag's — the stamp's
    # `tree-matches-tag: yes` says exactly that even when the writing COMMIT is not the tag's
    # (version-bump writes at the pre-bump HEAD; the tag lands later; a post-tag reconcile
    # may run with a docs file edited). Only a stamp that says the inputs had DRIFTED
    # (tree-matches-tag: no, or a dirty guarded tree) marks a content-identical slot suspect
    # — that is the shape the untracked cross-bins can hide behind.
    stamp="?"; tagc="$(git rev-list -n1 "refs/tags/$v" 2>/dev/null)"; stamp_bad=0
    if [ -f "$slot/SOURCE_COMMIT" ]; then
        sc="$(head -1 "$slot/SOURCE_COMMIT")"; tm="$(sed -n 's/^tree-matches-tag: //p' "$slot/SOURCE_COMMIT")"
        case "$sc" in
            "$tagc")       stamp="tag-commit" ;;
            "$tagc dirty") stamp="tag-commit+DIRTY-inputs"; stamp_bad=1 ;;
            *)             stamp="commit ${sc%% *}"; [ "$tm" = "yes" ] && stamp="$stamp (inputs == tag)" || { stamp="$stamp (inputs DRIFTED)"; stamp_bad=1; } ;;
        esac
    else
        stamp="no-stamp(pre-6.6.4: cross-bins unverifiable)"
    fi
    cross_note=""
    for cb in $(_cross_bins); do
        [ -f "$slot/bin/$cb" ] || continue
        git cat-file -e "refs/tags/$v:build/$cb" 2>/dev/null && continue   # tracked at the tag: verified above
        cross_note="$cross_note $cb"
    done
    total_bad=$((n_bad+n_missing+n_extra+n_bin_bad+stamp_bad))
    if [ "$total_bad" -eq 0 ]; then
        printf '  %-8s OK   lib %d/%d · tracked bins ok · stamp %s' "$v" "$n_lib" "$n_lib" "$stamp"
    else
        printf '  %-8s BAD  lib differs %d, missing %d, not-at-tag %d · tracked bins differ %d · stamp %s' "$v" "$n_bad" "$n_missing" "$n_extra" "$n_bin_bad" "$stamp"
        bad=$((bad+1))
    fi
    [ -n "$cross_note" ] && printf ' · untracked cross-bins (%s) judged by the stamp only' "$cross_note"
    printf '\n'
    return 0
}

restore_slot() {   # $1 = version
    v=$1; slot="$STORE/versions/$v"
    git rev-parse -q --verify "refs/tags/$v" >/dev/null 2>&1 || { echo "error: no tag $v — refusing to restore" >&2; exit 2; }
    [ -d "$slot" ] || { echo "error: no slot $slot" >&2; exit 2; }
    echo "restoring $slot from tag $v"
    changed=0
    for rel in $(git ls-tree -r --name-only "refs/tags/$v" lib/ 2>/dev/null | grep '\.cyr$'); do
        f="$slot/$rel"; mkdir -p "$(dirname "$f")"
        if [ ! -f "$f" ] || ! git show "refs/tags/$v:$rel" | cmp -s - "$f"; then
            git show "refs/tags/$v:$rel" > "$f.new" && mv -f "$f.new" "$f"; echo "  restored $rel"; changed=$((changed+1))
        fi
    done
    for f in $(find "$slot/lib" -type f -name '*.cyr' 2>/dev/null); do
        rel="lib/${f#$slot/lib/}"
        git cat-file -e "refs/tags/$v:$rel" 2>/dev/null || { rm -f "$f"; echo "  removed  $rel (not at the tag)"; changed=$((changed+1)); }
    done
    for b in $(_tag_tracked_bins "$v"); do
        [ -f "$slot/bin/$b" ] || continue
        if ! git show "refs/tags/$v:build/$b" | cmp -s - "$slot/bin/$b"; then
            git show "refs/tags/$v:build/$b" > "$slot/bin/.$b.new" && chmod +x "$slot/bin/.$b.new" && mv -f "$slot/bin/.$b.new" "$slot/bin/$b"
            echo "  restored bin/$b"; changed=$((changed+1))
        fi
    done
    # cross-bins: rebuild from the tag's sources with the tag's OWN cycc, in a temp tree
    # v6.6.6: CHECKED — an empty T makes every "$T/x" below "/x". CHANGELOG [6.6.6]
    T=$(mktemp -d) && [ -d "$T" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
    trap 'rm -rf "$T"' EXIT
    git archive "refs/tags/$v" src lib | tar -x -C "$T"
    git show "refs/tags/$v:build/cycc" > "$T/cycc" && chmod +x "$T/cycc"
    # ⚠ Recipes mirror scripts/install.sh's cross-bin build EXACTLY — cycc_win is the PE32+
    # compiler that runs ON Windows (CYRIUS_TARGET_WIN=1), not an x86 cross compiler; the
    # first cut of this script rebuilt it as an ELF and had to be re-run. cycc-native-aarch64
    # is TRACKED at every tag and is restored by the tracked-bin loop above.
    for cb in $(_cross_bins); do
        [ -f "$slot/bin/$cb" ] || continue
        cenv=""
        case "$cb" in
            cycc_aarch64) srcf=src/main_aarch64.cyr ;;
            cycc_win)     srcf=src/main_win.cyr; cenv="CYRIUS_TARGET_WIN=1" ;;
            cycc_cx)      srcf=src/main_cx.cyr ;;
            cycc-native-aarch64) continue ;;   # tracked at the tag — handled above
            *) echo "  skip bin/$cb (no source mapping — add it here, mirroring scripts/install.sh)"; continue ;;
        esac
        [ -f "$T/$srcf" ] || { echo "  skip bin/$cb ($srcf not at the tag)"; continue; }
        if ( cd "$T" && env $cenv ./cycc < "$srcf" > "$T/$cb" 2>/dev/null ) && [ -s "$T/$cb" ]; then
            if ! cmp -s "$T/$cb" "$slot/bin/$cb"; then
                cp "$T/$cb" "$slot/bin/.$cb.new" && chmod +x "$slot/bin/.$cb.new" && mv -f "$slot/bin/.$cb.new" "$slot/bin/$cb"
                echo "  rebuilt  bin/$cb from the tag's $srcf with the tag's cycc${cenv:+ ($cenv)}"; changed=$((changed+1))
            fi
        else
            echo "  FAIL: could not rebuild $cb from the tag" >&2; bad=$((bad+1))
        fi
    done
    printf '%s\ntree-matches-tag: yes\n' "$(git rev-list -n1 "refs/tags/$v")" > "$slot/SOURCE_COMMIT"
    echo "  stamped SOURCE_COMMIT = tag commit"
    echo "restore $v: $changed file(s) changed"
}

if [ "$MODE" = restore ]; then
    restore_slot "$RESTORE_V"
    echo "--- verify after restore ---"
    verify_slot "$RESTORE_V"
    exit "$bad"
fi

echo "verify-store: $STORE (tags from $ROOT)"
for d in "$STORE"/versions/*; do
    [ -d "$d" ] || continue
    verify_slot "$(basename "$d")"
done
echo "verify-store: $slots slot(s), $judged tagged, $bad BAD"
if [ "$slots" -gt 0 ] && [ "$judged" -eq 0 ]; then
    echo "verify-store: NOTHING was judged — this clone has no tags for any slot (git fetch --tags); a green here is vacuous" >&2
    exit 3
fi
exit "$bad"
