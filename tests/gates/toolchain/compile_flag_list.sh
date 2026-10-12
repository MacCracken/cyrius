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
# 6.7.8 — the same for the ENVIRONMENT: the compiler flags compile() injects (CYRIUS_BOUNDS,
# CYRIUS_DCE, CYRIUS_STRICT_PIN, CYRIUS_POISON, CYRIUS_PIE) come from ONE list, `_cc_flag_inject`,
# which the POSIX child's envp (`_cc_child_inject`) and the Windows arm (`_cc_win_env_apply`) both
# read. The Windows arm kept its own hand list — CYRIUS_DCE and CYRIUS_BOUNDS only — so `--poison`,
# `--strict-pin` and `--pie` never reached cycc.exe (the user's decision, 2026-10-10: fix it).
#   axis 4  derived (reads the arm): compile()'s `#ifdef CYRIUS_TARGET_WIN` arm calls
#           `_cc_flag_inject` and `_cc_win_env_apply` and sets no variable itself (`_win_setenv`);
#           `_cc_child_inject` calls `_cc_flag_inject` and pushes nothing but target selectors
#           (CYRIUS_TARGET_*, CYRIUS_KERNEL*, CYRIUS_ELF64_KERNEL); each flag entry literal is
#           spelled once in cbt/build.cyr.
#   axis 5  the REAL helpers, extracted, with a recording `_win_setenv`: for all 48 flag
#           combinations (bounds off / =1 / =0 x dce x strict-pin x poison x pie), each with the
#           target selectors off and on, the POSIX list is the flags in their documented order and
#           then the targets, and the Windows arm sets exactly the flags — each split NAME / value
#           — and no target; a `_win_setenv` that fails names the entry it failed on.
#   axis 6  ⭐ anti-vacuous: an extracted `_cc_win_env_apply` that hands `_win_setenv` the value
#           with its `=` (the split one byte short) is caught by axis 5.
# Mutation ledger (each measured RED in a scratch copy): the Windows arm back to its hand list
# (DCE + BOUNDS) -> axis 4, and build_config_windows_arm.sh axis 7 under wine; CYRIUS_POISON pushed
# by `_cc_child_inject` instead of `_cc_flag_inject` -> axes 4 and 5; `_cc_win_env_apply` applying
# only the first entry -> axis 5.
# 6.7.10 (P5-B) — `cyrius coverage --exec` adds CYRIUS_COVERAGE=1 + CYRIUS_COVERAGE_FILE=<dump> to the same
# list (`_cc_flag_inject`, while `_covx_dump` is set), LAST among the flags: axis 5 drives it alone and
# with every other flag and the targets on; axis 4 counts its literal once. (The arm deletes the two
# again once the compiler exits — `_covx_win_unset`, outside the arm text; coverage_exec_cli.sh W1.)
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

# ── axis 4 — the environment list, read out of the arm ───────────────────────────────────
x=$FAIL
awk '/^fn compile\(/ { inf = 1 } inf && /^[ \t]*#ifdef CYRIUS_TARGET_WIN/ { arm = 1; next } arm && /^[ \t]*#endif/ { exit } arm { print }' cbt/build.cyr | sed 's/#.*//' > "$T/winarm.cyr"
if [ ! -s "$T/winarm.cyr" ]; then
    fail "axis 4: compile()'s #ifdef CYRIUS_TARGET_WIN arm was not found in cbt/build.cyr"
else
    grep -q '_cc_flag_inject(' "$T/winarm.cyr" || fail "axis 4: the Windows arm does not build its environment from _cc_flag_inject (a hand list of its own is how it dropped --poison / --strict-pin / --pie)"
    grep -q '_cc_win_env_apply(' "$T/winarm.cyr" || fail "axis 4: the Windows arm does not apply the list (_cc_win_env_apply)"
    grep -n '_win_setenv(' "$T/winarm.cyr" > "$T/own" && fail "axis 4: the Windows arm sets a variable of its own: $(head -1 "$T/own")"
fi
fnbody _cc_child_inject > "$T/inject.cyr"
if [ ! -s "$T/inject.cyr" ]; then
    fail "axis 4: fn _cc_child_inject was not found in cbt/build.cyr"
else
    grep -q '_cc_flag_inject(' "$T/inject.cyr" || fail "axis 4: _cc_child_inject does not start from _cc_flag_inject"
    grep -oE 'vec_push\(inj, "[A-Z0-9_]+=' "$T/inject.cyr" | sed 's/.*"//; s/=$//' > "$T/pushed" || true
    [ -s "$T/pushed" ] || fail "axis 4: _cc_child_inject pushes no target selector — the scan is blind"
    grep -vxE 'CYRIUS_(TARGET_[A-Z]+|MACHO|MACHO_ARM|KERNEL|KERNEL_BASE|ELF64_KERNEL)' "$T/pushed" > "$T/nontgt" \
        && fail "axis 4: _cc_child_inject pushes a non-target entry of its own (the POSIX arm only): $(tr '\n' ' ' < "$T/nontgt")— put it in _cc_flag_inject"
