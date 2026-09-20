#!/bin/sh
# tests/gates/toolchain/cli_args_never_dropped.sh — v6.6.5
#
# THE ONE ARGUMENT RULE, ENFORCED. No verb of the `cyrius` CLI, and no delegated
# tool, may take a flag as a file name, drop a flag written after the operand, drop
# an extra operand, or shift its operands when a global -q/-v is present.
#
# WHAT WAS FILED, AND WHAT WAS ACTUALLY WRONG. The filing (mabda 4.1.3,
# docs/development/issues/archived/2026-09-16-mabda-lint-wrapper-drops-strict-deferrals.md)
# reported two rows: `cyrius lint --strict-deferrals f.cyr` gives cyrlint's usage and
# exit 1 (the flag became the FILE), and `cyrius lint f.cyr --strict-deferrals` exits
# 0 with the gate OFF (the flag was dropped in silence). Investigating it found ~60
# spellings of the same shape across every verb, several of them SILENT AND MUTATING:
#
#   fmt f --chekc      rewrote the file and exited 0
#   clean --dryrun     DELETED build/            (unknown flag ignored)
#   -q clean --dry-run DELETED build/            (argv(2) was the verb name)
#   lib sync --dry     really synced 110 files over ./lib
#   deps --dry-run     really resolved and created lib/  (deps.cyr's dry-run branch
#                      was unreachable from the CLI, so it had never once run)
#   build s --strict   wrote the binary to a file NAMED "--strict"
#   build s o -DCUDA   silently dropped the define
#   run f a b c        gave the program argc()==1
#   test --dry-run f   really ran the test
#   fuzz f --poisn     ran with poison mode silently OFF
#   pulsar/lsp/update  ignored every argument and did the real thing
#
# ⚠ ANTI-VACUOUS, AND THE EXPECTED VALUE COMES FROM SOMEWHERE ELSE. A gate that
# shares a defect with the thing it checks reads GREEN (the v6.6.2 lesson). So:
#   * side effects are measured with a tree hash THE SHELL computes
#     (find | sort | sha256sum), never by asking the tool what it did;
#   * axis 1's expected exit code has two independent oracles — the literal 2, and
#     the rc of `cyrlint --strict-deferrals` (a different parser in a different
#     binary);
#   * axis 1's --exit-with-count expectation is parsed out of STDOUT's "<n> warnings"
#     line, a different channel from the exit code it predicts;
#   * axis 8's expected exit code is arithmetic the shell does ($((3 + 1)));
#   * axis 0 derives the verb list from the SOURCE and fails on a verb with no row,
#     so a verb added later cannot escape the gate by not being listed here — and
#     "has a row" MEANS "is probed": COVERED is the axis-2 probe list itself;
#   * axis 13 does the same for cyriusly and ark, from their own dispatch fns;
#   * axis 14's expected argument count is `seq`'s, and axis 15 reads the tool list
#     out of cbt/ and the package list out of build-windows-tarball.sh.
#
# HERMETIC. Everything is built from this tree with ./build/cycc into a throwaway
# CYRIUS_HOME, AND HOME is a throwaway whose .cyrius is that same directory — cycc's
# include fallback reads $HOME/.cyrius/versions/<ver>/lib and ignores CYRIUS_HOME, so a
# CYRIUS_HOME alone was NOT hermetic (round 3: five rows compiled against the live
# store, and went red with an empty HOME). The wine leg runs in a throwaway
# WINEPREFIX under $T and removes its wineserver socket dir. Verified by running the
# whole gate with HOME pointed at an EMPTY directory: green.
#
# MUTATION LEDGER — every row RUN, not asserted (2026-09-18, at 6.6.5). "fails" is
# the number of assertions that went red; the gate exits 1 on any of them.
#   M47 (bite 9h) `_cbt_tmpbase`'s PE arm -> `return "/tmp";`                24 fails
#       ⭐ the row this replaced read the base out of the EMPTY cyrius-* dirs
#       every wrun left behind, which only worked while PE had no
#       RemoveDirectoryW reroute. It now makes %TEMP% a directory that does
#       not exist (a HKCU\Environment write — wine ignores the unix TEMP)
#       and requires the fail-closed refusal to NAME it.
#   M1  restore the 6.6.4 lint loop (first non---strict token is the file)  15 fails
#   M2  ignore unknown flags once an operand has been seen                  26 fails
#   M3  iterate only operand 0 in cmd_lint/cmd_fmt/cmd_doc                   6 fails
#       ⭐ this is WHY axis 4 puts the defect in the LAST file: with it in
#       the first file, M3 would pass every row.
#   M4  re-hardcode `argv(2)` in the clean branch                            2 fails
#   M5  set _dry_run after _auto_deps (the 6.6.4 order)                      8 fails
#   M7  drop cyrlint's 255 clamp on --exit-with-count                        1 fail  (it exits 44)
#   M8  drop run's argument forwarding                                       1 fail  (argc()==1)
#   M9  take -D out of test's flag table                                     1 fail
#   M10 print a flag in --help that the parser does not accept              24 fails
#   M11 add a `streq(cmd, "zz")` dispatch branch with no row here            2 fails
#   M6  restore lib/flags.cyr's silent return at the 128-positional cap:
#       this gate stays GREEN and tests/tcyr/crossos/flags.tcyr goes RED
#       ("every positional retained (got 128, expected 200)"). Recorded as
#       measured, not as intended: the `cyrius` CLI does NOT use lib/flags.cyr
#       (it has its own classifier in cbt/cli_args.cyr), so axis 4's 130-file
#       row proves the CLI path is uncapped and flags.tcyr owns the stdlib
#       parser's cap. Two parsers, two gates. (flags.tcyr moved from stdlib/
#       to crossos/ in the round-2 review, so it now runs on real hardware.)
#
# ROUND-2 REVIEW (same day): the rows below were added for defects the first cut
# shipped or left ungated, and every one was mutation-run against this gate:
#   M11 (re-run) a `streq(cmd, "zz")` branch with no row, census now shares
#       the axis-2 list                                                     1 fail
#   M12 cyrlint multi-file --exit-with-count returns the sum, drops rc      4 fails
#   M13 cmd_lint back to one cyrlint per file + MAX of the rcs              1 fail
#   M14 cyrdoc treats an existing 0-byte file as unreadable                 3 fails
#   M15 ark checks the operand count before the command name                1 fail
#   M16 cyriusly takes an unknown '-' token as an operand (6.6.4 shape)     7 fails
#       (it really created versions/--dry-run in the throwaway home)
#   M17 sign-efi argv capped at 15 again                                    2 fails
#   M18 _cli_int without its overflow guard (soak wraps and never ends)     2 fails
#   M19 drop `build` from AXIS2_VERBS — the census catches the unprobed verb 1 fail
#   M20 one tool lookup back to a bare make_path(_tools_dir, …)             1 fail
#   M21 drop cyrdoc's 255 clamp (300 undocumented exits 44)                 2 fails
#   M22 hand a .cyx's arguments to cxvm instead of refusing them            2 fails
#   M23 cmd_doc drops --check in BOTH positions (equivalence stays green)   4 fails
#   M24 check ignores --with-deps in both positions                         2 fails
#   M25 build-windows-tarball.sh stops shipping cyaudit                     1 fail
#   M26 `cyrius fmt a b c` (write mode) rewrites only the first file        1 fail
#
# ROUND-3 REVIEW (same day). The review found rows passing on the 6.6.4 CLI (axis 2
# grepped the bare token, which 6.6.4's "no such file: --zz-cli-probe" also names; the
# 2b typos ran where the real operation failed anyway). Those rows were rebuilt and the
# new axes 16-19 added; every mutation below was RUN against a copy of the tree:
#   MA  cyrlint returns the count before the strict checks (the round-2 code)  10 fails
#   MB  run_binary_timed without its Windows arm (fork/waitpid on PE)          2 fails (wine)
#   MC  _tool_path without the .exe probe — the reviewers' "mutation D", which
#       left the round-2 gate GREEN                                            4 fails (wine)
#   MD  temp dir back to "/tmp/cyrius-" + raw syscall(39)                      1 fail  (wine)
#   ME  a repeated single-valued flag accepted (last one wins)                 3 fails
#   MF  --features keeps the last occurrence only                              1 fail
#   MG  `run --` routes tokens to the operands before the stop-at-positional   1 fail
#   MH  coverage --min without its 0..100 range                                2 fails
#   MI  cyrsign-efi back to `argc() < 5`                                       4 fails
#   MJ  cyrius-init: the last project name wins                                5 fails
#   MK  ts_test_runner: the last path wins                                     2 fails
#   ML1 cyaudit deny returns the raw count (300 exits 44)                      1 fail
#   ML2 cyaudit vet with no file exits 0                                       1 fail
#   MM  deps --dry-run returns before the manifest check (the round-2 code)    2 fails
#   MN  cyrld accepts a second -o                                              2 fails
#   MO  build-macos-x86-tarball.sh stops shipping cyaudit                      2 fails
#   MP  cyrsign's unknown-option error drops the token                         3 fails
#   MQ  coverage/bench/tests/audit take unknown flags as operands (the
#       reviewers' "mutation E", which left the round-2 gate GREEN)            8 fails
#   MR  cyrld honours -o only at argv(1) (the 6.6.4 shape)                     3 fails
#   MU  THIS GATE without its HOME override, run with an empty outer HOME      7 fails
#   MB/MC/MD are caught ONLY by axis 19 (wine) — on a box without wine they are
#   covered by the cass rows in scripts/cross-os-selfhost.sh, nowhere else.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0

check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
ne_check() {   # $1 name, $2 got — pass when got != 0
    checks=$((checks + 1))
    if [ "$2" != "0" ]; then echo "  ok: $1 (rc=$2)"
    else echo "  FAIL: $1 — expected a non-zero exit, got 0"; fails=$((fails + 1)); fi
}

