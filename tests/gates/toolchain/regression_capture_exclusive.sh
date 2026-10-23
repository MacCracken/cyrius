#!/bin/sh
# Gate: lib/regression.cyr's capture verbs create the file their child writes to EXCLUSIVELY and
# PRIVATELY, under $TMPDIR, and name a refusal (6.7.15, CYRIUS-2026-0036).
#
# THE BUG. regression_exec_capture[_status], regression_exec_with_arg_capture[_status] and
# regression_exec_with_arg_capture_both[_status] wrote the child's stdout to "/tmp/<prefix><pid>"
# (`_regression_tmp_path`: audit_xc_ / audit_xa_) opened with Linux's O_WRONLY|O_CREAT|O_TRUNC
# bits (577) — no O_EXCL, no O_NOFOLLOW, /tmp whatever TMPDIR said, mode 0644. Another local
# user who planted a symlink at an upcoming pid's name had a capture (the check driver runs every
# .tcyr through regression_exec_capture_status) truncate and overwrite any file the victim can
# write; a planted regular file was read back as the capture. Linux's fs.protected_symlinks /
# protected_regular refuse both in a sticky /tmp; macOS has neither. (On Darwin 577 is
# O_WRONLY|O_ASYNC|O_CREAT — not even O_TRUNC.)
#
# THE FIX. `_regression_capture_open` creates each candidate "<base>/<prefix><pid>", then
# "…<pid>.1" … ".63", O_CREAT|O_EXCL|O_NOFOLLOW mode 0600 with each target's own bits (O_RDWR
# since 6.7.16, which unlinks the name at once and reads the capture back from the fd); a taken
# name is skipped; past the bound — or on any other open error — one stderr line names the
# refusal and nothing runs. The base is $TMPDIR when it is absolute (trailing slashes dropped),
# else /tmp (cbt's `_cbt_tmpbase` rule). The platform rows — the filed repro verbatim, planted
# links and files at each verb's names, all 64 taken, the file 0600 and unlinked before the
# child runs — are tests/tcyr/crossos/regression_capture_exclusive.tcyr, which the release gate
# runs on ecb, ach, pi and cass (macOS is where the hole was open).
#
# AXES (Linux; the probe is built from THIS tree with build/cycc). The planting shell `exec`s the
# probe, so its $$ IS the probe's pid and the names are predicted exactly — another process
# plants, as the attacker does.
#   1  symlinks planted at the first 3 names under a private TMPDIR, by another process ->
#      the capture is the child's ("cap-out"), the victim keeps its bytes, the 3 links stay
#   2  all 64 names taken -> 0 bytes, status -1, ONE stderr line naming the last name and
#      "every name before it were taken; nothing was run", all 64 plants intact
#   3  TMPDIR: (a) "$T///" -> the refusal names "$T/audit_xa_<pid>.63" (the base, slashes
#      dropped); (b) a missing directory -> refused by name with errno 2, nothing run;
#      (c) a relative value and (d) an empty one are ignored: 64 names planted under the
#      relative directory do not stop the capture (it is made under /tmp), and are left intact
#   4  STATIC over lib/**/*.cyr: (a) every "/tmp" or "/tmp/…" string literal in code sits in an
#      allowlisted file|fn, each with its reason, and an entry matching no live literal fails;
#      (b) lib/regression.cyr: `_regression_capture_open`'s open spells O_CREAT, O_EXCL,
#      O_NOFOLLOW and 0x180, only it calls `_regression_capture_name`, and each capture verb gets
#      its file from it; since 6.7.16 it also unlinks the name it created (`sys_unlink(name)`), and
#      each verb reads the capture back from its fd (`_regression_capture_read`) and never names a
#      file (no file_read_all / file_open / sys_unlink). Both detectors self-tested (the 6.7.16 rules
#      on the live file with the unlink deleted, and with the three read-backs put back by name).
#   5  CYRIUS-2026-0048 (6.7.18) — the same class in the CLI the PE build ships. A rooted POSIX
#      path is DRIVE-RELATIVE on Windows (<current drive>:\proc\self\environ, :\root\.cyrius), a
#      name any local user can create (the 0012 / 0014 / 0020 class lib/io.cyr's env_block
#      already refuses): load_environ read "/proc/self/environ" on PE to EOF through unchecked
#      doubling allocations (2.3 GB faulted cyrius.exe), and find_tools fell back to the home
#      "/root" with USERPROFILE and CYRIUS_HOME unset, then looked for \root\.cyrius\bin\cycc.exe.
#      (a) STATIC over cbt/*.cyr: a "/proc/…", "/etc/…", "/sys/…", "/dev/…", "/root", "/tmp",
#      "/usr/…", "/var/…" or "/home/…" literal in code the PE build compiles — outside an
#      `#ifndef CYRIUS_TARGET_WIN` / `#ifdef CYRIUS_TARGET_{LINUX,MACOS,AGNOS,CX}` region (or the
#      `#else` of `#ifdef CYRIUS_TARGET_WIN`) — sits in an allowlisted file|fn|literal with its
#      reason; an entry matching no live site fails. Detector self-tested.
#      (b) wine (a named SKIP without it): cyrius.exe --version under WINEDEBUG=+file opens no
#      "/proc/self/environ"; with USERPROFILE and CYRIUS_HOME unset (a .bat) it exits 1 naming
#      the refusal and probes no "/root/.cyrius". Both RED on the parent (b873a1eca's cbt/: 5a
#      flags load_environ, _cbt_environ and find_tools; 5b sees both opens).
#
# MUTATION LEDGER (2026-10-18, 6.7.15, each in a scratch copy of the tree's lib/; the .tcyr's
# count of 22 rows alongside):
#   a. the open without O_EXCL|O_NOFOLLOW (O_WRONLY|O_CREAT|O_TRUNC)  -> axes 1, 2, 3a, 4b RED; the
#      .tcyr 16 RED (the repro answers 0: the victim emptied)
#   b. O_EXCL alone dropped                                            -> axes 1 (the link refused
#      with ELOOP, nothing captured), 2, 3a, 4b RED; the .tcyr 15
#   c. O_NOFOLLOW alone dropped                                        -> axis 4b RED only: O_EXCL by
#      itself never follows a final link, so no behaviour row can see it
#   d. mode 0644                                                       -> axis 4b; the .tcyr 6 (the
#      "0600" rows)
#   e. the retry dropped (a taken name gives up)                       -> axes 1, 2, 3a; the .tcyr 12
#   f. the refusal line dropped                                        -> axes 2, 3a, 3b
#   g. TMPDIR ignored (always /tmp)                                    -> axes 2, 3a, 3b
#   h. a relative or empty TMPDIR honoured                             -> axes 3c, 3d
#   i. 6.7.15's base (`_regression_tmp_path`, 577)                     -> axes 2, 3a, 3b, 4a, 4b; the
#      .tcyr does not compile (it predicts names with the new helpers). Axis 1 reads green there:
#      the old code looked in /tmp, not the gate's TMPDIR, so its plants were never in the way.
# MUTATION LEDGER (2026-10-19, 6.7.16 — the name unlinked at its create, the capture read from the
# fd; issues/archived/2026-10-19-killed-capture-verb-leaves-capture-file-for-ever.md). The .tcyr has 23 rows:
#   j. the unlink dropped                    -> axes 1 (the files are left) and 4b; the .tcyr 7 (the
#      6 `_cr_private` rows see the name while the child runs, and a leaked name stops one plant)
#   k. the parent's lift dropped              -> the .tcyr 1 (`_cr_parent_stderr`: fd 2 closed, the
#      knob warning written into the capture)
#   l. the read-back's lseek dropped          -> the .tcyr 19 (every capture reads empty)
#   m. 6.7.15's verbs (unlink after a read-back by name) -> axis 4b; the .tcyr 6 (`_cr_private`)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=regression_capture_exclusive

