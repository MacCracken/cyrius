#!/bin/sh
# v6.4.61 regression: lib/net.cyr sock_accept must NOT allocate on the would-block
# (nothing-pending) path — the accept-per-poll bump-heap leak that OOMs long-running
# non-blocking accept-poll daemons (issue 2026-07-12-net-sock-accept-per-poll-alloc-
# leak). A non-blocking listener polled 100k times with nothing pending must grow the
# bump heap by 0 bytes after the first poll (which lazily builds the would-block
# Result singleton). Pre-fix this grew ~40 B/poll (client_addr+addrlen+Err box).
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
T=$(mktemp --suffix=.cyr); B=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$B" "$E"' EXIT

cat > "$T" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
include "lib/result.cyr"
include "lib/net.cyr"
fn main(): i64 {
    alloc_init();
    var lfd = syscall(41, 2, 1, 0);        # socket(AF_INET, SOCK_STREAM, 0)
    if (lfd < 0) { return 1; }
    sock_reuse(lfd);
    var br = sock_bind(lfd, 0, 0);         # INADDR_ANY, ephemeral port
    if (is_ok(br) == 0) { return 2; }
    var lr = sock_listen(lfd, 16);
    if (is_ok(lr) == 0) { return 3; }
    sock_set_nonblocking(lfd);
    var w = sock_accept(lfd);              # warm-up: builds the singleton
    var before = alloc_used();
    var i = 0;
    while (i < 100000) { var r = sock_accept(lfd); i = i + 1; }
    var grew = alloc_used() - before;
    sock_close(lfd);
    if (grew == 0) { return 42; }
    return 4;
}
var e = main();
syscall(60, e);
EOF

"$CC" < "$T" > "$B" 2>"$E" || { echo "FAIL: probe did not compile:"; cat "$E"; exit 1; }
chmod +x "$B"
rc=0; "$B" || rc=$?
if [ "$rc" -eq 42 ]; then
    echo "PASS: sock_accept would-block path is alloc-free (0 growth over 100k polls)"
    exit 0
elif [ "$rc" -eq 4 ]; then
    echo "FAIL: sock_accept LEAKS on the would-block path (bump heap grew over 100k polls)"; exit 1
else
    echo "SKIP: probe setup returned $rc (socket/bind/listen unavailable in this env)"; exit 0
fi
