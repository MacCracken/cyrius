#!/bin/sh
# tests/gates/codegen/coverage_exec_hits.sh — 6.7.10 (P5-B): the execution-coverage mode
#
# THE USER'S DECISIONS (2026-10-12): "P5-B depth: per-fn hit counters (one per fn, set after its
# prologue), dumped when the program exits (lost on a crash or kill). Every target, no new OS route.
# One release." — "Flag off ⇒ byte-identical output (P5-B)."
#
# GROUP S — THE SWITCH (P5B-1). The mode is decided once, in the shared PREPROCESS right after the
# bounds-checked mode's `_bnd_setup` (src/frontend/parse_cov.cyr `_cov_setup`): CYRIUS_COVERAGE 1
# on; 0, unset or empty off; any other value refused by name (lex_pp.cyr `_pp_env_rung`, the rung
# CYRIUS_BOUNDS uses). On, it needs CYRIUS_COVERAGE_FILE (no default: a predictable relative name
# is a symlink-plantable target in a shared directory) and predefines CYRIUS_COVERAGE. A kernel /
# EFI image and a `shared;` / `object;` build have no process exit to dump at: refused by name after
# pass 1 (`_cov_pass1`). There is no source spelling. (Every runnable fork deciding it alike is
# tests/gates/toolchain/fork_flag_parity.sh's `coverage` rows; the self-build scripts unsetting it
# is tests/gates/frontend/bounds_mode_checked.sh E4 / E4c.)
#
#   S1  unset -> off (the probe's `#ifdef CYRIUS_COVERAGE` arm not taken: exit 3)
#   S2  CYRIUS_COVERAGE=1 + CYRIUS_COVERAGE_FILE -> on, in the entry (exit 7) AND in a file it
#       includes (exit 9; its control 4); the compiler never writes the file
#   S3  CYRIUS_COVERAGE=0 -> off (with and without a FILE)
#   S4  CYRIUS_COVERAGE= (empty) -> off
#   S5  =1 with no FILE, an empty FILE, a 256 B FILE (over _read_env's 255 B, which it warns of) ->
#       refused by name, rc 1, exactly one error line, no binary; a 255 B FILE is accepted (the edge)
#   S6  =2 / true / yes -> refused by name, naming the value; no binary
#   S7  under the mode: `kernel;`, CYRIUS_KERNEL=1 (a bare-metal --target), `shared;`, `object;`,
#       CYRIUS_TARGET_EFI=1 -> refused by name, exactly one error line (fatal at once); each control
#       (the same build, mode off) compiles
#   S8  a plain `#define CYRIUS_COVERAGE` is an ordinary define and switches nothing (a `kernel;`
#       build with it compiles, where the mode + `kernel;` is refused)
#   S9  the 16-slot #define / flag table: the heaviest includer (lib/sandhi.cyr) plus 4 user
#       #defines compiles and runs under CYRIUS_BOUNDS=1 + CYRIUS_COVERAGE=1 (the mode takes one slot;
#       measured 2026-10-12: sandhi + 5 is the edge under both modes, + 7 with neither)
#   S10 mode off is byte-identical: over every 12th .tcyr (floor 30), unset == CYRIUS_COVERAGE=0 ==
#       CYRIUS_COVERAGE= (empty) — the binary, the stderr and the rc
#
# GROUPS H / A / B / M / CC / L — THE COUNTERS, THE MAP AND THE END-OF-PROGRAM DUMP (P5B-2). Every
# fn body bumps its own counter at its first byte (parse_cov.cyr `_cov_body` / `_cov_hit`); the
# counters and the fn map are two hidden globals (`_cov_greg`), the map an image blob; `_cov_tail`
# (one line before EEXIT in each of the seven forks) calls the dump appended to the unit
# (`_cov_finish`), which appends `# cyrius-coverage 1` and one `<count> <file>:<line> <name>` per fn
# entered to CYRIUS_COVERAGE_FILE. Each row compiles under the mode, runs, and holds the exit to the
# plain build's and the dump (sorted) to its expectation exactly. (These probes return from `main`
# or fall off the top level; the exit syscalls are group E.)
#   H1  `main` returns 4: `2 <source>:1 a`, `1 .. b`, `1 .. main`; `never` absent
#   H2  falling off the top level: the exit is the last var; `f` counted
#   H3  an included fn is named by its include path and its own line
#   H4  no fn entered: the header alone
#   H5  the dump path and the first map line are image bytes on all six writers (x86 ELF, PE, x86
#       Mach-O, agnos, arm64 Mach-O, cx) — and absent from the mode-off image
#   H6  the large-static advisory leaves the band and the map out (src/main.cyr instrumented: the
#       plain figure, within the two's alignment)
#   H7  the hit (x86's push / load / add 1 / pop / store) appears once per counted body under the mode
#       and NEVER with it off — the absolute anchor S10 cannot be (it compares three mode-off runs)
#   H8  a record over the dump's 992 B line budget is written straight out, whole
#   A2  H1-H3 under CYRIUS_IR=1 / IR=3 / DCE=1 / PIE=1 / STACK_ARRAYS=0
#   A4  the argument shapes (a 7-argument fn, Win64's 4, `#regalloc`, a capturing closure, a >16 B
#       struct return, a coroutine counted once across four forces): every result right (exit 50)
#       and the program's records exact — x86, IR=3, aarch64 (qemu), PE (wine)
#   B1  the highest fn indexes (generic instances minted in pass 2, after the dump's own fns) count
#   M3  tests/tcyr/compiler/large_source.tcyr, verbatim, compiles and dumps ONE block (through its own
#       last line, `syscall(60, r);` — the exit hook, group E)
#   CC1 an instrumented cycc compiles src/main.cyr byte-identical to cycc(src); its dump is ONE block
#       of > 500 records (through src/main.cyr's own `syscall(SYS_EXIT, _had_error);`)
#   L1-L5 aarch64 (qemu), the main_aarch64_native fork (qemu), PE through main.cyr and through the
#       main_win fork (wine), cx (cxvm; H1 there since 6.7.11, when cx gained the `main` auto-call)
#
# GROUP E — EVERY EXIT ROUTE (P5B-3). A program that leaves through an exit syscall never reaches
# `_cov_tail`, so the syscall builtin hooks every exit whose NUMBER is a compile-time constant
# (parse_cov.cyr `_sc_args_done`, the 1-for-1 swap for `_macho_warn_unrouted` in
# `_PARSE_FACTOR_IMPL`; `_cov_is_exit` per target: x86 ELF / x86 Mach-O / cx {60, 231}, aarch64 {60,
# 93, 94}, PE {60}, agnos {0}), after the arguments are pushed and before every target lowering.
# Each row holds the exit to the plain build's and to its stated value, and the program's own
# records and the BLOCK count exactly:
#   E1a `sys_exit(code())` three frames deep -> 5; code / deep2 / deep1 counted
#   E1b `syscall(SYS_EXIT, code())` -> `code` counted (the hook follows the argument evaluation)
#   E2  top-level `syscall(60, main())` -> `main` counted
#   E3a `syscall(SYS_EXIT, 3)` in a fn (aarch64's 93); E3b `sys_exit_group(4)` (x86 231, aarch64 94,
#       PE's wrapper issues 60)
#   E4  `syscall(231, 23); syscall(60, 9)`: x86 / cx exit 23, aarch64 (munlockall) and PE (-38) exit 9
#       — ONE block each
#   E5a PE: raw 231 is -38 and the program goes on to exit 78 — ONE block; E5b PE: E4's shape
#   E6  a CYRIUS_BOUNDS=1 violation -> 134 (the checker's own `syscall(60, 134)`), the violating fn
#       counted; E7 `panic` -> 1
#   E8  fork: the child's block and the parent's, both whole (O_APPEND); E9 four lib/thread workers
#       (their raw-asm exits do not dump) -> `wk` 4, ONE block
#   E10 an exit inside a `#naked` fn compiles and gets no call (objdump: none between its last
#       argument and its `syscall`; the ordinary fn's exit has the dump's one)
#   E11 `syscall(n, 0)` with a runtime-variable number: the exit unchanged and NO dump (the
#       documented residual — never a partial block)
#   E12 `const K = 60; syscall(K, 7)` -> a block; E13 an exit inside an `#inline` fn -> a block
#   AG  agnos (generated, NOT run: no agnos host here, and #58 is vfork on Linux): the dump's #7 /
#       0x501 / #58 / #6 immediates in the instrumented image only; a call precedes `syscall(0, ..)`,
#       none precedes `syscall(60, ..)`
#   DW  Darwin's 0x209 open flags in the x86 and arm64 Mach-O dumps, Linux's 0x441 in neither
#   Legs: E1-E3, E11-E13 on x86, aarch64 (qemu), the native fork (qemu), PE via main.cyr and
#   main_win (wine) and cx; E6 / E7 wherever `main` is auto-called (cx too since 6.7.11); E8 / E9 on
#   x86 and aarch64; E1b / E7 under CYRIUS_IR=1 / IR=3 / DCE=1 / PIE=1 / STACK_ARRAYS=0
#
# GROUP F — EVERY FN SHAPE (P5B-4). An `#inline` replay re-parses its callee's body inside the
# caller and bumps the callee's counter (parse_cov.cyr `_cov_body` with ti -1, the 1-for-1 swap for
# PARSE_FNCALL's one PARSE_PROG; the callee's line recorded only when its definition has not); a
# closure bumps its own once its frame is open (`_cl_frame_open`, the 1-for-1 swap for
# `_PARSE_FACTOR_IMPL`'s one ESUBRSP), named at its closing bar's line; a `#naked` fn is recorded as
# not instrumented (`- <file>:<line> <name>`). Each probe falls off the top level and its WHOLE dump
# is held exactly (a closure's `__clNNNNN` — its fn index — is compared as `__cl#` everywhere):
#   F1  `#inline inl` replayed twice directly and once inside a replayed `#inline inl2` -> 3; inl2 1
#   F2  closures: an expression closure x2, a block closure, a bar list over two lines (named at its
#       closing bar's line), a `||` closure, one inside a fn called twice — each at its line
#   F3  `gen<f64>` (minted `gen$f64`; `gen$i` before 6.7.11) and the base called at i64 both count;
#       an uncalled generic absent
#   F4  a method (`P_sum`); its uncalled sibling absent
#   F5  CYRIUS_ASYNC=1: `outer$impl` once across four forces (it suspends twice mid-body), `job$impl`
#       2, no constructor record (x86 and PE: aarch64 refuses a mid-body await by name, cx too)
#   F6  `#naked nk` -> `- <source>:2 nk` (E10a carries one too; M3 shows lib/fdlopen.cyr's two). cx
#       takes no `#naked` (an ordinary fn there): no record
#   F7  no `__cyrius_` record ever — the dump's own fns (F7a), and CYRIUS_BOUNDS=1's checker on every
#       runtime subscript (F7b)
#   F8  a fn and a closure with `defer`, each 1 (the defer-init jump never re-runs the hit)
#   A7  a self tail call `tail2(3)` -> 4 and a tail chain ta / tb -> 3 / 2 (ETAILJMP re-enters at the
#       prologue: every entry counts)
#   A6  a top-level indirect call (aarch64 / cx open a micro-frame with EFNPRO there) adds no record
#   Legs: all on x86, aarch64 (qemu), the native fork (qemu), PE via main.cyr and main_win (wine) and
#   cx (cxvm); F1 / F2 / F8 also under CYRIUS_IR=1 / IR=3 / DCE=1 / PIE=1 / STACK_ARRAYS=0. The rows
#   P5B-2 / P5B-3 wrote that these shapes reach: A4 (`capt`'s closure), E10a (`- <source>:2 nk`), E13
#   (`die`, the `#inline` exit), M3 / E8' (a `-` record is a well-formed line)
#
# GROUP G — THE GUIDE (P5B-8). docs/guides/cyrius-guide.md § "The execution-coverage mode (6.7.10)"
# is the mode's user documentation; these rows hold what it shows to the compiler (bounds_mode_checked
# TL4's shape), on x86:
#   G1  its example (the section's first unlabeled fence) exits the value its ```sh fence states and
#       dumps EXACTLY its first ```text fence (a closure's `__clNNNNN` compared as `__cl#`, as the
#       guide says the number moves); G1' the same exit with the mode off
#   G2  the texts it quotes are the compiler's: the `0 or 1` refusal (for `=2`), the missing-FILE
#       refusal, the over-255-byte warning
#   G3  the dump fns it names as reserved are exactly the `fn __cyrius_cov_*` that `_cov_finish`
#       (src/frontend/parse_cov.cyr) appends
#   G4  its reserved-name claims: a program's own `__cyrius_` fn gets no line, and one that reuses
#       `__cyrius_cov_dump` is replaced by the compiler's — the `duplicate fn` warning names it, and
#       the block is still written
#   G5  its `<line>` rule for a fn a `#derive` writes ("named at its struct's closing `}`"): a derive
#       probe whose `#derive`, `struct`, field and `}` lines all differ dumps P_x / P_set_x at the `}` line
#
# MUTATION LEDGER (P5B-1; scratch copies of the tree, each its 2-stage mutant cycc, this gate and the
# named gates run as CYCC=<mutant>; 2026-10-12):
#   MS1  `_cov_setup`'s PP_PREDEFINE dropped                     -> RED S2a S2b S5d
#   MS2  the rung accepts `2` as on                              -> RED S6 (=2)
#   MS3  CYRIUS_COVERAGE_FILE not required                       -> RED S5a S5b S5c
#   MS4  `_cov_pass1`'s shared; / object; refusal dropped        -> RED S7c S7d
#   MS5  one script's `unset ... CYRIUS_COVERAGE` removed        -> RED bounds_mode_checked.sh E4, naming it
#        (install.sh, seed-derive-cycc.sh — E4c too —, check.sh, bootstrap.sh each measured)
#   MS6  `_pp_env_rung`'s refusal text altered (the refactor)    -> RED bounds_mode_checked.sh E2 (x3);
#        fork_flag_parity.sh "bounds <every fork> env2" and "coverage <every fork> env2" (16 of 127)
#   MF   `_cov_setup` not called from PREPROCESS                 -> RED fork_flag_parity.sh "coverage <every
#        fork> env1 / nofile / env2" (24 of 127)
# MUTATION LEDGER (P5B-2; the same procedure, 2026-10-12; "N of 79" = the rows each turned RED):
#   M2   the hit removed (`_cov_body`)                           -> RED 41 of 79: H1-H3 H7, A2 (IR=3 included),
#        A4, B1, M3, CC1b, L1-L5
#   M4   the band left at 8 B (`_cov_tail`'s sizing dropped)       -> RED 32 of 79: B1, H1 H3, A2 H1 / H3, M3, CC1b
#   M5   `_cov_tail` removed from src/main.cyr                    -> RED 36 of 79: H1-H4, H5 on the four main.cyr
#        writers, A2, A4 x86 (the other forks' rows stay green: they run their own line)
#   M8   the file dropped from `_cov_map`                         -> RED 46 of 79: H1-H3, H5 (all six), A2, ...
#   M13  the EPUSHR / EPOPR around the dump call removed          -> RED 39 of 79: H1-H4 (exit 0, not the plain
#        build's), A2, ...
#   M17  the hit emitted with the mode off (the band registered and sized, the dump not) -> RED 2 of 79: H7
#        ("4 off, want 0") and H6; S10 stays GREEN (three mode-off runs agree), which is why H7 exists;
#        scripts/differential.sh sees it too. (Dropping the bare `if (_cov_mode == 1)` cannot self-host:
#        the hits then address a band that was never registered.)
#   ML   `_warn_large_static`'s subtraction removed               -> RED 1 of 79: H6 (303968 B under the mode)
# MUTATION LEDGER (P5B-3; the same procedure, 2026-10-12; "N of 166"):
#   MH   the exit hook removed (`_sc_args_done` calls no dump)     -> RED 74 of 166: M3, CC1b, E1-E7 / E12 /
#        E13 on every leg and x86 codegen mode, E8, E10, AG2
#   M12  the hook placed before the arguments (after the number)  -> RED 19 of 166: E1b (every leg and x86
#        codegen mode) and E2 on every leg (`code` / `main` missing), E10b, AG2
#   M9   231 added to the aarch64 predicate                      -> RED 2 of 166: E4 aarch64 + native (two blocks)
#   M10  94 dropped from the aarch64 predicate                   -> RED 2 of 166: E3b aarch64 + native (no dump)
#   M16  231 added to the PE predicate                           -> RED 3 of 166: E5a (both PE legs), E5b
#   M11  the agnos predicate 60 for 0                            -> RED 1 of 166: AG2
#   M14  Linux's open flags (1089) on Darwin                     -> RED 2 of 166: DW x86 + arm64 Mach-O
#   M15  O_TRUNC for O_APPEND (577)                              -> RED 2 of 166: E8 x86 + aarch64 (the
#        child's block lost)
# MUTATION LEDGER (P5B-4; the same procedure, 2026-10-12; "N of 243"):
#   M6   the replay swap reverted (PARSE_FNCALL's PARSE_PROG)     -> RED 17 of 243: F1 on every leg and x86
#        codegen mode, E13 on every leg (`inl` / `die` absent)
#   M7   the closure swap reverted (`_PARSE_FACTOR_IMPL`'s ESUBRSP) -> RED 32 of 243: F2 / F8 / A6 on every leg
#        and x86 codegen mode, A4 x86 / IR=3 / aarch64 / PE (`capt`'s closure absent)
#   M7b  the closure's line taken at its REGFN (the opening side) -> RED 11 of 243: F2 on every leg and x86
#        codegen mode (the two-line bar list named at line 5, not 6)
#   MN   the naked branch dropped (no `-` record)                 -> RED 6 of 243: F6 on the five legs that take
#        `#naked` (cx does not), E10a
#   MO   the `__cyrius_` skip dropped (`_cov_own`)                -> RED 109 of 243: F7a / F7b (the dump's own
#        fns, `__cyrius_bounds_chk`) and every whole-dump row (H1-H4 H8, A2, B1, L1-L5, group F); H7 (8 hits,
#        not 4). The `<source>`-filtered rows (A4, group E) stay green, as they must
# MUTATION LEDGER (P5B-8; scratch copies of the tree; "N of 250"):
#   MG1  the guide's dump block altered (`3 <source>:1 sq` -> `2 …`)  -> RED 1 of 250: G1
#   MG2  the guide's quoted `0 or 1` refusal altered                 -> RED 1 of 250: G2
#   MG3  a fifth dump fn in `_cov_finish` (its 2-stage cycc)         -> RED 1 of 250: G3
#   MG4  the guide's stated exit altered (`# 11` -> `# 12`)           -> RED 2 of 250: G1 G1'
#   MG5  the guide's derive clause altered (`closing `}`` -> `struct` line) -> RED 1 of 251: G5 (the 6.7.10
#        review: the guide said every `<line>` is the `fn` keyword's, which a derive-written fn has not)
# MUTATION LEDGER (6.7.11, cx's `main` auto-call; a scratch copy of the tree; "N of 254"):
#   MA1  the auto-call's `ECALLTO` dropped from src/main_cx.cyr    -> RED 3 of 254: L5 cx H1 (exit 0, the
#        header alone), E6 / E7 cx (exit 0, not 134 / 1)
# NOT MUTATION-PROVABLE, said by name (plan §5; the 6.7.10 review), kept as defensive lines:
#   - the two `_IR_REC0(S, IR_RAW_EMIT)` marks in `_cov_hit`: P11 measured identical output without them;
#     the IR=3 rows are pinned by M2.
#   - `_cfo = 0` in `_cov_hit` and in `_cov_call_dump` (src/frontend/parse_cov.cyr). Every factor that can
#     precede a fold clears or re-arms `_cfo` itself (a variable load, a call, a unary operator, the
#     syscall builtin), so a fold armed before the hit or the dump call is never consulted after it.
#     Measured, each line removed in its own 2-stage mutant cycc (MY2 the hit's, MY3 the dump call's):
#     this gate GREEN 250 / 250, coverage_mode_corpus.sh GREEN, and the shapes that put a fold around a
#     hit (`3 + c7()`, `c7() + 4`, `2 * k5(9)`, `1 + k5(2) + 1` with #inline literal bodies, `4 * f2(1) * 2`,
#     `6 + f2(2)`) compile BYTE-IDENTICAL to the tree compiler's under IR=0 / 1 / 3. Plan hazard H22's
#     "pinned by A1-A7" did not hold: no row pins them, and none can while no factor leaves `_cfo` armed.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=coverage_exec_hits
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix (and wine's own HOME / XDG_CACHE_HOME) under $T; the EXIT teardown stops
# THIS prefix's wineserver and removes its server dir, which `wineserver -k` leaves behind.
WP="$T/wp"
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
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS
fails=0
rows=0
ok()  { rows=$((rows + 1)); echo "  ok   $1"; }
bad() { rows=$((rows + 1)); echo "  FAIL $1"; fails=$((fails + 1)); }

# The probe: exit 7 when the CYRIUS_COVERAGE predefine is visible, 3 when it is not.
PROBE='var code = 3;
#ifdef CYRIUS_COVERAGE
code = 7;
#endif
syscall(60, code);'
F="$T/cov.out"   # the dump path the mode is given (the compiler must never write it)

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
# xe <row> <message> <src file> [env...]: refused — rc 1, exactly ONE error line holding <message>,
# and no binary
xe() {
    row=$1; msg=$2; src=$3; shift 3
    cc "e$rows" "$src" "$@"
    if [ "$RC" != 1 ]; then bad "$row: rc $RC (want 1, a refusal: $msg)"; return; fi
    if ! grep -qF -- "$msg" "$T/e$rows.err"; then bad "$row: rc $RC without '$msg': $(head -2 "$T/e$rows.err" | tr '\n' ' ')"; return; fi
    if [ "$ERRS" != 1 ]; then bad "$row: $ERRS error lines (want exactly 1): $(grep '^error' "$T/e$rows.err" | tr '\n' '|')"; return; fi
    if [ -s "$T/e$rows.bin" ]; then bad "$row: refused, but a binary was written"; return; fi
    ok "$row: $(grep '^error' "$T/e$rows.err" | head -1 | cut -c1-110)"
}
MF='CYRIUS_COVERAGE=1 needs CYRIUS_COVERAGE_FILE=<path> (the file the program appends its coverage to at exit)'
MK='the execution-coverage mode is not available for a kernel / EFI image (it has no process exit to dump at)'
MS='the execution-coverage mode is not available for a shared; or object; build (no process exit of its own; the counters and the dump would be defined in every object)'

# ── S: the switch ───────────────────────────────────────────────────────────────────────────────
printf '%s\n' "$PROBE" > "$T/s.cyr"
xc "S1 unset: off" 3 s.cyr
xc "S2a CYRIUS_COVERAGE=1 + CYRIUS_COVERAGE_FILE: on (the predefine)" 7 s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F"
printf 'fn inc_v(): i64 {\n#ifdef CYRIUS_COVERAGE\n    return 9;\n#endif\n    return 4;\n}\n' > "$T/inc_v.cyr"
printf 'include "inc_v.cyr"\nsyscall(60, inc_v());\n' > "$T/s2.cyr"
xc "S2b the predefine reaches an included file" 9 s2.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F"
xc "S2c the control: the same include, mode off" 4 s2.cyr
# Checked before anything RUNS a binary built under the mode (the program writes the file, never cycc).
rm -f "$F"
cc s2d s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F"
if [ "$RC" = 0 ] && [ ! -e "$F" ]; then ok "S2d the compiler does not write CYRIUS_COVERAGE_FILE"
else bad "S2d rc $RC; the dump file exists after the COMPILE: $(ls -l "$F" 2>&1)"; fi
xc "S3a CYRIUS_COVERAGE=0: off" 3 s.cyr CYRIUS_COVERAGE=0
xc "S3b CYRIUS_COVERAGE=0 with a FILE: off" 3 s.cyr CYRIUS_COVERAGE=0 CYRIUS_COVERAGE_FILE="$F"
xc "S4 CYRIUS_COVERAGE= (empty): off" 3 s.cyr CYRIUS_COVERAGE= CYRIUS_COVERAGE_FILE="$F"
xe "S5a CYRIUS_COVERAGE=1 with no CYRIUS_COVERAGE_FILE" "$MF" s.cyr CYRIUS_COVERAGE=1
xe "S5b CYRIUS_COVERAGE=1 with an empty CYRIUS_COVERAGE_FILE" "$MF" s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE=
L255="$T/$(printf 'p%.0s' $(seq $((254 - ${#T}))))"
L256="${L255}q"
xe "S5c a 256 B CYRIUS_COVERAGE_FILE (over _read_env's 255 B)" "$MF" s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$L256"
if grep -qF 'warning: ignoring CYRIUS_COVERAGE_FILE: its value is longer than 255 bytes' "$T/e$((rows - 1)).err"; then
    ok "S5c' the 256 B value is named by _read_env's warning (${#L256} B)"
else bad "S5c' no 'longer than 255 bytes' warning for the ${#L256} B value: $(head -1 "$T/e$((rows - 1)).err")"; fi
xc "S5d a 255 B CYRIUS_COVERAGE_FILE is accepted (the edge, ${#L255} B)" 7 s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$L255"
for v in 2 true yes; do
    xe "S6 CYRIUS_COVERAGE=$v is refused by name" "CYRIUS_COVERAGE must be 0 or 1 (or unset): $v" s.cyr CYRIUS_COVERAGE=$v CYRIUS_COVERAGE_FILE="$F"
done

# S7 — where the mode has no meaning; each control compiles
printf 'kernel;\nvar x = 1;\n' > "$T/s7a.cyr"
printf 'var x = 1;\n' > "$T/s7b.cyr"
printf 'shared;\nfn f(): i64 { return 1; }\n' > "$T/s7c.cyr"
printf 'object;\nfn f(): i64 { return 1; }\n' > "$T/s7d.cyr"
s7() {   # s7 <row> <msg> <src> [env...]: refused under the mode; the control (mode off) compiles
    row=$1; msg=$2; src=$3; shift 3
    xe "$row" "$msg" "$src" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F" "$@"
    cc "c$rows" "$src" "$@"
    if [ "$RC" = 0 ] && [ -s "$T/c$rows.bin" ]; then ok "$row' the control (mode off) compiles"
    else bad "$row' the control (mode off): rc $RC: $(grep -m1 error "$T/c$rows.err")"; fi
}
s7 "S7a kernel;" "$MK" s7a.cyr
s7 "S7b CYRIUS_KERNEL=1 (a bare-metal --target)" "$MK" s7b.cyr CYRIUS_KERNEL=1
s7 "S7c shared;" "$MS" s7c.cyr
s7 "S7d object;" "$MS" s7d.cyr
s7 "S7e CYRIUS_TARGET_EFI=1" "$MK" s7b.cyr CYRIUS_TARGET_EFI=1

# S8 — no source spelling
printf '#define CYRIUS_COVERAGE\nkernel;\nvar x = 1;\n' > "$T/s8.cyr"
cc s8 s8.cyr
if [ "$RC" = 0 ]; then ok "S8 a plain #define CYRIUS_COVERAGE switches nothing (a kernel; build with it compiles)"
else bad "S8 #define CYRIUS_COVERAGE + kernel;: rc $RC: $(head -1 "$T/s8.err")"; fi

# S9 — the flag table's headroom under both modes
{ echo 'include "lib/sandhi.cyr"'; awk 'BEGIN { for (i = 0; i < 4; i++) printf "#define COVCAP_USER%d 1\n", i }'; echo 'syscall(60, 6);'; } > "$T/s9.cyr"
RC=0
env CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F" "$CC" < "$T/s9.cyr" > "$T/s9.bin" 2> "$T/s9.err" || RC=$?
if [ "$RC" = 0 ]; then
    chmod +x "$T/s9.bin"; got=0; "$T/s9.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" = 6 ]; then ok "S9 lib/sandhi.cyr + 4 user #defines compiles under CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 (exit 6)"
    else bad "S9 lib/sandhi.cyr + 4 #defines under both modes: exit $got, want 6"; fi
