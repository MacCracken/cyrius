#!/bin/sh
# tests/gates/frontend/bounds_mode_checked.sh — 6.7.8 (C2-7, C2-8, C2-9)
#
# THE BOUNDS-CHECKED MODE'S SWITCH (the user's decision, 2026-10-10: "Flags: CYRIUS_BOUNDS=1 (all
# seven forks, like CYRIUS_POISON); a CYRIUS_BOUNDS predefine for #ifdef; --bounds on build / test /
# run / fuzz; [build] bounds = true; #bounds as a whole-program directive line. Precedence: argument
# > env > manifest > source."). The mode is decided once, in the shared PREPROCESS before the first
# `#ifdef` (src/frontend/lex_pp.cyr `_bnd_setup`): CYRIUS_BOUNDS 1 / 0 (unset or empty: no rung;
# anything else refused by name), else a `#bounds` line in the ENTRY file's LEADING BLOCK (blank
# lines, `#` comments, `include` lines before it). On, it predefines CYRIUS_BOUNDS. A `#bounds`
# anywhere else is refused by name — the line switches the whole program, so an included library
# must not be able to. The mode is refused for a kernel / EFI image and a `shared;` / `object;` build.
# (cbt's rungs — --bounds, [build] bounds, what compile() hands cycc — are build_config_precedence.sh's;
# every fork's env read and line are fork_flag_parity.sh's `bounds` rows.)
#
# WHAT THE MODE CHECKS (C2-8; the user's decision: "a violation prints `bounds: index N out of [0,
# LEN) at <file>:<line>` to stderr and exits 134 ... typed arrays a[i] against their exact N; slice
# reads AND writes; a *T subscript checked for a NEGATIVE index only ... A constant index provably
# out of range WARNS in every mode and is an ERROR under the mode. @unsafe { } turns checks off
# inside it."). Every subscript asks src/frontend/parse_expr.cyr `_bck_open` at its `[` and calls the
# checker the preprocessor appends to the finished unit (lex_pp.cyr `_bnd_finish`) once the index is
# in rax — so every target lowers the violation through its own write / exit paths.
#
#   B1  `#bounds` in the leading block — line 1, after comments / blank lines, indented with a
#       trailing comment — turns the mode on (the predefine's `#ifdef` arm runs: exit 7); the line
#       is blanked, not deleted: a later error keeps its exact line
#   B2  after `include` lines: on, and the predefine reaches the file included ABOVE the line (B9)
#   B3  after code (a var, a fn, a statement) -> refused by name at <source>:L, exactly one error
#   B4  inside a taken / an untaken `#ifdef`, after a `#define` -> refused, one error
#   B5  in an included file, and in a file THAT includes -> refused at its own file:line, once
#   B6  in a `[build] modules` file cbt splices in above `#@srcline` -> refused; the entry's own
#       `#bounds` through `cyrius build -D X` (a materialized unit) is honoured; the control (the
#       module without the line) builds
#   B7  `#bounds` inside a multi-line string is data: not honoured, not refused, bytes kept
#   B8  `#bounds on` / `#bounds 1` -> "#bounds takes no argument"
#   B10 `#bounds` + CYRIUS_BOUNDS=0 -> off (the environment beats the source)
#   E1  CYRIUS_BOUNDS=1 on; =0 off; EMPTY no rung (off alone, on with a `#bounds` line)
#   E2  CYRIUS_BOUNDS=2 / true / yes refused by name, naming the value; no binary
#   E3  a plain `#define CYRIUS_BOUNDS` is an ordinary define: it switches nothing (a `kernel;`
#       build with it compiles, where `#bounds` + `kernel;` is refused)
#   E4  (6.7.9: DERIVED, both variables) every self-build script unsets CYRIUS_BOUNDS and
#       CYRIUS_POISON before its first code line naming a src/main*.cyr fork — an inherited one
#       must not build a bounds-checked / poison-mode compiler (or install, ship, bench or verify
#       one). The set: each shell script under scripts/ (a .sh, or a file whose #! line runs a
#       shell — scripts/cyriusly) and bootstrap/ whose code (comment lines dropped) names a fork;
#       floor 12, and both file shapes seen (scripts/install.sh, scripts/cyriusly). Named out:
#       scripts/cyrius-watch.sh (src/main.cyr there is a user PROJECT's default entry — the user's
#       mode must reach it) and scripts/hooks/pre-commit (a restore hint; it builds nothing). Two
#       name no fork and are held BY NAME: bootstrap/bootstrap.sh (it builds the bootstrap compiler
#       cybs; both variables) and scripts/check.sh (its self-builds are install.sh and the check
#       driver: CYRIUS_BOUNDS; its CYRIUS_POISON stays for the suite, and
#       tests/gates/toolchain/selfbuild_poison_scrubbed.sh P3 holds its self-builds to
#       `_chk_selfbuild`). E4b: `CYRIUS_BOUNDS=1 CYRIUS_POISON=1 sh scripts/build-cycc-verify.sh`
#       is green, and that inherited pair DOES change cycc(src) (anti-vacuous)
#   M4  the mode with `kernel;`, CYRIUS_KERNEL=1 (a bare-metal --target), `shared;`, `object;`,
#       CYRIUS_TARGET_EFI=1 -> refused by name (and nothing more: the refusal is fatal at once, so the
#       injected checker is never compiled for a target it cannot serve); each control (the same
#       build, mode off) compiles
#   V1-V4 the violation — an array (u8[5] at runtime 5: the EXACT N), a `*T` (`[0, ...)`), a slice
#       (its length) and a file the entry includes (named by its include path) — exit 134 and exactly
#       the one line, on x86 (plain, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine)
#   AG  agnos: the checker writes with agnos's #1 and exits with agnos's #0 (run here: the line, then
#       the program's own exit 5 — a Linux exit 60 would be 134)
#   W   tests/tcyr/crossos/bounds_mode_in_range.tcyr (nothing trips: every checked shape at 0 and
#       N-1, @unsafe U1/U2) and bounds_mode_violation.tcyr (20 self-spawned children: every base and
#       context, each exit 134 + its exact line; on qemu / cx `nospawn`): no warning, --syntax-only
#       silent; x86 plain / IR=1 / IR=3 / DCE=1 / STACK_ARRAYS=0, aarch64, cx, PE
#   K   the constant rule: out of range a warning (mode off; under the mode inside @unsafe), an error
#       under the mode; consts, enum constants, `( )`, `+ - *`, unary minus; a shadowing local, `/`,
#       `<<` and a slice's index are not the rule's (run-time checked, no diagnostic); once per
#       token across generic instances; silent under --syntax-only; an in-range constant emits no
#       call (CYRIUS_DCE_VERBOSE lists the checker dead), a run-time index does
#   OFF every subscript-using .tcyr (floor 30): mode off holds no checker bytes, unset ==
#       CYRIUS_BOUNDS=0 byte for byte
#   N1  a folded global (`var A: u8[5]; var A: u8[6];`) checks against the FIRST declaration's N
#   R14 a checked subscript in a `#naked` fn under the mode is refused by name (inside @unsafe, or
#       with the mode off, it compiles)
#   DCE / SP / PURE / EFF / T2 / AS: no site, CYRIUS_DCE=1 drops the six checker fns; 2,001 sites in
#       one file (one interned name) and the last one's line; no `#pure` warning; a by-value struct
#       argument beside a subscripting one keeps its value; `return g(a[i]);` (a tail call) in range
#       and tripping; a suspending `async fn`'s frame in range and tripping
#   TL  (C2-9) tools and the guide: the lane's eight value files pass `cyrfmt --check` and cyrlint
#       with 0 warnings (TL1; each checker first shown to fail on a bad input, TL0); lib/slice.cyr's
#       api-surface is the snapshot's and `_slice_idx_addr` stays private (TL2); build / run / test /
#       fuzz --help describe --bounds, the top-level help shows [--bounds] on those four lines, bench
#       says nothing of it (TL3); the guide's § The bounds-checked mode: its first example prints
#       exactly the `bounds:` line its text fence states and exits 134, silent / exit 0 with
#       CYRIUS_BOUNDS=0, and the constant warning and the #naked refusal it quotes are the
#       compiler's texts (TL4). Each tool is built here from programs/ with $CC.
#
# MUTATION LEDGER (scratch trees, each its 2-stage mutant cycc; this gate and the named toolchain
# gates run from that tree as CYCC=<mutant>; 2026-10-10):
#   M13a `_bnd_line` honours a `#bounds` line outside the leading block (its two placement tests
#        removed)                                                            -> RED B3a-B3c B4a-B4c B6a
#   M13b `_bnd_inc_line` lets an included file's `#bounds` through           -> RED B5a B5b
#   M14  `_bnd_env_rung` ignores CYRIUS_BOUNDS=0                             -> RED B10, and
#        build_config_precedence.sh "bounds 3" (manifest false beats #bounds) + "bounds 8" (env 0
#        beats #bounds)
#   M15  cbt does not hand a manifest `false` down as CYRIUS_BOUNDS=0 (`_cfg_bounds_inject_set`)
#                                                                            -> RED build_config_precedence.sh
#        "bounds 3", build_config_windows_arm.sh axis 6
#   M20  `_bnd_target_check`'s kernel / EFI refusal dropped                  -> RED M4a M4b M4e
#   M29  `--bounds` / `[build] bounds` not read for `cyrius test` (`_cfg_bounds_verb` drops test)
#                                                                            -> RED build_config_precedence.sh
#        "test --bounds" (a file and a directory) and "[build] bounds reaches cyrius test"
#   MF   `_bnd_setup` not called from PREPROCESS                             -> RED every B / E1a / E2 /
#        M4 row here, and fork_flag_parity.sh "bounds <every fork> env1 / line / line_env0 / env2"
# C2-8 (2026-10-10; this gate, plus the two crossos files run from the mutant tree):
#   M9   N taken from the rounded storage (`u8[5]` checked as 8)             -> RED V1 V4 (every leg),
#        K1a-K1g, N1b, SP, AS2, DCE2, AG, WVa / WVd, and bounds_mode_violation.tcyr 30 of 63 (every
#        child whose N is not a multiple of 8 / sizeof(T))
#   M10  the check placed after EPTR_SCALE (the scaled index checked)        -> RED V2 (`index -16`) V4,
#        WI / WV every leg, EFF, T2a / T2b; bounds_mode_in_range.tcyr exits 134 (i16[4] index 3 as 6)
#   M11  `_bck_unsafe_at` always 0                                           -> RED WIa-WId (U1 trips at
#        its `a[six]`), K1c, R14b, bounds_mode_in_range.tcyr exits 134
#   M12  `_unsafe_depth` instead of the token ranges                         -> RED WVa / WVd: U3
#        `inline_in_unsafe` (an #inline fn replayed inside @unsafe) no longer trips (3 asserts)
#   M16  the in-range constant skip removed (only out-of-range skipped)      -> RED K5a, DCE1
#   M17  a constant out of range not escalated under the mode               -> RED K1b
#   M18  the site's line taken from an #inline replay's CALL site           -> RED WVa / WVd: U3's line
#   M19  the checker exits with syscall(60, …) on agnos                     -> RED AG (exit 134)
#   M30  the checker injected with the mode off                             -> RED OFF (every file),
#        the M4 EFI control (its write import refused)
#   M31a the checker exits 1, not 134                                        -> RED V1-V4 every leg,
#        bounds_mode_violation.tcyr 20 of 63
#   M31b the site's line off by one                                          -> RED V1-V4 every leg,
#        bounds_mode_violation.tcyr 21 of 63
#   MS   the slice read's site removed (the getter's own trap answers)      -> RED V3a-V3d ("slice
#        bounds violation", not the mode's line)
#   MN   the #naked refusal dropped                                          -> RED R14
# C2-9 (2026-10-10; this gate run from a scratch tree holding the one mutation, each RED exactly 1 of
# 153 rows):
#   MTL1 one line of deref_element_width.tcyr un-indented                    -> RED TL1a (that file)
#   MTL2 a 130-column comment line in slice_signed_read.tcyr                 -> RED TL1b (that file; cyrlint
#        exits 0 with a warning — the row reads its "0 warnings" line, not its exit code)
#   MTL3 a public `slice_idx_addr` wrapper appended to lib/slice.cyr         -> RED TL2
#   MTL4 the build help's two --bounds lines dropped (cbt/cli_args.cyr)      -> RED TL3 build
#   MTL5 the guide's stated violation line off by one (<source>:6)           -> RED TL4a
#   MTL6 the guide's quoted constant warning reworded ("in" for "under")     -> RED TL4c
# 6.7.9 E4 / E4b (the E4 block run alone on a scratch copy of the tree holding the one mutation;
# the pre-fix tree: 13 RED — the twelve unscrubbed scripts and E4b; 2026-10-11):
#   MQ1  install.sh's unset removed                                          -> RED E4 install.sh
#   MQ2  cyriusly's unset (its setup arm) removed                            -> RED E4 cyriusly
#   MQ3  funcgate-posix.sh unsets CYRIUS_BOUNDS only                         -> RED E4 (CYRIUS_POISON)
#   MQ4  mac-selfhost.sh's unset moved below its first build                 -> RED E4 ("after")
#   MQ5  install.sh blanks the pair (`CYRIUS_BOUNDS= CYRIUS_POISON=`)         -> RED E4 install.sh
#   MQ6  a new scripts/new-cross.sh building src/main_aarch64.cyr, no scrub  -> RED E4 new-cross.sh
#   MQ7  a new extensionless `#!/usr/bin/env bash` self-build, no scrub      -> RED E4 newtool
#   MQ8  build-cycc-verify.sh's unset removed                                -> RED E4 + E4b (rc 3)
#   MQ9  bootstrap.sh's CYRIUS_POISON unset removed                          -> RED E4 bootstrap.sh
#   MQ10 (the gate) the fork regex blinded                                   -> RED E4 floor + both shapes
#   MQ11 (the gate) the #! shape not scanned (only .sh)                      -> RED E4 misses cyriusly
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=bounds_mode_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT" || exit 1
unset CYRIUS_BOUNDS
fails=0
rows=0
skips=0
ok()  { rows=$((rows + 1)); echo "  ok   $1"; }
bad() { rows=$((rows + 1)); echo "  FAIL $1"; fails=$((fails + 1)); }

