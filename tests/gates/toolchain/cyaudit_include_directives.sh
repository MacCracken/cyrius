#!/bin/sh
# tests/gates/toolchain/cyaudit_include_directives.sh — 6.6.8 (bite 10)
#
# `cyrius vet` / `cyrius deny` (programs/cyaudit.cyr) see exactly the includes the COMPILER
# sees — every one of them, and nothing else — and judge a path by its COMPONENTS.
#
# THE DEFECT. `scan_includes` read a fixed 262,144 bytes and substring-searched them for
# `include "` at ANY offset, with no line anchor and no comment/string awareness:
#   * a COMMENT naming a removed include (`# Old: include "lib/gone.cyr" -- removed in 2.0`)
#     made vet print `MISSING lib/gone.cyr` and exit 1, and `# see include "../shared/x.cyr"`
#     made deny print a parent traversal and exit 1;
#   * SILENT: a real include past byte 262,144 was invisible — vet printed `no dependencies`
#     and deny `0 deps, 0 violations`, both rc 0 (~41 ecosystem CI pipelines run vet, 10 deny);
#   * the trust test (`lib/`, `src/`, … prefixes) and the traversal test (a LEADING `..`) were
#     prefix tests, so `lib/../../etc/x.cyr` was trusted by vet and passed deny;
#   * a path that exists but cannot be read (a directory) read as "no dependencies", rc 0.
#
# THE RULE, from the compiler: an include is a directive only in COLUMN 0 (ISINCLUDE in
# src/frontend/lex_pp.cyr — an indented `include` is an expression) and only outside a string
# literal (PP_PASS gates on the PP_LEXST string state), and the directive consumes its line.
# ⭐ AXIS 1 ASKS THE COMPILER, NOT cyaudit, what an include is: a file whose only mentions of a
# MISSING include are a comment and a raw line inside a string must COMPILE (so the compiler
# does not see them), and the same file with the include in column 0 must NOT.
#
# The cyaudit under test is BUILT HERE from programs/cyaudit.cyr, never build/ or PATH
# (CYAUDIT_SRC=<file> builds a different source instead — how the mutants below were run).
#
# MUTATION PROOF (each a scratch copy of programs/cyaudit.cyr via CYAUDIT_SRC; checks failed
# of 26). The 6.6.7 cyaudit itself fails 12.
#   M1  no column-0 anchor (`bol == 1` dropped)                                   1
#   M2  no string state (`st == 0` dropped)                                       1
#   M3  the fixed 262,144-byte read restored                                      2
#   M4  `..` detected as a LEADING component only (the old deny test)            2
#   M5  `\` not a component separator                                            1
#   M6  is_trusted ignores `..` components                                        1
#   M7  an unreadable file reads as "no dependencies" again                       2
#   M8  the directive's line not consumed (a later `"` on it opens a string)      1
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

if [ ! -x "$ROOT/build/cycc" ]; then echo "FAIL: cyaudit-include-directives — build/cycc not built"; exit 1; fi
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cyaudit-include-directives — mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT

AU="$T/cyaudit"
if ! "$ROOT/build/cycc" < "${CYAUDIT_SRC:-$ROOT/programs/cyaudit.cyr}" > "$AU" 2> "$T/build.err"; then
    echo "FAIL: cyaudit-include-directives — programs/cyaudit.cyr does not build"; sed -n '1,5p' "$T/build.err"; exit 1
fi
if [ "$(wc -c < "$AU")" -lt 20000 ]; then echo "FAIL: cyaudit-include-directives — built a $(wc -c < "$AU")-byte cyaudit"; exit 1; fi
chmod +x "$AU"

W="$T/w"
mkdir -p "$W/lib" "$W/adir.cyr"
printf 'fn ok_a(): i64 { return 1; }\n' > "$W/lib/ok.cyr"
printf 'fn ok_b(): i64 { return 2; }\n' > "$W/lib/ok2.cyr"

