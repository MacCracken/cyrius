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
# 6.7.3 (axis 7): that state machine is PP_LEXST_AT since 6.6.20 — a `#` that spells one of the
# lexer's ten attribute words keeps its line in CODE, strings included. cyaudit's copy read it
# as a comment, so after `#assert 1 == 1, "x<LF>y"` vet said `no dependencies` and deny
# `0 violations` (rc 0) for an include the compiler opens, and vet reported a false MISSING
# (rc 1) on a valid program. Axis 7 derives the word list and its `(` rule from LEXATTRWORD
# (src/frontend/lex.cyr) and holds cyaudit's own copy (_au_attr_len) to it — the drift guard.
# ⭐ AXIS 1 ASKS THE COMPILER, NOT cyaudit, what an include is: a file whose only mentions of a
# MISSING include are a comment and a raw line inside a string must COMPILE (so the compiler
# does not see them), and the same file with the include in column 0 must NOT.
#
# The cyaudit under test is BUILT HERE from programs/cyaudit.cyr, never build/ or PATH
# (CYAUDIT_SRC=<file> builds a different source instead — how the mutants below were run).
#
# MUTATION PROOF (each a scratch copy of programs/cyaudit.cyr via CYAUDIT_SRC; checks failed
# of 26 for M1..M8, measured at 6.6.8; of 44 for M9..M12, at 6.7.3). The 6.6.7 cyaudit itself
# fails 12 of the 26.
#   M1  no column-0 anchor (`bol == 1` dropped)                                   1
#   M2  no string state (`st == 0` dropped)                                       1
#   M3  the fixed 262,144-byte read restored                                      2
#   M4  `..` detected as a LEADING component only (the old deny test)            2
#   M5  `\` not a component separator                                            1
#   M6  is_trusted ignores `..` components                                        1
#   M7  an unreadable file reads as "no dependencies" again                       2
#   M8  the directive's line not consumed (a later `"` on it opens a string)      1
#   M9  the 6.7.2 cyaudit (every `#` in code opened a comment)                   14
#       (the census, all ten attribute rows, deny, at_str, the #deprecated( row)
#   M10 the wrong fix: every `#` in code stays code                               2
#       (the `#ioctl "notes` and `#io("notes` guards)
#   M11 #deprecated's `(` rule dropped from _au_attr_len                          2
#       (the census, the #deprecated( row)
#   M12 the `io` row deleted from _au_attr_len                                    2
#       (the census, the #io row)
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

echo "axis 7 — an ATTRIBUTE line is CODE, its strings included (PP_LEXST_AT; 6.7.3)"
# A `#` that spells one of the lexer's attribute words does not open a comment: LEX keeps lexing
# the line as code, and since 6.6.20 so does the preprocessor (PP_LEXST_AT asks LEXATTRWORD). A
# string literal opened there may span lines, and cyaudit, reading the line as a comment, fell
# one quote out of step with the compiler for the rest of the file. cyaudit carries its own
# copy of the list (_au_attr_len), so the drift guard is here: the words AND their `(` rule
# are DERIVED from LEXATTRWORD's rows in src/frontend/lex.cyr, the copy must list exactly the
# same pairs, and every derived word is probed — an attribute added to the lexer alone turns
# this RED. The compiler is the oracle on every row.
CYS="${CYAUDIT_SRC:-$ROOT/programs/cyaudit.cyr}"
LEXROWS=$(grep -oE '_lex_attr_is\(base, q, n, "[a-z_]+", [01]\)' "$ROOT/src/frontend/lex.cyr" \
    | sed 's/.*"\([a-z_]*\)", \([01]\))/\1 \2/' | sort | paste -sd',' -)
AUROWS=$(grep -oE '_au_attr_is\(b, p, n, "[a-z_]+", [01]\)' "$CYS" \
    | sed 's/.*"\([a-z_]*\)", \([01]\))/\1 \2/' | sort | paste -sd',' -)
ATTRS=$(printf '%s' "$LEXROWS" | tr ',' '\n' | sed 's/ .*//')
check "  (premise: LEXATTRWORD in src/frontend/lex.cyr lists at least the ten attribute words)" yes \
    "$([ "$(printf '%s\n' $ATTRS | grep -c .)" -ge 10 ] && echo yes || echo no)"
