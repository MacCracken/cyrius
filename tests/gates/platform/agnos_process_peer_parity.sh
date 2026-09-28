#!/bin/sh
# agnos_process_peer_parity.sh — v6.6.8. The agnos peers of lib/process.cyr and lib/regression.cyr
# define EVERY public verb their host modules define, at the same arity.
#
# ⛔ THE DEFECT. lib/regression.cyr puts its host verbs under `#ifndef CYRIUS_TARGET_AGNOS` and
# routes agnos to lib/regression_agnos.cyr — a hand-kept list. 6.6.7 added
# regression_exec_with_arg_capture_both_status to the host side only, and the two pipe pumps
# (regression_pipe_write_all / regression_pipe_read_all, 6.6.6) never had peers, so any agnos
# build that called one of them did not compile. Nothing compared the two lists.
# The derivation reads the SOURCE: every `fn` whose line sits inside an
# `#ifndef CYRIUS_TARGET_AGNOS` region of the host file, against every `fn` of the peer. Names
# starting `_` are private and not compared. proc_set_timeout_ms / proc_timeout_ms are POSIX-only
# ON PURPOSE (lib/process.cyr says so: a call on agnos must fail to compile rather than silently
# bound nothing), so they are the one named exclusion. CHANGELOG [6.6.8]
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_process_peer_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
cat > "$T/fns.awk" <<'EOF'
# mode=posix: public fns inside an `#ifndef CYRIUS_TARGET_AGNOS` region; mode=all: every public fn.
/^[ \t]*#ifndef[ \t]+CYRIUS_TARGET_AGNOS/ { st[++d] = 1; next }
/^[ \t]*#if/ { st[++d] = 0; next }
/^[ \t]*#endif/ { if (d > 0) d--; next }
/^fn [a-zA-Z]/ {
    ex = 0; for (i = 1; i <= d; i++) if (st[i] == 1) ex = 1
    if (mode == "posix" && ex == 0) next
    line = $0; sub(/^fn /, "", line); name = line; sub(/\(.*/, "", name)
    args = line; sub(/^[^(]*\(/, "", args); sub(/\).*/, "", args)
    n = 0; if (args ~ /[^ \t]/) n = split(args, a, ",")
    print name "/" n
}
EOF
fns() { awk -v mode="$1" -f "$T/fns.awk" "$2" | sort -u; }

echo "lib/process.cyr (POSIX) vs lib/process_agnos.cyr:"
fns posix lib/process.cyr | grep -vx 'proc_set_timeout_ms/1' | grep -vx 'proc_timeout_ms/0' > "$T/ph"
fns all lib/process_agnos.cyr > "$T/pa"
check "the host module has a verb list to compare (sanity floor: >= 14)" "yes" \
    "$([ "$(wc -l < "$T/ph")" -ge 14 ] && echo yes || echo no)"
check "every host verb has an agnos peer at the same arity" "" "$(comm -23 "$T/ph" "$T/pa" | tr '\n' ' ')"
check "the agnos peer defines no verb the host lacks" "" "$(comm -13 "$T/ph" "$T/pa" | tr '\n' ' ')"

echo "lib/regression.cyr (host-only regions) vs lib/regression_agnos.cyr:"
fns posix lib/regression.cyr > "$T/rh"
fns all lib/regression_agnos.cyr > "$T/ra"
check "the host module has a verb list to compare (sanity floor: >= 17)" "yes" \
    "$([ "$(wc -l < "$T/rh")" -ge 17 ] && echo yes || echo no)"
check "every host-only verb has an agnos peer at the same arity" "" "$(comm -23 "$T/rh" "$T/ra" | tr '\n' ' ')"
check "the agnos peer defines no verb the host lacks" "" "$(comm -13 "$T/rh" "$T/ra" | tr '\n' ' ')"

echo "an agnos build that calls the verbs 6.6.7 left without peers compiles clean:"
cat > "$T/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/regression.cyr"
var st[2];
var b[8];
var r = regression_exec_with_arg_capture_both_status("/bin/x", "a", &b, 64, 0, &st);
r = r + regression_pipe_write_all(1, "x", 1, 0) + regression_pipe_read_all(0, &b, 64, 10);
sys_exit(r);
EOF
if CYRIUS_TARGET_AGNOS=1 "$R/build/cycc" < "$T/p.cyr" > "$T/p.bin" 2> "$T/p.err"; then
    check "no 'undefined function' in the agnos build" "" \
        "$(grep -E "undefined function '(regression_|sys_)" "$T/p.err" | tr '\n' ' ')"
else
    echo "  FAIL: the agnos probe did not compile"; grep -E '^error' "$T/p.err" | head -3; fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then echo "FAIL agnos_process_peer_parity: $fails check(s)"; exit 1; fi
echo "PASS agnos_process_peer_parity"
exit 0