if [ ! -x "$ROOT/build/cycc" ]; then
    echo "FAIL: cli-args-never-dropped — build/cycc not built"
    exit 1
fi

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cli_args_never_dropped: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
HOME_DIR="$T/home"
mkdir -p "$HOME_DIR/bin" "$HOME_DIR/versions/$(cat VERSION)"
cp "$ROOT/build/cycc" "$HOME_DIR/bin/cycc" && chmod +x "$HOME_DIR/bin/cycc"
cp -r "$ROOT/lib" "$HOME_DIR/versions/$(cat VERSION)/lib"

# ── Build the CLI and every delegated tool from THIS tree. A compile that fails, or
# that produces an EMPTY file, must stop the gate: cycc on empty stdin exits 0 and
# emits a runnable binary, so an unbuilt tool would otherwise score a fake PASS.
build_one() {   # $1 source, $2 dest
    if ! "$ROOT/build/cycc" < "$1" > "$2" 2> "$T/build.err"; then
        echo "FAIL: cli-args-never-dropped — could not build $1"; sed -n '1,5p' "$T/build.err"; exit 1
    fi
    if [ ! -s "$2" ] || [ "$(wc -c < "$2")" -lt 20000 ]; then
        echo "FAIL: cli-args-never-dropped — $1 produced a $(wc -c < "$2")-byte binary"; exit 1
    fi
    chmod +x "$2"
}
build_one "$ROOT/cbt/cyrius.cyr" "$HOME_DIR/bin/cyrius"
for t in cyrlint cyrfmt cyrdoc cyaudit cyrius_api_surface cxvm cyriusly ark cyrius-init cyrsign cyrsign-efi cyrld ts_test_runner; do
    build_one "$ROOT/programs/$t.cyr" "$HOME_DIR/bin/$t"
done
# axis 14 swaps a stand-in in for cyrsign-efi; keep the real one to probe directly.
mv "$HOME_DIR/bin/cyrsign-efi" "$T/cyrsign-efi.real"
# The cx compiler, so axis 8 can build a real .cyx (`cyrius run p.cyx` + arguments).
build_one "$ROOT/src/main_cx.cyr" "$HOME_DIR/bin/cycc_cx"
CY="$HOME_DIR/bin/cyrius"
export CYRIUS_HOME="$HOME_DIR"
# ⛔ HERMETIC HOME TOO (round-3 review). cycc's include fallback reads
# $HOME/.cyrius/versions/<cycc version>/lib and ignores CYRIUS_HOME
# (src/frontend/lex.cyr), so the fixtures that `include "lib/…"` from a scratch dir
# with no lib/ were compiled against the LIVE store: with an empty HOME five rows went
# red (run argc x2, test -D, tests count, fuzz one-file) while the header claimed
# "nothing reads ~/.cyrius". HOME now points at a throwaway whose .cyrius IS the
# CYRIUS_HOME built above, so every compile — wrapper or fallback — sees this tree's lib.
export HOME="$T/h"
mkdir -p "$HOME"
ln -s "$HOME_DIR" "$HOME/.cyrius"

# ── Fixtures.
W="$T/w"; mkdir -p "$W"
# d.cyr: the filed repro's file, verbatim.
printf '# a deferred item with no tracking pointer\nfn f(): i64 { return 0; }\n' > "$W/d.cyr"
# clean.cyr: no deferral, no warning.
printf 'fn clean_fn(): i64 {\n    return 0;\n}\n' > "$W/clean.cyr"
# drift.cyr: not canonically formatted (leading tab + no space after `if`).
printf 'fn drift_fn(): i64 {\n\t\t\treturn 0;\n}\n' > "$W/drift.cyr"
# ok.cyr / probe.cyr / argc.cyr
printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$W/ok.cyr"
printf '#ifdef CLI_PROBE\nvar _p = 7;\n#endif\n#ifndef CLI_PROBE\nvar _p = 0;\n#endif\nfn main(): i64 { return _p; }\nvar r = main();\nsyscall(60, r);\n' > "$W/probe.cyr"
printf 'include "lib/args.cyr"\nfn main(): i64 { args_init(); return argc(); }\nvar r = main();\nsyscall(60, r);\n' > "$W/argc.cyr"
printf 'include "lib/assert.cyr"\nfn main(): i64 { assert_eq(1, 1, "ok"); return assert_summary(); }\nvar r = main();\nsyscall(60, r);\n' > "$W/pass.tcyr"
printf 'include "lib/assert.cyr"\nfn main(): i64 { assert_eq(1, 2, "bad"); return assert_summary(); }\nvar r = main();\nsyscall(60, r);\n' > "$W/fail.tcyr"
cp "$W/pass.tcyr" "$W/one.fcyr"
# undocN.cyr: N functions with NO comment above them — the undocumented count is the
# SHELL's loop counter, not a number cyrdoc reports.
mk_undoc() {   # $1 dest, $2 count
    : > "$1"
    i=0
    while [ "$i" -lt "$2" ]; do printf 'fn ud_%s(): i64 {\n    return 0;\n}\n\n' "$i" >> "$1"; i=$((i + 1)); done
}
mk_undoc "$W/undoc3.cyr" 3
mk_undoc "$W/undoc4.cyr" 4
mk_undoc "$W/undoc300.cyr" 300
: > "$W/empty.cyr"

# ── The shell's own side-effect oracle. Never ask the tool what it changed.
# NAMES (so a new directory or symlink counts as a side effect) plus CONTENT hashes
# of the regular files. A `find -type f` alone misses `cyrius deps`' symlinks and the
# bare `mkdir lib` that `lib sync --dry-run` used to do, which is exactly the kind of
# blind spot that lets a mutating dry run read as clean.
treehash() { ( cd "$1" && { find . | LC_ALL=C sort; find . -type f | LC_ALL=C sort | xargs -r sha256sum; } | sha256sum | cut -d' ' -f1 ); }

run_in() {   # $1 dir, rest: command. Captures rc, stdout, stderr; sets RC/OUT/ERR files.
    d="$1"; shift
    ( cd "$d" && "$@" > "$T/out" 2> "$T/err" )
    RC=$?
}

echo "axis 0 — CENSUS: every verb main() dispatches has a row here (or a reason):"
VERBS=$(awk '
    /^fn main\(\): i64 \{/ { inmain = 1 }
    inmain && /AUTO_DEPS_VERBS BEGIN/ { skip = 1 }
    inmain && /AUTO_DEPS_VERBS END/   { skip = 0; next }
    inmain && !skip {
        t = $0
        while (match(t, /streq\(cmd, "[^"]*"\)/)) {
            v = substr(t, RSTART, RLENGTH)
            sub(/^streq\(cmd, "/, "", v); sub(/"\)$/, "", v)
            print v
            t = substr(t, RSTART + RLENGTH)
        }
    }
' cbt/cyrius.cyr | LC_ALL=C sort -u)
NVERBS=$(printf '%s\n' "$VERBS" | grep -c .)
check "census found a plausible number of verbs (>= 30)" yes "$([ "$NVERBS" -ge 30 ] && echo yes || echo no)"
# COVERED *IS* the axis-2 probe list — one variable, read by both the census and the
# probe loop, so a verb cannot pass the census without being probed. (v6.6.5 round-2
# review: this used to be a second hand-typed list that had drifted — build, run and
# --version were "covered" here and never probed, and the comment claimed axes 2/3/5
# hit every verb when axis 3 drove 5 rows and axis 5 drove 3.)
AXIS2_VERBS="lint fmt doc vet deny header doctest check capacity coverage bench fuzz test tests clean deps version which self smoke soak distlib audit api-surface repl update install publish package lib hooks pulsar lsp build run --version"
COVERED="$AXIS2_VERBS"
# Reasoned exemptions — one line, one reason.
EXEMPT_init='the whole tail is forwarded verbatim to programs/cyrius-init.cyr, which parses and rejects its own flags (tests/gates/toolchain/port_language_arms.sh covers it)'
EXEMPT_port='same as init — forwarded verbatim to the scaffolder in port mode'
EXEMPT_signefi='execve replaces this process with cyrsign-efi, which owns the tail'
EXEMPT_help='takes anything and prints usage'
EXEMPTS="init port sign-efi help --help -h"
uncovered=0
for v in $VERBS; do
    case " $COVERED " in *" $v "*) continue ;; esac
    case " $EXEMPTS " in *" $v "*) continue ;; esac
    echo "  FAIL: verb '$v' is dispatched by main() but has NO row in this gate"
    echo "        → add it to COVERED (and give it fixtures), or EXEMPT it WITH A REASON."
    uncovered=$((uncovered + 1))
done
check "verbs with no row and no reason" 0 "$uncovered"
check "the exemption list still carries reasons" yes "$([ -n "$EXEMPT_init$EXEMPT_port$EXEMPT_signefi$EXEMPT_help" ] && echo yes || echo no)"

echo "axis 1 — ⭐ THE FILED REPRO, verbatim. All four spellings exit 2:"
# Oracle A: the literal 2. Oracle B: the rc of the tool called directly, a different
# parser in a different binary.
run_in "$W" "$HOME_DIR/bin/cyrlint" --strict-deferrals d.cyr; ORACLE=$RC
check "oracle: cyrlint --strict-deferrals d.cyr" 2 "$ORACLE"
run_in "$W" "$CY" lint --strict-deferrals d.cyr
check "cyrius lint --strict-deferrals d.cyr == 2" 2 "$RC"
check "  …and matches the direct-tool oracle" "$ORACLE" "$RC"
run_in "$W" "$CY" lint d.cyr --strict-deferrals
check "cyrius lint d.cyr --strict-deferrals == 2 (the SILENT row)" 2 "$RC"
check "  …and matches the direct-tool oracle" "$ORACLE" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrlint" d.cyr --strict-deferrals
check "cyrlint d.cyr --strict-deferrals == 2" 2 "$RC"
run_in "$W" "$CY" lint d.cyr
check "ANTI-VACUOUS: plain lint of the same file exits 0" 0 "$RC"
run_in "$W" "$CY" lint clean.cyr --strict-deferrals
check "ANTI-VACUOUS: a clean file with the flag exits 0" 0 "$RC"

# --exit-with-count, both positions, with the expected value read off STDOUT.
mk_warnfile() {   # $1 dest, $2 count — each line trips the tab-indent warning
    : > "$1"
    i=0
    while [ "$i" -lt "$2" ]; do printf 'fn wf_%s(): i64 {\n\treturn 0;\n}\n' "$i" >> "$1"; i=$((i + 1)); done
}
mk_warnfile "$W/warn3.cyr" 3
run_in "$W" "$HOME_DIR/bin/cyrlint" warn3.cyr
NW=$(awk '/ warnings$/ {n=$1} END {print n+0}' "$T/out")
check "fixture really produces warnings (floor)" yes "$([ "$NW" -ge 1 ] && echo yes || echo no)"
EXPECT=$NW; [ "$EXPECT" -gt 255 ] && EXPECT=255
run_in "$W" "$CY" lint --exit-with-count warn3.cyr
check "lint --exit-with-count warn3 (leading) == the stdout count" "$EXPECT" "$RC"
run_in "$W" "$CY" lint warn3.cyr --exit-with-count
check "lint warn3 --exit-with-count (trailing) == the stdout count" "$EXPECT" "$RC"
mk_warnfile "$W/warn300.cyr" 300
run_in "$W" "$CY" lint warn300.cyr --exit-with-count
BIG=$(awk '/ warnings$/ {n=$1} END {print n+0}' "$T/out")
check "the 300-fn fixture really exceeds 255 warnings (floor)" yes "$([ "$BIG" -gt 255 ] && echo yes || echo no)"
check "⭐ >255 warnings CLAMPS to 255, it does not wrap to 0" 255 "$RC"

echo "axis 2 — an undeclared '-' token is a NAMED error, in either position, with no side effect:"
mkdir -p "$W/hashdir"; printf 'x\n' > "$W/hashdir/f"
H0=$(treehash "$W")
# ⚠ "NAMES the token" means THE UNKNOWN-OPTION ERROR names it. Grepping for the bare
# token (the first cut) passed on 6.6.4 for every verb whose operand is a path, because
# "no such file: --zz-cli-probe" names it too — the flag-taken-as-a-file defect itself
# read as green (round-3 review, measured on HEAD's CLI).
UNK="unknown option '--zz-cli-probe'"
probe_unknown() {   # $1 verb, rest: operands
    v="$1"; shift
    run_in "$W" "$CY" "$v" --zz-cli-probe "$@"
    ne_check "cyrius $v --zz-cli-probe … rejects" "$RC"
    check "  …with the unknown-option error naming it" 1 "$(grep -c -- "$UNK" "$T/err" || true)"
    run_in "$W" "$CY" "$v" "$@" --zz-cli-probe
    ne_check "cyrius $v … --zz-cli-probe rejects (TRAILING)" "$RC"
    check "  …with the unknown-option error naming it" 1 "$(grep -c -- "$UNK" "$T/err" || true)"
}
# `run` is probed LEADING only: it is go-run style (stop at the first positional), so
# a token AFTER the source belongs to the program — that half is asserted right below.
probe_lead() {   # $1 verb, rest: operands
    v="$1"; shift
    run_in "$W" "$CY" "$v" --zz-cli-probe "$@"
    ne_check "cyrius $v --zz-cli-probe … rejects" "$RC"
    check "  …with the unknown-option error naming it" 1 "$(grep -c -- "$UNK" "$T/err" || true)"
}
for v in $AXIS2_VERBS; do
    case "$v" in
        lint|fmt|doc|vet|deny|header|doctest|check|capacity|build) probe_unknown "$v" ok.cyr ;;
        run)                                                       probe_lead "$v" ok.cyr ;;
        *)                                                         probe_unknown "$v" ;;
    esac