else bad "S9 lib/sandhi.cyr + 4 user #defines under CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1: rc $RC: $(grep -m1 error "$T/s9.err")"; fi

# S10 — mode off is byte-identical: unset == =0 == empty (binary, stderr, rc)
find tests/tcyr -name '*.tcyr' | LC_ALL=C sort | awk 'NR % 12 == 1' > "$T/s10.list"
n10=0; d10=0
while read -r f; do
    n10=$((n10 + 1))
    r0=0; env -u CYRIUS_COVERAGE "$CC" < "$f" > "$T/o0" 2> "$T/r0" || r0=$?
    r1=0; env CYRIUS_COVERAGE=0 "$CC" < "$f" > "$T/o1" 2> "$T/r1" || r1=$?
    r2=0; env CYRIUS_COVERAGE= "$CC" < "$f" > "$T/o2" 2> "$T/r2" || r2=$?
    if [ "$r0" != "$r1" ] || [ "$r0" != "$r2" ] || ! cmp -s "$T/o0" "$T/o1" || ! cmp -s "$T/o0" "$T/o2" \
        || ! cmp -s "$T/r0" "$T/r1" || ! cmp -s "$T/r0" "$T/r2"; then
        d10=$((d10 + 1)); echo "  S10 differs: $f (rc $r0 / $r1 / $r2)"
    fi
