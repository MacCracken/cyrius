#!/bin/sh
# Gate: a diagnostic must report the SOURCE line, not a line perturbed by include expansion.
#
# THE BUG (fixed v6.5.3). Diagnostics in the main source reported
# `actual_line - (number of includes before it)`. With one include a line-2 error said
# line 1; with two it still said 1. The excerpt and caret were always right — only the
# NUMBER was wrong — which made it easy to live with and easy to misdiagnose.
#
# WHY THE FIRST ATTEMPT FAILED, since that is the reusable part. The obvious fix — have
# the preprocessor's RESUME marker carry the line to resume on — is CORRECT, and it was
# implemented, verified present in the built compiler, and reverted as "disproved"
# because the output did not change. It did not change because `lex_pp.cyr` had a
# SECOND, hand-rolled marker emitter (the `source_marked` one-shot) that fired at the
# very same point, emitting a base-less `#@file "<source>"` immediately after the
# correct one. FM_LOOKUP matched the base-less duplicate and restarted numbering at 1.
# Two mechanisms for one job, and the older one silently won.
# LESSON: before concluding a fix "does not work", check whether something else writes
# the same record afterwards.
#
# Mechanism now: markers are `#@file "NAME" BASE`; FM_BUILD packs BASE into the HIGH 32
# bits of the entry's line-count word (the entry must stay 24 B so 1024 fit the band);
# FM_LOOKUP adds it instead of assuming 1. Every emitter goes through PP_FMARK.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/lib"
cd "$D" || exit 2
fails=0

printf 'fn inner_ok(): i64 { return 1; }\n'  > lib/inner.cyr
printf 'fn other_ok(): i64 { return 2; }\n'  > lib/other.cyr
printf 'fn deep_ok(): i64 { return 9; }\n'   > lib/deep.cyr

# $1 label · $2 program · $3 expected "file:line"
chk() {
    printf "$2" > t.cyr
    cat t.cyr | "$CC" > /dev/null 2>t.err
    # file:line only — drop the trailing :COLUMN. The obvious greedy regex keeps it.
    got=$(grep -m1 -oE 'error:[^ ]+:[0-9]+:[0-9]+:' t.err | sed 's/^error://; s/:[0-9]*:$//')
    if [ "$got" = "$3" ]; then echo "  ok: $1 ($got)"
    else echo "  FAIL: $1 — expected $3, got ${got:-<no error>}"; fails=$((fails + 1)); fi
}

# The error must be in a REACHABLE fn: an unreachable one is DCE'd and its body error
# never surfaces, which silently makes a test of this vacuous.
BAD='fn b(): i64 { return 1 + ; }\n'
USE='fn main(): i64 { return b(); }\n'

echo "main-source line is unperturbed by preceding includes:"
chk "no include, error on line 1"        "${BAD}${USE}"                                                              '<source>:1'
chk "1 include, error on line 2"         "include \"lib/inner.cyr\"\n${BAD}${USE}"                                   '<source>:2'
chk "2 includes, error on line 3"        "include \"lib/inner.cyr\"\ninclude \"lib/other.cyr\"\n${BAD}${USE}"        '<source>:3'
chk "blank line between, line 3"         "include \"lib/inner.cyr\"\n\n${BAD}${USE}"                                 '<source>:3'
chk "code before the include, line 3"    "fn g(): i64 { return 1; }\ninclude \"lib/inner.cyr\"\n${BAD}${USE}"        '<source>:3'

# include-once SKIPS a repeat, but the directive LINE is still consumed. Without a RESUME
# marker on the skip path the base goes stale by one per skipped include.
echo "include-once skips still advance the line:"
chk "2nd include is a repeat, line 3"    "include \"lib/inner.cyr\"\ninclude \"lib/inner.cyr\"\n${BAD}${USE}"        '<source>:3'
chk "3rd is a repeat, line 4"            "include \"lib/inner.cyr\"\ninclude \"lib/other.cyr\"\ninclude \"lib/inner.cyr\"\n${BAD}${USE}" '<source>:4'

# An INCLUDED file reports its own name and its own line — including one that itself
# includes something. PP_IFDEF_PASS reads PP_PASS's OUTPUT, i.e. already-expanded text,
# so a naive newline count there yields the EXPANDED line: lib/mid.cyr:2 came out as :4.
echo "included files report their own file and line:"
printf 'fn a(): i64 { return 1; }\nfn bad(): i64 { return 1 + ; }\n' > lib/inner.cyr
chk "error inside a top-level include"   "include \"lib/inner.cyr\"\nfn main(): i64 { return bad(); }\n"             'lib/inner.cyr:2'
printf 'include "lib/deep.cyr"\nfn midbad(): i64 { return 1 + ; }\n' > lib/mid.cyr
chk "error inside a NESTED include"      "include \"lib/mid.cyr\"\nfn main(): i64 { return midbad(); }\n"            'lib/mid.cyr:2'
printf 'include "lib/deep.cyr"\nfn mid_ok(): i64 { return 1; }\n' > lib/mid.cyr
chk "main after a nested include"        "include \"lib/mid.cyr\"\n${BAD}${USE}"                                     '<source>:2'

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: diag-line-after-include — source lines survive include expansion (10 shapes)"
    exit 0
fi
echo "FAIL: diag-line-after-include — $fails of 10 shapes wrong"
exit 1