check "cyaudit's _au_attr_len lists LEXATTRWORD's words with the same \`(\` rule (word ap)" "$LEXROWS" "$AUROWS"
for w in $ATTRS; do
    printf 'fn f(): i64 { return 1; }\n#%s 1 == 1, "x\ny"\ninclude "lib/missing_mod.cyr"\nsyscall(60, f());\n' "$w" > "$W/at_$w.cyr"
    crc=0; ( cd "$W" && "$ROOT/build/cycc" < "at_$w.cyr" > "$T/pa" 2> "$T/pa.err" ) || crc=$?
    au vet "at_$w.cyr"
    check "#$w line: the compiler opens the include after it, and vet reports it MISSING (it said 'no dependencies', rc 0)" \
        "1 1|1|MISSING lib/missing_mod.cyr" "$crc $(grep -c 'cannot open include file: lib/missing_mod.cyr' "$T/pa.err")|$ARC|$(rows)"
done
printf 'fn f(): i64 { return 1; }\n#assert 1 == 1, "x\ny"\ninclude "../escape.cyr"\nsyscall(60, f());\n' > "$W/at_deny.cyr"
crc=0; ( cd "$W" && "$ROOT/build/cycc" < at_deny.cyr > "$T/pd" 2> "$T/pd.err" ) || crc=$?
au deny at_deny.cyr
check "deny sees a traversal after an attribute line, as the compiler does (it said '0 violations', rc 0)" \
    "1 1|1|DENY: parent traversal: ../escape.cyr" "$crc $(grep -c 'path traversal rejected: ../escape.cyr' "$T/pd.err")|$ARC|$(rows)"
# The other direction, on a program that COMPILES: the attribute's string holds a raw line that
# begins `include "` — string data to the compiler, a false MISSING (rc 1) to the old copy.
printf '#assert 1 == 1, "x\ninclude "; var t2 = 0; var u2 = "\ny";\nsyscall(60, 7);\n' > "$W/at_str.cyr"
prc=0; ( cd "$W" && "$ROOT/build/cycc" < at_str.cyr > "$T/as" 2> /dev/null && chmod +x "$T/as" && timeout 10 "$T/as" ) || prc=$?
check "  (oracle: at_str.cyr compiles and runs — that line is string data; exit 7)" 7 "$prc"
au vet at_str.cyr
check "vet at_str.cyr: no dependencies, rc 0 (it reported MISSING '; var t2 = 0; var u2 = ', rc 1)" "0 1" "$ARC $(grep -c 'no dependencies' "$T/ao")"
# Over-correction guards, the compiler's verdict on each: a comment that only STARTS like an
# attribute, and `#io(` (`(` ends only #assert, #deprecated and #pe_import), are comments, so
# their quote opens nothing and the next line's include IS one; `#deprecated(` is code, so its
# string closes on the next line and the include after THAT is one.
printf 'fn f(): i64 { return 1; }\n#ioctl "notes\ninclude "lib/missing_mod.cyr"\nsyscall(60, f());\n' > "$W/at_cmt.cyr"
printf 'fn f(): i64 { return 1; }\n#io("notes\ninclude "lib/missing_mod.cyr"\nsyscall(60, f());\n' > "$W/at_iop.cyr"
printf '#deprecated("x\ny") fn f(): i64 { return 1; }\ninclude "lib/missing_mod.cyr"\nsyscall(60, f());\n' > "$W/at_depp.cyr"
for row in 'at_cmt:`#ioctl "notes` is a comment' 'at_iop:`#io("notes` is a comment' \
           'at_depp:`#deprecated("x<LF>y")` is code'; do
    f=${row%%:*}
    crc=0; ( cd "$W" && "$ROOT/build/cycc" < "$f.cyr" > "$T/pc" 2> "$T/pc.err" ) || crc=$?
    au vet "$f.cyr"
    check "ANTI-VACUOUS: ${row#*:} to both — the compiler opens the include, vet reports it MISSING" \
        "1 1|1|MISSING lib/missing_mod.cyr" "$crc $(grep -c 'cannot open include file: lib/missing_mod.cyr' "$T/pc.err")|$ARC|$(rows)"
done

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: cyaudit-include-directives — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: cyaudit-include-directives — $checks checks"
exit 0