done < "$T/s10.list"
if [ "$n10" -lt 30 ]; then bad "S10 the corpus holds $n10 .tcyr (floor 30) — the selection is blind"
elif [ "$d10" != 0 ]; then bad "S10 $d10 of $n10 .tcyr differ between unset, CYRIUS_COVERAGE=0 and CYRIUS_COVERAGE="
else ok "S10 $n10 .tcyr (every 12th, floor 30): unset == CYRIUS_COVERAGE=0 == CYRIUS_COVERAGE= (binary, stderr, rc)"; fi

# ════════════════════════════════════════════════════════════════════════════════════════════════
# GROUPS H / A / B / M / CC / L — THE COUNTERS, THE MAP AND THE END-OF-PROGRAM DUMP (P5B-2). Each
# probe is compiled under the mode and run; its exit must equal the plain build's, and its dump
# (sorted, `\r` dropped) must equal the rows' expectation exactly.
# ════════════════════════════════════════════════════════════════════════════════════════════════
D="$T/cov.out"
HAVE_QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && HAVE_QEMU=1
HAVE_WINE=0; command -v wine > /dev/null 2>&1 && HAVE_WINE=1
[ "$HAVE_QEMU" = 1 ] || echo "  SKIP (named): the aarch64 / native-fork legs — qemu-aarch64 is not installed"
[ "$HAVE_WINE" = 1 ] || echo "  SKIP (named): the PE legs — wine is not installed"
# The cross compilers, built once by the compiler under test.
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> /dev/null \
    && [ -s "$T/cc_cx" ] && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" || rm -f "$T/cc_cx" "$T/cxvm"
"$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
"$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null && [ -s "$T/cc_win" ] && chmod +x "$T/cc_win" || rm -f "$T/cc_win"
if [ "$HAVE_QEMU" = 1 ] && [ -x "$T/cc_a64" ]; then
    "$T/cc_a64" < src/main_aarch64_native.cyr > "$T/cc_a64n" 2> /dev/null && [ -s "$T/cc_a64n" ] && chmod +x "$T/cc_a64n" || rm -f "$T/cc_a64n"
fi
export WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'

# run_bin <runner> <binary> -> GOT (its exit; run in $T, where a relative dump path lands)
run_bin() {
    GOT=0
    chmod +x "$2"
    case $1 in
        qemu) (cd "$T" && timeout 120 qemu-aarch64 "$2" > "$2.out" 2>&1) || GOT=$? ;;
        pe) cp "$2" "$2.exe"; (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" timeout 300 wine "$2.exe" > "$2.out" 2>&1) || GOT=$? ;;
        cxvm) (cd "$T" && timeout 120 "$T/cxvm" < "$2" > "$2.out" 2>&1) || GOT=$? ;;
        *) (cd "$T" && timeout 120 "$2" > "$2.out" 2>&1) || GOT=$? ;;
    esac
}
# hx <row> <src> <dir> <runner> <want dump file> <compiler> [env...]: <src> compiled in <dir> under the
# mode and run; the exit must equal the plain build's (same compiler, same env, mode unset) — and
# $HXE when it is set — and the dump must equal <want> line for line once both are sorted ($HXF set:
# the header and the lines holding $HXF only). The PE runner gets a relative dump path (wine resolves
# it against the program's directory, $T).
HXE=""; HXF=""
hx() {
    row=$1; src=$2; dir=$3; runr=$4; want=$5; comp=$6; shift 6
    f="$D"; [ "$runr" = pe ] && f=cov.out
    rm -f "$D"
    rc=0; (cd "$dir" && env "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$f" $comp < "$src" > "$T/hx.bin" 2> "$T/hx.err") || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/hx.bin" ]; then bad "$row: did not compile under the mode (rc $rc): $(grep -m1 '^error' "$T/hx.err")"; return; fi
    rc=0; (cd "$dir" && env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE "$@" $comp < "$src" > "$T/hx.plain" 2> "$T/hx.perr") || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/hx.plain" ]; then bad "$row: the plain build did not compile (rc $rc): $(grep -m1 '^error' "$T/hx.perr")"; return; fi
    run_bin "$runr" "$T/hx.plain"; pgot=$GOT
    rm -f "$D"
    run_bin "$runr" "$T/hx.bin"; got=$GOT
    if [ "$got" != "$pgot" ]; then bad "$row: exit $got under the mode, $pgot plain"; return; fi
    if [ -n "$HXE" ] && [ "$got" != "$HXE" ]; then bad "$row: exit $got (want $HXE: a result is wrong)"; return; fi
    if [ ! -f "$D" ]; then bad "$row: exit $got, but no dump at the CYRIUS_COVERAGE_FILE"; return; fi
    # a closure's registered name is `__cl` + its fn index (5 digits), which moves with every fn an
    # include adds and differs by target: normalised to `__cl#` (its line names it)
    if [ -n "$HXF" ]; then tr -d '\r' < "$D" | grep -F -e "$HDR" -e "$HXF" | sed 's/ __cl[0-9][0-9][0-9][0-9][0-9]$/ __cl#/' | LC_ALL=C sort > "$T/hx.got"
    else tr -d '\r' < "$D" | sed 's/ __cl[0-9][0-9][0-9][0-9][0-9]$/ __cl#/' | LC_ALL=C sort > "$T/hx.got"; fi
    LC_ALL=C sort "$want" > "$T/hx.want"
    if cmp -s "$T/hx.got" "$T/hx.want"; then ok "$row (exit $got; $(grep -vc '^#' "$T/hx.got") record(s), exact)"
    else bad "$row: exit $got; the dump differs — got: $(tr '\n' '|' < "$T/hx.got") want: $(tr '\n' '|' < "$T/hx.want")"; fi
}
HDR='# cyrius-coverage 1'

# The probes
printf 'fn a(x): i64 { return x + 1; }\nfn b(): i64 { return a(1) + a(0); }\nfn never(): i64 { return 9; }\nfn main(): i64 { b(); return 4; }\n' > "$T/h1.cyr"
printf '%s\n2 <source>:1 a\n1 <source>:2 b\n1 <source>:4 main\n' "$HDR" > "$T/h1.want"
printf 'fn f(x): i64 { return x * 2; }\nvar a = f(3);\nvar z = f(a) + 1;\n' > "$T/h2.cyr"
printf '%s\n2 <source>:1 f\n' "$HDR" > "$T/h2.want"
printf '# an included file\nvar IV = 3;\nfn inc_f(x): i64 { return x + IV; }\nfn inc_never(): i64 { return 0; }\n' > "$T/cov_inc.cyr"
printf 'include "cov_inc.cyr"\nfn ent(): i64 { return inc_f(4); }\nvar r = ent();\n' > "$T/h3.cyr"
printf '%s\n1 cov_inc.cyr:3 inc_f\n1 <source>:2 ent\n' "$HDR" > "$T/h3.want"
printf 'fn never(): i64 { return 1; }\nvar x = 6;\n' > "$T/h4.cyr"
printf '%s\n' "$HDR" > "$T/h4.want"

