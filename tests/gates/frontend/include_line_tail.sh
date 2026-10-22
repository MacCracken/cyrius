#!/bin/sh
# Gate: an `include` line ends at its file name — source after the name on the line is refused by name (6.7.17, the
# user's D29, 2026-10-22; issues/2026-10-21-directive-line-tails-unread-use-without-path-late-private.md, row 3).
#
# THE DEFECT (measured at 6.7.16, x86_64 and PE, no diagnostic): the preprocessor replaces the WHOLE include line with
# the file's text, so whatever followed the closing quote was dropped unread —
#
#     include "lib/syscalls.cyr"; var x = 42; syscall(60, x);
#
# compiled rc 0 and exited 0 (the two statements were never compiled; on the next line they exit 42), and a second
# include on the line (`include "a.cyr"; include "b.cyr";`) was never read. The guide says "file contents replace the
# include line", so an include is a whole-line directive; the user's D29 refuses the tail by name.
#
# THE FIX: PP_INCLUDE_TAIL (src/frontend/lex_pp.cyr), called by BOTH include sites — PP_PASS (the entry's own lines) and
# PP_IFDEF_PASS (an included file's, expanded later) — right after the file name is read: only blanks, one `;`, a `#`
# comment and the line's end may follow; anything else is "expected the end of the line after an include's file name"
# at its first byte (`_pp_err_at`: <file>:<line>:<col>, the build fails, the line is still included, later errors
# still reported). Four legs: x86_64, aarch64 (the tree's cross compiler; runs under qemu-aarch64), cx (main_cx; runs
# under the tree's cxvm) and PE (CYRIUS_TARGET_WIN=1; runs under wine in a private prefix) — a refusal by its exact
# error lines and no binary, a run by its exit code.
#   IT1  row 3 verbatim
#   IT2  two includes on one line: the second is the refused tail
#   IT3  a tail on an include line INSIDE an included file (PP_IFDEF_PASS's copy), named at that file's line
#   IT4  a tail on an include-once SKIPPED line (the file already included) is refused too
#   IT5  a second `;` is a tail
#   IT6  the refused line's file is still included: a later line's own error (`zz`) is reported, nothing invented
#   IC1-IC6 controls: `include "x"`, `include "x";`, `include "x"  # note`, `include "x" ;  # note`, CRLF line ends,
#        and an included file whose own include lines end clean — each compiles and runs
# A `#ref` LINE ENDS AT ITS FILE NAME TOO (6.7.17, the user's D92, 2026-10-22). PP_REF_PASS stepped the rest of the line
# unread: `#ref "f.toml"; var y = 2; syscall(60, ka + y);` exited 5, not 7. The same rule (PP_FNAME_TAIL_AT, shared with
# PP_INCLUDE_TAIL) and the same words: "expected the end of the line after a #ref's file name" at its first byte, the
# line numbered as PP_PASS numbers it (`_bnd_err`: below cbt's `#@incdir` / `#@srcline` lines, the user's own line);
# the file is still read. The rows run in a scratch dir holding f.toml (`ka = 5`), as the filed repro does.
#   RT1  the repro verbatim; RT2 a second `;`; RT3 the file is still read — a later line's own error, nothing invented;
#   RT4  under a `#@incdir` line the user's own line number; RT5 under a `#@srcline` marker likewise
#   RC1-RC5 controls: `#ref "x"`, `#ref "x";`, `#ref "x"  # note`, `#ref "x" ;  # note`, CRLF — each runs (exit 7)
# MUTATION LEDGER (2026-10-22, lane fea FA1; a scratch copy of the tree with the one change, its 2-stage cycc run as
# CYCC=, so every leg's compiler carries the mutant):
#   PP_INCLUDE_TAIL answering 0 at once (6.7.16)        -> RED IT1-IT6, 24 row-legs (rc 0, or the line lost)
#   PP_PASS's call removed (PP_IFDEF_PASS's kept)       -> RED IT1 IT2 IT4 IT5 IT6, 20 (IT3 green: the nested copy)
#   PP_IFDEF_PASS's call removed (PP_PASS's kept)       -> RED IT3, 4 (the included file's tail dropped)
#   the `#` comment not accepted                         -> RED IC3 IC4 IC6 on x86 / PE / aarch64, 9 (a commented
#                                                           include line refused), and the cx leg lost (main_cx /
#                                                           cxvm include such lines: they no longer build)
# (the finish pass, 2026-10-22, D92 — the same way):
#   PP_REF_PASS's PP_REF_TAIL call removed (6.7.16)     -> RED RT1-RT5, 20 (rc 0, the tail dropped)
#   PP_REF_TAIL reporting with `_pp_err_at` (no bias)    -> RED RT4 RT5, 8 (the raw line: 2, 3 for the user's 1)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: include_line_tail: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
case "$CC" in /*) ;; *) CC="$ROOT/$CC" ;; esac   # the #ref rows compile from a scratch dir
G=include_line_tail
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $D for the PE runs (never ~/.wine), torn down with its server dir on exit.
WP="$D/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
N=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

LEGS="x86 pe"
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; LEGS="$LEGS a64"
else bad "src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then chmod +x "$D/cc_cx" "$D/cxvm"; LEGS="$LEGS cx"
else bad "src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && QEMU=1
WINE=0; command -v wine > /dev/null 2>&1 && WINE=1
[ "$QEMU" = 1 ] || echo "  SKIP: the aarch64 RUNS (qemu-aarch64 not installed; the compiles still run)"
[ "$WINE" = 1 ] || echo "  SKIP: the PE RUNS (wine not installed; the compiles still run)"
# The nested fixtures live in the scratch dir, so their includes are absolute.
CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1; export CYRIUS_ALLOW_ABSOLUTE_INCLUDES

comp() {   # <leg> <src> <out>: PRC = the compiler's rc (from $ROOT, where `include "lib/.."` resolves; from $RDIR when set)
    PRC=0
    cd "${RDIR:-$ROOT}" || { PRC=99; return 0; }
    case "$1" in
        x86) timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
        pe)  CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
        a64) timeout 60 "$D/cc_a64" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
        cx)  timeout 60 "$D/cc_cx" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
    esac
}
xrun() {   # <leg> <binary>: XRC = its exit code; 1 = no runner on this box (skipped by name above)
    XRC=0
    case "$1" in
        x86) chmod +x "$2"; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64) [ "$QEMU" = 1 ] || return 1; chmod +x "$2"; timeout 300 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$? ;;
        cx)  timeout 300 "$D/cxvm" < "$2" > /dev/null 2>&1 || XRC=$? ;;
        pe)  [ "$WINE" = 1 ] || return 1
             cp "$2" "$2.exe"
             (cd "$D" && WINEPREFIX="$WP" HOME="$D/whome" XDG_CACHE_HOME="$D/whome/.cache" WINEDEBUG=-all \
                 WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$2.exe" > /dev/null 2>&1) || XRC=$? ;;
    esac
    return 0
}
# refuse <id> <what> <source> <want>: refused on every leg (rc != 0, no binary), its error / warning lines exactly <want>
refuse() {
    printf '%s\n' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp "$leg" "$D/$1.cyr" "$o"
        N=$((N + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$PRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0 - want the refusal"
        elif ! cmp -s "$o.got" "$D/$1.want"; then bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 $leg: $2: refused, but a binary was written"
        else echo "  ok $1 $leg: $2"; fi
    done
}
# runs <id> <what> <source> <exit>: compiles clean on every leg (no error / warning line), and runs to <exit>
runs() {
    printf '%s\n' "$3" > "$D/$1.cyr"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp "$leg" "$D/$1.cyr" "$o"
        N=$((N + 1))
        if [ "$PRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            bad "$1 $leg: $2: rc $PRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
        elif ! xrun "$leg" "$o"; then echo "  ok $1 $leg: $2 (compiled; its run skipped above)"
        elif [ "$XRC" = "$4" ]; then echo "  ok $1 $leg: $2 (exit $4)"
        else bad "$1 $leg: $2: exit $XRC, want $4"; fi
    done
}
IM="expected the end of the line after an include's file name"
ZZ="undefined variable 'zz' (missing include or enum?)"
printf 'include "lib/syscalls.cyr" junk\nfn ia(): i64 { return 7; }\n' > "$D/inner_tail.cyr"
printf 'include "lib/syscalls.cyr";  # the clean forms\ninclude "lib/syscalls.cyr"\nfn ib(): i64 { return 6; }\n' > "$D/inner_clean.cyr"

refuse IT1 "row 3 verbatim" 'include "lib/syscalls.cyr"; var x = 42; syscall(60, x);' "error:<source>:1:29: $IM"
refuse IT2 "two includes on one line" 'include "lib/syscalls.cyr"; include "lib/string.cyr";
syscall(60, 3);' "error:<source>:1:29: $IM"
refuse IT3 "a tail inside an included file (PP_IFDEF_PASS)" "include \"$D/inner_tail.cyr\"
syscall(60, ia());" "error:$D/inner_tail.cyr:1:28: $IM"
refuse IT4 "a tail on an include-once skipped line" 'include "lib/syscalls.cyr"
include "lib/syscalls.cyr" junk
syscall(60, 3);' "error:<source>:2:28: $IM"
refuse IT5 "a second ';' is a tail" 'include "lib/syscalls.cyr";;
syscall(60, 3);' "error:<source>:1:28: $IM"
refuse IT6 "the file is still included: a later line's own error, nothing invented" 'include "lib/syscalls.cyr" junk
syscall(60, zz);' "error:<source>:1:28: $IM
error:<source>:2:15: $ZZ"
runs IC1 'control: include "x"' 'include "lib/syscalls.cyr"
syscall(60, 3);' 3
runs IC2 'control: include "x";' 'include "lib/syscalls.cyr";
syscall(60, 3);' 3
runs IC3 'control: include "x"  # note' 'include "lib/syscalls.cyr"  # note
syscall(60, 3);' 3
runs IC4 'control: include "x" ;  # note' 'include "lib/syscalls.cyr" ;  # note
syscall(60, 3);' 3
runs IC5 'control: CRLF line ends' "$(printf 'include "lib/syscalls.cyr"\r\nsyscall(60, 3);\r')" 3
runs IC6 "control: an included file's clean include lines" "include \"$D/inner_clean.cyr\"
syscall(60, ib());" 6
# IU — 6.7.17, met while writing the rows above: A FILE NAME WITH NO CLOSING QUOTE ON ITS LINE IS SAID SO. The include
# (both copies) and #ref name loops read to the next `"` wherever it sits, so the lines after an unclosed name were read
# as part of it: "cannot open include file: lib/syscalls.cyr<LF>var x = " (the next lines printed as the file's name),
# 767 bytes on "include/#ref filename exceeds 767 bytes", and with a quote on the next line also the tail error at a
# column of THAT line. Now one line naming the cause (PP_FNAME_UNCLOSED; the same exit 1, nothing else changes).
#   IU1 the entry; IU2 an included file (PP_IFDEF_PASS); IU3 no quote for 767+ bytes; IU4 `#ref`
#   `PP_FNAME_UNCLOSED` answering 0 at once (6.7.16's messages)  -> RED IU1-IU4, 16
#   PP_INCLUDE_TAIL without its unclosed-name stand-down         -> RED IU1 IU2, 8 (the tail error at the next line too)
UM_='the file name has no closing quote on its line'
printf 'include "lib/syscalls.cyr\nfn ic(): i64 { return 7; }\nvar s = "q";\n' > "$D/inner_unclosed.cyr"
refuse IU1 "an unclosed name in the entry" 'include "lib/syscalls.cyr
var x = "a";
syscall(60, 3);' "error: include \"lib/syscalls.cyr: $UM_"
refuse IU2 "an unclosed name in an included file" "include \"$D/inner_unclosed.cyr\"
syscall(60, ic());" "error: include \"lib/syscalls.cyr: $UM_"
refuse IU3 "an unclosed name with no quote for 767+ bytes" "$(printf 'include "lib/syscalls.cyr\n'; i=0; while [ $i -lt 100 ]; do printf 'var x%d = 1;\n' $i; i=$((i + 1)); done; printf 'syscall(60, 3);')" "error: include \"lib/syscalls.cyr: $UM_"
refuse IU4 "an unclosed #ref name" '#ref "nope.toml
var a = "x";
syscall(60, 3);' "error: #ref \"nope.toml: $UM_"
# RT / RC — the #ref line (D92; see the header). Compiled from $D/ref, where f.toml sits, as the filed repro is.
RM_="expected the end of the line after a #ref's file name"
mkdir -p "$D/ref" && printf 'ka = 5\n' > "$D/ref/f.toml" || bad "cannot write $D/ref/f.toml"
RDIR="$D/ref"
refuse RT1 "the D92 repro verbatim" '#ref "f.toml"; var y = 2; syscall(60, ka + y);' "error:<source>:1:16: $RM_"
refuse RT2 "a second ';' is a tail" '#ref "f.toml";;
syscall(60, ka);' "error:<source>:1:15: $RM_"
refuse RT3 "the file is still read: a later line's own error, nothing invented" 'var a = 1;
#ref "f.toml" junk
syscall(60, ka + zz);' "error:<source>:2:15: $RM_
error:<source>:3:20: $ZZ"
refuse RT4 "under cbt's #@incdir line: the user's own line" "#@incdir $D/ref
#ref \"f.toml\" x
syscall(60, ka);" "error:<source>:1:15: $RM_"
refuse RT5 "under a #@srcline marker: the user's own line" '# a prepended line
#@srcline
#ref "f.toml" x
syscall(60, ka);' "error:<source>:1:15: $RM_"
runs RC1 'control: #ref "x"' '#ref "f.toml"
syscall(60, ka + 2);' 7
runs RC2 'control: #ref "x";' '#ref "f.toml";
syscall(60, ka + 2);' 7
runs RC3 'control: #ref "x"  # note' '#ref "f.toml"  # note
syscall(60, ka + 2);' 7
runs RC4 'control: #ref "x" ;  # note' '#ref "f.toml" ;  # note
syscall(60, ka + 2);' 7
runs RC5 'control: CRLF line ends' "$(printf '#ref "f.toml"\r\nsyscall(60, ka + 2);\r')" 7
RDIR=
# The corpus floor: 26 rows on four legs. A row or a leg lost reads RED, never green.
[ "$N" -ge 104 ] || bad "floor: $N row-legs ran (floor 104) - rows or legs were lost"
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: $G: $NFAIL check(s) failed"
    exit 1
fi
echo "PASS: $G - an include line ends at its file name, a tail refused by name in both preprocessor copies, an unclosed file name said so, a #ref line likewise ($N row-legs on $LEGS) (6.7.17, D29, D92)"
exit 0
