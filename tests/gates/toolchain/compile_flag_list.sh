#!/bin/sh
# compile_flag_list.sh — 6.6.20 (REFACTOR-10 / CBTB-10). compile() hands the compiler its flags
# from ONE list, `_cc_flags` (cbt/build.cyr): the POSIX argv is built from it and SIZED from it
# (`_run_argv`), and the PE command line joins it (`_cc_flags_cmdline`).
#
# WHY: there were two hand-kept copies of the list, and the POSIX one sat in a fixed
# `var argv[32]` — four 8-byte slots — while v6.5.19's `--syntax-only` made five writers
# possible (cc + --strict + --allow-undef + --syntax-only + NUL): the NUL would land one slot
# past the array, on whatever local the frame put there. The comment above it still counted
# four. No verb sets all three flags today (`--strict` is build's, the other two belong to
# lint's pre-pass), so the overflow was latent — which is why nothing noticed, and why axis 1
# drives the combination directly instead of waiting for a verb to reach it.
#
#   axis 1  the REAL helpers, extracted from cbt/build.cyr, for all 8 combinations of the
#           three flags: the argv is [cc, flags in order, NUL] in an allocation that covers
#           every slot it writes, and the PE command line is the same tokens.
#   axis 2  derived: compile() builds no fixed-size argv, and neither compile() nor the PE
#           arm spells a flag literal of its own — a second list cannot come back unseen.
#   axis 3  ⭐ anti-vacuous: an extracted `_run_argv` that under-allocates by one slot (the
#           old shape) is caught by axis 1's sizing check.
# The flags actually reaching the compiler through the verbs are pinned elsewhere:
# build_config_precedence.sh (`--strict` on POSIX) and build_config_windows_arm.sh (all three
# on the PE arm, under wine).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compile_flag_list: no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: compile_flag_list: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

# ── axis 1 — the real helpers, every combination ─────────────────────────────────────────
for f in _cc_flags _cc_flags_cmdline _run_argv; do
    awk -v f="$f" '$0 ~ "^fn " f "\\(" { on = 1 } on { print } on && /^}/ { exit }' cbt/build.cyr > "$T/$f.cyr"
    [ -s "$T/$f.cyr" ] || fail "axis 1: fn $f was not found in cbt/build.cyr"
done
mk_probe() {   # $1 = the _run_argv source to use, $2 = output .cyr
    {
        echo 'include "lib/syscalls.cyr"'
        echo 'include "lib/string.cyr"'
        echo 'include "lib/alloc.cyr"'
        echo 'include "lib/fmt.cyr"'
        echo 'include "lib/vec.cyr"'
        echo 'include "lib/str.cyr"'
        echo 'var _strict = 0;'
        echo 'var _cc_allow_undef = 0;'
        echo 'var _cc_syntax_only = 0;'
        cat "$T/_cc_flags.cyr" "$T/_cc_flags_cmdline.cyr" "$1"
        cat <<'EOF'
fn put(s): i64 { sys_write(1, s, strlen(s)); return 0; }
# One line per combination: the argv tokens after cc, "|", the PE command line, "|", the size
# verdict ("fits" when the allocation covers cc + every flag + the NUL).
fn row(a, b, c): i64 {
    _strict = a; _cc_allow_undef = b; _cc_syntax_only = c;
    var av = _run_argv("cc", _cc_flags(), 0);
    var after = alloc(8);
    var i = 1;
    while (load64(av + i * 8) != 0) { put(" "); put(load64(av + i * 8)); i = i + 1; }
    put("|");
    put(_cc_flags_cmdline());
    put("|");
    if (after >= av + (i + 1) * 8) { put("fits"); } else { put("SHORT"); }
    put("\n");
    return 0;
}
fn main(): i64 {
    alloc_init();
    var m = 0;
    while (m < 8) { row(m & 1, (m >> 1) & 1, (m >> 2) & 1); m = m + 1; }
    return 0;
}
var e = main();
syscall(60, e);
EOF
    } > "$2"
}
run_probe() {   # $1 = _run_argv source -> 8 lines, or BUILD-FAILED
    mk_probe "$1" "$T/p.cyr"
    if ! "$CC" < "$T/p.cyr" > "$T/p" 2> "$T/p.err" || [ ! -s "$T/p" ]; then
        grep -E '^error' "$T/p.err" | head -2 | sed 's/^/    /'
        echo BUILD-FAILED; return
    fi
    chmod +x "$T/p"
    ( ulimit -c 0; "$T/p" ) 2> /dev/null
}
x=$FAIL
run_probe "$T/_run_argv.cyr" > "$T/out"
# The expectation is written out by hand, in the order the list is documented to have.
cat > "$T/want" <<'EOF'
||fits
 --strict| --strict|fits
 --allow-undef| --allow-undef|fits
 --strict --allow-undef| --strict --allow-undef|fits
 --syntax-only| --syntax-only|fits
 --strict --syntax-only| --strict --syntax-only|fits
 --allow-undef --syntax-only| --allow-undef --syntax-only|fits
 --strict --allow-undef --syntax-only| --strict --allow-undef --syntax-only|fits