# ── H: x86 ELF ───────────────────────────────────────────────────────────────────────────────
hx "H1 main returns 4: a x2, b, main counted at their fn lines; never absent" "$T/h1.cyr" "$T" x86 "$T/h1.want" "$CC"
hx "H2 falling off the top level: the exit is the last var; f counted" "$T/h2.cyr" "$T" x86 "$T/h2.want" "$CC"
hx "H3 an included fn is named by its include path and its own line" "$T/h3.cyr" "$T" x86 "$T/h3.want" "$CC"
hx "H4 no fn entered: the header alone" "$T/h4.cyr" "$T" x86 "$T/h4.want" "$CC"

# H5 — the path and the map are image bytes on all six writers (and on none with the mode off)
H5P="$T/h5_COVERAGE_PATH.out"
h5() {   # <writer> <compiler> [env...]
    w=$1; comp=$2; shift 2
    rc=0; (cd "$T" && env "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$H5P" $comp < "$T/h1.cyr" > "$T/h5.bin" 2> /dev/null) || rc=$?
    rc0=0; (cd "$T" && env "$@" $comp < "$T/h1.cyr" > "$T/h5.off" 2> /dev/null) || rc0=$?
    np=$(grep -c -a -F "$H5P" "$T/h5.bin" || true); nm=$(grep -c -a -F '<source>:1 a' "$T/h5.bin" || true)
    op=$(grep -c -a -F -e "$H5P" -e '<source>:1 a' -e "$HDR" "$T/h5.off" || true)
    if [ "$rc" = 0 ] && [ "$rc0" = 0 ] && [ "$np" -ge 1 ] && [ "$nm" -ge 1 ] && [ "$op" = 0 ]; then
        ok "H5 $w: the dump path and the first map line are in the image (and not in the mode-off image)"
    else bad "H5 $w: rc $rc / $rc0 off; path bytes $np, map line $nm, mode-off image hits $op"; fi
}
h5 "x86 ELF" "$CC"
h5 "PE" "$CC" CYRIUS_TARGET_WIN=1
h5 "x86 Mach-O" "$CC" CYRIUS_MACHO=1
h5 "agnos" "$CC" CYRIUS_TARGET_AGNOS=1
if [ -x "$T/cc_a64" ]; then h5 "arm64 Mach-O" "$T/cc_a64" CYRIUS_MACHO_ARM=1; else bad "H5 arm64 Mach-O: src/main_aarch64.cyr did not build"; fi
if [ -x "$T/cc_cx" ]; then h5 "cx" "$T/cc_cx"; else bad "H5 cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

# H6 — the large-static advisory leaves the band and the map out: the instrumented compile of
# src/main.cyr prints the plain figure, give or take the alignment around the two (each over 8 B, so
# 16-aligned on x86, and the vars after them re-align: a few bytes either way — never the ~70 KB the
# band and the map hold for src/main.cyr)
w0=$("$CC" < src/main.cyr 2>&1 > /dev/null | grep 'large static data' | sed 's/^warning: large static data (\([0-9]*\) bytes).*/\1/' || true)
w1=$(env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/h6.out" "$CC" < src/main.cyr 2>&1 > "$T/h6.bin" | grep 'large static data' | sed 's/^warning: large static data (\([0-9]*\) bytes).*/\1/' || true)
dw=$(( ${w1:-0} - ${w0:-0} )); [ "$dw" -lt 0 ] && dw=$((0 - dw))
if [ -n "$w0" ] && [ -n "$w1" ] && [ "$dw" -lt 64 ]; then ok "H6 the large-static advisory does not count the band or the map: $w1 B under the mode, $w0 B plain"
else bad "H6 the large-static figure: '$w0' plain, '$w1' under the mode (want within 64 B)"; fi

# H7 — the hit is emitted under the mode only (an absolute anchor S10's three mode-off spellings
# cannot give): x86's `push rax; mov rax, [rax]; add rax, 1; pop rcx; mov [rcx], rax` appears once
# per counted body (a, b, never, main) under the mode and never with it off
HIT=' 50 48 8b 00 48 05 01 00 00 00 59 48 89 01'
hits() { od -An -v -tx1 "$1" | tr -d '\n' | tr -s ' ' | grep -o "$HIT" | wc -l | tr -d ' '; }
rc=0; (cd "$T" && env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < h1.cyr > h7.on 2> /dev/null) || rc=$?
rc0=0; (cd "$T" && env -u CYRIUS_COVERAGE "$CC" < h1.cyr > h7.off 2> /dev/null) || rc0=$?
if [ "$rc" = 0 ] && [ "$rc0" = 0 ] && [ "$(hits "$T/h7.on")" = 4 ] && [ "$(hits "$T/h7.off")" = 0 ]; then
    ok "H7 the hit: 4 in the instrumented image (one per body), 0 with the mode off"
else bad "H7 rc $rc / $rc0; hits $(hits "$T/h7.on") under the mode (want 4), $(hits "$T/h7.off") off (want 0)"; fi

# H8 — a record over the dump's 992 B line budget is written straight out, whole (a 1000-character
# fn name), between two ordinary records that go through the buffer
NL=$(printf 'n%.0s' $(seq 1000))
printf 'fn a(): i64 { return 1; }\nfn %s(): i64 { return 2; }\nfn b(): i64 { return 3; }\nvar x = a() + %s() + b();\n' "$NL" "$NL" > "$T/h8.cyr"
printf '%s\n1 <source>:1 a\n1 <source>:2 %s\n1 <source>:3 b\n' "$HDR" "$NL" > "$T/h8.want"
hx "H8 a 1013 B record (a 1000-character name) is written whole" "$T/h8.cyr" "$T" x86 "$T/h8.want" "$CC"

# ── A2: H1-H3 under every x86 codegen mode ───────────────────────────────────────────────────
for m in CYRIUS_IR=1 CYRIUS_IR=3 CYRIUS_DCE=1 CYRIUS_PIE=1 CYRIUS_STACK_ARRAYS=0; do
    hx "A2 $m: H1" "$T/h1.cyr" "$T" x86 "$T/h1.want" "$CC" "$m"
    hx "A2 $m: H2" "$T/h2.cyr" "$T" x86 "$T/h2.want" "$CC" "$m"
    hx "A2 $m: H3" "$T/h3.cyr" "$T" x86 "$T/h3.want" "$CC" "$m"
done

# ── A4: the argument shapes — every register is dead at the body start, so a value the hit would
# clobber shows in the result: a 7-argument fn (one on the stack), a 4-argument fn (Win64's four
# registers), a `#regalloc` fn, a capturing closure (its env register), a >16 B struct return (the
# return pointer), a coroutine (Win64's SELF in rcx; counted once, at state 0, across four forces).
# The program exits 50 when every result is right; the dump keeps the lib's records out (grep). ──
cat > "$T/a4.cyr" << 'EOF'
include "lib/alloc.cyr"
struct Big { a; b; c; }
fn mk(x): Big { var g = Big { x, x + 1, x + 2 }; return g; }
fn seven(a, b, c, d, e, f, g): i64 { return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7; }
#regalloc
fn hot(a, b) { var x = a + b; var y = a * b; return x + y; }
fn four(a, b, c, d): i64 { return a * 1000 + b * 100 + c * 10 + d; }
fn capt(k): i64 { var f = |x| k + x; return callptr(f, 2); }
fn main(): i64 {
    alloc_init();
    var r = 0;
    var g: Big = mk(10);
    if (g.a + g.b + g.c != 33) { r = r + 1; }
    if (seven(1, 2, 3, 4, 5, 6, 7) != 140) { r = r + 2; }
    if (hot(3, 4) != 19) { r = r + 4; }
    if (four(1, 2, 3, 4) != 1234) { r = r + 8; }
    if (four(5, 6, 7, 8) != 5678) { r = r + 16; }
    if (capt(40) != 42) { r = r + 32; }
    return r + 50;
}
EOF
printf '%s\n1 <source>:3 mk\n1 <source>:4 seven\n1 <source>:6 hot\n2 <source>:7 four\n1 <source>:8 capt\n1 <source>:8 __cl#\n1 <source>:9 main\n' "$HDR" > "$T/a4.want"
cat > "$T/a5.cyr" << 'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
    var x = 1;
    var s1 = await nopark();
    x = x + 10;
    var s2 = await nopark();
    x = x + 100;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C); var r2 = future_force(C); var r3 = future_force(C); var r4 = future_force(C);
    if (r4 != 111) { return 1; }
    return 50;
}
EOF
printf '%s\n2 <source>:8 nopark\n1 <source>:9 steps$impl\n1 <source>:17 main\n' "$HDR" > "$T/a5.want"
# ax <row> <src> <runner> <want> <compiler> [env...]: hx in the tree (its lib includes resolve), the
# exit exactly 50, over the program's own records (the lib's vary with the lib)
ax() {
    row=$1; src=$2; runr=$3; want=$4; comp=$5; shift 5
    HXE=50; HXF='<source>'
    hx "$row" "$src" "$ROOT" "$runr" "$want" "$comp" "$@"
    HXE=""; HXF=""
}
ax "A4 x86" "$T/a4.cyr" x86 "$T/a4.want" "$CC"
ax "A4 x86, CYRIUS_IR=3" "$T/a4.cyr" x86 "$T/a4.want" "$CC" CYRIUS_IR=3
ax "A4 coroutine, x86 (CYRIUS_ASYNC=1)" "$T/a5.cyr" x86 "$T/a5.want" "$CC" CYRIUS_ASYNC=1
if [ "$HAVE_QEMU" = 1 ]; then
    if [ -x "$T/cc_a64" ]; then ax "A4 aarch64 (qemu)" "$T/a4.cyr" qemu "$T/a4.want" "$T/cc_a64"
    else bad "A4 aarch64: src/main_aarch64.cyr did not build"; fi
fi
if [ "$HAVE_WINE" = 1 ]; then
    ax "A4 PE (wine; Win64's four argument registers)" "$T/a4.cyr" pe "$T/a4.want" "$CC" CYRIUS_TARGET_WIN=1
    ax "A4 coroutine, PE (wine; SELF in rcx)" "$T/a5.cyr" pe "$T/a5.want" "$CC" CYRIUS_TARGET_WIN=1 CYRIUS_ASYNC=1
fi

# ── B1: the band covers the highest fn index — generic instances minted at their call sites in
# pass 2 (after the dump's own fns) and a closure registered after them ─────────────────────────
printf 'fn a(): i64 { return 1; }\nfn gen<T>(x: T): i64 { return 2; }\nfn b(): i64 { return 3; }\nvar r = a();\nvar s = gen<f64>(1.5);\nvar t = gen<i32>(7);\nvar u = gen(4);\nvar cl = || 3;\nvar z = r + s + t + u + b();\n' > "$T/b1.cyr"
printf '%s\n1 <source>:1 a\n1 <source>:2 gen\n1 <source>:3 b\n1 <source>:2 gen$f64\n1 <source>:2 gen$i32\n' "$HDR" > "$T/b1.want"
hx "B1 the highest indexes (instances minted in pass 2) count exactly" "$T/b1.cyr" "$T" x86 "$T/b1.want" "$CC"

