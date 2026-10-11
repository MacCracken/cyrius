#!/bin/sh
# tests/gates/frontend/bounds_mode_checked.sh — 6.7.8 (C2-7)
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
# (What the mode CHECKS lands in C2-8; this gate is the switch. cbt's rungs — --bounds, [build]
# bounds, what compile() hands cycc — are build_config_precedence.sh's; every fork's env read and
# line are fork_flag_parity.sh's `bounds` rows.)
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
#   E4  the five self-build scripts (scripts/check.sh, release-gate.sh, seed-derive-cycc.sh,
#       version-bump.sh, bootstrap/bootstrap.sh) unset CYRIUS_BOUNDS before their first build: an
#       inherited CYRIUS_BOUNDS=1 must not switch the mode on in a self-build
#   M4  the mode with `kernel;`, CYRIUS_KERNEL=1 (a bare-metal --target), `shared;`, `object;`,
#       CYRIUS_TARGET_EFI=1 -> refused by name; each control (the same build, mode off) compiles
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
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=bounds_mode_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT" || exit 1
unset CYRIUS_BOUNDS
fails=0
rows=0
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
for s in scripts/check.sh scripts/release-gate.sh scripts/seed-derive-cycc.sh scripts/version-bump.sh bootstrap/bootstrap.sh; do
    u=$(grep -nE '^[[:space:]]*unset([[:space:]]+[A-Z_]+)*[[:space:]]+CYRIUS_BOUNDS([[:space:]]|$)' "$s" | head -1 | cut -d: -f1 || true)
    b=$(grep -nE 'src/main\.cyr' "$s" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1 || true)
    if [ -z "$u" ]; then bad "E4 $s does not unset CYRIUS_BOUNDS (an inherited CYRIUS_BOUNDS=1 would switch the mode on in its self-build)"
    elif [ -n "$b" ] && [ "$u" -gt "$b" ]; then bad "E4 $s unsets CYRIUS_BOUNDS at line $u, after its first build line $b"
    else ok "E4 $s unsets CYRIUS_BOUNDS (line $u) before it builds"; fi
done

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

if [ "$fails" -ne 0 ]; then echo "FAIL: $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS: $G ($rows rows: #bounds honoured only in the entry's leading block and refused by name everywhere else; CYRIUS_BOUNDS 1 / 0 / empty / refused; the environment beats the line; kernel / EFI / shared / object refused under the mode)"
exit 0
