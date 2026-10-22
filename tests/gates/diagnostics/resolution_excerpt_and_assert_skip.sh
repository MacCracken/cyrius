#!/bin/sh
# Gate: resolution errors carry a source excerpt, and `#assert` cannot eat the next
# statement (v6.5.39). And only `;` or the line's end may follow its message (6.7.17, the user's D28: axis 8).
#
# TWO defects, one function apart, both found while closing the DX multi-error residual.
#
# (A) THE EXCERPT ASYMMETRY — the actual filed residual. v6.5.23 converted the five
# `undefined variable` sites from fail-fast to report-and-continue, which is why a compile
# now lists every unresolved name instead of stopping at the first. But `_err_excerpt` lives
# inside `ERR_IDENT`, and those five sites deliberately BYPASS `ERR_IDENT` — it sets
# `_panic = 1`, which reinstates the manufactured `unexpected else` regression on lib/fs.cyr
# that got an earlier attempt reverted. So resolution errors printed a bare message while
# every syntax error got line + caret. ⚠ The fix must stay a bare `_err_excerpt(S)` call and
# must NOT be "tidied" into a reroute through `ERR_IDENT`; that is the same revert, again.
#
# (B) ⛔ A LATENT SILENT MISCOMPILE in the `#assert` skip-loop. Its comment promised
# "consume remaining tokens until ; or newline change" and the loop tested only `;` and EOF —
# there was no newline check at all. A `#assert` with no trailing `;` therefore skipped across
# the following `fn` header and ate the first statement AND its `;`. Measured pre-fix: the
# axis-3 fixture exits 0 instead of 7 — wrong code, no diagnostic, no crash. Latent only
# because nothing in the tree uses `#assert` today (all 12 grep hits are compiler
# implementation or comments), so it was waiting for the first consumer who did. Duplicated at
# three sites in three files: src/frontend/parse.cyr (pass 2, shared by all forks) and the
# pass-1 arms in src/main.cyr and src/main_win.cyr.
#
# ⚠ THE FILING THIS CLOSES WAS WRONG THREE WAYS, recorded so a sweep does not re-inflate it:
# its residual count (7, re-stamped to 8) was 1 on live code; its "_ends_guard added a site"
# is false (that site recovers); and its "R2 must land before R1" dependency is contradicted
# by the CHANGELOG of the release that shipped both.
#
# (C) 6.6.11 — the v6.5.39 newline stop took the line of the token AT THE CURSOR. With no
# `,`, message or `;`, that token is already the NEXT line's first, so the stop never fired
# and `#assert 1 == 1<LF> return 42;` ate the return: the fn returned garbage, rc 0. The line
# is now the last consumed token's, unless a string (the message) sits at the cursor.
# Axes 5-6. Mutation: `GTLINE(S, GTI(S) - 1)` back to `GTLINE(S, GTI(S))` in _assert_tail
# -> axis 5 RED (5, want 42).
# (D) 6.6.11 — a failing #assert EXITED. A top-level one runs in the declaration phase,
# before PARSE_PROG parses the top-level `var` initialisers, so `var x = ;` followed by a
# failing assert printed only the assert. It now records _had_error and continues; an
# #inline body replayed at each call site reports its failure once. Axis 7. Mutation: put
# back `syscall(SYS_EXIT, 1)` -> axis 7 RED (the `unexpected ';'` line is missing); drop the
# `_assert_rep_ti` test -> axis 7 RED (the #inline failure is reported 3 times).
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: resolution_excerpt_and_assert_skip: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: resolution_excerpt_and_assert_skip: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: resolution_excerpt_and_assert_skip: $1"; exit 1; }