# au <verb> <file> → AO = stdout+stderr, ARC = exit code (10 s cap; a timeout is rc 124)
au() {
    ARC=0
    ( cd "$W" && timeout 10 "$AU" "$1" "$2" ) > "$T/ao" 2>&1 || ARC=$?
}
# the MISSING / UNTRUST / OK / DENY lines, in order, joined by '|'
rows() { grep -E '^  (MISSING|UNTRUST|OK|DENY:) ' "$T/ao" | sed 's/^  //; s/  */ /g' | paste -sd'|' -; }

echo "axis 1 — the COMPILER is the oracle: a comment and a string line are not includes"
# hidden.cyr: the include in a COMMENT; str.cyr: a raw line of a multi-line STRING that begins
# `include "` — the quote there CLOSES the string, so the "path" is code (`; var t = gone; …`),
# which is exactly why the compiler must not read that line as a directive.
printf '# Old: include "lib/gone.cyr" -- removed in 2.0\nsyscall(60, 0);\n' > "$W/hidden.cyr"
printf 'var gone = 7;\nvar s = "doc\ninclude "; var t = gone; var u = "\ntail";\nsyscall(60, 0);\n' > "$W/str.cyr"
printf 'include "lib/gone.cyr"\nsyscall(60, 0);\n' > "$W/real.cyr"
printf 'include "; var t = gone; var u = "\nsyscall(60, 0);\n' > "$W/real2.cyr"
for f in hidden str; do
    crc=0; ( cd "$W" && "$ROOT/build/cycc" < $f.cyr > "$T/p1" 2> /dev/null ) || crc=$?
    check "cycc compiles $f.cyr (it does not see that line as an include)" 0 "$crc"
done
for f in real real2; do
    crc=0; ( cd "$W" && "$ROOT/build/cycc" < $f.cyr > "$T/p2" 2> /dev/null ) || crc=$?
    check "cycc refuses $f.cyr (the same text in column 0, outside a string, IS an include)" nonzero "$([ "$crc" -ne 0 ] && echo nonzero || echo zero)"
done
au vet hidden.cyr
check "vet hidden.cyr: no dependencies, rc 0 (it printed MISSING lib/gone.cyr, rc 1)" "0 1" "$ARC $(grep -c 'no dependencies' "$T/ao")"
au vet str.cyr
check "vet str.cyr: no dependencies, rc 0 (the string line is not an include)" "0 1" "$ARC $(grep -c 'no dependencies' "$T/ao")"
au vet real2.cyr
check "vet real2.cyr: the same line in column 0 IS one" "1|MISSING ; var t = gone; var u = " "$ARC|$(rows)"
au vet real.cyr
check "vet real.cyr: MISSING, rc 1" "1|MISSING lib/gone.cyr" "$ARC|$(rows)"

echo "axis 2 — column 0 only, the directive's line consumed"
printf '    include "lib/indented.cyr"\ninclude "lib/ok.cyr" trailing "quote\ninclude "lib/ok2.cyr"\n' > "$W/col.cyr"
printf 'include "lib/ok.cyr" trailing "quote\ninclude "lib/ok2.cyr"\nsyscall(60, ok_a() + ok_b());\n' > "$W/colp.cyr"
prc=0; ( cd "$W" && "$ROOT/build/cycc" < colp.cyr > "$T/colp" 2> /dev/null && chmod +x "$T/colp" && timeout 10 "$T/colp" ) || prc=$?
check "  (oracle: the compiler takes BOTH includes — the directive swallows its line's stray quote; exit 1+2)" 3 "$prc"
au vet col.cyr
check "an indented include is not a directive; a quote after the path does not hide the next line" "0|OK lib/ok.cyr|OK lib/ok2.cyr" "$ARC|$(rows)"
printf '# see include "../shared/x.cyr"\ninclude "lib/ok.cyr"\n' > "$W/cmt.cyr"
au deny cmt.cyr
check "deny: a traversal named only in a comment is no violation (it was rc 1)" "0|1 deps, 0 violations" "$ARC|$(tail -n 1 "$T/ao")"

