#!/bin/sh
# manifest_read_whole_file.sh — v6.6.6 bite 17c. A tool that EDITS a file the user owns reads
# the WHOLE file. A fixed read cap over a file you are about to write back is data loss.
#
# ⛔ THE DEFECT. `file_read_all(path, buf, CAP)` returns exactly CAP for a larger file and says
# nothing — the caller cannot tell "the whole file" from "the first CAP bytes". Two tools then
# wrote that buffer back:
#   * programs/cyriusly.cyr `_write_cyml_cyrius_pin` — `alloc(65536)` + a 65535-byte read, edit,
#     write back. Measured on 6.6.5: a 144,090-byte cyrius.cyml came out 65,535 bytes, cut
#     mid-line, and `cyriusly use 9.9.9` printed "Pinned cyrius.cyml to 9.9.9" and exited 0.
#     78,555 bytes of the user's manifest destroyed, silently, by a command that edits ONE line.
#   * cbt/deps.cyr `cmd_update` — the cyrius.toml -> cyrius.cyml migration read the toml at
#     32767 bytes, wrote the buffer as the cyml and then `sys_unlink("cyrius.toml")`, deleting
#     the only untruncated copy.
# The same cap in `_print_resolved_version` is not data loss but is the same root cause: a
# `[package]` section starting past 65,535 bytes was invisible, so `cyriusly use` with no
# argument reported the GLOBAL default for a repo that is in fact pinned (measured: a 73,652-byte
# manifest pinned to 7.7.7 reported "cyrius none (~/.cyrius/current — global default)").
#
# ⭐ THE FIX HAS NO CAP TO GET WRONG. `file_read_whole(path, &n)` (lib/io.cyr) reads into a
# buffer that GROWS, so there is no number to pick and nothing to compare a size against. Not a
# bigger cap — a bigger cap is the same defect with a larger threshold. Not stat-then-alloc
# either: Windows has no POSIX stat on this path (`xstat` returns -1 there) and a stat-then-read
# races a concurrent writer.
#
# AXES
#   1. `cyriusly use <v>` over a 144 KB manifest: the file is EXACTLY what an independent
#      re-implementation of the edit produces (an awk one-liner replacing the `cyrius = ` line),
#      byte for byte — the expected value is computed a different way from the actual.
#   2. `cyriusly use` with no argument over a manifest whose `[package]` starts past 64 KB:
#      it reports the pin, not the global default.
#   3. `cyrius update` migrating a >32 KB cyrius.toml: the cyml holds the WHOLE toml plus the
#      `---` separator, and the toml is gone (i.e. the delete is safe because nothing was lost).
#   4. STATIC, programs/ + cbt/: no function that writes a path back — or unlinks it — reads
#      that same path through a fixed numeric cap. DERIVED per function from the source, so a
#      new read-modify-write site is covered the day it lands, and self-tested on the two
#      pre-fix bodies.
#   5. A FAILED READ IS NOT END-OF-FILE (added by the bite-17 review). RUNTIME: over a path that
#      OPENS but cannot be READ — a directory, where read(2) is -EISDIR — `file_read_whole`
#      returns 0/len 0 and `file_read_all` returns a NEGATIVE, neither of them a buffer; and
#      anti-vacuously a real file still comes back whole and byte-identical. STATIC: no
#      accumulating read loop in lib/io.cyr exits on `n <= 0` — the negative branch is separate
#      and comes first, in all five. Self-tested on the pre-fix body.
#      ⚠ WHY THE STATIC HALF EXISTS. The runtime half can only force a read that fails on its
#      FIRST call; the damaging shape is a read that fails AFTER 40 KB, and there is no portable
#      unprivileged way to force one (RLIMIT_FSIZE is writes; a pipe/FIFO gives EOF, not an
#      error; a pty needs a second process). Both cases are the SAME branch, so the static axis
#      is what pins the partial one: re-fold `n <= 0` and it reddens.
#
# MUTATION LEDGER (measured 6.6.6; each mutant is a COPY of the source in the gate's scratch
# dir, compiled with the tree's build/cycc)
#   a. _write_cyml_cyrius_pin back to alloc(65536) +   -> axes 1 and 4 FAIL (144,090 -> 65,535 B,
#      file_read_all(..., 65535)                          rc 0, "Pinned")
#   b. _print_resolved_version back to the 65535 cap   -> axis 2 FAIL ("cyrius none (global
#                                                         default)" for a pinned repo)
#   c. cmd_update back to alloc(32768) +               -> axes 3 and 4 FAIL (cyml 32,767 B, toml
#      file_read_all("cyrius.toml", ..., 32767)           deleted)
#   d. file_read_whole's grow branch removed           -> axes 1, 2 and 3 FAIL (a 65,536-byte cap
#      (`if (total == cap)`)                              reappears)
#   e. axis-4 detector's write-back rule disabled      -> axis 4 self-test FAIL (cyriusly site)
#   f. axis-4 detector's unlink rule disabled          -> axis 4 self-test FAIL (cbt site)
#   g. file_read_whole's `if (n < 0)` folded back      -> axis 5 FAIL (runtime: the probe gets a
#      into `if (n <= 0)`                                 non-zero buffer with len 0 for a path
#                                                         it could not read — rc 1; and static)
#   h. file_read_all's `if (n < 0)` folded back        -> axis 5 FAIL (runtime rc 5: a read error
#                                                         reported as a 0-byte file; and static)
#   i. file_read_all_r's / the environ loop's          -> axis 5 FAIL (static)
#      negative branch removed
#   j. axis-5 static detector disabled                 -> axis 5 self-test FAIL (the pre-fix
#                                                         body is not reported)
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: manifest_read_whole_file: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }

_build() {   # _build <src> <out>
    "$CC" < "$1" > "$2" 2> "$D/build.err"; brc=$?
    if [ "$brc" -ne 0 ] || [ ! -s "$2" ]; then
        echo "FAIL: $1 does not build (rc=$brc):"; tail -5 "$D/build.err" | sed 's/^/      /'; exit 1
    fi
    grep -q '^warning: undefined function' "$D/build.err" && { echo "FAIL: $1 compiled with undefined functions:"; grep '^warning: undefined' "$D/build.err" | sed 's/^/      /'; exit 1; }
    chmod +x "$2"
}
_build programs/cyriusly.cyr "$D/cyriusly"
_build cbt/cyrius.cyr "$D/cyrius"

# ── axis 1: a 144 KB manifest survives a one-line pin, byte for byte ──
mkdir -p "$D/a1" "$D/home/versions/9.9.9/bin" "$D/home/versions/9.9.9/lib"
{
    printf '[package]\nname = "big"\nversion = "0.1.0"\ncyrius = "1.0.0"\n\n[deps]\n'
    awk 'BEGIN { for (i = 0; i < 3000; i++) printf "padding_line_%06d = \"aaaaaaaaaaaaaaaaaaaaaaa\"\n", i }'
    printf '[end]\nlast = "sentinel"\n'
} > "$D/a1/cyrius.cyml"
orig_sz=$(wc -c < "$D/a1/cyrius.cyml" | tr -d ' ')
[ "$orig_sz" -gt 131072 ] || { echo "FAIL: the axis-1 fixture is only $orig_sz bytes — it must exceed the 65535 cap by a wide margin"; exit 1; }
# the expected result, computed a DIFFERENT way: replace the pin line with awk
awk '{ if ($0 ~ /^cyrius = /) print "cyrius = \"9.9.9\""; else print }' "$D/a1/cyrius.cyml" > "$D/a1.expected"
rc=0; ( cd "$D/a1" && CYRIUS_HOME="$D/home" exec "$D/cyriusly" use 9.9.9 ) > "$D/a1.out" 2>&1 || rc=$?
x=0
[ "$rc" -eq 0 ] || { fail "axis 1: the pin failed (rc=$rc):"; sed 's/^/      /' "$D/a1.out" | head -3; x=1; }
if ! cmp -s "$D/a1/cyrius.cyml" "$D/a1.expected"; then
    fail "axis 1: the manifest is not the expected edit — $(wc -c < "$D/a1/cyrius.cyml" | tr -d ' ') bytes, expected $(wc -c < "$D/a1.expected" | tr -d ' ') (was $orig_sz before the pin)"
    x=1