# ── axis 1: a resolution error prints the excerpt AND the caret ────────────────────
cat > "$WORK/multi.cyr" <<'EOF'
fn main(): i64 {
    var a = ALPHA;
    var b = BRAVO;
    return a + b;
}
EOF
set +e
( cd "$ROOT" && cat "$WORK/multi.cyr" | "$CC" > /dev/null ) 2> "$WORK/err"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "axis 1: a program with two undefined variables compiled successfully"
grep -q "undefined variable 'ALPHA'" "$WORK/err" || fail "axis 1: the first undefined variable was not reported"
# The excerpt is the SOURCE LINE echoed back; the caret is the column marker under it.
grep -q "var a = ALPHA;" "$WORK/err" \
    || fail "axis 1: the error has no source excerpt — resolution errors still print a bare message while syntax errors get line+caret: $(cat "$WORK/err")"
grep -q '\^' "$WORK/err" || fail "axis 1: excerpt present but no caret line"

# ── axis 2: R1 regression guard — ALL resolution errors in one compile ─────────────
# If someone re-routes these sites through ERR_IDENT to "reuse" the excerpt, `_panic = 1`
# comes back with it and the compile stops reporting after the first.
grep -q "undefined variable 'BRAVO'" "$WORK/err" \
    || fail "axis 2: only the first undefined variable was reported — report-and-continue was lost (an ERR_IDENT reroute sets _panic and does exactly this)"

# ── axis 3: `#assert` with no trailing ';' must not consume the next statement ─────
cat > "$WORK/asrt.cyr" <<'EOF'
include "lib/syscalls.cyr"
#assert 1 == 1 "ok"
fn main(): i64 {
    var x = 7;
    return x;
}
var ec = main();
syscall(60, ec);
EOF
# ⚠ TWO failure symptoms, and the gate must name both. If only the pass-2 copy
# (src/frontend/parse.cyr) regresses, the two passes disagree about where the directive ends
# and the fixture fails to COMPILE. If all three copies regress together, it compiles fine
# and returns the WRONG ANSWER. Reporting only the second would misdiagnose the first.
set +e
( cd "$ROOT" && cat "$WORK/asrt.cyr" | "$CC" > "$WORK/a.out" ) 2> "$WORK/aerr"; ARC=$?
set -e
[ "$ARC" -eq 0 ] || fail "axis 3: the #assert fixture did not compile ($(head -1 "$WORK/aerr")) — most likely the pass-1 and pass-2 skip-loops now disagree about where the directive ends"
chmod +x "$WORK/a.out"
set +e
( cd "$ROOT" && "$WORK/a.out" ); AR=$?
set -e
[ "$AR" -eq 7 ] || fail "axis 3: exit $AR, expected 7 — the #assert skip-loop consumed 'var x = 7;' and its ';' (pre-fix this returns 0: wrong code, no diagnostic)"

# ── axis 4: ANTI-VACUOUS — the excerpt machinery is live for syntax errors too ─────
# If `_err_excerpt` were globally broken, axis 1 would fail for an unrelated reason and the
# diagnosis would go to the wrong place. This pins that the machinery itself works.
cat > "$WORK/syn.cyr" <<'EOF'
fn main(): i64 {
    var b = ;
    return 0;
}
EOF
set +e
( cd "$ROOT" && cat "$WORK/syn.cyr" | "$CC" > /dev/null ) 2> "$WORK/serr"
set -e
grep -q '\^' "$WORK/serr" || fail "axis 4 anti-vacuous: even a plain SYNTAX error has no caret — _err_excerpt is broken generally, not just at the resolution sites"

