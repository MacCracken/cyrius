#!/bin/sh
# tests/gates/platform/io_rdwr_agnos.sh — v6.4.27 agnos O_RDWR flag-map gate.
# `lib/io.cyr` `file_open` translated the POSIX access mode wrong on agnos: line 80
# folded BOTH O_WRONLY (1) and O_RDWR (2) → AO_WRONLY (0x1), never emitting AO_RDWR
# (0x2). So an O_RDWR open became write-only on agnos and any subsequent read failed
# (patra "cannot read header" reopening its B-tree under sit/mirshi). The access-mode
# bits are identical Linux↔agnos (RDONLY/WRONLY/RDWR = 0/1/2), so they pass through:
#   ao = ao | (flags & 3);
# Asserts: (1) the Linux round-trip (create+write O_RDWR, close, reopen O_RDWR, read)
# exits 42; (2) the agnos-target build compiles clean; (3) if mirshi is present, the
# agnos binary round-trips read-after-write under mirshi (exits 42 — the real fix
# check; pre-fix exits 4 on the reopened-fd read); (4) source integrity — io.cyr's
# agnos branch passes the access mode through, not a fold-to-WRONLY.
# See 2026-07-08-io-file-open-agnos-rdwr-downgraded-to-wronly.md.
# v6.6.4 (5): the security bits. `file_open` bridged O_DIRECTORY→AO_DIRECTORY but DROPPED
# O_NOFOLLOW and O_EXCL under a comment saying agnos has no such bits — the kernel added
# AO_NOFOLLOW (0x1000) at 1.56.53 and AO_EXCL (0x2000) at 1.56.56 and its ABI doc listed
# both as "the cyrius peer is still owed". So patra's WAL open (`O_RDWR|O_CREAT|O_TRUNC|
# O_NOFOLLOW`) followed a symlink and truncated its target on agnos. Asserts, under mirshi
# (≥ 1.11.2, which translates both bits): O_NOFOLLOW on a symlink is refused and the plain
# open of the same path succeeds; O_CREAT|O_EXCL on an existing file is refused and O_CREAT
# alone succeeds. Plus source integrity for both bridge lines, so the axis has teeth
# without mirshi.
set -u
cd "$(dirname "$0")/../../.." || exit 2
TMP="${TMPDIR:-/tmp}/iordwr.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/rw.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/io.cyr"
fn main(): i64 {
    var path = "/tmp/cyrius_agnos_rdwr_gate";
    var fd = file_open(path, O_RDWR | O_CREAT | O_TRUNC, 0x1A4);
    if (fd < 0) { return 1; }
    if (file_write(fd, "rdwr-data", 9) != 9) { return 2; }
    file_close(fd);
    var fd2 = file_open(path, O_RDWR, 0);        # reopen O_RDWR (was write-only on agnos)
    if (fd2 < 0) { return 3; }
    var buf[16];
    var nr = file_read(fd2, &buf, 9);            # pre-fix agnos: read on write-only fd → -1
    if (nr != 9) { return 4; }
    file_close(fd2);
    if (load8(&buf + 0) != 114) { return 5; }    # 'r'
    # v6.5.1: `xunlink`, NOT `sys_unlink`. The raw `sys_*` wrappers are per-target by
    # design (lib/syscalls_<arch>_<os>.cyr) and agnos's are LENGTH-CARRYING, so agnos
    # spells this `sys_unlink(path, pathlen)` while every other target spells it
    # `sys_unlink(path)`. This gate compiles the same source for BOTH, so reaching past
    # the portable layer to a raw wrapper cannot work. It only ever "compiled clean"
    # because an arity mismatch was a warning; v6.5.1 makes it an error and this line
    # became the first thing it caught. `xunlink` is the portable bridge and already
    # has the agnos branch that measures the path.
    xunlink(path);
    return 42;
}
var r = main();
sys_exit(r);
EOF

# (1) Linux round-trip.
cat "$TMP/rw.cyr" | build/cycc > "$TMP/rw_lin" 2>/dev/null || { echo "FAIL: Linux O_RDWR build"; exit 1; }
chmod +x "$TMP/rw_lin"; "$TMP/rw_lin" >/dev/null 2>&1; el=$?
[ "$el" = "42" ] || { echo "FAIL: Linux O_RDWR round-trip exit=$el (expect 42)"; exit 1; }

# (2) agnos build compiles clean.
cat "$TMP/rw.cyr" | CYRIUS_TARGET_AGNOS=1 build/cycc > "$TMP/rw_agnos" 2>/dev/null \
  || { echo "FAIL: agnos O_RDWR build"; exit 1; }
chmod +x "$TMP/rw_agnos"

# (3) mirshi (agnos→Linux supervisor), if present, runs the real agnos round-trip.
MIRSHI="$HOME/Repos/mirshi/build/mirshi"
if [ -x "$MIRSHI" ]; then
    "$MIRSHI" "$TMP/rw_agnos" >/dev/null 2>&1; em=$?
    [ "$em" = "42" ] || { echo "FAIL: agnos O_RDWR under mirshi exit=$em (expect 42; pre-fix=4 read-on-write-only)"; exit 1; }
    MIR="mirshi round-trip=42"
else
    MIR="mirshi absent (agnos build clean only)"