# The probe: exit 7 when the CYRIUS_BOUNDS predefine is visible, 3 when it is not.
PROBE='var code = 3;
#ifdef CYRIUS_BOUNDS
code = 7;
#endif
syscall(60, code);'

# cc <tag> <src file> [env...]: compile in $T (includes resolve there); sets RC, ERRS (error lines)
cc() {
    tag=$1; src=$2; shift 2
    RC=0
    (cd "$T" && env "$@" "$CC" < "$src" > "$T/$tag.bin" 2> "$T/$tag.err") || RC=$?
    ERRS=$(grep -c '^error' "$T/$tag.err" || true)
}
# xc <row> <want exit> <src file> [env...]: compiles clean and the program exits <want>
xc() {
    row=$1; want=$2; src=$3; shift 3
    cc "x$rows" "$src" "$@"
    if [ "$RC" != 0 ]; then bad "$row: did not compile (rc $RC): $(head -2 "$T/x$rows.err" | tr '\n' ' ')"; return; fi
    chmod +x "$T/x$rows.bin"; got=0; "$T/x$rows.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" = "$want" ]; then ok "$row (exit $got)"; else bad "$row: exit $got, want $want"; fi
}
# xe <row> <message> <src file> [env...]: refused — rc != 0, exactly ONE error line, holding <message>
xe() {
    row=$1; msg=$2; src=$3; shift 3
    cc "e$rows" "$src" "$@"
    if [ "$RC" = 0 ]; then bad "$row: compiled (want a refusal: $msg)"; return; fi
    if ! grep -qF -- "$msg" "$T/e$rows.err"; then bad "$row: rc $RC without '$msg': $(head -2 "$T/e$rows.err" | tr '\n' ' ')"; return; fi
    if [ "$ERRS" != 1 ]; then bad "$row: $ERRS error lines (want exactly 1): $(grep '^error' "$T/e$rows.err" | tr '\n' '|')"; return; fi
    ok "$row: $(grep '^error' "$T/e$rows.err" | head -1 | cut -c1-110)"
}
M1='#bounds must sit in the entry file'"'"'s leading block'
M4K='the bounds-checked mode is not available for a kernel / EFI image'
M4S='the bounds-checked mode is not available for a shared; or object; build'

# ── B: the line ────────────────────────────────────────────────────────────────────────────────
printf '#bounds\n%s\n' "$PROBE" > "$T/b1a.cyr"
printf '# a program\n\n# another comment\n#bounds\n\n%s\n' "$PROBE" > "$T/b1b.cyr"
printf '   #bounds   # the whole program is checked\n%s\n' "$PROBE" > "$T/b1c.cyr"
xc "B1a #bounds on line 1" 7 b1a.cyr
xc "B1b #bounds after comments and blank lines" 7 b1b.cyr
xc "B1c an indented #bounds with a trailing comment" 7 b1c.cyr
printf '#bounds\n\nvar x = ;\n' > "$T/b1d.cyr"
cc b1d b1d.cyr
if [ "$RC" != 0 ] && grep -q '^error:<source>:3:' "$T/b1d.err"; then ok "B1d the line is blanked, not deleted: the error after it is at <source>:3"
else bad "B1d an error two lines after #bounds: rc $RC, $(grep '^error' "$T/b1d.err" | head -1) (want <source>:3)"; fi

printf 'fn inc_v(): i64 {\n#ifdef CYRIUS_BOUNDS\n    return 9;\n#endif\n    return 4;\n}\n' > "$T/inc_v.cyr"
printf '# entry\ninclude "inc_v.cyr"\n\n#bounds\nsyscall(60, inc_v());\n' > "$T/b2.cyr"
xc "B2 #bounds after an include line: on, and the file included ABOVE it sees the predefine (B9)" 9 b2.cyr
printf 'include "inc_v.cyr"\nsyscall(60, inc_v());\n' > "$T/b2c.cyr"
xc "B2c the control: the same include without #bounds" 4 b2c.cyr