done
check "⭐ no probe in axis 2 changed a single byte of the tree" "$H0" "$(treehash "$W")"
# `--` ends flag parsing and must not change what `run` forwards: the tokens after the
# source are still the PROGRAM's (the first cut refused them as extra operands).
run_in "$W" "$CY" run -- argc.cyr a
check "cyrius run -- argc.cyr a hands 'a' to the program (argc)" "$((1 + 1))" "$RC"
# The other half of `run`: a flag after the source is the PROGRAM's argument, handed
# over rather than rejected — argc() counts it. Expected: program name + 1 token.
run_in "$W" "$CY" run argc.cyr --zz-cli-probe
check "cyrius run argc.cyr --zz-cli-probe hands the token to the PROGRAM (argc)" "$((1 + 1))" "$RC"

echo "axis 2b — the SILENT+MUTATING typos, each with the tree hash unchanged:"
# Round-3 review: the first cut's rows passed on 6.6.4 because the FIXTURE made the
# real operation fail anyway (no manifest for deps, no fuzz harness, a scratch dir for
# pulsar/lsp/update, and only $W was hashed while pulsar/lsp/update write CYRIUS_HOME).
# Now each row (a) greps for the unknown-option error naming THE TYPO, (b) hashes the
# working dir AND the throwaway CYRIUS_HOME, and (c) where a fixture can make the real
# operation succeed, uses one — proven by an anti-vacuous twin without the typo.
P="$T/proj"; mkdir -p "$P"
printf '[package]\nname = "pj2b"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls"]\n' "$(cat "$ROOT/VERSION")" > "$P/cyrius.cyml"
mutating_typo() {   # $1 dir, $2 the typo token, rest: the full command after `cyrius`
    md="$1"; tok="$2"; shift 2
    H=$(treehash "$md")$(treehash "$HOME_DIR")
    run_in "$md" "$CY" "$@"
    ne_check "cyrius $* is refused" "$RC"
    check "  …with the unknown-option error naming '$tok'" 1 "$(grep -c -- "unknown option '$tok'" "$T/err" || true)"
    check "  …and wrote/deleted nothing (dir + CYRIUS_HOME)" "$H" "$(treehash "$md")$(treehash "$HOME_DIR")"
}
cp "$W/drift.cyr" "$W/drift_keep.cyr"
mutating_typo "$W" --chekc fmt drift.cyr --chekc
check "  …and drift.cyr is byte-identical" yes "$(cmp -s "$W/drift.cyr" "$W/drift_keep.cyr" && echo yes || echo no)"
mkdir -p "$P/build"; printf 'junk\n' > "$P/build/artifact"
mutating_typo "$P" --dryrun clean --dryrun
mutating_typo "$P" --dry lib sync --dry
mutating_typo "$P" --verfy deps --verfy
mutating_typo "$W" --poisn fuzz one.fcyr --poisn
mutating_typo "$W" --dry-run pulsar --dry-run
mutating_typo "$W" --dry-run lsp --dry-run
mutating_typo "$W" --dry-run update --dry-run
# ANTI-VACUOUS: the same fixtures WITHOUT the typo really do the work, so the rows
# above prove a refusal, not a fixture on which the operation could not run.
cp -r "$P" "$T/proj_real"
run_in "$T/proj_real" "$CY" deps
check "ANTI-VACUOUS: plain deps in the fixture really writes lib/" yes "$([ -f "$T/proj_real/lib/syscalls.cyr" ] && echo yes || echo no)"
run_in "$T/proj_real" "$CY" clean
check "ANTI-VACUOUS: plain clean in the fixture really removes build/" no "$([ -e "$T/proj_real/build/artifact" ] && echo yes || echo no)"
rm -rf "$T/proj_real"
run_in "$W" "$CY" fuzz one.fcyr
check "ANTI-VACUOUS: plain fuzz one.fcyr really runs the harness" 1 "$(grep -c '^=== 1 passed, 0 failed ===' "$T/out" || true)"

echo "axis 3 — position equivalence: 'V F fx' and 'V fx F' agree on rc and stdout:"
pos_equiv() {   # $1 verb, $2 flag, $3 operand
    run_in "$W" "$CY" "$1" "$2" "$3"; A=$RC; cp "$T/out" "$T/out.a"
    run_in "$W" "$CY" "$1" "$3" "$2"; B=$RC
    check "$1 $2 $3 == $1 $3 $2 (rc)" "$A" "$B"
    check "  …and the same stdout" yes "$(cmp -s "$T/out" "$T/out.a" && echo yes || echo no)"
}
pos_equiv lint --strict d.cyr
pos_equiv lint --strict-deferrals d.cyr
pos_equiv fmt --check drift.cyr
pos_equiv doc --check ok.cyr
pos_equiv check --with-deps ok.cyr
# ABSOLUTE ANCHORS. Equivalence alone is blind to a flag dropped in BOTH positions
# (the same binary compared with itself), so each verb also gets a row whose expected
# value comes from outside the tool. lint and fmt are anchored by axes 1 and 4.
run_in "$W" "$CY" doc --check undoc3.cyr
check "doc --check undoc3.cyr == the fixture's own fn count" 3 "$RC"
run_in "$W" "$CY" doc undoc3.cyr --check
check "doc undoc3.cyr --check (TRAILING) == the fixture's own fn count" 3 "$RC"
run_in "$W" "$CY" doc undoc3.cyr
check "ANTI-VACUOUS: doc without --check writes markdown and exits 0" 0 "$RC"
MP="$T/modp"; mkdir -p "$MP/src"
printf 'fn modp_m(): i64 { return 0; }\n' > "$MP/mod.cyr"
cp "$W/ok.cyr" "$MP/src/main.cyr"
run_in "$MP" "$CY" check --with-deps mod.cyr
check "check --with-deps mod.cyr takes the --with-deps redirect" 1 "$(grep -c '^check via src/main.cyr' "$T/out" || true)"
run_in "$MP" "$CY" check mod.cyr --with-deps
check "check mod.cyr --with-deps (TRAILING) takes it too" 1 "$(grep -c '^check via src/main.cyr' "$T/out" || true)"
run_in "$MP" "$CY" check mod.cyr
check "ANTI-VACUOUS: without the flag there is no redirect" 0 "$(grep -c '^check via src/main.cyr' "$T/out" || true)"