# ── axis 5: no `;`, no message — the NEXT line is a statement, not the assert's tail ──
# asrt_run <name> <want-exit>: compile $WORK/<name>.cyr from $ROOT and run it
asrt_run() {
    set +e
    ( cd "$ROOT" && cat "$WORK/$1.cyr" | "$CC" > "$WORK/$1.out" ) 2> "$WORK/$1.err"; _rc=$?
    set -e
    [ "$_rc" -eq 0 ] || fail "$1: did not compile ($(head -1 "$WORK/$1.err"))"
    chmod +x "$WORK/$1.out"
    set +e
    "$WORK/$1.out"; _rc=$?
    set -e
    [ "$_rc" -eq "$2" ] || fail "$1: exit $_rc, expected $2 — the #assert swallowed the following line (6.6.10 returned the garbage 5)"
}
printf 'fn f(): i64 { var x = 5; #assert 1 == 1\n return 42; }\nsyscall(60, f());\n' > "$WORK/nosemi.cyr"
asrt_run nosemi 42
printf 'fn f(): i64 { var x = 5; #assert 1 == 1,\n return 42; }\nsyscall(60, f());\n' > "$WORK/commanl.cyr"
asrt_run commanl 42
printf '#assert 1 == 1\nvar y = 9;\nsyscall(60, y);\n' > "$WORK/topnosemi.cyr"
asrt_run topnosemi 9

# ── axis 6: ANTI-VACUOUS — the message may still sit on the next line ──────────────
printf 'fn f(): i64 { var x = 5; #assert 1 == 1,\n "wrapped msg";\n return 42; }\nsyscall(60, f());\n' > "$WORK/wrapped.cyr"
asrt_run wrapped 42
printf 'fn f(): i64 { var x = 5; #assert 1 == 1, "multi\nline"\n return 42; }\nsyscall(60, f());\n' > "$WORK/mlmsg.cyr"
asrt_run mlmsg 42
# and a FAILING wrapped assert still prints its next-line message
printf 'fn f(): i64 { #assert 1 == 2,\n "wrapped fail";\n return 42; }\nsyscall(60, f());\n' > "$WORK/wrapfail.cyr"
set +e
( cd "$ROOT" && cat "$WORK/wrapfail.cyr" | "$CC" > /dev/null ) 2> "$WORK/wrapfail.err"; _rc=$?
set -e
[ "$_rc" -eq 1 ] || fail "axis 6: a failing wrapped #assert exited $_rc, expected 1"
grep -q '#assert failed: wrapped fail' "$WORK/wrapfail.err" || fail "axis 6: the wrapped message was not printed: $(cat "$WORK/wrapfail.err")"

# ── axis 7: a failing #assert does not hide an earlier error, and reports once ─────
printf 'var x = ;\n#assert 1 == 2;\n' > "$WORK/both.cyr"
set +e
( cd "$ROOT" && cat "$WORK/both.cyr" | "$CC" > "$WORK/both.out" ) 2> "$WORK/both.err"; _rc=$?
set -e
[ "$_rc" -eq 1 ] || fail "axis 7: exit $_rc, expected 1"
[ ! -s "$WORK/both.out" ] || fail "axis 7: a binary was emitted despite the errors"
grep -q "error:<source>:2:15: #assert failed" "$WORK/both.err" || fail "axis 7: the failing #assert was not reported: $(cat "$WORK/both.err")"
grep -q "error:<source>:1:9: unexpected ';'" "$WORK/both.err" \
    || fail "axis 7: the syntax error on line 1 was lost behind the failing #assert (6.6.10 exited at the assert): $(cat "$WORK/both.err")"
printf '#inline\nfn h(): i64 { #assert 1 == 2, "inl"; return 1; }\nfn g(): i64 { return h() + h(); }\n#assert 3 == 4, "top";\nsyscall(60, g());\n' > "$WORK/inl.cyr"
set +e
( cd "$ROOT" && cat "$WORK/inl.cyr" | "$CC" > "$WORK/inl.out" ) 2> "$WORK/inl.err"; _rc=$?
set -e
[ "$_rc" -eq 1 ] || fail "axis 7: #inline fixture exit $_rc, expected 1"
[ ! -s "$WORK/inl.out" ] || fail "axis 7: #inline fixture emitted a binary"
n=$(grep -c '#assert failed: inl' "$WORK/inl.err" || true)
[ "$n" -eq 1 ] || fail "axis 7: the failing assert in an #inline body was reported $n times, expected once"
grep -q '#assert failed: top' "$WORK/inl.err" || fail "axis 7: a second, independent failing #assert was not reported"