printf 'var x = 1;\n#bounds\nsyscall(60, x);\n' > "$T/b3a.cyr"
printf 'fn f(): i64 { return 1; }\n\n#bounds\nsyscall(60, f());\n' > "$T/b3b.cyr"
printf 'syscall(1, 1, "", 0);\n#bounds\n' > "$T/b3c.cyr"
xe "B3a after a var" "$M1" b3a.cyr
if ! grep -q '^error:<source>:2:1: ' "$T/e$((rows - 1)).err" 2>/dev/null; then bad "B3a: the refusal does not name <source>:2:1: $(head -1 "$T/e$((rows - 1)).err")"; fi
xe "B3b after a fn" "$M1" b3b.cyr
xe "B3c after a statement" "$M1" b3c.cyr

printf '#ifdef CYRIUS_ARCH_X86\n#bounds\n#endif\nsyscall(60, 3);\n' > "$T/b4a.cyr"
printf '#ifdef NOT_DEFINED_ANYWHERE\n#bounds\n#endif\nsyscall(60, 3);\n' > "$T/b4b.cyr"
printf '#define X 1\n#bounds\nsyscall(60, 3);\n' > "$T/b4c.cyr"
xe "B4a inside a taken #ifdef" "$M1" b4a.cyr
xe "B4b inside an untaken #ifdef" "$M1" b4b.cyr
xe "B4c after a #define" "$M1" b4c.cyr

printf 'fn inc_a(): i64 { return 1; }\n\n#bounds\n' > "$T/inc_b.cyr"
printf '# outer\ninclude "inc_b2.cyr"\n' > "$T/inc_w.cyr"
printf '# inner\n\n\n#bounds\n' > "$T/inc_b2.cyr"
printf 'include "inc_b.cyr"\nsyscall(60, inc_a());\n' > "$T/b5a.cyr"
printf 'include "inc_w.cyr"\nsyscall(60, 3);\n' > "$T/b5b.cyr"
xe "B5a in an included file, named at inc_b.cyr:3" "error:inc_b.cyr:3:1: #bounds must sit" b5a.cyr
xe "B5b in a file an included file includes, named at inc_b2.cyr:4" "error:inc_b2.cyr:4:1: #bounds must sit" b5b.cyr

printf 'var s = "x\n#bounds\n";\nvar c = load8(s + 2);\n#ifdef CYRIUS_BOUNDS\nc = 1;\n#endif\nsyscall(60, c);\n' > "$T/b7.cyr"
xc "B7 #bounds inside a multi-line string is data (byte kept: 35 = '#'; mode off)" 35 b7.cyr

printf '#bounds on\nsyscall(60, 3);\n' > "$T/b8a.cyr"
printf '#bounds 1\nsyscall(60, 3);\n' > "$T/b8b.cyr"
xe "B8a #bounds on" "#bounds takes no argument" b8a.cyr
xe "B8b #bounds 1" "#bounds takes no argument" b8b.cyr

xc "B10 #bounds with CYRIUS_BOUNDS=0: off" 3 b1a.cyr CYRIUS_BOUNDS=0

# ── B6: through cyrius build (the materialized unit) ─────────────────────────────────────────────
"$CC" < cbt/cyrius.cyr > "$T/cyrius" 2> "$T/cbt.err" || { bad "B6: cbt/cyrius.cyr does not build: $(grep -m1 error "$T/cbt.err")"; }
chmod +x "$T/cyrius" 2>/dev/null
mkdir -p "$T/home/bin" "$T/p/src"
ln -s "$CC" "$T/home/bin/cycc"
printf '%s\n' "$PROBE" > "$T/p/src/main.cyr"
printf '#bounds\n%s\n' "$PROBE" > "$T/p/src/on.cyr"
printf 'fn mod_fn(): i64 { return 1; }\n' > "$T/p/src/m_ok.cyr"
printf '# a module\n#bounds\nfn mod_fn(): i64 { return 1; }\n' > "$T/p/src/m_bad.cyr"
cb() {   # cb <module> <args...>: cyrius build in $T/p; sets RC, EXIT
    printf '[package]\nname = "p"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p"\nmodules = ["%s"]\n' "$1" > "$T/p/cyrius.cyml"
    shift
    rm -f "$T/p/build/p"
    RC=0
    (cd "$T/p" && env -u CYRIUS_BOUNDS -u CYRIUS_DCE -u CYRIUS_DEFINES CYRIUS_HOME="$T/home" CYRIUS_RESOLVED=1 "$T/cyrius" build "$@") > "$T/cb.out" 2>&1 || RC=$?
    EXIT=none
    if [ -x "$T/p/build/p" ]; then EXIT=0; "$T/p/build/p" || EXIT=$?; fi
}
cb src/m_bad.cyr
if [ "$RC" != 0 ] && grep -qF "$M1" "$T/cb.out" && [ "$EXIT" = none ]; then ok "B6a a #bounds line in a [build] modules file is refused (spliced above #@srcline)"
else bad "B6a [build] modules with #bounds: rc $RC, built $EXIT: $(grep -m1 error "$T/cb.out")"; fi
cb src/m_ok.cyr
if [ "$RC" = 0 ] && [ "$EXIT" = 3 ]; then ok "B6b the control: the module without the line builds (mode off, exit 3)"
else bad "B6b the control build: rc $RC, exit $EXIT: $(grep -m1 error "$T/cb.out")"; fi
cb src/m_ok.cyr -D SOME_DEFINE src/on.cyr build/p
if [ "$RC" = 0 ] && [ "$EXIT" = 7 ]; then ok "B6c the entry's own #bounds through cyrius build -D (a materialized unit with a prelude) is honoured (exit 7)"
else bad "B6c cyrius build -D of a #bounds entry: rc $RC, exit $EXIT: $(grep -m1 error "$T/cb.out")"; fi

# ── E: the environment ───────────────────────────────────────────────────────────────────────────
printf '%s\n' "$PROBE" > "$T/e.cyr"
xc "E1a CYRIUS_BOUNDS=1: on" 7 e.cyr CYRIUS_BOUNDS=1
xc "E1b CYRIUS_BOUNDS=0: off" 3 e.cyr CYRIUS_BOUNDS=0
xc "E1c unset: off" 3 e.cyr
xc "E1d CYRIUS_BOUNDS= (empty) is no rung: off" 3 e.cyr CYRIUS_BOUNDS=
xc "E1e CYRIUS_BOUNDS= (empty) with a #bounds line: the line decides (on)" 7 b1a.cyr CYRIUS_BOUNDS=
for v in 2 true yes; do
    xe "E2 CYRIUS_BOUNDS=$v is refused by name" "CYRIUS_BOUNDS must be 0 or 1 (or unset): $v" e.cyr CYRIUS_BOUNDS=$v
    if [ -s "$T/e$((rows - 1)).bin" ]; then bad "E2 CYRIUS_BOUNDS=$v: a binary was written"; fi