# ── M3: a large program (tests/tcyr/compiler/large_source.tcyr, ~6,000 fns through its includes)
# compiles and dumps — verbatim: its last line `syscall(60, r);` is an exit the syscall builtin's hook
# sees (P5B-3). ────────────────────────────────────────────────────────────────────────────────
if [ "$(tail -1 tests/tcyr/compiler/large_source.tcyr)" != 'syscall(60, r);' ]; then bad "M3: large_source.tcyr no longer ends in 'syscall(60, r);' — re-derive the row"
else
    rm -f "$D"
    rc=0; env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < tests/tcyr/compiler/large_source.tcyr > "$T/m3.bin" 2> "$T/m3.err" || rc=$?
    if [ "$rc" != 0 ]; then bad "M3: rc $rc: $(grep -m1 '^error' "$T/m3.err")"
    else
        run_bin x86 "$T/m3.bin"
        nr=$(grep -cE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$' "$D" 2>/dev/null || true); nr=${nr:-0}
        nbad=$(grep -vcE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$|^- [^ ]+:[0-9]+ [^ ]+$|^# cyrius-coverage 1$' "$D" 2>/dev/null || true); nbad=${nbad:-0}
        nh=$(grep -c "^$HDR\$" "$D" 2>/dev/null || true); nh=${nh:-0}
        nn=$(grep -cE '^- ' "$D" 2>/dev/null || true); nn=${nn:-0}
        if [ "$GOT" = 0 ] && grep -q ' passed, 0 failed' "$T/m3.bin.out" && [ "$nr" -ge 10 ] && [ "$nbad" = 0 ] && [ "$nh" = 1 ] \
            && grep -qE '^[0-9]+ lib/string\.cyr:[0-9]+ streq$' "$D"; then
            ok "M3 large_source.tcyr (verbatim, its own syscall(60, r)): exit 0, its asserts pass, ONE block of $nr well-formed records + $nn '-' (a lib #naked fn) (streq at its lib/string.cyr line)"
        else bad "M3 large_source.tcyr: exit $GOT, $nh block(s), $nr records, $nbad malformed: $(grep -m1 'passed' "$T/m3.bin.out")"; fi
    fi
fi

# ── CC1: an instrumented cycc reproduces cycc from src, and its dump holds more than 500 records —
# verbatim: src/main.cyr leaves through its own last line, `syscall(SYS_EXIT, _had_error);`, which
# the syscall builtin's hook sees (P5B-3). ─────────────────────────────────────────────────────────
if [ "$(tail -1 src/main.cyr)" != 'syscall(SYS_EXIT, _had_error);' ]; then bad "CC1: src/main.cyr no longer ends in 'syscall(SYS_EXIT, _had_error);' — re-derive the row"
else
    rm -f "$D"
    rc=0; env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < src/main.cyr > "$T/cc1.bin" 2> /dev/null || rc=$?
    "$CC" < src/main.cyr > "$T/cc1.ref" 2> /dev/null || true
    if [ "$rc" != 0 ]; then bad "CC1: the instrumented cycc did not compile (rc $rc)"
    else
        chmod +x "$T/cc1.bin"; got=0; env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE "$T/cc1.bin" < src/main.cyr > "$T/cc1.out" 2> /dev/null || got=$?
        nr=$(grep -cE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$' "$D" 2>/dev/null || true); nr=${nr:-0}
        nh=$(grep -c "^$HDR\$" "$D" 2>/dev/null || true); nh=${nh:-0}
        if [ "$got" = 0 ] && [ -s "$T/cc1.ref" ] && cmp -s "$T/cc1.out" "$T/cc1.ref"; then ok "CC1a the instrumented cycc compiles src/main.cyr byte-identical to cycc(src)"
        else bad "CC1a the instrumented cycc: exit $got; its output $(wc -c < "$T/cc1.out") B against cycc(src)'s $(wc -c < "$T/cc1.ref") B"; fi
        if [ "$nh" = 1 ] && [ "$nr" -gt 500 ] && grep -qE '^[0-9]+ src/common/util\.cyr:[0-9]+ L64$' "$D"; then ok "CC1b its dump (through src/main.cyr's own SYS_EXIT): ONE block, $nr records (> 500), L64 at its src/common/util.cyr line"
        else bad "CC1b its dump: $nh block(s) (want 1), $nr records (want > 500, with src/common/util.cyr's L64)"; fi
    fi
fi

# ── L: the other targets — aarch64 (qemu), the native aarch64 fork (qemu), PE through main.cyr and
# through the main_win fork (wine), cx (cxvm; its H1 returns from the auto-called `main`, 6.7.11)
# ──────────────────────────────────────────────────────────────────────────────────────────────────
if [ "$HAVE_QEMU" = 1 ]; then
    if [ -x "$T/cc_a64" ]; then
        hx "L1 aarch64 (qemu): H1" "$T/h1.cyr" "$T" qemu "$T/h1.want" "$T/cc_a64"
        hx "L1 aarch64 (qemu): H2" "$T/h2.cyr" "$T" qemu "$T/h2.want" "$T/cc_a64"
        hx "L1 aarch64 (qemu): H3" "$T/h3.cyr" "$T" qemu "$T/h3.want" "$T/cc_a64"
    else bad "L1 aarch64: src/main_aarch64.cyr did not build"; fi
    if [ -x "$T/cc_a64n" ]; then
        hx "L2 the main_aarch64_native fork (qemu): H1" "$T/h1.cyr" "$T" qemu "$T/h1.want" "qemu-aarch64 $T/cc_a64n"
        hx "L2 the main_aarch64_native fork (qemu): H3" "$T/h3.cyr" "$T" qemu "$T/h3.want" "qemu-aarch64 $T/cc_a64n"
    else bad "L2 src/main_aarch64_native.cyr did not build"; fi
fi
if [ "$HAVE_WINE" = 1 ]; then
    hx "L3 PE through main.cyr (wine): H1" "$T/h1.cyr" "$T" pe "$T/h1.want" "$CC" CYRIUS_TARGET_WIN=1
    hx "L3 PE through main.cyr (wine): H2" "$T/h2.cyr" "$T" pe "$T/h2.want" "$CC" CYRIUS_TARGET_WIN=1
    hx "L3 PE through main.cyr (wine): H3" "$T/h3.cyr" "$T" pe "$T/h3.want" "$CC" CYRIUS_TARGET_WIN=1
    if [ -x "$T/cc_win" ]; then
        hx "L4 PE through the main_win fork (wine): H1" "$T/h1.cyr" "$T" pe "$T/h1.want" "$T/cc_win"
        hx "L4 PE through the main_win fork (wine): H2" "$T/h2.cyr" "$T" pe "$T/h2.want" "$T/cc_win"
    else bad "L4 src/main_win.cyr did not build"; fi
fi
if [ -x "$T/cc_cx" ]; then
    printf 'fn code(): i64 { return 5; }\nfn deep2(): i64 { return code(); }\nfn deep1(): i64 { return deep2(); }\nvar r = deep1();\nvar q = deep1();\n' > "$T/l5.cyr"
    printf '%s\n2 <source>:1 code\n2 <source>:2 deep2\n2 <source>:3 deep1\n' "$HDR" > "$T/l5.want"
    hx "L5 cx (cxvm): three frames deep, twice; the exit is the last var" "$T/l5.cyr" "$T" cxvm "$T/l5.want" "$T/cc_cx"
    hx "L5 cx (cxvm): H3" "$T/h3.cyr" "$T" cxvm "$T/h3.want" "$T/cc_cx"
    hx "L5 cx (cxvm): H1 — the auto-called main counted, its return the exit (6.7.11)" "$T/h1.cyr" "$T" cxvm "$T/h1.want" "$T/cc_cx"
else bad "L5 cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

# ════════════════════════════════════════════════════════════════════════════════════════════════
# GROUP E — EVERY EXIT ROUTE (P5B-3). A program that leaves through an exit syscall never reaches the
# top level's `_cov_tail`, so the syscall builtin hooks each exit whose NUMBER is a compile-time
# constant (parse_cov.cyr `_sc_args_done` / `_cov_is_exit`, the 1-for-1 swap for
# `_macho_warn_unrouted` in `_PARSE_FACTOR_IMPL`): after the arguments are evaluated and pushed,
# before every target lowering. The exit numbers are per target, measured: x86 ELF / x86 Mach-O / cx
# {60, 231}; aarch64 {60, 93, 94} (raw 231 is munlockall there); PE {60} (raw 231 is -38 and the
# program goes on; `sys_exit_group` issues 60); agnos {0}. Each row compiles under the mode, runs,
# holds the exit to the plain build's (and to its stated value), and holds the program's own
# (`<source>`) records and the BLOCK count exactly (the lib's records vary with the target's lib).
# ════════════════════════════════════════════════════════════════════════════════════════════════
cat > "$T/e1a.cyr" << 'EOF'
include "lib/syscalls.cyr"
fn code(): i64 { return 5; }
fn deep2(): i64 { sys_exit(code()); return 0; }
fn deep1(): i64 { return deep2(); }
var r = deep1();
var z = 9;
EOF
cat > "$T/e1b.cyr" << 'EOF'
include "lib/syscalls.cyr"
fn code(): i64 { return 5; }
fn deep2(): i64 { syscall(SYS_EXIT, code()); return 0; }
fn deep1(): i64 { return deep2(); }
var r = deep1();
var z = 9;
EOF
printf '%s\n1 <source>:2 code\n1 <source>:3 deep2\n1 <source>:4 deep1\n' "$HDR" > "$T/e1.want"
printf 'fn main(): i64 { return 6; }\nsyscall(60, main());\n' > "$T/e2.cyr"
printf '%s\n1 <source>:1 main\n' "$HDR" > "$T/e2.want"
printf 'include "lib/syscalls.cyr"\nfn ex(): i64 { syscall(SYS_EXIT, 3); return 0; }\nvar r = ex();\nvar z = 9;\n' > "$T/e3a.cyr"
printf 'include "lib/syscalls.cyr"\nfn ex(): i64 { sys_exit_group(4); return 0; }\nvar r = ex();\nvar z = 9;\n' > "$T/e3b.cyr"
printf '%s\n1 <source>:2 ex\n' "$HDR" > "$T/e3.want"
printf 'fn f(): i64 { return 1; }\nvar r = f();\nvar a = syscall(231, 23);\nsyscall(60, 9);\n' > "$T/e4.cyr"
printf '%s\n1 <source>:1 f\n' "$HDR" > "$T/e4.want"
printf 'fn main(): i64 {\n    var r = syscall(231, 23);\n    if (r == 0 - 38) { return 78; }\n    return 1;\n}\n' > "$T/e5.cyr"
printf '%s\n1 <source>:1 main\n' "$HDR" > "$T/e5.want"
printf 'var A: i64[4];\nfn bad(i): i64 { return A[i]; }\nfn main(): i64 { return bad(7); }\n' > "$T/e6.cyr"
printf '%s\n1 <source>:2 bad\n1 <source>:3 main\n' "$HDR" > "$T/e6.want"
cat > "$T/e7.cyr" << 'EOF'
include "lib/string.cyr"
include "lib/syscalls.cyr"
include "lib/assert.cyr"
fn chk(x): i64 { if (x > 2) { panic("too big"); } return x; }
fn main(): i64 { chk(1); chk(5); return 9; }
EOF
printf '%s\n2 <source>:4 chk\n1 <source>:5 main\n' "$HDR" > "$T/e7.want"
cat > "$T/e8.cyr" << 'EOF'
include "lib/syscalls.cyr"
fn child(): i64 { return 3; }
fn main(): i64 {
    var pid = sys_fork();
    if (pid == 0) { child(); sys_exit(0); }
    var st = 0;
    sys_waitpid(pid, &st, 0);
    return 7;
}
EOF
printf '%s\n%s\n1 <source>:2 child\n1 <source>:3 main\n1 <source>:3 main\n' "$HDR" "$HDR" > "$T/e8.want"
cat > "$T/e9.cyr" << 'EOF'
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/thread.cyr"
fn wk(arg): i64 { return arg + 1; }
fn main(): i64 {
    alloc_init();
    var t0 = thread_create(&wk, 1);
    var t1 = thread_create(&wk, 2);
    var t2 = thread_create(&wk, 3);
    var t3 = thread_create(&wk, 4);
    thread_join(t0); thread_join(t1); thread_join(t2); thread_join(t3);
    return 11;
}
EOF
printf '%s\n4 <source>:4 wk\n1 <source>:5 main\n' "$HDR" > "$T/e9.want"
printf 'var n = 60;\nfn f(): i64 { return 1; }\nvar r = f();\nsyscall(n, 0);\n' > "$T/e11.cyr"
printf 'const K = 60;\nfn f(): i64 { syscall(K, 7); return 0; }\nvar r = f();\n' > "$T/e12.cyr"
printf '%s\n1 <source>:2 f\n' "$HDR" > "$T/e12.want"
printf '#inline\nfn die(c): i64 { syscall(60, c); return 0; }\nfn f(): i64 { die(12); return 0; }\nvar r = f();\n' > "$T/e13.cyr"
printf '%s\n1 <source>:2 die\n1 <source>:3 f\n' "$HDR" > "$T/e13.want"

# ex_ <row> <src> <runner> <want> <exit> <compiler> [env...]: hx in the tree (lib includes resolve
# there) over the program's own records, the exit stated
ex_() {
    row=$1; src=$2; runr=$3; want=$4; HXE=$5; comp=$6; shift 6
    HXF='<source>'
    hx "$row" "$src" "$ROOT" "$runr" "$want" "$comp" "$@"
    HXE=""; HXF=""
}
# en <row> <src> <runner> <compiler> [env...]: an exit the hook cannot see — the exit equals the
# plain build's, and NO dump is written (the documented residual, never a partial block)
en() {
    row=$1; src=$2; runr=$3; comp=$4; shift 4
    f="$D"; [ "$runr" = pe ] && f=cov.out
    rm -f "$D"
    rc=0; (cd "$ROOT" && env "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$f" $comp < "$src" > "$T/en.bin" 2> "$T/en.err") || rc=$?
    rc0=0; (cd "$ROOT" && env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE "$@" $comp < "$src" > "$T/en.plain" 2> /dev/null) || rc0=$?
    if [ "$rc" != 0 ] || [ "$rc0" != 0 ]; then bad "$row: did not compile (rc $rc / $rc0 plain): $(grep -m1 '^error' "$T/en.err")"; return; fi
    run_bin "$runr" "$T/en.plain"; pgot=$GOT
    rm -f "$D"
    run_bin "$runr" "$T/en.bin"; got=$GOT
    if [ "$got" != "$pgot" ]; then bad "$row: exit $got under the mode, $pgot plain"
    elif [ -e "$D" ]; then bad "$row: exit $got, but a dump was written: $(tr '\n' '|' < "$D")"
    else ok "$row (exit $got; no dump)"; fi
}
# eleg <leg> <runner> <compiler> [env...]: the rows every target runs (each falls off or calls its
# top level explicitly)
eleg() {
    leg=$1; runr=$2; comp=$3; shift 3
    ex_ "E1a $leg: sys_exit(code()) three frames deep" "$T/e1a.cyr" "$runr" "$T/e1.want" 5 "$comp" "$@"
    ex_ "E1b $leg: syscall(SYS_EXIT, code()) — the argument evaluated before the dump" "$T/e1b.cyr" "$runr" "$T/e1.want" 5 "$comp" "$@"
    ex_ "E2 $leg: top-level syscall(60, main())" "$T/e2.cyr" "$runr" "$T/e2.want" 6 "$comp" "$@"
    ex_ "E3a $leg: syscall(SYS_EXIT, 3) in a fn" "$T/e3a.cyr" "$runr" "$T/e3.want" 3 "$comp" "$@"
    ex_ "E3b $leg: sys_exit_group(4) in a fn" "$T/e3b.cyr" "$runr" "$T/e3.want" 4 "$comp" "$@"
    en  "E11 $leg: syscall(n, 0) with a runtime-variable number (the documented residual)" "$T/e11.cyr" "$runr" "$comp" "$@"
    ex_ "E12 $leg: const K = 60; syscall(K, 7)" "$T/e12.cyr" "$runr" "$T/e12.want" 7 "$comp" "$@"
    ex_ "E13 $leg: an exit inside an #inline fn" "$T/e13.cyr" "$runr" "$T/e13.want" 12 "$comp" "$@"
}
# emain <leg> <runner> <compiler> [env...]: the rows that leave from an auto-called `main`
emain() {
    leg=$1; runr=$2; comp=$3; shift 3
    ex_ "E6 $leg: a CYRIUS_BOUNDS=1 violation (the checker's own exit)" "$T/e6.cyr" "$runr" "$T/e6.want" 134 "$comp" "$@" CYRIUS_BOUNDS=1
    ex_ "E7 $leg: panic" "$T/e7.cyr" "$runr" "$T/e7.want" 1 "$comp" "$@"
}
# eproc <leg> <runner> <compiler>: fork and threads (POSIX targets)
eproc() {
    leg=$1; runr=$2; comp=$3
    ex_ "E8 $leg: fork — the child's block and the parent's, both whole" "$T/e8.cyr" "$runr" "$T/e8.want" 7 "$comp"
    nb=$(tr -d '\r' < "$D" 2>/dev/null | grep -vcE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$|^- [^ ]+:[0-9]+ [^ ]+$|^# cyrius-coverage 1$' || true)
    if [ -f "$D" ] && [ "${nb:-0}" = 0 ]; then ok "E8' $leg: every line of the two blocks is a header or a whole record"
    else bad "E8' $leg: ${nb:-?} malformed line(s) in the fork's dump: $(tr '\n' '|' < "$D" 2>/dev/null | cut -c1-300)"; fi
    ex_ "E9 $leg: 4 lib/thread workers (their raw-asm exits do not dump; the process exit does, once)" "$T/e9.cyr" "$runr" "$T/e9.want" 11 "$comp"
}

# ── E on x86 ELF ──────────────────────────────────────────────────────────────────────────────
eleg x86 x86 "$CC"
ex_ "E4 x86: raw syscall(231, 23) is exit_group here — exit 23, ONE block" "$T/e4.cyr" x86 "$T/e4.want" 23 "$CC"
emain x86 x86 "$CC"
eproc x86 x86 "$CC"
for m in CYRIUS_IR=1 CYRIUS_IR=3 CYRIUS_DCE=1 CYRIUS_PIE=1 CYRIUS_STACK_ARRAYS=0; do
    ex_ "E1b x86, $m" "$T/e1b.cyr" x86 "$T/e1.want" 5 "$CC" "$m"
    ex_ "E7 x86, $m" "$T/e7.cyr" x86 "$T/e7.want" 1 "$CC" "$m"
done

# ── E10: an exit inside a #naked fn compiles, and no call is emitted there (a #naked fn has no
# frame to call from); the control — the same exit in an ordinary fn — has the dump's one call
# between its last argument and its `syscall` ──────────────────────────────────────────────────
# ncalls <binary> <imm>: the `call`s between `mov $<imm>,%eax` and the next `syscall`
ncalls() { objdump -d "$1" | awk -v im="\$$2,%eax" 'index($0, "mov    " im) { f = 1; c = 0; next } f && /\tcall/ { c++ } f && /\tsyscall/ { print c; exit }'; }
if command -v objdump > /dev/null 2>&1; then
    printf '#naked\nfn nk() { syscall(60, 77); }\nfn okx(): i64 { syscall(60, 78); return 0; }\nvar sel = 0;\nif (sel == 1) { nk(); }\nokx();\n' > "$T/e10.cyr"
    printf '%s\n- <source>:2 nk\n1 <source>:3 okx\n' "$HDR" > "$T/e10.want"
    ex_ "E10a a program with an exit inside a #naked fn compiles and dumps through its other exit (nk: not instrumented)" "$T/e10.cyr" x86 "$T/e10.want" 78 "$CC"
    rc=0; (cd "$T" && env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < e10.cyr > e10.bin 2> /dev/null) || rc=$?
    n77=$(ncalls "$T/e10.bin" 0x4d); n78=$(ncalls "$T/e10.bin" 0x4e)
    if [ "$rc" = 0 ] && [ "$n77" = 0 ] && [ "$n78" = 1 ]; then ok "E10b objdump: no call before the #naked fn's exit; the ordinary fn's exit has the dump's one"
    else bad "E10b objdump: rc $rc; calls before the #naked exit '$n77' (want 0), before the ordinary exit '$n78' (want 1)"; fi
else echo "  SKIP (named): E10a / E10b / AG1 / AG2 — objdump is not installed"; fi

# ── AG: agnos (generated, NOT run — there is no agnos host here, and #58 is vfork on Linux): the
# dump's open #7 with 0x501, the seek #58, the close #6; the exit is #0, so a call precedes
# `syscall(0, ..)` and none precedes `syscall(60, ..)` (60 is no exit on agnos) ─────────────────
printf 'fn ex0(): i64 { syscall(0, 77); return 0; }\nfn nx(): i64 { syscall(60, 78); return 0; }\nvar sel = 0;\nif (sel == 1) { nx(); }\nex0();\n' > "$T/ag.cyr"
rc=0; (cd "$T" && env CYRIUS_TARGET_AGNOS=1 CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/ag_never_run.out" "$CC" < ag.cyr > ag.bin 2> /dev/null) || rc=$?
rc0=0; (cd "$T" && env CYRIUS_TARGET_AGNOS=1 "$CC" < ag.cyr > ag.off 2> /dev/null) || rc0=$?
if command -v objdump > /dev/null 2>&1; then
    agm=""
    for im in 0x7 0x501 0x3a 0x6; do
        a1=$(objdump -d "$T/ag.bin" | grep -cE "mov +\\\$$im,%eax" || true); a0=$(objdump -d "$T/ag.off" | grep -cE "mov +\\\$$im,%eax" || true)
        [ "$a1" -gt "$a0" ] || agm="$agm $im($a1 on, $a0 off)"
    done
    if [ "$rc" = 0 ] && [ "$rc0" = 0 ] && [ -z "$agm" ]; then ok "AG1 agnos: the dump's #7 / 0x501 / #58 / #6 immediates are in the instrumented image only"
    else bad "AG1 agnos: rc $rc / $rc0; immediates not added by the mode:$agm"; fi
    a0c=$(ncalls "$T/ag.bin" 0x4d); a60=$(ncalls "$T/ag.bin" 0x4e)
    if [ "$rc" = 0 ] && [ "$a0c" = 1 ] && [ "$a60" = 0 ]; then ok "AG2 agnos: the dump's call precedes syscall(0, ..) (its exit), none precedes syscall(60, ..)"
    else bad "AG2 agnos: calls before syscall(0, ..) '$a0c' (want 1), before syscall(60, ..) '$a60' (want 0)"; fi
fi

# ── DW: Darwin's O_WRONLY | O_CREAT | O_APPEND is 0x209 (Linux's 1089 = 0x441 would be O_WRONLY |
# O_NONBLOCK | ... there): x86 Mach-O `mov eax, 0x209` (b8 09 02 00 00), arm64 Mach-O `movz x0,
# #0x209` (20 41 80 d2) — and the Linux immediate in neither. Compile-verified here; the run is the
# ach / ecb leg (P5B-7). ─────────────────────────────────────────────────────────────────────────
hexs() { od -An -v -tx1 "$1" | tr -d '\n' | tr -s ' ' | grep -o "$2" | wc -l | tr -d ' '; }
dw() {   # <writer> <compiler> <darwin bytes> <linux bytes> [env...]
    w=$1; comp=$2; dk=$3; lk=$4; shift 4
    rc=0; (cd "$T" && env "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/dw_never_run.out" $comp < h2.cyr > dw.bin 2> /dev/null) || rc=$?
    nd=$(hexs "$T/dw.bin" "$dk"); nl=$(hexs "$T/dw.bin" "$lk")
    if [ "$rc" = 0 ] && [ "$nd" -ge 1 ] && [ "$nl" = 0 ]; then ok "DW $w: the dump opens with Darwin's 0x209 ($nd), never Linux's 0x441"
    else bad "DW $w: rc $rc; Darwin 0x209 x$nd (want >= 1), Linux 0x441 x$nl (want 0)"; fi
}
dw "x86 Mach-O (CYRIUS_MACHO=1)" "$CC" ' b8 09 02 00 00' ' b8 41 04 00 00' CYRIUS_MACHO=1
if [ -x "$T/cc_a64" ]; then dw "arm64 Mach-O (CYRIUS_MACHO_ARM=1)" "$T/cc_a64" ' 20 41 80 d2' ' 20 88 80 d2' CYRIUS_MACHO_ARM=1
else bad "DW arm64 Mach-O: src/main_aarch64.cyr did not build"; fi

# ── E on the other targets ────────────────────────────────────────────────────────────────────
if [ "$HAVE_QEMU" = 1 ]; then
    if [ -x "$T/cc_a64" ]; then
        eleg "aarch64 (qemu)" qemu "$T/cc_a64"
        ex_ "E4 aarch64 (qemu): raw 231 is munlockall here; syscall(60, 9) exits 9 with ONE block" "$T/e4.cyr" qemu "$T/e4.want" 9 "$T/cc_a64"
        emain "aarch64 (qemu)" qemu "$T/cc_a64"
        eproc "aarch64 (qemu)" qemu "$T/cc_a64"
    else bad "E aarch64: src/main_aarch64.cyr did not build"; fi
    if [ -x "$T/cc_a64n" ]; then
        eleg "the native aarch64 fork (qemu)" qemu "qemu-aarch64 $T/cc_a64n"
        ex_ "E4 the native aarch64 fork (qemu): exit 9, ONE block" "$T/e4.cyr" qemu "$T/e4.want" 9 "qemu-aarch64 $T/cc_a64n"
        emain "the native aarch64 fork (qemu)" qemu "qemu-aarch64 $T/cc_a64n"
    else bad "E src/main_aarch64_native.cyr did not build"; fi
fi
if [ "$HAVE_WINE" = 1 ]; then
    eleg "PE through main.cyr (wine)" pe "$CC" CYRIUS_TARGET_WIN=1
    ex_ "E5a PE through main.cyr (wine): raw 231 is -38 here, the program goes on to exit 78 — ONE block" "$T/e5.cyr" pe "$T/e5.want" 78 "$CC" CYRIUS_TARGET_WIN=1
    ex_ "E5b PE through main.cyr (wine): raw 231 then syscall(60, 9) — exit 9, ONE block" "$T/e4.cyr" pe "$T/e4.want" 9 "$CC" CYRIUS_TARGET_WIN=1
    emain "PE through main.cyr (wine)" pe "$CC" CYRIUS_TARGET_WIN=1
    if [ -x "$T/cc_win" ]; then
        eleg "PE through the main_win fork (wine)" pe "$T/cc_win"
        ex_ "E5a PE through the main_win fork (wine): raw 231, exit 78, ONE block" "$T/e5.cyr" pe "$T/e5.want" 78 "$T/cc_win"
        emain "PE through the main_win fork (wine)" pe "$T/cc_win"
    else bad "E src/main_win.cyr did not build"; fi
fi
if [ -x "$T/cc_cx" ]; then
    eleg "cx (cxvm)" cxvm "$T/cc_cx"
    ex_ "E4 cx (cxvm): cxvm passes 231 to the host as exit_group — exit 23, ONE block" "$T/e4.cyr" cxvm "$T/e4.want" 23 "$T/cc_cx"
    emain "cx (cxvm)" cxvm "$T/cc_cx"
else bad "E cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

# ════════════════════════════════════════════════════════════════════════════════════════════════
# GROUP F — EVERY FN SHAPE (P5B-4). An `#inline` replay re-parses its callee's body inside the
# CALLER and bumps the callee's counter (parse_cov.cyr `_cov_body` with ti -1, the 1-for-1 swap for
# `PARSE_FNCALL`'s PARSE_PROG); a closure bumps its own once its frame is open (`_cl_frame_open`,
# the 1-for-1 swap for `_PARSE_FACTOR_IMPL`'s ESUBRSP), named at its closing bar's line; a `#naked`
# fn is recorded as not instrumented (`- <file>:<line> <name>`). Each probe falls off the top level,
# holds the exit to the plain build's and to its stated value, and the whole dump exactly (no lib is
# included, so every record is the program's own).
# ════════════════════════════════════════════════════════════════════════════════════════════════
cat > "$T/f1.cyr" << 'EOF'
#inline
fn inl(x): i64 { return x + 1; }
#inline
fn inl2(x): i64 { return inl(x) * 2; }
fn user(): i64 { return inl(2) + inl(3) + inl2(1); }
var r = user();
EOF
printf '%s\n3 <source>:2 inl\n1 <source>:4 inl2\n1 <source>:5 user\n' "$HDR" > "$T/f1.want"
cat > "$T/f2.cyr" << 'EOF'
var add = |a, b| a + b;
var g = |a, b| {
    return a * b;
};
var h = |a,
         b| a - b;
var z0 = || 5;
fn mk(): i64 { var c = |x| x * 3; return callptr(c, 2) + callptr(c, 1); }
var r = callptr(add, 1, 2) + callptr(add, 3, 4) + callptr(g, 2, 3) + callptr(h, 9, 1) + callptr(z0) + mk();
EOF
printf '%s\n2 <source>:1 __cl#\n1 <source>:2 __cl#\n1 <source>:6 __cl#\n1 <source>:7 __cl#\n1 <source>:8 mk\n2 <source>:8 __cl#\n' "$HDR" > "$T/f2.want"
printf 'fn gen<T>(x: T): i64 { return 2; }\nfn gnever<T>(x: T): i64 { return 3; }\nvar g = gen<f64>(1.5) + gen(4);\n' > "$T/f3.cyr"
printf '%s\n1 <source>:1 gen\n1 <source>:1 gen$f64\n' "$HDR" > "$T/f3.want"
cat > "$T/f4.cyr" << 'EOF'
struct P { a; b; }
impl P {
    fn sum(self): i64 { return self.a + self.b; }
    fn unused(self): i64 { return 0; }
}
fn run(): i64 { var p = P { 3, 4 }; return p.sum(); }
var s = run();
EOF
printf '%s\n1 <source>:3 P_sum\n1 <source>:6 run\n' "$HDR" > "$T/f4.want"
printf '#naked\nfn nk() { syscall(60, 77); }\nfn f(): i64 { return 1; }\nvar r = f();\n' > "$T/f6.cyr"
printf '%s\n- <source>:2 nk\n1 <source>:3 f\n' "$HDR" > "$T/f6.want"
# cx ignores `#naked` (parse_fn.cyr: the attribute is not taken on cx — it has no raw-asm body), so
# there `nk` is an ordinary fn, instrumented and never entered: no record at all
printf '%s\n1 <source>:3 f\n' "$HDR" > "$T/f6cx.want"
F6W="$T/f6.want"; F6N=""
printf 'var A: i64[4];\nfn rd(i): i64 { return A[i]; }\nA[2] = 5;\nvar r = rd(1) + rd(2);\n' > "$T/f7.cyr"
printf '%s\n2 <source>:2 rd\n' "$HDR" > "$T/f7.want"
cat > "$T/f8.cyr" << 'EOF'
fn dfr(k): i64 {
    var r = k;
    defer { r = 0; }
    return r + 1;
}
var dc = |x| { var y = x; defer { y = 0; } return y + 2; };
var d = dfr(5) + callptr(dc, 1);
EOF
printf '%s\n1 <source>:1 dfr\n1 <source>:6 __cl#\n' "$HDR" > "$T/f8.want"
cat > "$T/a7.cyr" << 'EOF'
fn tail2(n): i64 {
    if (n == 0) { return 0; }
    return tail2(n - 1);
}
fn ta(n): i64 {
    if (n == 0) { return 7; }
    return tb(n - 1);
}
fn tb(n): i64 { return ta(n); }
var t = tail2(3) + ta(2);
EOF
printf '%s\n4 <source>:1 tail2\n3 <source>:5 ta\n2 <source>:9 tb\n' "$HDR" > "$T/a7.want"
printf 'fn f(x): i64 { return x + 1; }\nvar fp = &f;\nvar r = callptr(fp, 4);\nvar c = |x| x + 2;\nvar q = callptr(c, r);\n' > "$T/a6.cyr"
printf '%s\n1 <source>:1 f\n1 <source>:4 __cl#\n' "$HDR" > "$T/a6.want"
# fx <row> <src> <runner> <want> <exit> <compiler> [env...]: hx in $T over the whole dump, the exit stated
fx() {
    row=$1; src=$2; runr=$3; want=$4; HXE=$5; comp=$6; shift 6
    hx "$row" "$src" "$T" "$runr" "$want" "$comp" "$@"
    HXE=""
}
# fleg <leg> <runner> <compiler> [env...]: the shapes every target runs
fleg() {
    leg=$1; runr=$2; comp=$3; shift 3
    fx "F1 $leg: #inline replays (two direct, one nested in a replayed #inline) bump the callee" "$T/f1.cyr" "$runr" "$T/f1.want" 11 "$comp" "$@"
    fx "F2 $leg: closures — expression x2, block, a bar list over two lines (its closing bar's line), ||, one in a fn x2" "$T/f2.cyr" "$runr" "$T/f2.want" 38 "$comp" "$@"
    fx "F4 $leg: a method (P_sum; the uncalled method absent)" "$T/f4.cyr" "$runr" "$T/f4.want" 7 "$comp" "$@"
    fx "F3 $leg: gen<f64> (minted gen\$f64) and the base called at i64 both count; the uncalled generic is absent" "$T/f3.cyr" "$runr" "$T/f3.want" 4 "$comp" "$@"
    fx "F6 $leg: a #naked fn is a '-' record (not instrumented), never a count$F6N" "$T/f6.cyr" "$runr" "$F6W" 1 "$comp" "$@"
    fx "F7a $leg: no __cyrius_ record (the dump's own fns)" "$T/f7.cyr" "$runr" "$T/f7.want" 5 "$comp" "$@"
    fx "F7b $leg: no __cyrius_ record under CYRIUS_BOUNDS=1 (the checker's fns entered on every subscript)" "$T/f7.cyr" "$runr" "$T/f7.want" 5 "$comp" "$@" CYRIUS_BOUNDS=1
    fx "F8 $leg: a fn and a closure with defer, each counted once (the defer-init jump never re-runs the hit)" "$T/f8.cyr" "$runr" "$T/f8.want" 9 "$comp" "$@"
    fx "A7 $leg: a self tail call and a tail chain count every entry (tail2 4, ta 3, tb 2)" "$T/a7.cyr" "$runr" "$T/a7.want" 7 "$comp" "$@"
    fx "A6 $leg: a top-level indirect call (its micro-frame's prologue) adds no record" "$T/a6.cyr" "$runr" "$T/a6.want" 7 "$comp" "$@"
}

# ── F on x86 ELF, and F1 / F2 / F8 under every x86 codegen mode ─────────────────────────────────
fleg x86 x86 "$CC"
for m in CYRIUS_IR=1 CYRIUS_IR=3 CYRIUS_DCE=1 CYRIUS_PIE=1 CYRIUS_STACK_ARRAYS=0; do
    fx "F1 x86, $m" "$T/f1.cyr" x86 "$T/f1.want" 11 "$CC" "$m"
    fx "F2 x86, $m" "$T/f2.cyr" x86 "$T/f2.want" 38 "$CC" "$m"
    fx "F8 x86, $m" "$T/f8.cyr" x86 "$T/f8.want" 9 "$CC" "$m"
done
# F5 — an `async fn`'s body is `f$impl`, counted at its state-0 landing: `outer$impl` once across
# four forces of its future (it suspends twice mid-body), `job$impl` once per future (two); the
# constructors (`outer`, `job`: no source body of their own) are never a record
cat > "$T/f5.cyr" << 'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
async fn job(n): i64 { return n + 1; }
async fn outer(C): i64 {
    var x = 1;
    var s1 = await job(1);
    x = x + s1;
    var s2 = await job(2);
    x = x + s2;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = outer(0);
    var r1 = future_force(C); var r2 = future_force(C); var r3 = future_force(C); var r4 = future_force(C);
    if (r4 != 6) { return 1; }
    return 50;
}
EOF
printf '%s\n2 <source>:8 job$impl\n1 <source>:9 outer$impl\n1 <source>:17 main\n' "$HDR" > "$T/f5.want"
ax "F5 x86 (CYRIUS_ASYNC=1): outer\$impl once across four forces, job\$impl 2, no constructor record" "$T/f5.cyr" x86 "$T/f5.want" "$CC" CYRIUS_ASYNC=1
# (F5 runs on x86 and PE only: a mid-body `await` is refused by name on aarch64 — "`async fn`
# mid-body suspend is x86-only so far" — and cx)

# ── F on the other targets ────────────────────────────────────────────────────────────────────
if [ "$HAVE_QEMU" = 1 ]; then
    if [ -x "$T/cc_a64" ]; then
        fleg "aarch64 (qemu)" qemu "$T/cc_a64"
    else bad "F aarch64: src/main_aarch64.cyr did not build"; fi
    if [ -x "$T/cc_a64n" ]; then fleg "the native aarch64 fork (qemu)" qemu "qemu-aarch64 $T/cc_a64n"
    else bad "F src/main_aarch64_native.cyr did not build"; fi
fi
if [ "$HAVE_WINE" = 1 ]; then
    fleg "PE through main.cyr (wine)" pe "$CC" CYRIUS_TARGET_WIN=1
    ax "F5 PE through main.cyr (wine; CYRIUS_ASYNC=1)" "$T/f5.cyr" pe "$T/f5.want" "$CC" CYRIUS_TARGET_WIN=1 CYRIUS_ASYNC=1
    if [ -x "$T/cc_win" ]; then fleg "PE through the main_win fork (wine)" pe "$T/cc_win"
    else bad "F src/main_win.cyr did not build"; fi
fi
if [ -x "$T/cc_cx" ]; then
    F6W="$T/f6cx.want"; F6N=" — cx takes no #naked: nk is an ordinary fn, never entered, so no record"
    fleg "cx (cxvm)" cxvm "$T/cc_cx"
    F6W="$T/f6.want"; F6N=""
else bad "F cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

# ════════════════════════════════════════════════════════════════════════════════════════════════
# GROUP G — THE GUIDE (P5B-8): what § "The execution-coverage mode (6.7.10)" shows is what the
# compiler does.
# ════════════════════════════════════════════════════════════════════════════════════════════════
GUIDE=docs/guides/cyrius-guide.md
awk '/^## The execution-coverage mode \(6\.7\.10\)$/ { s = 1; next } s && /^## / { exit } s' "$GUIDE" > "$T/g.sec"
# the example is the section's first fence (unlabeled); its dump the first ```text fence; its exit
# the `echo $?  # N` of the ```sh fence
awk '/^```$/ && !inb { inb = 1; next } inb && /^```/ { exit } inb { print }' "$T/g.sec" > "$T/g_ex.cyr"
awk '/^```text$/ { t = 1; next } t && /^```/ { exit } t' "$T/g.sec" | tr -d '\r' | sed 's/__cl[0-9][0-9]*/__cl#/' > "$T/g_ex.want"
GX=$(awk '/^```sh$/ { t = 1; next } t && /^```/ { exit } t' "$T/g.sec" | sed -n 's/.*echo \$?[ ]*# \([0-9][0-9]*\).*/\1/p' | head -1)
if [ "$(grep -c . "$T/g.sec")" -lt 60 ] || ! grep -q '^#naked$' "$T/g_ex.cyr" || ! grep -q '^# cyrius-coverage 1$' "$T/g_ex.want" || [ -z "$GX" ]; then
    bad "G1 the guide's execution-coverage section, its example, its dump or its stated exit was not found (section $(grep -c . "$T/g.sec") lines)"
else
    rm -f "$T/g.cov"
    cc g1 g_ex.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/g.cov"
    if [ "$RC" != 0 ]; then bad "G1 the guide's example does not compile under the mode: $(grep -m1 '^error' "$T/g1.err")"
    else
        chmod +x "$T/g1.bin"; got=0; "$T/g1.bin" > /dev/null 2>&1 || got=$?
        { tr -d '\r' < "$T/g.cov" | sed 's/__cl[0-9][0-9]*/__cl#/'; } > "$T/g1.got" 2> /dev/null
        if [ "$got" = "$GX" ] && cmp -s "$T/g1.got" "$T/g_ex.want"; then
            ok "G1 the guide's example exits $GX under the mode and dumps exactly the block the guide shows ($(grep -c . "$T/g1.got") lines)"
        else bad "G1 the guide's example: exit $got (the guide: $GX); dump $(tr '\n' '|' < "$T/g1.got") — the guide shows $(tr '\n' '|' < "$T/g_ex.want")"; fi
    fi
    cc g1p g_ex.cyr
    got=0
    if [ "$RC" = 0 ]; then chmod +x "$T/g1p.bin"; "$T/g1p.bin" > /dev/null 2>&1 || got=$?; fi
    if [ "$RC" = 0 ] && [ "$got" = "$GX" ]; then ok "G1' ... and exits $GX without the mode, as the guide says"
    else bad "G1' the guide's example without the mode: rc $RC, exit $got (the guide: $GX)"; fi
fi
# G2 — the texts the guide quotes are the compiler's
GQ1=$(grep -o '`CYRIUS_COVERAGE must be 0 or 1 (or unset): <v>`' "$T/g.sec" | head -1 | sed 's/^`//; s/ <v>`$//')
GQ2=$(grep -o '`CYRIUS_COVERAGE=1 needs CYRIUS_COVERAGE_FILE=<path> …`' "$T/g.sec" | head -1 | sed 's/^`//; s/ …`$//')
GQ3=$(grep -o '`ignoring CYRIUS_COVERAGE_FILE: its value is longer than 255 bytes`' "$T/g.sec" | head -1 | tr -d '`')
cc g2a s.cyr CYRIUS_COVERAGE=2 CYRIUS_COVERAGE_FILE="$F"
if [ -n "$GQ1" ] && [ "$RC" = 1 ] && grep '^error' "$T/g2a.err" | grep -qF -- "$GQ1 2"; then ok "G2a the guide's '$GQ1 <v>' is the compiler's refusal"
else bad "G2a the guide quotes '${GQ1:-(not found in the guide)} <v>'; CYRIUS_COVERAGE=2 gives rc $RC: $(head -1 "$T/g2a.err")"; fi
cc g2b s.cyr CYRIUS_COVERAGE=1
if [ -n "$GQ2" ] && [ "$RC" = 1 ] && grep '^error' "$T/g2b.err" | grep -qF -- "$GQ2"; then ok "G2b the guide's '$GQ2 …' is the compiler's refusal"
else bad "G2b the guide quotes '${GQ2:-(not found in the guide)} …'; no CYRIUS_COVERAGE_FILE gives rc $RC: $(head -1 "$T/g2b.err")"; fi
cc g2c s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$L256"
if [ -n "$GQ3" ] && [ "$RC" = 1 ] && grep '^warning' "$T/g2c.err" | grep -qF -- "$GQ3"; then ok "G2c the guide's '$GQ3' is the compiler's warning"
else bad "G2c the guide quotes '${GQ3:-(not found in the guide)}'; a ${#L256} B CYRIUS_COVERAGE_FILE gives rc $RC: $(head -1 "$T/g2c.err")"; fi
# G3 — the reserved dump fns the guide names are exactly the ones the compiler appends
grep -o 'fn __cyrius_cov_[a-z_]*' src/frontend/parse_cov.cyr | sed 's/^fn //' | LC_ALL=C sort -u > "$T/g3.src"
grep -o '`__cyrius_cov_[a-z_]*`' "$T/g.sec" | tr -d '`' | grep -vx '__cyrius_cov_' | LC_ALL=C sort -u > "$T/g3.doc"
if [ "$(grep -c . "$T/g3.src")" -lt 4 ]; then bad "G3 found $(grep -c . "$T/g3.src") dump fns in parse_cov.cyr (floor 4) — the reader is blind"
elif cmp -s "$T/g3.src" "$T/g3.doc"; then ok "G3 the guide names exactly the dump's fns: $(tr '\n' ' ' < "$T/g3.src")"
else bad "G3 the compiler appends: $(tr '\n' ' ' < "$T/g3.src")— the guide names: $(tr '\n' ' ' < "$T/g3.doc")"; fi
# G4 — the reserved prefix: a program's own `__cyrius_` fn gets no line; its `__cyrius_cov_dump`
# is replaced by the compiler's (named by the duplicate-fn warning) and the block is still written
printf 'fn __cyrius_mine(): i64 { return 2; }\nfn b(): i64 { return __cyrius_mine(); }\nfn __cyrius_cov_dump(h, m): i64 { return 0; }\nvar r = b();\n' > "$T/g4.cyr"
printf '# cyrius-coverage 1\n1 <source>:2 b\n' > "$T/g4.want"
rm -f "$T/g4.cov"
cc g4 g4.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/g4.cov"
got=0
if [ "$RC" = 0 ]; then chmod +x "$T/g4.bin"; "$T/g4.bin" > /dev/null 2>&1 || got=$?; fi
if [ "$RC" = 0 ] && [ "$got" = 2 ] && grep -q "^warning.*duplicate fn '__cyrius_cov_dump'" "$T/g4.err" && cmp -s "$T/g4.cov" "$T/g4.want"; then
    ok "G4 a program's own __cyrius_ fn gets no line; its __cyrius_cov_dump is replaced, named by the duplicate-fn warning (exit 2, the block written)"
else bad "G4 rc $RC, exit $got; warning: $(grep -m1 'duplicate fn' "$T/g4.err"); dump: $(tr '\n' '|' < "$T/g4.cov" 2> /dev/null)"; fi
# G5 — the `<line>` of a fn a #derive writes is its struct's closing `}` (the guide's clause), not the
# `#derive` (1), `struct` (2) or a field (3 / 4) line
GD5=$(grep -c "a fn a \`#derive\` writes has no \`fn\` of its own and is named at its struct's closing \`}\`" "$T/g.sec")
printf '#derive(accessors)\nstruct P {\n    x;\n    y;\n}\nvar buf[2];\nP_set_x(&buf, 3);\nvar r = P_x(&buf);\nsyscall(60, r);\n' > "$T/g5.cyr"
printf '# cyrius-coverage 1\n1 <source>:5 P_x\n1 <source>:5 P_set_x\n' > "$T/g5.want"
rm -f "$T/g5.cov"
cc g5 g5.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/g5.cov"
got=0
if [ "$RC" = 0 ]; then chmod +x "$T/g5.bin"; "$T/g5.bin" > /dev/null 2>&1 || got=$?; fi
if [ "$GD5" = 1 ] && [ "$RC" = 0 ] && [ "$got" = 3 ] && cmp -s "$T/g5.cov" "$T/g5.want"; then
    ok "G5 the guide names a #derive-written fn at its struct's closing \`}\`, and the dump does (P_x / P_set_x at line 5)"
else bad "G5 the guide's derive clause found $GD5 time(s) (want 1); rc $RC, exit $got (want 3); dump: $(tr '\n' '|' < "$T/g5.cov" 2> /dev/null)"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS $G: $rows rows — CYRIUS_COVERAGE 1 / 0 / empty / other refused; CYRIUS_COVERAGE_FILE required (255 B edge); the predefine in the entry and an include; kernel / EFI / shared / object refused; no source spelling; flag-table headroom; mode off byte-identical; the per-fn counters, the map and the exit dump exact on x86 (every codegen mode), aarch64, the native fork, PE (main.cyr and main_win) and cx; every exit route (the constant-numbered exit syscalls per target, panic, the bounds checker, fork, threads; #naked / runtime-variable residuals; agnos and Darwin structural); every fn shape (#inline replays, closures, generics, methods, async bodies, #naked as not instrumented, no __cyrius_ record, defer, tail calls, the top-level micro-frame); the guide's example, quoted texts, reserved names and derive line rule held to the compiler"
exit 0
