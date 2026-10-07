#!/bin/sh
# FORK SHARED BLOCKS — code every compiler driver needs lives in ONE place.
#
# WHY (6.6.20): each src/main*.cyr fork is a hand copy, and a hand copy drifts — the --syntax-only,
# --pie and _strict_mode findings of the same release were all one fork's copy diverging from the
# others'. Three blocks that had stayed identical only by care now have one copy each:
#   regions — the heap-region bases + caps (`_fixup_base = S + 0x107B000;` … `_codebuf_cap`),
#             45 lines byte-identical in six drivers, now src/common/heap_regions.cyr, included
#             at the same spot (a text splice: every fork's compiler stayed byte-identical).
#             main_cx.cyr keeps its own: cx's codebuf and fixup table are different regions.
#   main    — the `fn main` auto-call lookup. main.cyr and main_win.cyr called
#             `_find_fn_by_name(S, "main", 4)`; main_aarch64, _macho, _native and main_x86_macho
#             open-coded the same five-deep byte compare.
#   cmdline — main_cx.cyr's Linux and agnos arms carried two verbatim /proc/self/cmdline scans;
#             one helper (_cx_cmdline_flags) now serves both.
# Plus a runtime row, because the lookup swap changes code: on the aarch64 cross and, under
# qemu-aarch64, the aarch64 and native compilers, a program whose `fn main` follows a
# `fn mainframe` exits with main's 42, and one with only `fn mai` exits with its last value.
#
# MUTATION LEDGER (6.6.20, scratch copies of src/, never the repo):
#   real tree                                                     -> GREEN
#   main_win.cyr's include replaced by the 45-line block inline   -> RED "regions: src/main_win.cyr assigns"
#   main_aarch64.cyr restored to its pre-6.6.20 copy             -> RED "main: src/main_aarch64.cyr open-codes"
#                                                                    + "only 5 drivers look `main` up" + regions
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: fork_shared_blocks_single_copy: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: fork_shared_blocks_single_copy: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: fork_shared_blocks_single_copy: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0
fail=0; rows=0
bad() { echo "  FAIL: fork_shared_blocks_single_copy $1"; fail=$((fail + 1)); }
code() { sed 's/#.*//' "$1"; }   # comment-stripped (an `include "…"` line has no `#` in it)

H=src/common/heap_regions.cyr
rows=$((rows + 1))
if [ ! -f "$H" ] || ! code "$H" | grep -q '^_fixup_base = S + 0x107B000;' || ! code "$H" | grep -q '^_codebuf_cap = 8388608;'; then
    bad "regions: $H is missing or no longer holds the region block"
fi

n=0; nmain=0
for f in src/main*.cyr; do
    [ "$f" = src/main_cx.cyr ] && continue
    n=$((n + 1)); rows=$((rows + 2))
    inc=$(code "$f" | grep -c '^include "src/common/heap_regions.cyr"' || true)
    [ "$inc" = 1 ] || bad "regions: $f includes $H $inc time(s) (want 1)"
    if code "$f" | grep -qE '^(_fixup_base = S \+ 0x107B000|_fnt_names = S \+|_codebuf_cap = 8388608|_var_cap = 8192);'; then
        bad "regions: $f assigns the region bases itself again — they live in $H"
    fi
    if code "$f" | grep -q '0xEC00000 + _main_noff'; then
        bad "main: $f open-codes the \`main\` lookup — call _find_fn_by_name(S, \"main\", 4)"
    fi
    code "$f" | grep -q '_find_fn_by_name(S, "main", 4)' && nmain=$((nmain + 1))
done
# Floors: the drivers that existed when this landed. A glob that broke must not score green.
rows=$((rows + 1))
[ "$n" -ge 6 ] || bad "regions: only $n non-cx src/main*.cyr drivers found (floor 6)"
[ "$nmain" -ge 6 ] || bad "main: only $nmain drivers look \`main\` up through _find_fn_by_name (floor 6)"

rows=$((rows + 1))
c=$(code src/main_cx.cyr | grep -c '"/proc/self/cmdline"' || true)
[ "$c" = 1 ] || bad "cmdline: src/main_cx.cyr opens /proc/self/cmdline at $c site(s) (want 1, _cx_cmdline_flags)"

# ── runtime: the auto-call still finds exactly `main` ───────────────────────────────────
printf 'fn mainframe(): i64 { return 7; }\nfn main(): i64 { return 42; }\n' > "$T/mm.cyr"
printf 'fn mai(): i64 { return 7; }\nvar x = 3;\n' > "$T/nm.cyr"
if ! cat src/main_aarch64.cyr | "$CC" > "$T/a64x" 2> "$T/b.err"; then
    echo "FAIL: fork_shared_blocks_single_copy: building the aarch64 cross failed"; exit 1
fi
chmod +x "$T/a64x"
AF="a64_cross|$T/a64x"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    cat src/main_aarch64.cyr | "$T/a64x" > "$T/a64" 2>/dev/null && chmod +x "$T/a64" \
        && cat src/main_aarch64_native.cyr | "$T/a64x" > "$T/a64n" 2>/dev/null && chmod +x "$T/a64n" \
        || { echo "FAIL: fork_shared_blocks_single_copy: building the aarch64 compilers failed"; exit 1; }
    AF="$AF
aarch64_qemu|qemu-aarch64 $T/a64
native_qemu|qemu-aarch64 $T/a64n"
    printf '%s\n' "$AF" | while IFS='|' read -r l c; do
        r1=x; r2=x
        $c < "$T/mm.cyr" > "$T/mm" 2>/dev/null && chmod +x "$T/mm" && { r1=0; qemu-aarch64 "$T/mm" || r1=$?; }
        $c < "$T/nm.cyr" > "$T/nm" 2>/dev/null && chmod +x "$T/nm" && { r2=0; qemu-aarch64 "$T/nm" || r2=$?; }
        [ "$r1" = 42 ] || { echo "  FAIL: fork_shared_blocks_single_copy main $l: fn main after fn mainframe exited $r1 (want 42)"; echo x >> "$T/red"; }
        [ "$r2" = 3 ]  || { echo "  FAIL: fork_shared_blocks_single_copy main $l: no fn main (only fn mai) exited $r2 (want 3)"; echo x >> "$T/red"; }
        echo x >> "$T/nrows"; echo x >> "$T/nrows"
    done
    [ -f "$T/nrows" ] && rows=$((rows + $(wc -l < "$T/nrows")))
    [ -f "$T/red" ] && fail=$((fail + $(wc -l < "$T/red")))
else
    echo "  SKIP (named): runtime main rows — qemu-aarch64 is not installed"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL fork_shared_blocks_single_copy: $fail of $rows row(s) red"; exit 1; fi
echo "PASS fork_shared_blocks_single_copy: $rows rows — one heap-region block ($n drivers), one \`main\` lookup ($nmain drivers), one cx cmdline scan; aarch64 auto-call finds exactly \`main\`"
exit 0
