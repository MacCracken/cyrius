#!/bin/sh
# target_selectors_exclusive.sh — 6.7.12 (the tools lane). ONE emit target per run: two of
# `--aarch64`, `--win`, `--agnos` and `--target=<v>` are refused by name (rc 1, nothing resolved,
# compiled or written); `--aarch64 --target=aarch64-bare-metal-elf`, the one consistent pair, builds
# the aarch64 bare-metal image exactly as the --target alone does (the user's decision D20,
# 2026-10-15).
#
# WHY (issues/2026-10-12-combined-target-flags-silently-resolved.md): the four selectors were
# independent switches, each read by whatever consumer cared about it, and every pair exited 0
# with an OK — `--win --aarch64` / `--agnos --aarch64` wrote the plain aarch64 ELF, `--win --agnos`
# a PE matching neither, `--win --target=x86_64-bare-metal-elf` a PE plus an x86 kernel line,
# `--aarch64 --target=x86_64-bare-metal-elf` an aarch64 ELF plus the x86 kernel line,
# `--win --target=cx` the plain .cyx, and `--aarch64 --target=js t.ts t.js` an aarch64 ELF named
# t.js — its child, cycc_aarch64, ignores `--emit-js` and reads stdin, so on a terminal it blocked
# for ever. The fix: cbt/cli_args.cyr `_cli_targets_exclusive` at the end of `_cli_apply_target`
# (before `_auto_deps`); `_emit_js` and its caller refuse unless the compiler they exec is the host
# cycc (`_js_cc_is_host`); the kernel line follows the compiler that ran.
#
# ROWS (the CLI built from cbt/ by build/cycc, with this tree's cycc / cycc_aarch64 / cycc_cx beside
# it; a throwaway HOME / CYRIUS_HOME; stdin closed unless said)
#   P1-P10  each pair (and two triples) rc 1, the exact `error: <A> and <B> select two emit
#           targets; pass one` line naming them in the order given, no output file, no OK
#   J       `--aarch64 --target=js t.ts t.js` with a stdin that would block (a FIFO held open):
#           rc 1 inside the timeout, the named error, no t.js
#   V       the rule is the CLI's, not build's: `cyrius run --win --aarch64 hello.cyr` rc 1, named,
#           the program not run
#   S1-S7   each single selector builds what it did: --aarch64 an aarch64 ELF (e_machine 0xb7),
#           --win an MZ image, --agnos an x86_64 ELF (0x3e), --target=cx a CYX image,
#           --target=x86_64-bare-metal-elf an x86_64 ELF and the x86 kernel line,
#           --target=aarch64-bare-metal-elf an aarch64 ELF and the aarch64 kernel line;
#           `--win --win` (a bool repeated) == `--win`
#   C       `--aarch64 --target=aarch64-bare-metal-elf` rc 0, byte-identical to the --target alone,
#           the aarch64 kernel line
#   Q       (qemu-aarch64) the --aarch64 single runs and exits 7; a named SKIP without qemu
#
# MUTATION LEDGER (6.7.12) — each a scratch copy of the tree (git archive + the mutant) through
# this gate:
#   M1  the `_cli_targets_exclusive()` call dropped                     RED P1-P10, J, V
#       (J: rc 1 inside the timeout, no t.js, but the js arm's own refusal — `_js_cc_is_host`
#       held; `--aarch64 --target=x86_64-bare-metal-elf` wrote its aarch64 ELF with the aarch64
#       kernel line — the line now follows the compiler that ran)
#   M2  M1 plus `_js_cc_is_host` always 1 (the 6.7.11 js arm)           RED P1-P10, J (t.js an
#       aarch64 ELF, rc 0), V
#   M3  the consistent pair refused too (no `a64_named` exception)      RED C
set -u
G=target_selectors_exclusive
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $G — needs timeout(1)"; exit 1; }
command -v mkfifo > /dev/null 2>&1 || { echo "FAIL: $G — needs mkfifo(1)"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'exec 3>&- 2> /dev/null; rm -rf "$W"' EXIT
FAIL=0
SKIPS=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
mkdir -p "$W/bin" "$W/p" "$W/h" "$W/ch"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/b.err" || { echo "FAIL: $G: cbt/cyrius.cyr does not build"; tail -3 "$W/b.err"; exit 1; }
[ "$(wc -c < "$W/bin/cyrius")" -ge 20000 ] || { echo "FAIL: $G: cbt/cyrius.cyr built a $(wc -c < "$W/bin/cyrius")-byte binary"; exit 1; }
"$CC" < src/main_aarch64.cyr > "$W/bin/cycc_aarch64" 2> "$W/b.err" && [ -s "$W/bin/cycc_aarch64" ] || { echo "FAIL: $G: src/main_aarch64.cyr does not build"; tail -3 "$W/b.err"; exit 1; }
"$CC" < src/main_cx.cyr > "$W/bin/cycc_cx" 2> "$W/b.err" && [ -s "$W/bin/cycc_cx" ] || { echo "FAIL: $G: src/main_cx.cyr does not build"; tail -3 "$W/b.err"; exit 1; }
cp "$CC" "$W/bin/cycc"   # the CLI takes the compilers beside it (v6.5.42)
chmod +x "$W/bin/cyrius" "$W/bin/cycc" "$W/bin/cycc_aarch64" "$W/bin/cycc_cx"
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$W/p/hello.cyr"
printf 'const x: number = 7;\nconsole.log(x);\n' > "$W/p/t.ts"

# cy <args...> — in the project dir; stdout+stderr to $W/out, exit in RC
cy() { RC=0; ( cd "$W/p" && HOME="$W/h" CYRIUS_HOME="$W/ch" "$W/bin/cyrius" "$@" ) > "$W/out" 2>&1 < /dev/null || RC=$?; }
show() { sed 's/^/      /' "$W/out" | head -4; }
hexat() { od -An -tx1 -j "$2" -N "$3" "$1" 2> /dev/null | tr -d ' \n'; }

# ── P: the pairs ──
np=0
# pair <row> <want error tail> <selectors...>
pair() {
    row=$1; want=$2; shift 2
    rm -f "$W/p/o"
    cy build "$@" hello.cyr o
    if [ "$RC" = 1 ] && grep -qxF "error: $want select two emit targets; pass one" "$W/out" && [ ! -e "$W/p/o" ] && ! grep -q 'OK' "$W/out"; then np=$((np + 1))
    else fail "$row: build $* — rc $RC (want 1), output $( [ -e "$W/p/o" ] && echo written || echo absent), not the named refusal"; show; fi
}
pair P1 '--win and --aarch64' --win --aarch64
pair P2 '--agnos and --aarch64' --agnos --aarch64
pair P3 '--win and --agnos' --win --agnos
pair P4 '--win and --target=x86_64-bare-metal-elf' --win --target=x86_64-bare-metal-elf
pair P5 '--aarch64 and --target=x86_64-bare-metal-elf' --aarch64 --target=x86_64-bare-metal-elf
pair P6 '--win and --target=cx' --win --target=cx
pair P7 '--target=cx and --aarch64' --target=cx --aarch64
pair P8 '--agnos and --target=aarch64-bare-metal-elf' --agnos --target=aarch64-bare-metal-elf
# the consistent pair plus a third selector: --aarch64 restates the --target, the --win does not
pair P9 '--target=aarch64-bare-metal-elf and --win' --aarch64 --target=aarch64-bare-metal-elf --win
rm -f "$W/p/o"
cy build --win --agnos --aarch64 hello.cyr o
if [ "$RC" = 1 ] && grep -qxF 'error: --win, --agnos and --aarch64 select three emit targets; pass one' "$W/out" && [ ! -e "$W/p/o" ]; then np=$((np + 1))
else fail "P10: build --win --agnos --aarch64 — rc $RC, not the named three-way refusal"; show; fi
[ "$np" = 10 ] && echo "  ok P1-P10: every pair and triple refused by name (rc 1), in the order given, no output, no OK"

# ── J: the js arm never reads stdin ──
mkfifo "$W/fifo"
exec 3<> "$W/fifo"     # held open read-write: a read on it blocks, it never sees EOF
rm -f "$W/p/t.js"
RC=0; ( cd "$W/p" && HOME="$W/h" CYRIUS_HOME="$W/ch" timeout 30 "$W/bin/cyrius" build --aarch64 --target=js t.ts t.js ) > "$W/out" 2>&1 <&3 || RC=$?
exec 3>&-
if [ "$RC" = 1 ] && grep -qxF 'error: --aarch64 and --target=js select two emit targets; pass one' "$W/out" && [ ! -e "$W/p/t.js" ]; then
    echo "  ok J: build --aarch64 --target=js — rc 1 with a blocking stdin, named, no t.js"
else fail "J: rc $RC (124 = it read stdin and blocked), t.js $( [ -e "$W/p/t.js" ] && echo written || echo absent)"; show; fi

# ── V: every verb with the target block ──
cy run --win --aarch64 hello.cyr
if [ "$RC" = 1 ] && grep -qxF 'error: --win and --aarch64 select two emit targets; pass one' "$W/out"; then echo "  ok V: cyrius run --win --aarch64 — refused by name (rc 1), the program not run"
else fail "V: run --win --aarch64 — rc $RC (7 = it ran)"; show; fi

# ── S: each single selector ──
ns=0
# single <row> <out> <selectors...> — rc 0, writes <out>
single() { row=$1; o=$2; shift 2; rm -f "$W/p/$o"; cy build "$@" hello.cyr "$o"; [ "$RC" = 0 ] && [ -s "$W/p/$o" ] || { fail "$row: build $* — rc $RC, no $o"; show; return 1; }; return 0; }
if single S1 s_a64 --aarch64 && [ "$(hexat "$W/p/s_a64" 0 4)" = 7f454c46 ] && [ "$(hexat "$W/p/s_a64" 18 2)" = b700 ]; then ns=$((ns + 1)); else fail "S1: --aarch64 is not an aarch64 ELF"; fi
if single S2 s_win --win && [ "$(hexat "$W/p/s_win" 0 2)" = 4d5a ]; then ns=$((ns + 1)); else fail "S2: --win is not an MZ image"; fi
if single S3 s_agn --agnos && [ "$(hexat "$W/p/s_agn" 0 4)" = 7f454c46 ] && [ "$(hexat "$W/p/s_agn" 18 2)" = 3e00 ]; then ns=$((ns + 1)); else fail "S3: --agnos is not an x86_64 ELF"; fi
if single S4 s_cx --target=cx && [ "$(hexat "$W/p/s_cx" 0 3)" = 435958 ]; then ns=$((ns + 1)); else fail "S4: --target=cx is not a CYX image"; fi
if single S5 s_kx --target=x86_64-bare-metal-elf && [ "$(hexat "$W/p/s_kx" 18 2)" = 3e00 ] && grep -qF 'kernel: entry 0x1000a8, load base 0x100000 (x86_64 ELF64 multiboot2)' "$W/out"; then ns=$((ns + 1)); else fail "S5: --target=x86_64-bare-metal-elf: not an x86_64 ELF with the x86 kernel line"; show; fi
if single S6 s_ka --target=aarch64-bare-metal-elf && [ "$(hexat "$W/p/s_ka" 18 2)" = b700 ] && grep -qF 'kernel: entry 0x40000078, load base 0x40000000 (aarch64 ELF64)' "$W/out"; then ns=$((ns + 1)); else fail "S6: --target=aarch64-bare-metal-elf: not an aarch64 ELF with the aarch64 kernel line"; show; fi
if single S7 s_ww --win --win && cmp -s "$W/p/s_ww" "$W/p/s_win"; then ns=$((ns + 1)); else fail "S7: --win --win differs from --win"; fi
[ "$ns" = 7 ] && echo "  ok S1-S7: each single selector builds its own target (aarch64 / MZ / x86_64 / CYX / both kernels with their lines); --win --win == --win"

# ── C: the consistent pair (D20) ──
rm -f "$W/p/s_kc"
cy build --aarch64 --target=aarch64-bare-metal-elf hello.cyr s_kc
if [ "$RC" = 0 ] && cmp -s "$W/p/s_kc" "$W/p/s_ka" && grep -qF 'kernel: entry 0x40000078, load base 0x40000000 (aarch64 ELF64)' "$W/out"; then
    echo "  ok C: --aarch64 --target=aarch64-bare-metal-elf — rc 0, byte-identical to the --target alone, the aarch64 kernel line"
else fail "C: rc $RC (want 0), $(cmp -s "$W/p/s_kc" "$W/p/s_ka" && echo identical || echo differs) to --target=aarch64-bare-metal-elf alone"; show; fi

# ── Q: the aarch64 output runs ──
if command -v qemu-aarch64 > /dev/null 2>&1; then
    chmod +x "$W/p/s_a64" 2> /dev/null
    xrc=0; timeout 20 qemu-aarch64 "$W/p/s_a64" > /dev/null 2>&1 || xrc=$?
    [ "$xrc" = 7 ] && echo "  ok Q: the --aarch64 output runs under qemu-aarch64 and exits 7" || fail "Q: the --aarch64 output exits $xrc under qemu-aarch64 (want 7)"
else echo "  SKIP (named): Q — qemu-aarch64 is not installed (the --aarch64 output is not run)"; SKIPS=$((SKIPS + 1)); fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G — $FAIL row(s) failed"; exit 1; }
[ "$SKIPS" = 0 ] || { echo "SKIP: $G — $SKIPS leg(s) above could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; }
echo "PASS: $G (two target selectors refused by name, the js arm without reading stdin; each single and the consistent pair build as before)"
