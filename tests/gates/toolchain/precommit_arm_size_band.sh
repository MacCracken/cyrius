#!/bin/sh
# precommit_arm_size_band.sh — 6.6.18 (XLAT-4): the pre-commit hook's build/cycc-native-aarch64
# size band is 700K–2M again, so an UN-folded ARM compiler is refused.
#
# 6.6.17 raised the band to 3M because ESYSXLAT inlined its whole translation chain at every
# aarch64 syscall site (2,042,184 B). The 6.6.18 fold (esysxlat_fold.sh) put the binary at
# ~1.32 MB, below x86 cycc, and the band came back to build/cycc's 2M — which also makes the
# hook a backstop for a LOST fold: a pre-fold build no longer fits.
#
# Runs a COPY of scripts/hooks/pre-commit inside a throwaway `git init` under mktemp, against a
# fabricated build/cycc-native-aarch64 (ELF magic + e_machine at offset 18, zero-padded to the
# size under test) staged in that repo. Nothing in the tree or its .git is touched — the
# installed .git/hooks/pre-commit is a shared copy that only install.sh / check.sh reinstall.
#   row 1  2,042,184 B aarch64 (the 6.6.17 un-folded size) — REFUSED  (the old 3M band accepted it)
#   row 2  1,323,072 B aarch64 (6.6.18 folded)             — accepted (anti-vacuous: the hook passes)
#   row 3    600,000 B aarch64                             — REFUSED  (lower bound kept)
#   row 4  1,323,072 B x86_64 e_machine                    — REFUSED  (architecture check kept)
# 6.6.20 (RS-05) — the hook judges the STAGED BLOB, not the working-tree file. It read "$bin"
# from the working tree, so a contaminated blob committed whenever the working copy was good.
# Rows on build/cycc (a fabricated 1,300,000 B x86_64 ELF is "good", 24 bytes of `MZ…` "bad"):
#   row 5  staged bad,  working copy good    — REFUSED  (was accepted: the hook read the good file)
#   row 6  staged good, working copy bad     — accepted (anti-vacuous: the index is what is judged)
#   row 7  staged bad,  working copy deleted — REFUSED  (was skipped: `[ -e "$bin" ] || continue`)
# Mutations (measured, 6.6.20): the hook as of 6.6.19 → rows 5 6 7 each red; the old
# `[ -e "$bin" ] || continue` skip put back in front of the index read → row 7 red.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
HOOK="$ROOT/scripts/hooks/pre-commit"
[ -f "$HOOK" ] || { echo "FAIL precommit_arm_size_band: $HOOK missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP precommit_arm_size_band: git absent"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL precommit_arm_size_band: mktemp -d"; exit 1; }
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL precommit_arm_size_band: $1" >&2; exit 1; }

R="$T/repo"
mkdir -p "$R/build"
git -C "$R" init -q
cp "$HOOK" "$T/pre-commit"

# $1 = size, $2 = e_machine byte 18 (octal escape); prints the hook's exit code
_row() {
    rm -f "$R/build/cycc-native-aarch64"
    head -c "$1" /dev/zero > "$R/build/cycc-native-aarch64"
    printf '\177ELF' | dd of="$R/build/cycc-native-aarch64" conv=notrunc 2>/dev/null
    printf "$2" | dd of="$R/build/cycc-native-aarch64" bs=1 seek=18 conv=notrunc 2>/dev/null
    git -C "$R" add build/cycc-native-aarch64
    rc=0; (cd "$R" && sh "$T/pre-commit" > "$T/out" 2>&1) || rc=$?
    git -C "$R" rm -q --cached build/cycc-native-aarch64
    echo "$rc"
}

[ "$(_row 1323072 '\267')" = 0 ] || fail "a folded 1,323,072 B aarch64 build is refused — the hook (or this harness) is broken: $(cat "$T/out")"
[ "$(_row 2042184 '\267')" != 0 ] || fail "an UN-folded 2,042,184 B aarch64 build is accepted — the band is still above 2M"
grep -q '700K–2M' "$T/out" || fail "the refusal does not name the 700K–2M band: $(cat "$T/out")"
[ "$(_row 600000 '\267')" != 0 ] || fail "a 600,000 B aarch64 build is accepted — the lower bound is gone"
[ "$(_row 1323072 '\076')" != 0 ] || fail "an x86_64 e_machine in the aarch64 slot is accepted — the architecture check is gone"

# ── rows 5-7: the staged blob, not the working-tree file ──────────────────────────────────
_mk_elf() {  # _mk_elf <path> <size> <e_machine byte 18, octal escape>
    rm -f "$1"; head -c "$2" /dev/zero > "$1"
    printf '\177ELF' | dd of="$1" conv=notrunc 2>/dev/null
    printf "$3" | dd of="$1" bs=1 seek=18 conv=notrunc 2>/dev/null
}
_put() {  # _put <good|bad|gone> → build/cycc in the working tree
    case "$1" in
        good) _mk_elf "$R/build/cycc" 1300000 '\076' ;;
        bad)  rm -f "$R/build/cycc"; printf 'MZ not an elf, truncated' > "$R/build/cycc" ;;
        gone) rm -f "$R/build/cycc" ;;
    esac
}
# $1 = what is staged, $2 = what the working tree holds at commit time; prints the hook's rc
_index_row() {
    _put "$1"; git -C "$R" add build/cycc; _put "$2"
    rc=0; (cd "$R" && sh "$T/pre-commit" > "$T/out" 2>&1) || rc=$?
    git -C "$R" rm -q -f --cached build/cycc; rm -f "$R/build/cycc"
    echo "$rc"
}
# a row whose harness died prints NOTHING — never read an empty rc as "refused"
_refused() { [ -n "$1" ] && [ "$1" != 0 ]; }
r=$(_index_row bad good); _refused "$r" || fail "row 5: a STAGED 24-byte MZ blob commits because the working-tree build/cycc is a good ELF — the hook reads the working tree, not the index"
grep -q 'build/cycc is not an ELF' "$T/out" || fail "row 5: the refusal does not name the staged blob's magic: $(cat "$T/out")"
r=$(_index_row good bad); [ "$r" = 0 ] || fail "row 6: a GOOD staged build/cycc is refused because the working copy is bad — the hook judges the working tree: $(cat "$T/out")"
r=$(_index_row bad gone); _refused "$r" || fail "row 7: a staged MZ blob commits when the working-tree build/cycc is deleted — a staged artifact is skipped unjudged"

echo "PASS precommit_arm_size_band (build/cycc-native-aarch64: 1,323,072 B folded accepted; 2,042,184 B un-folded, 600,000 B and an x86_64 e_machine refused — band 700K–2M; build/cycc judged from the INDEX: staged-bad refused with the working copy good or deleted, staged-good accepted with it bad)"