# ── axis 8: ONLY `;` OR THE LINE'S END AFTER THE MESSAGE (6.7.17, the user's D28, 2026-10-22) ─────────────────────────
# issues/2026-10-21-directive-line-tails-unread-use-without-path-late-private.md (rows 1 and 2). `_assert_tail`
# (src/frontend/parse.cyr) skipped whatever followed the message to the next `;` or the line's end, unread:
# `#assert 1 == 1, "m" junk` compiled, and in an impl body the tail ate the next method up to its `;` — pass 2 then
# ended the impl at the method's `}`, and the program after it was never compiled (exit 0, not 9). Now one error at the
# first token after the message ("#assert: expected `;` or the end of the line after the message"; after a `,` with no
# message "#assert: expected the message string, `;` or the end of the line after `,`"), the rest of the line stepped
# whole (a `{` through its `}`), so the next line reports its own; both passes stop on the same token. Four legs:
# x86_64, aarch64 (the tree's cross compiler, run under qemu-aarch64), cx (main_cx, run under the tree's cxvm) and PE
# (CYRIUS_TARGET_WIN=1, run under wine in a private prefix) — a refusal by its exact error lines and no binary, a run by
# its exit code.
#   AT1      row 1 verbatim: the impl method — one error, nothing after it dropped silently
#   AT2-AT3  row 2's module and fn forms
#   AT4      `#assert 1 == 1, junk` (a `,` with no message)
#   AT5      the next line reports its own (`zz`)
#   AT6      a `{` on the line stepped through its `}` on a later line; the body's `zz` after it reported
#   AT7      a failing assertion with a tail: both errors
#   AT8      after the first top-level statement, the next line's `zz` too
#   AT9      a message spanning two lines: `junk` on its LAST line is on the message's line
#   AT10     the zone: a struct's error after the refused line (the latch released)
#   AT11     a generic fn at two instances: once
#   AC1-AC6  controls: no message (the next line runs: 9); `;` then a statement on the line (9); the message then a
#            line break (9); `{ #assert 1 == 1, "m"; }` in a block (7); an impl's `#assert .., "m";` then a method (5);
#            a `#` comment after the message (9)
# MUTATION LEDGER (2026-10-22, lane fea FA1; a scratch copy of the tree with the one change, its 2-stage cycc run as
# CYCC=, so every leg's compiler carries the mutant):
#   `_assert_tail` without its refusal (the tail stepped, unreported) -> RED AT1-AT11, 44 row-legs (rc 0, or a line lost)
#   `_assert_end` without the refused tail's in-sync mark          -> RED AT5 AT8, 8 (the next line's `zz` swallowed)
#   the message's line taken from its first line (`GTLINE`)        -> RED AT9, 4 (`junk` parsed as the next statement)
#   `_ln_rest` not counting `{` / `}`                              -> RED AT6, 4 (the body's `}` met at depth 0)
WP="$WORK/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$WORK"' EXIT
AFAIL=0
ATN=0
abad() { echo "  FAIL: $1"; AFAIL=$((AFAIL + 1)); }
AT_LEGS="x86 pe"
if "$CC" < "$ROOT/src/main_aarch64.cyr" > "$WORK/cc_a64" 2> /dev/null && [ -s "$WORK/cc_a64" ]; then chmod +x "$WORK/cc_a64"; AT_LEGS="$AT_LEGS a64"
else abad "axis 8: src/main_aarch64.cyr did not build"; fi
if "$CC" < "$ROOT/src/main_cx.cyr" > "$WORK/cc_cx" 2> /dev/null && [ -s "$WORK/cc_cx" ] \
   && "$CC" < "$ROOT/programs/cxvm.cyr" > "$WORK/cxvm" 2> /dev/null && [ -s "$WORK/cxvm" ]; then chmod +x "$WORK/cc_cx" "$WORK/cxvm"; AT_LEGS="$AT_LEGS cx"