done
printf '#define CYRIUS_BOUNDS\nkernel;\nvar x = 1;\n' > "$T/e3.cyr"
cc e3 e3.cyr
if [ "$RC" = 0 ]; then ok "E3 a plain #define CYRIUS_BOUNDS switches nothing (a kernel; build with it compiles)"
else bad "E3 #define CYRIUS_BOUNDS + kernel;: rc $RC: $(head -1 "$T/e3.err")"; fi
# E4 (6.7.9) — DERIVED: every shell script under scripts/ and bootstrap/ whose code names a
# src/main*.cyr fork is a self-build (the header says which two are named out, and why).
# _e4_unset <file> <var>: the first line that unsets <var> (comment lines never match).
_e4_unset() { grep -nE "^[[:space:]]*unset([[:space:]]+[A-Z_]+)*[[:space:]]+$2([[:space:]]|\$)" "$1" | head -1 | cut -d: -f1 || true; }
: > "$T/e4set"
for s in $(find scripts bootstrap -type f | LC_ALL=C sort); do
    case "$s" in scripts/cyrius-watch.sh|scripts/hooks/pre-commit) continue ;; esac
    case "$s" in
        *.sh) ;;
        */*.*) continue ;;
        *) head -1 "$s" | grep -qE '^#!.*(/|env[[:space:]]+)(ba|da|k|z)?sh([[:space:]]|$)' || continue ;;
    esac
    b=$(grep -nE 'src/main[a-z_0-9]*\.cyr' "$s" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1 || true)
    [ -n "$b" ] && echo "$s $b" >> "$T/e4set"
done
e4n=$(grep -c . "$T/e4set" || true)
if [ "$e4n" -lt 12 ]; then bad "E4 the derivation found $e4n self-build script(s) (floor 12) — the scan is blind"
else ok "E4 the derivation finds $e4n self-build scripts (floor 12)"; fi
for s in scripts/install.sh scripts/cyriusly; do
    grep -q "^$s " "$T/e4set" || bad "E4 the derivation misses $s (a .sh and a #! script with no extension must each be seen)"
done
while read -r s b; do
    e4bad=""
    for v in CYRIUS_BOUNDS CYRIUS_POISON; do
        u=$(_e4_unset "$s" "$v")
        if [ -z "$u" ]; then e4bad="$e4bad; does not unset $v"
        elif [ "$u" -gt "$b" ]; then e4bad="$e4bad; unsets $v at line $u, after"; fi
    done
    if [ -n "$e4bad" ]; then bad "E4 $s (first src/main*.cyr line $b)${e4bad} — an inherited one reaches its self-build"
    else ok "E4 $s unsets CYRIUS_BOUNDS (line $(_e4_unset "$s" CYRIUS_BOUNDS)) and CYRIUS_POISON (line $(_e4_unset "$s" CYRIUS_POISON)) before line $b"; fi
done < "$T/e4set"
# By name: the two that name no fork. bootstrap.sh's first build line is its first `cat`.
b=$(grep -nE '^[^#]*cat[[:space:]]' bootstrap/bootstrap.sh | head -1 | cut -d: -f1 || true)
e4bad=""
for v in CYRIUS_BOUNDS CYRIUS_POISON; do
    u=$(_e4_unset bootstrap/bootstrap.sh "$v")
    if [ -z "$u" ]; then e4bad="$e4bad; does not unset $v"
    elif [ -n "$b" ] && [ "$u" -gt "$b" ]; then e4bad="$e4bad; unsets $v at line $u, after its first build line $b"; fi
done
if [ -n "$e4bad" ]; then bad "E4 bootstrap/bootstrap.sh${e4bad}"
else ok "E4 bootstrap/bootstrap.sh unsets CYRIUS_BOUNDS and CYRIUS_POISON before it builds (line ${b:-?})"; fi
u=$(_e4_unset scripts/check.sh CYRIUS_BOUNDS)
if [ -n "$u" ]; then ok "E4 scripts/check.sh unsets CYRIUS_BOUNDS (line $u); its CYRIUS_POISON is selfbuild_poison_scrubbed.sh P3's"
else bad "E4 scripts/check.sh does not unset CYRIUS_BOUNDS (an inherited CYRIUS_BOUNDS=1 would switch the mode on in its self-builds and its suite)"; fi
# E4b — the scrub at run time, on the cheapest self-build script: the inherited pair leaves its
# fixpoint green. A red run is judged against a clean one (red alone too: this row cannot judge).
e4rc=0
( CYRIUS_BOUNDS=1 CYRIUS_POISON=1; export CYRIUS_BOUNDS CYRIUS_POISON; sh scripts/build-cycc-verify.sh ) > "$T/e4b.on" 2>&1 || e4rc=$?
if [ "$e4rc" = 0 ]; then
    ( CYRIUS_BOUNDS=1 CYRIUS_POISON=1; export CYRIUS_BOUNDS CYRIUS_POISON; "$CC" < src/main.cyr > "$T/e4b.cc" 2> /dev/null ) || true
    if [ -s "$T/e4b.cc" ] && ! cmp -s "$T/e4b.cc" build/cycc; then
        ok "E4b CYRIUS_BOUNDS=1 CYRIUS_POISON=1 sh scripts/build-cycc-verify.sh is green (the pair changes cycc(src): $(wc -c < "$T/e4b.cc") B vs $(wc -c < build/cycc) B)"
    else bad "E4b cannot judge: under CYRIUS_BOUNDS=1 CYRIUS_POISON=1 cycc(src) is build/cycc (or did not build) — the premise is gone (re-derive E4)"; fi
    rm -f "$T/e4b.cc"
else
    e4rc0=0
    ( unset CYRIUS_BOUNDS CYRIUS_POISON; sh scripts/build-cycc-verify.sh ) > "$T/e4b.off" 2>&1 || e4rc0=$?
    if [ "$e4rc0" = 0 ]; then bad "E4b scripts/build-cycc-verify.sh is green alone and RED (rc $e4rc) under CYRIUS_BOUNDS=1 CYRIUS_POISON=1: $(grep -m1 -E 'FAIL|WARN' "$T/e4b.on")"
    else bad "E4b cannot judge: scripts/build-cycc-verify.sh is RED without the variables too (rc $e4rc0): $(grep -m1 -E 'FAIL|WARN' "$T/e4b.off")"; fi
fi

# ── M4: where the mode has no meaning ────────────────────────────────────────────────────────────
printf '#bounds\nkernel;\nvar x = 1;\n' > "$T/m4a.cyr"
printf 'kernel;\nvar x = 1;\n' > "$T/m4a0.cyr"
printf 'var x = 1;\n' > "$T/m4b.cyr"
printf '#bounds\nshared;\nfn f(): i64 { return 1; }\n' > "$T/m4c.cyr"
printf 'shared;\nfn f(): i64 { return 1; }\n' > "$T/m4c0.cyr"
printf '#bounds\nobject;\nfn f(): i64 { return 1; }\n' > "$T/m4d.cyr"
printf 'object;\nfn f(): i64 { return 1; }\n' > "$T/m4d0.cyr"
xe "M4a #bounds + kernel;" "$M4K" m4a.cyr
xe "M4b CYRIUS_BOUNDS=1 + CYRIUS_KERNEL=1 (a bare-metal --target)" "$M4K" m4b.cyr CYRIUS_BOUNDS=1 CYRIUS_KERNEL=1
xe "M4c #bounds + shared;" "$M4S" m4c.cyr
xe "M4d #bounds + object;" "$M4S" m4d.cyr
xe "M4e CYRIUS_BOUNDS=1 + CYRIUS_TARGET_EFI=1" "$M4K" m4b.cyr CYRIUS_BOUNDS=1 CYRIUS_TARGET_EFI=1
for c in "m4a0.cyr" "m4b.cyr CYRIUS_KERNEL=1" "m4c0.cyr" "m4d0.cyr" "m4b.cyr CYRIUS_TARGET_EFI=1"; do
    set -- $c; f=$1; shift
    cc m4ctl "$f" "$@"
    if [ "$RC" = 0 ]; then ok "M4 control: $c compiles with the mode off"
    else bad "M4 control $c: rc $RC: $(grep -m1 '^error' "$T/m4ctl.err")"; fi
done


# ════════════════════════════════════════════════════════════════════════════════════════════════
# C2-8 — WHAT THE MODE CHECKS (src/frontend/parse_expr.cyr `_bck_*`; the checker lex_pp.cyr
# `_bnd_finish`): a typed array `a[i]` against its exact N, a slice's reads and writes against its
# length, a `*T` subscript for a negative index only; `bounds: index N out of [0, LEN) at
# <file>:<line>` on stderr and exit 134; a constant index judged at compile time; `@unsafe` lexical.
# ════════════════════════════════════════════════════════════════════════════════════════════════
HAVE_WINE=0
if command -v wine > /dev/null 2>&1; then HAVE_WINE=1
else echo "  SKIP Vd / We: the PE legs — wine not installed"; skips=$((skips + 1)); fi
HAVE_QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then HAVE_QEMU=1
else echo "  SKIP Vb / Wc: the aarch64 legs — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
wine_run() {   # <dir> <exe> <stdout file> <stderr file> [arg]: run under the private prefix; sets got
    got=0
    (cd "$1" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "./$2" ${5:-} > "$3" 2> "$4") || got=$?
}
# The cross compilers, built once from this tree by the compiler under test.
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ] \
    && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> /dev/null && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" \
    || rm -f "$T/cc_cx" "$T/cxvm"
if [ "$HAVE_QEMU" -eq 1 ]; then
    "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
fi
# ok_line <row> <exit> <stderr file> <want line>: exit 134 and the stderr's one line is exactly <want>
# (wine's own `wine: created the configuration directory` notice on a fresh prefix set aside)
ok_line() {
    if [ "$2" -eq 134 ] && [ "$(tr -d '\r' < "$3" | grep -v '^wine: ')" = "$4" ]; then ok "$1: exit 134, \"$4\""
    else bad "$1: exit $2, stderr: $(tr -d '\r' < "$3" | head -2 | tr '\n' '|') (want 134 and \"$4\")"; fi
}

# ── V: the violation on every leg — x86 (plain, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx
# (cxvm), PE (wine): an array (its exact N), a `*T` (`[0, ...)`), a slice (its length), a file the
# entry includes (named by its include path) ─────────────────────────────────────────────────────
printf '#bounds\nfn f(i): i64 {\n    var a: u8[5];\n    a[i] = 1;\n    return 3;\n}\nsyscall(60, f(5));\n' > "$T/va.cyr"
printf '#bounds\nvar B: i64[2];\nfn f(i): i64 {\n    var p: *i32 = &B;\n    return p[i];\n}\nsyscall(60, f(0 - 4));\n' > "$T/vp.cyr"
printf '#bounds\ninclude "lib/slice.cyr"\nfn f(i): i64 {\n    var b: u8[4];\n    var s: [u8] = 0;\n    slice_set(&s, &b, 4);\n    return s[i];\n}\nsyscall(60, f(4));\n' > "$T/vs.cyr"
printf '# an included file\nvar VI: i16[3];\nfn vinc(i): i64 { VI[i] = 2; return 0; }\n' > "$T/vinc.cyr"
printf '#bounds\ninclude "vinc.cyr"\nsyscall(60, vinc(3));\n' > "$T/vi.cyr"
vleg() {   # <row> <name>: $T/<name>.cyr compiled in directory <dir> (its includes resolve there) <want line> <dir>
    s="$T/$2.cyr"; o="$T/$2"
    for mode in plain IR3 DCE1; do
        env_=""; lbl="${1}a: x86"
        [ "$mode" = IR3 ] && { env_="CYRIUS_IR=3"; lbl="${1}a: x86, CYRIUS_IR=3"; }
        [ "$mode" = DCE1 ] && { env_="CYRIUS_DCE=1"; lbl="${1}a: x86, CYRIUS_DCE=1"; }
        rc=0; (cd "$4" && env $env_ "$CC" < "$s" > "$o.$mode" 2> "$o.$mode.cerr") || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$o.$mode.cerr" | head -1)"; continue; fi
        chmod +x "$o.$mode"; got=0; timeout 10 "$o.$mode" > /dev/null 2> "$o.$mode.err" || got=$?
        ok_line "$lbl" "$got" "$o.$mode.err" "$3"
    done
    if [ "$HAVE_QEMU" -eq 1 ]; then
        if [ ! -x "$T/cc_a64" ]; then bad "${1}b: src/main_aarch64.cyr did not build"
        elif (cd "$4" && "$T/cc_a64" < "$s" > "$o.a64" 2> /dev/null) && [ -s "$o.a64" ]; then
            chmod +x "$o.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$2.a64" > /dev/null 2> "$o.a64.err") || got=$?
            ok_line "${1}b: aarch64 (qemu)" "$got" "$o.a64.err" "$3"
        else bad "${1}b: aarch64: did not compile"; fi
    fi
    if [ ! -x "$T/cc_cx" ]; then bad "${1}c: src/main_cx.cyr or programs/cxvm.cyr did not build"
    elif (cd "$4" && "$T/cc_cx" < "$s" > "$o.cyx" 2> /dev/null) && [ -s "$o.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$o.cyx" > /dev/null 2> "$o.cyx.err" || got=$?
        ok_line "${1}c: cx (cxvm)" "$got" "$o.cyx.err" "$3"
    else bad "${1}c: cx: did not compile"; fi
    if [ "$HAVE_WINE" -eq 1 ]; then
        if (cd "$4" && CYRIUS_TARGET_WIN=1 "$CC" < "$s" > "$o.exe" 2> /dev/null) && [ -s "$o.exe" ]; then
            wine_run "$T" "$2.exe" /dev/null "$o.exe.err"
            ok_line "${1}d: PE (wine)" "$got" "$o.exe.err" "$3"
        else bad "${1}d: PE: did not compile"; fi
    fi
}
vleg V1 va "bounds: index 5 out of [0, 5) at <source>:4" "$T"
vleg V2 vp "bounds: index -4 out of [0, ...) at <source>:5" "$T"
vleg V3 vs "bounds: index 4 out of [0, 4) at <source>:7" "$ROOT"
vleg V4 vi "bounds: index 3 out of [0, 3) at vinc.cyr:3" "$T"

# ── AG: agnos (an x86 ELF with its own numbers): the checker writes with agnos's write #1 and
# exits with agnos's exit #0. Run on THIS Linux host, #1 is write (the line appears) and #0 is
# read (it fails and returns), so the program goes on to its own `syscall(60, 5)` — exit 5; a
# checker that exited with 60 would exit 134 here. ─────────────────────────────────────────────
printf '#bounds\nfn f(i): i64 {\n    var a: u8[5];\n    a[i] = 1;\n    return 3;\n}\nvar r = f(5);\nsyscall(60, 5);\n' > "$T/ag.cyr"
rc=0; CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/ag.cyr" > "$T/ag.bin" 2> "$T/ag.cerr" || rc=$?
if [ "$rc" -ne 0 ]; then bad "AG: CYRIUS_TARGET_AGNOS=1 did not compile: $(grep '^error' "$T/ag.cerr" | head -1)"
else
    chmod +x "$T/ag.bin"; got=0; timeout 10 "$T/ag.bin" > /dev/null 2> "$T/ag.err" || got=$?
    if [ "$got" -eq 5 ] && [ "$(cat "$T/ag.err")" = "bounds: index 5 out of [0, 5) at <source>:4" ]; then
        ok "AG: agnos — the line through write #1, the exit through agnos's #0 (not Linux's 60)"
    else bad "AG: agnos: exit $got (want 5: the checker's exit must be agnos #0), stderr: $(head -1 "$T/ag.err")"; fi
fi

# ── W: the two value files on every leg ──────────────────────────────────────────────────────────
WI="$ROOT/tests/tcyr/crossos/bounds_mode_in_range.tcyr"
WV="$ROOT/tests/tcyr/crossos/bounds_mode_violation.tcyr"
for f in "$WI" "$WV"; do
    [ -f "$f" ] || { bad "W: $f missing"; continue; }
    b=$(basename "$f" .tcyr)
    rc=0; "$CC" < "$f" > "$T/$b.chk" 2> "$T/$b.chk.err" || rc=$?
    nw=$(grep -c '^warning\|^error' "$T/$b.chk.err" || true)
    if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "W0 $b: compiles with no warning"
    else bad "W0 $b: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/$b.chk.err" | head -2 | tr '\n' '|')"; fi
    rc=0; "$CC" --syntax-only < "$f" > /dev/null 2> "$T/$b.so.err" || rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$T/$b.so.err"; then ok "W0s $b: --syntax-only (cyrius lint) reports nothing"
    else bad "W0s $b: --syntax-only rc $rc: $(grep '^error\|^warning' "$T/$b.so.err" | head -1)"; fi
done
WANT_I=$(grep -oE '(assert_eq|assert)\(' "$WI" | wc -l)
WANT_V=$(grep -c 'trips("' "$WV")
if [ "$WANT_I" -lt 35 ]; then bad "W: only $WANT_I assertions derived from bounds_mode_in_range.tcyr (floor 35)"; fi
if [ "$WANT_V" -lt 20 ]; then bad "W: only $WANT_V violation children derived from bounds_mode_violation.tcyr (floor 20)"; fi
w_ok() {   # <label> <exit> <output file> <spawn: 1 = the violation group ran>
    if [ "$2" -eq 0 ] && tr -d '\r' < "$3" | grep -q ' passed, 0 failed'; then
        if [ "$4" -eq 1 ] && ! tr -d '\r' < "$3" | grep -q 'a violation prints its line and exits 134'; then bad "$1: the violation group did not run"
        else ok "$1: $(tr -d '\r' < "$3" | grep ' passed, 0 failed' | tail -1)"; fi
    else bad "$1: exit $2 $(tr -d '\r' < "$3" | grep -m3 'FAIL\|bounds:' | tr '\n' '|')"; fi
}
wlegs() {   # <file> <tag> <spawn 0|1>
    for mode in plain IR1 IR3 DCE1 SA0; do
        case $mode in
            plain) env_=""; lbl="W$2a: x86" ;;
            IR1) env_="CYRIUS_IR=1"; lbl="W$2a: x86, CYRIUS_IR=1" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="W$2a: x86, CYRIUS_IR=3" ;;
            DCE1) env_="CYRIUS_DCE=1"; lbl="W$2a: x86, CYRIUS_DCE=1" ;;
            SA0) env_="CYRIUS_STACK_ARRAYS=0"; lbl="W$2a: x86, CYRIUS_STACK_ARRAYS=0 (every local array in static storage)" ;;
        esac
        rc=0; env $env_ "$CC" < "$1" > "$T/w$2_$mode" 2> "$T/w$2_$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/w$2_$mode.err" | head -1)"; continue; fi
        chmod +x "$T/w$2_$mode"; got=0; (cd "$T" && timeout 120 "./w$2_$mode" > "w$2_$mode.out" 2>&1) || got=$?
        w_ok "$lbl" "$got" "$T/w$2_$mode.out" "$3"
    done
    if [ "$HAVE_QEMU" -eq 1 ]; then
        if [ ! -x "$T/cc_a64" ]; then bad "W$2b: src/main_aarch64.cyr did not build"
        elif "$T/cc_a64" < "$1" > "$T/w$2.a64" 2> /dev/null && [ -s "$T/w$2.a64" ]; then
            chmod +x "$T/w$2.a64"; got=0; (cd "$T" && timeout 120 qemu-aarch64 "./w$2.a64" nospawn > "w$2.a64.out" 2>&1) || got=$?
            w_ok "W$2b: aarch64 (qemu; nospawn — the violation is the V rows')" "$got" "$T/w$2.a64.out" 0
        else bad "W$2b: aarch64: did not compile"; fi
    fi
    if [ ! -x "$T/cc_cx" ]; then bad "W$2c: src/main_cx.cyr or programs/cxvm.cyr did not build"
    elif "$T/cc_cx" < "$1" > "$T/w$2.cyx" 2> /dev/null && [ -s "$T/w$2.cyx" ]; then
        got=0; timeout 120 "$T/cxvm" < "$T/w$2.cyx" > "$T/w$2.cyx.out" 2>&1 || got=$?
        w_ok "W$2c: cx (cxvm; no spawn — the violation is the V rows')" "$got" "$T/w$2.cyx.out" 0
    else bad "W$2c: cx: did not compile"; fi
    if [ "$HAVE_WINE" -eq 1 ]; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$1" > "$T/w$2.exe" 2> /dev/null && [ -s "$T/w$2.exe" ]; then
            wine_run "$T" "w$2.exe" "$T/w$2.exe.out" "$T/w$2.exe.serr"
            cat "$T/w$2.exe.serr" >> "$T/w$2.exe.out"
            w_ok "W$2d: PE (wine)" "$got" "$T/w$2.exe.out" "$3"
        else bad "W$2d: PE: did not compile"; fi
    fi
}
wlegs "$WI" I 0
wlegs "$WV" V 1

# ── K: the constant rule — an index of literals, `+ - *`, parentheses and integer consts / enum
# constants is judged at compile time: out of range a warning in every mode, an ERROR under the mode
# outside `@unsafe`; in range no run-time check at all ──────────────────────────────────────────────
KA='const K = 5;\nenum E { E0, E1, E9 = 9 }\nfn f(): i64 {\n    var a: u8[5];\n'
KZ='    return 0;\n}\nsyscall(60, f());\n'
KW="index 5 is out of range [0, 5) for 'a' (an error under the bounds-checked mode)"
kw() {   # <row> <body> <want warning> [env]: compiles (rc 0) with exactly one warning line holding <want>
    printf "$KA%b$KZ" "$2" > "$T/k$rows.cyr"
    rc=0; env ${4:-X=1} "$CC" < "$T/k$rows.cyr" > /dev/null 2> "$T/k$rows.err" || rc=$?
    nw=$(grep -c '^warning' "$T/k$rows.err" || true)
    if [ "$rc" -eq 0 ] && [ "$nw" -eq 1 ] && grep '^warning' "$T/k$rows.err" | grep -qF -- "$3"; then ok "$1: $(grep '^warning' "$T/k$rows.err" | cut -c1-120)"
    else bad "$1: rc $rc, $nw warning(s): $(grep '^warning\|^error' "$T/k$rows.err" | head -2 | tr '\n' '|') (want one: $3)"; fi
}
ke() {   # <row> <body> <want error> [env]: refused (rc != 0) with exactly one error line holding <want>
    printf "$KA%b$KZ" "$2" > "$T/k$rows.cyr"
    rc=0; env ${4:-X=1} "$CC" < "$T/k$rows.cyr" > /dev/null 2> "$T/k$rows.err" || rc=$?
    ne=$(grep -c '^error' "$T/k$rows.err" || true)
    if [ "$rc" -ne 0 ] && [ "$ne" -eq 1 ] && grep '^error' "$T/k$rows.err" | grep -qF -- "$3"; then ok "$1: $(grep '^error' "$T/k$rows.err" | cut -c1-120)"
    else bad "$1: rc $rc, $ne error(s): $(grep '^warning\|^error' "$T/k$rows.err" | head -2 | tr '\n' '|') (want one: $3)"; fi
}
kn() {   # <row> <body> [env]: compiles with no diagnostic at all
    printf "$KA%b$KZ" "$2" > "$T/k$rows.cyr"
    rc=0; env ${3:-X=1} "$CC" < "$T/k$rows.cyr" > /dev/null 2> "$T/k$rows.err" || rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/k$rows.err"; then ok "$1"
    else bad "$1: rc $rc: $(grep '^warning\|^error' "$T/k$rows.err" | head -2 | tr '\n' '|')"; fi
}
kw "K1a a[K] (const K = 5) on u8[5], mode off: a warning" '    a[K] = 1;\n' "$KW"
ke "K1b ... under the mode: an error" '    a[K] = 1;\n' "index 5 is out of range [0, 5) for 'a' (the bounds-checked mode" CYRIUS_BOUNDS=1
kw "K1c ... under the mode inside @unsafe: a warning" '    @unsafe { a[K] = 1; }\n' "$KW" CYRIUS_BOUNDS=1
kw "K1d a[(K - 1) * 2]: the evaluator's value (8)" '    var x = a[(K - 1) * 2];\n' "index 8 is out of range [0, 5) for 'a'"
kw "K1e a[E9 - 4] (an enum constant)" '    a[E9 - 4] += 1;\n' "$KW"
kw "K1f p[0 - 1] on a *u8: negative" '    var p: *u8 = &a;\n    p[0 - 1] = 1;\n' "index -1 is negative for 'p' (an error under the bounds-checked mode)"
kw "K1g a[-1] (unary minus)" '    var y = a[-1];\n' "index -1 is out of range [0, 5) for 'a'"
kn "K2a a[4], a[K - 1], a[E9 - 5], p[7]: in range, no diagnostic" '    var p: *u8 = &a;\n    a[4] = 1;\n    a[K - 1] = a[E9 - 5];\n    p[7] = 1;\n'
kn "K2b a local K shadows the const: a variable, no constant (run-time check)" '    var K = 7;\n    var y = a[K - 7];\n    @unsafe { y = a[K]; }\n' CYRIUS_BOUNDS=1
kn "K2c a[K / 1], a[K << 0]: not the rule's shapes (run-time checked)" '    var y = a[K / 1] + a[K << 0];\n' CYRIUS_BOUNDS=1
printf 'include "lib/slice.cyr"\nfn f(): i64 {\n    var s: [u8] = 0;\n    var y = s[3] + s[0];\n    return 0;\n}\nsyscall(60, f());\n' > "$T/k2d.cyr"
rc=0; CYRIUS_BOUNDS=1 CYRIUS_DCE_VERBOSE=1 "$CC" < "$T/k2d.cyr" > /dev/null 2> "$T/k2d.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/k2d.err" && ! grep -qx '  dead: __cyrius_bounds_chks' "$T/k2d.err"; then ok "K2d a slice's s[3], s[0]: no diagnostic, and still checked at run time (its length is unknown at compile time)"
else bad "K2d: rc $rc: $(grep '^warning\|^error\|dead: __cyrius_bounds_chks' "$T/k2d.err" | head -2 | tr '\n' '|')"; fi
printf 'fn g<T>(): i64 {\n    var a: T[2];\n    return a[2];\n}\nvar x = g<i32>() + g<i64>() + g<i16>();\nsyscall(60, 0);\n' > "$T/kg.cyr"
rc=0; "$CC" < "$T/kg.cyr" > /dev/null 2> "$T/kg.err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(grep -c '^warning' "$T/kg.err")" -eq 1 ]; then ok "K3 a generic's T[2] a[2], three instances: ONE warning (once per token)"
else bad "K3: rc $rc, $(grep -c '^warning' "$T/kg.err") warning(s) (want 1)"; fi
printf "$KA%b$KZ" '    a[K] = 1;\n' > "$T/ks.cyr"
rc=0; CYRIUS_BOUNDS=1 "$CC" --syntax-only < "$T/ks.cyr" > /dev/null 2> "$T/ks.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/ks.err"; then ok "K4 --syntax-only (cyrius lint) is silent about the constant rule"
else bad "K4 --syntax-only: rc $rc: $(head -1 "$T/ks.err")"; fi
# K5: an in-range constant emits NO check — the checker is unreachable (CYRIUS_DCE_VERBOSE lists it
# dead); a run-time index in the same program reaches it.
printf 'fn f(i): i64 {\n    var a: u8[5];\n    var p: *i32 = &a;\n    a[4] = 5;\n    a[0] = a[4] + p[1];\n    return a[0];\n}\nsyscall(60, f(1));\n' > "$T/k5.cyr"
CYRIUS_BOUNDS=1 CYRIUS_DCE_VERBOSE=1 "$CC" < "$T/k5.cyr" > /dev/null 2> "$T/k5.err" || true
if grep -qx '  dead: __cyrius_bounds_chk' "$T/k5.err"; then ok "K5a in-range constants under the mode: no call (__cyrius_bounds_chk unreachable)"
else bad "K5a: __cyrius_bounds_chk is reachable from a program whose every index is an in-range constant"; fi
sed 's/a\[0\] = a\[4\]/a[i] = a[4]/' "$T/k5.cyr" > "$T/k5b.cyr"
CYRIUS_BOUNDS=1 CYRIUS_DCE_VERBOSE=1 "$CC" < "$T/k5b.cyr" > /dev/null 2> "$T/k5b.err" || true
if grep -qx '  dead: __cyrius_bounds_chks' "$T/k5b.err" && ! grep -qx '  dead: __cyrius_bounds_chk' "$T/k5b.err"; then ok "K5b the control: a run-time index a[i] reaches __cyrius_bounds_chk (the slice checker stays unreachable)"
else bad "K5b: the dead list: $(grep 'dead:' "$T/k5b.err" | tr '\n' '|')"; fi

# ── OFF: with the mode off not a byte of the checker exists — every subscript-using .tcyr compiles
# with no `bounds: index` bytes in it, and `CYRIUS_BOUNDS=0` / unset are byte-identical ───────────
noff=0
for f in $(grep -rlE '[A-Za-z0-9_)]\[[^]]' tests/tcyr --include='*.tcyr' | grep -v 'bounds_mode_' | sort); do
    noff=$((noff + 1))
    rc=0; "$CC" < "$f" > "$T/off.a" 2> /dev/null || rc=$?
    [ "$rc" -eq 0 ] || continue
    CYRIUS_BOUNDS=0 "$CC" < "$f" > "$T/off.b" 2> /dev/null || true
    if ! cmp -s "$T/off.a" "$T/off.b"; then bad "OFF: $f: CYRIUS_BOUNDS=0 and unset differ"; continue; fi
    if grep -q 'bounds: index' "$T/off.a"; then bad "OFF: $f: the checker's text is in a mode-off binary"; fi
done
if [ "$noff" -lt 30 ]; then bad "OFF: only $noff subscript-using .tcyr found (floor 30)"
else ok "OFF: $noff subscript-using .tcyr: mode off holds no checker, unset == CYRIUS_BOUNDS=0"; fi

# ── N: a redeclared global array (one 8-byte storage, folded) is the FIRST declaration's array — its
# N (C2-3b, K15): under the mode `A[5]` trips against [0, 5) after `var A: u8[6];`; index 4 runs ──
printf '#bounds\nvar A: u8[5];\nvar A: u8[6];\nfn f(i): i64 {\n    A[i] = 1;\n    return A[4];\n}\nsyscall(60, f(I));\n' > "$T/n1.tpl"
sed 's/f(I)/f(4)/' "$T/n1.tpl" > "$T/n1.cyr"
sed 's/f(I)/f(5)/' "$T/n1.tpl" > "$T/n1b.cyr"
xc "N1a a folded u8[5] / u8[6] global: index 4 in range" 1 n1.cyr
cc n1b n1b.cyr
if [ "$RC" != 0 ]; then bad "N1b: did not compile: $(grep -m1 '^error' "$T/n1b.err")"
else chmod +x "$T/n1b.bin"; got=0; "$T/n1b.bin" > /dev/null 2> "$T/n1b.rerr" || got=$?; ok_line "N1b ... index 5: the first declaration's N" "$got" "$T/n1b.rerr" "bounds: index 5 out of [0, 5) at <source>:5"; fi

# ── R14 / DCE / SP / PURE / EFF / AS / T2 ─────────────────────────────────────────────────────────
printf '#bounds\nvar G: u8[4];\nvar K = 2;\n#naked\nfn isr(): i64 {\n    G[K] = 1;\n    asm { 0xC3; }\n}\nsyscall(60, 3);\n' > "$T/r14.cyr"
xe "R14 a checked subscript in a #naked fn under the mode" "the bounds check is a call, which a #naked fn cannot make - wrap the access in @unsafe { }" r14.cyr
sed 's/    G\[K\] = 1;/    @unsafe { G[K] = 1; }/' "$T/r14.cyr" > "$T/r14b.cyr"
cc r14b r14b.cyr
if [ "$RC" = 0 ]; then ok "R14b the same access inside @unsafe compiles"; else bad "R14b: rc $RC: $(grep -m1 '^error' "$T/r14b.err")"; fi
sed '1d' "$T/r14.cyr" > "$T/r14c.cyr"
cc r14c r14c.cyr
if [ "$RC" = 0 ]; then ok "R14c the same #naked fn with the mode off compiles"; else bad "R14c: rc $RC: $(grep -m1 '^error' "$T/r14c.err")"; fi

printf 'fn f(i): i64 {\n    var a: u8[5];\n    a[4] = 5;\n    return a[4];\n}\nsyscall(60, f(1));\n' > "$T/dce.cyr"
CYRIUS_BOUNDS=1 CYRIUS_DCE=1 CYRIUS_DCE_VERBOSE=1 "$CC" < "$T/dce.cyr" > "$T/dce.bin" 2> "$T/dce.err" || true
if [ "$(grep -c '^  dead: __cyrius_bounds_' "$T/dce.err")" -eq 6 ]; then ok "DCE1 CYRIUS_DCE=1 with no check site: the six checker fns are eliminated"
else bad "DCE1: $(grep -c '^  dead: __cyrius_bounds_' "$T/dce.err") checker fns dead (want 6)"; fi
xc "DCE2 CYRIUS_DCE=1 with a check site: the violation still trips" 134 va.cyr CYRIUS_DCE=1

awk 'BEGIN { print "#bounds"; print "var A: u8[3];"; print "fn f(i): i64 {"; print "    var s = 0;"; for (k = 0; k < 2000; k++) print "    s = s + A[i];"; print "    return s + A[i + 3];"; print "}"; print "syscall(60, f(0));" }' > "$T/sp.cyr"
cc sp sp.cyr
if [ "$RC" != 0 ]; then bad "SP: 2,001 check sites did not compile: $(grep -m1 '^error' "$T/sp.err")"
else
    chmod +x "$T/sp.bin"; got=0; "$T/sp.bin" > /dev/null 2> "$T/sp.rerr" || got=$?
    ok_line "SP 2,001 check sites in one file (one interned file name): the last one" "$got" "$T/sp.rerr" "bounds: index 3 out of [0, 3) at <source>:2005"
fi

printf 'var A: u8[4];\n#pure\nfn pk(i): i64 { return A[i]; }\nfn main(): i64 { return pk(3); }\nsyscall(60, main());\n' > "$T/pure.cyr"
cc pure0 pure.cyr
cc pure1 pure.cyr CYRIUS_BOUNDS=1
if [ "$RC" = 0 ] && ! grep -q '^warning' "$T/pure1.err" && ! grep -q '^warning' "$T/pure0.err"; then ok "PURE a checked subscript in a #pure fn: no effect warning under the mode (the checker call is the compiler's)"
else bad "PURE: rc $RC: $(grep -m1 '^warning\|^error' "$T/pure1.err")"; fi

# EFF: a by-value struct argument beside a later argument that subscripts: `[ ]` writes nothing (a
# check reads or exits), so no copy is forced and the callee still reads the struct as written.
printf 'struct B { a; b; c; }\nvar A: i32[3];\nfn rd(s: B, x): i64 { return s.a * 100 + x; }\nfn f(i): i64 {\n    var s = B { 7, 0, 0 };\n    A[i] = 5;\n    return rd(s, A[i]);\n}\nsyscall(60, f(2) - 700);\n' > "$T/eff.cyr"
xc "EFF rd(s, A[i]) with s by value, mode off" 5 eff.cyr
xc "EFF ... under the mode: the same value" 5 eff.cyr CYRIUS_BOUNDS=1

# T2: `return f(a[i]);` — a tail call whose argument calls the checker
printf 'fn g(x): i64 { return x + 1; }\nfn f(i): i64 {\n    var a: i16[4];\n    a[3] = 40;\n    return g(a[i]);\n}\nsyscall(60, f(3));\n' > "$T/t2.cyr"
xc "T2a return g(a[i]); (a tail call) in range under the mode" 41 t2.cyr CYRIUS_BOUNDS=1
sed 's/syscall(60, f(3));/syscall(60, f(4));/' "$T/t2.cyr" > "$T/t2b.cyr"
cc t2b t2b.cyr CYRIUS_BOUNDS=1
if [ "$RC" != 0 ]; then bad "T2b: did not compile"
else chmod +x "$T/t2b.bin"; got=0; "$T/t2b.bin" > /dev/null 2> "$T/t2b.rerr" || got=$?; ok_line "T2b ... out of range: the argument's check trips before the jump" "$got" "$T/t2b.rerr" "bounds: index 4 out of [0, 4) at <source>:5"; fi

# AS: a suspending `async fn` (CYRIUS_ASYNC=1) — a subscript in its heap frame across an await
AS='#bounds\ninclude "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nfn nopark(): i64 { return 0; }\nasync fn steps(i): i64 {\n    var a: u8[5];\n    a[i] = 7;\n    var s1 = await nopark();\n    return a[i];\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(IDX);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    syscall(60, future_force(C));\n    return 0;\n}\nvar e = main();\n'
for k in 4 5; do
    printf "$(printf '%s' "$AS" | sed "s/IDX/$k/")" > "$T/as$k.cyr"
    rc=0; CYRIUS_ASYNC=1 "$CC" < "$T/as$k.cyr" > "$T/as$k.bin" 2> "$T/as$k.cerr" || rc=$?   # from $ROOT: lib/ resolves
    if [ "$rc" -ne 0 ]; then bad "AS (index $k): did not compile: $(grep -m1 '^error' "$T/as$k.cerr")"; continue; fi
    chmod +x "$T/as$k.bin"; got=0; "$T/as$k.bin" > /dev/null 2> "$T/as$k.rerr" || got=$?
    if [ "$k" = 4 ]; then
        if [ "$got" -eq 7 ]; then ok "AS1 a subscript in a suspending async fn (CYRIUS_ASYNC=1), index 4 of u8[5], across an await: exit 7"
        else bad "AS1: exit $got (want 7): $(head -1 "$T/as$k.rerr")"; fi
    else ok_line "AS2 ... index 5: trips in the async frame" "$got" "$T/as$k.rerr" "bounds: index 5 out of [0, 5) at <source>:11"; fi
done

# ════════════════════════════════════════════════════════════════════════════════════════════════
# C2-9 — TOOLS AND THE GUIDE: the lane's new value files are canonically formatted and lint clean;
# the slice store's helper stays private (api-surface); every verb that takes --bounds says so in its
# help; the guide's bounds-mode example prints the line it states, and the texts it quotes are the
# compiler's. Each tool is built HERE from programs/ with $CC (never a stale build/ copy).
# ════════════════════════════════════════════════════════════════════════════════════════════════
TLF="tests/tcyr/crossos/pointer_subscript_values.tcyr tests/tcyr/crossos/pointer_subscript_bases.tcyr
tests/tcyr/crossos/deref_element_width.tcyr tests/tcyr/crossos/slice_read_left_operand.tcyr
tests/tcyr/crossos/slice_signed_read.tcyr tests/tcyr/crossos/slice_subscript_write.tcyr
tests/tcyr/crossos/bounds_mode_in_range.tcyr tests/tcyr/crossos/bounds_mode_violation.tcyr"
for t in cyrfmt cyrlint cyrius_api_surface; do
    "$CC" < "programs/$t.cyr" > "$T/$t" 2> /dev/null && [ -s "$T/$t" ] && chmod +x "$T/$t" || { rm -f "$T/$t"; bad "TL: programs/$t.cyr does not build"; }
done
# TL0: the checkers can fail — a mis-indented copy is rejected by cyrfmt --check and a 121-column
# line is flagged by cyrlint (a broken checker would call every file clean).
printf 'fn f(): i64 {\nreturn 1;\n}\n' > "$T/tl_bad_fmt.cyr"
printf 'fn f(): i64 {\n    return 1;   # %s\n}\n' "$(printf '%0110d' 0)" > "$T/tl_bad_lint.cyr"
if [ -x "$T/cyrfmt" ] && ! "$T/cyrfmt" --check "$T/tl_bad_fmt.cyr" > /dev/null 2>&1; then ok "TL0a cyrfmt --check rejects a mis-indented file"
else bad "TL0a cyrfmt --check accepted a mis-indented file (the format rows would prove nothing)"; fi
if [ -x "$T/cyrlint" ] && "$T/cyrlint" "$T/tl_bad_lint.cyr" 2>&1 | grep -q 'exceeds 120'; then ok "TL0b cyrlint flags a line over 120 columns"
else bad "TL0b cyrlint did not flag a 121-column line (the lint rows would prove nothing)"; fi
ntl=0
for f in $TLF; do
    ntl=$((ntl + 1))
    if [ ! -f "$f" ]; then bad "TL1 $f is missing"; continue; fi
    if [ -x "$T/cyrfmt" ] && "$T/cyrfmt" --check "$f" > "$T/tl.fmt" 2>&1; then ok "TL1a $f: cyrfmt --check clean"
    else bad "TL1a $f: cyrfmt --check: $(head -2 "$T/tl.fmt" | tr '\n' '|')"; fi
    rc=0; [ -x "$T/cyrlint" ] && "$T/cyrlint" "$f" > "$T/tl.lint" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && grep -qx '0 warnings' "$T/tl.lint"; then ok "TL1b $f: cyrlint 0 warnings"
    else bad "TL1b $f: cyrlint rc $rc: $(grep -m2 'warn\|error' "$T/tl.lint" | tr '\n' '|')"; fi
done
[ "$ntl" -ge 8 ] || bad "TL1: only $ntl lane value files listed (floor 8)"
# TL2: api-surface — lib/slice.cyr's public surface is the snapshot's, so the C2-6a store helper
# `_slice_idx_addr` (and anything the compiler calls) stays private.
if [ -x "$T/cyrius_api_surface" ]; then
    rc=0; "$T/cyrius_api_surface" --update --snapshot="$T/api.snap" > "$T/api.out" 2>&1 || rc=$?
    grep '^slice::' "$T/api.snap" > "$T/api.slice.new" 2> /dev/null || true
    grep '^slice::' docs/api-surface.snapshot > "$T/api.slice.old" || true
    nsl=$(grep -c . "$T/api.slice.old" || true)
    if [ "$rc" -ne 0 ] || [ "$nsl" -lt 20 ]; then bad "TL2 api-surface: rc $rc, $nsl slice rows in the snapshot (floor 20): $(tail -1 "$T/api.out")"
    elif cmp -s "$T/api.slice.old" "$T/api.slice.new" && ! grep -q 'slice_idx_addr' "$T/api.snap"; then ok "TL2 lib/slice.cyr's public surface is the snapshot's ($nsl fns); _slice_idx_addr is private"
    else bad "TL2 lib/slice.cyr's public surface changed: $(diff "$T/api.slice.old" "$T/api.slice.new" | grep '^[<>]' | head -3 | tr '\n' '|')"; fi
fi
# TL3: the help — every verb that takes --bounds names it (the hand-written rows, not only the
# generated usage line); bench takes no --bounds and says nothing of it.
cy() { (cd "$T/tlcwd" && env -u CYRIUS_BOUNDS HOME="$T/h" CYRIUS_HOME="$T/home" CYRIUS_RESOLVED=1 "$T/cyrius" "$@") < /dev/null 2>&1; }
mkdir -p "$T/h" "$T/tlcwd"
for v in build run test fuzz; do
    if cy "$v" --help | grep -v '^Usage:' | grep -q -- '--bounds.*bounds-checked mode'; then ok "TL3 cyrius $v --help describes --bounds"
    else bad "TL3 cyrius $v --help has no --bounds row"; fi
done
if cy bench --help | grep -q -- '--bounds'; then bad "TL3 cyrius bench --help mentions --bounds (bench does not take it)"
else ok "TL3 cyrius bench --help: no --bounds"; fi
cy --help > "$T/tl.help"
for v in build run test fuzz; do
    if grep -E "^  $v " "$T/tl.help" | grep -q -- '\[--bounds\]'; then ok "TL3 cyrius --help: the $v line shows [--bounds]"
    else bad "TL3 cyrius --help: the $v line lacks [--bounds]"; fi
done
# TL4: the guide (docs/guides/cyrius-guide.md, § The bounds-checked mode): its first example
# compiles, prints exactly the `bounds:` line the text fence after it states and exits 134; with
# CYRIUS_BOUNDS=0 it is silent and exits 0. The constant-rule warning and the #naked refusal it
# quotes are the compiler's texts.
GUIDE=docs/guides/cyrius-guide.md
awk '/^## The bounds-checked mode \(6\.7\.8\)/ { s = 1; next } s && /^## / { exit } s' "$GUIDE" > "$T/tl.sec"
awk '/^```$/ && !inb { inb = 1; next } inb && /^```/ { exit } inb { print }' "$T/tl.sec" > "$T/tl_ex.cyr"
TLW=$(awk '/^```text$/ { t = 1; next } t && /^```/ { exit } t' "$T/tl.sec" | sed -n 's/^\(bounds: index [^<]*<source>:[0-9]*\).*/\1/p' | head -1)
if [ "$(grep -c . "$T/tl.sec")" -lt 40 ] || ! grep -q '^#bounds$' "$T/tl_ex.cyr" || [ -z "$TLW" ]; then
    bad "TL4 the guide's bounds-mode section, its first example or its stated line was not found (section $(grep -c . "$T/tl.sec") lines)"