echo "axis 3 — the WHOLE file (the 256 KB read was silent)"
awk 'BEGIN { for (i = 0; i < 9000; i++) print "# padding line " i " xxxxxxxxxxxxxxxx"; print "include \"lib/really_missing.cyr\""; print "include \"../escape.cyr\"" }' > "$W/big.cyr"
check "  (premise: the includes sit past byte 262,144)" yes "$([ "$(grep -b 'really_missing' "$W/big.cyr" | cut -d: -f1)" -gt 262144 ] && echo yes || echo no)"
au vet big.cyr
check "vet sees both includes past 256 KB (it said 'no dependencies', rc 0)" "1|MISSING lib/really_missing.cyr|MISSING ../escape.cyr" "$ARC|$(rows)"
au deny big.cyr
check "deny sees the traversal past 256 KB (it said '0 violations', rc 0)" "1|DENY: parent traversal: ../escape.cyr" "$ARC|$(rows)"

echo "axis 4 — paths are judged by COMPONENT"
printf 'include "lib/../lib/ok.cyr"\ninclude "lib/ok.cyr"\n' > "$W/dd.cyr"
au vet dd.cyr
check "vet: lib/../lib/ok.cyr exists but is UNTRUSTED (it was OK); lib/ok.cyr stays OK" "1|UNTRUST lib/../lib/ok.cyr|OK lib/ok.cyr" "$ARC|$(rows)"
printf 'include "lib/../../etc/x.cyr"\ninclude "lib\\..\\..\\x.cyr"\ninclude "lib/..x/a..b/ok.cyr"\n' > "$W/dd2.cyr"
check "  (premise: the second include is spelled with backslashes)" 'include "lib\..\..\x.cyr"' "$(sed -n 2p "$W/dd2.cyr")"
au deny dd2.cyr
check "deny: an inner '..' and a backslash '..' are traversals; '..x' and 'a..b' are not" "2|DENY: parent traversal: lib/../../etc/x.cyr|DENY: parent traversal: lib\\..\\..\\x.cyr" "$ARC|$(rows)"
printf 'include "/abs/x.cyr"\ninclude "C:/abs/x.cyr"\ninclude "\\abs\\x.cyr"\ninclude "lib/ok.cyr"\n' > "$W/abs.cyr"
au deny abs.cyr
check "deny: /x, C:/x and \\x are absolute" "3|DENY: absolute path: /abs/x.cyr|DENY: absolute path: C:/abs/x.cyr|DENY: absolute path: \\abs\\x.cyr" "$ARC|$(rows)"

echo "axis 5 — a file that cannot be read is an error, not a clean bill"
au vet adir.cyr
check "vet on an unreadable path exits 1 and says so (it said 'no dependencies', rc 0)" "1 1" "$ARC $(grep -c 'cannot read' "$T/ao")"
au deny adir.cyr
check "deny on an unreadable path exits non-zero and says so" "nonzero 1" "$([ "$ARC" -ne 0 ] && echo nonzero || echo zero) $(grep -c 'cannot read' "$T/ao")"

echo "axis 6 — anti-vacuous: this repo's own CI files still vet and deny clean"
for f in programs/ark.cyr cbt/cyrius.cyr programs/cyaudit.cyr; do
    ARC=0; ( cd "$ROOT" && timeout 10 "$AU" vet "$f" ) > "$T/ao" 2>&1 || ARC=$?
    n=$(sed -n 's/^\([0-9]*\) deps, 0 untrusted, 0 missing$/\1/p' "$T/ao")
    check "vet $f: clean, with dependencies" "0 yes" "$ARC $([ "${n:-0}" -gt 0 ] && echo yes || echo no)"
    ARC=0; ( cd "$ROOT" && timeout 10 "$AU" deny "$f" ) > "$T/ao" 2>&1 || ARC=$?
    check "deny $f: 0 violations" 0 "$ARC"
done

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: cyaudit-include-directives — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: cyaudit-include-directives — $checks checks"
exit 0