fi

# (5) v6.6.4: O_NOFOLLOW / O_EXCL reach the kernel as AO_NOFOLLOW / AO_EXCL.
cat > "$TMP/sec.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/io.cyr"
fn main(): i64 {
    var tgt = "/tmp/cyrius_agnos_sec_target";
    var lnk = "/tmp/cyrius_agnos_sec_link";   # the gate script creates lnk -> tgt beforehand
    var fd = file_open(tgt, O_WRONLY | O_CREAT | O_TRUNC, 0x1A4);
    if (fd < 0) { return 1; }
    file_close(fd);
    # a symlink at lnk -> tgt. agnos cannot create symlinks itself; under mirshi the host
    # can, so the gate script pre-creates it and the binary only checks it is there.
    var s = file_open(lnk, O_RDONLY, 0);
    if (s < 0) { return 2; }                      # control: a plain open FOLLOWS the link
    file_close(s);
    var n = file_open(lnk, O_RDWR | O_NOFOLLOW, 0);
    if (n >= 0) { file_close(n); return 3; }      # O_NOFOLLOW must be REFUSED on a symlink
    var e = file_open(tgt, O_WRONLY | O_CREAT | O_EXCL, 0x1A4);
    if (e >= 0) { file_close(e); return 4; }      # O_CREAT|O_EXCL must be REFUSED on an existing file
    var c = file_open(tgt, O_WRONLY | O_CREAT, 0x1A4);
    if (c < 0) { return 5; }                      # control: O_CREAT alone succeeds
    file_close(c);
    xunlink(tgt);
    return 42;
}
var r = main();
sys_exit(r);
EOF
cat "$TMP/sec.cyr" | build/cycc > "$TMP/sec_lin" 2>/dev/null || { echo "FAIL: Linux O_NOFOLLOW/O_EXCL build"; exit 1; }
chmod +x "$TMP/sec_lin"
rm -f /tmp/cyrius_agnos_sec_link /tmp/cyrius_agnos_sec_target; ln -s /tmp/cyrius_agnos_sec_target /tmp/cyrius_agnos_sec_link
"$TMP/sec_lin" >/dev/null 2>&1; es=$?
[ "$es" = "42" ] || { echo "FAIL: Linux O_NOFOLLOW/O_EXCL probe exit=$es (expect 42; 3=NOFOLLOW followed, 4=EXCL clobbered)"; exit 1; }
cat "$TMP/sec.cyr" | CYRIUS_TARGET_AGNOS=1 build/cycc > "$TMP/sec_agnos" 2>/dev/null \
  || { echo "FAIL: agnos O_NOFOLLOW/O_EXCL build"; exit 1; }
chmod +x "$TMP/sec_agnos"
if [ -x "$MIRSHI" ]; then
    rm -f /tmp/cyrius_agnos_sec_link /tmp/cyrius_agnos_sec_target; ln -s /tmp/cyrius_agnos_sec_target /tmp/cyrius_agnos_sec_link
    "$MIRSHI" "$TMP/sec_agnos" >/dev/null 2>&1; em2=$?
    [ "$em2" = "42" ] || { echo "FAIL: agnos O_NOFOLLOW/O_EXCL under mirshi exit=$em2 (expect 42; 3=O_NOFOLLOW dropped → symlink followed, 4=O_EXCL dropped → existing file clobbered; needs mirshi ≥ 1.11.2)"; exit 1; }
    MIR="$MIR; O_NOFOLLOW/O_EXCL refused under mirshi=42"
fi
rm -f /tmp/cyrius_agnos_sec_link /tmp/cyrius_agnos_sec_target
grep -q 'if ((flags & 131072) != 0) { ao = ao | 0x1000; }' lib/io.cyr \
  || { echo "FAIL: lib/io.cyr agnos branch no longer bridges O_NOFOLLOW -> AO_NOFOLLOW (0x1000)"; exit 1; }
grep -q 'if ((flags & 128) != 0) { ao = ao | 0x2000; }' lib/io.cyr \
  || { echo "FAIL: lib/io.cyr agnos branch no longer bridges O_EXCL -> AO_EXCL (0x2000)"; exit 1; }
grep -q 'AO_NOFOLLOW = 0x1000;' lib/syscalls_x86_64_agnos.cyr && grep -q 'AO_EXCL = 0x2000;' lib/syscalls_x86_64_agnos.cyr \
  || { echo "FAIL: lib/syscalls_x86_64_agnos.cyr AgnosOpenFlag lost AO_NOFOLLOW/AO_EXCL"; exit 1; }

# (4) source integrity — the agnos branch passes the access mode through.
grep -q 'ao = ao | (flags & 3);' lib/io.cyr \
  || { echo "FAIL: lib/io.cyr agnos branch no longer passes the access mode through (re-collapse to WRONLY?)"; exit 1; }
grep -q 'if ((flags & 3) != 0) { ao = ao | 0x1; }' lib/io.cyr \
  && { echo "FAIL: lib/io.cyr still folds O_RDWR→AO_WRONLY (the bug)"; exit 1; }

echo "OK: O_RDWR Linux round-trip=42; agnos build clean; $MIR; io.cyr passes access mode through; O_NOFOLLOW/O_EXCL bridged (Linux probe=42)"
exit 0