else
    rc=0; (cd "$T" && "$CC" < tl_ex.cyr > tl_ex.bin 2> tl_ex.cerr) || rc=$?
    if [ "$rc" -ne 0 ]; then bad "TL4a the guide's example does not compile: $(grep -m1 '^error' "$T/tl_ex.cerr")"
    else chmod +x "$T/tl_ex.bin"; got=0; "$T/tl_ex.bin" > /dev/null 2> "$T/tl_ex.err" || got=$?; ok_line "TL4a the guide's example states its own violation line" "$got" "$T/tl_ex.err" "$TLW"; fi
    rc=0; (cd "$T" && CYRIUS_BOUNDS=0 "$CC" < tl_ex.cyr > tl_ex0.bin 2> /dev/null) || rc=$?
    chmod +x "$T/tl_ex0.bin" 2> /dev/null; got=0; "$T/tl_ex0.bin" > /dev/null 2> "$T/tl_ex0.err" || got=$?
    if [ "$rc" -eq 0 ] && [ "$got" -eq 0 ] && [ ! -s "$T/tl_ex0.err" ]; then ok "TL4b ... with CYRIUS_BOUNDS=0: silent, exit 0 (as the guide says)"
    else bad "TL4b the example with the mode off: rc $rc, exit $got, stderr: $(head -1 "$T/tl_ex0.err")"; fi
