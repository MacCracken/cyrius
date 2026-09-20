#!/bin/sh
# Remote batched lib-test runner (cyrius v6.5.8). Shipped by cross-os-selfhost.sh and run
# in ONE ssh session instead of one per test — the per-test loop it replaces spent ~1.8 s
# (cass) / 0.9 s (pi) of pure SSH handshake per file, which is what made a wider corpus
# look unaffordable when it is actually the connections, not the tests, that cost.
#
# $1 = compile command  $2 = 1 to codesign (macOS)  $3 = subdir under tests/tcyr ("" = whole corpus)
#
# v6.5.11: selection is a SUBDIRECTORY and the walk is RECURSIVE. It was a flat prefix
# glob (`tests/tcyr/${PREFIX}*.tcyr`) whose no-match case was swallowed by the `[ -e ]`
# guard below, so the loop ran ZERO tests and reported "__LIBTEST_SUMMARY__ 0 0" — which
# the caller graded GREEN. The caller now also cross-checks this count against the number
# it selected locally, so the two sides can no longer disagree silently.
#
# 6.6.6: A TEST PASSES WHEN ITS ASSERTIONS RAN, NOT WHEN THE PROCESS EXITED 0. Same family as
# the v6.5.11 note above — a leg that cannot tell "nothing happened" from "everything passed".
# A binary that executes no user code exits 0, and the 6.6.5 compiler produced exactly that for
# tests/tcyr/crossos/macro_expansion_with_include.tcyr. So stdout is captured and a test whose
# SOURCE calls assert_summary must produce its "N passed" line. See the block at the check
# itself, and tests/gates/toolchain/crossos_runner_rejects_a_silent_binary.sh.
# v6.6.6: $4 is the staging directory. It used to be a hardcoded `cd ~/_cyaud`, which is
# the same fixed-name collision the caller just removed — two runs on one host shared it.
# The caller already cd's into its per-run dir before invoking this, so "." is the default.
# CHANGELOG [6.6.6]
CC_CMD="$1"; DO_SIGN="$2"; SUBDIR="$3"; RUNDIR="${4:-.}"
cd "$RUNDIR" || exit 2