echo "axis 4 — MULTI-FILE, with the defect only in the LAST file:"
run_in "$W" "$CY" lint clean.cyr clean.cyr d.cyr --strict-deferrals
check "lint a b c (bad LAST) == 2" 2 "$RC"
check "  …and linted 3 files, counted by the shell" 3 "$(grep -c '^=== cyrlint: ' "$T/out" || true)"
cp "$W/drift.cyr" "$W/d1.cyr"; cp "$W/clean.cyr" "$W/c1.cyr"; cp "$W/clean.cyr" "$W/c2.cyr"
H=$(treehash "$W")
run_in "$W" "$CY" fmt --check c1.cyr c2.cyr d1.cyr
ne_check "fmt --check a b c (bad LAST) fails" "$RC"
check "  …and --check wrote nothing" "$H" "$(treehash "$W")"
run_in "$W" "$CY" doc --check clean.cyr ok.cyr
check "doc --check over 2 files runs both" 2 "$(grep -c 'documented' "$T/out" || true)"
run_in "$W" "$CY" check ok.cyr nosuchfile.cyr
ne_check "check good bad fails (the extra operand is PROCESSED)" "$RC"
run_in "$W" "$CY" test pass.tcyr fail.tcyr
ne_check "test pass.tcyr fail.tcyr fails" "$RC"
check "  …and reports 1 passed, 1 failed" 1 "$(grep -c '^1 passed, 1 failed' "$T/out" || true)"
for v in vet deny doctest header capacity; do
    run_in "$W" "$CY" "$v" ok.cyr clean.cyr
    ne_check "$v with TWO operands is refused, not half-done" "$RC"
done
# --exit-with-count over N files means ONE thing whichever binary you ask: the SUM,
# clamped. The first cut of cmd_lint spawned cyrlint per file and took the MAX, so
# `cyrius lint` and `cyrlint` disagreed on the same question. Expected = the sum of
# each file's single-file count, read off stdout and added up by the shell.
mk_warnfile "$W/warn6.cyr" 6
run_in "$W" "$HOME_DIR/bin/cyrlint" warn6.cyr
NW6=$(awk '/ warnings$/ {n=$1} END {print n+0}' "$T/out")
SUM=$((NW + NW6)); [ "$SUM" -gt 255 ] && SUM=255
run_in "$W" "$CY" lint --exit-with-count warn3.cyr warn6.cyr
check "cyrius lint --exit-with-count a b == the shell's sum of the per-file counts" "$SUM" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrlint" --exit-with-count warn3.cyr warn6.cyr
check "  …and cyrlint called directly agrees" "$SUM" "$RC"
run_in "$W" "$CY" lint warn300.cyr warn3.cyr --exit-with-count
check "  …and a sum past 255 clamps to 255 through the wrapper" 255 "$RC"
# fmt with no mode WRITES every file, not just the first.
for x in fA fB fC; do cp "$W/drift.cyr" "$W/$x.cyr"; done
run_in "$W" "$CY" fmt fA.cyr fB.cyr fC.cyr
check "fmt a b c (write mode) exits 0" 0 "$RC"
nfixed=0
for x in fA fB fC; do
    if ! cmp -s "$W/$x.cyr" "$W/drift.cyr"; then
        if "$HOME_DIR/bin/cyrfmt" --check "$W/$x.cyr" > /dev/null 2>&1; then nfixed=$((nfixed + 1)); fi
    fi
done
check "⭐ all 3 files were rewritten AND now pass cyrfmt --check (the LAST one too)" 3 "$nfixed"
# The tools called directly with N files.
run_in "$W" "$HOME_DIR/bin/cyrfmt" --check c1.cyr c2.cyr drift.cyr
ne_check "cyrfmt --check a b c (drift LAST) fails" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrfmt" --check c1.cyr c2.cyr
check "ANTI-VACUOUS: cyrfmt --check over two clean files exits 0" 0 "$RC"
run_in "$W" "$HOME_DIR/bin/cyrdoc" --check undoc3.cyr undoc4.cyr
check "cyrdoc --check a b == the shell's sum of the two fixtures' fn counts" "$((3 + 4))" "$RC"
# 130 files: proves there is no flags.cyr-style silent cap anywhere in the chain.
M="$T/many"; mkdir -p "$M"
i=0; while [ "$i" -lt 129 ]; do cp "$W/clean.cyr" "$M/m$i.cyr"; i=$((i + 1)); done
cp "$W/d.cyr" "$M/m129.cyr"
# shellcheck disable=SC2046
( cd "$M" && "$CY" --quiet lint $(ls | LC_ALL=C sort) --strict-deferrals > "$T/out" 2> "$T/err" )
RC=$?
check "⭐ 130 files, the bad one LAST, still exits 2 (no silent cap)" 2 "$RC"
check "  …and all 130 were linted (shell-counted)" 130 "$(grep -c '^=== cyrlint: ' "$T/out" || true)"

echo "axis 5 — a global -q/-v must not shift the operands:"
offset_same() {   # $1.. command after `cyrius`
    run_in "$W" "$CY" "$@"; A=$RC; HA=$(treehash "$W")
    run_in "$W" "$CY" -q "$@"; B=$RC; HB=$(treehash "$W")
    check "cyrius $* == cyrius -q $* (rc)" "$A" "$B"
    check "  …and the same tree hash" "$HA" "$HB"
    run_in "$W" "$CY" --verbose "$@"; C=$RC
    check "  …and == cyrius --verbose $* (rc)" "$A" "$C"
}
offset_same lint d.cyr --strict-deferrals
offset_same doc --check ok.cyr
offset_same version
offset_same fuzz one.fcyr
# `-v` (the short global) as well as --verbose — the killer the plan named.
run_in "$W" "$CY" fuzz one.fcyr; A=$RC
run_in "$W" "$CY" -v fuzz one.fcyr; B=$RC
check "cyrius -v fuzz one.fcyr == cyrius fuzz one.fcyr (rc)" "$A" "$B"
check "  …and it really fuzzed the one file" 1 "$(grep -c '^=== 1 passed, 0 failed ===' "$T/out" || true)"
# The named killers.
mkdir -p "$W/build"; printf 'junk\n' > "$W/build/artifact"
run_in "$W" "$CY" -q clean --dry-run
check "⭐ -q clean --dry-run leaves build/artifact ALONE" yes "$([ -f "$W/build/artifact" ] && echo yes || echo no)"
run_in "$W" "$CY" clean --dry-run
check "  …as does clean --dry-run" yes "$([ -f "$W/build/artifact" ] && echo yes || echo no)"
run_in "$W" "$CY" clean
check "ANTI-VACUOUS: a real clean DOES remove it" no "$([ -f "$W/build/artifact" ] && echo yes || echo no)"
printf '9.9.9\n' > "$W/VERSION"
run_in "$W" "$CY" -q version --project
check "⭐ -q version --project prints ./VERSION, not the toolchain version" "9.9.9" "$(cat "$T/out")"
rm -f "$W/VERSION"

echo "axis 6 — --dry-run means NOTHING is written, in either position:"
D="$T/dry"; mkdir -p "$D"
printf '[package]\nname = "dg"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls"]\n' "$(cat "$ROOT/VERSION")" > "$D/cyrius.cyml"
cp "$W/ok.cyr" "$D/ok.cyr"
cp "$W/pass.tcyr" "$D/pass.tcyr"
HD=$(treehash "$D")
for spec in "build --dry-run ok.cyr out" "build ok.cyr out --dry-run" "deps --dry-run" "test --dry-run pass.tcyr" "test pass.tcyr --dry-run" "clean --dry-run" "lib sync --dry-run"; do
    # shellcheck disable=SC2086
    run_in "$D" "$CY" $spec
    check "cyrius $spec wrote nothing" "$HD" "$(treehash "$D")"
done
check "  …and lib/ was never created by a dry run" no "$([ -d "$D/lib" ] && echo yes || echo no)"
# ANTI-VACUOUS: the same build WITHOUT --dry-run really does write.
run_in "$D" "$CY" build ok.cyr out
check "ANTI-VACUOUS: the same build without --dry-run writes the binary" yes "$([ -f "$D/out" ] && echo yes || echo no)"

echo "axis 7 — a flag's VALUE is validated, not silently coerced:"
# Each row names the offending value in its error (round-3 review: rc != 0 alone passed
# on 6.6.4, where `soak abc` ran 100 iterations and failed for an unrelated reason).
val_refused() {   # $1 the token the error must name, rest: command after `cyrius`
    vt="$1"; shift
    run_in "$W" "$CY" "$@"
    ne_check "cyrius $* is refused" "$RC"
    check "  …and names '$vt'" yes "$(grep -q -- "$vt" "$T/err" "$T/out" && echo yes || echo no)"
}
val_refused abc coverage --min abc
val_refused -1 coverage --min -1
val_refused 101 coverage --min 101
val_refused abc soak abc
val_refused projct api-surface --scope=projct
val_refused bogus build --target=bogus ok.cyr out
val_refused "'-D'" build ok.cyr out -D
# A single-valued flag given twice is REFUSED by name (it used to keep the last one).
val_refused "given more than once '--target=cx'" build --target=js --target=cx ok.cyr out
val_refused "given more than once '--min'" coverage --min 10 --min 20
run_in "$W" "$CY" soak 0
ne_check "cyrius soak 0 is refused (0 iterations is not a run)" "$RC"
# An integer past 63 bits must be REJECTED, not wrapped: the first cut accumulated
# 99999999999999999999 into 7766279631452241919, which passed the `> 0` guard and
# started a soak that never ends. Bounded, so a regression FAILS instead of hanging.
run_in "$W" timeout 20 "$CY" soak 99999999999999999999
check "cyrius soak 99999999999999999999 is refused (rc 1, not a 124 timeout)" 1 "$RC"
check "  …and names the value" 1 "$(grep -c '99999999999999999999' "$T/err" || true)"