fi
grep -q '^last = "sentinel"$' "$D/a1/cyrius.cyml" || { fail "axis 1: the tail of the manifest is gone"; x=1; }
[ "$(grep -c '^cyrius = ' "$D/a1/cyrius.cyml")" = "1" ] || { fail "axis 1: $(grep -c '^cyrius = ' "$D/a1/cyrius.cyml") pin lines after the edit, expected 1"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: a $orig_sz-byte cyrius.cyml is pinned byte-for-byte as an independent awk edit produces it"

# ── axis 2: a `[package]` past the old cap is still found ──
mkdir -p "$D/a2" "$D/home/versions/7.7.7/bin"
{
    printf '[preamble]\n'
    awk 'BEGIN { for (i = 0; i < 1600; i++) printf "pad_%06d = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n", i }'
    printf '[package]\nname = "late"\ncyrius = "7.7.7"\n'
} > "$D/a2/cyrius.cyml"
off=$(awk '/^\[package\]$/ { print o; exit } { o += length($0) + 1 }' "$D/a2/cyrius.cyml")
[ "$off" -gt 65535 ] || { echo "FAIL: the axis-2 fixture puts [package] at byte $off — it must start past the 65535 cap"; exit 1; }
rc=0; ( cd "$D/a2" && CYRIUS_HOME="$D/home" exec "$D/cyriusly" use ) > "$D/a2.out" 2>&1 || rc=$?
x=0
grep -q 'cyrius 7.7.7 (pinned in cyrius.cyml)' "$D/a2.out" || { fail "axis 2: the pin at byte $off was not seen:"; sed 's/^/      /' "$D/a2.out" | head -2; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: a [package] starting at byte $off is read (pin reported, not the global default)"

# ── axis 3: the toml -> cyml migration keeps the whole toml before deleting it ──
mkdir -p "$D/a3" "$D/uhome/versions/5.5.5/lib"
printf '5.5.5\n' > "$D/uhome/current"
printf '# one stdlib file so `update` has something to copy\n' > "$D/uhome/versions/5.5.5/lib/io.cyr"
{
    printf '[package]\nname = "big"\n'
    awk 'BEGIN { for (i = 0; i < 1000; i++) printf "pad_%06d = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n", i }'
    printf 'last = "sentinel"\n'
} > "$D/a3/cyrius.toml"
toml_sz=$(wc -c < "$D/a3/cyrius.toml" | tr -d ' ')
[ "$toml_sz" -gt 32767 ] || { echo "FAIL: the axis-3 fixture is only $toml_sz bytes — it must exceed the 32767 cap"; exit 1; }
cp "$D/a3/cyrius.toml" "$D/a3.tomlcopy"
{ cat "$D/a3.tomlcopy"; printf -- '---\n'; } > "$D/a3.expected"
rc=0; ( cd "$D/a3" && CYRIUS_HOME="$D/uhome" exec "$D/cyrius" update ) > "$D/a3.out" 2>&1 || rc=$?
x=0
[ "$rc" -eq 0 ] || { fail "axis 3: cyrius update failed (rc=$rc):"; sed 's/^/      /' "$D/a3.out" | head -5; x=1; }
if ! cmp -s "$D/a3/cyrius.cyml" "$D/a3.expected"; then
    fail "axis 3: the migrated cyrius.cyml is $( [ -f "$D/a3/cyrius.cyml" ] && wc -c < "$D/a3/cyrius.cyml" | tr -d ' ' || echo MISSING) bytes, expected $(wc -c < "$D/a3.expected" | tr -d ' ') (toml was $toml_sz)"
    x=1
fi
[ -f "$D/a3/cyrius.toml" ] && { fail "axis 3: cyrius.toml was not removed after a complete migration"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 3: a $toml_sz-byte cyrius.toml migrates whole (cyml = toml + separator) before the toml is removed"

# ── axis 4: STATIC — a file you write back (or delete) is read WHOLE ──
# Per function: every `file_read_all(P, ..., <digits>)` whose P is also written back or unlinked
# in the same function is a finding. The path is compared as written (a literal or a variable).
cat > "$D/rmw.awk" <<'AWK'
function flush(  p, i) {
    for (p in cap) {
        if (p in wrote || p in unlinked)
            print file "|" fname "|" p "|" cap[p]
    }
    delete cap; delete wrote; delete unlinked
}
/^(pub )?fn / { flush(); fname = $0; sub(/\(.*/, "", fname); sub(/^(pub )?fn /, "", fname) }
{
    line = $0
    sub(/^[ \t]*#.*/, "", line)
    if (match(line, /file_read_all\([^,]+,[^,]+,[ \t]*[0-9]+[ \t]*\)/)) {
        s = substr(line, RSTART, RLENGTH)
        p = s; sub(/^file_read_all\(/, "", p); sub(/,.*/, "", p); gsub(/[ \t]/, "", p)
        n = s; sub(/.*,[ \t]*/, "", n); sub(/\).*/, "", n)
        cap[p] = n
    }
    if (match(line, /(file_write_all|file_write_atomic|file_replace_atomic)\([^,]+,/)) {
        s = substr(line, RSTART, RLENGTH)
        p = s; sub(/^[a-z_]+\(/, "", p); sub(/,.*/, "", p); gsub(/[ \t]/, "", p)
        wrote[p] = 1
    }
    if (match(line, /(sys_unlink|xunlink)\([^)]+\)/)) {
        s = substr(line, RSTART, RLENGTH)
        p = s; sub(/^[a-z_]+\(/, "", p); sub(/\).*/, "", p); gsub(/[ \t]/, "", p)
        unlinked[p] = 1
    }
}
END { flush() }
AWK
_rmw() { awk -v file="${2:-$1}" -f "$D/rmw.awk" "$1"; }
# A site is allowed only when the file is one the TOOL ITSELF made and a prefix is all it wants
# — a child's stdout/stderr capture, a gate's own scratch. Each entry carries its reason, and an
# entry that no longer matches a live site FAILS, so the list cannot rot into a blanket pass.
ALLOW='programs/checks/cx.cyr|_cx_roundtrip_gate|out1|the gate reads the 8-byte header of a binary IT just emitted, then removes it
programs/checks/deps_init.cyr|_deps_sidecar_gate|sidecar|a sidecar the gate itself generated into its scratch dir
programs/checks/deps_init.cyr|_deps_lock_gate|lock_path|a cyrius.lock the gate itself generated into its scratch dir
programs/checks/platform_efi.cyr|_efi_ovmf_fn_exit_gate|efi_bin|the gate reads the 64-byte header of an EFI image it just built
cbt/commands.cyr|_lint_syntax_prepass|errf|a child compiler'"'"'s stderr capture in the private temp dir
cbt/commands.cyr|cmd_capacity|tmperr|a child compiler'"'"'s stderr capture in the private temp dir
cbt/commands.cyr|cmd_distlib|dl_errf|a child compiler'"'"'s stderr capture in the private temp dir
cbt/deps.cyr|_sha256sum_file|tmpf|a capture of sha256sum'"'"'s stdout (one 64-char line)
cbt/deps.cyr|_git_rev|tmpf|a capture of git rev-parse'"'"'s stdout (one 40-char line)'
x=0
found=""
for f in programs/*.cyr programs/checks/*.cyr cbt/*.cyr; do
    r=$(_rmw "$f")
    [ -n "$r" ] && found="$found$r
"
done
# strip the cap from the key, then subtract the allowlist
printf '%s' "$found" | grep . | sed 's/|[0-9]*$//' | LC_ALL=C sort > "$D/keys.live"
printf '%s\n' "$ALLOW" | grep . | cut -d'|' -f1-3 | LC_ALL=C sort > "$D/keys.allow"
unlisted=$(comm -23 "$D/keys.live" "$D/keys.allow")
stale=$(comm -13 "$D/keys.live" "$D/keys.allow")
if [ -n "$(printf '%s' "$unlisted")" ]; then
    fail "axis 4: a file that is written back or deleted is read through a FIXED cap (use file_read_whole):"
    printf '%s\n' "$unlisted" | grep . | sed 's/^/      /'
    x=1
fi
if [ -n "$(printf '%s' "$stale")" ]; then
    fail "axis 4: an allowlist entry no longer matches a live site — remove it, it is hiding nothing and could hide the next one:"
    printf '%s\n' "$stale" | grep . | sed 's/^/      /'
    x=1
fi
# self-test: the two pre-fix bodies must be REPORTED, or the detector reads green on anything
cat > "$D/prefix.cyr" <<'CYR'
fn _write_cyml_cyrius_pin(ver_cstr): i64 {
    var buf = alloc(65536);
    var n = file_read_all("cyrius.cyml", buf, 65535);
    if (file_replace_atomic("cyrius.cyml", out, out_n) != 0) { return 1; }
    return 0;
}
fn cmd_update(): i64 {
    var toml_buf = alloc(32768);
    var toml_n = file_read_all("cyrius.toml", toml_buf, 32767);
    if (file_replace_atomic("cyrius.cyml", cyml_str, strlen(cyml_str)) != 0) { return 1; }
    sys_unlink("cyrius.toml");
    return 0;
}
fn _reads_only(path): i64 {
    var buf = alloc(4096);
    var n = file_read_all(path, buf, 4095);
    return n;
}
CYR
want='x.cyr|_write_cyml_cyrius_pin|"cyrius.cyml"|65535
x.cyr|cmd_update|"cyrius.toml"|32767'
got=$(_rmw "$D/prefix.cyr" x.cyr | LC_ALL=C sort)
[ "$got" = "$(printf '%s' "$want" | LC_ALL=C sort)" ] || { fail "axis 4 self-test: the pre-fix bodies judged:"; printf '%s\n' "$got" | sed 's/^/      /'; fail "axis 4 self-test: expected exactly the two read-modify-write sites (and NOT the read-only one)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: no read-modify-write site in programs/ or cbt/ reads through a fixed cap outside the $(printf '%s\\n' "$ALLOW" | grep -c .) allowlisted tool-own temps (detector self-tested on the two pre-fix bodies)"

# ── axis 5: a read that FAILS is never handed back as content ──
# The read side of the same defect: `file_read_whole` (and `file_read_all`) exited the loop on
# `n <= 0`, folding a read ERROR into end-of-file, so the bytes read so far came back as if they
# were the file — and all three callers WRITE THAT BUFFER BACK. A directory is the one path that
# opens and cannot be read, on every POSIX target, so it is the probe.
mkdir -p "$D/a5/adir"
printf 'the whole file, every byte of it, and then some more bytes\n' > "$D/a5/real.txt"
real_sz=$(wc -c < "$D/a5/real.txt" | tr -d ' ')
cat > "$D/a5/probe.cyr" <<CYR
include "lib/io.cyr"
fn main(): i64 {
    alloc_init();
    # premise: the directory really does OPEN (else the axis would pass vacuously)
    var dfd = file_open("$D/a5/adir", 0, 0);
    if (dfd < 0) { return 7; }
    file_close(dfd);
    # a read that fails must be "could not read" (0), never "here is the file" (a buffer)
    var n = 1234;
    var b = file_read_whole("$D/a5/adir", &n);
    if (b != 0) { return 1; }
    if (n != 0) { return 2; }
    # anti-vacuous: a real file still comes back WHOLE
    var m = 1234;
    var c = file_read_whole("$D/a5/real.txt", &m);
    if (c == 0) { return 3; }
    if (m != $real_sz) { return 4; }
    # the fixed-buffer peer reports the failure as a negative, not as a 0-byte file
    var buf = alloc(4096);
    var r = file_read_all("$D/a5/adir", buf, 4096);
    if (r >= 0) { return 5; }
    var r2 = file_read_all("$D/a5/real.txt", buf, 4096);
    if (r2 != $real_sz) { return 6; }
    return 0;
}
var rc = main();
syscall(60, rc);
CYR
_build "$D/a5/probe.cyr" "$D/a5/probe"
prc=0; ( ulimit -c 0; "$D/a5/probe" ) || prc=$?
x=0
case "$prc" in
    0) ;;
    1) fail "axis 5: file_read_whole handed back a BUFFER for a path it could not read — a failed read is being reported as content"; x=1 ;;
    2) fail "axis 5: file_read_whole reported a non-zero length for a path it could not read"; x=1 ;;
    3) fail "axis 5: file_read_whole returned 0 for a readable file (anti-vacuous check)"; x=1 ;;
    4) fail "axis 5: file_read_whole did not return all $real_sz bytes of a readable file"; x=1 ;;
    5) fail "axis 5: file_read_all returned >= 0 for a path it could not read — a read error folded into end-of-file"; x=1 ;;
    6) fail "axis 5: file_read_all did not return $real_sz for a readable file (anti-vacuous check)"; x=1 ;;
    7) fail "axis 5: a directory does not open read-only here, so the probe cannot force a failing read — the axis must not read green"; x=1 ;;
    *) fail "axis 5: the probe exited $prc (a crash, or a code this gate does not know)"; x=1 ;;
esac
# STATIC: no accumulating read loop in lib/io.cyr exits on `n <= 0`. This is what pins the
# PARTIAL case — a read that fails after 40 KB — which no portable unprivileged runtime probe
# can force (see the axis note in the header). Same branch, so re-folding it reddens here.
cat > "$D/folds.awk" <<'AWK'
{ L[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        line = L[i]
        if (line ~ /^[ \t]*#/) continue
        if (!match(line, /var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(file_read|sys_read)\(/)) continue
        id = substr(line, RSTART, RLENGTH); sub(/^var[ \t]+/, "", id); sub(/[ \t]*=.*/, "", id)
        nsites++
        ok = 0
        for (j = i + 1; j <= NR && j <= i + 8; j++) {
            t = L[j]
            if (t ~ /^[ \t]*#/ || t ~ /^[ \t]*$/) continue
            if (t ~ ("if[ \t]*\\([ \t]*" id "[ \t]*<=[ \t]*0")) break
            if (t ~ ("if[ \t]*\\([ \t]*" id "[ \t]*<[ \t]*0")) ok = 1
            break
        }
        if (!ok) print i ": " line
    }
    print "SITES " nsites > "/dev/stderr"
}
AWK
_read_folds() { awk -f "$D/folds.awk" "$1" 2> "$D/folds.n"; }
# self-test: the pre-fix loop must be reported and the fixed one must not
printf '    var n = file_read(fd, buf + total, cap - total);\n    if (n <= 0) { go = 0; }\n    else { total = total + n; }\n' > "$D/fold.prefix.cyr"
printf '    var n = file_read(fd, buf + total, cap - total);\n    # a comment in between\n    if (n < 0) { file_close(fd); return n; }\n    if (n == 0) { go = 0; }\n' > "$D/fold.clean.cyr"
[ -n "$(_read_folds "$D/fold.prefix.cyr")" ] || { fail "axis 5 self-test: the pre-fix \`n <= 0\` loop was not reported — the detector is blind"; x=1; }
[ -z "$(_read_folds "$D/fold.clean.cyr")" ] || { fail "axis 5 self-test: the fixed loop was reported: $(_read_folds "$D/fold.clean.cyr")"; x=1; }
folds=$(_read_folds lib/io.cyr)
nsites=$(awk '{ print $2 }' "$D/folds.n")
[ -n "$folds" ] && { fail "axis 5: a read loop in lib/io.cyr treats a NEGATIVE read as end-of-file (check \`< 0\` first, separately from \`== 0\`):"; printf '%s\n' "$folds" | sed 's/^/      /'; x=1; }
[ "${nsites:-0}" -ge 5 ] || { fail "axis 5: only ${nsites:-0} read sites found in lib/io.cyr (floor 5) — the scan read nothing"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 5: a path that cannot be read yields 0/len 0 (file_read_whole) and a negative (file_read_all), a readable one all $real_sz bytes, and all $nsites read loops in lib/io.cyr keep a negative read distinct from EOF"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: manifest_read_whole_file (5 axes)"