else abad "axis 8: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
AT_QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && AT_QEMU=1
AT_WINE=0; command -v wine > /dev/null 2>&1 && AT_WINE=1
[ "$AT_QEMU" = 1 ] || echo "  SKIP: axis 8's aarch64 RUNS (qemu-aarch64 not installed; the compiles still run)"
[ "$AT_WINE" = 1 ] || echo "  SKIP: axis 8's PE RUNS (wine not installed; the compiles still run)"
at_comp() {   # <leg> <src> <out>: PRC = the compiler's rc (compiled from $ROOT, where `include` resolves)
    PRC=0
    case "$1" in
        x86) ( cd "$ROOT" && timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" ) || PRC=$? ;;
        pe)  ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" ) || PRC=$? ;;
        a64) ( cd "$ROOT" && timeout 60 "$WORK/cc_a64" < "$2" > "$3" 2> "$3.err" ) || PRC=$? ;;
        cx)  ( cd "$ROOT" && timeout 60 "$WORK/cc_cx" < "$2" > "$3" 2> "$3.err" ) || PRC=$? ;;
    esac
}
at_exec() {   # <leg> <binary>: XRC = its exit code; 1 = no runner on this box (skipped by name above)
    XRC=0
    case "$1" in
        x86) chmod +x "$2"; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64) [ "$AT_QEMU" = 1 ] || return 1; chmod +x "$2"; timeout 300 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$? ;;
        cx)  timeout 300 "$WORK/cxvm" < "$2" > /dev/null 2>&1 || XRC=$? ;;
        pe)  [ "$AT_WINE" = 1 ] || return 1
             cp "$2" "$2.exe"
             (cd "$WORK" && WINEPREFIX="$WP" HOME="$WORK/whome" XDG_CACHE_HOME="$WORK/whome/.cache" WINEDEBUG=-all \
                 WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$2.exe" > /dev/null 2>&1) || XRC=$? ;;
    esac
    return 0
}
# atrefuse <id> <what> <source> <want>: refused on every leg (rc != 0, no binary), its error / warning lines exactly <want>
atrefuse() {
    printf '%s\n' "$3" > "$WORK/$1.cyr"
    printf '%s\n' "$4" > "$WORK/$1.want"
    for leg in $AT_LEGS; do
        o="$WORK/$1_$leg"
        at_comp "$leg" "$WORK/$1.cyr" "$o"
        ATN=$((ATN + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$PRC" -eq 0 ]; then abad "$1 $leg: $2: rc 0 - want the refusal"
        elif ! cmp -s "$o.got" "$WORK/$1.want"; then abad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then abad "$1 $leg: $2: refused, but a binary was written"
        else echo "  ok $1 $leg: $2"; fi
    done
}
# atrun <id> <what> <source> <exit>: compiles clean on every leg (no error / warning line), and runs to <exit>
atrun() {
    printf '%s\n' "$3" > "$WORK/$1.cyr"
    for leg in $AT_LEGS; do
        o="$WORK/$1_$leg"
        at_comp "$leg" "$WORK/$1.cyr" "$o"
        ATN=$((ATN + 1))
        if [ "$PRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            abad "$1 $leg: $2: rc $PRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
        elif ! at_exec "$leg" "$o"; then echo "  ok $1 $leg: $2 (compiled; its run skipped above)"
        elif [ "$XRC" = "$4" ]; then echo "  ok $1 $leg: $2 (exit $4)"
        else abad "$1 $leg: $2: exit $XRC, want $4"; fi
    done
}
AM='#assert: expected `;` or the end of the line after the message'
AK='#assert: expected the message string, `;` or the end of the line after `,`'
AZ="undefined variable 'zz' (missing include or enum?)"
atrefuse AT1 "row 1 verbatim: the impl method" 'struct S { a; }
impl S { #assert 1 == 1, "m" fn m(self): i64 { return 5; } }
syscall(60, 9);' "error:<source>:2:30: $AM"
atrefuse AT2 "row 2, module scope" '#assert 1 == 1, "m" junk
syscall(60, 9);' "error:<source>:1:21: $AM"
atrefuse AT3 "row 2, in a fn" 'fn main(): i64 { #assert 1 == 1, "m" junk
return 9; }
syscall(60, main());' "error:<source>:1:38: $AM"
atrefuse AT4 "a ',' with no message, then junk" '#assert 1 == 1, junk
syscall(60, 9);' "error:<source>:1:17: $AK"
atrefuse AT5 "the next line reports its own" '#assert 1 == 1, "m" junk
syscall(60, zz);' "error:<source>:1:21: $AM
error:<source>:2:15: $AZ"
atrefuse AT6 "a { on the line stepped through its } on a later line" 'fn f(): i64 { #assert 1 == 1, "m" if (1 == 1) {
return 4; }
return zz; }
syscall(60, f());' "error:<source>:1:35: $AM
error:<source>:3:10: $AZ"
atrefuse AT7 "a failing assertion with a tail: both" '#assert 1 == 2, "m" junk
syscall(60, 9);' "error:<source>:1:17: #assert failed: m
error:<source>:1:21: $AM"
atrefuse AT8 "after the first top-level statement" 'var a = 1;
a = 2;
#assert 1 == 1, "m" junk
a = a + zz;
syscall(60, a);' "error:<source>:3:21: $AM
error:<source>:4:11: $AZ"
atrefuse AT9 "a message spanning two lines, junk on its last" '#assert 1 == 1, "multi
line" junk
syscall(60, 9);' "error:<source>:2:7: $AM"
atrefuse AT10 "the zone: a struct's error after the refused line" '#assert 1 == 1, "m" junk
struct Q { a: Foo; }
syscall(60, 3);' "error:<source>:2:15: unknown type 'Foo' for struct field 'a'
error:<source>:1:21: $AM"
atrefuse AT11 "a generic fn at two instances: once" 'fn g<T>(x: T): i64 { #assert 1 == 1, "m" junk
return 1; }
syscall(60, g<i64>(1) + g<i32>(2));' "error:<source>:1:42: $AM"
atrun AC1 "control: no message, the next line runs" '#assert 1 == 1
syscall(60, 9);' 9
atrun AC2 "control: a ';' then a statement on the line" '#assert 1 == 1, "m"; var y = 9;
syscall(60, y);' 9
atrun AC3 "control: the message then a line break" '#assert 1 == 1, "m"
syscall(60, 9);' 9
atrun AC4 "control: { #assert 1 == 1, \"m\"; } in a block" 'fn f(): i64 { if (1 == 1) { #assert 1 == 1, "m"; } return 7; }
syscall(60, f());' 7
atrun AC5 "control: an impl's #assert ended by ';', a method after it" 'struct S { a; }
impl S { #assert 1 == 1, "m"; fn m(self): i64 { return 5; } }
var s = S { 1 };
syscall(60, s.m());' 5
atrun AC6 "control: a # comment after the message" '#assert 1 == 1, "m"  # note
syscall(60, 9);' 9
# The corpus floor: 17 rows on four legs. A row or a leg lost reads RED, never green.
[ "$ATN" -ge 68 ] || abad "axis 8 floor: $ATN row-legs ran (floor 68) - rows or legs were lost"
[ "$AFAIL" -eq 0 ] || fail "axis 8: $AFAIL check(s) failed (the #assert tail, D28)"

echo "PASS: resolution_excerpt_and_assert_skip (resolution errors carry excerpt+caret, all are reported, and #assert no longer eats the following statement; only \`;\` or the line's end follows its message, $ATN row-legs on $AT_LEGS)"
