#!/bin/sh
# The OLD_CC stand-in beside stub/cycc.sh: the same programs, one higher exit code, and its
# own error text.
src=$(cat; echo .)
src=${src%.}
case "$src" in *BADBAD*) printf 'note: old note\nerror: old stub refuses\n' >&2; exit 2 ;; esac
case "$src" in *EMPTYOUT*) exit 0 ;; esac
code=$(printf '%s\n' "$src" | sed -n 's/^EXIT //p' | head -1)
[ -n "$code" ] || code=0
printf '#!/bin/sh\n'
printf '%s\n' "$src" | sed -n "s/^SAY \(.*\)/echo 'old \1'/p"
printf 'exit %s\n' "$((code + 1))"