# ⛔ EVERY TEST RUN IS TIME-BOUNDED (v6.5.19). A test that HANGS on the target used to
# wedge this loop forever: the caller's ssh has no command timeout (ConnectTimeout covers
# setup only), so the whole cross-OS leg produced no summary and no verdict until a human
# killed it. cass already had `timeout 90` around its per-test ssh for exactly this reason
# — the POSIX hosts never got the equivalent, and they are the ones running the batched
# loop where a single hang costs the entire corpus rather than one test.
#
# It matters more now than it did: tests/tcyr/crossos/ carries threading and allocator-lock
# tests as of v6.5.19, and the failure mode of a spinlock is a hang, not a fault. A hang has
# to COUNT AS A FAILURE and let the sweep continue; anything else and the gate reports
# nothing at all about the other 44 files.
#
# ⚠ NEITHER MAC HAS `timeout`. Checked on real ecb and ach: no `timeout`, no `gtimeout`
# (they are GNU coreutils, not part of the macOS base system), and pi has it. So this is
# hand-rolled rather than delegated — poll `kill -0` on a backgrounded child. `sleep 0.1`
# is honoured by BSD and GNU sleep alike; it costs at most one extra tenth of a second per
# test because the loop tests liveness BEFORE it sleeps.
#
# stdin is /dev/null explicitly: a background child's stdin is shell-dependent (some
# shells attach /dev/null when job control is off, some inherit), and the ssh channel is
# not a sane input for a test either way.
LT_TIMEOUT="${CYRIUS_LIBTEST_TIMEOUT:-90}"
# stdout is CAPTURED, not discarded (6.6.6) — see the summary check below, which needs the
# binary's own "N passed, M failed" line to tell a real run from a binary that ran nothing.
run_bounded() {
    "$1" </dev/null >_ltout 2>&1 &
    _bp=$!
    _bn=0
    _blim=$((LT_TIMEOUT * 10))
    while [ "$_bn" -lt "$_blim" ]; do
        kill -0 "$_bp" 2>/dev/null || break
        sleep 0.1
        _bn=$((_bn + 1))
    done
    if kill -0 "$_bp" 2>/dev/null; then
        kill -9 "$_bp" 2>/dev/null
        wait "$_bp" 2>/dev/null
        return 124
    fi
    wait "$_bp"
    return $?
}
ROOT="tests/tcyr"
[ -n "$SUBDIR" ] && ROOT="tests/tcyr/$SUBDIR"
if [ ! -d "$ROOT" ]; then echo "__LIBTEST_NODIR__ $ROOT"; exit 3; fi
p=0; f=0; hung=0; bad=""
for t in $(find "$ROOT" -name '*.tcyr' | sort); do
    [ -e "$t" ] || continue
    b=${t#tests/tcyr/}
    ok=1
    sh -c "cat '$t' | $CC_CMD > _lt 2>/dev/null" || ok=0
    [ -s _lt ] || ok=0
    if [ "$ok" = "1" ]; then
        chmod +x _lt
        [ "$DO_SIGN" = "1" ] && codesign -s - -f _lt >/dev/null 2>&1
        rc=0
        run_bounded ./_lt || rc=$?
        if [ "$rc" -eq 124 ]; then
            ok=0; hung=$((hung + 1)); b="${b}(HANG@${LT_TIMEOUT}s)"
        elif [ "$rc" -ne 0 ]; then
            ok=0
        fi
        # ⛔ 6.6.6 — EXIT 0 FROM A BINARY THAT RAN NOTHING IS NOT A PASS.
        #
        # This loop graded by exit code alone, and a process that executes no user code at
        # all exits 0. That is not hypothetical: measured on the 6.6.5 compiler,
        # tests/tcyr/crossos/macro_expansion_with_include.tcyr compiled rc 0 to a 43,512-byte
        # binary that printed NOTHING and exited 0 — a PASS scored over the exact preprocessor
        # defect the file is named for. The macro pass had replaced the filtered source with
        # its own unfiltered input and truncated it at the 1 MB helper window, so the whole
        # top-level program (assertions, summary and exit syscall alike) was simply gone. No
        # in-file trick can catch that: the file's own `var rc = 92;` seed is part of the text
        # that vanished. The judgement has to come from OUTSIDE the binary.
        #
        # Every .tcyr ends in `assert_summary()`, which prints "N passed, M failed (T total)"
        # to stdout. So the requirement is DERIVED from the test file rather than kept in an
        # allowlist here: a file that calls assert_summary must produce that line with at least
        # one assertion. Measured over the whole corpus at 6.6.6: 332 of 333 files call it and
        # all 332 print a line with N >= 1, so the check is not selective in practice — the one
        # exception (tests/tcyr/frontend/struct_sid_20_21_field.tcyr) opts itself out by not
        # calling it, and is not in the crossos set.
        #
        # ⚠ N >= 1, not "N equals the assertion count": a test may legitimately assert inside a
        # loop or behind a platform guard. The claim being enforced is "user code ran and
        # reported", which is precisely what a dropped program cannot fake.
        if [ "$ok" = "1" ] && grep -q 'assert_summary(' "$t" 2>/dev/null; then
            _np=$(sed -n 's/^\([0-9][0-9]*\) passed,.*/\1/p' _ltout 2>/dev/null | tail -1)
            if [ -z "$_np" ]; then
                ok=0
                b="${b}(exit 0 but the binary printed NO assert summary — it ran nothing;"
                b="${b} see the 6.6.6 note in cross-os-libtest-runner.sh)"
            elif [ "$_np" -lt 1 ]; then
                ok=0; b="${b}(assert summary reports $_np assertions)"
            fi
        fi
        # ⛔ 6.6.5 — ARGV-LENGTH SWEEP, for a test that asks for it with `@rerun-argv-parity`.
        #
        # THIS LOOP NAMES EVERY BINARY `./_lt`, i.e. it samples exactly ONE argv0 length. That
        # is normally irrelevant — and on Darwin x86_64 it is not, because XNU's process entry
        # rsp parity varies with the byte count of the argv/env string area. Measured on ach at
        # 6.6.5: `tests/tcyr/crossos/call_site_stack_alignment.tcyr` FAILED under `./_l` and
        # `./_lt` and PASSED under `./_ltxx` on the same broken compiler. The defect was caught
        # here only because `_lt` happens to be a losing length on that host; one byte longer
        # and this leg would have gone GREEN on a compiler that was wrong half the time. A leg
        # that samples one configuration and reports a verdict about all of them is the same
        # shape as the macOS rot this whole script exists to prevent.
        #
        # ⛔ A SECOND NAME IS NOT ENOUGH, AND THE FIRST CUT OF THIS BLOCK USED ONE. It appended
        # a fixed 20-byte suffix, and MEASURED against the pre-fix compiler on ach that name
        # landed on the SAME parity as `_lt` at every one of ten env paddings — a mechanism
        # that would have shipped reading green while sampling one parity twice. The relation
        # between two lengths is host- and kernel-dependent; there is no name that is portably
        # "the other parity". So this sweeps 15 CONSECUTIVE lengths, which cannot all share a
        # parity while the entry rsp is a function of the byte count. Measured on ach with the
        # pre-fix compiler, suffix 0..8 already reports BOTH outcomes at each of three env
        # paddings (rc 6,6,0,6,6,6,0,0,0 with PADVAR unset) — 15 is the belt-and-braces bound.
        #
        # MUTATION LEDGER — measured END TO END THROUGH THIS SCRIPT on ach (real Intel Mac),
        # 2026-09-17, against a compiler built from the same tree with `EALIGN_RSP_16` removed
        # from both landings. Running this runner over one marked file at 16 env paddings:
        #
        #   marker REMOVED (i.e. the single-name behaviour this block replaces):
        #     pad  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
        #     ---  R  R  R  R  R  R  G  G  G  G  G  G  G  G  R  R
        #     -> 8 of 16 environments report `__LIBTEST_SUMMARY__ 1 0` — GREEN — on a compiler
        #        that is misaligned at every call site half the time. A coin flip decided
        #        whether this leg found the 6.6.5 Mach-O defect or shipped it.
        #   marker PRESENT, same broken compiler, at one of those GREEN paddings (pad 6):
        #     __LIBTEST_FAILED__ ...(PASSED as ./_lt, rc=6 as ./_ltzzz — the process entry
        #     alignment depends on argv/env SIZE; see the ENTRY row in that test)
        #   marker PRESENT, FIXED compiler, same padding:  __LIBTEST_SUMMARY__ 1 0
        #
        # So the environments where this block is load-bearing are not hypothetical: they are
        # half of them, and the sweep fires in them and names the cause.
        #
        # ⚠ NOT every test, deliberately: the corpus does real file and socket I/O and a
        # blanket re-run would fail tests that are simply not idempotent. The test DECLARES the
        # requirement in its own header instead, so it travels with the file rather than living
        # in an allowlist here that rots the moment a test is renamed. CHANGELOG [6.6.5]
        if [ "$ok" = "1" ] && grep -q '@rerun-argv-parity' "$t" 2>/dev/null; then
            cp _lt _ltbase
            _k=1
            while [ "$_k" -le 15 ]; do
                _sfx=""; _i=0
                while [ "$_i" -lt "$_k" ]; do _sfx="${_sfx}z"; _i=$((_i + 1)); done
                _nm="_lt$_sfx"
                cp _ltbase "$_nm"
                chmod +x "$_nm"
                [ "$DO_SIGN" = "1" ] && codesign -s - -f "$_nm" >/dev/null 2>&1
                rc2=0
                run_bounded "./$_nm" || rc2=$?
                rm -f "$_nm"
                if [ "$rc2" -eq 124 ]; then
                    ok=0; hung=$((hung + 1)); b="${b}(HANG@${LT_TIMEOUT}s,argv-len+$_k)"
                    break
                elif [ "$rc2" -ne 0 ]; then
                    ok=0
                    b="${b}(PASSED as ./_lt, rc=$rc2 as ./$_nm — the process entry alignment"
                    b="${b} depends on argv/env SIZE; see the ENTRY row in that test)"
                    break
                fi
                _k=$((_k + 1))
            done
            rm -f _ltbase
        fi
    fi
    if [ "$ok" = "1" ]; then p=$((p + 1)); else f=$((f + 1)); bad="$bad $b"; fi
done
[ "$hung" != "0" ] && echo "__LIBTEST_HUNG__ $hung test(s) killed at ${LT_TIMEOUT}s"
echo "__LIBTEST_SUMMARY__ $p $f"
[ -n "$bad" ] && echo "__LIBTEST_FAILED__$bad"
exit 0