fi
for lit in CYRIUS_DCE=1 CYRIUS_STRICT_PIN=1 CYRIUS_POISON=1 CYRIUS_PIE=1 CYRIUS_BOUNDS=1 CYRIUS_BOUNDS=0 CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE=; do
    n=$(sed 's/#.*//' cbt/build.cyr | grep -c -- "\"$lit\"" || true)
    [ "$n" = 1 ] || fail "axis 4: \"$lit\" is spelled $n times in cbt/build.cyr (want 1: in _cc_flag_inject / _cc_bounds_entry)"
done
[ "$FAIL" = "$x" ] && echo "  ok axis 4: the Windows arm builds its environment from _cc_flag_inject and sets nothing of its own; _cc_child_inject adds only target selectors; each flag entry is spelled once"

# ── axis 5 — the real helpers, every combination, both arms ──────────────────────────────
for f in _cc_flag_inject _cc_bounds_entry _cc_child_inject _cc_win_env_apply; do
    awk -v f="$f" '$0 ~ "^fn " f "\\(" { on = 1 } on { print } on && /^}/ { exit }' cbt/build.cyr > "$T/$f.cyr"
    [ -s "$T/$f.cyr" ] || fail "axis 5: fn $f was not found in cbt/build.cyr"
done
mk_env_probe() {   # $1 = the _cc_win_env_apply source to use, $2 = output .cyr
    {
        echo 'include "lib/syscalls.cyr"'
        echo 'include "lib/string.cyr"'
        echo 'include "lib/alloc.cyr"'
        echo 'include "lib/fmt.cyr"'
        echo 'include "lib/vec.cyr"'
        echo 'var _cfg_bounds_inject = 0;'
        echo 'var _cfg_dce_inject = 0;'
        echo 'var _strict_pin = 0;'
        echo 'var _poison_mode = 0;'
        echo 'var _pie_target = 0;'
        echo 'var _agnos_target = 0;'
        echo 'var _win_target = 0;'
        echo 'var _baremetal_target = 0;'
        echo 'var _section_base_env_ptr = 0;'
        echo 'var _fail_on = 0;'
        echo 'var _covx_dump = 0;'
        cat <<'CYR'
fn put(s): i64 { sys_write(1, s, strlen(s)); return 0; }
# cbt's `_cat2` (cbt/deps.cyr), which `_cc_flag_inject` builds the dump entry with.
fn _cat2(a, b): i64 {
    var la = strlen(a);
    var lb = strlen(b);
    var p = alloc(la + lb + 1);
    memcpy(p, a, la);
    memcpy(p + la, b, lb);
    store8(p + la + lb, 0);
    return p;
}
# The Windows arm's setter, recording "NAME=value;" per call; it fails (1) on the name _fail_on.
fn _win_setenv(name, val): i64 {
    if (_fail_on != 0) { if (streq(name, _fail_on) == 1) { return 1; } }
    put(name); put("="); put(val); put(";");
    return 0;
}
CYR
        cat "$T/_cc_flag_inject.cyr" "$T/_cc_bounds_entry.cyr" "$T/_cc_child_inject.cyr" "$1"
        cat <<'CYR'
# One line per combination: the POSIX list (each entry + ";"), "|", what the Windows arm set.
fn row(m, tg): i64 {
    _cfg_bounds_inject = m % 3;
    _cfg_dce_inject = (m / 3) & 1;
    _strict_pin = (m / 6) & 1;
    _poison_mode = (m / 12) & 1;
    _pie_target = (m / 24) & 1;
    _agnos_target = tg;
    _win_target = tg;
    _baremetal_target = tg;
    var pv = vec_new();
    _cc_child_inject(pv);
    var i = 0;
    while (i < vec_len(pv)) { put(vec_get(pv, i)); put(";"); i = i + 1; }
    put("|");
    var wv = vec_new();
    _cc_flag_inject(wv);
    var bad = _cc_win_env_apply(wv);
    if (bad != 0) { put("FAILED:"); put(bad); }
    put("\n");
    return 0;
}
fn main(): i64 {
    alloc_init();
    _section_base_env_ptr = "CYRIUS_KERNEL_BASE=0x100000";
    var tg = 0;
    while (tg < 2) {
        var m = 0;
        while (m < 48) { row(m, tg); m = m + 1; }
        tg = tg + 1;
    }
    _fail_on = "CYRIUS_POISON";
    row(47, 0);
    _fail_on = 0;
    _covx_dump = "/t/cov_1";
    row(0, 0);
    row(47, 1);
    return 0;
}
var e = main();
syscall(60, e);
CYR
    } > "$2"
}
run_env_probe() {   # $1 = _cc_win_env_apply source -> 97 lines, or BUILD-FAILED
    mk_env_probe "$1" "$T/e.cyr"
    if ! "$CC" < "$T/e.cyr" > "$T/e" 2> "$T/e.err" || [ ! -s "$T/e" ]; then
        grep -E '^error' "$T/e.err" | head -2 | sed 's/^/    /'
        echo BUILD-FAILED; return
    fi
    chmod +x "$T/e"
    ( ulimit -c 0; "$T/e" ) 2> /dev/null
}
# The oracle, written from the documented order (bounds first, then dce, strict-pin, poison, pie;
# the POSIX arm appends the target selectors; the Windows arm sets the flags and nothing else).
env_want() {
    tg=0
    while [ $tg -lt 2 ]; do
        m=0
        while [ $m -lt 48 ]; do
            f=""
            case $((m % 3)) in 1) f="${f}CYRIUS_BOUNDS=1;" ;; 2) f="${f}CYRIUS_BOUNDS=0;" ;; esac
            [ $(( (m / 3) & 1 )) = 1 ] && f="${f}CYRIUS_DCE=1;"
            [ $(( (m / 6) & 1 )) = 1 ] && f="${f}CYRIUS_STRICT_PIN=1;"
            [ $(( (m / 12) & 1 )) = 1 ] && f="${f}CYRIUS_POISON=1;"
            [ $(( (m / 24) & 1 )) = 1 ] && f="${f}CYRIUS_PIE=1;"
            t=""
            [ $tg = 1 ] && t="CYRIUS_TARGET_AGNOS=1;CYRIUS_TARGET_WIN=1;CYRIUS_KERNEL=1;CYRIUS_ELF64_KERNEL=1;CYRIUS_KERNEL_BASE=0x100000;"
            printf '%s%s|%s\n' "$f" "$t" "$f"
            m=$((m + 1))
        done
        tg=$((tg + 1))
    done
    echo "CYRIUS_BOUNDS=0;CYRIUS_DCE=1;CYRIUS_STRICT_PIN=1;CYRIUS_POISON=1;CYRIUS_PIE=1;|CYRIUS_BOUNDS=0;CYRIUS_DCE=1;CYRIUS_STRICT_PIN=1;FAILED:CYRIUS_POISON=1"
    # 6.7.10: the coverage entries, alone and after every other flag (the targets after them on POSIX)
    echo "CYRIUS_COVERAGE=1;CYRIUS_COVERAGE_FILE=/t/cov_1;|CYRIUS_COVERAGE=1;CYRIUS_COVERAGE_FILE=/t/cov_1;"
    cv="CYRIUS_BOUNDS=0;CYRIUS_DCE=1;CYRIUS_STRICT_PIN=1;CYRIUS_POISON=1;CYRIUS_PIE=1;CYRIUS_COVERAGE=1;CYRIUS_COVERAGE_FILE=/t/cov_1;"
    echo "${cv}CYRIUS_TARGET_AGNOS=1;CYRIUS_TARGET_WIN=1;CYRIUS_KERNEL=1;CYRIUS_ELF64_KERNEL=1;CYRIUS_KERNEL_BASE=0x100000;|${cv}"
}
x=$FAIL
env_want > "$T/ewant"
run_env_probe "$T/_cc_win_env_apply.cyr" > "$T/eout"
cmp -s "$T/ewant" "$T/eout" || { fail "axis 5: the env list differs between the arms or from the documented order:"; diff "$T/ewant" "$T/eout" | sed 's/^/      /' | head -12; }
[ "$FAIL" = "$x" ] && echo "  ok axis 5: all 48 flag combinations x targets off / on — the POSIX list is the flags then the targets, the Windows arm sets exactly the flags (NAME / value split) and no target; a failing set names its entry"

# ── axis 6 — anti-vacuous: a split one byte short is caught ───────────────────────────────
x=$FAIL
sed 's/_win_setenv(nm, e + n + 1)/_win_setenv(nm, e + n)/' "$T/_cc_win_env_apply.cyr" > "$T/short_env.cyr"
cmp -s "$T/_cc_win_env_apply.cyr" "$T/short_env.cyr" && fail "axis 6: the mutation did not apply (has _cc_win_env_apply's split changed shape?)"
run_env_probe "$T/short_env.cyr" > "$T/eout_short"
cmp -s "$T/ewant" "$T/eout_short" && fail "axis 6: a value handed to _win_setenv with its '=' was NOT detected by axis 5"
[ "$FAIL" = "$x" ] && echo "  ok axis 6: ⭐ a NAME / value split one byte short is caught by axis 5"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: compile_flag_list (one flag list for the POSIX argv and the PE command line; argv sized from it; one environment list for both spawn arms)"
