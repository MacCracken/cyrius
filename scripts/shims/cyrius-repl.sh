#!/bin/sh
# cyrius-repl — interactive Cyrius expression evaluator
# Type expressions, see results. Uses exit code for simple values.
# Multi-line: end with ;; to execute.
#
# Usage: cyrius repl

CC="${1:-./build/cycc}"

# v6.6.6: a CHECKED private temp dir. This COMPILED each entered expression to
# "/tmp/cyrius_repl_$$", chmod'd it +x and RAN it — a predictable path in a world-writable
# directory, so another local user could pre-create the name (the redirect follows a symlink) or
# swap the binary between the chmod and the exec, and the REPL would execute their code as you.
# The same shape as CVE-44 (scripts/ci.sh) and install.sh's /tmp/cc5_verify, in a script the
# installer ships into ~/.cyrius/versions/<v>/bin. An unguessable 0700 dir leaves nothing to
# pre-create; a mktemp that cannot produce one aborts rather than falling back to a shared name.
# CHANGELOG [6.6.6]
TD=$(mktemp -d) && [ -d "$TD" ] || { echo "error: could not create a private temp directory (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
chmod 700 "$TD" 2>/dev/null
trap 'rm -rf "$TD"' EXIT INT TERM
BIN="$TD/repl"
ERRF="$TD/repl.err"

echo "Cyrius REPL ($(cat VERSION 2>/dev/null || echo '?'))"
echo "Type expressions. Result = exit code (0-255). Use syscall(1,1,...) for output."
echo "End multi-line with ;;   Ctrl+D to exit."
echo ""

# Preamble includes
PREAMBLE='include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/tagged.cyr"
include "lib/str.cyr"
fn _print(n) { fmt_int(n); syscall(1, 1, "\n", 1); return 0; }
fn main() { alloc_init();
'
EPILOGUE='
}
var _r = main();
syscall(60, _r);'

buffer=""
prompt="> "

while true; do
    printf "%s" "$prompt"
    if ! IFS= read -r line; then
        echo ""
        echo "bye"
        break
    fi

    # Check for special commands
    case "$line" in
        ":q"|":quit"|"exit") echo "bye"; break ;;
        ":help"|":h")
            echo "  :q          quit"
            echo "  :type expr  show value as decimal"
            echo "  ;;          execute multi-line buffer"
            echo "  expr;       evaluate expression (exit code = result mod 256)"
            continue
            ;;
        ":type "*)
            expr=$(echo "$line" | sed 's/^:type //')
            src="${PREAMBLE}_print(${expr});return 0;${EPILOGUE}"
            echo "$src" | "$CC" > "$BIN" 2>/dev/null && chmod +x "$BIN" && "$BIN" 2>/dev/null
            rm -f "$BIN"
            continue
            ;;
    esac

    # Accumulate multi-line
    buffer="${buffer}${line}
"

    # Check for ;; (execute) or single-line with ;
    case "$line" in
        *";;")
            # Strip trailing ;;
            buffer=$(echo "$buffer" | sed 's/;;$//')
            ;;
        *";")
            # Single statement — execute immediately
            ;;
        *)
            # Incomplete — wait for more
            prompt="... "
            continue
            ;;
    esac

    # Execute
    # Wrap in main, last expression becomes return value
    src="${PREAMBLE}${buffer}${EPILOGUE}"
    if echo "$src" | "$CC" > "$BIN" 2>"$ERRF"; then
        chmod +x "$BIN"
        result=$("$BIN" 2>/dev/null; echo $?)
        echo "= $result"
    else
        # Show error
        cat "$ERRF" 2>/dev/null
        echo "(compile error)"
    fi
    rm -f "$BIN" "$ERRF"

    buffer=""
    prompt="> "
done