EOF
cmp -s "$T/want" "$T/out" || { fail "axis 1: argv / PE command line / sizing differ from the documented list:"; diff "$T/want" "$T/out" | sed 's/^/      /' | head -12; }
[ "$FAIL" = "$x" ] && echo "  ok axis 1: all 8 flag combinations — argv [cc, flags, NUL] fits its allocation, the PE command line carries the same tokens (all three at once: 5 slots)"

# ── axis 2 — one owner, derived from the sources ─────────────────────────────────────────
x=$FAIL
fnbody() { awk -v f="$1" '$0 ~ "^fn " f "\\(" { on = 1 } on { print } on && /^}/ { exit }' cbt/build.cyr | sed 's/#.*//'; }
fnbody compile > "$T/compile.cyr"
fnbody _win_compile_spawn_err > "$T/win.cyr"
[ -s "$T/compile.cyr" ] && [ -s "$T/win.cyr" ] || fail "axis 2: compile() / _win_compile_spawn_err not found in cbt/build.cyr"
grep -nE 'var[ \t]+argv[ \t]*\[' "$T/compile.cyr" > "$T/fixed" && fail "axis 2: compile() builds a fixed-size argv again: $(head -1 "$T/fixed")"
for lit in '--strict' '--allow-undef' '--syntax-only'; do
    for w in compile win; do
        grep -n -- "\"[ ]*$lit\"" "$T/$w.cyr" > "$T/lit" && fail "axis 2: a second copy of the flag list: $lit spelled in $w ($(head -1 "$T/lit"))"
    done
    n=$(sed 's/#.*//' cbt/build.cyr | grep -c -- "\"$lit\"" || true)
    [ "$n" = 1 ] || fail "axis 2: \"$lit\" is spelled $n times in cbt/build.cyr (want 1: inside _cc_flags)"
done
[ "$FAIL" = "$x" ] && echo "  ok axis 2: compile() has no fixed argv, and each flag literal is spelled once (in _cc_flags)"

# ── axis 3 — anti-vacuous: the old one-slot-short shape is caught ───────────────────────
x=$FAIL
sed 's/(n + base + 1) \* 8/(n + base) * 8/' "$T/_run_argv.cyr" > "$T/short.cyr"
cmp -s "$T/_run_argv.cyr" "$T/short.cyr" && fail "axis 3: the mutation did not apply (has _run_argv's allocation changed shape?)"
run_probe "$T/short.cyr" > "$T/out_short"
grep -q 'SHORT' "$T/out_short" || fail "axis 3: an argv allocation one slot short was NOT detected by axis 1's sizing check"
[ "$FAIL" = "$x" ] && echo "  ok axis 3: ⭐ an argv allocation one slot short reads SHORT (axis 1's sizing check is live)"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: compile_flag_list (one flag list for the POSIX argv and the PE command line; argv sized from it)"