[ -x "$CC" ] || { echo "FAIL: $NAME — $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $NAME: $*"; FAIL=1; }

# ── the probe: runs a capture verb on itself ("child" prints cap-out) and reports ──
# argv(1) "xc" -> regression_exec_capture_status (the child sees CAPG in its environment),
# else regression_exec_with_arg_capture_status. Prints "rc=<bytes> st=<status> cap=<bytes>".
cat > "$W/probe.cyr" <<'EOF'
include "lib/regression.cyr"
include "lib/args.cyr"
args_init();
if (argc() > 1) {
    if (streq(argv(1), "child") == 1) { sys_write(1, "cap-out", 7); sys_exit(0); }
}
if (getenv("CAPG") != 0) { sys_write(1, "cap-out", 7); sys_exit(0); }
var st[16];
var buf[64];
var envp[16];
store64(&envp, "CAPG=1");
store64(&envp + 8, 0);
store64(&st, 99);
var n = 0;
var xc = 0;
if (argc() > 1) { if (streq(argv(1), "xc") == 1) { xc = 1; } }
if (xc == 1) { n = regression_exec_capture_status(argv(0), &buf, 64, &envp, &st); }
else { n = regression_exec_with_arg_capture_status(argv(0), "child", &buf, 64, &envp, &st); }
var sb = str_builder_new();
str_builder_add_cstr(sb, "rc=");
str_builder_add_int(sb, n);
str_builder_add_cstr(sb, " st=");
str_builder_add_int(sb, load64(&st));
str_builder_add_cstr(sb, " cap=");
var i = 0;
while (i < n) { str_builder_add_byte(sb, load8(&buf + i)); i = i + 1; }
str_builder_add_cstr(sb, "\n");
var s = str_builder_build(sb);
sys_write(1, str_data(s), strlen(str_data(s)));
syscall(60, 0);
EOF
( cd "$ROOT" && "$CC" < "$W/probe.cyr" > "$W/probe" 2> "$W/probe.err" ) && [ -s "$W/probe" ] \
  || { echo "FAIL: $NAME: the probe does not build:"; grep -v '^note\|^warning' "$W/probe.err" | tail -3; exit 1; }