echo "axis 8 — ⭐ run forwards the program's own arguments (go-run style):"
NARGS=3
run_in "$W" "$CY" run argc.cyr a b c
check "cyrius run argc.cyr a b c -> argc() == 1 + the arg count" "$((NARGS + 1))" "$RC"
run_in "$W" "$CY" run argc.cyr
check "ANTI-VACUOUS: with no args, argc() == 1" 1 "$RC"
# A .cyx cannot receive arguments — cx has no guest argv ABI, and cxvm reads nothing
# but the program on stdin — so they are REFUSED by name rather than handed to cxvm
# and silently ignored. The bare run is the anti-vacuous half, and also proves the
# run_cx argv rewrite (the old `var argv[8]` was one slot) still execs cxvm.
printf 'fn f(): i64 { return 33; }\nsyscall(60, f());\n' > "$W/cx33.cyr"
run_in "$W" "$CY" build --target=cx cx33.cyr cx33.cyx
check "the .cyx fixture was built (floor)" yes "$([ -s "$W/cx33.cyx" ] && echo yes || echo no)"
run_in "$W" "$CY" run cx33.cyx
check "ANTI-VACUOUS: cyrius run p.cyx returns the guest's code" 33 "$RC"
run_in "$W" "$CY" run cx33.cyx a b c
check "cyrius run p.cyx a b c is REFUSED (rc 1, not the guest's 33)" 1 "$RC"
check "  …and names the first argument it would have dropped" 1 "$(grep -c "refusing to drop: a$" "$T/err" || true)"

echo "axis 9 — -D reaches every compiling verb, in both spellings:"
run_in "$W" "$CY" build -D CLI_PROBE probe.cyr pb_a
run_in "$W" ./pb_a
check "build -D CLI_PROBE s o" 7 "$RC"
run_in "$W" "$CY" build probe.cyr pb_b -DCLI_PROBE
run_in "$W" ./pb_b
check "build s o -DCLI_PROBE (attached, TRAILING)" 7 "$RC"
run_in "$W" "$CY" build probe.cyr pb_c
run_in "$W" ./pb_c
check "ANTI-VACUOUS: without -D it is 0" 0 "$RC"
printf '#ifdef CLI_PROBE\nfn _dv(): i64 { return 0; }\n#endif\n#ifndef CLI_PROBE\nfn _dv(): i64 { return 1; }\n#endif\ninclude "lib/assert.cyr"\nfn main(): i64 { assert_eq(_dv(), 0, "CLI_PROBE"); return assert_summary(); }\nvar r = main();\nsyscall(60, r);\n' > "$W/dprobe.tcyr"
run_in "$W" "$CY" test -D CLI_PROBE dprobe.tcyr
check "test -D CLI_PROBE t.tcyr" 0 "$RC"
run_in "$W" "$CY" test dprobe.tcyr
ne_check "ANTI-VACUOUS: the same test without -D fails" "$RC"

echo "axis 10 — a flag in the OUTPUT slot never becomes a file name:"
run_in "$W" "$CY" build probe.cyr --strict
ne_check "cyrius build s --strict is refused" "$RC"
check "⭐ and no file named '--strict' exists" no "$([ -e "$W/--strict" ] && echo yes || echo no)"
run_in "$W" "$CY" build probe.cyr -o outx
ne_check "cyrius build s -o outx is refused (-o is not a cyrius flag)" "$RC"
check "  …and no file named '-o' exists" no "$([ -e "$W/-o" ] && echo yes || echo no)"

echo "axis 11 — HELP AND PARSER CANNOT DRIFT: every flag in --help is accepted:"
for v in build run test tests bench fuzz check lint fmt doc vet deny coverage capacity deps clean lib version audit api-surface distlib soak doctest header; do
    run_in "$W" "$CY" "$v" --help
    check "$v --help exits 0" 0 "$RC"
    HELPFLAGS=$(grep -o -- '--[a-z0-9-]*' "$T/out" | LC_ALL=C sort -u)
    check "  …and lists at least the 3 common flags" yes \
        "$([ "$(printf '%s\n' "$HELPFLAGS" | grep -c .)" -ge 3 ] && echo yes || echo no)"
    bad=0
    for f in $HELPFLAGS; do
        run_in "$W" "$CY" "$v" "$f" --zz-value-probe-unused 2> /dev/null
        if grep -q -- "unknown option '$f'" "$T/err" 2>/dev/null; then
            echo "    FAIL: '$v --help' advertises $f but the parser rejects it as unknown"
            bad=$((bad + 1))
        fi
    done
    check "  …no advertised flag is rejected as unknown" 0 "$bad"
done

echo "axis 12 — the delegated tools, called DIRECTLY, follow the same rule:"
run_in "$W" "$HOME_DIR/bin/cyrlint" d.cyr --strcit
ne_check "cyrlint f --strcit is refused (it used to lint with strict OFF)" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrfmt" --check drift.cyr; A=$RC
run_in "$W" "$HOME_DIR/bin/cyrfmt" drift.cyr --check; B=$RC
check "cyrfmt f --check == cyrfmt --check f" "$A" "$B"
ne_check "  …and both actually FAIL on a drifted file (floor)" "$A"
run_in "$W" "$HOME_DIR/bin/cyrdoc" --check ok.cyr; A=$RC
run_in "$W" "$HOME_DIR/bin/cyrdoc" ok.cyr --check; B=$RC
check "cyrdoc f --check == cyrdoc --check f" "$A" "$B"
run_in "$W" "$HOME_DIR/bin/cyrdoc" nosuch_xyz.cyr
ne_check "cyrdoc <missing> is refused (it used to exit 0 with no output)" "$RC"
run_in "$W" "$HOME_DIR/bin/cyaudit" vet nosuch_xyz.cyr
ne_check "cyaudit vet <missing> is refused (it used to say 'no dependencies', exit 0)" "$RC"
run_in "$W" "$HOME_DIR/bin/cyaudit" vet ok.cyr --x
ne_check "cyaudit vet f --x is refused" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrius_api_surface" --updat
ne_check "cyrius_api_surface --updat is refused (it used to diff the default snapshot)" "$RC"
# cyrlint, N files + --exit-with-count + an UNREADABLE file. The first cut returned the
# summed warning count and threw the read error away, so this exited 0 — a fail-open
# written by the fix itself. Both positions, and the file that fails is the LAST one.
run_in "$W" "$HOME_DIR/bin/cyrlint" --exit-with-count clean.cyr nosuch_xyz.cyr
ne_check "cyrlint --exit-with-count good MISSING is refused (was exit 0)" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrlint" clean.cyr nosuch_xyz.cyr --exit-with-count
ne_check "cyrlint good MISSING --exit-with-count (TRAILING) is refused" "$RC"
run_in "$W" "$CY" lint --exit-with-count clean.cyr nosuch_xyz.cyr
ne_check "  …and through the wrapper" "$RC"
run_in "$W" "$HOME_DIR/bin/cyrlint" --strict-deferrals clean.cyr d.cyr
check "cyrlint --strict-deferrals clean d (deferral LAST) == 2" 2 "$RC"
# cyrdoc --check clamps like cyrlint does: 300 undocumented must not wrap to 44.
run_in "$W" "$HOME_DIR/bin/cyrdoc" --check undoc300.cyr
UD=$(awk '/ undocumented / {n=$3} END {print n+0}' "$T/out")
check "the 300-fn fixture really exceeds 255 undocumented (floor, read off stdout)" yes "$([ "$UD" -gt 255 ] && echo yes || echo no)"
check "⭐ cyrdoc --check with >255 undocumented CLAMPS to 255" 255 "$RC"
run_in "$W" "$CY" doc undoc300.cyr --check
check "  …and so does cyrius doc, flag TRAILING" 255 "$RC"
# An EXISTING empty module is "no functions", not a read error: file_read_all returns 0
# for both, and the first cut of the unreadable-file guard failed a legal 0-byte file.
run_in "$W" "$HOME_DIR/bin/cyrdoc" empty.cyr
check "cyrdoc on a 0-byte file exits 0" 0 "$RC"
run_in "$W" "$HOME_DIR/bin/cyrdoc" --check empty.cyr
check "cyrdoc --check on a 0-byte file exits 0" 0 "$RC"
run_in "$W" "$CY" doc empty.cyr
check "cyrius doc on a 0-byte file exits 0" 0 "$RC"

