#!/bin/sh
# 6.6.11 (J4) — a CLI child inherits the WHOLE environment, not its first 8 KB.
#
# THE BUG. `load_environ` (cbt/core.cyr) builds `_envp`, the envp of every POSIX
# `sys_execve` the CLI makes (cycc, test binaries, git, the hasher, /bin/sh). It read
# /proc/self/environ into a fixed 8,192-byte buffer (`file_read_all(…, buf, 8191)`), so
# every variable past 8 KB — PATH, HOME, CYRIUS_* — was silently absent in the child, and
# the one straddling the cut was truncated. Measured on 6.6.10: with a 10,000-byte BIG
# ahead of ZZ_SENTINEL, the `cyrius run` child's /proc/self/environ was exactly 8,192
# bytes and the sentinel was gone. Now it reads to EOF into a growing buffer.
# (The macOS half, J6 — an EMPTY `_envp` there — is the same function; it is exercised by
# the cross-OS leg on ecb/ach, where a fake tool first on PATH must be run by a CLI child.)
#
# THE CHECK. Build the tree's CLI, run `cyrius run` of a probe that dumps its own
# /proc/self/environ, under `env -i` with a 40,000-byte variable (past the old cap and past
# two doublings of the new buffer) followed by a trailing sentinel. The probe's environment
# must be byte-identical to what `env -0` sees under the same `env -i`: nothing dropped,
# nothing truncated.
#
# MUTATION LEDGER (2026-09-29, 6.6.11): `load_environ` restored to the 8191-byte cap FAILS
# (child environ 8192 bytes, sentinel absent); a buffer that never grows past its first
# 16 KB FAILS the same way.
#
# Exit 77 = could not run (no /proc/self/environ on this host, compiler missing).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=cli_child_env_complete

[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }
[ -r /proc/self/environ ] || { echo "SKIP: $NAME — no /proc/self/environ on this host"; exit 77; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")
H="$T/home"
mkdir -p "$H/bin" "$H/versions/$VER"
cp "$CC" "$H/bin/cycc" && chmod +x "$H/bin/cycc"
cp -R "$ROOT/lib" "$H/versions/$VER/lib"
if ! ( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$H/bin/cyrius" 2> "$T/cli.err" ); then
    echo "FAIL: $NAME — could not build the tree CLI"; sed -n '1,5p' "$T/cli.err"; exit 1
fi
chmod +x "$H/bin/cyrius"

P="$T/proj"; mkdir -p "$P"
printf '[package]\nname = "envprobe"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls", "string", "alloc", "io"]\n' "$VER" > "$P/cyrius.cyml"
cat > "$P/envprobe.cyr" <<'EOF'
fn main(): i64 {
    alloc_init();
    var cap = 1048576;
    var buf = alloc(cap);
    var n = file_read_all("/proc/self/environ", buf, cap);
    if (n <= 0) { return 3; }
    if (n >= cap) { return 4; }
    if (file_write_all("env.out", buf, n) != n) { return 5; }
    return 0;
}
var r = main();
syscall(60, r);
EOF

BIG=$(head -c 40000 /dev/zero | tr '\0' 'x')
# Run under a MINIMAL, fully specified environment so the expected bytes are exact.
envrun() {
    env -i PATH=/usr/bin:/bin HOME="$T/h" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 \
        BIG="$BIG" ZZ_SENTINEL=1 "$@"
}
mkdir -p "$T/h"
envrun env -0 > "$T/want" || { echo "SKIP: $NAME — env -0 unsupported here"; exit 77; }
( cd "$P" && envrun "$H/bin/cyrius" run envprobe.cyr > "$T/run.out" 2> "$T/run.err" )
rc=$?
if [ "$rc" -ne 0 ] || [ ! -f "$P/env.out" ]; then
    echo "FAIL: $NAME — \`cyrius run envprobe.cyr\` exited $rc"; sed -n '1,5p' "$T/run.err"; exit 1
fi
cp "$P/env.out" "$T/child"
want=$(wc -c < "$T/want" | tr -d ' ')
got=$(wc -c < "$T/child" | tr -d ' ')
fail=0
if cmp -s "$T/want" "$T/child"; then
    echo "  ok: the child's environment is byte-identical ($got bytes, BIG=40000, sentinel last)"
else
    echo "  FAIL: the child's environment differs from the parent's: $got bytes, expected $want"
    fail=1
fi
if tr '\0' '\n' < "$T/child" | grep -qx 'ZZ_SENTINEL=1'; then
    echo "  ok: ZZ_SENTINEL (past 40 KB) reached the child"
else
    echo "  FAIL: ZZ_SENTINEL (past 40 KB) did not reach the child"
    fail=1
fi
[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (a >8 KB environment reaches a \`cyrius run\` child intact)"
