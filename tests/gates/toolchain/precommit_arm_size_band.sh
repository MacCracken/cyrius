#!/bin/sh
# precommit_arm_size_band.sh — the pre-commit hook's build/cycc-native-aarch64 size band refuses an
# UN-folded ARM compiler (the lost-fold backstop) and accepts a folded one at any size the compiler
# legitimately reaches.
#
# 6.6.17 raised the band to 3M because ESYSXLAT inlined its whole translation chain at every
# aarch64 syscall site (2,042,184 B against x86's 1,582,088: 1.29x). The 6.6.18 fold
# (esysxlat_fold.sh) put the binary at ~1.32 MB, below x86 cycc, and the band came back to a fixed
# 2M. 6.7.11: the wave-1 merge grew both compilers past it (x86 2,168,800 B, ARM 2,016,960 B: 0.93x)
# and the fixed 2M refused that good, seed-derived regeneration — so the ceiling is RELATIVE: at
# most 1.10x the build/cycc the commit records (the index's blob), under build/cycc's 700K-3M band;
# with no build/cycc in the index, the old fixed 2M.
#
# Runs a COPY of scripts/hooks/pre-commit inside a throwaway `git init` under mktemp, against a
# fabricated build/cycc-native-aarch64 (ELF magic + e_machine at offset 18, zero-padded to the
# size under test) and, where a row names one, a fabricated x86_64 build/cycc, both staged in that
# repo. Nothing in the tree or its .git is touched — the installed .git/hooks/pre-commit is a shared
# copy that only install.sh / check.sh reinstall.
#   row 1   ARM 2,042,184 B vs x86 1,582,088 B (6.6.17, un-folded, 1.29x) — REFUSED, names 1.10x
#   row 2   ARM 1,323,072 B vs x86 1,582,088 B (6.6.18, folded)          — accepted (anti-vacuous)
#   row 2b  ARM 2,016,960 B vs x86 2,168,800 B (6.7.11, folded)          — accepted (the fixed 2M refused it)
#   row 2c  ARM 2,500,000 B vs x86 2,168,800 B (1.15x)                   — REFUSED
#   row 2d  ARM 3,100,000 B vs x86 2,900,000 B (1.07x, over 3M)          — REFUSED (the absolute ceiling)
#   row 2e  ARM 2,042,184 B, no build/cycc in the index                  — REFUSED (the fixed-2M fallback)
#   row 3     600,000 B aarch64                                          — REFUSED (lower bound kept)
#   row 4   1,323,072 B x86_64 e_machine                                 — REFUSED (architecture check kept)
# Mutations (measured, 6.7.11): the relative arm dropped -> rows 1 2c red; the fixed 2M put back
# -> row 2b red; the fallback arm dropped -> row 2e red.
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

# $1 = size, $2 = e_machine byte 18 (octal escape), $3 = an x86_64 build/cycc staged beside it
# (its size; 0 = none); prints the hook's exit code
_row() {
    rm -f "$R/build/cycc-native-aarch64" "$R/build/cycc"
    head -c "$1" /dev/zero > "$R/build/cycc-native-aarch64"
    printf '\177ELF' | dd of="$R/build/cycc-native-aarch64" conv=notrunc 2>/dev/null
    printf "$2" | dd of="$R/build/cycc-native-aarch64" bs=1 seek=18 conv=notrunc 2>/dev/null
    git -C "$R" add build/cycc-native-aarch64
    if [ "$3" -gt 0 ]; then
        head -c "$3" /dev/zero > "$R/build/cycc"
        printf '\177ELF' | dd of="$R/build/cycc" conv=notrunc 2>/dev/null
        printf '\076' | dd of="$R/build/cycc" bs=1 seek=18 conv=notrunc 2>/dev/null
        git -C "$R" add build/cycc
    fi
    rc=0; (cd "$R" && sh "$T/pre-commit" > "$T/out" 2>&1) || rc=$?
    git -C "$R" rm -q --cached build/cycc-native-aarch64
    if [ "$3" -gt 0 ]; then git -C "$R" rm -q -f --cached build/cycc; fi
    rm -f "$R/build/cycc"
    echo "$rc"
}

[ "$(_row 1323072 '\267' 1582088)" = 0 ] || fail "row 2: a folded 1,323,072 B aarch64 build beside a 1,582,088 B x86 cycc is refused — the hook (or this harness) is broken: $(cat "$T/out")"
[ "$(_row 2016960 '\267' 2168800)" = 0 ] || fail "row 2b: the 6.7.11 folded 2,016,960 B aarch64 build beside a 2,168,800 B x86 cycc is refused — a fixed ceiling is back: $(cat "$T/out")"
[ "$(_row 2042184 '\267' 1582088)" != 0 ] || fail "row 1: the 6.6.17 UN-folded 2,042,184 B aarch64 build (1.29x x86) is accepted — the relative ceiling is gone"
grep -q 'over 1.10x build/cycc' "$T/out" || fail "row 1: the refusal does not name the 1.10x ceiling: $(cat "$T/out")"
[ "$(_row 2500000 '\267' 2168800)" != 0 ] || fail "row 2c: a 2,500,000 B aarch64 build (1.15x x86) is accepted — the relative ceiling is gone"
[ "$(_row 3100000 '\267' 2900000)" != 0 ] || fail "row 2d: a 3,100,000 B aarch64 build is accepted — the absolute 3M ceiling is gone"
[ "$(_row 2042184 '\267' 0)" != 0 ] || fail "row 2e: a 2,042,184 B aarch64 build with no build/cycc in the index is accepted — the fixed-2M fallback is gone"
[ "$(_row 600000 '\267' 1582088)" != 0 ] || fail "row 3: a 600,000 B aarch64 build is accepted — the lower bound is gone"
[ "$(_row 1323072 '\076' 1582088)" != 0 ] || fail "row 4: an x86_64 e_machine in the aarch64 slot is accepted — the architecture check is gone"

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

echo "PASS precommit_arm_size_band (build/cycc-native-aarch64: folded 1,323,072 B / 1,582,088 and 2,016,960 B / 2,168,800 accepted; the un-folded 1.29x, 1.15x, over 3M, 2.04M with no build/cycc, 600,000 B and an x86_64 e_machine refused — at most 1.10x build/cycc under 700K–3M; build/cycc judged from the INDEX: staged-bad refused with the working copy good or deleted, staged-good accepted with it bad)"