echo "axis 13 — the OTHER shipped binaries with their own dispatch (cyriusly, ark):"
# Census again: each binary's verb list is DERIVED from its own `_<x>_known_cmd`
# function, and a verb with no operand rule here FAILS. The same three probes for every
# verb: an unknown '-' token is named, one operand past the maximum is named, and
# neither changes a byte of the working tree OR the throwaway CYRIUS_HOME.
known_cmds() {   # $1 source, $2 fn name — every streq(cmd, "…") in that fn
    awk -v fn="$2" '
        $0 ~ "^fn " fn "\\(" { inf = 1; next }
        inf && /^}/ { inf = 0 }
        inf {
            t = $0
            while (match(t, /streq\(cmd, "[^"]*"\)/)) {
                v = substr(t, RSTART, RLENGTH)
                sub(/^streq\(cmd, "/, "", v); sub(/"\)$/, "", v)
                print v
                t = substr(t, RSTART + RLENGTH)
            }
        }' "$1" | LC_ALL=C sort -u
}
FH="$T/fakehome"; mkdir -p "$FH"
bin_probe() {   # $1 binary, $2 verb, $3 max operands
    b="$1"; v="$2"; mx="$3"
    HB=$(treehash "$W"); HH=$(treehash "$HOME_DIR")
    ( cd "$W" && HOME="$FH" "$HOME_DIR/bin/$b" "$v" --zz-cli-probe > "$T/out" 2> "$T/err" ); RC=$?
    ne_check "$b $v --zz-cli-probe is refused" "$RC"
    check "  …and NAMES the token" 1 "$(grep -c -- '--zz-cli-probe' "$T/err" || true)"
    ops=""; k=0
    while [ "$k" -le "$mx" ]; do ops="$ops opnd$k"; k=$((k + 1)); done
    # shellcheck disable=SC2086
    ( cd "$W" && HOME="$FH" "$HOME_DIR/bin/$b" "$v" $ops > "$T/out" 2> "$T/err" ); RC=$?
    ne_check "$b $v with $((mx + 1)) operand(s) (max $mx) is refused" "$RC"
    check "  …and names the first EXTRA one (opnd$mx)" 1 "$(grep -c "opnd$mx" "$T/err" || true)"
    check "  …and wrote nothing (tree + CYRIUS_HOME)" "$HB$HH" "$(treehash "$W")$(treehash "$HOME_DIR")"
}
CYL=$(known_cmds programs/cyriusly.cyr _cyl_known_cmd)
check "cyriusly census found its verbs (>= 10)" yes "$([ "$(printf '%s\n' "$CYL" | grep -c .)" -ge 10 ] && echo yes || echo no)"
norule=0
for v in $CYL; do
    case "$v" in
        version|--version|-v|list|ls|which|home|update|setup) bin_probe cyriusly "$v" 0 ;;
        use|install|uninstall)                                bin_probe cyriusly "$v" 1 ;;
        cmdtools)                                             bin_probe cyriusly "$v" 2 ;;
        *) echo "  FAIL: cyriusly verb '$v' has no operand rule in this gate"; norule=$((norule + 1)) ;;
    esac
done
check "cyriusly verbs with no rule" 0 "$norule"
# The filed shape verbatim: a mistyped --global used to be DROPPED and the LOCAL pin
# path taken; `install --dry-run` used to install a version literally named --dry-run.
( cd "$W" && HOME="$FH" "$HOME_DIR/bin/cyriusly" use 6.6.4 --globl > "$T/out" 2> "$T/err" ); RC=$?
ne_check "⭐ cyriusly use 6.6.4 --globl is refused (it took the LOCAL path, exit 0)" "$RC"
check "  …and names --globl" 1 "$(grep -c -- "'--globl'" "$T/err" || true)"
( cd "$W" && HOME="$FH" "$HOME_DIR/bin/cyriusly" install --dry-run > "$T/out" 2> "$T/err" ); RC=$?
ne_check "⭐ cyriusly install --dry-run is refused" "$RC"
check "  …and no version named --dry-run appeared" no "$([ -e "$HOME_DIR/versions/--dry-run" ] && echo yes || echo no)"
( cd "$W" && HOME="$FH" "$HOME_DIR/bin/cyriusly" use --global > "$T/out" 2> "$T/err" ); RC=$?
ne_check "cyriusly use --global with NO version is refused (it printed the version, flag dropped)" "$RC"
( cd "$W" && HOME="$FH" "$HOME_DIR/bin/cyriusly" which > "$T/out" 2> "$T/err" ); RC=$?
check "ANTI-VACUOUS: cyriusly which (no operands) still works" 0 "$RC"
ARK=$(known_cmds programs/ark.cyr _ark_known_cmd)
check "ark census found its verbs (>= 8)" yes "$([ "$(printf '%s\n' "$ARK" | grep -c .)" -ge 8 ] && echo yes || echo no)"
norule=0
for v in $ARK; do
    case "$v" in
        status|list|history|verify)  bin_probe ark "$v" 0 ;;
        search|info|install|remove)  bin_probe ark "$v" 1 ;;
        *) echo "  FAIL: ark verb '$v' has no operand rule in this gate"; norule=$((norule + 1)) ;;
    esac
done
check "ark verbs with no rule" 0 "$norule"
# The verb NAME is judged before its operand count: an unknown command with arguments
# must say so, not complain about the arity of a command that does not exist.
( cd "$W" && "$HOME_DIR/bin/ark" create a.ark a.txt x > "$T/out" 2> "$T/err" ); RC=$?
ne_check "ark create a.ark a.txt x is refused" "$RC"
check "  …as an UNKNOWN COMMAND, not an operand-count error" 1 "$(grep -c '^unknown command: create' "$T/err" || true)"

echo "axis 14 — sign-efi hands the helper EVERY argument (it used to cap at 15, silently):"
# A stand-in helper that reports what it received. The expected count is `seq`'s,
# i.e. the shell's, not anything the CLI says.
printf '#!/bin/sh\nprintf "%%s\\n" "$#"\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$HOME_DIR/bin/cyrsign-efi"
chmod +x "$HOME_DIR/bin/cyrsign-efi"
NSE=20
# shellcheck disable=SC2046
run_in "$W" "$CY" sign-efi $(seq 1 "$NSE")
check "sign-efi with $NSE arguments: the helper saw all of them" "$NSE" "$(head -1 "$T/out")"
check "  …and the LAST one arrived intact" "$NSE" "$(tail -1 "$T/out")"
rm -f "$HOME_DIR/bin/cyrsign-efi"