chmod +x "$W/probe" || exit 1

# _plant <tmpdir-env> <dir> <prefix> <n> <kind> <probe-args...> — under env TMPDIR=<tmpdir-env>
# ("-" = unset), plant <n> names "<dir>/<prefix><pid>[.<i>]" (kind `link` -> symlinks to
# $W/victim, `file` -> files holding "P"), then exec the probe under that same pid. stdout to
# $W/out, stderr to $W/err; prints the pid.
_plant() {
    _t=$1; _d=$2; _p=$3; _n=$4; _k=$5; shift 5
    if [ "$_t" = - ]; then set -- env -u TMPDIR "$W/probe" "$@"; else set -- env TMPDIR="$_t" "$W/probe" "$@"; fi
    ( cd "$W" && exec sh -c '
        d=$1; p=$2; n=$3; k=$4; shift 4
        echo $$ > "'"$W"'/pid"
        i=0
        while [ $i -lt "$n" ]; do
            f="$d/$p$$"; [ $i -gt 0 ] && f="$f.$i"
            if [ "$k" = link ]; then ln -s "'"$W"'/victim" "$f" || exit 90
            else echo P > "$f" || exit 90; fi
            i=$((i + 1))
        done
        exec "$@"' sh "$_d" "$_p" "$_n" "$_k" "$@" ) > "$W/out" 2> "$W/err" || :   # judged by its output
}
_nlinks() { find "$1" -maxdepth 1 -type l -name "$2*" | wc -l | tr -d ' '; }
_nplants() {  # regular files named <prefix>* in <dir> holding exactly "P"
    _c=0
    for _f in "$1/$2"*; do [ -f "$_f" ] && [ ! -L "$_f" ] && [ "$(cat "$_f")" = P ] && _c=$((_c + 1)); done
    echo "$_c"
}

# ── axis 1: symlinks at the first 3 names, planted by another process ──
T1="$W/t1"; mkdir -p "$T1"
a1=0
for verb in xa xc; do
    pre=audit_${verb}_
    rm -f "$T1"/* ; printf 'precious\n' > "$W/victim"
    _plant "$T1" "$T1" "$pre" 3 link "$verb"
    grep -qx 'rc=7 st=0 cap=cap-out' "$W/out" || { fail "axis 1 ($verb): the capture with links at its first 3 names is not the child's: $(cat "$W/out" "$W/err" | head -2 | tr '\n' ' ')"; a1=1; }
    [ "$(cat "$W/victim")" = precious ] || { fail "axis 1 ($verb): the capture wrote THROUGH a planted link — the victim now holds $(wc -c < "$W/victim") bytes"; a1=1; }
    [ "$(_nlinks "$T1" "$pre")" = 3 ] || { fail "axis 1 ($verb): $(_nlinks "$T1" "$pre") of the 3 planted links are left"; a1=1; }
    [ "$(find "$T1" -type f | wc -l | tr -d ' ')" = 0 ] || { fail "axis 1 ($verb): a capture file was left: $(ls "$T1" | tr '\n' ' ')"; a1=1; }
done
[ "$a1" = 0 ] && echo "  ok: axis 1: links planted at a verb's first 3 names by another process are skipped — the capture is the child's, the victim and the links are left as they were, no file is left"

# ── axis 2: all 64 names taken -> refused by name, nothing runs ──
T2="$W/t2"; mkdir -p "$T2"
_plant "$T2" "$T2" audit_xa_ 64 file
p=$(cat "$W/pid")
a2=0
grep -qx 'rc=0 st=-1 cap=' "$W/out" || { fail "axis 2: with every name taken the verb answered '$(cat "$W/out")' (want rc=0 st=-1: nothing ran)"; a2=1; }
want2="regression: cannot create the capture file $T2/audit_xa_$p.63 — it and every name before it were taken; nothing was run"
[ "$(cat "$W/err")" = "$want2" ] || { fail "axis 2: the refusal is not the one named line:"; sed 's/^/      /' "$W/err" | head -3; a2=1; }
[ "$(_nplants "$T2" audit_xa_)" = 64 ] || { fail "axis 2: only $(_nplants "$T2" audit_xa_) of the 64 planted files are intact"; a2=1; }
[ "$a2" = 0 ] && echo "  ok: axis 2: with all 64 names taken nothing runs (0 bytes, status -1), one stderr line names the refusal, every plant is intact"

# ── axis 3: TMPDIR ──
a3=0
T3="$W/t3"; mkdir -p "$T3"
_plant "$T3///" "$T3" audit_xa_ 64 file
p=$(cat "$W/pid")
grep -q "cannot create the capture file $T3/audit_xa_$p.63 — " "$W/err" \
  || { fail "axis 3a: TMPDIR=\"\$T///\" is not the base with its slashes dropped: $(head -1 "$W/err")"; a3=1; }
_plant "$W/missing" "$W" none 0 file
p=$(cat "$W/pid")
{ grep -qx 'rc=0 st=-1 cap=' "$W/out" \
  && [ "$(cat "$W/err")" = "regression: cannot create the capture file $W/missing/audit_xa_$p (errno 2); nothing was run" ]; } \
  || { fail "axis 3b: a missing TMPDIR is not refused by name: $(cat "$W/out" "$W/err" | tr '\n' ' ')"; a3=1; }
mkdir -p "$W/rel"
_plant rel "$W/rel" audit_xa_ 64 file
{ grep -qx 'rc=7 st=0 cap=cap-out' "$W/out" && [ "$(_nplants "$W/rel" audit_xa_)" = 64 ]; } \
  || { fail "axis 3c: a RELATIVE TMPDIR was used as the base: $(cat "$W/out" "$W/err" | head -2 | tr '\n' ' ')"; a3=1; }
_plant "" "$W" none 0 file
grep -qx 'rc=7 st=0 cap=cap-out' "$W/out" || { fail "axis 3d: an EMPTY TMPDIR was used as the base: $(cat "$W/out" "$W/err" | head -2 | tr '\n' ' ')"; a3=1; }
_plant - "$W" none 0 file xc
grep -qx 'rc=7 st=0 cap=cap-out' "$W/out" || { fail "axis 3e: with TMPDIR unset the capture failed: $(cat "$W/out" "$W/err" | head -2 | tr '\n' ' ')"; a3=1; }
[ "$a3" = 0 ] && echo "  ok: axis 3: an absolute TMPDIR is the base (trailing slashes dropped), a missing one is refused by name (errno 2), a relative or empty one is ignored for /tmp"

# ── axis 4: STATIC ──
# The scanner: "<fn>\t<literal>" for every "…" literal outside `#` comments and char literals
# (cbt_no_shared_tmp_paths.sh's, plus the enclosing fn).
cat > "$W/lits.awk" <<'AWK'
/^[ \t]*fn [A-Za-z_0-9]+[ \t]*\(/ { f = $0; sub(/^[ \t]*fn[ \t]+/, "", f); sub(/[ \t]*\(.*/, "", f) }
{
    line = $0; n = length(line); i = 1; ins = 0; cur = ""
    while (i <= n) {
        c = substr(line, i, 1)
        if (ins) {
            if (c == "\\") { cur = cur substr(line, i, 2); i += 2; continue }
            if (c == "\"") { print f "\t" cur; ins = 0; cur = ""; i++; continue }
            cur = cur c; i++; continue
        }
        if (c == "#") break
        if (c == "'") {
            if (substr(line, i + 1, 1) == "\\") { i += 4 } else { i += 3 }
            continue
        }
        if (c == "\"") { ins = 1; cur = "" }
        i++
    }
}
AWK
# The code lines of each fn: "<fn>\t<line>", comments dropped.
cat > "$W/code.awk" <<'AWK'
/^[ \t]*fn [A-Za-z_0-9]+[ \t]*\(/ { f = $0; sub(/^[ \t]*fn[ \t]+/, "", f); sub(/[ \t]*\(.*/, "", f) }
{ l = $0; sub(/^[ \t]*#.*/, "", l); sub(/[ \t]#[^"]*$/, "", l); if (l != "") print f "\t" l }
AWK
_tmplits() { awk -f "$W/lits.awk" "$1" | awk -F'\t' '$2 == "/tmp" || $2 ~ /^\/tmp\//' | cut -f1 | LC_ALL=C sort -u; }
# 4b's verdict on a regression.cyr-shaped file: the empty string when it holds.
_capopen_bad() {
    awk -f "$W/code.awk" "$1" > "$W/code"
    o=$(awk -F'\t' '$1 == "_regression_capture_open" && $2 ~ /sys_open\(|file_open\(/' "$W/code")
    [ -n "$o" ] || { echo "no open in _regression_capture_open"; return; }
    for w in O_CREAT O_EXCL O_NOFOLLOW 0x180; do
        printf '%s\n' "$o" | grep -q "$w" || echo "the capture open lacks $w: $(printf '%s' "$o" | cut -f2 | sed 's/^ *//')"
    done
    awk -F'\t' '$1 != "_regression_capture_open" && $1 != "_regression_capture_name" && $2 ~ /_regression_capture_name\(/ { print "a caller other than _regression_capture_open builds a capture name: " $1 }' "$W/code"
    # 6.7.16: the name is unlinked at its create, and the verbs read the capture back from the fd
    awk -F'\t' '$1 == "_regression_capture_open" && $2 ~ /sys_unlink\(name\)/' "$W/code" | grep -q . \
        || echo "_regression_capture_open does not unlink the name it created"
    for v in regression_exec_capture_status regression_exec_with_arg_capture_status regression_exec_with_arg_capture_both_status; do
        awk -F'\t' -v v="$v" '$1 == v && $2 ~ /_regression_capture_open\(/' "$W/code" | grep -q . || echo "$v does not take its file from _regression_capture_open"
        awk -F'\t' -v v="$v" '$1 == v && $2 ~ /_regression_capture_read\(/' "$W/code" | grep -q . || echo "$v does not read its capture back from its fd (_regression_capture_read)"
        awk -F'\t' -v v="$v" '$1 == v && $2 ~ /file_read_all\(|file_open\(|sys_unlink\(/ { print v " reaches its capture by name:" $2 }' "$W/code"
    done
}
# self-tests: the 6.7.14 shape, the luks shape, the bare base; a comment and a look-alike are not
TR=/tmp
mkdir -p "$W/fx"
sed "s|@T@|$TR|g" > "$W/fx/lits.cyr" <<'EOF'
fn _old(prefix): i64 {
    str_builder_add_cstr(sb, "@T@/");
    # a comment may say "@T@/x"
}
fn _luks(): i64 {
    var prefix = "@T@/.agnos-luks-";
    if (c == '"') { var q = "@T@"; }
    var y = "@T@foo"; var z = "a#b"; var u = "@T@/after_hash";
}
EOF
st4=0
[ "$(_tmplits "$W/fx/lits.cyr" | tr '\n' ' ')" = "_luks _old " ] || { fail "axis 4 self-test: the literal scanner saw '$(_tmplits "$W/fx/lits.cyr" | tr '\n' ' ')' (want _luks _old)"; st4=1; }
n4=$(awk -f "$W/lits.awk" "$W/fx/lits.cyr" | awk -F'\t' '$2 == "/tmp" || $2 ~ /^\/tmp\//' | grep -c .)
[ "$n4" = 4 ] || { fail "axis 4 self-test: $n4 /tmp literals counted in the fixture (want 4: the comment and \"/tmpfoo\" are not)"; st4=1; }
sed 's/O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0x180/O_RDWR | O_CREAT | O_TRUNC, 0x180/' "$ROOT/lib/regression.cyr" > "$W/fx/noexcl.cyr"
cmp -s "$W/fx/noexcl.cyr" "$ROOT/lib/regression.cyr" && { fail "axis 4 self-test: the capture open is not spelled as this gate expects — update the mutation"; st4=1; }
[ -n "$(_capopen_bad "$W/fx/noexcl.cyr")" ] || { fail "axis 4 self-test: a capture open without O_EXCL / O_NOFOLLOW was not flagged"; st4=1; }
awk '/^fn _regression_capture_open\(/ { f = 1 } f && /^            sys_unlink\(name\);$/ { next } /^}/ { f = 0 } { print }' "$ROOT/lib/regression.cyr" > "$W/fx/nounlink.cyr"
cmp -s "$W/fx/nounlink.cyr" "$ROOT/lib/regression.cyr" && { fail "axis 4 self-test: the capture open's unlink is not spelled as this gate expects — update the mutation"; st4=1; }
[ -n "$(_capopen_bad "$W/fx/nounlink.cyr")" ] || { fail "axis 4 self-test: a capture open that keeps its name was not flagged"; st4=1; }
sed 's/^    return _regression_capture_read(out_fd, buf, buflen);$/    var total = file_read_all(out_path, buf, buflen); sys_unlink(out_path); return total;/' "$ROOT/lib/regression.cyr" > "$W/fx/byname.cyr"
cmp -s "$W/fx/byname.cyr" "$ROOT/lib/regression.cyr" && { fail "axis 4 self-test: the capture read-back is not spelled as this gate expects — update the mutation"; st4=1; }
[ "$(_capopen_bad "$W/fx/byname.cyr" | grep -c 'reaches its capture by name')" = 3 ] || { fail "axis 4 self-test: the verbs reading the capture back by name were not each flagged"; st4=1; }
# (a) the literals
ALLOW4='lib/regression.cyr|_regression_tmp_base|the base when TMPDIR is unset, relative or empty: every name under it is created by _regression_capture_open, O_CREAT|O_EXCL|O_NOFOLLOW 0600
lib/sigil.cyr|luks_keyfile_path|"<prefix><pid>-<16 random hex>", created by luks_write_keyfile O_CREAT|O_EXCL|O_NOFOLLOW 0600 (sigil Audit F-3)'
: > "$W/sites"
nf=0; nl=0
for f in $(cd "$ROOT" && find lib -name '*.cyr' | LC_ALL=C sort); do
    nf=$((nf + 1))
    nl=$((nl + $(awk -f "$W/lits.awk" "$ROOT/$f" | grep -c . || true)))
    _tmplits "$ROOT/$f" | sed "s|^|$f\||" >> "$W/sites"
done
printf '%s\n' "$ALLOW4" | cut -d'|' -f1,2 | LC_ALL=C sort -u > "$W/allow.keys"
bad=$(LC_ALL=C sort -u "$W/sites" | LC_ALL=C comm -23 - "$W/allow.keys")
dead=$(LC_ALL=C sort -u "$W/sites" | LC_ALL=C comm -13 - "$W/allow.keys")
a4=$st4
{ [ "$nf" -ge 100 ] && [ "$nl" -ge 3000 ]; } || { fail "axis 4a: scanned $nf lib files / $nl literals (floors 100 / 3000) — the scan read nothing"; a4=1; }
[ -z "$bad" ] || { echo "$bad" | sed "s/^/FAIL: $NAME: axis 4a: a fixed \/tmp path in lib\/ (a shared name another user can plant — create it O_EXCL|O_NOFOLLOW under \$TMPDIR, or allowlist it here with its reason): /"; FAIL=1; a4=1; }
[ -z "$dead" ] || { echo "$dead" | sed "s/^/FAIL: $NAME: axis 4a: allowlist entry matches no live \/tmp literal (remove it): /"; FAIL=1; a4=1; }
# (b) the capture open
b=$(_capopen_bad "$ROOT/lib/regression.cyr")
[ -z "$b" ] || { echo "$b" | sed "s/^/FAIL: $NAME: axis 4b: /"; FAIL=1; a4=1; }
[ "$a4" = 0 ] && echo "  ok: axis 4: no lib/ string literal names a /tmp path outside the 2 allowlisted sites ($nf files, $nl literals); the capture open is O_CREAT|O_EXCL|O_NOFOLLOW 0600, unlinks the name at once and is the only builder of a capture name; each verb reads its capture back from the fd, never by name (detectors self-tested)"

# ── axis 5: the PE CLI reads no drive-relative rooted path (CYRIUS-2026-0048) ──
cat > "$W/pe.awk" <<'AWK'
# "<fn>\t<literal>" for each rooted POSIX system-path literal in code the PE build compiles
function excl(   i) { for (i = 1; i <= sp; i++) if (ex[i]) return 1; return 0 }
/^[ \t]*fn [A-Za-z_0-9]+[ \t]*\(/ { f = $0; sub(/^[ \t]*fn[ \t]+/, "", f); sub(/[ \t]*\(.*/, "", f) }
/^[ \t]*#ifndef[ \t]/ { sp++; nm[sp] = $2; ng[sp] = 1; ex[sp] = ($2 == "CYRIUS_TARGET_WIN"); next }
/^[ \t]*#ifdef[ \t]/  { sp++; nm[sp] = $2; ng[sp] = 0; ex[sp] = ($2 ~ /^CYRIUS_TARGET_(LINUX|MACOS|AGNOS|CX)$/); next }
/^[ \t]*#else/        { if (sp > 0) ex[sp] = (nm[sp] == "CYRIUS_TARGET_WIN" && ng[sp] == 0); next }
/^[ \t]*#endif/       { if (sp > 0) sp--; next }
excl() { next }
{
    line = $0; n = length(line); i = 1; ins = 0; cur = ""
    while (i <= n) {
        c = substr(line, i, 1)
        if (ins) {
            if (c == "\\") { cur = cur substr(line, i, 2); i += 2; continue }
            if (c == "\"") { if (cur ~ /^\/(proc|etc|sys|dev|root|tmp|usr|var|home)(\/|$)/) print f "\t" cur; ins = 0; cur = ""; i++; continue }
            cur = cur c; i++; continue
        }
        if (c == "#") break
        if (c == "'") { if (substr(line, i + 1, 1) == "\\") { i += 4 } else { i += 3 }; continue }
        if (c == "\"") { ins = 1; cur = "" }
        i++
    }
}
AWK
cat > "$W/fx/pe.cyr" <<'PEFX'
fn _a(): i64 {
    var x = file_open("/proc/self/environ", 0, 0);
}
fn _b(): i64 {
    #ifndef CYRIUS_TARGET_WIN
    var y = "/etc/hosts";
    #endif
    #ifdef CYRIUS_TARGET_WIN
    var z = 0;
    #else
    var w = "/etc/passwd";
    #endif
    #ifdef CYRIUS_TARGET_LINUX
    var t = "/tmp";
    #endif
    # "/proc/x" in a comment
    var v = "/procfoo"; var u = "/lib"; var q = '"';
    var r = "/root";
}
PEFX
a5=0
[ "$(awk -f "$W/pe.awk" "$W/fx/pe.cyr" | tr '\t\n' '| ')" = '_a|/proc/self/environ _b|/root ' ] \
  || { fail "axis 5a self-test: the detector saw '$(awk -f "$W/pe.awk" "$W/fx/pe.cyr" | tr '\t\n' '| ')' (want _a|/proc/self/environ _b|/root)"; a5=1; }
ALLOW5='cbt/deps.cyr|_dep_wt_run|/dev/null|a POSIX fork child: the PE arm spawns before the fork (cbt_fork_sites_have_pe_arm.sh)
cbt/deps.cyr|_dep_wt_run|/usr/bin/env|the execve target of that POSIX fork child (sys_execve is a -1 stub on PE)
cbt/deps.cyr|_git_run|/dev/null|a POSIX fork child: the PE arm spawns before the fork (cbt_fork_sites_have_pe_arm.sh)
cbt/deps.cyr|_git_run|/usr/bin/env|the execve target of that POSIX fork child (sys_execve is a -1 stub on PE)
cbt/deps.cyr|_process_named_deps|/usr/bin/env|the execve target of a POSIX fork child (sys_execve is a -1 stub on PE)'
: > "$W/pesites"; npe=0
for f in "$ROOT"/cbt/*.cyr; do
    [ -f "$f" ] || continue
    npe=$((npe + 1))
    awk -f "$W/pe.awk" "$f" | tr '\t' '|' | sed "s|^|${f#"$ROOT"/}\||" >> "$W/pesites"
done
printf '%s\n' "$ALLOW5" | cut -d'|' -f1-3 | LC_ALL=C sort -u > "$W/allow5"
pbad=$(LC_ALL=C sort -u "$W/pesites" | LC_ALL=C comm -23 - "$W/allow5")
pdead=$(LC_ALL=C sort -u "$W/pesites" | LC_ALL=C comm -13 - "$W/allow5")
[ "$npe" -ge 10 ] || { fail "axis 5a: scanned $npe cbt/ files (floor 10) — the scan read nothing"; a5=1; }
[ -z "$pbad" ] || { echo "$pbad" | sed "s/^/FAIL: $NAME: axis 5a: a rooted POSIX path the PE CLI compiles (drive-relative on Windows — put it under #ifndef CYRIUS_TARGET_WIN, or allowlist it with its reason): /"; FAIL=1; a5=1; }
[ -z "$pdead" ] || { echo "$pdead" | sed "s/^/FAIL: $NAME: axis 5a: allowlist entry matches no live site (remove it): /"; FAIL=1; a5=1; }
[ "$a5" = 0 ] && echo "  ok: axis 5a: no rooted POSIX path in cbt/ code the PE build compiles outside the $(printf '%s\n' "$ALLOW5" | grep -c .) allowlisted fork-child sites ($npe files; detector self-tested)"
if command -v wine > /dev/null 2>&1 && command -v winepath > /dev/null 2>&1; then
    # A PRIVATE prefix under $W (never ~/.wine), its HOME and cache with it; torn down on exit.
    WP="$W/wine"; WHM="$W/whome"; mkdir -p "$WHM" "$W/wrun"
    _wine_down() {
        [ -d "$WP" ] || return 0
        _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
        WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
        WINEPREFIX="$WP" wineserver -w > /dev/null 2>&1 || true
        rm -rf "$_ws" || true
    }
    trap '_wine_down; rm -rf "$W"' EXIT
    _wine() { ( cd "$W/wrun" && env WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' "$@" ); }
    a5b=0
    if ( cd "$ROOT" && "$CC" < src/main_win.cyr > "$W/cc_win" 2> /dev/null ) && chmod +x "$W/cc_win" \
       && ( cd "$ROOT" && "$W/cc_win" < cbt/cyrius.cyr > "$W/cyrius.exe" 2> "$W/pe.err" ) && [ -s "$W/cyrius.exe" ]; then
        rc=0; _wine env WINEDEBUG=+file timeout 300 wine "$W/cyrius.exe" --version > "$W/w5v.out" 2> "$W/w5v.trace" || rc=$?
        grep -q '^cyrius ' "$W/w5v.out" || { fail "axis 5b: cyrius.exe --version did not run under wine (rc=$rc): $(head -c 200 "$W/w5v.out" | tr -d '\r')"; a5b=1; }
        if grep -q 'proc.self.environ' "$W/w5v.trace"; then
            fail "axis 5b: cyrius.exe opened the drive-relative /proc/self/environ: $(grep -m1 'proc.self.environ' "$W/w5v.trace" | cut -c1-160)"; a5b=1
        fi
        WEXE=$(_wine winepath -w "$W/cyrius.exe" 2> /dev/null | tr -d '\r')
        printf '@echo off\r\nset USERPROFILE=\r\nset CYRIUS_HOME=\r\n%s --version\r\necho rc=%%errorlevel%%\r\n' "$WEXE" > "$W/wrun/nohome.bat"
        _wine env WINEDEBUG=+file timeout 300 wine cmd /c nohome.bat > "$W/w5h.out" 2> "$W/w5h.trace" || true
        if ! grep -q 'rc=1' "$W/w5h.out" || ! grep -q 'neither CYRIUS_HOME nor USERPROFILE is set' "$W/w5h.out" "$W/w5h.trace"; then
            fail "axis 5b: with USERPROFILE and CYRIUS_HOME unset cyrius.exe did not refuse by name: $(tr -d '\r' < "$W/w5h.out" | tail -2 | tr '\n' ' ')"; a5b=1
        fi
        if grep -q 'root.\.cyrius' "$W/w5h.trace"; then
            fail "axis 5b: with no home cyrius.exe probed the drive-relative \\root\\.cyrius: $(grep -m1 'root.\.cyrius' "$W/w5h.trace" | cut -c1-160)"; a5b=1
        fi
    else
        fail "axis 5b: the PE CLI does not cross-build: $(grep -m1 -E 'error' "$W/pe.err")"; a5b=1
    fi
    [ "$a5b" = 0 ] && echo "  ok: axis 5b (wine): cyrius.exe opens no /proc/self/environ, and with no home refuses by name instead of probing \\root\\.cyrius"
else
    echo "  SKIP: axis 5b — wine not found; the PE CLI's opens are checked where wine is installed (axis 5a still holds the source)"
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: $NAME"; exit 1; fi
echo "PASS $NAME (lib/regression.cyr's capture verbs create their file O_EXCL|O_NOFOLLOW 0600 under \$TMPDIR: a planted link or file is skipped, every name taken is refused by name, and no lib/ literal names a /tmp path outside the allowlist; the PE CLI reads no drive-relative rooted path)"