fi
TLK=$(grep -o "^warning:<source>:[0-9]*:[0-9]*: index 5 is out of range .*" "$T/tl.sec" | sed 's/^warning:<source>:[0-9]*:[0-9]*: //' | head -1)
printf 'const K = 5;\nfn f(): i64 {\n    var a: u8[5];\n    a[K] = 1;\n    return 0;\n}\nsyscall(60, f());\n' > "$T/tl_k.cyr"
"$CC" < "$T/tl_k.cyr" > /dev/null 2> "$T/tl_k.err" || true
if [ -n "$TLK" ] && grep '^warning' "$T/tl_k.err" | sed 's/^warning:<source>:[0-9]*:[0-9]*: //' | grep -qxF -- "$TLK"; then ok "TL4c the constant-rule warning the guide quotes is the compiler's"
else bad "TL4c the guide quotes '$TLK'; the compiler says: $(grep -m1 '^warning' "$T/tl_k.err")"; fi
TLN=$(grep -o '(`the bounds check is a call[^`]*`)' "$T/tl.sec" | sed 's/^(`//; s/`)$//' | head -1)
rc=0; "$CC" < "$T/r14.cyr" > /dev/null 2> "$T/tl_r14.err" || rc=$?
if [ -n "$TLN" ] && [ "$rc" -ne 0 ] && grep '^error' "$T/tl_r14.err" | grep -qF -- "$TLN"; then ok "TL4d the #naked refusal the guide quotes is the compiler's"
else bad "TL4d the guide quotes '$TLN'; the compiler says: $(grep -m1 '^error' "$T/tl_r14.err")"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G: $fails of $rows row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed ($rows rows; exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G ($rows rows: #bounds honoured only in the entry's leading block and refused by name everywhere else; CYRIUS_BOUNDS 1 / 0 / empty / refused; the environment beats the line; kernel / EFI / shared / object refused under the mode; the check — exact N, slices, *T negative only, the message and exit 134 on x86 / IR=3 / DCE / aarch64 / cx / PE / agnos; the constant rule; @unsafe; #naked; mode off holds no checker; the tools clean on the lane's files and the guide's example and quoted texts the compiler's)"
exit 0
