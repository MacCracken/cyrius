#!/bin/sh
# A stand-in compiler for tests/gates/toolchain/dev_helpers_match_golden.sh: it reads a
# "program" on stdin and writes a shell script that runs it. A source that starts with
# `#!/bin/sh` is copied as it is (a stand-in compiler fork is itself such a script). In a
# program: `EXIT <n>` sets the exit code, `SAY <text>` prints a line, SPIN sleeps 30 s, WARN
# writes warnings, EMPTYOUT writes nothing, BADBAD fails the compile. With CYRIUS_TARGET_WIN
# set the exit code is <n> + 3.
src=$(cat; echo .)
src=${src%.}
case "$src" in '#!/bin/sh'*) printf '%s' "$src"; exit 0 ;; esac
case "$src" in *BADBAD*)
    printf 'error: stub refuses BADBAD\nnote: a note line\nerror: the second error line yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\nerror: third\n' >&2
    exit 1 ;;
esac
case "$src" in *WARN*) printf 'warning: stub warns\nnote: n\nwarning: twice\n' >&2 ;; esac
case "$src" in *EMPTYOUT*) exit 0 ;; esac
code=$(printf '%s\n' "$src" | sed -n 's/^EXIT //p' | head -1)
[ -n "$code" ] || code=0
[ -n "${CYRIUS_TARGET_WIN:-}" ] && code=$((code + 3))
printf '#!/bin/sh\n'
printf '%s\n' "$src" | sed -n "s/^SAY \(.*\)/echo '\1'/p"
case "$src" in *SPIN*) printf 'sleep 30\n' ;; esac
printf 'exit %s\n' "$code"