echo "axis 15 — Windows: every sibling tool resolves through the .exe-aware _tool_path:"
# The shipped Windows layout is bin/cyrlint.exe, and a bare make_path(_tools_dir,
# "cyrlint") is refused by run_tool_vec's file_exists check before CreateProcess —
# measured under wine: `error: tool not found`. So NO tool lookup may bypass
# _tool_path. Comment lines are excluded; everything else counts.
BYPASS=$(grep -n 'make_path(_tools_dir' cbt/*.cyr | grep -v ':[0-9]*:[[:space:]]*#' || true)
check "tool lookups in cbt/ that bypass _tool_path (the .exe arm)" 0 "$(printf '%s' "$BYPASS" | grep -c . || true)"
[ -n "$BYPASS" ] && printf '%s\n' "$BYPASS" | sed 's/^/    /'
# …and every tool the CLI resolves that way is PACKAGED by the Windows tarball, or
# exempted here with a reason. (cyaudit and cyrius_api_surface were missing, so
# `cyrius vet/deny/api-surface` had no tool to spawn on a Windows install at all.)
# (EXE_EXEMPT_cyrius_init is GONE as of v6.6.6 — it cross-compiles to PE and the Windows
#  tarball ships it plus its templates. tests/gates/toolchain/cyrius_init_builds_for_pe.sh
#  is what keeps that true.)
EXE_EXEMPT_cyrsign_efi='Linux-only helper by design (cbt/cyrius.cyr sign-efi comment: the execve stub returns -1 elsewhere)'
EXE_EXEMPT_cycc_aarch64='the tarball ships no aarch64 cross-compiler; a Windows-install packaging scope line, not an argument defect'
TOOLS=$(grep -ho '_tool_path(_tools_dir, "[^"]*")' cbt/*.cyr | sed 's/.*"\(.*\)")/\1/' | LC_ALL=C sort -u)
check "tool census found the delegated tools (>= 8)" yes "$([ "$(printf '%s\n' "$TOOLS" | grep -c .)" -ge 8 ] && echo yes || echo no)"
unpacked=0
for t in $TOOLS; do
    if grep '^for tool in ' scripts/build-windows-tarball.sh | tr ' ;' '\n\n' | grep -qx "$t"; then continue; fi
    if grep -q "/bin/$t\.exe" scripts/build-windows-tarball.sh; then continue; fi
    ev="EXE_EXEMPT_$(printf '%s' "$t" | tr -- '-' '_')"
    eval "reason=\${$ev:-}"
    if [ -n "$reason" ]; then continue; fi
    echo "  FAIL: the CLI resolves tool '$t' but build-windows-tarball.sh does not ship $t.exe"
    unpacked=$((unpacked + 1))
done
check "delegated tools missing from the Windows tarball (no reason given)" 0 "$unpacked"
# The same census over BOTH macOS tarball scripts (round-3 review: they shipped neither
# cyaudit nor cyrius_api_surface, so vet/deny/api-surface said "tool not found" on every
# macOS binary install — the Windows fix had stopped at Windows).
MAC_EXEMPT_cyrsign_efi="$EXE_EXEMPT_cyrsign_efi"
MAC_EXEMPT_cycc_aarch64='arm64: the native cycc is copied to cycc_aarch64 by its own line; x86: no aarch64 cross-compiler ships — a packaging scope line'
for ms in scripts/build-macos-arm64-tarball.sh scripts/build-macos-x86-tarball.sh; do
    unpacked=0
    for t in $TOOLS; do
        if grep '^for tool in ' "$ms" | tr ' ;' '\n\n' | grep -qx "$t"; then continue; fi
        if grep -q "/bin/$t\"" "$ms"; then continue; fi
        ev="MAC_EXEMPT_$(printf '%s' "$t" | tr -- '-' '_')"
        eval "reason=\${$ev:-}"
        if [ -n "$reason" ]; then continue; fi
        echo "  FAIL: the CLI resolves tool '$t' but $ms does not ship it"
        unpacked=$((unpacked + 1))
    done
    check "delegated tools missing from $(basename "$ms") (no reason given)" 0 "$unpacked"
done

echo "axis 16 — --exit-with-count must not switch the strict checks OFF:"
# The spec: a strict verdict is 2, --exit-with-count is the count, and the exit code is
# the MAX of the two, so neither flag can cancel the other. The first cut returned the
# count before the strict checks, so `--exit-with-count --strict-deferrals` on a file
# with 0 warnings and an untracked deferral exited 0 — the filed flag, now forwarded,
# switched off by its neighbour. Expected values: max(the stdout count, 2), computed here.
maxof() { if [ "$1" -gt "$2" ]; then echo "$1"; else echo "$2"; fi; }
run_in "$W" "$HOME_DIR/bin/cyrlint" d.cyr
ND=$(awk '/ warnings$/ {n=$1} END {print n+0}' "$T/out")
check "premise: d.cyr has fewer than 2 warnings, so a lost verdict cannot hide behind the count" yes "$([ "$ND" -lt 2 ] && echo yes || echo no)"
EXP=$(maxof "$ND" 2)
for spec in "--exit-with-count --strict-deferrals d.cyr" "--strict-deferrals --exit-with-count d.cyr" "d.cyr --strict-deferrals --exit-with-count" "--exit-with-count --strict-deferrals clean.cyr d.cyr"; do
    # shellcheck disable=SC2086
    run_in "$W" "$CY" lint $spec
    check "cyrius lint $spec == max(count, 2)" "$EXP" "$RC"
    # shellcheck disable=SC2086
    run_in "$W" "$HOME_DIR/bin/cyrlint" $spec
    check "  …and cyrlint $spec agrees" "$EXP" "$RC"
done
mk_warnfile "$W/warn1.cyr" 1
run_in "$W" "$HOME_DIR/bin/cyrlint" warn1.cyr
N1=$(awk '/ warnings$/ {n=$1} END {print n+0}' "$T/out")
check "premise: warn1.cyr has exactly 1 warning (count < the strict verdict)" 1 "$N1"
run_in "$W" "$CY" lint warn1.cyr --exit-with-count --strict
check "cyrius lint warn1 --exit-with-count --strict == max(1, 2)" "$(maxof "$N1" 2)" "$RC"
run_in "$W" "$CY" lint --exit-with-count warn3.cyr --strict
check "  …and a count above 2 still reports the count" "$(maxof "$NW" 2)" "$RC"
run_in "$W" "$CY" lint --exit-with-count d.cyr
check "ANTI-VACUOUS: --exit-with-count alone on d.cyr is just the count" "$ND" "$RC"

echo "axis 17 — the remaining shipped binaries, called DIRECTLY:"
# cyrsign-efi: EXACTLY four operands, no options. `cyrius sign-efi in key cert --dry-run`
# wrote the signed PE to a FILE NAMED --dry-run and exited 0.
SE="$T/se"; mkdir -p "$SE"; : > "$SE/in.efi"; : > "$SE/key.der"; : > "$SE/cert.der"
for spec in "in.efi key.der cert.der --dry-run" "in.efi key.der cert.der out.efi --verify-only" "--zz-cli-probe in.efi key.der cert.der out.efi"; do
    HS=$(treehash "$SE")
    # shellcheck disable=SC2086
    ( cd "$SE" && "$T/cyrsign-efi.real" $spec > "$T/out" 2> "$T/err" ); RC=$?
    ne_check "cyrsign-efi $spec is refused" "$RC"
    tok=$(printf '%s\n' $spec | grep -- '^-' | head -1)
    check "  …naming '$tok' as an unknown option" 1 "$(grep -c -- "unknown option '$tok'" "$T/err" || true)"
    check "  …and wrote nothing (no file named after the flag)" "$HS" "$(treehash "$SE")"
done
( cd "$SE" && "$T/cyrsign-efi.real" in.efi key.der cert.der out.efi opnd4 > "$T/out" 2> "$T/err" ); RC=$?
ne_check "cyrsign-efi with 5 operands is refused" "$RC"
check "  …naming the extra one" 1 "$(grep -c "extra argument 'opnd4'" "$T/err" || true)"
( cd "$SE" && "$T/cyrsign-efi.real" in.efi key.der cert.der out.efi > "$T/out" 2> "$T/err" ); RC=$?
check "ANTI-VACUOUS: four operands pass the argument check (then fail on the EMPTY input)" 1 "$(grep -c 'cannot read PE input' "$T/err" || true)"
# cyrius-init / port: ONE project per invocation (the last positional used to win).
IN="$T/initw"; mkdir -p "$IN"
for spec in "init alpha beta" "init --dry-run alpha beta" "port rp1 rp2"; do
    HI=$(treehash "$IN")
    # shellcheck disable=SC2086
    run_in "$IN" "$CY" $spec
    ne_check "cyrius $spec is refused" "$RC"
    lastop=$(printf '%s\n' $spec | tail -1)
    check "  …naming the extra '$lastop'" 1 "$(grep -c "extra argument '$lastop'" "$T/out" "$T/err" | awk -F: '{s+=$NF} END {print s}')"
    check "  …and scaffolded nothing" "$HI" "$(treehash "$IN")"
done
run_in "$IN" "$CY" init --dry-run alpha
check "ANTI-VACUOUS: init --dry-run alpha (one name) succeeds" 0 "$RC"
# ts_test_runner: one path.
mkdir -p "$T/tsa" "$T/tsb"
run_in "$T" "$HOME_DIR/bin/ts_test_runner" tsa tsb
ne_check "ts_test_runner a b is refused (it walked b alone)" "$RC"
check "  …naming 'tsb'" 1 "$(grep -c "extra argument 'tsb'" "$T/err" || true)"
# cyrld: -o anywhere (6.6.4 honoured it only at argv(1), so a trailing -o produced a
# dump-only run with NO linked output), one -o, and unknown tokens named. The expected
# exit code comes from the LEADING-position link, a different argv shape.
LK="$T/lk"; mkdir -p "$LK"
"$ROOT/build/cycc" < "$ROOT/tests/fixtures/linker/c.cyr" > "$LK/c.o" 2> /dev/null
"$ROOT/build/cycc" < "$ROOT/tests/fixtures/linker/a.cyr" > "$LK/a.o" 2> /dev/null
run_in "$LK" "$HOME_DIR/bin/cyrld" -o exe_lead c.o a.o
check "cyrld -o exe c.o a.o links (floor)" yes "$([ -s "$LK/exe_lead" ] && echo yes || echo no)"
chmod +x "$LK/exe_lead" 2> /dev/null; run_in "$LK" ./exe_lead; LEAD=$RC
check "  …and the linked program runs (its code is not 0 or 127)" yes "$([ "$LEAD" != 0 ] && [ "$LEAD" != 127 ] && echo yes || echo no)"
run_in "$LK" "$HOME_DIR/bin/cyrld" c.o a.o -o exe_trail
check "⭐ cyrld c.o a.o -o exe (TRAILING -o) links too" yes "$([ -s "$LK/exe_trail" ] && echo yes || echo no)"
chmod +x "$LK/exe_trail" 2> /dev/null; run_in "$LK" ./exe_trail
check "  …and the program exits exactly as the leading-position link does" "$LEAD" "$RC"
run_in "$LK" "$HOME_DIR/bin/cyrld" -o x1 -o x2 c.o a.o
ne_check "cyrld -o x1 -o x2 is refused (one output)" "$RC"
check "  …by name" 1 "$(grep -c "more than once '-o'" "$T/err" || true)"
run_in "$LK" "$HOME_DIR/bin/cyrld" c.o --zz-cli-probe
ne_check "cyrld c.o --zz-cli-probe is refused" "$RC"
check "  …naming it" 1 "$(grep -c -- "$UNK" "$T/err" || true)"
# cyrsign: every refusal names the token, and a '-' token is judged before the count.
for spec in "sign --zz-cli-probe" "keygen --zz-cli-probe" "verify a --zz-cli-probe b c"; do
    # shellcheck disable=SC2086
    run_in "$W" "$HOME_DIR/bin/cyrsign" $spec
    ne_check "cyrsign $spec is refused" "$RC"
    check "  …with the unknown-option error naming it" 1 "$(grep -c -- "$UNK" "$T/err" || true)"
done
run_in "$W" "$HOME_DIR/bin/cyrsign" sign a b
check "cyrsign sign a b names the extra operand" 1 "$(grep -c "extra argument 'b'" "$T/err" || true)"
# cyaudit: a missing operand is a failure, and deny's count clamps like cyrlint's.
run_in "$W" "$HOME_DIR/bin/cyaudit" vet
ne_check "cyaudit vet (no file) is refused (it printed usage and exited 0)" "$RC"
run_in "$W" "$HOME_DIR/bin/cyaudit" --help
check "ANTI-VACUOUS: cyaudit --help exits 0" 0 "$RC"
i=0; : > "$W/deny300.cyr"
while [ "$i" -lt 300 ]; do printf 'include "/abs/p%s.cyr"\n' "$i" >> "$W/deny300.cyr"; i=$((i + 1)); done
run_in "$W" "$HOME_DIR/bin/cyaudit" deny deny300.cyr
check "premise: deny300 reports more than 255 violations (read off stderr)" yes "$([ "$(grep -c 'DENY: absolute path' "$T/err")" -gt 255 ] && echo yes || echo no)"
check "⭐ cyaudit deny with >255 violations CLAMPS to 255 (256 used to exit 0)" 255 "$RC"
# cyrfmt names its unknown option on STDERR like every other tool.
run_in "$W" "$HOME_DIR/bin/cyrfmt" drift.cyr --zz-cli-probe
check "cyrfmt names an unknown option on stderr" 1 "$(grep -c -- "$UNK" "$T/err" || true)"

echo "axis 18 — repeated values ACCUMULATE where the flag is multi-valued (--features):"
# Two optional deps that a matching feature ACTIVATES and a target gate then skips, so
# nothing is cloned or written: an activated dep prints "target mismatch", an inactive
# one "no active feature". Expected count = the number of features the shell passed.
FT="$T/feat"; mkdir -p "$FT"
printf '[package]\nname = "ft"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps.fa]\noptional = true\ntarget = "agnos"\npath = "nope"\n\n[deps.fb]\noptional = true\ntarget = "agnos"\npath = "nope"\n' "$(cat "$ROOT/VERSION")" > "$FT/cyrius.cyml"
run_in "$FT" "$CY" -v deps --features fa --features fb
check "⭐ --features fa --features fb activates BOTH (it kept fb only)" 2 "$(grep -c 'skip dep (target mismatch): f[ab]$' "$T/err" || true)"
run_in "$FT" "$CY" -v deps --features fa,fb
check "  …exactly like --features fa,fb" 2 "$(grep -c 'skip dep (target mismatch): f[ab]$' "$T/err" || true)"
run_in "$FT" "$CY" -v deps --features fa
check "ANTI-VACUOUS: --features fa alone leaves fb inactive" 1 "$(grep -c 'no active feature): fb$' "$T/err" || true)"
# deps --dry-run is reachable now; it must fail where the real run fails (no manifest)
# and report what it read, not a canned line.
mkdir -p "$T/nomani"
run_in "$T/nomani" "$CY" deps --dry-run
ne_check "deps --dry-run with NO manifest fails like deps does (it exited 0)" "$RC"
run_in "$FT" "$CY" deps --dry-run
check "deps --dry-run lists the manifest's [deps.NAME] entries" 2 "$(grep -c '^  f[ab]$' "$T/out" || true)"

echo "axis 19 — the WINDOWS CLI under wine (SKIP when wine is absent — NOT hardware):"
# Until 6.6.5 every spawn the CLI makes — tools (lint/fmt/doc/vet/deny/api-surface) AND
# programs (run/test/tests/bench/fuzz) — was sys_fork/sys_waitpid, -1 stubs on PE.
# tests/tcyr/crossos/tool_spawn_roundtrip.tcyr does not cover it (it never builds
# cyrius.exe, and it compiles to the same binary at 6.6.4), so without this leg the
# Windows fix had no runnable gate: deleting _tool_path's .exe arm left every other
# axis green (round-3 review, mutation D). The layout is the SHIPPED one: bin/ holds
# ONLY *.exe names, and cycc.exe is present, so lint's syntax pre-pass runs and needs
# the private temp dir (a literal "/tmp" + a raw, PE-unrouted getpid until round 3 —
# it failed CLOSED on this exact layout). The expected codes are axis 1's oracle and
# axis 8's arithmetic, computed on Linux. cass runs the same four rows on hardware
# (scripts/cross-os-selfhost.sh, cass leg).
if ! command -v wine > /dev/null 2>&1 || ! command -v winepath > /dev/null 2>&1; then
    echo "  SKIP: wine/winepath not installed — the Windows CLI spawn is covered by the cass leg only"
else
    # A THROWAWAY prefix under $T, so the leg reads and writes nothing of the user's
    # ~/.wine (and HOME is already $T/h). winemenubuilder/mono/gecko are disabled so a
    # fresh prefix neither writes desktop entries nor tries to download runtimes.
    export WINEPREFIX="$T/wine" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    WN="$T/wn"; mkdir -p "$WN/bin" "$WN/w"
    "$ROOT/build/cycc" < "$ROOT/src/main_win.cyr" > "$T/cc_win" 2> "$T/build.err" && chmod +x "$T/cc_win"
    build_pe() {   # $1 source, $2 dest — refuse an empty or non-PE artifact
        if ! "$T/cc_win" < "$1" > "$2" 2> "$T/build.err"; then
            echo "FAIL: cli-args-never-dropped — could not cross-build $1 for PE"; sed -n '1,5p' "$T/build.err"; exit 1
        fi
        if [ "$(head -c 2 "$2")" != "MZ" ] || [ "$(wc -c < "$2")" -lt 20000 ]; then
            echo "FAIL: cli-args-never-dropped — $1 produced a non-PE / $(wc -c < "$2")-byte file"; exit 1
        fi
    }
    build_pe "$ROOT/cbt/cyrius.cyr" "$WN/bin/cyrius.exe"
    build_pe "$ROOT/programs/cyrlint.cyr" "$WN/bin/cyrlint.exe"
    build_pe "$ROOT/src/main_win.cyr" "$WN/bin/cycc.exe"
    cp "$W/d.cyr" "$W/clean.cyr" "$W/argc.cyr" "$W/pass.tcyr" "$W/fail.tcyr" "$WN/w/"
    printf 'fn bad(: i64 {\n    return 0;\n}\n' > "$WN/w/syn.cyr"
    ln -s "$HOME_DIR/versions/$(cat VERSION)/lib" "$WN/w/lib"
    WH=$(winepath -w "$WN" 2> /dev/null)
    WTEMP=$(WINEDEBUG=-all timeout 120 wine cmd /c 'echo %TEMP%' 2> /dev/null | tr -d '\r')
    WTEMPU=$(winepath -u "$WTEMP" 2> /dev/null)
    ls -d "$WTEMPU"/cyrius-* 2> /dev/null | LC_ALL=C sort > "$T/wtemp_before"
    wrun() {   # rest: arguments to cyrius.exe; runs in $WN/w
        ( cd "$WN/w" && WINEDEBUG=-all CYRIUS_HOME="$WH" timeout 120 wine "$WN/bin/cyrius.exe" "$@" > "$T/out" 2> "$T/err" )
        RC=$?
    }
    check "wine: the staging path translated (floor)" yes "$([ -n "$WH" ] && echo yes || echo no)"
    wrun lint d.cyr --strict-deferrals
    check "⭐ wine: cyrius.exe lint d.cyr --strict-deferrals == the Linux oracle" "$ORACLE" "$RC"
    wrun lint --strict-deferrals d.cyr
    check "⭐ wine: cyrius.exe lint --strict-deferrals d.cyr == the Linux oracle" "$ORACLE" "$RC"
    wrun lint d.cyr
    check "wine: ANTI-VACUOUS plain lint exits 0" 0 "$RC"
    wrun lint --exit-with-count --strict-deferrals d.cyr
    check "wine: --exit-with-count does not switch --strict-deferrals off" "$EXP" "$RC"
    wrun lint d.cyr --strcit
    check "wine: an unknown option is named" 1 "$(grep -c "unknown option '--strcit'" "$T/err" || true)"
    wrun lint syn.cyr
    ne_check "wine: a file that does not parse fails lint" "$RC"
    check "  …via the cycc.exe syntax pre-pass (needs the private temp dir)" 1 "$(grep -c 'does not parse' "$T/err" || true)"
    wrun run argc.cyr a b c
    check "⭐ wine: cyrius.exe run argc.cyr a b c -> argc() == 1 + the arg count" "$((NARGS + 1))" "$RC"
    wrun test pass.tcyr fail.tcyr
    ne_check "wine: cyrius.exe test pass fail fails" "$RC"
    check "  …having RUN both (1 passed, 1 failed)" 1 "$(grep -c '^1 passed, 1 failed' "$T/out" || true)"
    # ⛔ v6.6.6 (bite 9h): THE BASE IS PROVED FROM THE CLI'S OWN REFUSAL, not from debris.
    # This row used to read `%TEMP%` is the base out of the EMPTY cyrius-* directories every
    # wrun left behind, which worked only because PE had no RemoveDirectoryW reroute and
    # `xrmdir` returned -1 there. 6.6.6 wired that reroute, the CLI removes its directory on
    # Windows too, and a row whose evidence is another bug's symptom went RED with nothing
    # wrong. (The 16-candidate squeeze the POSIX gates use cannot be reproduced here: the
    # Windows name carries a FILETIME nonce, so the candidate names are unpredictable.)
    # Instead, point the prefix's %TEMP% at a directory that does not exist — wine takes
    # TEMP/TMP from HKCU\Environment and IGNORES the unix environment for these two, which
    # is why this is a registry write and not a variable — and require the documented
    # fail-closed refusal to NAME that base. That is a stronger statement than "something
    # appeared under the path we computed": it is the CLI saying where it looked.
    WREG_OK=0
    WINEDEBUG=-all timeout 120 wine reg add 'HKCU\Environment' /v TEMP /d 'C:\cyr-no-such-base' /f > /dev/null 2>&1 && WREG_OK=1
    WINEDEBUG=-all timeout 120 wine reg add 'HKCU\Environment' /v TMP /d 'C:\cyr-no-such-base' /f > /dev/null 2>&1 || WREG_OK=0
    if [ "$WREG_OK" = 1 ]; then
        check "wine: the override took (floor)" "C:\cyr-no-such-base" \
            "$(WINEDEBUG=-all timeout 120 wine cmd /c 'echo %TEMP%' 2> /dev/null | tr -d '\r')"
        wrun test pass.tcyr fail.tcyr
        check "⭐ wine: the private temp base is %TEMP% (named in the fail-closed refusal)" 1 \
            "$(grep -c 'cannot create a private temp directory under C:.cyr-no-such-base' "$T/out" || true)"
        WINEDEBUG=-all timeout 120 wine reg add 'HKCU\Environment' /v TEMP /d "$WTEMP" /f > /dev/null 2>&1 || true
        WINEDEBUG=-all timeout 120 wine reg add 'HKCU\Environment' /v TMP /d "$WTEMP" /f > /dev/null 2>&1 || true
    else
        echo "  FAIL: wine: could not set HKCU\\Environment TEMP for the base probe"; fails=$((fails + 1))
    fi
    # Our own debris, if any survived (a non-empty directory is NOT removed, by contract).
    ls -d "$WTEMPU"/cyrius-* 2> /dev/null | LC_ALL=C sort > "$T/wtemp_after"
    NEWT=$(comm -13 "$T/wtemp_before" "$T/wtemp_after")
    check "wine: and the runs above left no temp directory behind" "" "$NEWT"
    for d in $NEWT; do rmdir "$d" 2> /dev/null || true; done
    # Stop this prefix's wineserver and remove its socket dir (/tmp/.wine-<uid>/
    # server-<dev>-<inode>, keyed on the prefix directory), so the leg leaves nothing
    # behind outside $T.
    SOCK="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WINEPREFIX" 2> /dev/null)-$(printf '%x' "$(stat -c '%i' "$WINEPREFIX" 2> /dev/null || echo 0)")"
    wineserver -k > /dev/null 2>&1 || true
    wineserver -w > /dev/null 2>&1 || true
    [ -d "$SOCK" ] && rm -rf "$SOCK"
fi

echo ""
echo "  assertions: $checks"
if [ "$fails" = "0" ]; then
    echo "PASS: cli-args-never-dropped — no flag taken as a file, no flag dropped, no operand dropped"
    exit 0
fi
echo "FAIL: cli-args-never-dropped — $fails assertion(s) failed"
exit 1
