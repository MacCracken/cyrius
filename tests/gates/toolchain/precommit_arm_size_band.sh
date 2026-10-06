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

echo "PASS precommit_arm_size_band (build/cycc-native-aarch64: 1,323,072 B folded accepted; 2,042,184 B un-folded, 600,000 B and an x86_64 e_machine refused — band 700K–2M)"
